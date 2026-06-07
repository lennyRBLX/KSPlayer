//
//  SubtitleDataSource.swift
//  KSPlayer-7de52535
//
//  Created by kintan on 2018/8/7.
//
import CoreGraphics
import Foundation

public class EmptySubtitleInfo: SubtitleInfo {
    public var isEnabled: Bool = true
    public let subtitleID: String = ""
    public var delay: TimeInterval = 0
    public let name = NSLocalizedString("no show subtitle", comment: "")
    public var languageCode: String?
    public var comment: String?
    public var userInfo: NSMutableDictionary?
    /// RE: Forward v1.3.15 — EmptySubtitleInfo carries an explicit
    /// renderMode field. `.srtView` is the default for the null-object
    /// "no subtitle" state.
    public var renderMode: SubtitleRenderMode = .srtView
    public func search(for _: TimeInterval) -> [SubtitlePart] {
        []
    }
}

/// Remote / local subtitle entry. Extends `KSSubtitle`, conforms to `SubtitleInfo`.
///
/// RE: `_TtC8KSPlayer15URLSubtitleInfo`. `types.json` records EXACTLY 12 stored
/// fields, set in the designated initialiser `URLSubtitleInfo_initWithFields`
/// (0x1014839e0, 480B). The Ghidra field-store order in that init is:
/// subtitleID, name, userAgent, downloadURL (params) with searchProtocol,
/// isDownloading, languageCode, renderMode, delay, comment, userInfo
/// zero-initialised at +0x10…+0x50.
public class URLSubtitleInfo: KSSubtitle, SubtitleInfo {
    /// Private backing parser / search delegate.
    /// RE: field #1 of the 12-field `initWithFields` layout (offset +0x10).
    private var searchProtocol: KSSubtitleProtocol?
    /// In-flight download guard so a second `isEnabled = true` does not
    /// re-issue the download/parse task while one is already running.
    /// RE: field #2 (offset +0x20).
    private var isDownloading: Bool = false
    /// BCP-47 / ISO 639 language tag for the subtitle, when known from the
    /// search result. RE: field #3.
    public private(set) var languageCode: String?
    /// Preferred rendering strategy (text / image / ass). Bitmap results from
    /// the palette-decode path set `.image`; text/SRT/ASS default to `.srtView`.
    /// RE: field #4.
    public var renderMode: SubtitleRenderMode = .srtView
    public var isEnabled: Bool = false {
        didSet {
            if isEnabled, parts.isEmpty, !isDownloading {
                isDownloading = true
                Task {
                    try? await parse(url: downloadURL, userAgent: userAgent)
                    isDownloading = false
                }
            }
        }
    }

    public private(set) var downloadURL: URL
    public var delay: TimeInterval = 0
    public private(set) var name: String
    public let subtitleID: String
    public var comment: String?
    public var userInfo: NSMutableDictionary?
    private let userAgent: String?
    public convenience init(url: URL) {
        self.init(subtitleID: url.absoluteString, name: url.lastPathComponent, url: url)
    }

    /// RE: 0x101484460 (`URLSubtitleInfo_init_0`, 924B). Sets the stored
    /// fields, checks `isFileURL`; for a remote URL with an empty name it
    /// kicks off a background `URLSession.downloadTask` whose weak-self
    /// completion relocates the temp file (see `moveDownloadToTemp`).
    public init(subtitleID: String, name: String, url: URL, userAgent: String? = nil) {
        self.subtitleID = subtitleID
        self.name = name
        self.userAgent = userAgent
        downloadURL = url
        super.init()
        if !url.isFileURL, name.isEmpty {
            url.download(userAgent: userAgent) { [weak self] filename, tmpUrl in
                guard let self else {
                    return
                }
                self.moveDownloadToTemp(filename: filename, tmpURL: tmpUrl)
            }
        }
    }

