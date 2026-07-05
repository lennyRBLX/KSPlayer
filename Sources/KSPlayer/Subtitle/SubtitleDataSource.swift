//
//  SubtitleDataSouce.swift
//  KSPlayer-7de52535
//
//  Created by kintan on 2018/8/7.
//
import Foundation

// §8.3 — fields in binary reflection order (languageCode, name, renderMode, isEnabled, subtitleID, delay).
// +languageCode/renderMode vs recon. Conforms KSSubtitleProtocol+SubtitleInfo directly (§8.5).
public class EmptySubtitleInfo: KSSubtitleProtocol, SubtitleInfo {
    public var languageCode: String? = nil
    public var isEnabled: Bool = true
    public let subtitleID: String = ""
    public var delay: TimeInterval = 0
    public let name: String = NSLocalizedString("no show subtitle", comment: "")
    public var renderMode: SubtitleRenderMode = .srtView // ⚑ default inferred → M2
    public init() {}
    // the "no show subtitle" info has no parts — [] is the minimal faithful body.
    public func search(for _: TimeInterval) -> [SubtitlePart] { [] }
}

// §8.3 — flattened: the KSSubtitle base is REMOVED (§8.2); fields in binary reflection order.
// +searchProtocol/isDownloading/languageCode/renderMode vs recon. Conforms KSSubtitleProtocol+SubtitleInfo
// directly (§8.5). The recon isEnabled-didSet parse-trigger + init download/rename logic → P4 M2.
public class URLSubtitleInfo: KSSubtitleProtocol, SubtitleInfo {
    public var searchProtocol: (any KSSubtitleProtocol)? = nil // §8.6
    public var isDownloading: Bool = false
    public var languageCode: String? = nil
    public var renderMode: SubtitleRenderMode = .srtView // ⚑ default inferred → M2
    public var isEnabled: Bool = false // ⚑ UNRESOLVED → P4 M2: the didSet parse-trigger (was on the KSSubtitle base)
    public private(set) var downloadURL: URL
    public var delay: TimeInterval = 0
    public private(set) var name: String
    public let subtitleID: String
    public var comment: String?
    public var userInfo: NSMutableDictionary?
    private let userAgent: String?
    // ⚑ init shape inferred → M2 witness-verify (minimal faithful: assigns stored props, defers download/rename)
    public init(subtitleID: String, name: String, url: URL, userAgent: String? = nil) {
        self.subtitleID = subtitleID
        self.name = name
        self.userAgent = userAgent
        downloadURL = url
    }

    public convenience init(url: URL) {
        self.init(subtitleID: url.absoluteString, name: url.lastPathComponent, url: url)
    }

    // ⚑ UNRESOLVED → P4 M2: search(for:) — no `parts` field after flattening (was inherited from KSSubtitle)
    public func search(for _: TimeInterval) -> [SubtitlePart] { [] }
}

// §7.1 — correct-spelled datasource hierarchy. The base is a 0-req MARKER (drops the recon's `infos`
// requirement; descriptor 0x1039f1a68, ctxflags 0x43 = AnyObject). The search protocols RETURN the
// results (the §5.1 infos-split: search datasources dropped the stored `infos`, so `searchSubtitle`
// returns the found infos instead of assigning them). Method signatures are M2-non-deterministic —
// the M1 gates check fields/kind/super/conformance, not signatures (durable handoff §6).
public protocol SubtitleDataSource: AnyObject {}

public protocol SearchSubtitleDataSource: SubtitleDataSource {
    // ⚑ sig inferred → M2 witness-verify (return element [URLSubtitleInfo] vs [any SubtitleInfo] — §7.5 P42; WT 0x1041da848)
    func searchSubtitle(query: String?, languages: [String]) async throws -> [any SubtitleInfo]
}

public protocol URLSubtitleDataSource: SubtitleDataSource { // was recon `FileURLSubtitleDataSouce`
    // ⚑ sig inferred → M2 witness-verify
    func searchSubtitle(fileURL: URL?) async throws -> [any SubtitleInfo]
}

public protocol CacheSubtitleDataSource: URLSubtitleDataSource {
    func addCache(fileURL: URL, downloadURL: URL) // sync (§7.1, req flags 0x11)
}

public protocol ConstantSubtitleDataSource: SubtitleDataSource {
    // ⚑ 1 async method (§1 CORRECTED — method-bearing, NOT a marker; conformer KSAVPlayer, witness 0x1019aba18) — sig inferred → M2
    func searchSubtitle() async throws -> [any SubtitleInfo]
}

