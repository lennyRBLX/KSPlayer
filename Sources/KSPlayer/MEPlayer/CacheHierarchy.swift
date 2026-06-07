//
//  CacheHierarchy.swift
//  KSPlayer
//
//  RE source: v1.3.15 (TranscodeIO.md)
//
//  Cache hierarchy (per 1.3.15 binary):
//
//    AbstractAVIOContext              KSPlayer base -- all custom IO contexts derive from this
//    +- URLContextDownload            Raw HTTP download, 256 KB buffer, conforms to DownloadProtocol
//    +- CacheIOContext                Core disk cache I/O, NSRecursiveLock, 27 stored properties
//    |    +- LimitCacheIOContext      Max file size enforcement (512 MiB), 4 MiB hysteresis eviction
//    |    +- PreLoadIOContext         Preload scheduling, thumbnail fetch, TimeIndex
//    |         +- LimitPreLoadIOContext       Moov protection, cached-range distribution
//    |              +- LimitCountPreLoadIOContext  Max request count limiting
//    +- CacheOnlyIOContext            Read-only cache wrapper (provider-closure snapshot from PreLoadIOContext)
//    +- HLSCacheIOContext             HLS-aware wrapper (HLSCacheIOContext.swift)
//    +- ReadCacheIOContext            Cache-first read with AVERROR_EOF handling
//
//  Binary class names mangle as `_TtC16PreLoadIOContext<n><Name>`; module
//  "PreLoadIOContext" takes its name from the PreLoadIOContext class.
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

// `CacheFileEntry` (the segment descriptor) is defined in CacheFileEntry.swift.
// The `CacheEntry` (Codable persistence record) type is also defined there.
// The binary metadata string is `_TtC16PreLoadIOContext14CacheFileEntry`, so that
// is the canonical runtime name. Call sites use `CacheFileEntry` directly.

// MARK: - DownloadProtocol

/// Protocol for download backends that provide byte-range reads and seeks.
/// URLContextDownload conforms to this; CacheIOContext holds one via composition.
/// RE: 1.3.15 -- CacheIOContext.download: DownloadProtocol
public protocol DownloadProtocol: AnyObject {
    func read(into buffer: UnsafeMutablePointer<UInt8>, count: Int32) -> Int32
    func seek(to offset: Int64, whence: Int32) -> Int64
    func close()
    var totalFileSize: Int64 { get }
}

// MARK: - TimeIndexEntry

/// One time-to-byte index record: maps a media timestamp to a byte position so the
/// preload logic can translate between the two domains (and seeks can resolve to
/// a file offset / packet-cache hit).
///
/// RE: 1.3.15 -- `struct KSPlayer.TimeIndexEntry` (types.json,
/// `kind: struct`, module `KSPlayer`; 2 fields). Element type of
/// `PreLoadIOContext._timeIndex: [TimeIndexEntry]`. See .reversal/TranscodeIO.md
/// TimeIndexEntry and .reversal/PlayerCore.md TimeIndexEntry.
public struct TimeIndexEntry: Equatable, Hashable, Sendable {
    /// RE: field 1 of 2 -- byte offset into the stream.
    public var position: UInt64
    /// RE: field 2 of 2 -- playback time (seconds) at that byte offset.
    public var time: Double

    public init(position: UInt64, time: Double) {
        self.position = position
        self.time = time
    }
}

// MARK: - URLContextDownload (sibling of CacheIOContext)

/// Raw HTTP download context. Direct subclass of AbstractAVIOContext --
/// a SIBLING of CacheIOContext, NOT its parent. Conforms to DownloadProtocol
/// so CacheIOContext can hold one via composition (`download: DownloadProtocol`).
///
/// RE: 1.3.15 -- 17 named Ghidra symbols. 4 binary fields
/// (context, keepAlive, isReadComplete, url). 256 KB download buffer (0x40000).
/// init @ 0x10155c030, buildURL @ 0x10155c234,
/// deallocate(=open) @ 0x1015662e0, ensureFileHandle(=allocating init+open) @ 0x10156603c.
/// metadataInit @ 0x10156b2c8 confirms 4-field count.
open class URLContextDownload: AbstractAVIOContext, DownloadProtocol {
    /// RE: 0x40000 (256 KB) buffer for downloads, verified at two instantiation sites.
    /// RE: 0x10155c030 (URLContextDownload_init, 1.3.15)
    public static let downloadBufferSize: Int = 256 * 1024

    /// RE: field 1 of 4 -- FFmpeg URLContext handle, opened lazily by open/buildURL.
    // Original: UnsafeMutablePointer<URLContext>? -- we use an opaque pointer since
    // URLContext is an FFmpeg internal type.
    public var context: UnsafeMutableRawPointer?

    /// RE: field 2 of 4 -- whether HTTP connection kept alive between range requests.
    /// Backed by the "multiple_requests" format-dict option.
    public var keepAlive: Bool = false

    /// RE: field 3 of 4 -- set when source fully read (EOF reached).
    /// Real ldrb accessor is inlined (not separately named in Ghidra).
    public var isReadComplete: Bool = false

    /// RE: field 4 of 4 -- source URL for the download.
    public let url: URL

    // Implementation fields for the Swift-side HTTP download path.
    private let urlSession: URLSession
    public internal(set) var totalFileSize: Int64 = -1
    var position: Int64 = 0
    let downloadLock = NSLock()

