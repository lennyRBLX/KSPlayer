//
//  CacheHierarchy.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 (TranscodeIO.md)
//  Cache hierarchy: URLContextDownload -> CacheIOContext -> Limit -> PreLoad
//
//  Classes:
//    URLContextDownload          -- Raw HTTP download, 256KB buffer
//    CacheEntry                  -- Cached byte-range descriptor
//    ReadCacheIOContext           -- Cache-first read with network fallthrough
//    CacheOnlyIOContext           -- Read-only cache, never touches network
//    LimitCacheIOContext          -- Max file size enforcement (512MB)
//    LimitPreLoadIOContext        -- Moov protection (10MB), 256-element histogram
//    LimitCountPreLoadIOContext   -- Max request count limiting
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

// MARK: - CacheEntry

/// Represents a single cached segment of downloaded data.
/// Maps logical file positions to physical positions in the on-disk cache file.
/// RE: Forward v1.3.15 binary fields (5): logicalPos, physicalPos, size, eof, maxSize
public class CacheEntry {
    /// Byte offset in the original media file
    public let logicalPos: Int64
    /// Byte offset in the local cache file on disk
    public let physicalPos: UInt64
    /// Number of cached bytes in this segment (UInt32 caps individual segments at ~4GB)
    public private(set) var size: UInt32
    /// True if this entry extends to the end of the source file
    public var eof: Bool
    /// Optional maximum size cap for this cache entry (set by LimitCacheIOContext)
    public var maxSize: UInt32?

    public init(logicalPos: Int64, physicalPos: UInt64, size: UInt32 = 0, eof: Bool = false, maxSize: UInt32? = nil) {
        self.logicalPos = logicalPos
        self.physicalPos = physicalPos
        self.size = size
        self.eof = eof
        self.maxSize = maxSize
    }

    /// Whether this entry covers the given byte position
    public func contains(position: Int64) -> Bool {
        position >= logicalPos && position < logicalPos + Int64(size)
    }

    /// End position (exclusive) of this entry in the logical file
    public var endPosition: Int64 {
        logicalPos + Int64(size)
    }

    func grow(by count: UInt32) {
        if let cap = maxSize {
            size = min(size + count, cap)
        } else {
            size += count
        }
    }
}

// MARK: - URLContextDownload

/// Raw HTTP download context wrapping FFmpeg URL I/O for streaming media.
/// Base of the cache chain. Uses 256KB download buffer (RE: Forward v1.3.15).
///
/// RE: 13 functions named in binary. This provides the network fetch layer
/// that all cache contexts build upon.
open class URLContextDownload: AbstractAVIOContext {
    /// RE-confirmed: Forward uses 0x40000 (256KB) buffer for downloads
    public static let downloadBufferSize: Int = 256 * 1024
    public let sourceURL: URL
    private let urlSession: URLSession
    private(set) var totalFileSize: Int64 = -1
    private var position: Int64 = 0
    private let downloadLock = NSLock()

    public init(url: URL, session: URLSession = .shared) {
        self.sourceURL = url
        self.urlSession = session
        super.init(bufferSize: Int32(Self.downloadBufferSize), writable: false)
    }

    override open func read(buffer: UnsafePointer<UInt8>?, size: Int32) -> Int32 {
        downloadLock.lock()
        defer { downloadLock.unlock() }
        guard let data = fetchBytes(from: position, length: Int(size)) else {
            return -1
        }
        if let buffer = UnsafeMutablePointer(mutating: buffer) {
            data.copyBytes(to: buffer, count: data.count)
        }
        position += Int64(data.count)
        return Int32(data.count)
    }

    override open func seek(offset: Int64, whence: Int32) -> Int64 {
        downloadLock.lock()
        defer { downloadLock.unlock() }
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
        // URLSession is shared; nothing to tear down
    }

