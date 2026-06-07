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
//  Binary fields (3) per TranscodeIO.md (offsets instruction-verified in
//  MEPlayerItem_updatePBArrayProgress @ 0x10142d174):
//    1. pb:         UnsafeMutablePointer<AVIOContext>?  -- wrapped FFmpeg I/O context (self+0x10)
//    2. _bytesRead: Int64                               -- last-seen bytes_read snapshot (self+0x18)
//    3. add:        Int64                               -- accumulated carry from prior resets (self+0x20)
//

import Foundation
import Libavformat

public final class PBClass {
    /// The wrapped FFmpeg I/O context. Optional to allow PBClass to exist before
    /// the AVIO context is opened and after it is closed.
    /// RE: self+0x10 (loaded at 0x10142d38c: ldr x8,[x24,#0x10], 1.3.15)
    public private(set) var pb: UnsafeMutablePointer<AVIOContext>?

    /// Last-seen `AVIOContext.bytes_read` snapshot for this I/O context.
    /// Consumed by `DynamicInfo.bytesReadBlock` for network speed calculation.
    /// Underscored to match the binary field name `_bytesRead`.
    /// RE: self+0x18 (0x10142d398/0x10142d3b4, 1.3.15)
    public private(set) var _bytesRead: Int64 = 0

    /// Accumulated carry from prior `bytes_read` resets. When the AVIO context
    /// is reopened/reset and the live counter goes backwards, the pre-reset
    /// total is carried forward into `add` so cumulative byte accounting is
    /// preserved across resets.
    /// RE: self+0x20 (0x10142d3a4-0x10142d3b0, 1.3.15)
    public private(set) var add: Int64 = 0

    /// Source-compat: wraps an existing AVIOContext pointer. The binary's PBClass
    /// does not call `avio_alloc_context` itself — the AVIOContext is created by
    /// FFmpeg's own `io_open` path and PBClass wraps the result for teardown
    /// tracking via `MEPlayerItem.pbArray`.
    /// RE: 0x10143d77c (PBClass_initFromCacheEntry, 1.3.15) — the genuine init
    /// path wraps an already-opened context.
    public init(pb: UnsafeMutablePointer<AVIOContext>? = nil) {
        self.pb = pb
    }

    /// Refreshes `_bytesRead` from the underlying `AVIOContext` and updates
    /// the `add` accumulator. When the AVIO context is reopened/reset (live
    /// counter goes backwards), the pre-reset `_bytesRead` is carried forward
    /// into `add` to preserve cumulative byte accounting.
    /// RE: 0x10142d174 (MEPlayerItem_updatePBArrayProgress per-PBClass loop, 1.3.15)
    public func updateBytesRead() {
        guard let pb else { return }
        let live = pb.pointee.bytes_read
        if live < _bytesRead {
            // AVIO context was reopened/reset — carry the pre-reset total forward.
            // Binary: add += _bytesRead (0x10142d3a4-0x10142d3b0)
            add &+= _bytesRead
        }
        _bytesRead = live
    }

    /// Returns the total bytes read for this context: `add + _bytesRead`.
    /// This is the per-PBClass value pushed into the temp array by
    /// MEPlayerItem_updatePBArrayProgress before the grand-total sum.
    /// RE: 0x10142d3c0 (add load) + 0x10142d3cc (add + bytes_read), 1.3.15
    public var totalBytesRead: Int64 {
        add &+ _bytesRead
    }

    deinit {
        // The AVIOContext lifetime is managed by FFmpeg's io_close2 path
        // (customIOClose trampoline installed by MEPlayerItem_openAndFindStream).
        // PBClass is a tracking wrapper; it does not own the context's allocation.
        pb = nil
    }
}