    /// RE: 0x10155c030 (URLContextDownload_init, 1.3.15)
    public init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.urlSession = session
        super.init(bufferSize: Int32(Self.downloadBufferSize), writable: false)
    }

    // MARK: - DownloadProtocol conformance

    public func read(into buffer: UnsafeMutablePointer<UInt8>, count: Int32) -> Int32 {
        downloadLock.lock()
        defer { downloadLock.unlock() }
        guard let data = fetchBytes(from: position, length: Int(count)) else {
            return -1
        }
        data.copyBytes(to: buffer, count: data.count)
        position += Int64(data.count)
        return Int32(data.count)
    }

    public func seek(to offset: Int64, whence: Int32) -> Int64 {
        downloadLock.lock()
        defer { downloadLock.unlock() }
        switch whence {
        case 0: position = offset             // SEEK_SET
        case 1: position += offset            // SEEK_CUR
        case 2: if totalFileSize > 0 { position = totalFileSize + offset }  // SEEK_END
        default: break
        }
        return position
    }

    // MARK: - AbstractAVIOContext overrides

    override open func read(buffer: UnsafePointer<UInt8>?, size: Int32) -> Int32 {
        guard let buf = UnsafeMutablePointer(mutating: buffer) else { return -1 }
        return read(into: buf, count: size)
    }

    override open func seek(offset: Int64, whence: Int32) -> Int64 {
        seek(to: offset, whence: whence)
    }

    override open func fileSize() -> Int64 { totalFileSize }

    override open func close() {
        // Release the FFmpeg URLContext if present.
        context = nil
    }

    /// Fetch bytes from sourceURL via HTTP Range request. Stateless (no position update).
    public func fetchBytes(from offset: Int64, length: Int) -> Data? {
        var request = URLRequest(url: url)
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

/// Core disk-backed cache I/O. Direct subclass of AbstractAVIOContext (NOT URLContextDownload).
/// Holds a URLContextDownload via composition as `download: DownloadProtocol`.
/// Thread-safe via NSRecursiveLock (`downloadLock`). 27 stored properties (verified by
/// metadataInit2 @ 0x10156b114 passing arg3=0x1b=27).
///
/// RE: 1.3.15 -- ~90 named Ghidra symbols. Default max cache 200 MiB.
/// Binary: `_TtC16PreLoadIOContext14CacheIOContext`.
/// Disk layout: `NSTemporaryDirectory()/videoCaches/<source_component>/`.
/// Designated init: FUN_10155c54c, allocAndInit: 0x10155c4c8.
open class CacheIOContext: AbstractAVIOContext {
    /// RE: Default max cache = 200 MiB. CacheIOContext_getDefaultMaxBytes
    /// @ 0x10155b96c returns IEEE-754 double 0x41a9000000000000 = 209715200.0.
    /// RE: 0x10155b96c (CacheIOContext_getDefaultMaxBytes, 1.3.15)
    public static let defaultMaxBytes: Int64 = 209_715_200

    /// RE: ~9.5 KB per network fetch (downloadChunk).
    public static let chunkSize: Int = 9728

    // MARK: - 27 stored properties (RE: metadataInit2 @ 0x10156b114, arg3=0x1b=27)

    /// RE: field 1 -- the download backend held via composition, NOT inheritance.
    /// Typically a URLContextDownload. Pinned at init via protocol witness.
    /// RE: 0x10156a6c8 (CacheIOContext_openURL, 1.3.15)
    public var download: DownloadProtocol?

    /// RE: field 2 -- total/end byte position, pinned at self+0x40.
    public var end: UInt64 = 0

    /// RE: field 3 -- underlying URL/file read position.
    public var urlPos: UInt64 = 0

    /// RE: field 4 -- timestamp of last bandwidth sample.
    public var lastSpeedSampleTime: Double = 0

    /// RE: field 5 -- byte position at last speed sample.
    public var lastSpeedSamplePos: UInt64 = 0

    /// RE: field 6 -- computed download speed.
    public var _downloadSpeed: Double = 0

    /// RE: field 7 -- interval between speed samples.
    public var speedSampleInterval: Double = 0

    /// RE: field 8 -- speed cap to reject outlier measurements.
    public var maxReasonableSpeed: Double = 0

    /// RE: field 9 -- the read cursor, pinned at self+0x48.
    public var logicalPos: UInt64 = 0

    /// RE: field 10 -- sorted entry list, pinned at self+0x80.
    /// Binary field name is `entryList` (per designated-init Rosetta Stone).
    /// RE: 0x10156475c (findCacheEntry binary search, 1.3.15)
    public private(set) var entryList: [CacheFileEntry] = []

    /// RE: field 11 -- on-disk cache path.
    /// NSTemporaryDirectory()/videoCaches/<source_component>/
    public var tmpURL: URL

    /// RE: field 12 -- judge-EOF flag.
    public var isJudgeEOF: Bool = true

    /// RE: field 13 -- whether segments persist to disk.
    public var saveFile: Bool = false

    /// RE: field 14 -- whether reading is complete.
    public var isReadComplete: Bool = false

    /// RE: field 15 -- EOF flag. Drives AVERROR_EOF returns and end.txt persistence.
    public var eof: Bool = false

    /// RE: field 16 -- closed flag.
    public var _isClosed: Bool = false

    /// RE: field 17 -- thread-safety lock. Binary name is `downloadLock`.
    /// Allocated as NSRecursiveLock in designated init FUN_10155c54c.
    /// RE: 0x10155bbd4 (CacheIOContext_initLock, 1.3.15)
    public let downloadLock = NSRecursiveLock()

    /// RE: field 18 -- optional URL refresh closure.
    public var urlRefreshHandler: (() -> URL?)?

    /// RE: field 19 -- FFmpeg format-context options.
    public var formatContextOptions: [String: Any]?

    /// RE: field 20 -- AVIO interrupt callback.
    public var interrupt: OpaquePointer? // AVIOInterruptCB in FFmpeg

    /// RE: field 21 -- cache-update notification callback, pinned at self+0x168.
    public var onCacheUpdated: (() -> Void)?

    /// RE: field 22 -- whether to stop when limit reached.
    public var stopOnLimitReached: Bool = false

    /// RE: field 23 -- total fetched bytes, pinned at self+0x170.
    public var fetchedSize: Int64 = 0

    /// RE: field 24 -- timestamp of first seek.
    public var firstSeekTime: Double = 0

    /// RE: field 25 -- seek offset history.
    public var seekOffsets: [Int64] = []

    /// RE: field 26 -- whether content is interleaved (audio/video).
    public var isInterleaved: Bool? = nil // binary init stores 2 = nil-sentinel

    /// RE: field 27 -- first-file-size flag.
    public var isFirstFileSize: Bool = true

    // MARK: - Init

    /// RE: 0x10155c4c8 (CacheIOContext_allocAndInit, 1.3.15)
    /// RE: FUN_10155c54c (designated init, 1.3.15)
    public init(url: URL, saveFile: Bool = false, isReadComplete: Bool = false) {
        let md5 = Self.md5Hash(url.absoluteString)
        let tempDir = FileManager.default.temporaryDirectory
        self.tmpURL = tempDir.appendingPathComponent("videoCaches/\(md5)", isDirectory: true)
        self.saveFile = saveFile
        self.isReadComplete = isReadComplete
        super.init(bufferSize: 32 * 1024, writable: false)
        try? FileManager.default.createDirectory(at: tmpURL, withIntermediateDirectories: true)
        loadCacheFileEntries()
    }

    // MARK: - Read / Write / Close

    override open func read(buffer: UnsafePointer<UInt8>?, size: Int32) -> Int32 {
        downloadLock.lock()
        defer { downloadLock.unlock() }
        let length = Int(size)

        // Cache hit -- binary search entryList
        if let entry = findCacheEntry(forPosition: logicalPos) {
            let offset = logicalPos - entry.position
            if let data = entry.readData(at: offset, length: length), !data.isEmpty {
                if let buf = UnsafeMutablePointer(mutating: buffer) {
                    data.copyBytes(to: buf, count: data.count)
                }
                logicalPos += UInt64(data.count)
                return Int32(data.count)
            }
        }

        // Cache miss -- fetch via download backend, then persist
        guard let dl = download else { return -1 }
        let seekResult = dl.seek(to: Int64(logicalPos), whence: 0)
        guard seekResult >= 0 else { return -1 }
        let readSize = min(Int32(length), Int32(Self.chunkSize))
        let tempBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(readSize))
        defer { tempBuf.deallocate() }
        let bytesRead = dl.read(into: tempBuf, count: readSize)
        guard bytesRead > 0 else { return bytesRead }
        let data = Data(bytes: tempBuf, count: Int(bytesRead))
        storeToDisk(data, at: logicalPos)
        if let buf = UnsafeMutablePointer(mutating: buffer) {
            data.copyBytes(to: buf, count: data.count)
        }
        logicalPos += UInt64(bytesRead)
        return bytesRead
    }

    override open func seek(offset: Int64, whence: Int32) -> Int64 {
        downloadLock.lock()
        defer { downloadLock.unlock() }
        switch whence {
        case 0: logicalPos = UInt64(max(offset, 0))        // SEEK_SET
        case 1: logicalPos = UInt64(max(Int64(logicalPos) + offset, 0))  // SEEK_CUR
        case 2:
            if end > 0 { logicalPos = UInt64(max(Int64(end) + offset, 0)) }
        default: break
        }
        return Int64(logicalPos)
    }

    override open func fileSize() -> Int64 {
        download?.totalFileSize ?? Int64(end)
    }

    override open func close() {
        flushAndClose()
    }

    // MARK: - Flush / Close pair

    /// RE: 0x101561b98 (processRange = flushAndClose, 1.3.15)
    /// Pass 1: sets _isClosed=1, locks downloadLock, marks CacheFileEntry::saveFile,
    /// writes end.txt on eof. Per binary: if !saveFile, clears entryList + removes tmpURL.
    public func flushAndClose() {
        _isClosed = true
        downloadLock.lock()
        defer { downloadLock.unlock() }

        if saveFile {
            for entry in entryList {
                entry.saveFile = true
            }
            if eof, end != 0 {
                // Write end.txt with the total size
                let endFile = tmpURL.appendingPathComponent("end.txt")
                try? String(end).write(to: endFile, atomically: true, encoding: .utf8)
            }
        } else {
            entryList.removeAll()
            try? FileManager.default.removeItem(at: tmpURL)
        }

        download?.close()
    }

    /// RE: 0x101562038 (cleanupAfterFlush, 1.3.15)
    /// Pass 2: per-segment cache-file rotate + close + end.txt + onCacheUpdated notify.
    /// 32 MiB per-segment cap (0x2000000).
    open func cleanupAfterFlush(data: Data) {
        downloadLock.lock()
        defer { downloadLock.unlock() }

        // Find or create the active entry
        let pos = logicalPos
        let entry: CacheFileEntry
        if let existing = findEntryEndingAt(offset: pos) {
            entry = existing
        } else {
            let segmentFile = tmpURL.appendingPathComponent("\(pos)")
            entry = CacheFileEntry(url: segmentFile, position: pos)
            insertEntrySorted(entry)
        }

        // 32 MiB per-segment cap: roll a new file if exceeded
        if entry.shouldRoll(extra: UInt32(data.count)) {
            entry.maxSize = entry.size
            // A new segment will be created on next write
        } else {
            entry.append(data)
        }

        // Persist size and notify
        let endFile = tmpURL.appendingPathComponent("end.txt")
        if eof, end != 0 {
            try? String(end).write(to: endFile, atomically: true, encoding: .utf8)
        }
        onCacheUpdated?()
    }

    // MARK: - Entry management

    /// RE: 0x10156475c (downloadTask_didReceiveData = findCacheEntry binary search, 1.3.15)
    /// Binary search of entryList by CacheFileEntry::position/size.
    public func findCacheEntry(forPosition pos: UInt64) -> CacheFileEntry? {
        var lo = 0
        var hi = entryList.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let entry = entryList[mid]
            let entryPos = entry.position
            let entryEnd = entryPos + UInt64(entry.size)
            if pos < entryPos {
                hi = mid - 1
            } else if pos < entryEnd {
                return entry // Found
            } else {
                lo = mid + 1
            }
        }
        return nil
    }

    /// RE: 0x10156247c (writeSizeToEndTxt = insertEntrySorted, 1.3.15)
    /// Binary-search entryList for position-ordered insertion index.
    func insertEntrySorted(_ entry: CacheFileEntry) {
        var lo = 0
        var hi = entryList.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if entryList[mid].position < entry.position {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        entryList.insert(entry, at: lo)
    }

    /// RE: 0x1015622b8 (createEndMarker = findEntryEndingAt, 1.3.15)
    /// Binary-search for entry whose position+size == offset.
    func findEntryEndingAt(offset: UInt64) -> CacheFileEntry? {
        var lo = 0
        var hi = entryList.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let entry = entryList[mid]
            let entryEnd = entry.position + UInt64(entry.size)
            if entryEnd == offset {
                return entry
            } else if entryEnd < offset {
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return nil
    }

    /// RE: 0x101564294 (downloadTask_cancel = cachedRangeFractions, 1.3.15)
    /// Coalesces contiguous CacheFileEntry and emits fractions for seek-bar / loadedTimeRanges.
    public func cachedRangeFractions() -> [(startFraction: Double, endFraction: Double)] {
        downloadLock.lock()
        defer { downloadLock.unlock() }
        guard end > 0, eof || !entryList.isEmpty else { return [] }
        let total = Double(end)
        var result: [(Double, Double)] = []
        var i = 0
        while i < entryList.count {
            let start = entryList[i]
            var rangeEnd = start.position + UInt64(start.size)
            // Coalesce contiguous entries
            while i + 1 < entryList.count,
                  UInt64(entryList[i + 1].position) == rangeEnd {
                i += 1
                rangeEnd = UInt64(entryList[i].position) + UInt64(entryList[i].size)
            }
            let startFrac = Double(start.position) / total
            let endFrac = Double(rangeEnd) / total
            result.append((startFrac, endFrac))
            i += 1
        }
        return result
    }

    /// RE: 0x10155b978 (CacheIOContext_resetCounters, 1.3.15)
    /// Zeroes bandwidth sample offsets.
    public func resetCounters() {
        lastSpeedSampleTime = 0
        lastSpeedSamplePos = 0
        _downloadSpeed = 0
    }

    /// RE: 0x10156a6c8 (CacheIOContext_openURL, 1.3.15)
    /// The real AVIO-open path: reads 'multiple_requests', builds URLContextDownload,
    /// calls ffurl_open_whitelist.
    public func openURL(_ url: URL, formatOptions: [String: Any]? = nil) {
        let dl = URLContextDownload(url: url)
        // Read 'multiple_requests' from format options
        if let options = formatOptions ?? formatContextOptions,
           let multiReq = options["multiple_requests"] as? Bool {
            dl.keepAlive = multiReq
        }
        self.download = dl
        self.formatContextOptions = formatOptions
    }

    /// RE: 0x101562cf4 (CacheIOContext_evictEntries, 1.3.15)
    /// Directory cleanup: removes stale cache dirs.
    public func evictEntries() {
        let parentDir = tmpURL.deletingLastPathComponent()
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: parentDir,
            includingPropertiesForKeys: nil
        ) else { return }
        let keepName = tmpURL.lastPathComponent
        for dirURL in contents {
            if dirURL.lastPathComponent != keepName {
                try? FileManager.default.removeItem(at: dirURL)
            }
        }
    }

    // MARK: - Persistence

    /// RE: 0x10155d094 (CacheIOContext_loadCacheFileEntry, 1.3.15)
    /// Rehydrates cache state from disk, parses end.txt for total size,
    /// parses filename as segment position.
    private func loadCacheFileEntries() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: tmpURL, includingPropertiesForKeys: [.fileSizeKey]) else { return }
        for fileURL in contents {
            let name = fileURL.lastPathComponent
            // end.txt marker: parse contents as total size
            if name == "end.txt" {
                if let text = try? String(contentsOf: fileURL, encoding: .utf8),
                   let totalSize = UInt64(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    end = totalSize
                    eof = true
                }
                continue
            }
            guard let pos = Int64(name) else { continue }
            let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            let size = UInt32(clamping: attrs?.fileSize ?? 0)
            let entry = CacheFileEntry(url: fileURL, position: UInt64(pos), size: size)
            entryList.append(entry)
        }
        entryList.sort { $0.position < $1.position }
        // Sum fetched size from entries
        if !entryList.isEmpty {
            fetchedSize = entryList.reduce(0) { $0 + Int64($1.size) }
        }
    }

    func storeToDisk(_ data: Data, at pos: UInt64) {
        let entry: CacheFileEntry
        if let existing = entryList.last(where: { $0.position + UInt64($0.size) == pos }) {
            entry = existing
        } else {
            let segmentFile = tmpURL.appendingPathComponent("\(pos)")
            entry = CacheFileEntry(url: segmentFile, position: pos)
            insertEntrySorted(entry)
        }
        entry.append(data)
    }

    public func purge() {
        downloadLock.lock()
        defer { downloadLock.unlock() }
        entryList.removeAll()
        try? FileManager.default.removeItem(at: tmpURL)
    }

    /// Total bytes currently cached on disk.
    public var cachedSize: Int64 {
        downloadLock.lock()
        defer { downloadLock.unlock() }
        return entryList.reduce(0) { $0 + Int64($1.size) }
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

/// Read-only cache wrapper. Direct subclass of AbstractAVIOContext (NOT CacheIOContext).
/// Captures the source context's data through provider closures rather than subclassing.
/// 8 binary fields. Returns AVERROR_EOF on cache miss when !allowNetworkFallback.
///
/// RE: 1.3.15 -- `_TtC16PreLoadIOContext18CacheOnlyIOContext`.
/// 4 named symbols: alloc @ 0x10156c424, init @ 0x10156c488,
/// deinit @ 0x1000958c4, vtableHelper @ 0x101571c9c.
public final class CacheOnlyIOContext: AbstractAVIOContext {
    /// AVERROR_EOF constant from FFmpeg.
    private static let avErrorEOF: Int32 = -541_478_725 // 0xDFB9B0BB

    // MARK: - 8 binary fields

    /// RE: field 1 -- closure returning the source context's cached segments.
    public let entryListProvider: () -> [CacheFileEntry]

    /// RE: field 2 -- closure returning the source's end position.
    public let endProvider: () -> UInt64

    /// RE: field 3 -- closure returning the source's EOF state.
    public let eofProvider: () -> Bool

    /// RE: field 4 -- current read cursor.
    public var logicalPos: UInt64 = 0

    /// RE: field 5 -- back-reference to the originating preload context.
    public weak var sourceContext: PreLoadIOContext?

    /// RE: field 6 -- whether cache miss may fall back to network.
    public var allowNetworkFallback: Bool = false

    /// RE: field 7 -- bytes requested so far.
    public var requestedBytes: Int64 = 0

    /// RE: field 8 -- cap on bytes served via network-fallback path.
    public var maxNetworkBytes: Int64 = 0

    /// RE: 0x10156c488 (CacheOnlyIOContext_init, 1.3.15)
    public init(
        entryListProvider: @escaping () -> [CacheFileEntry],
        endProvider: @escaping () -> UInt64,
        eofProvider: @escaping () -> Bool,
        sourceContext: PreLoadIOContext? = nil,
        allowNetworkFallback: Bool = false
    ) {
        self.entryListProvider = entryListProvider
        self.endProvider = endProvider
        self.eofProvider = eofProvider
        self.sourceContext = sourceContext
        self.allowNetworkFallback = allowNetworkFallback
        super.init(bufferSize: 32 * 1024, writable: false)
    }

    /// RE: 0x10156b89c (setFormatContextOptions = cache READ callback, 1.3.15)
    /// Binary-search entryList by CacheFileEntry::position/size, read from cache,
    /// fall back to weak sourceContext when allowNetworkFallback.
    override public func read(buffer: UnsafePointer<UInt8>?, size: Int32) -> Int32 {
        let entries = entryListProvider()
        let pos = logicalPos

        // Binary search for cache entry containing pos
        if let entry = binarySearchEntry(entries, position: pos) {
            let offset = pos - entry.position
            if let data = entry.readData(at: offset, length: Int(size)), !data.isEmpty {
                if let buf = UnsafeMutablePointer(mutating: buffer) {
                    data.copyBytes(to: buf, count: data.count)
                }
                logicalPos += UInt64(data.count)
                requestedBytes += Int64(data.count)
                return Int32(data.count)
            }
        }

        // Cache miss
        if !allowNetworkFallback {
            if eofProvider(), logicalPos >= endProvider() {
                return Self.avErrorEOF
            }
            return -1
        }

        // Fall back to sourceContext network read
        guard let source = sourceContext else { return -1 }
        let dl = source.download
        guard let dl else { return -1 }
        let seekResult = dl.seek(to: Int64(pos), whence: 0)
        guard seekResult >= 0 else { return -1 }
        guard let buf = UnsafeMutablePointer(mutating: buffer) else { return -1 }
        let result = dl.read(into: buf, count: size)
        if result > 0 {
            logicalPos += UInt64(result)
            requestedBytes += Int64(result)
        }
        return result
    }

    /// RE: 0x10156c254 (getInterrupt = avio SEEK callback, 1.3.15)
    override public func seek(offset: Int64, whence: Int32) -> Int64 {
        switch whence {
        case 0: // SEEK_SET
            logicalPos = UInt64(max(offset, 0))
        case 1: // SEEK_CUR
            logicalPos = UInt64(max(Int64(logicalPos) + offset, 0))
        case 2: // SEEK_END
            let total = endProvider()
            logicalPos = UInt64(max(Int64(total) + offset, 0))
        default: return -1
        }
        return Int64(logicalPos)
    }

    override public func fileSize() -> Int64 {
        Int64(endProvider())
    }

    private func binarySearchEntry(_ entries: [CacheFileEntry], position pos: UInt64) -> CacheFileEntry? {
        var lo = 0
        var hi = entries.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let entry = entries[mid]
            let entryPos = entry.position
            let entryEnd = entryPos + UInt64(entry.size)
            if pos < entryPos {
                hi = mid - 1
            } else if pos < entryEnd {
                return entry
            } else {
                lo = mid + 1
            }
        }
        return nil
    }
}

