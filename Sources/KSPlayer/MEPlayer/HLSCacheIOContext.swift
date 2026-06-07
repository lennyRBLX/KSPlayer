//
//  HLSCacheIOContext.swift
//  KSPlayer
//
//  HLS segment cache context -- manages per-segment CacheIOContext
//  instances for M3U8-based streams with playlist parsing, prefetch,
//  and on-disk caching.
//
//  Binary: _TtC16PreLoadIOContext17HLSCacheIOContext (class metadata @ 0x103343dd0)
//  Binary module: PreLoadIOContext (kept under KSPlayer in source)
//  RE source: v1.3.15
//
//  NOTE: No named function symbols carry the HLSCacheIOContext prefix in
//  Ghidra (search returns zero). All methods are unnamed/interior. Type is
//  present via class metadata + the refreshed inventory. Method bodies below
//  are reconstructed from binary field layout, the cache hierarchy patterns
//  established by CacheIOContext, and the 14-field inventory.
//

import Foundation

/// HLS-aware cache wrapper. Subclass of `AbstractAVIOContext` (per the refreshed
/// inventory -- structurally it derives from `AbstractAVIOContext` and *contains*
/// per-segment `CacheIOContext` instances in `subContexts`, rather than inheriting
/// from `CacheIOContext`).
///
/// RE: _TtC16PreLoadIOContext17HLSCacheIOContext (class metadata, 1.3.15)
/// Binary source file: PreLoadIOContext/HLSCacheIOContext.swift (0x103343a90)
open class HLSCacheIOContext: AbstractAVIOContext {
    // MARK: - Binary fields (14, from the refreshed 1.3.15 inventory)

    /// RE: field 1/14 -- underlying HTTP download context for playlist/segment fetches.
    public var download: URLContextDownload

    /// RE: field 2/14 -- stream/media identifier.
    public var mediaId: String

    /// RE: field 3/14 -- base URL for resolving relative segment URLs.
    public var baseURL: URL

    /// RE: field 4/14 -- FFmpeg format-context options passed through to sub-contexts.
    public var formatContextOptions: [String: Any]

    /// RE: field 5/14 -- on-disk directory for HLS cache.
    public var hlsCacheDir: URL

    /// RE: field 6/14 -- buffered playlist text (raw M3U8 content).
    public var m3u8Buffer: Data?

    /// RE: field 7/14 -- whether the playlist has been parsed.
    public var m3u8Parsed: Bool

    /// RE: field 8/14 -- parsed segment list (URL strings extracted from M3U8).
    public var segments: [String]

    /// RE: field 9/14 -- per-segment cache contexts, keyed by segment URL.
    /// Each segment gets its own `CacheIOContext` for independent disk caching.
    public var subContexts: [String: CacheIOContext]

    /// RE: field 10/14 -- guards `subContexts` dictionary access.
    private let subContextsLock: NSLock

    /// RE: field 11/14 -- nested HLS contexts for variant/alternate playlists.
    public var childHLSContexts: [HLSCacheIOContext]

    /// RE: field 12/14 -- number of segments to prefetch ahead of playback position.
    public var prefetchCount: Int

    /// RE: field 13/14 -- dispatch queue for prefetch work.
    public let prefetchQueue: DispatchQueue

    /// RE: field 14/14 -- closed-state flag.
    public var isClosed: Bool

    // MARK: - Init

