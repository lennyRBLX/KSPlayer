//
//  PBClass.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 (TranscodeIO.md).
//
//  Binary class metadata: `_TtC8KSPlayerP33_92A0AD70DC642356038FCA3F4FD833927PBClass`
//  -- private nested class in module `KSPlayer`. The `MEPlayerItem.pbArray`
//  field stores an array of `PBClass` instances. The name "pb" comes from
//  FFmpeg's `AVFormatContext.pb` field convention.
//
//  Binary fields (3) per TranscodeIO.md:
//    1. pb:         UnsafeMutablePointer<AVIOContext>?  -- wrapped FFmpeg I/O context
//    2. _bytesRead: Int64                               -- cumulative bytes read
//    3. add:        Int64                               -- delta since last speed calc
//

import Foundation
import Libavformat

public final class PBClass {
    /// RE: Forward field 1 of 3.
    public private(set) var pb: UnsafeMutablePointer<AVIOContext>?

    /// RE: Forward field 2 of 3 -- cumulative bytes read through this I/O
    /// context. Consumed by `DynamicInfo.bytesReadBlock` for network speed
    /// calculation. Underscored to match the binary field name `_bytesRead`.
    public private(set) var _bytesRead: Int64 = 0

    /// RE: Forward field 3 of 3 -- incremental byte count since the last speed
    /// calculation. The bandwidth formula is
    /// `networkSpeed = add / elapsed`, after which `add` is zeroed and
    /// `_bytesRead` continues accumulating.
    public private(set) var add: Int64 = 0

    /// Source-compat alias for the previous `bytesRead` accessor.
    public var bytesRead: Int64 { _bytesRead }

    private var lastSpeedCheck: CFTimeInterval = 0
    private let buffer: UnsafeMutablePointer<UInt8>

    /// Computed network speed in bytes/second based on the `add` delta since
    /// the last speed check. Non-destructive (does not zero `add`).
    public var networkSpeed: Double {
        let now = CACurrentMediaTime()
        let elapsed = now - lastSpeedCheck
        guard elapsed > 0 else { return 0 }
        return Double(add) / elapsed
    }

    /// Creates an AVIOContext via avio_alloc_context.
    ///
    /// - Parameters:
    ///   - bufferSize: Internal buffer size (default 32KB)
    ///   - readPacket: C-convention read callback
    ///   - writePacket: C-convention write callback (nil for read-only)
    ///   - seek: C-convention seek callback
    public init(bufferSize: Int32 = 32768,
                readPacket: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int32) -> Int32)?,
                writePacket: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<UInt8>?, Int32) -> Int32)?,
                seek: (@convention(c) (UnsafeMutableRawPointer?, Int64, Int32) -> Int64)?) {
        let buf = av_malloc(Int(bufferSize))!.assumingMemoryBound(to: UInt8.self)
        self.buffer = buf
        let writeFlag: Int32 = writePacket != nil ? 1 : 0
        self.pb = avio_alloc_context(
            buf,
            bufferSize,
            writeFlag,
            nil, // opaque — caller should set via pb.pointee.opaque if needed
            readPacket,
            writePacket,
            seek
        )
        self.lastSpeedCheck = CACurrentMediaTime()
    }

    /// Refreshes `_bytesRead` from the underlying `AVIOContext` and updates
    /// the `add` delta against the prior cumulative reading.
    public func updateBytesRead() {
        guard let pb else { return }
        let newTotal = pb.pointee.bytes_read
        add &+= max(0, newTotal - _bytesRead)
        _bytesRead = newTotal
    }

    /// Calculates current speed and resets the measurement window.
    /// - Returns: Bytes per second since the last call to `calculateSpeed()`.
    public func calculateSpeed() -> Double {
        let now = CACurrentMediaTime()
        let elapsed = now - lastSpeedCheck
        guard elapsed > 0 else { return 0 }
        let speed = Double(add) / elapsed
        add = 0
        lastSpeedCheck = now
        return speed
    }

    deinit {
        if pb != nil {
            avio_context_free(&pb)
        }
    }
}