// MARK: - LimitCacheIOContext

/// Cache with maximum per-file size enforcement.
/// Direct subclass of CacheIOContext (branches off the spine -- sibling of PreLoadIOContext).
///
/// RE: 1.3.15 -- 20 named Ghidra symbols. Default max per-file cache
/// = 512 MiB (0x20000000), verified at LimitCacheIOContext_allocInit @ 0x101571e00.
/// LimitCacheIOContext_initWithMaxSize @ 0x101571d60 lets callers override.
/// 4 MiB (0x400000) hysteresis gate in handleOverflow @ 0x101573a10.
/// Position-aware evictor at FUN_101573cdc protects moov + playback position.
open class LimitCacheIOContext: CacheIOContext {
    /// RE: Default max cache per file = 512 MiB (0x20000000).
    /// Field-offset symbol: _TtC16PreLoadIOContext19LimitCacheIOContext::maxFileSize.
    /// RE: 0x101571e00 (LimitCacheIOContext_allocInit, 1.3.15)
    public var maxFileSize: UInt64 = 512 * 1024 * 1024

    /// RE: 0x101571d60 (LimitCacheIOContext_initWithMaxSize, 1.3.15)
    public convenience init(url: URL, maxSize: UInt64) {
        self.init(url: url)
        self.maxFileSize = maxSize
    }

