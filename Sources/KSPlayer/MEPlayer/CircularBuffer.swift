//
//  CircularBuffer.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/9.
//

import Foundation

/// 这个是单生产者，多消费者的阻塞队列和单生产者，多消费者的阻塞环形队列。并且环形队列还要有排序的能力。
/// 因为seek需要清空队列，所以导致他是多消费者。后续可以看下能不能改成单消费者的。
public class CircularBuffer<Item: ObjectQueueItem> {
    private var _buffer = ContiguousArray<Item?>()
//    private let semaphore = DispatchSemaphore(value: 0)
    private let condition = NSCondition()
    private var headIndex = UInt(0)
    private var tailIndex = UInt(0)
    private let expanding: Bool
    private let sorted: Bool
    // Forward-added stored `let`, and the 4th init parameter. Name AND position are binary-read, not inferred:
    //   __swift5_fieldmd (l2_field_gate) gives the field order
    //   [_buffer, condition, headIndex, tailIndex, expanding, sorted, isClearItem, destroyed, mask, maxCount, fps],
    //   and the init body @0x101a5a2a8 stores param3→+0x30 (expanding), param2→+0x31 (sorted),
    //   param4→+0x32 (isClearItem) and a constant false→+0x33 (destroyed), object size 0x4c.
    private let isClearItem: Bool
    private var destroyed = false

    private var mask: UInt
    public private(set) var maxCount: UInt
    public internal(set) var fps: Float = 24
    @inline(__always)
    private var _count: UInt { tailIndex &- headIndex }
    // ⚑[tool=member_surface ref=CircularBuffer.count.getter:0x101a160f8 result=Swift.UInt] — as is `pop(wait:where:)`'s
    //   predicate arity (0x101a167b4). Both bodies: no swift_task_*/ScM call (lock-guarded, nonisolated).
    @inline(__always)
    public var count: UInt {
//        condition.lock()
//        defer { condition.unlock() }
        tailIndex &- headIndex
    }
    // ⚑[tool=export_trie_oracle ref=CircularBuffer.__allocating_init:$s8KSPlayer14CircularBufferC15initialCapacity6sorted9expanding11isClearItemACyxGSu_S3btcfC result=initialCapacity:UInt,sorted:Bool,expanding:Bool,isClearItem:Bool]
    //   All four labels and their order are read from the export trie, not inferred. The four DEFAULTS below are
    //   NOT binary-readable (ZERO `default argument N of …` trie symbols). 0x101a16238 `cbz x0→brk` precedes the stores; the later `sub` is flagless.
    public init(initialCapacity: UInt = 256, sorted: Bool = false, expanding: Bool = true, isClearItem: Bool = false) {
        precondition(initialCapacity > 0)
        self.expanding = expanding
        self.sorted = sorted
        self.isClearItem = isClearItem
        let capacity = initialCapacity.nextPowerOf2()
        _buffer = ContiguousArray<Item?>(repeating: nil, count: Int(capacity))
        maxCount = capacity
        mask = maxCount - 1
        assert(_buffer.count == Int(capacity))
    }

    public func push(_ value: Item) {
        condition.lock()
        defer { condition.unlock() }
        if destroyed {
            return
        }
        if _buffer[Int(tailIndex & mask)] != nil {
            assertionFailure("value is not nil of headIndex: \(headIndex),tailIndex: \(tailIndex), bufferCount: \(_buffer.count), mask: \(mask)")
        }
        _buffer[Int(tailIndex & mask)] = value
        if sorted {
            // 不用sort进行排序，这个比较高效
            var index = tailIndex
            while index > headIndex {
                guard let item = _buffer[Int((index - 1) & mask)] else {
                    assertionFailure("value is nil of index: \((index - 1) & mask) headIndex: \(headIndex),tailIndex: \(tailIndex), bufferCount: \(_buffer.count),  mask: \(mask)")
                    break
                }
                if item.timestamp <= _buffer[Int(index & mask)]!.timestamp {
                    break
                }
                _buffer.swapAt(Int((index - 1) & mask), Int(index & mask))
                index -= 1
            }
        }
        tailIndex &+= 1
        if _count >= maxCount {
            if expanding {
                // No more room left for another append so grow the buffer now.
                _doubleCapacity()
            } else {
                condition.wait()
            }
        } else {
            // 只有数据了。就signal。因为有可能这是最后的数据了。
            if _count == 1 {
                condition.signal()
            }
        }
    }

