//
//  CacheFileEntry.swift
//  KSPlayer
//
//  Forward addition (RE/40, RE/68): File-level cache entry with handle
//  management for on-disk segment storage. Used by the cache hierarchy
//  to manage individual cached file segments.
//
//  Binary: _TtC16PreLoadIOContext14CacheFileEntry (22 functions)
//  Binary module: PreLoadIOContext (kept under KSPlayer in source)
//  RE source: Forward v1.3.15
//

import Foundation

public class CacheFileEntry {
    // MARK: - Properties

    public let url: URL
    public private(set) var position: Int64 = 0
    public private(set) var size: Int64 = 0
    private var multipleRequests: Bool = false
    private var fileHandle: FileHandle?

    // MARK: - Init (RE: CacheFileEntry_ensureFileHandle @ 0x10156603c)

    public init(url: URL, multipleRequests: Bool = false) {
        self.url = url
        self.multipleRequests = multipleRequests
    }

    // MARK: - Position/Size Accessors (RE: 0x101565fc4, 0x101565fd8, 0x101564e18, 0x101564e6c)

    public func getPosition() -> Int64 {
        position
    }

    public func setPosition(_ pos: Int64) {
        position = pos
    }

    public func getSize() -> Int64 {
        size
    }

    public func setSize(_ newSize: Int64) {
        size = newSize
    }

    // MARK: - File Handle Management (RE: 0x101565b1c, 0x10156603c, 0x100015204, 0x10010aac4)

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

    // MARK: - Read/Write (RE: CacheFileEntry_readData @ 0x101565cf8, CacheFileEntry_writeData @ 0x101571f0c)

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
        let newEnd = offset + Int64(data.count)
        if newEnd > size {
            size = newEnd
        }
    }

    // MARK: - Load Resource (RE: CacheFileEntry_loadResource @ 0x1015658ec)

    public func loadResource() -> Data? {
        guard let handle = fileHandle else { return nil }
        handle.seek(toFileOffset: 0)
        return handle.readDataToEndOfFile()
    }

    // MARK: - Update Size (RE: CacheFileEntry_updateSize @ 0x101565a78)

    public func updateSize() {
        guard let handle = fileHandle else { return }
        let currentOffset = handle.offsetInFile
        handle.seekToEndOfFile()
        size = Int64(handle.offsetInFile)
        handle.seek(toFileOffset: currentOffset)
    }

    // MARK: - Sum Sizes (RE: CacheFileEntry_sumSizes @ 0x100598c28)

    public static func sumSizes(_ entries: [CacheFileEntry]) -> Int64 {
        entries.reduce(0) { $0 + $1.size }
    }

    // MARK: - Deallocate (RE: CacheFileEntry_deallocate @ 0x101565de0)

    public func deallocate() {
        closeHandle()
        try? FileManager.default.removeItem(at: url)
    }

    deinit {
        closeHandle()
    }
}
