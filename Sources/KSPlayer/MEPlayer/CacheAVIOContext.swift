//
//  CacheAVIOContext.swift
//  KSPlayer
//
//  Forward addition (RE/40, RE/68): Progressive download cache with
//  on-disk segment storage. Subclasses AbstractAVIOContext to provide
//  transparent caching of network media reads.
//
//  Hierarchy:
//    CacheAVIOContext         — Core cache with HTTP range requests
//      LimitCacheAVIOContext  — 512MB max per file
//        PreLoadAVIOContext   — Moov protection (10MB), preload scheduling
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

// MARK: - CacheFileSegment

/// Represents a contiguous cached byte range on disk.
final class CacheFileSegment {
    let logicalPosition: Int64
    let filePath: URL
    private(set) var size: Int64
    private var fileHandle: FileHandle?

    init(logicalPosition: Int64, filePath: URL, size: Int64 = 0) {
        self.logicalPosition = logicalPosition
        self.filePath = filePath
        self.size = size
    }

    func contains(position: Int64) -> Bool {
        position >= logicalPosition && position < logicalPosition + size
    }

    func read(at offset: Int64, length: Int) -> Data? {
        guard let handle = try? openForReading() else { return nil }
        handle.seek(toFileOffset: UInt64(offset))
        return handle.readData(ofLength: length)
    }

    func append(_ data: Data) {
        guard let handle = try? openForWriting() else { return }
        handle.seekToEndOfFile()
        handle.write(data)
        size += Int64(data.count)
    }

    private func openForReading() throws -> FileHandle {
        if let existing = fileHandle { return existing }
        let handle = try FileHandle(forReadingFrom: filePath)
        fileHandle = handle
        return handle
    }

    private func openForWriting() throws -> FileHandle {
        if let existing = fileHandle { return existing }
        if !FileManager.default.fileExists(atPath: filePath.path) {
            FileManager.default.createFile(atPath: filePath.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: filePath)
        fileHandle = handle
        return handle
    }

    func close() {
        try? fileHandle?.close()
        fileHandle = nil
    }

    deinit { close() }
}

// MARK: - CacheAVIOContext

/// Disk-caching AVIO layer for progressive download of network media.
/// Thread-safe via NSRecursiveLock. Each segment maps a byte range to a file.
///
/// Disk layout: NSTemporaryDirectory()/videoCaches/<md5(url)>/<position>
open class CacheAVIOContext: AbstractAVIOContext {
    private(set) var segments: [CacheFileSegment] = []
    private let cacheDirectory: URL
    private var totalFileSize: Int64 = 0
    private var position: Int64 = 0
    private let chunkSize: Int = 9728  // ~9.5KB per read (RE/40)
    private let lock = NSRecursiveLock()
    private let sourceURL: URL
    private let urlSession = URLSession(configuration: .default)

    public init(url: URL) {
        self.sourceURL = url
        let md5 = Self.md5Hash(url.absoluteString)
        let tempDir = FileManager.default.temporaryDirectory
        self.cacheDirectory = tempDir.appendingPathComponent("videoCaches/\(md5)", isDirectory: true)
        super.init(bufferSize: 32 * 1024, writable: false)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        loadExistingSegments()
    }

    // MARK: - AbstractAVIOContext overrides

    override open func read(buffer: UnsafePointer<UInt8>?, size: Int32) -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        let length = Int(size)

        if let segment = findSegment(containing: position) {
            let offset = position - segment.logicalPosition
            let available = min(Int64(length), segment.size - offset)
            guard let data = segment.read(at: offset, length: Int(available)) else {
                return -1
            }
            if let buffer = UnsafeMutablePointer(mutating: buffer) {
                data.copyBytes(to: buffer, count: data.count)
            }
            position += Int64(data.count)
            return Int32(data.count)
        } else {
            guard let data = downloadChunk(from: position, length: length) else {
                return -1
            }
            storeData(data, at: position)
            if let buffer = UnsafeMutablePointer(mutating: buffer) {
                data.copyBytes(to: buffer, count: data.count)
            }
            position += Int64(data.count)
            return Int32(data.count)
        }
    }