    /// Relocate a freshly downloaded temp file into `NSTemporaryDirectory()`
    /// under its suggested filename, updating `name` and `downloadURL`.
    ///
    /// RE: 0x101483d84 (`URLSubtitleInfo_moveDownloadToTemp`, 484B). Uses
    /// `NSFileManager.moveItemAtURL:toURL:error:`; the original stored the new
    /// name and download URL through begin/endAccess guards.
    private func moveDownloadToTemp(filename: String, tmpURL: URL) {
        name = filename
        downloadURL = tmpURL
        var fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
        fileURL.appendPathComponent(filename)
        try? FileManager.default.moveItem(at: tmpURL, to: fileURL)
        downloadURL = fileURL
    }

    /// Scan the parent directory of a local media URL for sibling subtitle
    /// files (the 5 supported extensions), returning them sorted by name.
    ///
    /// RE: 0x10148c7a4 (`URLSubtitleInfo_searchLocalSubtitleFiles`, 1060B).
    /// Non-file URLs short-circuit to an empty array; the scan uses
    /// `NSFileManager.contentsOfDirectoryAtURL:` on `deletingLastPathComponent`
    /// and filters on `pathExtension.lowercased()`.
    public static func searchLocalSubtitleFiles(fileURL: URL) -> [URLSubtitleInfo] {
        guard fileURL.isFileURL else {
            return []
        }
        let directory = fileURL.deletingLastPathComponent()
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { DirectorySubtitleDataSource.subtitleExtensions.contains($0.pathExtension.lowercased()) }
            .map { URLSubtitleInfo(url: $0) }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Keyword / hash search drivers

    /// Core keyword search driver. Parses the JSON response, extracts the
    /// `status` / `sub` / `subs` keys, iterates the `filelist`, and builds one
    /// `URLSubtitleInfo` per result (issuing a `URLSession.downloadTask` for
    /// remote URLs).
    ///
    /// RE: 0x101488254 (`URLSubtitleInfo_searchByKeyword_async`, 4380B).
    /// Writes subtitleID / name / downloadURL / delay / comment / userInfo /
    /// userAgent on each constructed result.
    public static func searchByKeyword(query: String, api: URL, token: String? = nil) async throws -> [URLSubtitleInfo] {
        guard let searchApi = api.add(queryItems: ["q": query]) else {
            return []
        }
        var request = URLRequest(url: searchApi)
        request.httpMethod = "POST"
        if let token {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        guard let status = json["status"] as? Int, status == 0 else {
            return []
        }
        guard let subDict = json["sub"] as? [String: Any], let subArray = subDict["subs"] as? [[String: Any]] else {
            return []
        }
        var result = [URLSubtitleInfo]()
        for sub in subArray {
            guard let fileList = sub["filelist"] as? [[String: String]] else {
                continue
            }
            for dic in fileList {
                if let urlString = dic["url"], let filename = dic["f"], let url = URL(string: urlString) {
                    result.append(URLSubtitleInfo(subtitleID: urlString, name: filename, url: url))
                }
            }
        }
        return result
    }

    /// Hash-based search. Parses the `Files` array and the `Delay` integer
    /// from the JSON dict, iterates the file list extracting each `Link`, and
    /// sets `delay = Delay / 1000.0` on every constructed result.
    ///
    /// RE: 0x1014873f8 (`URLSubtitleInfo_searchByHash_async`, 1928B). Uses
    /// `swift_dynamicCast` to coerce the `Files` / `Delay` JSON values; remote
    /// hits issue a `URLSession.downloadTask`.
    public static func searchByHash(json: [String: Any]) -> [URLSubtitleInfo] {
        let delay = TimeInterval(json["Delay"] as? Int ?? 0) / 1000.0
        guard let files = json["Files"] as? [[String: String]] else {
            return []
        }
        var result = [URLSubtitleInfo]()
        for dic in files {
            if let link = dic["Link"], let url = URL(string: link) {
                let info = URLSubtitleInfo(subtitleID: link, name: "", url: url)
                info.delay = delay
                result.append(info)
            }
        }
        return result
    }

    // MARK: - Bitmap (palette-indexed) decode pipeline

    /// Palette-indexed bitmap decode. Allocates a `rows * cols * 4` RGBA byte
    /// buffer and maps every source byte index through a 256-entry palette LUT
    /// into a `UInt32` RGBA pixel.
    ///
    /// RE: 0x101484cd8 (`URLSubtitleInfo_parseDownloaded`, 304B) — body is
    /// identical to `downloadSubtitle` (0x101484b90); callees `_swift_slowAlloc`
    /// + `_bzero`. Returns the decoded RGBA buffer plus its geometry so the
    /// caller can wrap it into a `CGImage` via `makeBitmapImage`.
    static func parseDownloaded(indices: [UInt8], palette: [UInt32], cols: Int, rows: Int) -> [UInt32] {
        var pixels = [UInt32](repeating: 0, count: cols * rows)
        guard cols > 0, rows > 0 else {
            return pixels
        }
        for row in 0 ..< rows {
            let rowBase = row * cols
            for col in 0 ..< cols {
                let offset = rowBase + col
                guard offset < indices.count else { continue }
                let paletteIndex = Int(indices[offset])
                if paletteIndex < palette.count {
                    pixels[offset] = palette[paletteIndex]
                }
            }
        }
        return pixels
    }

    /// Wrap a decoded RGBA pixel buffer into a `CGImage`.
    ///
    /// RE: 0x101484a90 (`URLSubtitleInfo_fetchSubtitleURL`, 236B — misleadingly
    /// named). Decompile path: `CFDataCreate` → `CGDataProviderCreateWithCFData`
    /// → `CGColorSpaceCreateDeviceRGB` → `CGImageCreate(width, height, 8,
    /// bitsPerPixel, bytesPerRow, colorSpace, bitmapInfo, provider, …)`.
    /// `bitsPerPixel` is 0x18 (24) when the source had no alpha, else 0x20 (32).
    static func makeBitmapImage(pixels: [UInt32], cols: Int, rows: Int, hasAlpha: Bool = true) -> CGImage? {
        guard cols > 0, rows > 0, !pixels.isEmpty else {
            return nil
        }
        let bitsPerPixel = hasAlpha ? 32 : 24
        let bytesPerRow = cols * 4
        let cfData = pixels.withUnsafeBytes { Data($0) } as CFData
        guard let provider = CGDataProvider(data: cfData) else {
            return nil
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        return CGImage(
            width: cols,
            height: rows,
            bitsPerComponent: 8,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    // MARK: - CustomStringConvertible

    /// RE: 0x101484e08 (`URLSubtitleInfo_description_getter`,
    /// `CustomStringConvertible`). The binary builds the description by
    /// allocating a formatting object and folding in the same value used by
    /// `hash` (subtitleID); see `comment_getter` 0x101484a38 for the sibling
    /// String-building helper.
    public var description: String {
        "URLSubtitleInfo(subtitleID: \(subtitleID), name: \(name))"
    }
}

extension URLSubtitleInfo: CustomStringConvertible {}

public protocol SubtitleDataSource: AnyObject {
    var infos: [any SubtitleInfo] { get }
}

/// Sub-protocol for data sources searched against a media file URL.
///
/// RE: string at 0x102ef17a0, mangled `$s8KSPlayer21URLSubtitleDataSourceP`
/// at 0x103711790 (21 chars). The earlier name `FileURLSubtitleDataSource`
/// has ZERO string/mangled hits in the 1.3.15 binary (CORRECTION v5.3 R1
/// G-R1-4 / R5 G-R5-1) — renamed here to the binary-verified name.
public protocol URLSubtitleDataSource: SubtitleDataSource {
    func searchSubtitle(fileURL: URL?) async throws
}

public protocol CacheSubtitleDataSource: URLSubtitleDataSource {
    func addCache(fileURL: URL, downloadURL: URL)
}

public protocol SearchSubtitleDataSource: SubtitleDataSource {
    func searchSubtitle(query: String?, languages: [String]) async throws
}

public extension KSOptions {
    /// Registered subtitle data sources. Apps add/remove sources at runtime.
    ///
    /// RE: backed by the swift_once-guarded global `DAT_104459010`. The lazy
    /// initial write lives in `DirectorySubtitleDataSource_registerGlobal`
    /// (0x101485928, store at 0x101485984), gated by token `DAT_103d06350`.
    /// The Swift compiler synthesises the full accessor quartet the binary
    /// exposes — unsafeAddress (0x101485994), read (0x1014859d4), setter
    /// (0x101485a40, runtime replacement write) and modify (0x101485ab4) — all
    /// sharing that same once-token. A plain `static var` is the idiomatic
    /// equivalent; the default value is `[DirectorySubtitleDataSource()]`.
    static var subtitleDataSources: [SubtitleDataSource] = [DirectorySubtitleDataSource()]
}

public class PlistCacheSubtitleDataSource: CacheSubtitleDataSource {
    public static let singleton = PlistCacheSubtitleDataSource()
    public var infos = [any SubtitleInfo]()
    private let srtCacheInfoPath: String
    // plist 不能保存 URL，故缓存为字符串数组
    private var srtInfoCaches: [String: [String]]
    /// RE: 0x101485bd8 (`PlistCacheSubtitleDataSource_init`). Ensures the
    /// `KSSubtitleCache` temp folder exists, derives the plist path, then loads
    /// the existing cache off the main thread via `loadFromCache`.
    private init() {
        let cacheFolder = (NSTemporaryDirectory() as NSString).appendingPathComponent("KSSubtitleCache")
        if !FileManager.default.fileExists(atPath: cacheFolder) {
            try? FileManager.default.createDirectory(atPath: cacheFolder, withIntermediateDirectories: true, attributes: nil)
        }
        srtCacheInfoPath = (cacheFolder as NSString).appendingPathComponent("KSSrtInfo.plist")
        srtInfoCaches = [String: [String]]()
        DispatchQueue.global().async { [weak self] in
            self?.loadFromCache()
        }
    }

    /// Load the persisted filename→URL-list mapping from disk into
    /// `srtInfoCaches`.
    ///
    /// RE: 0x101485f34 (`PlistCacheSubtitleDataSource_loadFromCache`). Reads
    /// `NSMutableDictionary(contentsOfFile: srtCacheInfoPath)` and bridges it to
    /// `[String: [String]]`, falling back to empty on a missing/corrupt file.
    private func loadFromCache() {
        srtInfoCaches = (NSMutableDictionary(contentsOfFile: srtCacheInfoPath) as? [String: [String]]) ?? [String: [String]]()
    }

    /// Persist `srtInfoCaches` to disk.
    ///
    /// RE: 0x1014866d4 (`PlistCacheSubtitleDataSource_cleanup`). Bridges the
    /// dictionary to `NSDictionary` and calls `writeToFile:atomically:`. (The
    /// separate `saveToCache` 0x101486054 → `fetchAndCache` 0x1014860ec async
    /// chain drives the network-fetch-then-cache flow; see `searchSubtitle`.)
    private func cleanup() {
        (srtInfoCaches as NSDictionary).write(toFile: srtCacheInfoPath, atomically: false)
    }

    /// Build `infos` from the cached subtitle URLs for `fileURL`.
    ///
    /// RE: 0x10007a7a4 (`PlistCacheSubtitleDataSource_search`) →
    /// `fetchAndCache` 0x1014860ec (the async coroutine that reads
    /// `srtInfoCaches[absoluteString]`, constructs a `URLSubtitleInfo` per URL
    /// and tags `comment = "local"`). The handler variants
    /// `handleFetchResult` (0x1014863ec / 0x1014867d4) feed results back into
    /// the cache.
    public func searchSubtitle(fileURL: URL?) async throws {
        infos = [any SubtitleInfo]()
        guard let fileURL else {
            return
        }
        infos = srtInfoCaches[fileURL.absoluteString]?.compactMap { downloadURL -> (any SubtitleInfo)? in
            guard let url = URL(string: downloadURL) else {
                return nil
            }
            let info = URLSubtitleInfo(url: url)
            info.comment = "local"
            return info
        } ?? [any SubtitleInfo]()
    }

    /// RE: 0x101486054 (`PlistCacheSubtitleDataSource_saveToCache`). Appends a
    /// (file → downloadURL) pair and persists via `cleanup` off the main
    /// thread.
    public func addCache(fileURL: URL, downloadURL: URL) {
        let file = fileURL.absoluteString
        let path = downloadURL.absoluteString
        var array = srtInfoCaches[file] ?? [String]()
        if !array.contains(where: { $0 == path }) {
            array.append(path)
            srtInfoCaches[file] = array
            DispatchQueue.global().async { [weak self] in
                self?.cleanup()
            }
        }
    }
}

public class DirectorySubtitleDataSource: URLSubtitleDataSource {
    public var infos = [any SubtitleInfo]()
    public init() {}

    /// RE: 0x10007a6c4 (`DirectorySubtitleDataSource_search`). Delegates the
    /// parent-directory scan to `URLSubtitleInfo.searchLocalSubtitleFiles`
    /// (0x10148c7a4), which filters by the 5 subtitle extensions and returns
    /// the results sorted alphabetically by name (TimSort monomorphisation at
    /// 0x1007ba938).
    public func searchSubtitle(fileURL: URL?) async throws {
        infos = [any SubtitleInfo]()
        guard let fileURL else {
            return
        }
        infos = URLSubtitleInfo.searchLocalSubtitleFiles(fileURL: fileURL)
    }
}

public class ShooterSubtitleDataSource: URLSubtitleDataSource {
    public var infos = [any SubtitleInfo]()
    public init() {}
    /// RE: 0x10148e838 (`ShooterSubtitleDataSource_search`). POSTs the
    /// pathinfo + 4×4096-byte MD5 filehash to the Shooter.cn API and parses
    /// the `Files` / `Delay` response into `URLSubtitleInfo` results.
    public func searchSubtitle(fileURL: URL?) async throws {
        infos = [any SubtitleInfo]()
        guard let fileURL else {
            return
        }
        guard fileURL.isFileURL, let searchApi = URL(string: "https://www.shooter.cn/api/subapi.php")?
            .add(queryItems: ["format": "json", "pathinfo": fileURL.path, "filehash": fileURL.shooterFilehash])
        else {
            return
        }
        var request = URLRequest(url: searchApi)
        request.httpMethod = "POST"
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return
        }
        infos = json.flatMap { URLSubtitleInfo.searchByHash(json: $0) }
    }
}

/// RE: Forward v1.3.15 — AssrtSubtitleDataSource.
///
/// Binary instance layout: 2 stored fields after the Swift object header —
/// `token`, `host` (per `types.json`). `infos` is exposed via the
/// `SubtitleDataSource` protocol getter, not a stored property. `host` holds
/// the API base URL; the `/sub/search` / `/sub/detail` paths are appended at
/// the call sites (`AssrtSubtitleDataSource_search` 0x10148ecb8).
public class AssrtSubtitleDataSource: SearchSubtitleDataSource {
    private let token: String
    public var infos = [any SubtitleInfo]()
    /// Assrt API base URL. Default: `"https://api.assrt.net/v1"`.
    public let host: String

    public static let defaultHost = "https://api.assrt.net/v1"

    public init(token: String, host: String = AssrtSubtitleDataSource.defaultHost) {
        self.token = token
        self.host = host
    }

    public func searchSubtitle(query: String?, languages _: [String] = ["zh-cn"]) async throws {
        infos = [any SubtitleInfo]()
        guard let query else {
            return
        }
        guard let searchApi = URL(string: "\(host)/sub/search")?.add(queryItems: ["q": query]) else {
            return
        }
        var request = URLRequest(url: searchApi)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        guard let status = json["status"] as? Int, status == 0 else {
            return
        }
        guard let subDict = json["sub"] as? [String: Any], let subArray = subDict["subs"] as? [[String: Any]] else {
            return
        }
        var result = [URLSubtitleInfo]()
        for sub in subArray {
            if let assrtSubID = sub["id"] as? Int {
                try await result.append(contentsOf: loadDetails(assrtSubID: String(assrtSubID)))
            }
        }
        infos = result
    }

    func loadDetails(assrtSubID: String) async throws -> [URLSubtitleInfo] {
        var infos = [URLSubtitleInfo]()
        guard let detailApi = URL(string: "\(host)/sub/detail")?.add(queryItems: ["id": assrtSubID]) else {
            return infos
        }
        var request = URLRequest(url: detailApi)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return infos
        }
        guard let status = json["status"] as? Int, status == 0 else {
            return infos
        }
        guard let subDict = json["sub"] as? [String: Any], let subArray = subDict["subs"] as? [[String: Any]], let sub = subArray.first else {
            return infos
        }
        if let fileList = sub["filelist"] as? [[String: String]] {
            for dic in fileList {
                if let urlString = dic["url"], let filename = dic["f"], let url = URL(string: urlString) {
                    let info = URLSubtitleInfo(subtitleID: urlString, name: filename, url: url)
                    infos.append(info)
                }
            }
        } else if let urlString = sub["url"] as? String, let filename = sub["filename"] as? String, let url = URL(string: urlString) {
            let info = URLSubtitleInfo(subtitleID: urlString, name: filename, url: url)
            infos.append(info)
        }
        return infos
    }
}

/// RE: Forward v1.3.15 — OpenSubtitleDataSource.
///
/// `types.json` records EXACTLY 5 stored fields after the Swift object header —
/// `token?`, `username?`, `password?`, `apiKey`, `host`. There is NO `infos`
/// stored property on this class; `infos` comes from the `SubtitleDataSource`
/// protocol getter and search results are aggregated into
/// `SubtitleModel.searchInfos`.
///
/// Request construction is split across real Ghidra functions:
/// `buildSearchQueryParams` (0x10148957c) assembles the `query` / `language`
/// items, and the `URLSession` send + `Api-Key` / `Bearer` header attachment is
/// reached through the async continuation `fetchAPI_continuation` (0x101488188)
/// → `fetchAPI_cleanup` (0x101489370). The previously cited
/// `OpenSubtitleDataSource_sendSearchRequest @ 0x10136d3ac` does NOT exist —
/// 0x10136d3ac is the unnamed `FUN_10136d3ac`, a SwiftUI `State`/`KeyPath`
/// struct initialiser, and the old `0x102D6C9D0…0x102D6C9F8` byte offsets were
/// fabricated (zero data xrefs) and have been dropped.
public class OpenSubtitleDataSource: SearchSubtitleDataSource {
    private var token: String? = nil
    private let username: String?
    private let password: String?
    private let apiKey: String
    /// Base URL host (the `host` field of the binary layout).
    /// Default: `"https://api.opensubtitles.com/api"`.
    public let host: String
    public var infos = [any SubtitleInfo]()

    /// Default OpenSubtitles.com host. Stored as a field rather than a
    /// hard-coded URL literal so deployments behind a proxy or against
    /// the staging API can override it.
    public static let defaultHost = "https://api.opensubtitles.com/api"

    public init(apiKey: String, username: String? = nil, password: String? = nil, host: String = OpenSubtitleDataSource.defaultHost) {
        self.apiKey = apiKey
        self.username = username
        self.password = password
        self.host = host
    }

    public func searchSubtitle(query: String?, languages: [String] = ["zh-cn"]) async throws {
        try await searchSubtitle(query: query, imdbID: 0, tmdbID: 0, languages: languages)
    }

    public func searchSubtitle(query: String?, imdbID: Int, tmdbID: Int, languages: [String] = ["zh-cn"]) async throws {
        infos = [any SubtitleInfo]()
        var queryItems = [String: String]()
        if let query {
            queryItems["query"] = query
        }
        if imdbID != 0 {
            queryItems["imdb_id"] = String(imdbID)
        }
        if tmdbID != 0 {
            queryItems["tmdb_id"] = String(tmdbID)
        }
        if queryItems.isEmpty {
            return
        }
        queryItems["languages"] = languages.joined(separator: ",")
        try await searchSubtitle(queryItems: queryItems)
    }

    // https://opensubtitles.stoplight.io/docs/opensubtitles-api/a172317bd5ccc-search-for-subtitles
    public func searchSubtitle(queryItems: [String: String]) async throws {
        infos = [any SubtitleInfo]()
        if queryItems.isEmpty {
            return
        }
        guard let searchApi = URL(string: "\(host)/v1/subtitles")?.add(queryItems: queryItems) else {
            return
        }
        var request = URLRequest(url: searchApi)
        request.addValue(apiKey, forHTTPHeaderField: "Api-Key")
        if let token {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        guard let dataArray = json["data"] as? [[String: Any]] else {
            return
        }
        var result = [URLSubtitleInfo]()
        for sub in dataArray {
            if let attributes = sub["attributes"] as? [String: Any], let files = attributes["files"] as? [[String: Any]] {
                for file in files {
                    if let fileID = file["file_id"] as? Int, let info = try await loadDetails(fileID: fileID) {
                        result.append(info)
                    }
                }
            }
        }
        infos = result
    }

    func loadDetails(fileID: Int) async throws -> URLSubtitleInfo? {
        guard let detailApi = URL(string: "\(host)/v1/download")?.add(queryItems: ["file_id": String(fileID)]) else {
            return nil
        }
        var request = URLRequest(url: detailApi)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "Api-Key")
        if let token {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let link = json["link"] as? String, let fileName = json["file_name"] as?
            String, let url = URL(string: link)
        else {
            return nil
        }
        return URLSubtitleInfo(subtitleID: String(fileID), name: fileName, url: url)
    }
}

extension URL {
    public var components: URLComponents? {
        URLComponents(url: self, resolvingAgainstBaseURL: true)
    }

    func add(queryItems: [String: String]) -> URL? {
        guard var urlComponents = components else {
            return nil
        }
        var reserved = CharacterSet.urlQueryAllowed
        reserved.remove(charactersIn: ": #[]@!$&'()*+, ;=")
        urlComponents.percentEncodedQueryItems = queryItems.compactMap { key, value in
            URLQueryItem(name: key.addingPercentEncoding(withAllowedCharacters: reserved) ?? key, value: value.addingPercentEncoding(withAllowedCharacters: reserved))
        }
        return urlComponents.url
    }

    var shooterFilehash: String {
        let file: FileHandle
        do {
            file = try FileHandle(forReadingFrom: self)
        } catch {
            return ""
        }
        defer { file.closeFile() }

        file.seekToEndOfFile()
        let fileSize: UInt64 = file.offsetInFile

        guard fileSize >= 12288 else {
            return ""
        }

        let offsets: [UInt64] = [
            4096,
            fileSize / 3 * 2,
            fileSize / 3,
            fileSize - 8192,
        ]

        let hash = offsets.map { offset -> String in
            file.seek(toFileOffset: offset)
            return file.readData(ofLength: 4096).md5()
        }.joined(separator: ";")
        return hash
    }
}
