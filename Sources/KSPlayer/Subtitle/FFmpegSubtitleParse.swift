//
//  FFmpegSubtitleParse.swift
//  KSPlayer
//
//  Forward 1.3.17 — NEW stateless FFmpeg subtitle parser (P4 M1 structure). 0 fields (§8.3). Bodies → P4 M2.
//
import AVFoundation
import CoreMedia
import Libavcodec
import Libavformat
import Foundation

// FFmpegSubtitleParse @0x1039f16c4 — stateless parser (:KSParseProtocol, §8.5).
// canParse = `{ true }` (witness 0x10002c740 = `return 1`); parsePart INHERITS the KSParseProtocol
// extension default `{ [] }` (witness 0x10002d9dc, shared with AssImageParse) — FFmpeg subtitles are
// decoded via the FFmpeg subtitle pipeline, not the Scanner text-parse path.
public class FFmpegSubtitleParse: KSParseProtocol {

    public func canParse(scanner: Scanner) -> Bool { true }
    // ⚑ s105: the binary declares this member ON THIS CLASS — the trie carries
    // `KSPlayer.FFmpegSubtitleParse.parsePart(scanner: __C.NSScanner) -> [KSPlayer.SubtitlePart]`
    // directly, not as a protocol-witness thunk, so it is an explicit declaration rather than the
    // inheritance the file header assumed. Body 0x10002d9dc is three instructions:
    //   adrp x0, 0x104112000 / ldr x0, [x0, #0xd00] / ret
    // and that GOT slot binds libswiftCore `__swiftEmptyArrayStorage`, i.e. it returns [].
    // ⚑[tool=bind_oracle ref=_swiftEmptyArrayStorage:0x104112d00 result=libswiftCore]
    // Identical to the KSParseProtocol extension default, which is why ICF folded them onto one
    // address — the fold is the CONSEQUENCE of them matching, not evidence of inheritance.
    public func parsePart(scanner _: Scanner) -> [SubtitlePart] { [] }

    public func parse(url: URL, scanner _: Scanner) throws -> KSSubtitleProtocol {
        try FFmpegSubtitle(url: url)
    }

    public init() {}
}

