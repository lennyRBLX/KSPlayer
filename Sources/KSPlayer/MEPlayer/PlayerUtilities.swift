//
//  PlayerUtilities.swift
//  KSPlayer
//
//  RE-derived utility types from Forward v1.3.15.
//

import CoreGraphics
import Foundation

// MARK: - Average

/// Running average calculator for A/V sync and buffer monitoring.
public struct Average: Sendable {
    public private(set) var count: Int = 0
    public private(set) var total: Double = 0

    public var average: Double {
        count > 0 ? total / Double(count) : 0
    }

    public init() {}

    public mutating func add(_ value: Double) {
        count += 1
        total += value
    }

    public mutating func reset() {
        count = 0
        total = 0
    }
}

// MARK: - VideoInfo

/// Demux/probe media-info model produced when a source is opened: a summary
/// of the container plus its discovered ``FFmpegAssetTrack`` list.
///
/// RE: 0x101416958, 0x101416b48 (VideoInfo, 1.3.15)
public final class VideoInfo {
    /// Container duration in seconds (from `avformat_find_stream_info`).
    public var duration: Double
    /// Total file size in bytes (from `avio_size`).
    public var fileSize: Int64
    /// Container-level metadata tags (title, artist, etc.).
    public var metadata: [String: String]
    /// All discovered streams — ties this class to ``FFmpegAssetTrack``.
    public var assetTracks: [FFmpegAssetTrack]
    /// Decoded attached cover-art image, nil if none present.
    public var coverImage: CGImage?

    public init(
        duration: Double = 0,
        fileSize: Int64 = 0,
        metadata: [String: String] = [:],
        assetTracks: [FFmpegAssetTrack] = [],
        coverImage: CGImage? = nil
    ) {
        self.duration = duration
        self.fileSize = fileSize
        self.metadata = metadata
        self.assetTracks = assetTracks
        self.coverImage = coverImage
    }

    /// In-place filter of `assetTracks`: retains only elements whose track ID
    /// is a member of the passed set. Partition-compacts survivors without
    /// reallocating the array.
    ///
    /// The binary hashes each element via `Hasher._hash(seed:)` against the
    /// Set's bucket bitmap and performs a CoW uniqueness check
    /// (`_swift_isUniquelyReferenced_nonNull_native`) before mutating. In
    /// reconstructed Swift we key on `trackID` (the stream index) which is the
    /// semantic identifier callers use to select a subset of streams.
    ///
    /// RE: 0x101416958 (VideoInfo_filterByHashSet, 1.3.15)
    public func filterByHashSet(_ retainSet: Set<Int32>) {
        assetTracks.removeAll { track in
            !retainSet.contains(track.trackID)
        }
    }

    /// Lock-guarded wrapper over ``filterByHashSet(_:)`` for thread-safe
    /// mutation of `assetTracks` from arbitrary queues.
    ///
    /// RE: 0x101416b48 (VideoInfo_filterByHashSetThreadsafe, 1.3.15)
    public func filterByHashSetThreadSafe(_ retainSet: Set<Int32>, lock: NSLock) {
        lock.lock()
        defer { lock.unlock() }
        filterByHashSet(retainSet)
    }
}

// MARK: - SerialTaskQueue

/// Async serial task queue for ordered execution.
public final class SerialTaskQueue: Sendable {
    private let continuation: AsyncStream<@Sendable () async -> Void>.Continuation
    private let task: Task<Void, Never>

    public init() {
        let (stream, continuation) = AsyncStream<@Sendable () async -> Void>.makeStream()
        self.continuation = continuation
        self.task = Task {
            for await work in stream {
                await work()
            }
        }
    }

    public func enqueue(_ work: @escaping @Sendable () async -> Void) {
        continuation.yield(work)
    }

    public func cancelAll() {
        continuation.finish()
        task.cancel()
    }

    deinit {
        continuation.finish()
        task.cancel()
    }
}
