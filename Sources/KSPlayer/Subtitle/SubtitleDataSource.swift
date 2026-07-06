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
    // return element PINNED [URLSubtitleInfo] (Task 5, session 20, P55/P60): the Assrt witness FUN_101aa6c50 →
    // loadDetails builds concrete URLSubtitleInfo (FUN_101aa7290); result.append(contentsOf:) uses element stride 8
    // (class refs, FUN_1019c7d88); the result array is returned directly (no array-map / existential boxing);
    // corroborated by SubtitleModel [URLSubtitleInfo] collectors (§7.3). Same requirement for both conformers (Assrt/Open).
    func searchSubtitle(query: String?, languages: [String]) async throws -> [URLSubtitleInfo]
}

public protocol URLSubtitleDataSource: SubtitleDataSource { // was recon `FileURLSubtitleDataSouce`
    // return element PINNED [URLSubtitleInfo] (session 19, P55/§7.5): ConstantURL cont FUN_101aa5b64 returns
    // self.infos directly with NO existential boxing; corroborated by SubtitleModel [URLSubtitleInfo] collectors (§7.3).
    func searchSubtitle(fileURL: URL?) async throws -> [URLSubtitleInfo]
}

public protocol CacheSubtitleDataSource: URLSubtitleDataSource {
    func addCache(fileURL: URL, downloadURL: URL) // sync (§7.1, req flags 0x11)
}

public protocol ConstantSubtitleDataSource: SubtitleDataSource {
    // ⚑ 1 async method (§1 CORRECTED — method-bearing, NOT a marker; conformer KSAVPlayer, witness 0x1019aba18).
    //   return element → Task 6 witness-verify (sibling URLSubtitleDataSource PINNED [URLSubtitleInfo] s19; UNPROVEN here, P55/P23)
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

    // ⚑ UNRESOLVED → P4 M2 (Task 6): searchSubtitle(fileURL:) (cache lookup → returns URLSubtitleInfos)
    public func searchSubtitle(fileURL: URL?) async throws -> [URLSubtitleInfo] { [] }

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

    // FUN_101aa5b4c → cont FUN_101aa5b64 (P42-disasm): returns infos iff url == the requested fileURL, else [].
    //   Guard = Foundation URL.== on self.url vs fileURL @0x101aa5b88 (tbz w0); true → retain+return self.infos,
    //   false → __swiftEmptyArrayStorage. Element [URLSubtitleInfo] (self.infos returned directly, no boxing).
    //   ⚑ optional-compare form (url:URL vs fileURL:URL?) via Swift optional promotion — minor, audit-confirmed.
    public func searchSubtitle(fileURL: URL?) async throws -> [URLSubtitleInfo] {
        if url == fileURL {
            return infos
        }
        return []
    }
}

// §7.2 — Souce→Source + FileURL→URL. Stateless (dropped the recon's stored `infos`, §5.1).
public class DirectorySubtitleDataSource: URLSubtitleDataSource {
    public init() {}
    // FUN_101aa5c5c → FUN_101aac684 (setup) → FUN_101aac728 (isFileURL + contentsOfDirectory + filter) → FUN_101aa4844
    //   (in-place mergeSort by URLSubtitleInfo.name). Binary-pinned: isFileURL guard, contentsOfDirectory(at:
    //   deletingLastPathComponent, includingPropertiesForKeys:nil) [try?→[]], .filter(\.isSubtitle) (inlined
    //   FUN_10001e034 = the 5-ext contains incl "sup"), .map { URLSubtitleInfo(url:) }, .sorted { $0.name < $1.name }.
    //   §5.1: Forward RETURNS the array (base assigned self.infos). map = FUN_101aa3e10 (URLSubtitleInfo init/elem);
    //   nil-fileURL unwrap folds into setup FUN_101aac684 → returns [] (audit-confirmed, not a divergence).
    public func searchSubtitle(fileURL: URL?) async throws -> [URLSubtitleInfo] {
        guard let fileURL, fileURL.isFileURL else { return [] }
        let subtitleURLs = (try? FileManager.default.contentsOfDirectory(
            at: fileURL.deletingLastPathComponent(), includingPropertiesForKeys: nil
        ).filter(\.isSubtitle)) ?? []
        return subtitleURLs.map { URLSubtitleInfo(url: $0) }.sorted { $0.name < $1.name }
    }
}

