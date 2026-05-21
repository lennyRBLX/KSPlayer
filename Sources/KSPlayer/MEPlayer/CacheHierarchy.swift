//
//  CacheHierarchy.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 (TranscodeIO.md)
//
//  Cache hierarchy (per Forward binary):
//
//    URLContextDownload                    Raw HTTP download, 256 KB buffer
//      CacheIOContext                      Core disk cache I/O, NSRecursiveLock
//        CacheOnlyIOContext                Read-only cache, never network
//        HLSCacheIOContext                 HLS-aware cache wrapper
//        LimitCacheIOContext               Max file size enforcement (512 MiB)
//          LimitPreLoadIOContext           Moov protection (10 MB), 256-slot histogram
//            LimitCountPreLoadIOContext    Max request count limiting
//              PreLoadIOContext            Preload scheduling, thumbnail fetch
//    ReadCacheIOContext                    Cache-first read with AVERROR_EOF (standalone)
//
//  Binary class names mangle as `_TtC16PreLoadIOContext<n><Name>`; module
//  "PreLoadIOContext" takes its name from the top-of-chain class.
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

// `CacheFileEntry` (the segment descriptor) is defined in CacheFileEntry.swift.
// The earlier `CacheEntry` shim that lived here has been removed: the binary
// metadata string is `_TtC16PreLoadIOContext14CacheFileEntry`, so that is the
// canonical name. Call sites use `CacheFileEntry` directly.

// MARK: - URLContextDownload (root of cache chain)

/// Raw HTTP download context. Root of the cache hierarchy.
/// RE: Forward v1.3.15 -- 17 named Ghidra symbols (`init`, `buildURL`,
/// `deallocate`, `getFormatName`, getter/setter pairs for `isRead` /
/// `multipleRequests` / `url`, `metadataInit`, `retain_helper`, plus four
/// vtable thunk slots). 256 KB download buffer (`0x40000`).
open class URLContextDownload: AbstractAVIOContext {
    /// RE: Forward uses 0x40000 (256 KB) buffer for downloads.
    public static let downloadBufferSize: Int = 256 * 1024

    public let sourceURL: URL
    private let urlSession: URLSession
    public internal(set) var totalFileSize: Int64 = -1
    var position: Int64 = 0
    let downloadLock = NSLock()

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
        case 0: position = offset
        case 1: position += offset
        case 2: if totalFileSize > 0 { position = totalFileSize + offset }
        default: break
        }
        return position
    }

    override open func fileSize() -> Int64 { totalFileSize }
    override open func close() {}

    /// Fetch bytes from sourceURL via HTTP Range request. Stateless (no position update).
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

    public var currentPosition: Int64 { position }
}

// MARK: - CacheIOContext (disk cache layer)

/// Core disk-backed cache I/O. Subclass of `URLContextDownload` -- inherits raw
/// HTTP download, adds segment-based on-disk caching with thread-safe
/// `NSRecursiveLock`.
///
/// RE: Forward v1.3.15 -- ~90 named Ghidra symbols (property modify/read/get/set
/// accessors, download/retry/refresh, cache write/seek/evict, deallocate,
/// metadata init, and the `swift_updateClassMetadata2` driver).
/// Default max cache 200 MiB.
/// Binary: `_TtC16PreLoadIOContext14CacheIOContext`.
/// Disk layout: `NSTemporaryDirectory()/videoCaches/<md5(url)>/<position>`.
open class CacheIOContext: URLContextDownload {
    /// RE: Default max cache = 200 MiB. `CacheIOContext_getDefaultMaxBytes`
    /// @ 0x10155b96c returns the IEEE-754 double `0x41a9000000000000` = 209715200.0.
    public static let defaultMaxBytes: Int64 = 209_715_200

    /// RE: ~9.5 KB per network fetch (downloadChunk).
    public static let chunkSize: Int = 9728

    private(set) var entries: [CacheFileEntry] = []
    let cacheDirectory: URL
    let cacheLock = NSRecursiveLock()

