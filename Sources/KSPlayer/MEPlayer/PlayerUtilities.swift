//
//  PlayerUtilities.swift
//  KSPlayer
//
//  RE-derived utility types from Forward v1.3.15.
//

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

/// Simple data model for video metadata.
public struct VideoInfo: Sendable, Codable {
    public var width: Int32
    public var height: Int32
    public var fps: Float
    public var duration: TimeInterval
    public var bitRate: Int64
    public var codecName: String
    public var dynamicRange: DynamicRange

    public init(
        width: Int32 = 0,
        height: Int32 = 0,
        fps: Float = 0,
        duration: TimeInterval = 0,
        bitRate: Int64 = 0,
        codecName: String = "",
        dynamicRange: DynamicRange = .sdr
    ) {
        self.width = width
        self.height = height
        self.fps = fps
        self.duration = duration
        self.bitRate = bitRate
        self.codecName = codecName
        self.dynamicRange = dynamicRange
    }
}

// DynamicRange needs Codable for VideoInfo synthesis.
extension DynamicRange: Codable {}

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
