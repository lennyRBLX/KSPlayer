//
//  Anime4KFrameDump.swift
//  KSPlayer
//
//  Forward 1.3.17 reconstruction (partial). `Anime4KFrameDump` is a feature-toggled, rate-limited
//  GPU frame-export facility — part of the (otherwise un-reconstructed) Anime4K real-time-upscaling
//  subsystem. `MetalRender.draw` integrates it: when enabled and under the rate limit it reads back
//  the rendered frame texture and exports numbered files to <Documents>/Anime4KDump.
//
//  THIS COMMIT = the enum + its static STATE only (floor-neutral declaration; MetalRender static-
//  storage precedent). The 4 static methods follow in later commits:
//    configure(…) @0x101a775c0 · gate @0x101a784d4 · async-notify @0x101a778a8 · readback @0x101a77d20
//
//  Owner identified deterministically (s52): the default-dir builder @0x101a76f44 appends the
//  "Anime4KDump" literal; catalog types_1.3.17.json lists `Anime4KFrameDump` (enum, KSPlayer). All
//  property names WERE inferred (`#function` yielded nothing) and FIVE OF THEM WERE WRONG — the
//  orphaned export trie names every public static directly. TYPES + storage are decoded from the
//  module globals + swift_once inits. Full map: reconstruction/draw_preflight_session52.json.
//
//  RECOVERED session 63 (each type independently corroborates the pairing):
//    isEnabled -> enabled (Bool) · frameLimit -> maxFrames (Int) · directory -> outputDirectory (URL)
//    notifyEnabled -> dumpDecoded (Bool) · readbackEnabled -> dumpRendered (Bool)
//  All five carry a `property descriptor` (vpMV), which is public-exclusive, so all five are
//  `public` — previously only `isEnabled` was.
// ⚑[tool=export_trie_oracle ref=Anime4KFrameDump.{enabled,maxFrames,outputDirectory,dumpDecoded,dumpRendered} result=NAMES+ACCESS RECOVERED, superseding "all property names INFERRED"]
//

import Foundation

public enum Anime4KFrameDump {
    /// Master enable toggle. Storage DAT_104c636c0; direct setter @0x101a76c08 (no once-guard).
    public nonisolated(unsafe) static var enabled = false

    /// Max frames to export; set by configure @0x101a775c0. Storage DAT_1044ebcd0.
    public nonisolated(unsafe) static var maxFrames = 0

    /// Frames exported so far; reset to 0 by configure, incremented under `stateLock` in the gate
    /// @0x101a784d4 (dumps only while frameCounter < maxFrames). Storage DAT_1044ebcf0.
    /// ⚑ name still INFERRED — and now a VERIFIED negative: this static carries no symbol in the
    ///   export trie, consistent with it not being public (the five above all do).
    // ⚑[tool=export_trie_oracle ref=Anime4KFrameDump.frameCounter result=absent — VERIFIED negative, name remains inferred]
    nonisolated(unsafe) static var frameCounter = 0

    /// Sub-toggle gating the async-notify path (@0x101a778a8). Storage DAT_1044ebcc8.
    public nonisolated(unsafe) static var dumpDecoded = false

    /// Sub-toggle gating the GPU texture-readback path (@0x101a77d20). Storage DAT_1044ebcc9.
    public nonisolated(unsafe) static var dumpRendered = false

    /// Export directory (lazy). Storage DAT_104c636c8; default builder @0x101a76f44. configure can
    /// override.
    public nonisolated(unsafe) static var outputDirectory: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Anime4KDump")
    }()

    /// Serializes `frameCounter`. Lazy = NSLock() (once-init @0x101a77598). Storage DAT_1044ebce8.
    /// ⚑ name INFERRED (absent from the trie, as expected for a non-public static).
    static let stateLock = NSLock()

    /// Serial queue for the export work. Lazy (once-init @0x101a773cc: label "Anime4KFrameDump",
    /// default qos, empty attributes → serial). Storage DAT_1044ebd00. ⚑ name INFERRED (absent from trie).
    static let queue = DispatchQueue(label: "Anime4KFrameDump")

    // ⚑[tool=export_trie_oracle ref=Anime4KFrameDump.reset():() result=MISSING FROM SOURCE — the binary exports `static KSPlayer.Anime4KFrameDump.reset() -> ()`. Its body is NOT reconstructed here and is NOT guessed; it needs its own decompile unit]

    /// Public config entry. The method name and ALL FIVE parameter labels are RECOVERED, not
    /// inferred — `recover_swift_function_name` returned None here, but the orphaned export trie
    /// carries the full mangled name. Every one of the five inferred labels was wrong.
    /// ⚑[tool=export_trie_oracle ref=Anime4KFrameDump.configure(enabled:maxFrames:outputDirectory:dumpDecoded:dumpRendered:) result=labels RECOVERED, superseding the `recover_swift_function_name ref=0x101a775c0 result=None` pin]
    /// Sets the enable flag, the frame limit and the two sub-toggles, optionally overrides the export
    /// directory, and resets the frame counter under `stateLock`. Reconstructed from @0x101a775c0.
    public static func configure(enabled: Bool, maxFrames: Int, outputDirectory: URL?, dumpDecoded: Bool, dumpRendered: Bool) {
        Anime4KFrameDump.enabled = enabled
        Anime4KFrameDump.maxFrames = maxFrames
        if let outputDirectory {
            Anime4KFrameDump.outputDirectory = outputDirectory
        }
        Anime4KFrameDump.dumpDecoded = dumpDecoded
        Anime4KFrameDump.dumpRendered = dumpRendered
        stateLock.lock()
        frameCounter = 0
        stateLock.unlock()
    }
}