    public override init(url: URL, session: URLSession = .shared) {
        let md5 = Self.md5Hash(url.absoluteString)
        let tempDir = FileManager.default.temporaryDirectory
        self.cacheDirectory = tempDir.appendingPathComponent("videoCaches/\(md5)", isDirectory: true)
        super.init(url: url, session: session)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        loadExistingEntries()
    }

    override open func read(buffer: UnsafePointer<UInt8>?, size: Int32) -> Int32 {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let length = Int(size)
        let pos = position

        // Cache hit
        if let entry = findEntry(containing: pos) {
            let offset = pos - entry.logicalPos
            try? entry.ensureFileHandle()
            if let data = entry.readData(at: offset, length: length), !data.isEmpty {
                if let buf = UnsafeMutablePointer(mutating: buffer) {
                    data.copyBytes(to: buf, count: data.count)
                }
                position += Int64(data.count)
                return Int32(data.count)
            }
        }

        // Cache miss — fetch via parent's HTTP downloader, then persist
        guard let data = fetchBytes(from: pos, length: min(length, Self.chunkSize)) else {
            return -1
        }
        storeToDisk(data, at: pos)
        if let buf = UnsafeMutablePointer(mutating: buffer) {
            data.copyBytes(to: buf, count: data.count)
        }
        position += Int64(data.count)
        return Int32(data.count)
    }

    override open func close() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        entries.forEach { $0.closeHandle() }
        super.close()
    }

    public func purge() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        entries.forEach { $0.deallocate() }
        entries.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    /// Total bytes currently cached on disk.
    public var cachedSize: Int64 {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return entries.reduce(0) { $0 + Int64($1.size) }
    }

    // MARK: - Internal helpers (cacheLock must be held)

    func findEntry(containing pos: Int64) -> CacheFileEntry? {
        entries.first { $0.contains(position: pos) }
    }

    func storeToDisk(_ data: Data, at pos: Int64) {
        let entry: CacheFileEntry
        if let existing = entries.last(where: { $0.logicalPos + Int64($0.size) == pos }) {
            entry = existing
        } else {
            let segmentFile = cacheDirectory.appendingPathComponent("\(pos)")
            entry = CacheFileEntry(url: segmentFile, logicalPos: pos)
            entries.append(entry)
            entries.sort { $0.logicalPos < $1.logicalPos }
        }
        try? entry.ensureFileHandle()
        entry.writeData(data, at: Int64(entry.size))
    }

    private func loadExistingEntries() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return }
        for fileURL in contents {
            guard let pos = Int64(fileURL.lastPathComponent) else { continue }
            let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            let size = UInt32(clamping: attrs?.fileSize ?? 0)
            entries.append(CacheFileEntry(url: fileURL, logicalPos: pos, size: size))
        }
        entries.sort { $0.logicalPos < $1.logicalPos }
    }

    static func md5Hash(_ string: String) -> String {
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

/// Read-only cache: returns AVERROR_EOF on cache miss instead of going to network.
/// RE: CacheOnlyIOContext in Forward hierarchy — offline mode wrapper.
public final class CacheOnlyIOContext: CacheIOContext {
    override public func read(buffer: UnsafePointer<UInt8>?, size: Int32) -> Int32 {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let pos = position
        guard let entry = findEntry(containing: pos) else {
            return -541478725 // AVERROR_EOF — cache miss in offline mode
        }
        let offset = pos - entry.logicalPos
        try? entry.ensureFileHandle()
        guard let data = entry.readData(at: offset, length: Int(size)), !data.isEmpty else {
            return -1
        }
        if let buf = UnsafeMutablePointer(mutating: buffer) {
            data.copyBytes(to: buf, count: data.count)
        }
        position += Int64(data.count)
        return Int32(data.count)
    }
}

// MARK: - LimitCacheIOContext

/// Cache with maximum per-file size enforcement.
/// RE: Forward v1.3.15 -- 20 named Ghidra symbols. Default max per-file cache
/// = 512 MiB (`0x20000000`), verified at `LimitCacheIOContext_allocInit`
/// @ 0x101571e00 which stores `0x20000000` into
/// `_TtC16PreLoadIOContext19LimitCacheIOContext::maxFileSize`.
/// `LimitCacheIOContext_initWithMaxSize` @ 0x101571d60 lets callers override.
open class LimitCacheIOContext: CacheIOContext {
    /// RE: Default max cache per file = 512 MiB (`0x20000000`).
    public let maxCacheSize: Int64 = 512 * 1024 * 1024

    override open func read(buffer: UnsafePointer<UInt8>?, size: Int32) -> Int32 {
        evictIfNeeded()
        return super.read(buffer: buffer, size: size)
    }

    private func evictIfNeeded() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        var total = entries.reduce(Int64(0)) { $0 + Int64($1.size) }
        while total > maxCacheSize, entries.count > 1 {
            let oldest = entries.removeFirst()
            total -= Int64(oldest.size)
            oldest.deallocate()
        }
    }
}

