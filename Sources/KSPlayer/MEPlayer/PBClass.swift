//
//  PBClass.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — binary address 0x101321cac
//  FFmpeg AVIO context wrapper with bandwidth tracking.
//  The name "pb" comes from FFmpeg's AVFormatContext.pb field.
//

import Foundation
import Libavformat

public final class PBClass {
    public private(set) var pb: UnsafeMutablePointer<AVIOContext>?
    public private(set) var bytesRead: Int64 = 0
    private var lastBytesRead: Int64 = 0
    private var lastSpeedCheck: CFTimeInterval = 0
    private let buffer: UnsafeMutablePointer<UInt8>

    /// Computed network speed in bytes/second based on delta since last check.
    public var networkSpeed: Double {
        let now = CACurrentMediaTime()
        let elapsed = now - lastSpeedCheck
        guard elapsed > 0 else { return 0 }
        let delta = Double(bytesRead - lastBytesRead)
        return delta / elapsed
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

    /// Updates bytesRead from the underlying AVIOContext.
    public func updateBytesRead() {
        guard let pb else { return }
        bytesRead = pb.pointee.bytes_read
    }

    /// Calculates current speed and resets the measurement window.
    /// - Returns: Bytes per second since the last call to calculateSpeed().
    public func calculateSpeed() -> Double {
        let now = CACurrentMediaTime()
        let elapsed = now - lastSpeedCheck
        guard elapsed > 0 else { return 0 }
        let delta = Double(bytesRead - lastBytesRead)
        let speed = delta / elapsed
        lastBytesRead = bytesRead
        lastSpeedCheck = now
        return speed
    }

    deinit {
        if pb != nil {
            avio_context_free(&pb)
        }
    }
}