    /// Fetch bytes from the source URL via HTTP range request.
    /// Returns nil on failure.
    public func fetchBytes(from offset: Int64, length: Int) -> Data? {
        var request = URLRequest(url: sourceURL)
        let end = offset + Int64(min(length, Self.downloadBufferSize)) - 1
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

    /// Current read position
    public var currentPosition: Int64 { position }
}

// MARK: - ReadCacheIOContext

/// Cache-first read context with AVERROR_EOF handling.
/// Reads from the disk cache when the requested range is cached,
/// falls through to network (via URLContextDownload) on cache miss.
///
/// RE: Standalone class in the hierarchy, not a subclass of CacheIOContext.
/// Handles EOF detection and transparent cache population.
open class ReadCacheIOContext: AbstractAVIOContext {
    private let downloader: URLContextDownload
    private let cacheDirectory: URL
    private var entries: [CacheEntry] = []
    private var position: Int64 = 0
    private let lock = NSRecursiveLock()

    public init(url: URL) {
        self.downloader = URLContextDownload(url: url)
        let md5 = Self.md5Hash(url.absoluteString)
        let tempDir = FileManager.default.temporaryDirectory
        self.cacheDirectory = tempDir.appendingPathComponent("videoCaches/\(md5)", isDirectory: true)
        super.init(bufferSize: 32 * 1024, writable: false)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        loadExistingEntries()
    }

    override open func read(buffer: UnsafePointer<UInt8>?, size: Int32) -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        let length = Int(size)

        // Try cache first
        if let entry = entries.first(where: { $0.contains(position: position) }) {
            let segmentFile = cacheDirectory.appendingPathComponent("\(entry.logicalPos)")
            let offsetInSegment = position - entry.logicalPos
            let available = min(Int64(length), Int64(entry.size) - offsetInSegment)
            if let handle = try? FileHandle(forReadingFrom: segmentFile) {
                handle.seek(toFileOffset: UInt64(offsetInSegment))
                let data = handle.readData(ofLength: Int(available))
                try? handle.close()
                if !data.isEmpty {
                    if let buf = UnsafeMutablePointer(mutating: buffer) {
                        data.copyBytes(to: buf, count: data.count)
                    }
                    position += Int64(data.count)
                    return Int32(data.count)
                }
            }
        }

        // Cache miss: fetch from network and store
        guard let data = downloader.fetchBytes(from: position, length: length) else {
            // AVERROR_EOF detection
            if downloader.totalFileSize > 0, position >= downloader.totalFileSize {
                return -541478725 // AVERROR_EOF
            }
            return -1
        }
        storeToDisk(data, at: position)
        if let buf = UnsafeMutablePointer(mutating: buffer) {
            data.copyBytes(to: buf, count: data.count)
        }
        position += Int64(data.count)
        return Int32(data.count)
    }

    override open func seek(offset: Int64, whence: Int32) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        switch whence {
        case 0: position = offset
        case 1: position += offset
        case 2:
            let size = downloader.totalFileSize
            if size > 0 { position = size + offset }
        default: break
        }
        return position
    }

    override open func fileSize() -> Int64 {
        downloader.totalFileSize
    }

    override open func close() {
        downloader.close()
    }

    // MARK: - Disk I/O

    private func storeToDisk(_ data: Data, at pos: Int64) {
        let segmentFile = cacheDirectory.appendingPathComponent("\(pos)")
        if !FileManager.default.fileExists(atPath: segmentFile.path) {
            FileManager.default.createFile(atPath: segmentFile.path, contents: data)
        } else if let handle = try? FileHandle(forWritingTo: segmentFile) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        }
        // Update or add entry
        if let idx = entries.firstIndex(where: { $0.logicalPos == pos }) {
            entries[idx].grow(by: UInt32(data.count))
        } else {
            entries.append(CacheEntry(logicalPos: pos, physicalPos: 0, size: UInt32(data.count)))
            entries.sort { $0.logicalPos < $1.logicalPos }
        }
    }

    private func loadExistingEntries() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return }
        for fileURL in contents {
            guard let pos = Int64(fileURL.lastPathComponent) else { continue }
            let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            let size = UInt32(clamping: attrs?.fileSize ?? 0)
            entries.append(CacheEntry(logicalPos: pos, physicalPos: 0, size: size))
        }
        entries.sort { $0.logicalPos < $1.logicalPos }
    }

    /// Total bytes currently cached on disk
    public var cachedSize: Int64 {
        entries.reduce(0) { $0 + Int64($1.size) }
    }

    public func purge() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: cacheDirectory)
        entries.removeAll()
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