public extension KSOptions {
    nonisolated(unsafe) static var subtitleDataSources: [any SubtitleDataSource] = [DirectorySubtitleDataSource()]
}

// §7.2 — Souce→Source. Fields srtCacheInfoPath, srtInfoCaches (dropped the recon's stored `infos`, §5.1).
public class PlistCacheSubtitleDataSource: CacheSubtitleDataSource {
    nonisolated(unsafe) public static let singleton = PlistCacheSubtitleDataSource()
    private let srtCacheInfoPath: String
    // 因为plist不能保存URL
    private var srtInfoCaches: [String: [String]]
    private init() {
        // ⚑ UNRESOLVED → P4 M2: the cache-dir scan (NSTemporaryDirectory/KSSubtitleCache + plist load).
        //   minimal faithful init assigns the stored props:
        srtCacheInfoPath = ""
        srtInfoCaches = [:]
    }

    // ⚑ UNRESOLVED → P4 M2: searchSubtitle(fileURL:) (cache lookup → returns URLSubtitleInfos)
    public func searchSubtitle(fileURL: URL?) async throws -> [any SubtitleInfo] { [] }

    // ⚑ UNRESOLVED → P4 M2: addCache(fileURL:downloadURL:) (plist write)
    public func addCache(fileURL: URL, downloadURL: URL) {}
}

// §7.2 — recon `URLSubtitleDataSouce` class → ConstantURLSubtitleDataSource (→ URL, now HAS searchSubtitle).
public class ConstantURLSubtitleDataSource: URLSubtitleDataSource {
    public var infos: [URLSubtitleInfo]
    public var url: URL // ⚑ optionality §7.5 (mangle reads non-optional; recon init(urls:) built infos from [URL]) → M2 verify
    // ⚑ init shape inferred → M2 witness-verify
    public init(url: URL, infos: [URLSubtitleInfo]) {
        self.url = url
        self.infos = infos
    }

    // ⚑ UNRESOLVED → P4 M2: searchSubtitle(fileURL:) — constant source (near-empty async trampoline, FUN_101aa5b4c)
    public func searchSubtitle(fileURL: URL?) async throws -> [any SubtitleInfo] { infos }
}

// §7.2 — Souce→Source + FileURL→URL. Stateless (dropped the recon's stored `infos`, §5.1).
public class DirectorySubtitleDataSource: URLSubtitleDataSource {
    public init() {}
    // ⚑ UNRESOLVED → P4 M2: searchSubtitle(fileURL:) (directory scan → returns found infos)
    public func searchSubtitle(fileURL: URL?) async throws -> [any SubtitleInfo] { [] }
}

// §7.2 — Souce→Source + FileURL→URL. Stateless.
public class ShooterSubtitleDataSource: URLSubtitleDataSource {
    public init() {}
    // ⚑ UNRESOLVED → P4 M2: searchSubtitle(fileURL:) (shooter.cn API → returns found infos)
    public func searchSubtitle(fileURL: URL?) async throws -> [any SubtitleInfo] { [] }
}

// §7.2 — Souce→Source. token+host (was token+infos; +host = the API base, dropped stored infos §5.1).
public class AssrtSubtitleDataSource: SearchSubtitleDataSource {
    private let token: String
    private let host: String
    // ⚑ init shape inferred → M2 witness-verify
    public init(token: String, host: String) {
        self.token = token
        self.host = host
    }

    // ⚑ UNRESOLVED → P4 M2: searchSubtitle(query:languages:) (assrt.net API → returns found infos; WT 0x1041da848)
    public func searchSubtitle(query: String?, languages: [String]) async throws -> [any SubtitleInfo] { [] }
}

// §7.2 — Souce→Source. token?/apiKey/host (dropped username/password/infos; +host §5.1).
public class OpenSubtitleDataSource: SearchSubtitleDataSource {
    private var token: String? = nil
    private let apiKey: String
    private let host: String
    // ⚑ init shape inferred → M2 witness-verify
    public init(apiKey: String, host: String) {
        self.apiKey = apiKey
        self.host = host
    }

    // ⚑ UNRESOLVED → P4 M2: searchSubtitle(query:languages:) (opensubtitles.com API → returns found infos)
    public func searchSubtitle(query: String?, languages: [String]) async throws -> [any SubtitleInfo] { [] }
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
