//
//  FormatContext.swift
//  KSPlayer
//
//  Binary-faithful reconstruction (Forward 1.3.17). NEW Forward-only type.
//  Remux-foundation; consumed by the Phase-2 Remuxer + Phase-3 DV path.
//  Reconstructed from binary: outer init `0x101a35050` (_swift_allocObject + delegate)
//  → inner init `0x101a350bc` (the real body; derivation-heavy + side effects).
//
//  FAITHFUL PARTIAL: the 6 param-fed fields are assigned exactly as the binary stores
//  them; the derived fields (bitrate, byteSeek, startTime, maxFrameDuration, formatName)
//  are COMPUTED in the 794-line body from `formatCtx` and are NOT reconstructed here —
//  they are declared with safe defaults and marked `// UNRESOLVED`. Derivations are not
//  fabricated (a plausible-but-wrong body looks done and crashes downstream).
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
    public var seekByBytes: Bool                             // +0x58  binary stores constant 0 (false)
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

        // --- seekByBytes: binary stores constant 0 at +0x58 (faithful) ---
        self.seekByBytes = false

        // --- assetTracks: empty default (binary populates +0x40 from a per-stream
        //     FFmpegAssetTrack-building loop; that construction is UNRESOLVED) ---
        self.assetTracks = []

        // --- Derived fields: COMPUTED in the binary init body (likely from formatCtx).
        //     Declared with safe Swift defaults; computation not reconstructed. ---
        self.bitrate = 0          // UNRESOLVED: derived in binary init @+0x38 — fileSize*8/duration-style calc not reconstructed (faithful partial)
        self.formatName = ""      // UNRESOLVED: derived in binary init @+0x48 — from formatCtx->iformat->name not reconstructed (faithful partial)
        self.byteSeek = false     // UNRESOLVED: derived in binary init @+0x59 — from format flags + name compare not reconstructed (faithful partial)
        self.startTime = .zero    // UNRESOLVED: derived in binary init @+0x5c — CMTime from formatCtx->start_time / kCMTimeZero not reconstructed (faithful partial)
        self.maxFrameDuration = 0 // UNRESOLVED: derived in binary init @+0x78 — 3600 or 10 from format flags not reconstructed (faithful partial)

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