// MARK: - LimitPreLoadIOContext

/// Moov protection (first 10 MB always cached) + 256-slot playback-position
/// histogram.
/// RE: Forward v1.3.15 -- 13 named Ghidra symbols (`metadataInit`,
/// `proto_close` x2, `proto_read`, `mergeSort`, `sortEntries`,
/// `deallocate` / `deallocPartial`, `setCanPreload` / `getCanPreload`,
/// `getMoovProtectionSize`, `getSyncThreshold`, `setPlaybackBytePos`).
/// A sibling subclass `LimitCountPreLoadIOContext` adds 6 more.
open class LimitPreLoadIOContext: LimitCacheIOContext {
    /// RE: Forward v1.3.15 -- `moovProtectionSize: UInt64`. Field name anchored
    /// by string `moovProtectionSize` @ 0x1033441d0 (and @ 0x103749a50); Swift
    /// mangled property descriptor `moovProtectionSizes6UInt64Vv` confirms the
    /// type is `UInt64` (no `Sg`, so non-optional). The literal `10 * 1024 *
    /// 1024` (= `0xA00000`) is the design-level value -- the metadataInit
    /// driver uses `_swift_updateClassMetadata2` and the audit did not pin the
    /// constant to a single immediate load.
    public let moovProtectionSize: UInt64 = 10 * 1024 * 1024
    /// RE: Forward v1.3.15 -- `playbackBytePosition: UInt64?`. Field name
    /// anchored by string @ 0x1033441f0 (and @ 0x103749a70); mangled descriptor
    /// `playbackBytePositions6UInt64VSgv` confirms type `Optional<UInt64>`.
    public var playbackBytePosition: UInt64?
    /// RE: Forward v1.3.15 -- `canPreload: Bool`. Field name anchored by string
    /// @ 0x10334419e (and @ 0x103749a10).
    public var canPreload: Bool = true
    /// RE: Position histogram = 256 slots (design-level; the count is
    /// consistent with the binary's prefetch heuristic but is not anchored to
    /// a single immediate in this audit).
    private var positionHistogram = [Int](repeating: 0, count: 256)
    private var moovCached = false
    private let preloadLock = NSLock()

    /// Target preload size in bytes (set by caller based on buffer duration * bitrate).
    public var preloadTargetSize: Int64 = 0

    public convenience init(url: URL, cacheSize: Double) {
        self.init(url: url, session: .shared)
        self.preloadTargetSize = Int64(max(cacheSize, 0))
    }

    override open func read(buffer: UnsafePointer<UInt8>?, size: Int32) -> Int32 {
        ensureMoovCached()
        let result = super.read(buffer: buffer, size: size)
        if result > 0 {
            updateHistogram(position: currentPosition)
            // RE: Forward v1.3.15 -- expose the current read cursor as
            // `playbackBytePosition: UInt64?` (binary field, mangled
            // `playbackBytePositions6UInt64VSgv`).
            playbackBytePosition = UInt64(max(currentPosition, 0))
        }
        return result
    }