    // MARK: - Limit predicates

    /// RE: 0x1015734e8, 0x101573324, 0x1015731f8 (readCallback/proto_close/proto_seek, 1.3.15)
    /// Three near-identical "hit cache limit?" predicates.
    /// If _isClosed -> return false. If stopOnLimitReached: sum entries, return total >= maxFileSize.
    public func hasReachedCacheLimit() -> Bool {
        if _isClosed { return false }
        guard stopOnLimitReached else { return false }
        let total = max(cachedSize, fetchedSize)
        return total >= Int64(maxFileSize)
    }

    // MARK: - Eviction

    /// RE: 0x101573a10 (handleOverflow, 1.3.15)
    /// Eviction trigger with 4 MiB hysteresis gate.
    /// total > lastCheckCacheSize + 0x400000 AND total > cap - 0x400000.
    /// Calls position-aware evictor, resets cachedDistribution.
    /// Tail-calls cleanupAfterFlush.
    public func handleOverflow(playbackPos: UInt64, lastCheckCacheSize: inout UInt64) {
        let total = UInt64(cachedSize)
        let cap = maxFileSize
        let hysteresis: UInt64 = 0x400000 // 4 MiB

        // Hysteresis gate
        guard total > lastCheckCacheSize + hysteresis,
              total > cap - hysteresis else {
            return
        }

        // Position-aware eviction
        evictAwayFromPlayback(playbackPos: playbackPos, cap: cap)

        // Update check size
        lastCheckCacheSize = UInt64(cachedSize)
    }

