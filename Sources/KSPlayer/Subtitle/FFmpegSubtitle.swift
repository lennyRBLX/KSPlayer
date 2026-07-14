import AVFoundation
import CoreMedia
import Foundation
import Libavcodec
import Libavformat

// FFmpegSubtitle @0x1039f1718 — Forward 1.3.17 `actor` ($defaultActor field record; type_kind_gate).
// §8.3 fields (7, reflection-authoritative: formatContext/decode/subtitleStreamIndex/preTime/startTime/
// endTime/parts) + §8.5 conforms KSSubtitleProtocol directly.
actor FFmpegSubtitle: KSSubtitleProtocol {
    private let formatContext: FormatContext          // +0x70
    private let decode: SubtitleDecode                // +0x78
    private var subtitleStreamIndex: Int32 = 0        // +0x80  ⚑ Int32 inferred (§8.6)
    private var preTime: Double = 0                   // +0x88
    private var startTime: Double = 0                 // +0x90
    private var endTime: Double = 0                   // +0x98
    private var parts: [SubtitlePart] = []            // +0xa0

    // Binary init `(time: Double, url: URL) throws` (FUN_101a9f27c, 0x101a9f27c-0x101a9f8df) — MIGRATED from the
    //   base stub `init(formatContext:decode:)`. A throwing ACTOR init: open the subtitle source via the shared
    //   `openFormatContext`, wrap it in a `FormatContext`, find the `.subtitle` asset track, enable it, build a
    //   `SubtitleDecode`, then pump packets to accumulate `parts`. Throws "can not judge stream" if there is no
    //   subtitle track. ⚑ signature P28 (param names `time`/`url` irreducible; actor init = _swift_defaultActor_*).
    //
    // FAITHFUL PARTIAL. The SPINE (open → FormatContext → stream-select → decode setup → throw) is reconstructed +
    //   disasm-confirmed. The intricate DECODE-ACCUMULATE LOOP is flagged `// UNRESOLVED` below and NOT fabricated
    //   (a plausible-but-wrong decode call looks done and mis-loads every subtitle).
    init(time: Double, url: URL) throws {
        // preTime/startTime/endTime = 0 + parts = [] are the declared defaults (binary prologue @0x101a9f33c-348).

        // ── open: a fresh interrupt context + the shared throwing open/probe. ──
        // ⚑ IOInterruptContext(nil) (block = nil): binary allocs a 0x30 obj (FUN_101a3a694 metadata) then
        //   FUN_101a391bc(0,0) = IOInterruptContext.init (@0x101a9f384-3a0).
        let interrupt = IOInterruptContext(nil)
        let formatCtx = try openFormatContext(time: time, url: url, interrupt: interrupt, options: nil, cacheKey: nil)
        // ⚑ FormatContext.init (FUN_101a350bc @0x101a9f43c) wraps the opened AVFormatContext. Two args are
        //   DISASM-confirmed live: `formatCtx`(x0) = the openFormatContext return; `interrupt`(x2) = the IOInterruptContext.
        //   The other four are DEAD arguments the binary does not encode — 0/0/nil/nil are flagged residues:
        //   `duration`(d0) is PROVEN dead (the callee never reads d0 — its first bl @0x101a35128 clobbers it — and
        //   re-derives the duration field @+0x68 from formatCtx); `fileSize`(x1)/`ioContext`(x3)/`fontsDir`(x4) are
        //   dead-arg-elided (openFormatContext returns a single UnsafeMutablePointer, so their post-call registers are
        //   leftovers, not returns). The decompile's 0/nil for these is a stale-variable artifact — it renders
        //   `interrupt` as 0 too, yet disasm proves interrupt = x20 — so they were resolved by disasm, not decompile.
        let formatContext = FormatContext(duration: 0, formatCtx: formatCtx, fileSize: 0,
                                          interrupt: interrupt, ioContext: nil, fontsDir: nil)

        // ── stream-select: the FIRST `.subtitle` asset track. Disasm @0x101a9f47c-0x101a9f4f4: iterate
        //   `formatContext.assetTracks`, compare `track.mediaType`(track+0x78, String-backed AVMediaType) ==
        //   `AVMediaType.subtitle` (GOT `*(*0x104108738)`, the Audio@730/Subtitle@738/Video@740 family). ──
        guard let track = formatContext.assetTracks.first(where: { $0.mediaType == .subtitle }) else {
            // throw @0x101a9f800-844: code@0 = 0 (.unknown), message = "can not judge stream" (str-len 0x14=20,
            //   chars @0x103d3a070; the decompile's pointer 0x103d3a050 is P72-scrambled). _swift_allocError(0x1041d5790).
            throw KSPlayerError(description: "can not judge stream")
        }

        // ── on match (LAB_101a9f554): enable the stream, reset its startTime, record the index, build the decode. ──
        // ⚑ binary does `track.stream?.pointee.discard = AVDISCARD_DEFAULT` (@0x101a9f560 `str wzr,[stream,#0x44]`;
        //   AVStream+0x44 = `discard`, offsetof-proven). `stream` is `private` to FFmpegAssetTrack → the accessible
        //   faithful form is the `isEnabled` setter, whose `mediaType == .subtitle → AVDISCARD_DEFAULT` branch
        //   constant-folds to the bare discard=0 the disasm shows.
        track.isEnabled = true
        track.startTime = .zero                       // track+0xa0 CMTime = kCMTimeZero (@0x101a9f564-594)
        subtitleStreamIndex = track.trackID           // self+0x80 = track.trackID (track+0x10, Int32) @0x101a9f5ac-5b4
        // ⚑ SubtitleDecode.init(assetTrack:options:) with options = nil (@0x101a9f5d8 `mov x1,#0x0`; the KSOptions?
        //   refinement committed @0f6c92f). alloc 0x88 (FUN_101a6bfe0 metadata) + FUN_101a6914c (@0x101a9f5b8-5dc).
        let decode = SubtitleDecode(assetTrack: track, options: nil)
        self.formatContext = formatContext            // self+0x70
        self.decode = decode                          // self+0x78

        // ⚑ image-subtitle early-return: `if track.isImageSubtitle { return }` (@0x101a9f5e8 `ldrb w8,[track,#0xe8];
        //   tbz w8,#0` → skip the text-decode loop for image subtitles; they render via the ASS-image pipeline).
        if track.isImageSubtitle {
            return
        }

        // ── decode-accumulate loop (@0x101a9f618-0x101a9f7cc): pump every packet from the subtitle stream through the
        //   synchronous SubtitleDecode.decodeFrame(from:) (FUN_101a69f54, resolved this session) and accumulate its parts.
        //   The sync decode returns ([SubtitlePart], timestamp, timebase)? — this sidecar caller uses only .parts (the
        //   timestamp/timebase elements feed the completion-handler wrapper FUN_101a69de8, not the accumulate). ──
        var pkt = av_packet_alloc() // ⚑[tool=ffmpeg_name_oracle ref=av_packet_alloc:0x102d61878 result=CONFIRMED] (avcodec/packet.o)
        guard let packet = pkt else {
            av_packet_free(&pkt) // ⚑[tool=ffmpeg_name_oracle ref=av_packet_free:0x102d618b8 result=CONFIRMED] alloc-nil path ONLY (@0x101a9f688)
            // ⚑ UNRESOLVED (audit-caught, LOW) — on this OOM-only path the binary ALSO calls FUN_101a18c4c(0.0, 0.0)
            //   (@0x101a9f698, a two-Double callee) between the packet-free and return. Its semantics are unresolved and
            //   the path is unreachable unless the packet allocation returns nil (OOM), so its effect is DEFERRED
            //   (a callee resolution), NOT fabricated. Everything reachable in this init is reconstructed + FAITHFUL.
            return
        }
        // ⚑[tool=ffmpeg_name_oracle ref=av_read_frame:0x1030e6e78 result=CONFIRMED] (avformat/demux.o)
        while av_read_frame(formatContext.formatCtx, packet) == 0 {
            // ⚑ BREAK on the first non-subtitle-stream packet — binary @0x101a9f704 `b.ne LAB_101a9f650`
            //   (exit, NOT skip-and-continue). For a single-stream subtitle sidecar every packet matches.
            guard packet.pointee.stream_index == subtitleStreamIndex else { break }
            if let (decoded, _, _) = decode.decodeFrame(from: packet) {
                parts += decoded
            }
            av_packet_unref(packet) // ⚑[tool=ffmpeg_name_oracle ref=av_packet_unref:0x102d61970 result=CONFIRMED] loop-body (@0x101a9f6e4)
        }
        // ⚑ exit teardown = av_packet_unref, NOT av_packet_free: the binary frees the AVPacket STRUCT only on the
        //   alloc-nil path (@0x101a9f688); every non-nil exit (read-fail / stream-index break) UNREFs at LAB_101a9f650
        //   (@0x101a9f654), leaking the struct. Faithful to the binary's teardown (audit-caught free-vs-unref).
        av_packet_unref(packet) // ⚑[tool=ffmpeg_name_oracle ref=av_packet_unref:0x102d61970 result=CONFIRMED] exit (@0x101a9f654)
    }

    // ⚑ UNRESOLVED → P4 M2 (Batch 4): subtitle(currentTime:) async + the real parts search. Signature migrated to
    //   search(with: KSSubtitleQuery) async (session 21, P55 ripple); body still a deferred stub.
    nonisolated public func search(with _: KSSubtitleQuery) async -> [SubtitlePart] { [] }
}