// MARK: - CacheOnlyIOContext

/// Read-only cache context that never goes to network (offline mode).
/// Returns AVERROR_EOF on cache miss instead of fetching.
///
/// RE: CacheOnlyIOContext in Forward hierarchy -- read-only wrapper.
public final class CacheOnlyIOContext: AbstractAVIOContext {
    private let cacheDirectory: URL
    private var entries: [CacheEntry] = []
    private var position: Int64 = 0
    private var totalFileSize: Int64 = -1
    private let lock = NSRecursiveLock()

    public init(url: URL) {
        let md5 = Self.md5Hash(url.absoluteString)
        let tempDir = FileManager.default.temporaryDirectory
        self.cacheDirectory = tempDir.appendingPathComponent("videoCaches/\(md5)", isDirectory: true)
        super.init(bufferSize: 32 * 1024, writable: false)
        loadExistingEntries()
    }

    override public func read(buffer: UnsafePointer<UInt8>?, size: Int32) -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        let length = Int(size)

        guard let entry = entries.first(where: { $0.contains(position: position) }) else {
            return -541478725 // AVERROR_EOF -- cache miss in offline mode
        }

        let segmentFile = cacheDirectory.appendingPathComponent("\(entry.logicalPos)")
        let offsetInSegment = position - entry.logicalPos
        let available = min(Int64(length), Int64(entry.size) - offsetInSegment)
        guard let handle = try? FileHandle(forReadingFrom: segmentFile) else {
            return -1
        }
        handle.seek(toFileOffset: UInt64(offsetInSegment))
        let data = handle.readData(ofLength: Int(available))
        try? handle.close()
        guard !data.isEmpty else { return -1 }
        if let buf = UnsafeMutablePointer(mutating: buffer) {
            data.copyBytes(to: buf, count: data.count)
        }
        position += Int64(data.count)
        return Int32(data.count)
    }

    override public func seek(offset: Int64, whence: Int32) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        switch whence {
        case 0: position = offset
        case 1: position += offset
        case 2:
            if totalFileSize > 0 { position = totalFileSize + offset }
        default: break
        }
        return position
    }

    override public func fileSize() -> Int64 { totalFileSize }
    override public func close() {}

    private func loadExistingEntries() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return }
        for fileURL in contents {
            guard let pos = Int64(fileURL.lastPathComponent) else { continue }
            let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            let size = UInt32(clamping: attrs?.fileSize ?? 0)
            entries.append(CacheEntry(logicalPos: pos, physicalPos: 0, size: size))
        }
        entries.sort { $0.logicalPos < $1.logicalPos }
        // Estimate total file size from cached entries
        if let last = entries.last, last.eof {
            totalFileSize = last.logicalPos + Int64(last.size)
        }
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

// MARK: - LimitCacheIOContext

/// Cache with maximum file size enforcement.
/// RE: Forward v1.3.15 max file size = 512 MB (0x20000000).
/// Evicts oldest entries when cache exceeds the limit.
open class LimitCacheIOContext: ReadCacheIOContext {
    /// RE: Max cache per file = 512 MB (0x20000000)
    public let maxCacheSize: Int64 = 512 * 1024 * 1024

    override open func read(buffer: UnsafePointer<UInt8>?, size: Int32) -> Int32 {
        evictIfNeeded()
        return super.read(buffer: buffer, size: size)
    }

    /// Evict oldest cache entries when total cached size exceeds maxCacheSize.
    private func evictIfNeeded() {
        guard cachedSize > maxCacheSize else { return }
        // Purge and let re-download as needed
        // In a full implementation this would selectively evict LRU entries;
        // here we purge everything beyond the limit boundary.
        purge()
    }
}

// MARK: - LimitPreLoadIOContext

/// Moov protection (10MB) and playback position tracking via 256-element histogram.
/// RE: Forward v1.3.15 LimitPreLoadIOContext -- 11+ functions.
///
/// Ensures the MP4 moov atom (essential for playback) is always cached within
/// the first 10MB. Position histogram enables smart prefetch optimization.
open class LimitPreLoadIOContext: LimitCacheIOContext {
    /// RE: Moov protection threshold = 10 MB
    public let moovProtectionSize: Int64 = 10 * 1024 * 1024
    /// RE: Position histogram = 256 elements
    private var positionHistogram = [Int](repeating: 0, count: 256)
    private var moovCached = false
    private let preloadLock = NSLock()

