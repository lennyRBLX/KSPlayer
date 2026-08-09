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
//  ⚠️ CORRECTED — THE `ioContext as? PlayList` ARMS ARE NOT IN THIS FUNCTION. This block used to
//  record them as "STILL UNRESOLVED" here, and the s84 verdict carried the same attribution. Both
//  are wrong about the location. Measured over the whole extent of the inner init
//  (0x101a350bc-0x101a362c0, 1153 instructions):
//    · zero `swift_dynamicCast` and zero `swift_conformsToProtocol` calls;
//    · zero `adrp` to page 0x1039ed — so the `PlayList` protocol descriptor at 0x1039edc98 is
//      never referenced.
//  A conditional protocol cast cannot happen without one of those. The arms — the
//  `seekByBytes`=true branch, the `formatCtx->duration = duration*AV_TIME_BASE` side-effect and the
//  per-track `languageCode`/`name` override from the playlist metadata — live somewhere else; the
//  original note's own aside points at MEPlayerItem's FUN_101a512b4, which is the place to look.
//  ⚑[tool=export_trie_oracle ref=$s8KSPlayer8PlayListMp:0x1039edc98 result=unreferenced-in-this-extent]
//
//  Two further things that block quoting the old note: `PlayList` IS reconstructed in-tree now
//  (`public protocol PlayList` with all four requirements, PlayerDefines.swift:642), so "NOT yet
//  reconstructed" is stale as well.
//
//  FFmpeg provenance (P32) — every av* symbol named in this file is ffmpeg_name_oracle result=CONFIRMED:
//    ⚑[tool=ffmpeg_name_oracle ref=av_freep:0x103253ed0 result=CONFIRMED]     (FUN_103253ed0, avutil/mem.o — free+null idiom)
//    ⚑[tool=ffmpeg_name_oracle ref=av_dict_get:0x10323a9d8 result=CONFIRMED]  (FUN_10323a9d8, avutil/dict.o — inside toDictionary)
//

