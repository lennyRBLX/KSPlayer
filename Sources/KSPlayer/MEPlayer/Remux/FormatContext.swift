//
//  FormatContext.swift
//  KSPlayer
//
//  Binary-faithful reconstruction (Forward 1.3.17). NEW Forward-only type.
//  Remux-foundation; consumed by the Phase-2 Remuxer + Phase-3 DV path.
//  Reconstructed from binary: outer init `0x101a35050` (_swift_allocObject + delegate)
//  → inner init `0x101a350bc` (the real body; derivation-heavy + side effects).
//
//  FAITHFUL PARTIAL: the 6 param-fed fields are assigned exactly as the binary stores them.
//  RECONSTRUCTED (session 28) the 4 cleanly-separable symbolic-FFmpeg scalar derivations — `formatName`,
//  `startTime`, `maxFrameDuration` (idiom of the proven MEPlayerItem:233-239), and `byteSeek`
//  (@0x101a35494-0x101a354e8, disasm-verified). RECONSTRUCTED (session 29) the per-stream `assetTracks`
//  loop (calls the EXISTING `FFmpegAssetTrack(stream:)` = FUN_101a211ec — the 625-instr builder is already
//  done, NOT re-derived here; the loop appends non-nil tracks and font-extracts on nil+attachment), the
//  embedded-font-extraction side-effect (Data + createDirectory + write + CTFontManagerRegisterFontsForURL
//  + av_freep, on ATTACHMENT streams whose codec_id ∈ {none, TTF, OTF}), the per-track `startTime`
//  container-alignment, `bitrate` (+0x38, fileSize*8/duration with a track-bitRate-sum fallback), and the
//  dominant-path `duration` = durationSeconds. Symbolic FFmpeg field access = faithful by construction
//  under the non-stock ABI.
//
//  STILL UNRESOLVED (flagged `// UNRESOLVED`, NOT fabricated) — the `ioContext as? PlayList` arms: the
//  `seekByBytes`=true branch + the `formatCtx->duration = duration*AV_TIME_BASE` side-effect + the per-track
//  `languageCode`/`name` override from the playlist's per-entry metadata. `PlayList` (mangled
//  `$s8KSPlayer8PlayListP`, cast-target descriptor resolved via l2 walk_mangled @0x103c2fbba) is a
//  Forward-only protocol NOT yet reconstructed in-tree (only `parsePlaylist()` helpers exist); the same
//  cast drives MEPlayerItem's FUN_101a512b4. Reconstructing these arms now would fabricate PlayList's
//  witness interface — a flagged deferral is success (a plausible-but-wrong body looks done and crashes).
//
//  FFmpeg provenance (P32) — every av* symbol named in this file is ffmpeg_name_oracle result=CONFIRMED:
//    ⚑[tool=ffmpeg_name_oracle ref=av_freep:0x103253ed0 result=CONFIRMED]     (FUN_103253ed0, avutil/mem.o — free+null idiom)
//    ⚑[tool=ffmpeg_name_oracle ref=av_dict_get:0x10323a9d8 result=CONFIRMED]  (FUN_10323a9d8, avutil/dict.o — inside toDictionary)
//

import AVFoundation
import CoreMedia
import CoreText
import FFmpegKit
import Foundation
import Libavformat
import Libavutil

// Binary: vtable 1 (num_immediate 14 − num_fields 13 = 1). Slot 0 = init `0x101a35050`.
// let/var is NOT binary-determinable for this class (vtable has NO accessor slots).
// Param-fed fields declared `let`; derived/defaulted fields declared `var`.
// let/var inferred — no vtable accessors.
public final class FormatContext {
    // Stored fields in reflection (offset) order. Types transcribed from the class's
    // own __swift5_fieldmd field-records (authoritative), NOT inferred from the
    // decompile's undefined8/long/char* widths (those are decompiler noise).
    public let interrupt: IOInterruptContext                  // +0x10  (init param 4)
    public let formatCtx: UnsafeMutablePointer<AVFormatContext> // +0x18 (init param 2)
    public let ioContext: AbstractAVIOContext?                // +0x20  (init param 5)
    public let duration: Double                               // +0x28  (init param 1; see DIVERGENCE note in init)
    public let fileSize: Int64                                // +0x30  (init param 3) — external/unmapped stdlib symref; NOT Int
    public var bitrate: Int64                                 // +0x38  DERIVED — external/unmapped; NOT Int
    public var assetTracks: [FFmpegAssetTrack]                // +0x40  default [] (binary builds from a stream loop)
    public var formatName: String                            // +0x48  DERIVED (from formatCtx->iformat->name)
    public var seekByBytes: Bool                             // +0x58  DERIVED (conditionally 0/1 across branches; default false)
    public var byteSeek: Bool                               // +0x59  DERIVED (from format flags + name compare)
    public var startTime: CMTime                            // +0x5c  DERIVED (from formatCtx->start_time / kCMTimeZero)
    public var maxFrameDuration: Int                        // +0x78  DERIVED (3600 or 10 from format flags); field-record sugar `Si` — NOT Double
    public var fontsDir: URL?                               // (sym)  (init param 6) → triggers font registration side-effect