    /// Initialize an HLS cache context for the given media stream.
    ///
    /// - Parameters:
    ///   - url: The base URL of the HLS stream (typically the M3U8 playlist URL).
    ///   - mediaId: Stream/media identifier.
    ///   - formatContextOptions: FFmpeg format-context options to propagate to sub-contexts.
    ///   - prefetchCount: Number of segments to prefetch ahead. Defaults to 3.
    public init(
        url: URL,
        mediaId: String,
        formatContextOptions: [String: Any] = [:],
        prefetchCount: Int = 3
    ) {
        self.download = URLContextDownload(url: url)
        self.mediaId = mediaId
        self.baseURL = url.deletingLastPathComponent()
        self.formatContextOptions = formatContextOptions

        // On-disk cache: NSTemporaryDirectory()/videoCaches/hls_<md5>/
        let md5 = CacheIOContext.md5Hash(url.absoluteString)
        let tempDir = FileManager.default.temporaryDirectory
        self.hlsCacheDir = tempDir.appendingPathComponent("videoCaches/hls_\(md5)", isDirectory: true)

        self.m3u8Buffer = nil
        self.m3u8Parsed = false
        self.segments = []
        self.subContexts = [:]
        self.subContextsLock = NSLock()
        self.childHLSContexts = []
        self.prefetchCount = prefetchCount
        self.prefetchQueue = DispatchQueue(label: "com.ksplayer.hlscache.prefetch", qos: .utility)
        self.isClosed = false

        super.init(bufferSize: Int32(URLContextDownload.downloadBufferSize), writable: false)

        try? FileManager.default.createDirectory(at: hlsCacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Playlist handling

    /// Store raw M3U8 playlist data and mark as unparsed.
    public func storePlaylist(_ data: Data) {
        m3u8Buffer = data
        m3u8Parsed = false
    }

    /// Parse the buffered M3U8 playlist, extracting segment URLs.
    /// Resolves relative URLs against `baseURL`.
    public func parsePlaylist() {
        guard let buffer = m3u8Buffer,
              let content = String(data: buffer, encoding: .utf8),
              !m3u8Parsed else {
            return
        }

        var parsed: [String] = []
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip M3U8 tags and empty lines
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            // Resolve relative segment URLs against baseURL
            if let segmentURL = URL(string: trimmed, relativeTo: baseURL) {
                parsed.append(segmentURL.absoluteString)
            } else {
                parsed.append(trimmed)
            }
        }

        segments = parsed
        m3u8Parsed = true
    }

    // MARK: - Sub-context management

    /// Get or create a `CacheIOContext` for the given segment URL.
    /// Thread-safe via `subContextsLock`.
    public func subContext(for segmentURL: String) -> CacheIOContext? {
        subContextsLock.lock()
        defer { subContextsLock.unlock() }

        if let existing = subContexts[segmentURL] {
            return existing
        }

        guard let url = URL(string: segmentURL) else { return nil }
        let context = CacheIOContext(url: url)
        subContexts[segmentURL] = context
        return context
    }

    /// Remove and close the sub-context for a given segment URL.
    public func removeSubContext(for segmentURL: String) {
        subContextsLock.lock()
        defer { subContextsLock.unlock() }

        if let context = subContexts.removeValue(forKey: segmentURL) {
            context.close()
        }
    }

    // MARK: - Prefetch

    /// Trigger prefetch for segments starting at the given index.
    /// Creates sub-contexts for up to `prefetchCount` segments ahead.
    public func prefetchSegments(from index: Int) {
        guard m3u8Parsed, !isClosed else { return }
        let endIndex = min(index + prefetchCount, segments.count)
        guard index < endIndex else { return }

        let segmentsToFetch = Array(segments[index..<endIndex])
        prefetchQueue.async { [weak self] in
            guard let self, !self.isClosed else { return }
            for segmentURL in segmentsToFetch {
                // Creating a sub-context triggers the cache infrastructure
                _ = self.subContext(for: segmentURL)
            }
        }
    }

    // MARK: - Child HLS contexts (variant playlists)

    /// Add a child HLS context for a variant/alternate playlist.
    public func addChildContext(_ child: HLSCacheIOContext) {
        childHLSContexts.append(child)
    }

    /// Remove and close all child HLS contexts.
    public func removeAllChildContexts() {
        for child in childHLSContexts {
            child.close()
        }
        childHLSContexts.removeAll()
    }

    // MARK: - AbstractAVIOContext overrides

    override open func close() {
        guard !isClosed else { return }
        isClosed = true

        // Close all sub-contexts
        subContextsLock.lock()
        for (_, context) in subContexts {
            context.close()
        }
        subContexts.removeAll()
        subContextsLock.unlock()

        // Close child HLS contexts
        removeAllChildContexts()

        // Close underlying download context
        download.close()

        super.close()
    }
}