import AVFoundation
import CoreMedia
import CoreText
import CryptoKit
import FFmpegKit
import Foundation
import Libavformat
import Libavutil
import QuartzCore

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
    public let duration: Double                               // +0x28  DERIVED (not an init param — see init)
    public let fileSize: Int64                                // +0x30  (init param 3) — external/unmapped stdlib symref; NOT Int
    public let bitrate: Int64                                 // +0x38  DERIVED — external/unmapped; NOT Int
    public let assetTracks: [FFmpegAssetTrack]                // +0x40  default [] (binary builds from a stream loop)
    public let formatName: String                            // +0x48  DERIVED (from formatCtx->iformat->name)
    public let seekByBytes: Bool                             // +0x58  DERIVED (conditionally 0/1 across branches; default false)
    public let byteSeek: Bool                               // +0x59  DERIVED (from format flags + name compare)
    public let startTime: CMTime                            // +0x5c  DERIVED (from formatCtx->start_time / kCMTimeZero)
    public let maxFrameDuration: Int                        // +0x78  DERIVED (3600 or 10 from format flags); field-record sugar `Si` — NOT Double
    public let fontsDir: URL?                               // (sym)  (init param 6) → triggers font registration side-effect

    // Inner init `0x101a350bc`. FIVE params (register order → field):
    //   x0 formatCtx(ptr), x1 fileSize(Int64), x2 interrupt, x3 ioContext(ptr), x4 fontsDir.
    // Param→field stores observed in the binary at unaff_x20 + off:
    //   +0x10=interrupt, +0x18=formatCtx, +0x20=ioContext, fontsDir, +0x30=fileSize, +0x58=0(seekByBytes).
    //
    // There is NO `duration` parameter, and the one this declaration used to carry was a
    // decompiler artifact: Ghidra's default __swiftcall prototype prepends a phantom
    // `double param_1`, which is visible verbatim in the prefetch caches. Three independent
    // reads settle it, and the correct signature was ALREADY sitting in the
    // `⚑[tool=resolve_fun_pins …]` markers below while the declaration above contradicted them:
    //   · the trie (export_trie_oracle --addr 0x101a350bc --owner FormatContext) → OWNER_MATCH on
    //     exactly these five labels, no `duration:`;
    //   · the prologue @0x101a350e8-fc consumes only x20(self)+x0..x4 and never reads d0 —
    //     the d8..d11 stores at 0x101a350bc-c0 are callee-SAVES, not argument reads;
    //   · every call site (0x101a34ff8 / 0x101a3a294 / 0x101a3a65c / 0x101a9f43c) passes x0..x4
    //     with no d0 write in the preceding instructions.
    // The parameter was never read by this body either: `duration` is assigned below from the
    // locally derived `durationValue`, not from any argument.
    public init(formatCtx: UnsafeMutablePointer<AVFormatContext>,
                fileSize: Int64,
                interrupt: IOInterruptContext,
                ioContext: AbstractAVIOContext?,
                fontsDir: URL?) {
        // ── Scalar derivations into LOCALS first. Swift init-order forbids reading `self.startTime`
        //    (or calling any `self` member) until EVERY stored property is assigned, and the per-track
        //    startTime alignment in the loop needs the container startTime — so it reads the LOCAL. ──

        // +0x5c = CMTime from formatCtx.start_time (== AV_NOPTS_VALUE(Int64.min) ? .zero :
        //   CMTime(value:, timescale: AV_TIME_BASE)). FUN_101a350bc prologue @unaff_x20+0x5c; MEPlayerItem:238-239 idiom.  ⚑[tool=resolve_fun_pins ref=FUN_101a350bc:0x101a350bc result=RESOLVES_UNIQUELY] = KSPlayer.FormatContext.init(formatCtx: Swift.UnsafeMutablePointer<__C.AVFormatContext>, fileSize: Swift.Int64, interrupt: KSPlayer.IOInterruptContext, ioContext: KSPlayer.AbstractAVIOContext?, fontsDir: Foundation.URL?) -> KSPlayer.FormatContext
        let startTimeValue: CMTime = formatCtx.pointee.start_time != Int64.min
            ? CMTime(value: formatCtx.pointee.start_time, timescale: AV_TIME_BASE)
            : .zero
        // +0x28 duration: the binary re-derives durationSeconds = max(formatCtx.duration,0)/AV_TIME_BASE (INTEGER
        //   divide → Double) and stores THAT on every non-PlayList path — the dominant path (plain file playback:
        //   ioContext is nil / not a PlayList).
        // ⚠️ A `// UNRESOLVED: the ioContext as? PlayList seg>=2 branch` marker stood here and is REMOVED:
        //   the cast is not in this function. See the corrected header block — 1153 instructions with zero
        //   swift_dynamicCast, zero swift_conformsToProtocol and zero adrp to page 0x1039ed.
        let durationSecondsInt = max(formatCtx.pointee.duration, 0) / Int64(AV_TIME_BASE)
        let durationValue = Double(durationSecondsInt)
        // +0x48 = String(cString: iformat.name). FUN_101a350bc reads *(*(formatCtx+8)); MEPlayerItem:236 idiom.  ⚑[tool=resolve_fun_pins ref=FUN_101a350bc:0x101a350bc result=RESOLVES_UNIQUELY] = KSPlayer.FormatContext.init(formatCtx: Swift.UnsafeMutablePointer<__C.AVFormatContext>, fileSize: Swift.Int64, interrupt: KSPlayer.IOInterruptContext, ioContext: KSPlayer.AbstractAVIOContext?, fontsDir: Foundation.URL?) -> KSPlayer.FormatContext
        let formatNameValue = String(cString: formatCtx.pointee.iformat.pointee.name)
        // +0x59 = (flags & AVFMT_NO_BYTE_SEEK == 0) && (flags & (AVFMT_TS_DISCONT|AVFMT_NOTIMESTAMPS) != 0) &&
        //   formatName != "ogg". FUN_101a350bc @0x101a35494-0x101a354e8 disasm-verified (and #0x280; "ogg" 0x67676f).  ⚑[tool=resolve_fun_pins ref=FUN_101a350bc:0x101a350bc result=RESOLVES_UNIQUELY] = KSPlayer.FormatContext.init(formatCtx: Swift.UnsafeMutablePointer<__C.AVFormatContext>, fileSize: Swift.Int64, interrupt: KSPlayer.IOInterruptContext, ioContext: KSPlayer.AbstractAVIOContext?, fontsDir: Foundation.URL?) -> KSPlayer.FormatContext
        let iformatFlags = formatCtx.pointee.iformat.pointee.flags
        let byteSeekValue = (iformatFlags & AVFMT_NO_BYTE_SEEK == 0)
            && (iformatFlags & (AVFMT_TS_DISCONT | AVFMT_NOTIMESTAMPS) != 0)
            && (formatNameValue != "ogg")
        // +0x78 = (flags & AVFMT_TS_DISCONT) ? 10 : 3600. FUN_101a350bc reads (flags & 0x200); MEPlayerItem:233-234 (here Int, `Si`).  ⚑[tool=resolve_fun_pins ref=FUN_101a350bc:0x101a350bc result=RESOLVES_UNIQUELY] = KSPlayer.FormatContext.init(formatCtx: Swift.UnsafeMutablePointer<__C.AVFormatContext>, fileSize: Swift.Int64, interrupt: KSPlayer.IOInterruptContext, ioContext: KSPlayer.AbstractAVIOContext?, fontsDir: Foundation.URL?) -> KSPlayer.FormatContext
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
                // ⚠️ A `// UNRESOLVED: the ioContext as? PlayList per-entry override` marker stood here, citing
                //   the LAB_101a358b8 tail. REMOVED: 0x101a358b8 is inside this extent and is a plain
                //   `mov x26,x0 / ldr x0,[x0,#0x78] / bl 0x10345745c` string-bridge sequence — no cast, no
                //   protocol descriptor. The marker was describing code that is not here.
                assetTracks.append(track)
            } else if stream.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_ATTACHMENT {
                // Embedded-font attachment: codec_id ∈ {NONE, 0x18000 TTF, 0x18006 OTF} — raw compare = the binary's
                //   `iVar3 == 0 || == 0x18000 || == 0x18006`. Extract extradata → Data, write under fontsDir, register
                //   with CoreText, then av_freep the extradata. FUN_101a350bc @0x101a35540-0x101a35840 font block.  ⚑[tool=resolve_fun_pins ref=FUN_101a350bc:0x101a350bc result=RESOLVES_UNIQUELY] = KSPlayer.FormatContext.init(formatCtx: Swift.UnsafeMutablePointer<__C.AVFormatContext>, fileSize: Swift.Int64, interrupt: KSPlayer.IOInterruptContext, ioContext: KSPlayer.AbstractAVIOContext?, fontsDir: Foundation.URL?) -> KSPlayer.FormatContext  ⚑[tool=ffmpeg_name_oracle ref=av_freep:0x103253ed0 result=CONFIRMED]
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
        //   match on mediaType, NOT contains-any-positive (@0x101a35fd0-0x101a36114). FUN_101a350bc @0x101a35e00-0x101a361cc.  ⚑[tool=resolve_fun_pins ref=FUN_101a350bc:0x101a350bc result=RESOLVES_UNIQUELY] = KSPlayer.FormatContext.init(formatCtx: Swift.UnsafeMutablePointer<__C.AVFormatContext>, fileSize: Swift.Int64, interrupt: KSPlayer.IOInterruptContext, ioContext: KSPlayer.AbstractAVIOContext?, fontsDir: Foundation.URL?) -> KSPlayer.FormatContext
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
        // +0x58 seekByBytes: false on every path in this function.
        // ⚠️ A `// UNRESOLVED: the ioContext as? PlayList seg>=2 branch` marker stood here and is REMOVED for
        //   the same measured reason as the other two.
        self.seekByBytes = false
        self.assetTracks = assetTracks
        self.formatName = formatNameValue
        self.byteSeek = byteSeekValue
        self.startTime = startTimeValue
        self.maxFrameDuration = maxFrameDurationValue
        self.bitrate = bitrateValue
    }

    // ⚑ chapters — computed getter, body = FUN_101a362d0. Self reads self+0x18 (= formatCtx) via RAW offsets  ⚑[tool=resolve_fun_pins ref=FUN_101a362d0:0x101a362d0 result=RESOLVES_UNIQUELY] = KSPlayer.FormatContext.chapters() -> [KSPlayer.Chapter]
    //   (Ghidra anchors MEPlayerItem's fields symbolically; these are raw ⟹ owner is FormatContext, not
    //   MEPlayerItem). Forward moved the base MEPlayerItem.openThread chapters loop onto the wrapper.
    //   Timebase.cmtime(for:) = CMTime(value: start*num, timescale: den) matches the decompile's inlined
    //   CMTime math (Model.swift:197); title via toDictionary(chapter.metadata)["title"] ?? "".
    var chapters: [Chapter] {
        var result: [Chapter] = []
        for i in 0 ..< formatCtx.pointee.nb_chapters {
            if let chapter = formatCtx.pointee.chapters[Int(i)]?.pointee {
                let timeBase = Timebase(chapter.time_base)
                let start = timeBase.cmtime(for: chapter.start).seconds
                let end = timeBase.cmtime(for: chapter.end).seconds
                let metadata = toDictionary(chapter.metadata)
                let title = metadata["title"] ?? ""
                result.append(Chapter(start: start, end: end, title: title))
            }
        }
        return result
    }

    // seekable `0x101a34e24` (12 instr, extent from LC_FUNCTION_STARTS 0x101a34e24..0x101a34e54) — a COMPUTED
    // property with no stored field (s68: recovered as MEMBER_MISSING; the class had no `seekable` member at all).
    // Trie: `$s8KSPlayer13FormatContextC8seekableSbvg` = KSPlayer.FormatContext.seekable.getter : Swift.Bool.
    // Body read instruction-by-instruction — three exits, in this order:
    //   0x101a34e24 `ldr x8,[x20,#0x18]`  self.formatCtx        (+0x18, as this class's own field map says)
    //   0x101a34e28 `ldr x8,[x8,#0x20]`   formatCtx->pb          (AVFormatContext.pb — its 5th pointer-width
    //                                                             field, per libavformat/avformat.h)
    //   0x101a34e2c `cbz x8, 0x101a34e3c` pb == nil            ⇒ take the `mov w0,#1` exit ⇒ TRUE
    //   0x101a34e30 `ldr w8,[x8,#0x90]`   pb->seekable          (AVIOContext.seekable is `int` — hence the
    //                                                             32-bit w-register load, not x)
    //   0x101a34e34 `cmp w8,#0` / `b.le`  seekable > 0         ⇒ TRUE (`mov w0,#1` @0x101a34e3c)
    //   0x101a34e44 `ldr d0,[x20,#0x28]`  self.duration         (+0x28, Double)
    //   0x101a34e48 `fcmp d0,#0.0` / `cset w0,ne`              ⇒ duration != 0
    // i.e. a nil pb reports seekable, matching FFmpeg's "no custom IO ⇒ the demuxer decides" convention.
    var seekable: Bool {
        guard let pb = formatCtx.pointee.pb else { return true }
        return pb.pointee.seekable > 0 || duration != 0
    }

    // pause `0x101a362c0` / play `0x101a362c8` — two 2-instruction tail-call thunks, extents exact from
    // LC_FUNCTION_STARTS (8 bytes each). Trie: `$s8KSPlayer13FormatContextC5pauseyyF` =
    // KSPlayer.FormatContext.pause() -> () and `$s8KSPlayer13FormatContextC4playyyF` = ...play() -> ().
    // Both bodies are literally `ldr x0,[x20,#0x18]` (self.formatCtx, +0x18 per this class's field map)
    // then an unconditional `b` into FFmpeg. The Int32 result is dropped — these return ().
    //
    // Naming the two branch targets was the whole difficulty, and it is why s68 could not land these.
    // The targets share fingerprint [11,44] with n=48 indexed symbols, so `ffmpeg_name_oracle
    // --candidate` (fingerprint-only at the time) "CONFIRMED" BOTH av_read_pause and av_read_play at
    // BOTH addresses, and even the unrelated avio_wb64. That defect is fixed in s69: --candidate now
    // also compares the linked body instruction-for-instruction against the candidate's own code in
    // the FFmpegKit archive, and `--resolve` collapses the whole 48-way class to one survivor.
    //
    // Ground truth, derived WITHOUT the oracle from llvm-objdump + FFmpeg n8.1.1 (FFmpegKit/.Script):
    // n8.1.1 has NO read_play/read_pause fields — both functions call the single TWO-ARG
    // FFInputFormat.read_set_state(s, state) at iformat+0x78, then fall back to avio_pause(s->pb, flag):
    //     av_read_play  -> read_set_state(s, FF_INFMT_STATE_PLAY  = 0), avio_pause(pb, 0)
    //     av_read_pause -> read_set_state(s, FF_INFMT_STATE_PAUSE = 1), avio_pause(pb, 1)
    // so the discriminating operand is `mov w1,#0` vs `mov w1,#1`, and it appears TWICE in each body.
    // 0x1030ecfa8 sets w1=1 (⇒ av_read_pause); 0x1030ecf7c sets w1=0 (⇒ av_read_play). Both share the
    // avio_pause callee 0x1030c49f0 and both return `mov w0,#-0x4e` = AVERROR(ENOSYS).
    // ⚑[tool=ffmpeg_name_oracle ref=av_read_pause:0x1030ecfa8 result=CONFIRMED]
    // ⚑[tool=ffmpeg_name_oracle ref=av_read_play:0x1030ecf7c result=CONFIRMED]
    func pause() {
        av_read_pause(formatCtx)
    }

    func play() {
        av_read_play(formatCtx)
    }

    // time(index:timestamp:) `0x101a32e28` (109 instr, extent exact from LC_FUNCTION_STARTS
    // 0x101a32e28..0x101a32fdc) — MEMBER_MISSING: in the binary, absent from source. Trie:
    // `KSPlayer.FormatContext.time(index: Swift.Int32, timestamp: Swift.Int64) -> Swift.Double?`.
    // FFmpegAssetTrack.swift:46 already pinned this address as the cross-module `timebase` reader.
    // Verbatim decompile, structure-for-structure:
    //   `if (param_2 != -0x8000000000000000)`    guard timestamp != Int64.min  (AV_NOPTS_VALUE)
    //   loads self+0x40                          self.assetTracks (this class's field map)
    //   inline loop w/ retain/release            a `for` over the array, NOT `first(where:)` —
    //                                            the array is indexed directly, no generic call
    //   `*(int *)(uVar6 + 0x10) == param_1`      track.trackID == index
    //   `CMTime.init(value:timescale:)` with
    //     value = timestamp * *(int*)(t+0xc0)    timebase.num
    //     timescale = *(uint*)(t+0xc4)           timebase.den   ⇒ exactly Timebase.cmtime(for:)
    //   `CMTime.-_infix(…, *(t+0xa0…0xb0))`      minus track.startTime (24-byte CMTime at +0xa0)
    //   `.seconds` then `dVar3=0; if (0<dVar10) dVar3=dVar10`   ⇒ max(0, …)
    //   returns on the FIRST match (goto with the some-flag 0); falls out of the loop ⇒ nil.
    // Offsets are consistent with the field-record order (dump_field_bindings): trackID is field 1,
    // hence the post-header +0x10; startTime is 14 and occupies the 24 bytes +0xa0..+0xb8; codecpar
    // (15, a pointer) takes +0xb8; timebase (16) lands on +0xc0, its two Int32s at +0xc0/+0xc4 —
    // and Timebase declares `num` before `den`, matching value*num / timescale=den.
    func time(index: Int32, timestamp: Int64) -> Double? {
        guard timestamp != Int64.min else { return nil }
        for track in assetTracks where track.trackID == index {
            return max(0, (track.timebase.cmtime(for: timestamp) - track.startTime).seconds)
        }
        return nil
    }

    // subtitleAssetTrackMap(options:) `0x101a36488` (242 instr, extent exact from LC_FUNCTION_STARTS
    // 0x101a36488..0x101a36850) — MEMBER_MISSING: in the binary, absent from source. Trie:
    // `KSPlayer.FormatContext.subtitleAssetTrackMap(options: KSPlayer.KSOptions) -> [Swift.Int32 : KSPlayer.FFmpegAssetTrack]`.
    // Read instruction-for-instruction (llvm-objdump; every stub resolved through the chained-fixup
    // bind table, every symbolic type ref decoded through its nominal-type descriptor):
    //   0x101a364ac  ldr x26,[x20,#0x40]              self.assetTracks (empty ⇒ 0x101a36814 returns [:])
    //   0x101a364c8  adrp/ldr [0x104108738]; ldr x28,[x8]   __got 0x104108738 binds AVFoundation
    //                                                 `_AVMediaTypeSubtitle` — the NSString constant
    //   0x101a364e4  ldr x25,[0x104112d08]            libswiftCore `__swiftEmptyDictionarySingleton` = `[:]`
    //   0x101a365c4  ldr x0,[x27,#0x78] then String._unconditionallyBridgeFromObjectiveC on BOTH sides,
    //                then _stringCompareWithSmolCheck(_:_:expecting:) with w4=0 (.equal), with a
    //                bitwise-identical fast path at 0x101a365e8  ⇒ `where track.mediaType == .subtitle`
    //                (mediaType is the 8-byte AVMediaType at +0x78 — session-36 designated-init offset map)
    //   0x101a36650  ldr w28,[x27,#0x10]              track.trackID (Int32) — the dictionary KEY
    //   0x101a36668-740  native Dictionary insert: find-bucket 0x1019c10ec, grow 0x1019f9a74,
    //                copy-to-unique 0x1019f7310, key `str w28,[x25+0x30]`, value `str x27,[x25+0x38]`,
    //                count bump `[x25+0x10]`; the mismatch trap is libswiftCore
    //                KEY_TYPE_OF_DICTIONARY_VIOLATES_HASHABLE_REQUIREMENTS  ⇒ `result[track.trackID] = track`
    //   0x101a36744  ldrb w8,[x27,#0xe8]; cmp #1; b.ne 0x101a364f8   ⇒ `if track.isImageSubtitle`
    //                (+0xe8 isImageSubtitle, +0x100 subtitle — same session-36 offset map)
    // The two branches build DIFFERENT generic classes. Each metadata accessor is handed a mangled-name
    // ref of the form `\x02<indirect ctx desc> y \x02<arg> G`; resolving the indirect slots through the
    // chained-fixup rebase targets and reading each descriptor's name field gives:
    //   image-subtitle (fallthrough 0x101a36758): nameRef 0x10356aa38 → 0x1039efb30 `AsyncPlayerItemTrack`
    //     × 0x1039f0030 `SubtitleFrame`; swift_allocObject size 0xa8/align 7; frameCapacity w1=8. Built
    //     ONCE and SHARED: [sp+0x18] is nil-seeded at 0x101a364c4, `cbnz x0` at 0x101a36760 skips the
    //     whole construction on later image tracks, and it is released once at loop exit 0x101a367e0.
    //     Order is init → decode() → `track.subtitle = …` (0x101a367b4/67bc/67c8).
    //   text-subtitle (0x101a364f8): nameRef 0x10356ac50 → 0x1039ef97c `SyncPlayerItemTrack` ×
    //     `SubtitleFrame`; frameCapacity w1=0x80=128; per-track. Order is init → `track.subtitle = …`
    //     → decode() (0x101a3652c/6538/6548).
    // Both tails call the SAME member: the text path dispatches `blr [metadata+0x190]`, which is
    // vtable slot (0x190-0xd0)/8 = 24 = SyncPlayerItemTrack.decode() @0x101a5ba20; the image path calls
    // 0x101a36850 directly (AsyncPlayerItemTrack is `final`, so the override devirtualises) and that
    // body opens with the identical `strb w8,[x20,#0x78]; strh w8,[x20,#0x28]` pair before doing the
    // BlockOperation/operationQueue work of the `decode()` override.
    // The 4th init argument is now declared (see MEPlayerItemTrack.swift): this body emits w3=1 on the text
    // path (0x101a36510) and w3=0 on the image path (0x101a367a8), both read from the call sites.
    func subtitleAssetTrackMap(options: KSOptions) -> [Int32: FFmpegAssetTrack] {
        var result = [Int32: FFmpegAssetTrack]()
        var imageSubtitleTrack: AsyncPlayerItemTrack<SubtitleFrame>?
        for track in assetTracks where track.mediaType == .subtitle {
            result[track.trackID] = track
            if track.isImageSubtitle {
                if imageSubtitleTrack == nil {
                    let subtitle = AsyncPlayerItemTrack<SubtitleFrame>(mediaType: .subtitle, frameCapacity: 8, options: options, expanding: false)
                    subtitle.decode()
                    imageSubtitleTrack = subtitle
                }
                track.subtitle = imageSubtitleTrack
            } else {
                let subtitle = SyncPlayerItemTrack<SubtitleFrame>(mediaType: .subtitle, frameCapacity: 128, options: options, expanding: true)
                track.subtitle = subtitle
                subtitle.decode()
            }
        }
        return result
    }

    // close (FUN_101a3302c) — FormatContext teardown. Reconstructed FAITHFUL (every callee named/confirmed,  ⚑[tool=resolve_fun_pins ref=FUN_101a3302c:0x101a3302c result=RESOLVES_UNIQUELY] = KSPlayer.FormatContext.close() -> ()
    //   no deep pins): (1) raise the interrupt flag to cancel any in-flight IO; (2) if fonts were registered,
    //   unregister each embedded font (the init's CTFontManagerRegisterFontsForURL mirror, .process scope) and
    //   delete the temp fontsDir — both file ops `try?` (the binary __convertNSErrorToError + willThrow +
    //   errorRelease is a swallowed throw); (3) if a custom ioContext is installed, close it (AbstractAVIOContext
    //   vtable +0xa0) and hand-free its AVIOContext (pb) — buffer via av_freep, struct via avio_context_free,
    //   which FFmpeg leaves to the caller under AVFMT_FLAG_CUSTOM_IO; (4) close the format context.
    // ⚑[tool=disassemble ref=FUN_101a3302c:0x101a3302c result=interrupt.flag=1 → fontsDir cleanup → (ioContext close + pb free) → format-context teardown]  ⚑[tool=resolve_fun_pins ref=FUN_101a3302c:0x101a3302c result=RESOLVES_UNIQUELY] = KSPlayer.FormatContext.close() -> ()
    // ⚑[tool=read_memory ref=AbstractAVIOContext.close:0x10000e52c result=vtable +0xa0=close() (metadata 0x1044e69b0+0xa0 word=0x10000e52c, coalesced w/ seek@+0x90; +0xa8=urlContext 0x10002d9d4 anchors the slot)]
    // ⚑[tool=ffmpeg_name_oracle ref=av_freep:0x103253ed0 result=CONFIRMED]
    // ⚑[tool=ffmpeg_name_oracle ref=avio_context_free:0x1030c1358 result=CONFIRMED]
    // ⚑[tool=ffmpeg_name_oracle ref=avformat_close_input:0x1030e632c result=CONFIRMED]
    // ⚑[tool=decompile ref=FUN_101a39028:0x101a39028 result=avformat-close wrapper — nils formatCtx.interrupt_callback then avformat_close_input(0x1030e632c CONFIRMED); its callback-clear + verbose KSLog simplified to the close core, matching :290/:310]
    func close() {
        interrupt.flag = true
        if let fontsDir {
            if let fonts = try? FileManager.default.contentsOfDirectory(at: fontsDir, includingPropertiesForKeys: nil) {
                for fontURL in fonts {
                    CTFontManagerUnregisterFontsForURL(fontURL as CFURL, .process, nil)
                }
            }
            try? FileManager.default.removeItem(at: fontsDir)
        }
        if let ioContext {
            ioContext.close()
            // free the caller-owned custom AVIOContext (fields accessed symbolically per the non-stock ABI).
            if let pb = formatCtx.pointee.pb {
                if pb.pointee.buffer != nil {
                    av_freep(&pb.pointee.buffer)
                }
                var pbLocal: UnsafeMutablePointer<AVIOContext>? = pb
                avio_context_free(&pbLocal)
            }
        }
        var mutableCtx: UnsafeMutablePointer<AVFormatContext>? = formatCtx
        avformat_close_input(&mutableCtx)   // ⚑ core of wrapper FUN_101a39028 (=avformat_close_input, see header)
    }
}

