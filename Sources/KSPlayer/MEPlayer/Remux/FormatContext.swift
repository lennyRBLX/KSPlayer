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
//  RECONSTRUCTED (session 28) the 4 cleanly-separable symbolic-FFmpeg derivations — `formatName`,
//  `startTime`, `maxFrameDuration` (idiom of the proven MEPlayerItem:233-239), and `byteSeek`
//  (@0x101a35494-0x101a354e8, disasm-verified) — symbolic field access = faithful by construction under
//  the non-stock ABI. Still UNRESOLVED (safe defaults, `// UNRESOLVED`): `seekByBytes` (+0x58, a CMTime
//  duration-compare with a `formatCtx->duration` side-effect + array counts) and `bitrate` (+0x38, a
//  rate calc at the loop tail) — BOTH entangled with the deferred `assetTracks` per-stream FFmpegAssetTrack
//  loop + the embedded-font-extraction side-effect, so they come WITH that deep reconstruction. Remaining
//  derivations are NOT fabricated (a plausible-but-wrong body looks done and crashes downstream).
//

import CoreMedia
import Foundation
import Libavformat

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
        // --- Param-fed fields: assigned faithfully (offsets confirmed in inner decompile) ---
        self.interrupt = interrupt   // +0x10 = param_4
        self.formatCtx = formatCtx   // +0x18 = param_2
        self.ioContext = ioContext   // +0x20 = param_5
        self.fileSize = fileSize     // +0x30 = param_3
        self.fontsDir = fontsDir     // (sym field) from param_6
        // DIVERGENCE from brief mapping: the binary stores +0x28(duration)=param_1 on the
        // dominant path, BUT param_1 is reassigned mid-body to a formatCtx-derived fallback
        // (formatCtx->duration / 1_000_000) on the ioContext==nil branch. We assign the
        // param (faithful to the dominant store); the derived-fallback override is UNRESOLVED.
        self.duration = duration     // +0x28 = param_1 (derived override on ioContext==nil branch UNRESOLVED)

        // --- seekByBytes: default false. UNRESOLVED: binary conditionally stores 0
        //     (inner L222) or a computed 1 (inner L211, uVar20) across branches —
        //     derivation not reconstructed (faithful partial); NOT a constant. ---
        self.seekByBytes = false

        // --- assetTracks: empty default (binary populates +0x40 from a per-stream
        //     FFmpegAssetTrack-building loop; that construction is UNRESOLVED) ---
        self.assetTracks = []

        // --- Derived fields: COMPUTED in the binary init body (likely from formatCtx).
        //     Declared with safe Swift defaults; computation not reconstructed. ---
        self.bitrate = 0          // UNRESOLVED: derived in binary init @+0x38 — fileSize*8/duration-style calc not reconstructed (faithful partial)
        // +0x48 = String(cString: iformat->name). FUN_101a350bc reads *(*(formatCtx+8)) (iformat->name);
        // identical idiom to MEPlayerItem:236 (FFmpeg struct fields accessed SYMBOLICALLY — non-stock ABI, faithful by construction).
        self.formatName = String(cString: formatCtx.pointee.iformat.pointee.name)
        // +0x59 = (iformat.flags & AVFMT_NO_BYTE_SEEK == 0) && (iformat.flags & (AVFMT_TS_DISCONT|AVFMT_NOTIMESTAMPS) != 0)
        //   && formatName != "ogg". FUN_101a350bc @0x101a35494-0x101a354e8 disasm-verified (tbnz #0xf; and #0x280; "ogg" 0x67676f
        //   compare). Broader mask than MEPlayerItem:237's seekByBytes (0x280 = AVFMT_TS_DISCONT|AVFMT_NOTIMESTAMPS, vs 0x200 there).
        let iformatFlags = formatCtx.pointee.iformat.pointee.flags
        self.byteSeek = (iformatFlags & AVFMT_NO_BYTE_SEEK == 0)
            && (iformatFlags & (AVFMT_TS_DISCONT | AVFMT_NOTIMESTAMPS) != 0)
            && (formatName != "ogg")
        // +0x5c = CMTime from formatCtx->start_time (== AV_NOPTS_VALUE(Int64.min) ? kCMTimeZero : CMTime(value:, timescale: AV_TIME_BASE)).
        // FUN_101a350bc reads formatCtx-start_time == INT64_MIN; identical idiom to MEPlayerItem:238-239.
        self.startTime = formatCtx.pointee.start_time != Int64.min
            ? CMTime(value: formatCtx.pointee.start_time, timescale: AV_TIME_BASE)
            : .zero
        // +0x78 = (iformat->flags & AVFMT_TS_DISCONT) ? 10 : 3600 — discontinuous-timestamp formats get a small max
        // frame duration. FUN_101a350bc reads (iformat.flags & 0x200); idiom of MEPlayerItem:233-234 (there Double; here the field is Int, Si).
        self.maxFrameDuration = formatCtx.pointee.iformat.pointee.flags & AVFMT_TS_DISCONT == AVFMT_TS_DISCONT ? 10 : 3600

        // --- Side effect (font registration) ---
        // init registers fonts: FileManager.createDirectory(at: fontsDir) + CTFontManagerRegisterFontsForURL(fontsDir) — side-effect spine; deep construction UNRESOLVED
        // Binary detail (NOT fabricated here): the real spine is a per-stream loop over
        // formatCtx->streams that finds attachment streams (codec type == 4 / font mime),
        // extracts each embedded font's Data, writes it to a derived temp URL, then calls
        // NSFileManager.createDirectoryAtURL(...) + _CTFontManagerRegisterFontsForURL(url, 1, 0)
        // per extracted font file. The observable two-call spine cannot be expressed without
        // inventing the per-attachment URL/Data internals, so it is left UNRESOLVED.
    }
}
