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
//  property names are ⚑ INFERRED (#function-unrecoverable); TYPES + storage are decoded from the
//  module globals + swift_once inits. Full map: reconstruction/draw_preflight_session52.json.
//

import Foundation

public enum Anime4KFrameDump {
    /// Master enable toggle. Storage DAT_104c636c0; direct setter @0x101a76c08 (no once-guard).
    /// ⚑ name + `public` inferred (setter has no in-binary callers → host-facing config API).
    public nonisolated(unsafe) static var isEnabled = false

    /// Max frames to export; set by configure @0x101a775c0. Storage DAT_1044ebcd0. ⚑ name inferred.
    nonisolated(unsafe) static var frameLimit = 0

    /// Frames exported so far; reset to 0 by configure, incremented under `stateLock` in the gate
    /// @0x101a784d4 (dumps only while frameCounter < frameLimit). Storage DAT_1044ebcf0. ⚑ name inferred.
    nonisolated(unsafe) static var frameCounter = 0

    /// Sub-toggle gating the async-notify path (@0x101a778a8). Storage DAT_1044ebcc8. ⚑ name inferred.
    nonisolated(unsafe) static var notifyEnabled = false

    /// Sub-toggle gating the GPU texture-readback path (@0x101a77d20). Storage DAT_1044ebcc9. ⚑ name inferred.
    nonisolated(unsafe) static var readbackEnabled = false

    /// Export directory (lazy). Storage DAT_104c636c8; default builder @0x101a76f44. configure can
    /// override. ⚑ name inferred.
    nonisolated(unsafe) static var directory: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Anime4KDump")
    }()

    /// Serializes `frameCounter`. Lazy = NSLock() (once-init @0x101a77598). Storage DAT_1044ebce8. ⚑ name inferred.
    static let stateLock = NSLock()

    /// Serial queue for the export work. Lazy (once-init @0x101a773cc: label "Anime4KFrameDump",
    /// default qos, empty attributes → serial). Storage DAT_1044ebd00. ⚑ name inferred.
    static let queue = DispatchQueue(label: "Anime4KFrameDump")

    /// Public config entry — ⚑ method + param names INFERRED ⚑[tool=recover_swift_function_name ref=0x101a775c0 result=None].
    /// Sets the enable flag, the frame limit and the two sub-toggles, optionally overrides the export
    /// directory, and resets the frame counter under `stateLock`. Reconstructed from @0x101a775c0.
    public static func configure(enable: Bool, limit: Int, directory: URL?, notify: Bool, readback: Bool) {
        isEnabled = enable
        frameLimit = limit
        if let directory {
            Anime4KFrameDump.directory = directory
        }
        notifyEnabled = notify
        readbackEnabled = readback
        stateLock.lock()
        frameCounter = 0
        stateLock.unlock()
    }
}
