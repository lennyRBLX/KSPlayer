//
//  CacheFileEntry.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 (TranscodeIO.md)
//
//  Represents a single cached segment of downloaded data. Maps logical file
//  positions to physical positions in the on-disk cache file.
//
//  Binary class metadata: _TtC16PreLoadIOContext14CacheFileEntry
//  (Plain "CacheFileEntry" string @ 0x102ef6828, mangled @ 0x103343840.)
//
//  Binary fields (5) per TranscodeIO.md:
//    1. logicalPos:  Int64    -- byte offset in the original media file
//    2. physicalPos: UInt64   -- byte offset in the local cache file on disk
//    3. size:        UInt32   -- number of cached bytes in this segment
//    4. eof:         Bool     -- true if this entry extends to end of source
//    5. maxSize:     UInt32?  -- optional size cap (set by LimitCacheIOContext)
//
//  Cache segments stored at NSTemporaryDirectory()/videoCaches/<md5>/<position>.
//

import Foundation

public class CacheFileEntry {
    // MARK: - RE-verified binary fields (5)

    /// RE: Forward field 1 of 5 -- byte offset in the original media file.
    public let logicalPos: Int64

    /// RE: Forward field 2 of 5 -- byte offset in the local cache file on disk.
    public let physicalPos: UInt64

    /// RE: Forward field 3 of 5 -- number of cached bytes in this segment.
    /// UInt32 caps individual segments at ~4 GB; the cache system splits large
    /// files into multiple entries.
    public private(set) var size: UInt32

    /// RE: Forward field 4 of 5 -- true if this entry extends to the end of the
    /// source file. Optimizes EOF detection without a separate size query.
    public var eof: Bool

    /// RE: Forward field 5 of 5 -- optional maximum size cap. When set (e.g. by
    /// `LimitCacheIOContext` with 512 MiB cap), prevents unbounded growth.
    public var maxSize: UInt32?

    // MARK: - Implementation helpers (file-handle layer)
    //
    // The on-disk URL and FileHandle are implementation helpers used by
    // CacheIOContext to read/write segment data. They are not part of the
    // binary class layout; CacheFileEntry on the binary is a value-descriptor
    // and the FileHandle equivalent lives on the parent CacheIOContext.

    public let url: URL
    private var fileHandle: FileHandle?

    // MARK: - Init

    public init(url: URL,
                logicalPos: Int64 = 0,
                physicalPos: UInt64 = 0,
                size: UInt32 = 0,
                eof: Bool = false,
                maxSize: UInt32? = nil) {
        self.url = url
        self.logicalPos = logicalPos
        self.physicalPos = physicalPos
        self.size = size
        self.eof = eof
        self.maxSize = maxSize
    }

    // MARK: - Range queries

    public func contains(position: Int64) -> Bool {
        position >= logicalPos && position < logicalPos + Int64(size)
    }

    public var endPosition: Int64 {
        logicalPos + Int64(size)
    }

    public func grow(by count: UInt32) {
        if let cap = maxSize {
            size = min(size + count, cap)
        } else {
            size = size &+ count
        }
    }

    // MARK: - Legacy accessor shims
    //
    // CacheIOContext.swift was written against an Int64 `getPosition` /
    // `getSize` API. Keep those shims so the call sites still compile while the
    // class header now matches the binary's UInt32/Int64 typing.

    public func getPosition() -> Int64 { logicalPos }
    public func setPosition(_ pos: Int64) {
        // Position is immutable in the binary class layout (let-bound logicalPos).
        // The setter here is a no-op kept for source compatibility with the
        // earlier API; callers should construct a new entry instead.
        precondition(pos == logicalPos, "CacheFileEntry.logicalPos is immutable; construct a new entry")
    }
    public func getSize() -> Int64 { Int64(size) }
    public func setSize(_ newSize: Int64) {
        size = UInt32(clamping: max(newSize, 0))
    }

    // MARK: - File-handle management

    public func ensureFileHandle() throws {
        guard fileHandle == nil else { return }
        try openFileHandle()
    }

    public func openFileHandle() throws {
        let path = url.path
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        fileHandle = try FileHandle(forUpdating: url)
    }

    public func closeHandle() {
        try? fileHandle?.close()
        fileHandle = nil
    }

    // MARK: - Read/Write

    public func readData(at offset: Int64, length: Int) -> Data? {
        guard let handle = fileHandle else { return nil }
        handle.seek(toFileOffset: UInt64(offset))
        let data = handle.readData(ofLength: length)
        return data.isEmpty ? nil : data
    }

    public func writeData(_ data: Data, at offset: Int64) {
        guard let handle = fileHandle else { return }
        handle.seek(toFileOffset: UInt64(offset))
        handle.write(data)
        let newEnd = UInt32(clamping: offset + Int64(data.count))
        if newEnd > size {
            size = newEnd
        }
    }

    public func loadResource() -> Data? {
        guard let handle = fileHandle else { return nil }
        handle.seek(toFileOffset: 0)
        return handle.readDataToEndOfFile()
    }

    public func updateSize() {
        guard let handle = fileHandle else { return }
        let currentOffset = handle.offsetInFile
        handle.seekToEndOfFile()
        size = UInt32(clamping: handle.offsetInFile)
        handle.seek(toFileOffset: currentOffset)
    }

    public static func sumSizes(_ entries: [CacheFileEntry]) -> Int64 {
        entries.reduce(0) { $0 + Int64($1.size) }
    }

    public func deallocate() {
        closeHandle()
        try? FileManager.default.removeItem(at: url)
    }

    deinit {
        closeHandle()
    }
}