// FFmpegSubtitle @0x1039f1718 — Forward 1.3.17 `actor` ($defaultActor field record; type_kind_gate).
// §8.3 fields (7, reflection-authoritative: formatContext/decode/subtitleStreamIndex/preTime/startTime/
// endTime/parts) + §8.5 conforms KSSubtitleProtocol directly.
// ⚑ L7: `@preconcurrency` = the Swift 6 spelling that lets the actor-ISOLATED `search(with:)` witness (Forward
//   hop 0x101a9f9d0 → swift_task_switch(0x101a9fa34, x1=self)) satisfy the nonisolated async requirement with
//   non-Sendable KSSubtitleQuery/[SubtitlePart]; codegen-neutral (mock asm identical to the plain Swift 5 conformance).
actor FFmpegSubtitle: @preconcurrency KSSubtitleProtocol {
    // ⚑ L7: `nonisolated(unsafe)` = Swift 6 spelling for the Forward deinit's reads of these non-Sendable lets
    //   (Ffd 0x101a9f8e0 reads +0x70/+0x78 from the nonisolated deinit); codegen-neutral (mock asm identical).
    private nonisolated(unsafe) let formatContext: FormatContext          // +0x70
    private nonisolated(unsafe) let decode: SubtitleDecode                // +0x78
    private let subtitleStreamIndex: Int32            // +0x80  ⚑[tool=field_surface ref=FFmpegSubtitle.subtitleStreamIndex:idx3 result=let Int32]
    private var preTime: Double = 0                   // +0x88
    private var startTime: Double = 0                 // +0x90
    private var endTime: Double = 0                   // +0x98
    private var parts: [SubtitlePart] = []            // +0xa0

    // ⚑ L7: unnamed local body 0x101a9f0cc (file KSPlayer/FFmpegSubtitleParse.swift, between the metadata accessor
    //   0x101a9f0ac and init 0x101a9f27c; x20 = self, no args). Its one call is search's finish path @0x101a9ff84,
    //   right after `self.parts = parts`. Name recon-chosen (stripped). first non-empty part → startTime (+0x90) =
    //   part.start @0x101a9f20c; parts.last → endTime (+0x98) = end.isInfinite ? start : end (fcsel @0x101a9f240);
    //   none → `stp xzr,xzr,[x20,#0x90]` @0x101a9f1e0. `final`: Forward's FFmpegSubtitle vtable has no slot for it
    //   (slot 12 = init; vtable_surface add_final, pass 20260928T165255547393Z).
    private final func updateTimeRange() {
        if let first = parts.first(where: { !$0.isEmpty }) {
            startTime = first.start
            if let last = parts.last {
                endTime = last.end.isInfinite ? last.start : last.end
            }
        } else {
            startTime = 0
            endTime = 0
        }
    }

    // Binary init `(url: URL) throws` (FUN_101a9f27c, 0x101a9f27c-0x101a9f8df) — MIGRATED from the
    //   base stub `init(formatContext:decode:)`. A throwing ACTOR init: open the subtitle source via the shared
    //   `openFormatContext`, wrap it in a `FormatContext`, find the `.subtitle` asset track, enable it, build a
    //   `SubtitleDecode`, then pump packets to accumulate `parts`. Throws "can not judge stream" if there is no
    //   subtitle track. ⚑ signature P28 (param name `url` irreducible; actor init = _swift_defaultActor_*).
    // ⚑ `time: Double` REFUTED: the prologue @0x101a9f29c-a4 takes only x21(swifterror→x23), x20(self→x19) and
    //   x0(URL ptr→x28) — no d0. The only d0 in the whole 1636-byte body is a LOCAL `ldr d0,[x19,#0x8]` +
    //   `str d0,[x26,#0xa8]` @0x101a9f58c (the CMTime store for `track.startTime`), i.e. defined before use.
    //   Same Ghidra `double param_1` phantom as openFormatContext's. Blast radius zero: `FFmpegSubtitle(`
    //   has no call site in Sources/.
    //
    // FAITHFUL PARTIAL. The SPINE (open → FormatContext → stream-select → decode setup → throw) is reconstructed +
    //   disasm-confirmed. The intricate DECODE-ACCUMULATE LOOP is flagged `// UNRESOLVED` below and NOT fabricated
    //   (a plausible-but-wrong decode call looks done and mis-loads every subtitle).
    init(url: URL) throws {
        // preTime/startTime/endTime = 0 + parts = [] are the declared defaults (binary prologue @0x101a9f33c-348).

        // ── open: a fresh interrupt context + the shared throwing open/probe. ──
        // ⚑ IOInterruptContext(nil) (block = nil): binary allocs a 0x30 obj (FUN_101a3a694 metadata) then  ⚑[tool=resolve_fun_pins ref=FUN_101a3a694:0x101a3a694 result=RESOLVES_UNIQUELY] = type metadata accessor for KSPlayer.IOInterruptContext
        //   FUN_101a391bc(0,0) = IOInterruptContext.init (@0x101a9f384-3a0).
        let interrupt = IOInterruptContext(nil)
        // ⚑ the binary BUILDS the Either here: it allocas from the Either<URL, AbstractAVIOContext> metadata
        //   (`__swift_instantiateConcreteTypeFromMangledName(0x1044e4778, 0x103566d40)` @0x101a9f304), copies the
        //   `url` parameter into the payload with URL's vwt[0x10] @0x101a9f36c, then stamps case 0 with
        //   `swift_storeEnumTagMultiPayload(buf, EitherMeta, w2=0)` @0x101a9f37c. `mov x2,#0`/`mov x3,#0`/`mov x4,#0`
        //   @0x101a9f3b0-b8 = options nil, inFormat nil.
        let (formatCtx, fileSize, ioContext) = try openFormatContext(io: .left(url), interrupt: interrupt,
                                                                     options: nil, inFormat: nil)
        // ⚑ FormatContext.init (FUN_101a350bc @0x101a9f43c) wraps the opened AVFormatContext.  ⚑[tool=resolve_fun_pins ref=FUN_101a350bc:0x101a350bc result=RESOLVES_UNIQUELY] = KSPlayer.FormatContext.init(formatCtx: Swift.UnsafeMutablePointer<__C.AVFormatContext>, fileSize: Swift.Int64, interrupt: KSPlayer.IOInterruptContext, ioContext: KSPlayer.AbstractAVIOContext?, fontsDir: Foundation.URL?) -> KSPlayer.FormatContext
        //   `duration`(d0) is GONE from the signature entirely: it was never a parameter, only Ghidra's
        //   phantom `double param_1`, and the trie / the prologue @0x101a350e8-fc / every call site all
        //   agree on five parameters.
        //   RESOLVED: the `fileSize: 0` / `ioContext: nil` PLACEHOLDERS are gone. openFormatContext returns three
        //   values (`mov x0,x26 / x1,x24 / x2,x27` @0x101a39f28-30) and this call site FORWARDS all three straight
        //   into FormatContext.init: `mov x24,x0`/`mov x23,x1`/`mov x27,x2` @0x101a9f3e4-f8, then
        //   `mov x0,x24`(formatCtx) / `mov x1,x23`(fileSize) / `mov x2,x20`(interrupt) / `mov x3,x27`(ioContext)
        //   @0x101a9f424-30 immediately before `bl 0x101a350bc` @0x101a9f43c.
        //   ⚑ `fontsDir`(x4 = x25 @0x101a9f434) is a pointer to a `URL?` stack buffer whose initialization was not
        //     located; `nil` is UNCHANGED and remains unproven.
        //   ⚑[tool=llvm-objdump ref=openFormatContext:0x101a392a0 result=3-TUPLE-RETURN]
        let formatContext = FormatContext(formatCtx: formatCtx, fileSize: fileSize,
                                          interrupt: interrupt, ioContext: ioContext, fontsDir: nil)

        // ── stream-select: the FIRST `.subtitle` asset track. Disasm @0x101a9f47c-0x101a9f4f4: iterate
        //   `formatContext.assetTracks`, compare `track.mediaType`(track+0x78, String-backed AVMediaType) ==
        //   `AVMediaType.subtitle` (GOT `*(*0x104108738)`, the Audio@730/Subtitle@738/Video@740 family). ──
        guard let track = formatContext.assetTracks.first(where: { $0.mediaType == .subtitle }) else {
            // throw @0x101a9f800-844: code@0 = 0 (.unknown), message = "can not judge stream" (str-len 0x14=20,
            //   chars @0x103d3a070; the decompile's pointer 0x103d3a050 is P72-scrambled). _swift_allocError(0x1041d5790).
            throw KSPlayerError(code: 0, description: "can not judge stream")
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
        //   refinement committed @0f6c92f). alloc 0x88 (FUN_101a6bfe0 metadata) + FUN_101a6914c (@0x101a9f5b8-5dc).  ⚑[tool=resolve_fun_pins ref=FUN_101a6bfe0:0x101a6bfe0 result=RESOLVES_UNIQUELY] = type metadata accessor for KSPlayer.SubtitleDecode  ⚑[tool=resolve_fun_pins ref=FUN_101a6914c:0x101a6914c result=RESOLVES_UNIQUELY] = KSPlayer.SubtitleDecode.init(assetTrack: KSPlayer.FFmpegAssetTrack, options: KSPlayer.KSOptions?) -> KSPlayer.SubtitleDecode
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
        //   timestamp/timebase elements feed the completion-handler wrapper FUN_101a69de8, not the accumulate). ──  ⚑[tool=resolve_fun_pins ref=FUN_101a69de8:0x101a69de8 result=RESOLVES_UNIQUELY] = KSPlayer.SubtitleDecode.decodeFrame(from: Swift.UnsafeMutablePointer<__C.AVPacket>, completionHandler: (Swift.Result<KSPlayer.MEFrame, Swift.Error>) -> ()) -> ()
        var parts = [SubtitlePart]() // LOCAL accumulator: x28 = empty array @0x101a9f644, grown @0x101a9f75c, released at exit; no store to self+0xa0
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

    // ⚑ L7: explicit deinit (Forward Ffd 0x101a9f8e0): `bl 0x101a3302c` FormatContext.close(), then the inlined
    //   SubtitleDecode.shutdown() (avsubtitle_free 0x10294d330 / avcodec_free_context 0x102d53ac8 under
    //   beginAccess), then swift_defaultActor_destroy; FfD 0x101a9f9b8 = deinit + swift_defaultActor_deallocate.
    deinit {
        formatContext.close()
        decode.shutdown()
    }

    // ⚑ L7: actor-ISOLATED (Forward entry 0x101a9f9d0 stores query/self then swift_task_switch(0x101a9fa34,
    //   x1=self)); internal param name `query` (read @0x101a9fadc). Body = continuation 0x101a9fa34.
    public final func search(with query: KSSubtitleQuery) async -> [SubtitlePart] {
        // decode+0x10 non-nil → retain + swift_task_switch(0x101aa015c, x1=renderer): delegate to the ASS renderer.
        if let assImageRenderer = decode.assImageRenderer {
            return await assImageRenderer.search(with: query)
        }
        let time = query.time
        // every non-renderer exit stores preTime (+0x88) = time (@0x101a9fb6c/0x101a9fbe0/0x101a9fd58/0x101aa00f8).
        defer { preTime = time }
        // in range: `fcmp startTime,time; b.hi` / `fcmp time,endTime; b.ls` → filter self.parts.
        if startTime <= time, time <= endTime {
            return self.parts.filter { $0 == time }
        }
        if abs(preTime - time) >= 10 {
            // fabd + 10.0 @0x101a9fb00; avformat_seek_file(ctx, -1, Int64.min, Int64(time * 1e6), Int64.max, 1) @0x101a9fbd8
            if avformat_seek_file(formatContext.formatCtx, -1, Int64.min, Int64(time * 1_000_000), Int64.max, AVSEEK_FLAG_BACKWARD) != 0 {
                return []
            }
        } else if time < startTime {
            return []
        }
        var parts = [SubtitlePart]()
        var packet = av_packet_alloc()
        if let packet {
            while true {
                // read-fail / foreign-stream exit (0x101a9fb58): unref + return [].
                guard av_read_frame(formatContext.formatCtx, packet) == 0, packet.pointee.stream_index == subtitleStreamIndex else {
                    av_packet_unref(packet)
                    return []
                }
                if let (decoded, _, _) = decode.decodeFrame(from: packet) {
                    parts.append(contentsOf: decoded)
                }
                av_packet_unref(packet)
                if parts.contains(where: { !$0.isEmpty }), let last = parts.last, !last.end.isInfinite || last.isEmpty {
                    break
                }
            }
        }
        av_packet_free(&packet)
        // L7 lane 16: Forward calls 0x101a18c4c here (@0x101a9ff60: `ldp d0,d1,[query,#0x8]`, x20 = &parts) —
        //   the mutating [SubtitlePart].adjust(size:) in EmbedDataSouce.swift — before the +0xa0 store.
        parts.adjust(size: query.size)
        self.parts = parts
        updateTimeRange()
        return self.parts.filter { $0 == time }
    }
}