    /// RE: FUN_101573cdc (position-aware evictor, 1.3.15)
    /// LRU-by-distance: protects entries containing playbackPos and moovProtectionSize.
    /// Removes files async on dispatch_queue. Fires onCacheUpdated.
    private func evictAwayFromPlayback(playbackPos: UInt64, cap: UInt64) {
        downloadLock.lock()
        defer { downloadLock.unlock() }

        var totalCached = UInt64(cachedSize)
        guard totalCached > cap else { return }
        let bytesToFree = totalCached - cap

        var freed: UInt64 = 0
        var indicesToRemove: [Int] = []

        for (idx, entry) in entryList.enumerated() {
            if freed >= bytesToFree { break }
            let entryPos = entry.position
            let entryEnd = entryPos + UInt64(entry.size)

            // Protect entries containing the playback position
            if entryPos <= playbackPos && playbackPos < entryEnd {
                continue
            }

            indicesToRemove.append(idx)
            freed += UInt64(entry.size)
        }

        // Remove in reverse order to maintain indices
        for idx in indicesToRemove.reversed() {
            let entry = entryList.remove(at: idx)
            let filePath = tmpURL.appendingPathComponent("\(entry.position)")
            DispatchQueue.global(qos: .utility).async {
                try? FileManager.default.removeItem(at: filePath)
            }
            totalCached -= UInt64(entry.size)
        }

        onCacheUpdated?()
    }

    /// RE: 0x101571f0c (writeData, 1.3.15)
    /// Write-side finalize override: sums cached bytes, overflow gate vs maxFileSize,
    /// eviction loop that protects playbackPos entries, fires onCacheUpdated.
    /// Vtable slot +0x3f0 finalize witness for LimitCacheIOContext.
    open func writeDataWithEviction(data: Data, playbackPos: UInt64) {
        downloadLock.lock()
        defer { downloadLock.unlock() }

        let total = entryList.reduce(UInt64(0)) { $0 + UInt64($1.size) }
        guard total >= maxFileSize else { return }

        // Eviction loop: skip entry 0 (head never evicted), protect playback position
        var idx = 1
        while idx < entryList.count {
            let entry = entryList[idx]
            let entryEnd = entry.position + UInt64(entry.size)
            if playbackPos < entryEnd {
                break // Stop once we reach playback position
            }
            // Check maxSize
            if let maxSz = entry.maxSize,
               entry.size + UInt32(data.count) > maxSz {
                let removed = entryList.remove(at: idx)
                let filePath = tmpURL.appendingPathComponent("\(removed.position)")
                DispatchQueue.global(qos: .utility).async {
                    try? FileManager.default.removeItem(at: filePath)
                }
                onCacheUpdated?()
                continue
            }
            idx += 1
        }
    }

    /// RE: 0x101573970 (closeCallback, 1.3.15)
    /// Flush-and-save on close: delegates to CacheIOContext base flush/close.
    public func closeCallback() {
        flushAndClose()
    }

    /// No binary address — Swift-side no-op placeholder for subclass override.
    /// LimitPreLoadIOContext overrides with the real body (RE: 0x101572b54).
    public func resetSyncState() {
        // Subclasses (LimitPreLoadIOContext) override this with their own fields.
    }

    /// RE: FUN_101562fec (LRU cache-directory eviction, 1.3.15)
    /// Modification-date LRU: lists tmp cache dir, sorts by date, removes oldest files.
    public func evictOldestCacheDirectories(keepCount: Int) {
        let parentDir = tmpURL.deletingLastPathComponent()
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: parentDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let withDates: [(url: URL, date: Date?)] = contents.map { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            return (url, values?.contentModificationDate)
        }

        // Sort by date ascending (oldest first)
        let sorted = withDates.sorted { a, b in
            (a.date ?? .distantPast) < (b.date ?? .distantPast)
        }

        // Remove the oldest beyond keepCount
        if sorted.count > keepCount {
            for item in sorted.prefix(sorted.count - keepCount) {
                try? FileManager.default.removeItem(at: item.url)
            }
        }
    }

    /// RE: 0x101574d4c (handleDisconnect = cached-range distribution, 1.3.15)
    /// Computes cachedDistribution tuple: partitions cached bytes into
    /// readed/contiguousPreload/disconnected buckets relative to playbackPos.
    public func computeCachedDistribution(playbackPos: UInt64) -> (
        readed: UInt64, contiguousPreload: UInt64, disconnected: UInt64
    ) {
        downloadLock.lock()
        defer { downloadLock.unlock() }

        var readed: UInt64 = 0
        var contiguous: UInt64 = 0
        var disconnected: UInt64 = 0

        for entry in entryList {
            let entryEnd = entry.position + UInt64(entry.size)
            if entryEnd <= playbackPos {
                readed += UInt64(entry.size)
            } else if entry.position <= playbackPos {
                // Entry spans the playback position
                readed += playbackPos - entry.position
                contiguous += entryEnd - playbackPos
            } else if contiguous > 0 || entry.position == playbackPos {
                contiguous += UInt64(entry.size)
            } else {
                disconnected += UInt64(entry.size)
            }
        }

        return (readed, contiguous, disconnected)
    }
}

// MARK: - PreLoadIOContext (mid-spine)

/// Mid-spine of the cache hierarchy: subclass of CacheIOContext.
/// Adds preload scheduling, seek-preview thumbnail fetching, and TimeIndex.
/// The binary module "PreLoadIOContext" takes its name from this class.
///
/// RE: 1.3.15 -- 18 named symbols (after mislabel strikes ~9 genuine).
/// `_TtC16PreLoadIOContext16PreLoadIOContext`.
/// 9 binary fields: loadMoreBuffer, fakeUrlPos, isPreloadPaused, _timeIndex,
/// _timeIndexLock, minBufferSecondsForThumbnail, videoDuration,
/// thumbnailFetchRequest, thumbnailFetchResult.
open class PreLoadIOContext: CacheIOContext {
    // MARK: - 9 binary fields