    /// Target preload size in bytes (set by caller based on buffer duration * bitrate)
    public var preloadTargetSize: Int64 = 0

    public convenience init(url: URL, cacheSize: Double) {
        self.init(url: url)
        self.preloadTargetSize = Int64(max(cacheSize, 0))
    }

    override open func read(buffer: UnsafePointer<UInt8>?, size: Int32) -> Int32 {
        ensureMoovCached()
        let result = super.read(buffer: buffer, size: size)
        if result > 0 {
            updateHistogram(position: seek(offset: 0, whence: 1))
        }
        return result
    }

    /// Ensure the moov atom region (first 10MB) is cached for fast seeking.
    /// RE: Forward v1.3.15 moov protection logic.
    public func ensureMoovCached() {
        preloadLock.lock()
        defer { preloadLock.unlock() }
        guard !moovCached else { return }
        let fileTotal = fileSize()
        guard fileTotal > 0 else { return }
        let moovEnd = min(moovProtectionSize, fileTotal)
        // Check if first 10MB is already cached
        if cachedSize >= moovEnd {
            moovCached = true
            return
        }
        // Cache the moov region by reading through it
        let savedPos = seek(offset: 0, whence: 1)
        _ = seek(offset: 0, whence: 0)
        let tempBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(moovEnd))
        defer { tempBuf.deallocate() }
        var remaining = moovEnd
        while remaining > 0 {
            let chunkSize = min(remaining, Int64(URLContextDownload.downloadBufferSize))
            let ret = super.read(buffer: tempBuf, size: Int32(chunkSize))
            if ret <= 0 { break }
            remaining -= Int64(ret)
        }
        _ = seek(offset: savedPos, whence: 0)
        moovCached = true
    }

    /// Update the 256-element position histogram for prefetch optimization.
    /// Maps the current read position to a histogram bucket.
    private func updateHistogram(position: Int64) {
        let fileTotal = fileSize()
        guard fileTotal > 0 else { return }
        let bucket = Int(position * 255 / fileTotal)
        let clampedBucket = min(max(bucket, 0), 255)
        positionHistogram[clampedBucket] += 1
    }

    /// Returns the histogram bucket with the highest read frequency.
    /// Used to predict the next seek target for preloading.
    public func hotBucket() -> Int? {
        guard let maxCount = positionHistogram.max(), maxCount > 0 else { return nil }
        return positionHistogram.firstIndex(of: maxCount)
    }
}

// MARK: - LimitCountPreLoadIOContext

/// Preload context with a maximum outstanding request count limit.
/// RE: Forward v1.3.15 LimitCountPreLoadIOContext -- limits concurrent
/// preload requests to prevent overwhelming the network or disk I/O.
///
/// Sits atop LimitPreLoadIOContext in the hierarchy, adding request
/// count management for background preloading.
public final class LimitCountPreLoadIOContext: LimitPreLoadIOContext {
    /// Maximum number of concurrent preload requests
    public let maxPreloadCount: Int
    private var activePreloadCount = 0
    private let countLock = NSLock()

    public init(url: URL, maxCount: Int = 8) {
        self.maxPreloadCount = maxCount
        super.init(url: url)
    }

    /// Attempt to start a preload request. Returns false if at the limit.
    public func canStartPreload() -> Bool {
        countLock.lock()
        defer { countLock.unlock() }
        return activePreloadCount < maxPreloadCount
    }

    /// Increment active preload count. Call when starting a preload.
    public func beginPreload() {
        countLock.lock()
        defer { countLock.unlock() }
        activePreloadCount += 1
    }

    /// Decrement active preload count. Call when a preload completes.
    public func endPreload() {
        countLock.lock()
        defer { countLock.unlock() }
        activePreloadCount = max(activePreloadCount - 1, 0)
    }

    /// Current number of active preload requests
    public var currentPreloadCount: Int {
        countLock.lock()
        defer { countLock.unlock() }
        return activePreloadCount
    }
}
