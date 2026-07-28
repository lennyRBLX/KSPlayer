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
    // search witness 0x10199fbc4 (async) returns __swiftEmptyArrayStorage — the "no show subtitle" has no parts.
    public func search(with _: KSSubtitleQuery) async -> [SubtitlePart] { [] }
}

// §8.3 — flattened: the KSSubtitle base is REMOVED (§8.2); fields in binary reflection order.
// +searchProtocol/isDownloading/languageCode/renderMode vs recon. Conforms KSSubtitleProtocol+SubtitleInfo
// directly (§8.5). The recon isEnabled-didSet parse-trigger + init download/rename logic → P4 M2.
public class URLSubtitleInfo: KSSubtitleProtocol, SubtitleInfo {
    public var searchProtocol: (any KSSubtitleProtocol)? = nil // §8.6
    public var isDownloading: Bool = false
    public var languageCode: String? = nil
    public var renderMode: SubtitleRenderMode = .srtView // ⚑ default inferred → M2
    // Plain stored var (no didSet). RE-VERIFIED session 63 against the ORPHANED export trie — the tool
    //   the session-21 check used could not see it, so the negative was sound but unproven. It now holds
    //   on the stronger evidence: URLSubtitleInfo carries 0 `parse` symbols, 0 `parts` symbols, and ZERO
    //   didSet/willSet observers (no `vW`/`vw`) anywhere in the class.
    // ⚑[tool=export_trie_oracle ref=URLSubtitleInfo:parse/parts/vW result=VERIFIED negative — 0/0/0]
    // P43 existence-check RAN + FAILED (session 21): the base parse-trigger didSet
    //   `didSet { if isEnabled, parts.isEmpty { Task { try? await parse(url:userAgent:) } } }` is GONE, not deferred —
    //   `URLSubtitleInfo.parse` has 0 binary symbols (removed), the `parts` field is gone (KSSubtitle-flatten), the
    //   init (0x101aa3310) never writes isEnabled (default-false zero-init, no observer), and no URLSubtitleInfo
    //   accessor spawns a parse-Task. The download/search pipeline moved to SubtitleModel (§7.3, Batch 3).
    public var isEnabled: Bool = false
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

    // search witness 0x101aa3dc0 → real body FUN_101aa3a94 (async): delegate to searchProtocol when set, else [].
    // The nil-check is the searchProtocol existential's metadata word (self+0x28; searchProtocol = field[0] @0x10,
    // a 5-word `any KSSubtitleProtocol?`). No stored `parts` after the KSSubtitle-flatten.
    public func search(with query: KSSubtitleQuery) async -> [SubtitlePart] {
        if let searchProtocol {
            return await searchProtocol.search(with: query)
        }
        return []
    }
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
    // Task 6 (session 20). Base cce7002 P19 cache-dir scan: NSTemporaryDirectory/"KSSubtitleCache" folder (created if
    // absent) + "KSSrtInfo.plist"; the plist load is a background DispatchQueue.global().async [weak self] read.
    private init() {
        let cacheFolder = (NSTemporaryDirectory() as NSString).appendingPathComponent("KSSubtitleCache")
        if !FileManager.default.fileExists(atPath: cacheFolder) {
            try? FileManager.default.createDirectory(atPath: cacheFolder, withIntermediateDirectories: true, attributes: nil)
        }
        srtCacheInfoPath = (cacheFolder as NSString).appendingPathComponent("KSSrtInfo.plist")
        srtInfoCaches = [String: [String]]()
        DispatchQueue.global().async { [weak self] in
            guard let self else {
                return
            }
            srtInfoCaches = (NSMutableDictionary(contentsOfFile: srtCacheInfoPath) as? [String: [String]]) ?? [String: [String]]()
        }
    }

    // Task 6: cache lookup keyed by fileURL.absoluteString → URLSubtitleInfo(url:) per cached downloadURL, comment "local".
    // Dropped stored infos → RETURNS [URLSubtitleInfo] (§5.1; the URLSubtitleDataSource req type pinned session 19).
    public func searchSubtitle(fileURL: URL?) async throws -> [URLSubtitleInfo] {
        guard let fileURL else {
            return []
        }
        return srtInfoCaches[fileURL.absoluteString]?.compactMap { downloadURL -> URLSubtitleInfo? in
            guard let url = URL(string: downloadURL) else {
                return nil
            }
            let info = URLSubtitleInfo(url: url)
            info.comment = "local"
            return info
        } ?? []
    }

