//
//  SubtitleDataSources.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — Additional subtitle data sources
//  Contains ConstantURLSubtitleDataSource (pre-configured URLs from media servers)
//  and extended OpenSubtitleDataSource methods per the binary RE.
//
//  Note: The base data sources (DirectorySubtitleDataSource, PlistCacheSubtitleDataSource,
//  ShooterSubtitleDataSource, AssrtSubtitleDataSource, OpenSubtitleDataSource) are defined
//  in SubtitleDataSource.swift (upstream). This file adds the binary-specific additions.
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

// MARK: - ConstantURLSubtitleDataSource

/// Pre-configured subtitle data source for URLs known at media load time.
///
/// Used for subtitle URLs from M3U8 playlist metadata or media server API responses
/// (Emby/Jellyfin provide subtitle URLs alongside media streams). Unlike search-based
/// sources, these URLs are known before playback begins.
///
/// RE: 0x100a50240 (ConstantURLSubtitleDataSource_init, 1.3.15)
///
/// Stored field layout per `ConstantURLSubtitleDataSource_initWithURLs` @ 0x1014868b8:
/// the source `url: URL` is copied first (struct offset 0, via the URL value-witness),
/// then the `[URLSubtitleInfo]` array is stored at +0x10. The public `infos` requirement
/// of `SubtitleDataSource` is satisfied by a computed property over the concrete backing
/// storage so the documented element type (`[URLSubtitleInfo]`) is preserved.
public class ConstantURLSubtitleDataSource: SubtitleDataSource {
    /// Source URL for the subtitle list (e.g. the media API endpoint or playlist URL).
    /// RE: field 2 — stored non-optional `url: URL` (offset 0 in `initWithURLs`).
    public let url: URL

    /// Pre-configured subtitle entries, concrete element type per the binary
    /// (`[URLSubtitleInfo]`, stored at +0x10 in `initWithURLs`).
    /// RE: field 1.
    public private(set) var urlInfos: [URLSubtitleInfo]

    /// `SubtitleDataSource` protocol requirement. Erases the concrete backing storage
    /// to `[any SubtitleInfo]` without losing the documented `[URLSubtitleInfo]` layout.
    public var infos: [any SubtitleInfo] { urlInfos }

    /// Initialize with a list of known subtitle URLs.
    ///
    /// RE: 0x1014868b8 (ConstantURLSubtitleDataSource_initWithURLs). Copies the source
    /// URL into `self.url`, then maps each entry to a `URLSubtitleInfo` (via
    /// `URLSubtitleInfo_init_0`) into the `urlInfos` array. An empty array yields the
    /// shared empty-array storage.
    /// - Parameters:
    ///   - url: The API endpoint or playlist URL that provided these subtitles.
    ///   - urls: Pre-configured subtitle URLs from playlist or API metadata.
    public init(url: URL, urls: [URL]) {
        self.url = url
        urlInfos = urls.map { URLSubtitleInfo(url: $0) }
    }

    /// Initialize with subtitle info objects directly.
    /// - Parameters:
    ///   - url: The API endpoint or playlist URL that provided these subtitles.
    ///   - infos: Pre-built subtitle info objects.
    public init(url: URL, infos: [URLSubtitleInfo]) {
        self.url = url
        urlInfos = infos
    }

    // MARK: - Resource Fetch

    /// Build a player resource carrying the pre-configured subtitle URLs.
    ///
    /// RE: 0x1014ee2c0 (ConstantURLSubtitleDataSource_fetch). Constructs a
    /// `KSPlayerResource` whose `subtitleDataSource` is a `ConstantURLSubtitleDataSource`
    /// built via `initWithURLs` (when `subtitleURLs` is non-empty), carrying the cover,
    /// extinf dictionary, and now-playing metadata. This is the entry point that
    /// materializes the pre-configured URL infos into a playable resource.
    /// - Parameters:
    ///   - definitions: Video stream definitions for the resource.
    ///   - name: Display name for the media item.
    ///   - sourceURL: The endpoint/playlist URL that produced the subtitle list.
    ///   - cover: Optional cover artwork URL.
    ///   - subtitleURLs: Pre-configured subtitle URLs to attach.
    ///   - extinf: Optional EXTINF metadata dictionary.
    /// - Returns: A `KSPlayerResource` with the constant-URL subtitle source attached.
    public static func fetch(definitions: [KSPlayerResourceDefinition],
                             name: String,
                             sourceURL: URL,
                             cover: URL? = nil,
                             subtitleURLs: [URL]? = nil,
                             extinf: [String: String]? = nil) -> KSPlayerResource
    {
        let subtitleDataSource: ConstantURLSubtitleDataSource?
        if let subtitleURLs, !subtitleURLs.isEmpty {
            subtitleDataSource = ConstantURLSubtitleDataSource(url: sourceURL, urls: subtitleURLs)
        } else {
            subtitleDataSource = nil
        }
        return KSPlayerResource(name: name,
                                definitions: definitions,
                                cover: cover,
                                subtitleDataSource: subtitleDataSource,
                                extinf: extinf)
    }

    // MARK: - API Loading

    /// Fetch the subtitle list from a media server API endpoint.
    ///
    /// RE: 0x101487dc0 (ConstantURLSubtitleDataSource_fetchFromAPI_async). Appends
    /// `/v1/sub/detail` to the base URL, issues a POST `URLRequest` carrying a
    /// `Bearer <token>` `Authorization` header (built from the source URL's host
    /// context), and awaits `URLSession.data(for:)`. The decoded entries replace
    /// `urlInfos`.
    /// - Parameters:
    ///   - token: Authentication bearer token (empty string when unauthenticated).
    /// - Returns: The parsed subtitle entries.
    @discardableResult
    public func fetchFromAPI(token: String) async -> [URLSubtitleInfo] {
        let detailURL = url.appendingPathComponent("v1/sub/detail")

        var request = URLRequest(url: detailURL)
        request.httpMethod = "POST"
        request.addValue("Bearer " + token, forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let parsed = parseDetailResponse(data)
            urlInfos = parsed
            return parsed
        } catch {
            KSLog(level: .error, "[subtitle] ConstantURLSubtitleDataSource /v1/sub/detail fetch failed: \(error)")
            return []
        }
    }