    override open func seek(offset: Int64, whence: Int32) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        switch whence {
        case 0: // SEEK_SET
            position = offset
        case 1: // SEEK_CUR
            position += offset
        case 2: // SEEK_END
            if totalFileSize > 0 {
                position = totalFileSize + offset
            }
        default:
            break
        }
        return position
    }

    override open func fileSize() -> Int64 {
        totalFileSize
    }

    override open func close() {
        lock.lock()
        defer { lock.unlock() }
        segments.forEach { $0.close() }
    }

    // MARK: - Cache lookup

    private func findSegment(containing pos: Int64) -> CacheFileSegment? {
        segments.first { $0.contains(position: pos) }
    }

    private func findOrCreateSegment(at pos: Int64) -> CacheFileSegment {
        if let existing = segments.last(where: { $0.logicalPosition + $0.size == pos }) {
            return existing
        }
        let segmentFile = cacheDirectory.appendingPathComponent("\(pos)")
        let segment = CacheFileSegment(logicalPosition: pos, filePath: segmentFile)
        segments.append(segment)
        segments.sort { $0.logicalPosition < $1.logicalPosition }
        return segment
    }

    // MARK: - Download

    private func downloadChunk(from offset: Int64, length: Int) -> Data? {
        var request = URLRequest(url: sourceURL)
        let end = offset + Int64(min(length, chunkSize)) - 1
        request.setValue("bytes=\(offset)-\(end)", forHTTPHeaderField: "Range")

        var result: Data?
        let semaphore = DispatchSemaphore(value: 0)

        let task = urlSession.dataTask(with: request) { [weak self] data, response, _ in
            result = data
            if let httpResponse = response as? HTTPURLResponse,
               let rangeHeader = httpResponse.value(forHTTPHeaderField: "Content-Range"),
               let totalStr = rangeHeader.components(separatedBy: "/").last,
               let total = Int64(totalStr) {
                self?.totalFileSize = total
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        return result
    }

    private func storeData(_ data: Data, at pos: Int64) {
        let segment = findOrCreateSegment(at: pos)
        segment.append(data)
    }

    // MARK: - Disk management

    private func loadExistingSegments() {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: cacheDirectory,
                                                                          includingPropertiesForKeys: [.fileSizeKey]) else { return }
        for fileURL in contents {
            guard let pos = Int64(fileURL.lastPathComponent) else { continue }
            let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            let size = Int64(attrs?.fileSize ?? 0)
            segments.append(CacheFileSegment(logicalPosition: pos, filePath: fileURL, size: size))
        }
        segments.sort { $0.logicalPosition < $1.logicalPosition }
    }

    public func purge() {
        close()
        try? FileManager.default.removeItem(at: cacheDirectory)
        segments.removeAll()
    }

    private static func md5Hash(_ string: String) -> String {
        #if canImport(CryptoKit)
        let data = Data(string.utf8)
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        return string.hashValue.description
        #endif
    }
}

// MARK: - LimitCacheAVIOContext

/// 512MB max cache per file (RE/40: maxSize = 0x20000000).
open class LimitCacheAVIOContext: CacheAVIOContext {
    let maxSize: Int64 = 512 * 1024 * 1024

    override open func read(buffer: UnsafePointer<UInt8>?, size: Int32) -> Int32 {
        let totalCached = segments.reduce(Int64(0)) { $0 + $1.size }
        if totalCached >= maxSize {
            while segments.count > 1 && segments.reduce(Int64(0), { $0 + $1.size }) >= maxSize {
                let oldest = segments.removeFirst()
                oldest.close()
                try? FileManager.default.removeItem(at: oldest.filePath)
            }
        }
        return super.read(buffer: buffer, size: size)
    }
}

// MARK: - PreLoadAVIOContext

/// Moov protection (10MB) and preload scheduling (RE/40).
public final class PreLoadAVIOContext: LimitCacheAVIOContext {
    let moovProtectionSize: Int64 = 10 * 1024 * 1024

    /// Ensure the moov atom region (first 10MB) is cached for fast seeking.
    public func ensureMoovCached() {
        guard totalFileSize > 0 else { return }
        let moovEnd = min(moovProtectionSize, totalFileSize)
        let isCached = segments.contains { $0.logicalPosition == 0 && $0.size >= moovEnd }
        if !isCached {
            let saved = position
            _ = seek(offset: 0, whence: 0)
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(moovEnd))
            defer { buf.deallocate() }
            _ = read(buffer: buf, size: Int32(moovEnd))
            _ = seek(offset: saved, whence: 0)
        }
    }
}