    /// RE: field 1 -- preload scratch buffer.
    /// String `loadMoreBuffer` @ 0x103344a09.
    /// Accessor setLoadMoreBuffer @ 0x1014d8a64 (modify-yield coroutine).
    public var loadMoreBuffer: UnsafeMutablePointer<UInt8>?

    /// RE: field 2 -- virtual URL cursor. Field-offset symbol
    /// `_TtC16PreLoadIOContext16PreLoadIOContext::fakeUrlPos`.
    /// Writers: getFakeUrlPos @ 0x10157a05c/0x10157a0c0/0x10157f744.
    public var fakeUrlPos: UInt64 = 0

    /// RE: field 3 -- whether preload scheduling is currently paused.
    /// Anchored by mangled property descriptor `5isPreloadPausedSbv` @ 0x10469b230
    /// and log strings "[PreloadMore] return -1: isPreloadPaused=true".
    /// Real ldrb accessor inlined into LimitPreLoadIOContext_deallocPartial @ 0x101579d5c.
    public var isPreloadPaused: Bool = false

    /// RE: field 4 -- sorted (position, time) index for byte-to-time mapping.
    public var _timeIndex: [TimeIndexEntry] = []

    /// RE: field 5 -- guards mutation of _timeIndex.
    public let _timeIndexLock = NSLock()

    /// RE: field 6 -- minimum buffered seconds before thumbnail fetch.
    public var minBufferSecondsForThumbnail: Double = 0

    /// RE: field 7 -- cached total video duration (seconds).
    public var videoDuration: Double = 0

    /// RE: field 8 -- pending seek-preview thumbnail fetch: byte offset and size.
    public var thumbnailFetchRequest: (offset: UInt64, size: Int32)?

    /// RE: field 9 -- status/result of last thumbnail fetch.
    public var thumbnailFetchResult: Int32 = 0

    private var preloadQueue = [URL]()
    private var preloadedContexts = [String: PreLoadIOContext]()
    private var preloadTask: Task<Void, Never>?
    private let scheduleLock = NSLock()

    // MARK: - Preload scheduling

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
            // Preload moov region
            self.scheduleLock.lock()
            self.preloadedContexts[url.absoluteString] = context
            self.preloadTask = nil
            self.scheduleLock.unlock()
            self.scheduleLock.lock()
            self.startPreloadIfNeeded()
            self.scheduleLock.unlock()
        }
    }

    // MARK: - URLContextDownload wiring

    /// RE: 0x10157f818 (PreLoadIOContext_initURLDownload, 1.3.15) TRACED.
    /// Genuine preload-to-URLContextDownload construction + AVIO-open wiring.
    /// Builds URL, calls CacheIOContext_openURL, constructs URLContextDownload
    /// conformance, dispatches open witness with 256 KB buffer.
    public func initURLDownload(url: URL) {
        openURL(url, formatOptions: formatContextOptions)
    }

    // MARK: - Thumbnail fetch

    /// RE: 0x10157ba0c (deallocFields = thumbnailFetchResolver, 1.3.15)
    /// Binary-searches entryList by position/size and writes thumbnailFetchRequest.
    public func resolveThumbnailFetch(targetOffset: UInt64) {
        downloadLock.lock()
        defer { downloadLock.unlock() }

        // Binary search entryList for entry containing targetOffset
        var lo = 0
        var hi = entryList.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let entry = entryList[mid]
            let entryPos = entry.position
            let entryEnd = entryPos + UInt64(entry.size)
            if targetOffset < entryPos {
                hi = mid - 1
            } else if targetOffset < entryEnd {
                // Found: write thumbnailFetchRequest
                thumbnailFetchRequest = (offset: entryPos, size: Int32(entry.size))
                return
            } else {
                lo = mid + 1
            }
        }
        thumbnailFetchRequest = nil
    }

    // MARK: - TimeIndex management

    /// Add a time-to-byte index entry (thread-safe).
    public func addTimeIndexEntry(_ entry: TimeIndexEntry) {
        _timeIndexLock.lock()
        defer { _timeIndexLock.unlock() }
        // Insert sorted by position
        var lo = 0
        var hi = _timeIndex.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if _timeIndex[mid].position < entry.position {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        _timeIndex.insert(entry, at: lo)
    }
}

// MARK: - LimitPreLoadIOContext

/// Moov protection + cached-range distribution.
/// Subclass of PreLoadIOContext (corrected from earlier doc error that said LimitCacheIOContext).
///
/// RE: 1.3.15 -- 13 named Ghidra symbols.
/// `_TtC16PreLoadIOContext21LimitPreLoadIOContext`.
/// 10 additional binary fields beyond PreLoadIOContext.
/// metadataInit @ 0x101578774 confirms 13 field count.
open class LimitPreLoadIOContext: PreLoadIOContext {
    // MARK: - Confirmed stored properties (mangled names + string anchors)

    /// RE: moovProtectionSize: UInt64. String anchor 0x1033441d0, 0x103749a50.
    /// Mangled descriptor moovProtectionSizes6UInt64Vv. Default 10 * 1024 * 1024 = 0xA00000.
    public let moovProtectionSize: UInt64 = 10 * 1024 * 1024

    /// RE: playbackBytePosition: UInt64?. String anchor 0x1033441f0, 0x103749a70.
    /// Mangled descriptor playbackBytePositions6UInt64VSgv.
    public var playbackBytePosition: UInt64?

    /// RE: canPreload: Bool. String anchor 0x10334419e, 0x103749a10.
    public var canPreload: Bool = true

    // MARK: - Additional stored properties (from refreshed 1.3.15 inventory)

    /// RE: per-instance max file size (shadows/overrides LimitCacheIOContext value).
    public var maxFileSize: UInt64 = 0

    /// RE: high-water mark of bytes read.
    public var maxReadedFileSize: UInt64 = 0

    /// RE: timestamp of last preload sync. Init to -1.0 per resetSyncState.
    public var _lastSyncedTime: Double = -1.0

    /// RE: minimum interval between sync passes.
    public var syncThreshold: Double = 1.0

    /// RE: cache size at last check (used in 4 MiB hysteresis).
    public var lastCheckCacheSize: UInt64 = 0

    /// RE: threshold for triggering cache eviction.
    public var deleteCheckThreshold: UInt64 = 0

    /// RE: cached-range distribution -- variable-length tuple structure,
    /// NOT a fixed 256-slot array. The "256 slots" figure is dropped per doc.
    /// Partitions cached bytes into readed/contiguousPreload/disconnected ranges.
    public var cachedDistribution: (
        readed: UInt64,
        contiguousPreload: UInt64,
        disconnected: UInt64,
        marker: UInt64,
        isValid: Bool
    ) = (0, 0, 0, 0x100, false)

    /// RE: logical position distribution was computed at.
    public var cachedDistributionLogicalPos: UInt64 = 0

    /// RE: number of entries in the distribution.
    public var cachedDistributionEntryCount: Int = 0

    /// RE: last computed total cached size.
    public var lastKnownCachedSize: UInt64 = 0

    // MARK: - Moov caching

