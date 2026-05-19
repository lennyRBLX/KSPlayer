//
//  PacketRingBuffer.swift
//  KSPlayer
//
//  Forward addition (RE): Lock-based ring buffer for packet queuing
//  with condition-variable signaling for consumer/producer coordination.
//
//  Binary: PacketRingBuffer (2 functions)
//  RE source: Forward v1.3.15
//

import Foundation

public class PacketRingBuffer<T: AnyObject> {
    private var buffer: [T?]
    private let condition = NSCondition()
    private var readIndex: UInt64 = 0
    private var writeIndex: UInt64 = 0
    private var releaseOnDequeue: Bool = false
    private var destroyed: Bool = false
    private let mask: UInt64
    private let capacity: UInt64

    public init(capacity: Int) {
        let powerOf2 = max(1, capacity).nextPowerOf2
        self.capacity = UInt64(powerOf2)
        self.mask = UInt64(powerOf2 - 1)
        self.buffer = Array(repeating: nil, count: powerOf2)
    }

    // RE: PacketRingBuffer_dequeue @ 0x1014298a0
    public func dequeue(wait: Bool = false, filter: ((T, UInt64) -> Bool)? = nil) -> T? {
        condition.lock()
        defer { condition.unlock() }

        if destroyed { return nil }

        if readIndex == writeIndex {
            if !wait { return nil }
            condition.wait()
            if destroyed { return nil }
            if readIndex == writeIndex { return nil }
        }

        let index = Int(readIndex & mask)
        guard let item = buffer[index] else { return nil }

        if let filter = filter {
            let count = writeIndex - readIndex
            if !filter(item, count) {
                return nil
            }
        }

        readIndex += 1

        if releaseOnDequeue {
            buffer[index] = nil
        }

        let remaining = writeIndex - readIndex
        let halfCap = capacity / 2
        if capacity > 16 {
            if remaining == capacity / 2 {
                condition.signal()
            }
        } else if remaining == capacity - 2 {
            condition.signal()
        }

        return item
    }

    // RE: PacketRingBuffer_flush @ 0x101429b38
    public func flush() {
        condition.lock()
        defer { condition.unlock() }
        for i in 0..<buffer.count {
            buffer[i] = nil
        }
        readIndex = 0
        writeIndex = 0
    }

    public func enqueue(_ item: T) {
        condition.lock()
        defer { condition.unlock() }
        let index = Int(writeIndex & mask)
        buffer[index] = item
        writeIndex += 1
        condition.signal()
    }

    public func destroy() {
        condition.lock()
        destroyed = true
        condition.broadcast()
        condition.unlock()
    }

    public var count: Int {
        Int(writeIndex - readIndex)
    }
}

private extension Int {
    var nextPowerOf2: Int {
        guard self > 0 else { return 1 }
        return 1 << (Int.bitWidth - (self - 1).leadingZeroBitCount)
    }
}
