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

public final class ThumbnailQueue {
    public private(set) var pendingIndices: [Int]
    public private(set) var generatedSet: Set<Int> = []
    public private(set) var skippedSet: Set<Int> = []
    private let lock = NSLock()
    public let id: String
    public let count: Int
    public let duration: Double

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

    /// Iterates pending indices, calls session.seekAndExtract for each, marks result.
    public func processQueue(using session: ThumbnailSession, generator: ThumbnailGenerator) {
        self.session = session
        while let index = nextPendingIndex() {
            if let _ = generator.generateThumbnail(at: index, session: session) {
                markGenerated(index)
            } else {
                markSkipped(index)
            }
        }
        KSLog("[ThumbnailQueue] \(id) complete: generated=\(generatedSet.count), skipped=\(skippedSet.count)")
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