    /// Ensure the moov atom region (first 10 MB) is cached for fast seeking.
    public func ensureMoovCached() {
        preloadLock.lock()
        defer { preloadLock.unlock() }
        guard !moovCached else { return }
        let fileTotal = fileSize()
        guard fileTotal > 0 else { return }
        // `moovProtectionSize` is `UInt64` to match the binary; convert via the
        // Int64 path that the on-disk math uses.
        let moovEndI64 = min(Int64(moovProtectionSize), fileTotal)
        if cachedSize >= moovEndI64 {
            moovCached = true
            return
        }
        let savedPos = currentPosition
        _ = seek(offset: 0, whence: 0)
        let tempBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(moovEndI64))
        defer { tempBuf.deallocate() }
        var remaining = moovEndI64
        while remaining > 0 {
            let chunkSize = min(remaining, Int64(URLContextDownload.downloadBufferSize))
            let ret = super.read(buffer: tempBuf, size: Int32(chunkSize))
            if ret <= 0 { break }
            remaining -= Int64(ret)
        }
        _ = seek(offset: savedPos, whence: 0)
        moovCached = true
    }

    private func updateHistogram(position: Int64) {
        let fileTotal = fileSize()
        guard fileTotal > 0 else { return }
        let bucket = Int(position * 255 / fileTotal)
        let clampedBucket = min(max(bucket, 0), 255)
        positionHistogram[clampedBucket] += 1
    }

    /// Returns the histogram bucket with the highest read frequency (for prefetch prediction).
    public func hotBucket() -> Int? {
        guard let maxCount = positionHistogram.max(), maxCount > 0 else { return nil }
        return positionHistogram.firstIndex(of: maxCount)
    }
}

// MARK: - LimitCountPreLoadIOContext

/// Adds max-concurrent-preload-request limiting on top of `LimitPreLoadIOContext`.
/// RE: Forward v1.3.15 -- 6 named Ghidra symbols (`getMoreCount` / `setMoreCount`,
/// `deallocFields` / `deallocPartial` / `deallocate`, `metadataInit`).
open class LimitCountPreLoadIOContext: LimitPreLoadIOContext {
    /// Maximum number of concurrent preload requests. Default 8.
    public var maxPreloadCount: Int = 8

    private var activePreloadCount = 0
    private let countLock = NSLock()

    public func canStartPreload() -> Bool {
        countLock.lock()
        defer { countLock.unlock() }
        return activePreloadCount < maxPreloadCount
    }

    public func beginPreload() {
        countLock.lock()
        defer { countLock.unlock() }
        activePreloadCount += 1
    }

    public func endPreload() {
        countLock.lock()
        defer { countLock.unlock() }
        activePreloadCount = max(activePreloadCount - 1, 0)
    }

    public var currentPreloadCount: Int {
        countLock.lock()
        defer { countLock.unlock() }
        return activePreloadCount
    }
}

// MARK: - PreLoadIOContext (top of chain)

/// Top of the cache hierarchy. Adds preload scheduling (for zero-delay episode
/// switching) and thumbnail fetch requests driven by the playback-position
/// histogram.
///
/// RE: Forward v1.3.15 -- ~16 named Ghidra symbols (`createCacheEntry`,
/// `initURLDownload`, `proto_close` / `proto_seek`, three `getFakeUrlPos`
/// symbols at different call sites, `getIsPreloadPaused` / `setIsPreloadPaused`,
/// `getStopOnLimit_override`, `getThumbnailFetchResult` / `setThumbnailFetchResult`,
/// `getEntries_override` / `setEntries_override`, `deallocFields`,
/// `setLoadMoreBuffer`, `accessor2`).
/// The binary module "PreLoadIOContext" takes its name from this class.
public final class PreLoadIOContext: LimitCountPreLoadIOContext {
    /// RE: Forward v1.3.15 -- virtual URL cursor. Field-offset symbol
    /// `_TtC16PreLoadIOContext16PreLoadIOContext::fakeUrlPos` is referenced in
    /// `LimitPreLoadIOContext_proto_read` (@ 0x101579e28) and
    /// `LimitPreLoadIOContext_proto_close` (@ 0x101579f84). The proto_read flow
    /// updates this to the underlying `+0x48` cursor whenever the two diverge,
    /// so subclasses can keep an alternate "virtual" position alongside the
    /// real download cursor.
    public var fakeUrlPos: UInt64 = 0
    /// RE: Forward v1.3.15 -- preload scratch buffer. Field name anchored by
    /// string `loadMoreBuffer` @ 0x103344a09; mangled
    /// `loadMoreBufferSpys5UInt8VGSgvpfi` confirms type
    /// `Optional<UnsafeMutablePointer<UInt8>>` with a property initializer
    /// (default `nil`). The accessor `PreLoadIOContext_setLoadMoreBuffer` @
    /// 0x1014d8a64 yields via the Swift coroutine
    /// `_swift_coroFrameAlloc(0x30, 0x10ea)` (modify-yield pattern).
    public var loadMoreBuffer: UnsafeMutablePointer<UInt8>?
    private var preloadQueue = [URL]()
    private var preloadedContexts = [String: PreLoadIOContext]()
    private var preloadTask: Task<Void, Never>?
    private let scheduleLock = NSLock()