    // Task 6: append downloadURL under fileURL (dedup by ==), persist the dict to plist on a background queue.
    public func addCache(fileURL: URL, downloadURL: URL) {
        let file = fileURL.absoluteString
        let path = downloadURL.absoluteString
        var array = srtInfoCaches[file] ?? [String]()
        if !array.contains(where: { $0 == path }) {
            array.append(path)
            srtInfoCaches[file] = array
            DispatchQueue.global().async { [weak self] in
                guard let self else {
                    return
                }
                (srtInfoCaches as NSDictionary).write(toFile: srtCacheInfoPath, atomically: false)
            }
        }
    }
}

// §7.2 — recon `URLSubtitleDataSouce` class → ConstantURLSubtitleDataSource (→ URL, now HAS searchSubtitle).
public class ConstantURLSubtitleDataSource: URLSubtitleDataSource {
    public let infos: [URLSubtitleInfo]
    public let url: URL // ⚑ optionality §7.5 (mangle reads non-optional; recon init(urls:) built infos from [URL]) → M2 verify
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
    // ⚑[tool=vtable_walk+get_xrefs_to+init_thunk_probe ref=FUN_10008090c:0x10008090c result=CONFIRMED]
    //   The class's ONLY vtable entry (slot 0, kind=Init) is @0x10084c444, a one-instruction
    //   `b 0x10008090c` (Ghidra names it thunk_). ⚠️ That target is NOT this class's own body: it is a
    //   linker-FOLDED body shared 34 ways (33 DATA refs + this thunk) — ShooterSubtitleDataSource, also a
    //   stateless `init()`, points its slot-0 impl @0x1039f1c7c straight at it with no thunk. Do not
    //   attribute that body, or any of its xrefs, to this class. Its 4 instructions are
    //   `mov x0,x20 · mov w1,#0x10 · mov w2,#7 · b _swift_allocObject`: the allocator is TAIL-called
    //   (`b`, not `bl`), so it allocates and returns with ZERO field stores, and it reads none of x0-x7
    //   ⇒ arity 0, i.e. `init()`.
    //   Because the body is shared, its `#0x10` sizes every class that folded into it, not this one.
    //   The class-SPECIFIC no-stored-property proofs are two independent ones: __swift5_fieldmd carries
    //   0 field records (dump_binary_field_types), and metadata VTableOffset=10 words vs Assrt 12 /
    //   Open 13 (the field-offset vector holds one word per stored property; 10+n fits all six
    //   datasources). Both confirm the §5.1 "dropped the recon's stored `infos`" finding.
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
    // ⚑[tool=vtable_walk+disassemble_function ref=AssrtSubtitleDataSource.__allocating_init:0x101aa6bd0 result=verified]
    //   M2 witness-verify of the former "init shape inferred": `host` is a COMPILE-TIME CONSTANT, not a
    //   parameter. The class has VTableSize=1, slot 0 kind=Init @0x101aa6bd0 (desc 0x1039f1c80), and that
    //   body reads ONLY x0/x1 — the single String parameter, stored to token @0x10. x2/x3 are never read,
    //   which also rules out `host: String = "…"`: a defaulted parameter is still passed in x2/x3 (the
    //   default-argument generator runs at the CALL site), so a default form would store x2/x3, not a literal.
    //   host @0x20 is materialized inline: adrp+add → 0x103d34200; `sub x8,#0x20` is _StringObject.nativeBias
    //   (32), NOT an address adjustment; `orr #0x8000000000000000` = immortal-literal flag; x9 = 0xd000…0017
    //   = ASCII-literal flags | count 23 — and 0x103d34200 holds exactly 23 bytes "http://api.assrt.net/v1"
    //   (http, NOT https). swift_allocObject(size 0x30, alignMask 7) = header 0x10 + 2×String ⇒ these 2 fields
    //   and no other. Field order token,host confirmed by dump_binary_field_types.
    //   ⚑ property-initializer vs in-body `self.host = …` is NOT separable in codegen; the constant store
    //   precedes the parameter store here AND in OpenSubtitleDataSource, in both cases against address order
    //   (so it is not a store-sorting artifact), which favors the property-initializer form written here.
    private let host: String = "http://api.assrt.net/v1"
    public init(token: String) {
        self.token = token
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
    // ⚑[tool=vtable_walk+disassemble_function ref=OpenSubtitleDataSource.__allocating_init:0x101aa84b0 result=verified]
    //   M2 witness-verify of the former "init shape inferred": `host` is a COMPILE-TIME CONSTANT, not a
    //   parameter — same shape as AssrtSubtitleDataSource. VTableSize=1, slot 0 kind=Init @0x101aa84b0
    //   (desc 0x1039f1cbc); the body reads ONLY x0/x1 (the single String parameter → apiKey @0x20) and never
    //   reads x2/x3, ruling out a defaulted `host:` parameter (a default is still passed in x2/x3).
    //   `stp xzr,xzr,[x0,#0x10]` zero-fills token ⇒ the `= nil` default. host @0x30 is materialized inline:
    //   adrp+add → 0x103d34220; `sub #0x20` = _StringObject.nativeBias; `orr #0x8000000000000000` = immortal
    //   literal; x9 = 0xd000…0024 = count 36 — and 0x103d34220 holds exactly 36 bytes
    //   "https://api.opensubtitles.com/api/v1". swift_allocObject(size 0x40, alignMask 7) = header 0x10 +
    //   String? + 2×String ⇒ exactly these 3 fields. Field order token,apiKey,host per dump_binary_field_types.
    private let host: String = "https://api.opensubtitles.com/api/v1"
    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    // Task 5 body 2/2 (session 20). Witness FUN_101aab81c → FUN_101aa9374 (the imdbID:tmdbID: delegate, args 0,0).
    // Base cce7002 OpenSubtitleDataSouce P19-adapted: host-field URLs, dropped stored `infos` → RETURNS [URLSubtitleInfo]
    // (§5.1/§7.5, P60 — no-boxing confirmed at Open's witness). Internal choices deep-pinned from the binary (P59/P61):
    //   host+"/subtitles" (search) · host+"/download" (loadDetails) · queryItems query/imdb_id/tmdb_id/languages
    //   (base typo "imbd_id" → Forward-corrected "imdb_id") · headers Api-Key + optional Bearer (NO Accept/Content-Type —
    //   the earlier chain-scan hits were spurious pairings) · JSON data[].attributes.files[].file_id → link/file_name.
    public func searchSubtitle(query: String?, languages: [String]) async throws -> [URLSubtitleInfo] {
        try await searchSubtitle(query: query, imdbID: 0, tmdbID: 0, languages: languages)
    }

    public func searchSubtitle(query: String?, imdbID: Int, tmdbID: Int, languages: [String]) async throws -> [URLSubtitleInfo] {
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
        // Forward DROPPED base's `if queryItems.isEmpty { return [] }` here (audit+P42 disasm FUN_101aa9394:30-39: control
        // flows unconditionally from the tmdb block into the languages build — no count-check/early-return). And the
        // languages value gets `.replacingOccurrences(of: "_", with: "-")` (P42 disasm :44-52: _joined then
        // _replacingOccurrences with 0x5f="_" / 0x2d="-") — normalizes locale codes (zh_CN → zh-CN). Base had neither.
        queryItems["languages"] = languages.joined(separator: ",").replacingOccurrences(of: "_", with: "-")
        return try await searchSubtitle(queryItems: queryItems)
    }

    public func searchSubtitle(queryItems: [String: String]) async throws -> [URLSubtitleInfo] {
        if queryItems.isEmpty {
            return []
        }
        guard let searchApi = URL(string: host + "/subtitles")?.add(queryItems: queryItems) else {
            return []
        }
        var request = URLRequest(url: searchApi)
        request.addValue(apiKey, forHTTPHeaderField: "Api-Key")
        if let token {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        guard let dataArray = json["data"] as? [[String: Any]] else {
            return []
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
        return result
    }

    private func loadDetails(fileID: Int) async throws -> URLSubtitleInfo? {
        guard let detailApi = URL(string: host + "/download")?.add(queryItems: ["file_id": String(fileID)]) else {
            return nil
        }
        var request = URLRequest(url: detailApi)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "Api-Key")
        if let token {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        // P42 disasm (FUN_101aaae78:48-60): JSON-parse error path calls __convertNSErrorToError + _swift_willThrow
        // ⇒ `try` (propagate), NOT base cce7002's `try?` — same as Assrt.loadDetails (Forward unified the datasources).
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let link = json["link"] as? String, let fileName = json["file_name"] as? String, let url = URL(string: link) else {
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
