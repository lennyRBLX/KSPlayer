//
//  HLSCacheIOContext.swift
//  KSPlayer
//
//  Forward addition (RE): HLS segment cache for M3U8-based streams.
//  Caches individual TS/fMP4 segments for seamless playback and
//  bandwidth optimization.
//
//  Binary: _TtC16PreLoadIOContext17HLSCacheIOContext (class metadata only)
//  Binary module: PreLoadIOContext (kept under KSPlayer in source)
//  RE source: Forward v1.3.15
//

import Foundation

public class HLSCacheIOContext: CacheIOContext {
    private var segmentCache: [String: Data] = [:]
    private var m3u8Content: String?
    private let segmentLock = NSLock()

    public func cacheSegment(key: String, data: Data) {
        segmentLock.lock()
        defer { segmentLock.unlock() }
        segmentCache[key] = data
    }

    public func cachedSegment(for key: String) -> Data? {
        segmentLock.lock()
        defer { segmentLock.unlock() }
        return segmentCache[key]
    }

    public func cacheM3U8(_ content: String) {
        m3u8Content = content
    }

    public func cachedM3U8() -> String? {
        m3u8Content
    }

    public func clearSegmentCache() {
        segmentLock.lock()
        defer { segmentLock.unlock() }
        segmentCache.removeAll()
        m3u8Content = nil
    }
}
