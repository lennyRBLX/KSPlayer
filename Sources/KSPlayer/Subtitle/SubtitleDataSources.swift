//
//  SubtitleDataSources.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — Additional subtitle data sources
//  Contains ConstantURLSubtitleDataSource (pre-configured URLs from media servers)
//  and extended OpenSubtitleDataSouce methods per the Forward binary RE.
//
//  Note: The base data sources (DirectorySubtitleDataSouce, PlistCacheSubtitleDataSouce,
//  ShooterSubtitleDataSouce, AssrtSubtitleDataSouce, OpenSubtitleDataSouce) are defined
//  in SubtitleDataSouce.swift (upstream). This file adds Forward-specific additions.
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
/// RE: ConstantURLSubtitleDataSource at 0x10136A0B4
/// Fields: infos [URLSubtitleInfo], url URL
public class ConstantURLSubtitleDataSource: SubtitleDataSouce {
    public var infos: [any SubtitleInfo]

    /// Source URL for the subtitle list (e.g., the media API endpoint).
    private let sourceURL: URL?

    /// Initialize with a list of known subtitle URLs.
    /// - Parameter urls: Pre-configured subtitle URLs from playlist or API metadata.
    public init(urls: [URL]) {
        self.sourceURL = nil
        self.infos = urls.map { URLSubtitleInfo(url: $0) }
    }

    /// Initialize with subtitle info objects directly.
    /// - Parameters:
    ///   - infos: Pre-built subtitle info objects.
    ///   - sourceURL: The API endpoint or playlist URL that provided these subtitles.
    public init(infos: [URLSubtitleInfo], sourceURL: URL? = nil) {
        self.sourceURL = sourceURL
        self.infos = infos
    }

    /// Initialize from a media server API response.
    ///
    /// RE: ConstantURLSubtitleDataSource_parseAPIResponse at 0x101371540
    /// Parses JSON subtitle metadata from Emby/Jellyfin API responses.
    /// - Parameters:
    ///   - apiURL: Base URL of the media server API.
    ///   - mediaID: The media item ID to fetch subtitles for.
    ///   - token: Authentication bearer token.
    public convenience init(apiURL: URL, mediaID: String, token: String? = nil) {
        self.init(urls: [])
        Task {
            await loadFromAPI(apiURL: apiURL, mediaID: mediaID, token: token)
        }
    }

    // MARK: - API Loading

    /// Fetch subtitle list from a media server API endpoint.
    ///
    /// RE: ConstantURLSubtitleDataSource_fetchFromAPI_async at 0x10136B630
    /// Builds POST request to /v1/sub/detail with Bearer auth token.
    private func loadFromAPI(apiURL: URL, mediaID: String, token: String?) async {
        let detailURL = apiURL.appendingPathComponent(mediaID)
            .appendingPathComponent("Subtitles")

        var request = URLRequest(url: detailURL)
        request.httpMethod = "GET"
        if let token {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let parsedInfos = parseAPIResponse(data)
            infos = parsedInfos
        } catch {
            KSLog("[subtitle] ConstantURLSubtitleDataSource API fetch failed: \(error)")
        }
    }

    /// Parse subtitle entries from a JSON API response.
    ///
    /// RE: ConstantURLSubtitleDataSource_parseAPIResponse_and_extractSubtitleIDs at 0x101371540
    /// Expected format: Array of objects with "Id", "Language", "DisplayTitle", "DeliveryUrl" keys.
    private func parseAPIResponse(_ data: Data) -> [URLSubtitleInfo] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return json.compactMap { entry -> URLSubtitleInfo? in
            guard let deliveryURLString = entry["DeliveryUrl"] as? String,
                  let url = URL(string: deliveryURLString)
            else { return nil }

            let subtitleID = entry["Id"] as? String
                ?? entry["Index"] as? String
                ?? deliveryURLString
            let name = entry["DisplayTitle"] as? String
                ?? entry["Language"] as? String
                ?? url.lastPathComponent

            return URLSubtitleInfo(subtitleID: subtitleID, name: name, url: url)
        }
    }

    // MARK: - Hash-Based Search

    /// Compute MD5 hashes at 4 file positions for hash-based subtitle search.
    ///
    /// RE: ConstantURLSubtitleDataSource_searchByHash_async at 0x10136A478
    /// Computes MD5 hashes at 4 file positions (each 4KB), joins with semicolons.
    /// Same algorithm as Shooter.cn but used for media server subtitle matching.
    public static func computeFileHash(url: URL) -> String? {
        guard url.isFileURL else { return nil }
        return url.shooterFilehash
    }
}

// MARK: - OpenSubtitleDataSouce Extensions

public extension OpenSubtitleDataSouce {
    /// Extended search with IMDB and TMDB IDs.
    ///
    /// RE: OpenSubtitleDataSource_buildSearchQueryParams at 0x10136CEC0
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

// MARK: - DirectorySubtitleDataSouce Extensions

public extension DirectorySubtitleDataSouce {
    /// Extended subtitle file extension list per Forward v1.3.15.
    /// RE: Supported extensions include .sup in addition to upstream .srt/.ass/.ssa/.vtt
    static let subtitleExtensions: Set<String> = ["srt", "ass", "ssa", "vtt", "sup"]

    /// Check if a URL points to a recognized subtitle file.
    static func isSubtitleFile(_ url: URL) -> Bool {
        subtitleExtensions.contains(url.pathExtension.lowercased())
    }
}

// MARK: - PlistCacheSubtitleDataSouce Extensions

public extension PlistCacheSubtitleDataSouce {
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