    private var moovCached = false
    private let preloadLock = NSLock()

    /// Target preload size in bytes (set by caller based on buffer duration * bitrate).
    public var preloadTargetSize: Int64 = 0

    public convenience init(url: URL, cacheSize: Double) {
        self.init(url: url)
        self.preloadTargetSize = Int64(max(cacheSize, 0))
    }

    /// Ensure the moov atom region (first 10 MB) is cached for fast seeking.
    public func ensureMoovCached() {
        preloadLock.lock()
        defer { preloadLock.unlock() }
        guard !moovCached else { return }
        let fileTotal = fileSize()
        guard fileTotal > 0 else { return }
        let moovEndI64 = min(Int64(moovProtectionSize), fileTotal)
        if cachedSize >= moovEndI64 {
            moovCached = true
            return
        }
        let savedPos = logicalPos
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
        _ = seek(offset: Int64(savedPos), whence: 0)
        moovCached = true
    }

    // MARK: - Playback position sync

    /// RE: 0x101572920 (getSaveFileStatus = playbackBytePositionSync, 1.3.15)
    /// Syncs playbackBytePosition from currentTime with 1-second throttle.
    /// 100 MiB floor on total cached bytes. Uses TimeIndex interpolation
    /// via FUN_10157afb8 when eof + partial cache.
    public func syncPlaybackBytePosition(currentTime: Double, duration: Double) {
        // 1-second throttle
        guard abs(currentTime - _lastSyncedTime) >= 1.0 else { return }
        _lastSyncedTime = currentTime
        guard duration > 0 else { return }

        let bytePos: UInt64
        if eof, end != 0 {
            // EOF + partial cache: use TimeIndex interpolation
            bytePos = interpolateBytePosition(
                currentTime: currentTime,
                duration: duration,
                totalCachedBytes: UInt64(cachedSize)
            )
        } else {
            // Early/no partial: proportional estimate with 100 MiB floor
            var totalCached = UInt64(cachedSize)
            if totalCached < 0x6400000 { // 100 MiB floor
                totalCached = 0x6400000
            }
            bytePos = UInt64(currentTime / duration * Double(totalCached))
        }
        playbackBytePosition = bytePos
    }

    /// RE: 0x10157afb8 (TimeIndex interpolation, 1.3.15)
    /// Binary-searches _timeIndex entries, linearly interpolates byte position.
    /// Locks _timeIndexLock.
    func interpolateBytePosition(
        currentTime: Double,
        duration: Double,
        totalCachedBytes: UInt64
    ) -> UInt64 {
        _timeIndexLock.lock()
        let entries = _timeIndex
        _timeIndexLock.unlock()

        guard !entries.isEmpty else {
            // Fallback: proportional
            return UInt64(currentTime / duration * Double(totalCachedBytes))
        }

        // Binary search for bracketing time
        var lo = 0
        var hi = entries.count - 1

        if currentTime <= entries[0].time {
            return entries[0].position
        }
        if currentTime >= entries[entries.count - 1].time {
            return entries[entries.count - 1].position
        }

        while lo < hi - 1 {
            let mid = (lo + hi) / 2
            if entries[mid].time <= currentTime {
                lo = mid
            } else {
                hi = mid
            }
        }

        // Linear interpolation between lo and hi
        let t0 = entries[lo].time
        let t1 = entries[hi].time
        let p0 = entries[lo].position
        let p1 = entries[hi].position
        guard t1 > t0 else { return p0 }

        let fraction = (currentTime - t0) / (t1 - t0)
        let interpolated = Double(p0) + fraction * Double(p1 - p0)
        return UInt64(max(min(interpolated, Double(totalCachedBytes)), 0))
    }

    /// RE: 0x101572b54 (getSeekOffsetsHelper = resetSyncState, 1.3.15)
    /// Writes playbackBytePosition = 0, _lastSyncedTime = -1.0.
    public func resetSyncState() {
        playbackBytePosition = 0
        _lastSyncedTime = -1.0
    }

    /// RE: 0x101577ccc (handlePartialRange = cacheFillFraction, 1.3.15)
    /// On LimitPreLoadIOContext: sums CacheFileEntry sizes,
    /// returns min(fetchedSize_MB / maxFileSize_MB, 1.0).
    public func cacheFillFraction() -> Double {
        guard maxFileSize > 0 else { return 0 }
        let total = Double(cachedSize)
        let max = Double(maxFileSize)
        return min(total / max, 1.0)
    }
}

// MARK: - LimitCountPreLoadIOContext

/// Adds max-concurrent-preload-request limiting on top of LimitPreLoadIOContext.
///
/// RE: 1.3.15 -- 6 named Ghidra symbols (getMoreCount/setMoreCount,
/// deallocFields(=playbackBytePosition getter), deallocPartial(=setter),
/// deallocate(=metadata init driver), metadataInit).
/// 2 binary fields: maxMoreCount (UInt16), moreCount (UInt16).
open class LimitCountPreLoadIOContext: LimitPreLoadIOContext {
    /// RE: field 1 -- maximum additional preload requests allowed. Binary type UInt16.
    public var maxMoreCount: UInt16 = 8

    /// RE: field 2 -- current count of additional preload requests. Binary type UInt16.
    /// Accessors getMoreCount @ 0x1015783ec / setMoreCount @ 0x1015784a0.
    public var moreCount: UInt16 = 0

    private let countLock = NSLock()

    public func canStartPreload() -> Bool {
        countLock.lock()
        defer { countLock.unlock() }
        return moreCount < maxMoreCount
    }

    public func beginPreload() {
        countLock.lock()
        defer { countLock.unlock() }
        moreCount += 1
    }

    public func endPreload() {
        countLock.lock()
        defer { countLock.unlock() }
        if moreCount > 0 { moreCount -= 1 }
    }

    public var currentPreloadCount: UInt16 {
        countLock.lock()
        defer { countLock.unlock() }
        return moreCount
    }
}

// MARK: - ReadCacheIOContext (standalone)

/// Cache-first read context with explicit AVERROR_EOF handling. Separate from the
/// CacheIOContext chain -- direct subclass of AbstractAVIOContext, uses composition.
///
/// RE: 1.3.15. 7 binary fields.
/// `_TtC16PreLoadIOContext18ReadCacheIOContext`.
/// Op-table at 0x103d178f0: read slot +0x30, seek slot +0x40, close slot +0x50.
/// Avio read callback @ 0x10157fb6c: AVERROR_EOF (0xDFB9B0BB) fast-path,
/// findCacheEntry binary search, cache HIT disk read, cache MISS with onlyCache gate.
/// Avio seek callback @ 0x1015802a8: SEEK_END/CUR/SET + findCacheEntry HIT/MISS.
open class ReadCacheIOContext: AbstractAVIOContext {
    /// AVERROR_EOF constant: 0xDFB9B0BB = -541478725.
    private static let avErrorEOF: Int32 = -541_478_725

    // MARK: - 7 binary fields

    /// RE: field 1 -- the download backend (DownloadProtocol, same slot as CacheIOContext.download).
    /// Existential box spans self+0x18..+0x40 in binary; instance at self+0x30,
    /// witness table at self+0x38. Witness slots: [+0x28]=read, [+0x30]=seek, [+0x40]=close.
    private let download: DownloadProtocol

    /// RE: field 2 -- on-disk cache directory.
    private let tmpURL: URL