    public func pop(wait: Bool = false, where predicate: ((Item, UInt) -> Bool)? = nil) -> Item? {
        condition.lock()
        defer { condition.unlock() }
        if destroyed {
            return nil
        }
        if headIndex == tailIndex {
            if wait {
                condition.wait()
                if destroyed || headIndex == tailIndex {
                    return nil
                }
            } else {
                return nil
            }
        }
        let index = Int(headIndex & mask)
        guard let item = _buffer[index] else {
            assertionFailure("value is nil of index: \(index) headIndex: \(headIndex),tailIndex: \(tailIndex), bufferCount: \(_buffer.count), mask: \(mask)")
            return nil
        }
        if let predicate, !predicate(item, _count) {
            return nil
        } else {
            headIndex &+= 1
            _buffer[index] = nil
            if _count == maxCount >> 1 {
                condition.signal()
            }
            return item
        }
    }

    public func search(where predicate: (Item) -> Bool) -> [Item] {
        condition.lock()
        defer { condition.unlock() }
        var i = headIndex
        var result = [Item]()
        while i < tailIndex {
            if let item = _buffer[Int(i & mask)] {
                if predicate(item) {
                    result.append(item)
                    _buffer[Int(i & mask)] = nil
                    headIndex = i + 1
                }
            } else {
                assertionFailure("value is nil of index: \(i) headIndex: \(headIndex), tailIndex: \(tailIndex), bufferCount: \(_buffer.count), mask: \(mask)")
                return result
            }
            i += 1
        }
        return result
    }
    public func seek(seconds: Double, needKeyFrame: Bool) -> (UInt, Double)? { fatalError("L7: CircularBuffer.seek — Forward body unread") }

    public func flush() {
        condition.lock()
        defer { condition.unlock() }
        headIndex = 0
        tailIndex = 0
        _buffer.removeAll(keepingCapacity: !destroyed)
        _buffer.append(contentsOf: ContiguousArray<Item?>(repeating: nil, count: destroyed ? 1 : Int(maxCount)))
        condition.broadcast()
    }

    public func shutdown() {
        destroyed = true
        flush()
    }

    private func _doubleCapacity() {
        var newBacking: ContiguousArray<Item?> = []
        let newCapacity = maxCount << 1 // Double the storage.
        precondition(newCapacity > 0, "Can't double capacity of \(_buffer.count)")
        assert(newCapacity % 2 == 0)
        newBacking.reserveCapacity(Int(newCapacity))
        let head = Int(headIndex & mask)
        newBacking.append(contentsOf: _buffer[head ..< Int(maxCount)])
        if head > 0 {
            newBacking.append(contentsOf: _buffer[0 ..< head])
        }
        let repeatitionCount = Int(newCapacity) &- newBacking.count
        newBacking.append(contentsOf: repeatElement(nil, count: repeatitionCount))
        headIndex = 0
        tailIndex = UInt(newBacking.count &- repeatitionCount)
        _buffer = newBacking
        maxCount = newCapacity
        mask = maxCount - 1
    }
}

extension FixedWidthInteger {
    /// Returns the next power of two.
    // No zero-guard: `@inline(__always)` puts this helper inside the init's machine code, and the binary has no
    // `return 1` arm anywhere in 0x101a16198..0x101a16314 (95 instr). The parameter is referenced at exactly two
    // sites — `cbz x25, 0x101a16308` @0x101a16238 branching to `brk #1`, and the `sub x8, x25, #1` @0x101a16254
    // that cbz guards — so the zero case traps as the unsigned-subtraction precondition rather than returning 1.
    // Sole call site is CircularBuffer.init above, so removing the guard changes no other caller.
    @inline(__always)
    func nextPowerOf2() -> Self {
        1 << (Self.bitWidth - (self - 1).leadingZeroBitCount)
    }
}