    /// Schedule a URL for background preloading (moov + initial data).
    /// Used for next-episode zero-delay switching.
    public func schedulePreload(url: URL) {
        scheduleLock.lock()
        defer { scheduleLock.unlock() }
        let key = url.absoluteString
        guard preloadedContexts[key] == nil else { return }
        preloadQueue.append(url)
        startPreloadIfNeeded()
    }

    /// Return a preloaded context if available (for zero-delay open of next content).
    public func preloadedContext(for url: URL) -> PreLoadIOContext? {
        scheduleLock.lock()
        defer { scheduleLock.unlock() }
        return preloadedContexts[url.absoluteString]
    }

    public func cancelPreloads() {
        scheduleLock.lock()
        defer { scheduleLock.unlock() }
        preloadTask?.cancel()
        preloadTask = nil
        preloadQueue.removeAll()
    }

    private func startPreloadIfNeeded() {
        guard preloadTask == nil, !preloadQueue.isEmpty else { return }
        let url = preloadQueue.removeFirst()
        preloadTask = Task.detached { [weak self] in
            guard let self, !Task.isCancelled else { return }
            let context = PreLoadIOContext(url: url)
            context.ensureMoovCached()
            self.scheduleLock.lock()
            self.preloadedContexts[url.absoluteString] = context
            self.preloadTask = nil
            self.scheduleLock.unlock()
            self.scheduleLock.lock()
            self.startPreloadIfNeeded()
            self.scheduleLock.unlock()
        }
    }
}

// MARK: - ReadCacheIOContext (standalone)

/// Cache-first read context with explicit AVERROR_EOF handling. Separate from the
/// URLContextDownload→CacheIOContext chain — uses composition rather than inheritance.
///
/// RE: Forward v1.3.15. Standalone class — not a subclass of CacheIOContext.
open class ReadCacheIOContext: AbstractAVIOContext {
    private let downloader: URLContextDownload
    private let cacheDirectory: URL
    private var entries: [CacheFileEntry] = []
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

        if let entry = entries.first(where: { $0.contains(position: position) }) {
            let offsetInSegment = position - entry.logicalPos
            let available = min(Int64(length), Int64(entry.size) - offsetInSegment)
            if let handle = try? FileHandle(forReadingFrom: entry.url) {
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

        guard let data = downloader.fetchBytes(from: position, length: length) else {
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

    override open func fileSize() -> Int64 { downloader.totalFileSize }
    override open func close() { downloader.close() }

    private func storeToDisk(_ data: Data, at pos: Int64) {
        let segmentFile = cacheDirectory.appendingPathComponent("\(pos)")
        if !FileManager.default.fileExists(atPath: segmentFile.path) {
            FileManager.default.createFile(atPath: segmentFile.path, contents: data)
        } else if let handle = try? FileHandle(forWritingTo: segmentFile) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        }
        if let idx = entries.firstIndex(where: { $0.logicalPos == pos }) {
            entries[idx].grow(by: UInt32(data.count))
        } else {
            entries.append(CacheFileEntry(url: segmentFile, logicalPos: pos, physicalPos: 0, size: UInt32(data.count)))
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
            entries.append(CacheFileEntry(url: fileURL, logicalPos: pos, physicalPos: 0, size: size))
        }
        entries.sort { $0.logicalPos < $1.logicalPos }
    }

    public var cachedSize: Int64 {
        entries.reduce(0) { $0 + Int64($1.size) }
    }

    public func purge() {
        lock.lock()
        defer { lock.unlock() }
        entries.forEach { $0.deallocate() }
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