    /// RE: field 3 -- when true, reads served strictly from cache, no network fallback.
    /// The distinguishing field that gates cache-miss behavior.
    /// RE: 0x10157f97c (init, 1.3.15) -- `onlyCache = param_5`
    public let onlyCache: Bool

    /// RE: field 4 -- set when cached range is exhausted.
    private var eof: Bool = false

    /// RE: field 5 -- total/end byte position.
    private var end: UInt64 = 0

    /// RE: field 6 -- current logical read cursor.
    private var logicalPos: UInt64 = 0

    /// RE: field 7 -- underlying URL/file read position.
    private var urlPos: UInt64 = 0

    private var entries: [CacheFileEntry] = []
    private let lock = NSRecursiveLock()

    /// RE: 0x10157f97c (ReadCacheIOContext_init, 1.3.15)
    public init(url: URL, download: DownloadProtocol? = nil, onlyCache: Bool = false) {
        if let dl = download {
            self.download = dl
        } else {
            self.download = URLContextDownload(url: url)
        }
        self.onlyCache = onlyCache
        let md5 = Self.md5Hash(url.absoluteString)
        let tempDir = FileManager.default.temporaryDirectory
        self.tmpURL = tempDir.appendingPathComponent("videoCaches/\(md5)", isDirectory: true)
        super.init(bufferSize: 32 * 1024, writable: false)
        try? FileManager.default.createDirectory(at: tmpURL, withIntermediateDirectories: true)
        loadExistingEntries()
    }

    // MARK: - Avio read callback

    /// RE: 0x10157fb6c (avio read_packet callback, 1.3.15) LIVE-via-struct at table slot +0x30.
    /// AVERROR_EOF fast-path (0xDFB9B0BB), findCacheEntry binary search,
    /// cache HIT disk read, cache MISS with onlyCache gate, download existential dispatch.
    override open func read(buffer: UnsafePointer<UInt8>?, size: Int32) -> Int32 {
        lock.lock()
        defer { lock.unlock() }

        // EOF fast-path
        if logicalPos == end, eof {
            return Self.avErrorEOF
        }

        let length = Int(size)

        // Cache HIT: binary search + disk read
        if let entry = findCacheEntry(forPosition: logicalPos) {
            let offsetInSegment = logicalPos - entry.position
            if let data = entry.readData(at: offsetInSegment, length: length), !data.isEmpty {
                if let buf = UnsafeMutablePointer(mutating: buffer) {
                    data.copyBytes(to: buf, count: data.count)
                }
                logicalPos += UInt64(data.count)
                return Int32(data.count)
            }
        }

        // Cache MISS with onlyCache gate
        if onlyCache {
            return -1
        }

        // Download existential dispatch
        let seekResult = download.seek(to: Int64(logicalPos), whence: 0)
        guard seekResult >= 0, let buf = UnsafeMutablePointer(mutating: buffer) else {
            return -1
        }
        let result = download.read(into: buf, count: Int32(min(length, Int(size))))
        if result > 0 {
            let data = Data(bytes: buf, count: Int(result))
            storeToDisk(data, at: logicalPos)
            logicalPos += UInt64(result)
            urlPos = logicalPos
            if download.totalFileSize > 0 {
                end = UInt64(download.totalFileSize)
            }
        } else if result == Self.avErrorEOF || (download.totalFileSize > 0 && Int64(logicalPos) >= download.totalFileSize) {
            eof = true
            if download.totalFileSize > 0 {
                end = UInt64(download.totalFileSize)
            }
        }
        return result
    }

    // MARK: - Avio seek callback

    /// RE: 0x1015802a8 (avio seek callback, 1.3.15) LIVE-via-struct at table slot +0x40.
    /// Handles SEEK_END/SEEK_CUR/SEEK_SET, findCacheEntry for HIT/MISS with onlyCache gate,
    /// download witness dispatch.
    override open func seek(offset: Int64, whence: Int32) -> Int64 {
        lock.lock()
        defer { lock.unlock() }

        var target: Int64
        switch whence {
        case 2: // SEEK_END -- only if eof
            guard eof else { return -1 }
            target = Int64(end) + offset
        case 1: // SEEK_CUR
            target = Int64(logicalPos) + offset
        case 0: // SEEK_SET
            target = offset
        default:
            return -1
        }

        guard target >= 0 else { return -1 }

        // Cache HIT seek: no I/O needed
        if findCacheEntry(forPosition: UInt64(target)) != nil {
            logicalPos = UInt64(target)
            return target
        }

        // Cache MISS with onlyCache gate
        if onlyCache {
            return -1
        }

        // Download witness dispatch for seek
        let result = download.seek(to: target, whence: 0)
        if result >= 0 {
            logicalPos = UInt64(result)
            urlPos = logicalPos
        }
        return result
    }

    override open func fileSize() -> Int64 { download.totalFileSize }

    /// RE: 0x101580dac (close_helper, 1.3.15)
    /// Releases the download backend via protocol witness dispatch.
    override open func close() {
        download.close()
    }

    // MARK: - Cache entry management

    /// RE: 0x101580df0 (findCacheEntry, 1.3.15)
    /// Cache-directory scan: parses filenames as byte positions, sorts, builds CacheFileEntry.
    /// Uses binary search for lookup.
    private func findCacheEntry(forPosition pos: UInt64) -> CacheFileEntry? {
        var lo = 0
        var hi = entries.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let entry = entries[mid]
            let entryPos = entry.position
            let entryEnd = entryPos + UInt64(entry.size)
            if pos < entryPos {
                hi = mid - 1
            } else if pos < entryEnd {
                return entry
            } else {
                lo = mid + 1
            }
        }
        return nil
    }

    /// RE: 0x10157e408 (initCacheEntries, 1.3.15)
    /// Builds [CacheFileEntry] from input array handling both native-Swift and
    /// _CocoaArrayWrapper backings.
    private func loadExistingEntries() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: tmpURL, includingPropertiesForKeys: [.fileSizeKey]) else { return }
        for fileURL in contents {
            let name = fileURL.lastPathComponent
            if name == "end.txt" {
                if let text = try? String(contentsOf: fileURL, encoding: .utf8),
                   let totalSize = UInt64(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    end = totalSize
                    eof = true
                }
                continue
            }
            guard let pos = Int64(name) else { continue }
            let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            let size = UInt32(clamping: attrs?.fileSize ?? 0)
            entries.append(CacheFileEntry(url: fileURL, position: UInt64(pos), size: size))
        }
        entries.sort { $0.position < $1.position }
    }

    private func storeToDisk(_ data: Data, at pos: UInt64) {
        let segmentFile = tmpURL.appendingPathComponent("\(pos)")
        if let idx = entries.firstIndex(where: { $0.position == pos }) {
            // Append to existing segment via CacheFileEntry.append
            entries[idx].append(data)
        } else {
            // Create new segment file and entry
            FileManager.default.createFile(atPath: segmentFile.path, contents: data)
            entries.append(CacheFileEntry(url: segmentFile, position: pos, size: UInt32(data.count)))
            entries.sort { $0.position < $1.position }
        }
    }

    public var cachedSize: Int64 {
        entries.reduce(0) { $0 + Int64($1.size) }
    }

    public func purge() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
        try? FileManager.default.removeItem(at: tmpURL)
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