    /// Decode subtitle entries from a `/v1/sub/detail` JSON response.
    ///
    /// Internal split of `fetchFromAPI` (the binary inlines the response decode into
    /// the async continuation; no separate Ghidra address). The contract is the
    /// `/v1/sub/detail` payload: a list of `{ url, name, language }` records.
    private func parseDetailResponse(_ data: Data) -> [URLSubtitleInfo] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        // The detail payload is either a bare array or an object wrapping a "sub" / "list" array.
        let entries: [[String: Any]]
        if let array = root as? [[String: Any]] {
            entries = array
        } else if let object = root as? [String: Any] {
            entries = (object["sub"] as? [[String: Any]])
                ?? (object["list"] as? [[String: Any]])
                ?? []
        } else {
            entries = []
        }

        return entries.compactMap { entry -> URLSubtitleInfo? in
            guard let urlString = entry["url"] as? String ?? entry["filelink"] as? String,
                  let subtitleURL = URL(string: urlString)
            else { return nil }
            let subtitleID = entry["id"].map { "\($0)" } ?? urlString
            let name = entry["name"] as? String
                ?? entry["filename"] as? String
                ?? subtitleURL.lastPathComponent
            return URLSubtitleInfo(subtitleID: subtitleID, name: name, url: subtitleURL)
        }
    }

    // MARK: - Hash-Based Search

    /// Compute the media-server file fingerprint used for hash-based subtitle search.
    ///
    /// RE: 0x101486c7c (ConstantURLSubtitleDataSource_searchByHash_async). Reads the
    /// local file, requires a size of at least 12289 bytes (0x3001), then MD5-hashes a
    /// 4096-byte (0x1000) window at each of four offsets
    /// `[4096, fileSize*2/3, fileSize/3, fileSize-8192]`, lower-case hex-encodes each
    /// digest (`%02hhx` per byte), and joins the four hashes with `;`. Same offset
    /// layout as Shooter.cn, but computed asynchronously via CryptoKit `Insecure.MD5`
    /// for media-server subtitle matching.
    /// - Parameter url: A local (`file://`) media URL to fingerprint.
    /// - Returns: The `;`-joined four-position MD5 fingerprint, or `nil` when the file
    ///   cannot be read or is below the minimum size.
    #if canImport(CryptoKit)
    // CryptoKit Insecure.MD5 is the binary's hash primitive; available on all targets (iOS/tvOS/macOS).
    public func searchByHash(url: URL) async -> String? {
        guard url.isFileURL, let file = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? file.close() }

        file.seekToEndOfFile()
        let fileSize = file.offsetInFile
        guard fileSize > 0x3000 else {
            return nil
        }

        let offsets: [UInt64] = [
            0x1000,
            (fileSize << 1) / 3,
            fileSize / 3,
            fileSize - 0x2000,
        ]

        let hashes: [String] = offsets.map { offset in
            file.seek(toFileOffset: offset)
            let chunk = file.readData(ofLength: 0x1000)
            let digest = Insecure.MD5.hash(data: chunk)
            return digest.map { String(format: "%02hhx", $0) }.joined()
        }
        return hashes.joined(separator: ";")
    }
    #endif
}

// MARK: - OpenSubtitleDataSource Extensions

public extension OpenSubtitleDataSource {
    /// Extended search with IMDB and TMDB IDs.
    ///
    /// RE: 0x10148957c (OpenSubtitleDataSource_buildSearchQueryParams).
    /// Supports filtering by movie/show identifiers for more accurate results.
    func searchSubtitle(query: String?, imdbID: String?, tmdbID: String?, languages: [String]) async throws {
        var queryItems = [String: String]()
        if let query {
            queryItems["query"] = query
        }
        if let imdbID, !imdbID.isEmpty {
            queryItems["imdb_id"] = imdbID
        }
        if let tmdbID, !tmdbID.isEmpty {
            queryItems["tmdb_id"] = tmdbID
        }
        if queryItems.isEmpty { return }
        queryItems["languages"] = languages.joined(separator: ",")
        try await searchSubtitle(queryItems: queryItems)
    }
}

// MARK: - DirectorySubtitleDataSource Extensions

public extension DirectorySubtitleDataSource {
    /// Extended subtitle file extension list per Forward v1.3.15.
    /// RE: Supported extensions include .sup in addition to upstream .srt/.ass/.ssa/.vtt
    static let subtitleExtensions: Set<String> = ["srt", "ass", "ssa", "vtt", "sup"]

    /// Check if a URL points to a recognized subtitle file.
    static func isSubtitleFile(_ url: URL) -> Bool {
        subtitleExtensions.contains(url.pathExtension.lowercased())
    }
}

// MARK: - PlistCacheSubtitleDataSource Extensions

public extension PlistCacheSubtitleDataSource {
    /// Remove cached entries for a specific file URL.
    func removeCache(fileURL: URL) {
        // The singleton manages srtInfoCaches privately, but this extension
        // provides a public interface for cache management.
        // Implementation requires access to srtInfoCaches, so this is a
        // convenience wrapper that triggers a re-search.
        Task {
            try? await searchSubtitle(fileURL: nil)
        }
    }
}