// §7.2 — Souce→Source + FileURL→URL. Stateless.
public class ShooterSubtitleDataSource: URLSubtitleDataSource {
    public init() {}
    // FUN_101aa5cbc → FUN_101aacc04 (setup) → FUN_101aaccfc (URL+request+URLSession.data) → FUN_101aad004 →
    //   FUN_101aad0c0 (JSON decode + flatMap). base cce7002 P19-adapted to RETURN [URLSubtitleInfo] (§5.1).
    //   Binary-pinned: URL "https://www.shooter.cn/api/subapi.php" @0x103d3a2f0 (exact), .add(queryItems:)
    //   (format/pathinfo=fileURL.path/filehash=fileURL.shooterFilehash), URLRequest(url:,cachePolicy:0,timeout:60)
    //   = URLRequest(url:), httpMethod POST, URLSession.shared.data, JSONSerialization. shooter.cn API keys are
    //   external-fixed (not divergence-prone). ⚑ delay unit (/1000.0) + name:"" — audit-confirmed.
    public func searchSubtitle(fileURL: URL?) async throws -> [URLSubtitleInfo] {
        guard let fileURL, fileURL.isFileURL,
              let searchApi = URL(string: "https://www.shooter.cn/api/subapi.php")?
              .add(queryItems: ["format": "json", "pathinfo": fileURL.path, "filehash": fileURL.shooterFilehash])
        else {
            return []
        }
        var request = URLRequest(url: searchApi)
        request.httpMethod = "POST"
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return json.flatMap { sub -> [URLSubtitleInfo] in
            let filesDic = sub["Files"] as? [[String: String]]
            let delay = TimeInterval(sub["Delay"] as? Int ?? 0) / 1000.0
            return filesDic?.compactMap { dic in
                if let string = dic["Link"], let url = URL(string: string) {
                    let info = URLSubtitleInfo(subtitleID: string, name: "", url: url)
                    info.delay = delay
                    return info
                }
                return nil
            } ?? [URLSubtitleInfo]()
        }
    }
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

    // Task 5 (session 20). Witness FUN_101aa6c50 (WT 0x1041da848) → real body FUN_101aad528. Base cce7002
    // AssrtSubtitleDataSouce.searchSubtitle P19-adapted: host-field URL (not the base hardcode), dropped stored
    // `infos` → RETURNS [URLSubtitleInfo] (§5.1/§7.5, P60). Internal choices deep-pinned from the binary (P59/P61):
    //   URL host+"/sub/search" · query ["q":query] · header Authorization: Bearer <token> · JSON status/sub/subs ·
    //   per-sub sub["fileid"] as? String → Int → .description (base was sub["id"] as? Int; get_description @101aae404:264).
    public func searchSubtitle(query: String?, languages _: [String]) async throws -> [URLSubtitleInfo] {
        guard let query else {
            return []
        }
        guard let searchApi = URL(string: host + "/sub/search")?.add(queryItems: ["q": query]) else {
            return []
        }
        var request = URLRequest(url: searchApi)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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
            if let fileid = sub["fileid"] as? String, let subID = Int(fileid) {
                try await result.append(contentsOf: loadDetails(assrtSubID: subID.description))
            }
        }
        return result
    }

    // loadDetails(assrtSubID:) helper — assrt.net /sub/detail lookup (FUN_101aa6cc0 → build FUN_101aa7290).
    // filelist[].{url, "f"} → URLSubtitleInfo. Per-site keys deep-pinned (P59, audit-caught): the filelist LOOP uses
    // the 1-char key dic["f"] (base-retained; 0x66/disc-0xe1 @101aa7290:286); the else-fallback uses sub["filename"]
    // (full 8-char, 0x656d616e656c6966 @101aa7290:485) — the two sites genuinely use different keys.
    private func loadDetails(assrtSubID: String) async throws -> [URLSubtitleInfo] {
        var infos = [URLSubtitleInfo]()
        guard let detailApi = URL(string: host + "/sub/detail")?.add(queryItems: ["id": assrtSubID]) else {
            return infos
        }
        var request = URLRequest(url: detailApi)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        // P42 disasm (FUN_101aa7290:59-74): the JSON-parse error path calls __convertNSErrorToError + _swift_willThrow
        // ⇒ `try` (propagate), NOT base cce7002's `try?` (swallow) — Forward unified loadDetails with the search body.
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
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

    // ⚑ UNRESOLVED → P4 M2 (Task 5 body 2/2, NEXT commit): searchSubtitle(query:languages:) — opensubtitles.com
    //   API (host https://api.opensubtitles.com/api/v1 @0x103d34220). Signature return rippled to [URLSubtitleInfo]
    //   (P55/P60 proven at the shared SearchSubtitleDataSource req via Assrt); body decode pending.
    public func searchSubtitle(query: String?, languages _: [String]) async throws -> [URLSubtitleInfo] { [] }
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
