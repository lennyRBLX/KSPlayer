//
//  ThumbnailQueue.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — .reversal/MediaServices.md § Thumbnail Generation
//  Verified Ghidra named entries:
//    ThumbnailQueue_processQueue @ 0x10141C6DC
//    ThumbnailQueue_submitJob    @ 0x1007900A0
//
//  The earlier addresses 0x101300164 / 0x101300280 / 0x101300674 were three
//  separate mid-function offsets that all collapse into a single Ghidra
//  function FUN_101300130 (1,396 B). The real named entries above live at
//  unrelated addresses.
//
//  Thumbnail generation queue with batch index tracking.
//  Sits between ThumbnailController (UI-facing) and ThumbnailSession (FFmpeg extraction).
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Protocol for thumbnail generation backends.
/// Allows ThumbnailQueue to drive extraction without coupling to a specific implementation.
public protocol ThumbnailGenerator: AnyObject {
    func generateThumbnail(at index: Int, session: ThumbnailSession) -> FFThumbnail?
}

/// RE: ThumbnailQueue class (TrackDecode.md, 7 fields per types.json)
/// Work queue that schedules which timeline indices still need thumbnails,
/// tracking generated vs. skipped sets under a lock.
///
/// Field offsets visible in processQueue: pendingIndices at +0x10,
/// Set backing stores reached via +0x18/+0x20, id String at +0x30.
public final class ThumbnailQueue {
    // Field 1: Timeline indices still awaiting generation (+0x10)
    public private(set) var pendingIndices: [Int]
    // Field 2: Indices already generated (+0x18)
    public private(set) var generatedSet: Set<Int> = []
    // Field 3: Indices deliberately skipped (e.g. too close to a cached one) (+0x20)
    public private(set) var skippedSet: Set<Int> = []
    // Field 4: Guards the three collections for concurrent access
    private let lock = NSLock()
    // Field 5: Queue/source identifier (+0x30)
    public let id: String
    // Field 6: Total thumbnail count for the source
    public let count: Int
    // Field 7: Source duration in seconds
    public let duration: Double

    /// Active ThumbnailSession (observed at offset +48 in components-side layout)
    public weak var session: ThumbnailSession?

    public init(id: String, count: Int, duration: Double) {
        self.id = id
        self.count = count
        self.duration = duration
        self.pendingIndices = Array(0 ..< count)
    }

    /// Thread-safe pop of the next pending index.
    public func nextPendingIndex() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard !pendingIndices.isEmpty else { return nil }
        return pendingIndices.removeFirst()
    }

    /// Mark an index as successfully generated.
    public func markGenerated(_ index: Int) {
        lock.lock()
        defer { lock.unlock() }
        generatedSet.insert(index)
    }

    /// Mark an index as skipped (extraction failed or was cancelled).
    public func markSkipped(_ index: Int) {
        lock.lock()
        defer { lock.unlock() }
        skippedSet.insert(index)
    }

    /// RE: 0x10141c6dc (ThumbnailQueue_processQueue, 1.3.15)
    /// Drains the queue: clears the counter on the first pending object (+0x10 -> +0x28 = 0),
    /// releases the generatedSet/skippedSet Set backing stores, runs the locked mutation
    /// under a _swift_beginAccess exclusive guard, then _swift_bridgeObjectRelease the
    /// id String at +0x30.
    ///
    /// The binary describes a cleanup/reset/drain operation, not a generation loop.
    /// This resets the queue state after a generation pass is complete or cancelled.
    public func processQueue() {
        lock.lock()
        defer { lock.unlock() }

        // Clear the pending indices counter (binary: +0x10 -> +0x28 = 0)
        pendingIndices.removeAll()

        // Release the generatedSet/skippedSet backing stores
        // (binary: FUN_102a16d38 releases Set backing)
        generatedSet.removeAll()
        skippedSet.removeAll()

        // The binary also _swift_bridgeObjectRelease the id String at +0x30,
        // but since id is a let-bound String in Swift, the release happens
        // naturally when the ThumbnailQueue is deallocated. The drain operation
        // resets mutable state only.

        KSLog("[ThumbnailQueue] \(id) processQueue: queue drained and reset")
    }

    /// RE: 0x1007900a0 (ThumbnailQueue_submitJob, 1.3.15)
    /// Enqueues a generation job. This is the async job-submission entry point
    /// that the doc describes as a trampoline into FUN_10078ff50 + FUN_10076d2f4.
    /// Dispatches generation work onto a background queue, iterating pending indices
    /// and driving extraction through the provided generator and session.
    public func submitJob(session: ThumbnailSession, generator: ThumbnailGenerator) {
        self.session = session
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            while let index = self.nextPendingIndex() {
                if let _ = generator.generateThumbnail(at: index, session: session) {
                    self.markGenerated(index)
                } else {
                    self.markSkipped(index)
                }
            }
            KSLog("[ThumbnailQueue] \(self.id) submitJob complete: generated=\(self.generatedSet.count), skipped=\(self.skippedSet.count)")
        }
    }

    /// Progress as a fraction (0.0 ... 1.0).
    public var progress: Double {
        guard count > 0 else { return 1.0 }
        return Double(generatedSet.count) / Double(count)
    }

    /// Whether all indices have been processed (generated or skipped).
    public var isComplete: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pendingIndices.isEmpty
    }
}