// MARK: - openFormatContext (FUN_101a392a0) — the shared avformat open/probe pipeline
//
//  ⚑ P28 NAME + HOME. The binary function `0x101a392a0` is `__swiftcall` with NO class namespace — stripped,
//  takes no `self`/x20 (free/static, disasm-confirmed). Forward EXTRACTED the base KSPlayer
//  `MEPlayerItem.openThread()` (alloc_context → open_input → find_stream_info, base @MEPlayerItem.swift:164-219)
//  into this SHARED throwing routine — 9 callers (FFmpegSubtitle.init 0x101a9f27c, the thumbnailer 0x101a241f4,
//  the main open paths 0x101a336b4/33f0c/34e54/3a0b8/3a2e8/3a89c/4d3d0). Homed here because its returned
//  AVFormatContext is exactly what `FormatContext` wraps; free-func name `openFormatContext` = semantically
//  grounded. Both names ⚑ P28 (IRREDUCIBLE — free-func + param names are not in reflection).
//
//  Signature RE-DERIVED @0x101a392a0 (extent 3608 B / 902 instr, LC_FUNCTION_STARTS 0x101a392a0→0x101a3a0b8).
//  The prologue consumes EXACTLY x0..x4 + x21 (swifterror) and never takes d0; the sole `ret` @0x101a39f58 —
//  the ONLY `ret` in the body — is preceded by `mov x0,x26 / x1,x24 / x2,x27 / x21,x28` @0x101a39f28-34.
//  The old `time: Double` was Ghidra's phantom `double param_1`: the only d0 in the whole body is a LOCAL
//  `ldr d0,[x25,#0x30]` + `fcmp` @0x101a398fc, i.e. defined before use, never an incoming argument.
//  The old `url: URL?` was the projected `.left` payload, not the parameter.
//    x0    = INDIRECT ptr to Either<URL, AbstractAVIOContext>
//    x1    = IOInterruptContext  (field chain read @0x101a395cc-d0)
//    x2    = KSOptions?          (`cbz x22` @0x101a3956c; FFmpegSubtitle passes `mov x2,#0` @0x101a9f3b0)
//    x3:x4 = String?             (`cbz x4` @0x101a398bc; non-nil → String.utf8CString → av_find_input_format)
//  ⚑ P28 IRREDUCIBLE: this address exports NO symbol, so the four param LABELS and the tuple element labels
//    are NOT recoverable. `io`/`options`/`inFormat` are borrowed from the trie-named caller below;
//    `interrupt` is conventional. The returned tuple is left UNLABELED — ABI-identical, and label-free is
//    the faithful minimum.
//  ⚑[tool=export_trie_oracle ref=openFormatContext:0x101a392a0 result=NOT_IN_TRIE]
//  ⚑[tool=resolve_fun_pins ref=FUN_101a34e54:0x101a34e54 result=RESOLVES_UNIQUELY] = KSPlayer.FormatContext.__allocating_init(io: KSPlayer.Either<Foundation.URL, KSPlayer.AbstractAVIOContext>, options: KSPlayer.KSOptions?, inFormat: Swift.String?, interruptBlock: (@Sendable () -> Swift.Bool)?) throws -> KSPlayer.FormatContext
//  Interrupt-context type recovered from reflection:
//    ⚑[tool=read_memory ref=metadata:0x1044e9d20→desc:0x1039ef584→name:0x10356ab00 result="class IOInterruptContext"]
//
//  FFmpeg provenance (P32) — every av* symbol CONFIRMED via ffmpeg_name_oracle:
//    ⚑[tool=ffmpeg_name_oracle ref=avformat_alloc_context:0x1031b85bc result=CONFIRMED]    (avformat/options.o)
//    ⚑[tool=ffmpeg_name_oracle ref=avformat_open_input:0x1030e5dac result=CONFIRMED]       (avformat/demux.o)
//    ⚑[tool=ffmpeg_name_oracle ref=avformat_find_stream_info:0x1030e8520 result=CONFIRMED] (avformat/demux.o)
//    ⚑[tool=ffmpeg_name_oracle ref=avformat_close_input:0x1030e632c result=CONFIRMED]      (avformat/demux.o; the
//      binary calls it via wrapper FUN_101a39028, which also clears ctx+0xd8/+0xe0 + verbose-logs — ⚑ simplified to the close core)
//    ⚑[tool=ffmpeg_name_oracle ref=av_dict_free:0x10323b034 result=CONFIRMED]               (avutil/dict.o; FUN_10323b034, frees the options dict after open — session 32)
//    ⚑[tool=ffmpeg_name_oracle ref=avio_size:0x1030c1d6c result=CONFIRMED]                  (avformat/aviobuf.o; @0x101a39b6c — its
//      x0 is BOTH the duration_probesize input AND the RETURNED fileSize: `mov x24,x0` @0x101a39b70, `mov x1,x24` @0x101a39f2c)
//    ⚑[tool=ffmpeg_name_oracle ref=av_find_input_format:0x1030fdb5c result=CONFIRMED]       (avformat/format.o; @0x101a398d4 on
//      `inFormat`.utf8CString — it produces avformat_open_input's `fmt` ARG 3 (`mov x24,x0` @0x101a398d8, `mov x2,x24` @0x101a39a9c),
//      NOT a file size. This CORRECTS the s74 brief, which named 0x1030fdb5c as the fileSize producer.)
//
//  FAITHFUL PARTIAL. The SPINE (alloc → open → find, the 4 throws, the P42 timing side-effects, the fontsDir
//  block) is reconstructed. Session 32 RESOLVED 2 of the 4 deferred sub-systems (both DISASM-confirmed, not just
//  decompile): `options.formatContextOptions`→AVDictionary (av_dict_free CONFIRMED) and the `duration_probesize`
//  heuristic (avio_size CONFIRMED; also CORRECTED the ctx-field misname "probesize" → `duration_probesize`
//  @ctx+0x1d0, offsetof-proven). The remaining 2 each need their own unit and stay flagged `// UNRESOLVED`
//  (NOT fabricated — a plausible-but-wrong body looks done and crashes downstream): the interrupt-callback
//  install (needs the registry predicate FUN_101a34af4 + IOInterruptContext token-visibility) and the `url`
//  custom-AVIOContext arm (a Forward-modified `process(url:,cb,opaque)` + a second `ioContext`-param AVIO branch).
func openFormatContext(io: Either<URL, AbstractAVIOContext>,
                       interrupt: IOInterruptContext,
                       options: KSOptions?,
                       inFormat: String?) throws
    -> (UnsafeMutablePointer<AVFormatContext>, Int64, AbstractAVIOContext?)
{
    // ⚑ P42 (disasm @0x101a392a0): the decompiler LINEARIZES `options.prepareTime = time`, but the disasm
    //   stores `CACurrentMediaTime()` (bl 0x103459d54 → d8), guarded on `options != nil`. Same for openTime/
    //   findTime below — a decompile-only body would bake the wrong value (`time`).
    options?.prepareTime = CACurrentMediaTime()

    // avformat_alloc_context() → nil ⟹ throw #1. Binary: err.code@0 = 0 (.unknown), message =
    //   .formatCreate.description (disasm str-length 0x21=33 = "avformat_alloc_context return nil"; the
    //   decompiler's string POINTER is scrambled — the length is the reliable disambiguator).
    guard let formatCtx = avformat_alloc_context() else {
        throw KSPlayerError(description: KSPlayerErrorCode.formatCreate.description)
    }

    // ⚑ UNRESOLVED — interrupt-callback install. Disasm @0x101a395cc-0x101a395dc: `stp x8,x27,[x0,#0xd8]`
    //   installs `formatCtx.interrupt_callback = {callback: FUN_101a34dc0, opaque: x27}`, where the opaque
    //   x27 = *(*(interrupt+0x28)+0x18) = `interrupt.token.opaque` (IOInterrupt.swift: token @+0x28,
    //   IOInterruptToken.opaque @+0x18). The cb FUN_101a34dc0 = `{ IOInterruptRegistry.shared (swift_once
    //   &DAT_1044e9ab8) ; FUN_101a34af4(opaque) & 1 }` — a hoisted @convention(c) closure over the
    //   UN-reconstructed registry predicate FUN_101a34af4 (id→flag lookup). Base MEPlayerItem.openThread:171-185
    //   inlines this reading `self.state`. DEFERRED: faithful reconstruction needs (a) FUN_101a34af4, (b) the
    //   closure-hoisting shape, (c) cross-file access to `fileprivate token` — reconstructing now fabricates the
    //   IOInterruptContext↔AVIOInterruptCB bridge (installing a WRONG cb mis-drives open/find interruption). Own unit.
    _ = interrupt

    // ── io projection. Disasm @0x101a397dc `bl 0x10345cd3c` = swift_getEnumCaseMultiPayload(buffer, EitherMeta),
    //   `cmp w0,#1`. tag 1 = `.right`; anything else = `.left`. FFmpegSubtitle's caller stores tag 0 for a URL
    //   (`swift_storeEnumTagMultiPayload(..., w2=0)` @0x101a9f378), matching Either<Left, Right> in Utility.swift.
    //   The `.right` payload IS the third return value: `ldr x27,[x24]` @0x101a397e8 vs `mov x27,#0` @0x101a398a8,
    //   and x27 is never redefined before `mov x2,x27` @0x101a39f30. Its type is proven by the dynamic cast at
    //   0x101a3995c, whose srcType argument is `bl 0x1019e4db4` = type metadata accessor for AbstractAVIOContext. ──
    let url: URL?
    let ioContext: AbstractAVIOContext?
    switch io {
    case let .left(fileURL):
        url = fileURL
        ioContext = nil                 // ⚑ x27 = 0 @0x101a398a8
    case let .right(context):
        url = nil                       // ⚑ the url C-string is NULL on this arm (@0x101a39858-5c stores 0/0)
        ioContext = context             // ⚑ x27 = *(enum payload) @0x101a397e8
        // ⚑ UNRESOLVED (unchanged) — the `.right` AVIO install: `av_malloc(ctx.<Int32 @+0x14>)` @0x101a39800,
        //   `avio_alloc_context(buf, size, 0, ctx, 0x1019e2628, 0x1019e2684, 0x1019e26e0)` @0x101a39828, a
        //   a swift_once-guarded class-pointer store @0x101a3984c, then `formatCtx.pb = avio` @0x101a39864.
        //   (The store's target field is identified in the verdict, not here: naming it would assert an
        //   FFmpeg symbol this unit cannot provenance with ffmpeg_name_oracle, which fingerprints
        //   FUNCTIONS and can never CONFIRM a struct field.)
        //   ⚑[tool=ffmpeg_name_oracle ref=avio_alloc_context:0x1030c1250 result=CONFIRMED]
        //   ⚑[tool=ffmpeg_name_oracle ref=av_malloc:0x103253d30 result=CONFIRMED]
    }

    // ⚑ UNRESOLVED — the `url` custom-AVIOContext arm. Disasm @0x101a39720-0x101a39798: `x21 = options.vtable[0x5b0]`
    //   then `x21(indirect-ret, url, FUN_101a34dc0, opaque)` — NOT a plain "custom pb". It is a Forward-MODIFIED
    //   `process(url:,callback,opaque)`: the base `KSOptions.process(url:) -> AbstractAVIOContext?` (KSOptions:469)
    //   EXTENDED to take the interrupt cb + opaque (so custom IO can be interrupted); indirect-returns
    //   `AbstractAVIOContext?`, threaded via FUN_101a3b534, then `formatCtx.pointee.pb = pb.getContext()`
    //   (base MEPlayerItem.openThread:192-195). Entangled with a SECOND AVIO branch (the `ioContext`-param arm
    //   @0x101a397e8, FUN_1030c1250/FUN_1030fdb5c → `ctx[4]=ctx->pb`). Its own AVIO subsystem unit —
    //   reconstructing the modified `process` signature now would fabricate the KSOptions API.
    //
    // RESOLVED — `options.formatContextOptions` → AVDictionary. Disasm @0x101a39a40-0x101a39a74: FUN_101a322c0 =
    //   the `[String:Any].avOptions` builder (AVFFmpegExtension:447 — per-entry inserts), its x0 return =
    //   the AVDictionary (`mov x19,x0`; Ghidra dropped the capture). Guarded on options!=nil (`cbz x25,0x101a399e4`
    //   → avOptions=nil) ⟹ exactly `options?.…avOptions`. Freed on BOTH paths (av_dict_free before the result
    //   check @0x101a39ab4). Mirrors base MEPlayerItem.openThread:191-203 (`avOptions` → open → av_dict_free).
    //   ⚑[tool=ffmpeg_name_oracle ref=avformat_open_input:0x1030e5dac result=CONFIRMED] (avformat/demux.o; opened below with &avOptions as the options dict)
    var avOptions = options?.formatContextOptions.avOptions
    var mutableCtx: UnsafeMutablePointer<AVFormatContext>? = formatCtx
    // ⚑ `fmt` ARG 3 is NOT nil. Disasm @0x101a398bc: `cbz x4` (inFormat._object) ? x24 = 0 @0x101a399dc :
    //   `String.utf8CString` (stub 0x103457624) → `add x0,x0,#0x20` (ContiguousArray element base) →
    //   `bl 0x1030fdb5c` = av_find_input_format @0x101a398d4, `mov x24,x0` @0x101a398d8. x24 is then
    //   `mov x2,x24` @0x101a39a9c, immediately before the avformat_open_input call @0x101a39aa0.
    let inputFormat = inFormat.flatMap { av_find_input_format($0) }
    // RESOLVED (session 76): the binary's url C-string comes from
    //   `bl 0x1019f59c4` = (extension in KSPlayer):Foundation.URL.ffmpegString.getter @0x101a39888.
    //   That property is now reconstructed in Core/Utility.swift, so the `.path` stand-in is gone.
    //   ⚑[tool=export_trie_oracle ref=$s10Foundation3URLV8KSPlayerE12ffmpegStringSSvg:0x1019f59c4 result=RECONSTRUCTED]
    let urlString = url?.ffmpegString
    //   ⚑[tool=ffmpeg_name_oracle ref=avformat_open_input:0x1030e5dac result=CONFIRMED] (re-resolved s75:
    //     "unique instruction-level survivor of the 1-symbol fingerprint class"; call site @0x101a39aa0)
    let openResult = avformat_open_input(&mutableCtx, urlString, inputFormat, &avOptions)
    av_dict_free(&avOptions)   // ⚑ binary frees before the result check (@0x101a39ab4) — both success and failure paths
    guard openResult == 0 else {
        avformat_close_input(&mutableCtx)   // ⚑ core of wrapper FUN_101a39028 (=FUN_1030e632c) — see provenance header
        // throw #2. ⚑ binary embeds the open AVERROR in code@0 (P8, KSPlayerError-owner) — reconstructed via
        //   description-form (code=.unknown). message = .formatOpenInput.description (str-length 0x19=25).
        throw KSPlayerError(description: KSPlayerErrorCode.formatOpenInput.description)
    }
    options?.openTime = CACurrentMediaTime()   // ⚑ P42

    // RESOLVED — duration-probe heuristic for very large sources. Disasm @0x101a39b50-0x101a39bb0:
    //   `avio_size(ctx->pb)` (pb @ctx+0x20) → if the source is > 50_000_000_000 bytes (cmp #0xBA43B7401,
    //   strictly-greater) → `ctx->duration_probesize = avio_size / 235` (0xeb; umulh…lsr#7 magic-division,
    //   store @ctx+0x1d0). ⚑ ctx+0x1d0 = `duration_probesize` (offsetof-proven against the reconstruction's own
    //   Libavformat, anchor-validated: pb@0x20 / interrupt_callback@0xd8 / duration@0x68 all match the binary) —
    //   CORRECTS the prior comment's "probesize" guess. Field accessed SYMBOLICALLY (faithful under the ABI).
    //   ⚑ ONE avio_size call, TWO consumers: the heuristic below AND the returned x1. `mov x24,x0` @0x101a39b70,
    //     never redefined before `mov x1,x24` @0x101a39f2c. Threshold `cmp x24,#0xBA43B7401` (= 50_000_000_001,
    //     built as `mov #0x7401 / movk #0xa43b,lsl#16 / movk #0xb,lsl#32`) + `b.lt`, i.e. strictly-greater than
    //     50_000_000_000. Divisor 235 re-verified: magic M=0x16E0689427378EB5, `umulh` + `sub` + `lsr#1` + `lsr#7`
    //     reproduces n/235 for every probe (0 mismatches over 20k values incl. the boundaries 234/235/236).
    let fileSize = avio_size(mutableCtx?.pointee.pb)
    if fileSize > 50_000_000_000 {
        mutableCtx?.pointee.duration_probesize = fileSize / 235
    }

    let findResult = avformat_find_stream_info(mutableCtx, nil)
    guard findResult == 0 else {
        avformat_close_input(&mutableCtx)   // ⚑ core of wrapper FUN_101a39028 (see open-fail path)
        // AVERROR_EOF = FFERRTAG('E','O','F',' ') = -0x20464f45. throw #4 (EOF special) vs throw #3.
        if findResult == swift_AVERROR_EOF {
            // ⚑ binary: err.code@0 = AVERROR_EOF (raw), message nil. The enum-typed `code` cannot hold a raw
            //   AVERROR — P8 (KSPlayerError-owner); reconstructed as an empty-message unknown.
            throw KSPlayerError(code: Int32(KSPlayerErrorCode.unknown.rawValue), description: nil)
        }
        // throw #3. ⚑ binary embeds the find AVERROR in code@0 (P8). message = .formatFindStreamInfo.description
        //   (str-length 0x24=36).
        throw KSPlayerError(description: KSPlayerErrorCode.formatFindStreamInfo.description)
    }

    // ⚑ the returned pointer is the POST-open ctx re-read from the `ps` out-parameter slot
    //   (`ldur x26,[x29,#-0x68]` @0x101a39bc0), and the binary throws when it is nil. The check is on the
    //   find-SUCCESS path: `cbz w0,0x101a39c0c` @0x101a39bc4 then `cbz x26,0x101a39e90` @0x101a39c0c — the
    //   ONLY branch to 0x101a39e90 in the body. That block loads a 36-char literal (`mov x8,#0x15` +
    //   `add x8,#0xf` = 0x24) at 0x103d34e80, read as the find-failure message — byte-identical
    //   to KSPlayerErrorCode.formatFindStreamInfo.description, so the same throw is spelled here.
    //   ⚑ the s74 brief placed this check at 0x101a39bc0; that address is the `ldur`, and the `cbz x26` is at
    //     0x101a39c0c. Corrected against the disassembly.
    guard let openedCtx = mutableCtx else {
        throw KSPlayerError(description: KSPlayerErrorCode.formatFindStreamInfo.description)
    }

    if let options {
        options.findTime = CACurrentMediaTime()   // ⚑ P42
        // fontsDir = NSTemporaryDirectory() + "fontsDir/" + key, where key = (cacheKey == nil ? UUID().uuidString
        //   : MD5(urlString).hex). CryptoKit Insecure.MD5 (FUN_100006158 / HashFunction.init / _finalize / the
        //   digest hex-joined). ⚑ path prefix = the 9-char small-string "fontsDir/" (0x72694473746e6f66 /
        //   0xe9…2f; audit-corrected from the wrong "fonts/"). ⚑ MD5 INPUT = the opened url's string; the exact
        //   input (urlString vs cacheKey) + hex-join are SSA-aliased. ⚑ the UUID-vs-MD5 SELECTOR tests local_160,
        //   which the decompile reassigns to the url-string bridge (line 372) — the polarity may key off
        //   url-string presence, not cacheKey; kept as the defensible cacheKey!=nil reading (audit did not overturn).
        // ⚑ REFUTES the previous `cacheKey != nil` reading (which this comment already flagged as doubtful).
        //   The selector @0x101a39c90 is `cbz x21` on slot(fp-0x150). That slot holds the incoming x4
        //   (inFormat._object) ONLY until `stur x26,[x8,#-0x100]` @0x101a39b68 (x8 = fp-0x50, so the slot IS
        //   fp-0x150) OVERWRITES it with the url string's _object; the same slot is re-loaded by
        //   `ldur x21,[x8,#-0x100]` @0x101a39c8c immediately before the test. So the test is "is there a url
        //   string", i.e. the `.left` arm — not cacheKey/inFormat. The MD5 input @0x101a39ca8 is that SAME
        //   string value, so it is spelled as the same local here.
        let key: String
        if let urlString {
            let digest = Insecure.MD5.hash(data: Data(urlString.utf8))
            key = digest.map { String(format: "%02x", $0) }.joined()
        } else {
            key = UUID().uuidString
        }
        let fontsURL = URL(fileURLWithPath: NSTemporaryDirectory() + "fontsDir/" + key)
        try? FileManager.default.createDirectory(at: fontsURL, withIntermediateDirectories: true)
        options.fontsDir = fontsURL
    }

    // ⚑ `mov x0,x26 / mov x1,x24 / mov x2,x27` @0x101a39f28-30, sole `ret` @0x101a39f58 (the only `ret` in
    //   the 902-instruction body).
    //   ⚑[tool=llvm-objdump ref=openFormatContext:0x101a392a0 result=3-TUPLE-RETURN]
    return (openedCtx, fileSize, ioContext)
}