    // Inner init `0x101a350bc`. 6 params (register order → field):
    //   p1 duration(double), p2 formatCtx(ptr), p3 fileSize(ulong/Int64),
    //   p4 interrupt, p5 ioContext(ptr), p6 fontsDir.
    // Param→field stores observed in the binary at unaff_x20 + off:
    //   +0x10=p4(interrupt), +0x18=p2(formatCtx), +0x20=p5(ioContext),
    //   fontsDir=p6, +0x30=p3(fileSize), +0x28=p1(duration), +0x58=0(seekByBytes).
    public init(duration: Double,
                formatCtx: UnsafeMutablePointer<AVFormatContext>,
                fileSize: Int64,
                interrupt: IOInterruptContext,
                ioContext: AbstractAVIOContext?,
                fontsDir: URL?) {
        // ── Scalar derivations into LOCALS first. Swift init-order forbids reading `self.startTime`
        //    (or calling any `self` member) until EVERY stored property is assigned, and the per-track
        //    startTime alignment in the loop needs the container startTime — so it reads the LOCAL. ──

        // +0x5c = CMTime from formatCtx.start_time (== AV_NOPTS_VALUE(Int64.min) ? .zero :
        //   CMTime(value:, timescale: AV_TIME_BASE)). FUN_101a350bc prologue @unaff_x20+0x5c; MEPlayerItem:238-239 idiom.
        let startTimeValue: CMTime = formatCtx.pointee.start_time != Int64.min
            ? CMTime(value: formatCtx.pointee.start_time, timescale: AV_TIME_BASE)
            : .zero
        // +0x28 duration: the binary re-derives durationSeconds = max(formatCtx.duration,0)/AV_TIME_BASE (INTEGER
        //   divide → Double) and stores THAT on every non-PlayList path — the dominant path (plain file playback:
        //   ioContext is nil / not a PlayList). // UNRESOLVED: the `ioContext as? PlayList` seg≥2 branch keeps the
        //   `duration` PARAM instead (and mutates formatCtx.duration) — deferred with the PlayList protocol.
        let durationSecondsInt = max(formatCtx.pointee.duration, 0) / Int64(AV_TIME_BASE)
        let durationValue = Double(durationSecondsInt)
        // +0x48 = String(cString: iformat.name). FUN_101a350bc reads *(*(formatCtx+8)); MEPlayerItem:236 idiom.
        let formatNameValue = String(cString: formatCtx.pointee.iformat.pointee.name)
        // +0x59 = (flags & AVFMT_NO_BYTE_SEEK == 0) && (flags & (AVFMT_TS_DISCONT|AVFMT_NOTIMESTAMPS) != 0) &&
        //   formatName != "ogg". FUN_101a350bc @0x101a35494-0x101a354e8 disasm-verified (and #0x280; "ogg" 0x67676f).
        let iformatFlags = formatCtx.pointee.iformat.pointee.flags
        let byteSeekValue = (iformatFlags & AVFMT_NO_BYTE_SEEK == 0)
            && (iformatFlags & (AVFMT_TS_DISCONT | AVFMT_NOTIMESTAMPS) != 0)
            && (formatNameValue != "ogg")
        // +0x78 = (flags & AVFMT_TS_DISCONT) ? 10 : 3600. FUN_101a350bc reads (flags & 0x200); MEPlayerItem:233-234 (here Int, `Si`).
        let maxFrameDurationValue = iformatFlags & AVFMT_TS_DISCONT == AVFMT_TS_DISCONT ? 10 : 3600

        // ── +0x40 assetTracks: per-stream loop over formatCtx.streams[0..<nb_streams] (MEPlayerItem:283-284 idiom).
        //    Builds an FFmpegAssetTrack per stream via the EXISTING FFmpegAssetTrack(stream:) (= FUN_101a211ec, the
        //    625-instr builder, already reconstructed — NOT re-derived here); appends non-nil tracks; on a nil track
        //    that is an ATTACHMENT stream, extracts the embedded font. ──
        var assetTracks: [FFmpegAssetTrack] = []
        for i in 0 ..< Int(formatCtx.pointee.nb_streams) {
            guard let stream = formatCtx.pointee.streams[i] else { continue }
            if let track = FFmpegAssetTrack(stream: stream) {
                // GROUNDED @LAB_101a358b8 head (no PlayList): subtitle tracks — and any track whose start is within
                //   10s of the container — snap to the container startTime.
                if track.mediaType == .subtitle || abs((track.startTime - startTimeValue).seconds) < 10 {
                    track.startTime = startTimeValue
                }
                // UNRESOLVED: the `ioContext as? PlayList` per-entry languageCode/name override (LAB_101a358b8 tail —
                //   witness +0x08/+0x10/+0x20 + an [Int32:String] lookup keyed by the stream id) — deferred with the
                //   PlayList protocol. ⚑[tool=name_type_at_addr ref=PlayList:0x103c2fbba result=protocol-not-in-tree]
                assetTracks.append(track)
            } else if stream.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_ATTACHMENT {
                // Embedded-font attachment: codec_id ∈ {NONE, 0x18000 TTF, 0x18006 OTF} — raw compare = the binary's
                //   `iVar3 == 0 || == 0x18000 || == 0x18006`. Extract extradata → Data, write under fontsDir, register
                //   with CoreText, then av_freep the extradata. FUN_101a350bc @0x101a35540-0x101a35840 font block.
                let codecpar = stream.pointee.codecpar.pointee
                let codecID = codecpar.codec_id
                if codecID == AV_CODEC_ID_NONE || codecID.rawValue == 0x18000 || codecID.rawValue == 0x18006,
                   let fontsDir, let extradata = codecpar.extradata {
                    // FUN_100036e98 = Data(bytes:count:) from codecpar.extradata (+0x10) / extradata_size (+0x18).
                    let data = Data(bytes: extradata, count: Int(codecpar.extradata_size))
                    let metadata = toDictionary(stream.pointee.metadata)   // FUN_101a07bd8 = av_dict_get loop → [String:String]
                    try? FileManager.default.createDirectory(at: fontsDir, withIntermediateDirectories: true)
                    // ⚑ filename = "<stream.index>" + (metadata["filename"] ?? ".ttf"): index@stream+8, the "filename"
                    //   key + ".ttf" literal are GROUNDED; the exact concatenation is the clearest reading of the two
                    //   String.append + appendPathComponent (SSA register aliasing leaves the composition slightly fuzzy).
                    let fontName = "\(stream.pointee.index)" + (metadata["filename"] ?? ".ttf")
                    let fontURL = fontsDir.appendingPathComponent(fontName)
                    try? data.write(to: fontURL)
                    // scope .process (=1), error nil (=0) — same call as KSParseProtocol:99 (P42-disasm-confirmed).
                    CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
                    // FUN_103253ed0 = av_freep(&extradata) idiom (free + null), then extradata_size = 0 (codecpar+0x18).
                    av_freep(&stream.pointee.codecpar.pointee.extradata)
                    stream.pointee.codecpar.pointee.extradata_size = 0
                }
            }
        }

        // +0x38 bitrate: duration>0 && fileSize≥1 → max((fileSize*8)/Int(duration), 1) (the binary's `< 2 → 1` clamp).
        //   Else the fallback keys off the FIRST .video track: if that track's bitRate>0 → Σ all tracks' bitRate;
        //   else (or no .video track) → 1. The selector M = .video, recovered by disasm @0x101a35fc4 (loads
        //   GOT[0x104108740] — the AVMediaType slot the decompiler dropped, adjacent to Audio@0x104108730 /
        //   Subtitle@0x104108738) + elimination (FFmpegAssetTrack.mediaType ∈ {audio,video,subtitle}). It is a FIRST-
        //   match on mediaType, NOT contains-any-positive (@0x101a35fd0-0x101a36114). FUN_101a350bc @0x101a35e00-0x101a361cc.
        let bitrateValue: Int64
        if durationValue > 0, fileSize >= 1 {
            let bps = (fileSize * 8) / durationSecondsInt
            bitrateValue = bps < 2 ? 1 : bps
        } else {
            bitrateValue = (assetTracks.first { $0.mediaType == .video }?.bitRate ?? 0) > 0
                ? assetTracks.reduce(0) { $0 + $1.bitRate }
                : 1
        }

        // ── Store every stored property (param-fed offsets confirmed in the inner-decompile prologue) ──
        self.interrupt = interrupt   // +0x10 = param_4
        self.formatCtx = formatCtx   // +0x18 = param_2
        self.ioContext = ioContext   // +0x20 = param_5
        self.fileSize = fileSize     // +0x30 = param_3
        self.fontsDir = fontsDir     // (sym field) from param_6
        self.duration = durationValue
        // +0x58 seekByBytes: false on every reconstructed (non-PlayList) path. // UNRESOLVED: the
        //   `ioContext as? PlayList` seg≥2 branch computes true (+ mutates formatCtx.duration) — deferred.
        self.seekByBytes = false
        self.assetTracks = assetTracks
        self.formatName = formatNameValue
        self.byteSeek = byteSeekValue
        self.startTime = startTimeValue
        self.maxFrameDuration = maxFrameDurationValue
        self.bitrate = bitrateValue
    }
}
