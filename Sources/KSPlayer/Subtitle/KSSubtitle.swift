//
//  KSSubtitle.swift
//  Pods
//
//  Created by kintan on 2017/4/2.
//
//

import CoreFoundation
import CoreGraphics
import Foundation
import SwiftUI
#if canImport(Translation) && !os(tvOS) && !os(watchOS)
import Translation
#endif


public protocol KSSubtitleProtocol {
    // The sole requirement (NumRequirements=1, desc 0x1039f18a0). Forward version-changed the base
    // `search(for time: TimeInterval) -> [SubtitlePart]` (sync) to a query-based ASYNC lookup: the mangled
    // requirement name is `search…KSSubtitleQueryV_tYaF` and both info-class witnesses are async-fp records.
    // Rippled to all 6 conformers (P55, session 21) — the conformance gate checks presence, not signature.
    func search(with query: KSSubtitleQuery) async -> [SubtitlePart]
}

public protocol SubtitleInfo: KSSubtitleProtocol, AnyObject {
    var subtitleID: String { get }
    var name: String { get }
    var delay: TimeInterval { get }
    // Order pinned to the URLSubtitleInfo:SubtitleInfo witness table getters (+0x10..+0x38 =
    // subtitleID / name / delay / languageCode / subtitleLanguage / isEnabled): languageCode (witness
    // 0x100c55b00, String? getter @self+0x40) then subtitleLanguage (witness +0x30, FUN_101aa3cc8) sit
    // between delay and isEnabled.
    var languageCode: String? { get }
    // subtitleLanguage = the subtitle's language as a `Locale.Language` (the translation SOURCE). Named
    // `subtitleLanguage` (not `language`) to avoid the `MediaPlayerTrack.language: String?` collision on
    // FFmpegAssetTrack. ⚑ P28: true name stripped.
    var subtitleLanguage: Locale.Language? { get }
    //    var userInfo: NSMutableDictionary? { get set }
    //    var subtitleDataSouce: SubtitleDataSouce? { get set }
//    var comment: String? { get }
    var isEnabled: Bool { get set }
    var isSrt: Bool { get }
    var renderMode: SubtitleRenderMode { get }
}

public extension SubtitleInfo {
    var id: String { subtitleID }

    /// ⚑[tool=export_trie_oracle ref=SubtitleInfo.language.getter:0x101aa23d0 result=23-instr]
    /// A `PAAE` extension member with a `vpMV` — public proven, no witness slot. Its type comes
    /// off the mangling (`…8language10Foundation6LocaleV8LanguageVSg…`), so it is
    /// `Locale.Language?`, NOT the `String?` that `MediaPlayerTrack.language` returns.
    ///
    /// The body is short and complete:
    ///   · `ldr x8,[x1,#0x28]` / `blr` — witness +0x28, which THIS FILE's own requirement-order
    ///     note above already pins to `languageCode` (+0x10…+0x38 = subtitleID / name / delay /
    ///     languageCode / <Locale.Language? member> / isEnabled). No new count was taken.
    ///   · `cbz x1` on the returned String?'s second word selects the nil arm (`w20 = 1`);
    ///     otherwise `Locale.Language.init(identifier:)` (__got 0x104109ed8) builds into the
    ///     indirect return and `w20 = 0`.
    ///   · the tail loads the `Locale.Language` value witness table (metadata __got 0x104109ee8),
    ///     takes `[vwt,#0x38]` — `storeEnumTagSinglePayload` — and tail-calls it with
    ///     `numEmptyCases = 1` to stamp the Optional tag. That is the `?` wrapper, not a branch.
    /// So the closure result is non-optional and the map is `map`, not `flatMap`.
    /// ⚑[tool=bind_oracle ref=__got:0x104109ed8 result=Locale.Language.init(identifier:)]
    ///
    /// ⚑ OPEN, and deliberately NOT acted on: the protocol above declares a `Locale.Language?`
    ///   requirement whose name this reconstruction invented as `subtitleLanguage` ("true name
    ///   stripped"), and the trie's ONLY `SubtitleInfo` member of that type is this `language`.
    ///   That makes "the requirement is really named `language`, and this is its default" the
    ///   obvious hypothesis — but it is NOT proven and was not assumed. All four conformers'
    ///   slot-5 witnesses (URLSubtitleInfo 0x101aa3cc8, EmptySubtitleInfo 0x101aa269c,
    ///   AVMediaSelectionTrack 0x100abde9c) are 37-instruction bodies reading their OWN stored
    ///   fields, not thunks to 0x101aa23d0, so nothing here shows this member serving as that
    ///   requirement's default. Renaming on that hypothesis would assert more than is read.
    var language: Locale.Language? {
        languageCode.map { Locale.Language(identifier: $0) }
    }
    /// ⚑ getter 0x10002c740 — `mov w0, #0x1` / `ret`. Unconditional true: the body reads no
    /// field and takes no branch, so it does NOT inspect the subtitle's type or extension.
    /// The address is the image's canonical `return true` and is ICF-folded, so the constant is
    /// the whole of what it establishes and the whole of what this declares.
    /// Trie: `(extension in KSPlayer):KSPlayer.SubtitleInfo.isSrt.getter : Swift.Bool`, i.e. the
    /// binary places it in an extension of the protocol, which is where it is written here.
    var isSrt: Bool { true }
    // FUN_101aa3cc8: `Locale.Language(identifier:)` from `languageCode`, or nil when `languageCode` is nil.
    var subtitleLanguage: Locale.Language? {
        languageCode.map { Locale.Language(identifier: $0) }
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(subtitleID)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.subtitleID == rhs.subtitleID
    }
}

// §8.2 — `class KSSubtitle` REMOVED (confirmed absent from __swift5_types). Its KSSubtitleProtocol
// conformance moved to the concrete info/actor classes (§8.5); the parse pipeline → the parse classes / P4 M2.

public protocol NumericComparable {
    associatedtype Compare
    static func < (lhs: Self, rhs: Compare) -> Bool
    static func == (lhs: Self, rhs: Compare) -> Bool
}

extension Collection where Element: NumericComparable {
    func binarySearch(key: Element.Compare) -> Self.Index? {
        var lowerBound = startIndex
        var upperBound = endIndex
        while lowerBound < upperBound {
            let midIndex = index(lowerBound, offsetBy: distance(from: lowerBound, to: upperBound) / 2)
            if self[midIndex] == key {
                return midIndex
            } else if self[midIndex] < key {
                lowerBound = index(lowerBound, offsetBy: 1)
            } else {
                upperBound = midIndex
            }
        }
        return nil
    }
}

// SubtitleRenderMode @0x1039f18c0 — cases descriptor-confirmed
// ⚑[tool=type_surface ref=SubtitleRenderMode:0x1039f18c0 result=RawRepresentable(RawValue=Int)@0x10356cb58]
// L7: raw values are the implicit case indices 0…2; Forward's rawValue body was not read.
public enum SubtitleRenderMode: Int {
    case image
    case assView
    case srtView
}

// KSSubtitleQuery @0x1039f1884 — the SubtitleActor lookup key
// ⚑[tool=field_surface ref=KSSubtitleQuery:fieldmd result=5 let]
public struct KSSubtitleQuery {
    public let time: Double
    public let size: CGSize
    public let verticalAlign: VerticalAlignment?   // ⚑ SwiftUI VerticalAlignment (recon TextPosition survives it)
    public let textPosition: TextPosition?
    public let textRole: SubtitleTextRole
}

public protocol AudioRecognize: SubtitleInfo {
    func append(frame: AudioFrame)
}

// §8.3 — fields in binary reflection order (languageCode, name, renderMode, isEnabled, subtitleID, delay).
// +languageCode/renderMode vs recon. Conforms KSSubtitleProtocol+SubtitleInfo directly (§8.5).
public final class EmptySubtitleInfo: KSSubtitleProtocol, SubtitleInfo {
    public var languageCode: String? = nil
    public var isEnabled: Bool = true
    public let subtitleID: String = ""
    public var delay: TimeInterval = 0
    public let name: String = NSLocalizedString("no show subtitle", comment: "")
    public var renderMode: SubtitleRenderMode = .srtView // ⚑ default inferred → M2
    public init() {}
    // search witness 0x10199fbc4 (async) returns __swiftEmptyArrayStorage — the "no show subtitle" has no parts.
    // ⚑[tool=member_surface ref=EmptySubtitleInfo.search(with:) result=Forward sync (no Ya); body has no swift_task_* call]
    public func search(with _: KSSubtitleQuery) -> [SubtitlePart] { [] }
}

// §8.3 — flattened: the KSSubtitle base is REMOVED (§8.2); fields in binary reflection order.
// +searchProtocol/isDownloading/languageCode/renderMode vs recon. Conforms KSSubtitleProtocol+SubtitleInfo
// directly (§8.5). The recon isEnabled-didSet parse-trigger + init download/rename logic → P4 M2.
public final class URLSubtitleInfo: KSSubtitleProtocol, SubtitleInfo {
    private var searchProtocol: (any KSSubtitleProtocol)? = nil // §8.6
    private var isDownloading: Bool = false
    public var languageCode: String? = nil
    // Both inits (0x101aa3310 / 0x101aa34f0) zero-init +0x50/+0x51 with one `strh wzr`: renderMode raw 0 = .image.
    public var renderMode: SubtitleRenderMode = .image
    // The export trie has no `vW`, but the observer is private and inlined, so that negative does not rule it
    //   out. The setter 0x101aa2b54 (87 instr) and the modify resume 0x101aa2de8 both run this body after the
    //   store: newValue/isEnabled true, searchProtocol copy has a nil metadata word, and isDownloading is not set;
    //   then isDownloading = true and Task(priority: nil) with a weak box (0x18 + swift_weakInit) and a (0,0)
    //   isolation context. The Task body (0x101aa279c → 0x101aa2828) runs weakLoadStrong, then
    //   URL.parseSubtitle(userAgent:encoding: nil) @0x1019f52d8 on a downloadURL copy. On success it assigns
    //   searchProtocol (modify access) and then renderMode. Both the success and throw arms clear isDownloading.
    //   The init still never writes isEnabled.
    public var isEnabled: Bool = false {
        didSet {
            if isEnabled, searchProtocol == nil, !isDownloading {
                isDownloading = true
                // Swift 6: Task's operation is `sending`, and URLSubtitleInfo is not Sendable. This is the
                //   repo's established `nonisolated(unsafe) weak var` launder (see init). Like the binary, it
                //   lowers to one 0x18 heap box holding the weak reference.
                nonisolated(unsafe) weak var weakSelf = self
                Task {
                    guard let self = weakSelf else {
                        return
                    }
                    do {
                        let (searchProtocol, renderMode) = try await self.downloadURL.parseSubtitle(userAgent: self.userAgent, encoding: nil)
                        self.searchProtocol = searchProtocol
                        self.renderMode = renderMode
                    } catch {}
                    self.isDownloading = false
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

    // 0x101aa330c = URLSubtitleInfo.__allocating_init(url:), a 4-byte thunk `b 0x101aa3e10`. The 900-byte /
    // 225-instr body at 0x101aa3e10 is NOT_IN_TRIE only because the THUNK carries the symbol; that body is
    // this delegation with the designated init AND URL.download both inlined and specialised for
    // userAgent == nil. Both inits install the SAME completion body, which is why the download is written
    // once, above — reproducing it here would duplicate the pipeline. No source change needed.
    public convenience init(url: URL) {
        self.init(subtitleID: url.absoluteString, name: url.lastPathComponent, url: url)
    }
    // 0x101aa3310 = URLSubtitleInfo.__allocating_init(subtitleID:name:url:userAgent:), trie-named, extent
    // 0x101aa3310..0x101aa34f0 (120 instr). The previous note here claimed this init only assigned stored
    // properties and left the download/rename to a later unit — REFUTED. This init calls
    // (extension in KSPlayer):Foundation.URL.download(userAgent:completion:) @0x1019f457c at 0x101aa34c0,
    // which is inside this init's own extent; the guard and the [weak self] box precede it.
    public init(subtitleID: String, name: String, url: URL, userAgent: String? = nil) {
        self.subtitleID = subtitleID
        self.name = name
        self.userAgent = userAgent
        downloadURL = url
        // Guard = URL.isFileURL.getter then a _StringObject count test on `name`.
        if !url.isFileURL, name.isEmpty {
            // swift_allocObject(24) + swift_weakInit on the new instance = a weak box of self.
            // ⚑ Swift 6 spelling: `download`'s completion is `@Sendable` (member_surface, Yb) and
            //   URLSubtitleInfo is not Sendable, so the box is a `nonisolated(unsafe) weak var` rather
            //   than a `[weak self]` capture list; both lower to one heap box holding a weak reference.
            nonisolated(unsafe) weak var weakSelf = self
            url.download(userAgent: userAgent) { filename, url in
                guard let self = weakSelf else {
                    return
                }
                // ⚑ the closure parameter names are not recoverable (P28); only the type (String, URL) is.
                //   `filename` is recon-chosen because `name` would shadow this init's own parameter.
                self.name = filename
                self.downloadURL = url
                var newURL = URL(fileURLWithPath: NSTemporaryDirectory())
                newURL.appendPathComponent(filename)
                try? FileManager.default.moveItem(at: url, to: newURL)
                self.downloadURL = newURL
            }
        }
    }

    // isSrt.getter @0x101aa3914, 90 instr. `public` is proven by the property descriptor
    // $s8KSPlayer15URLSubtitleInfoC5isSrtSbvpMV @0x10356cbe0; there is no `…Sbvs`, so get-only.
    // This SHADOWS the `SubtitleInfo` extension default (`var isSrt: Bool { true }`,
    // KSSubtitle.swift) — the class carries its own getter symbol, not an extension one, and it
    // is the conformer that actually inspects itself instead of answering the folded `true`.
    //
    // Both halves are read end to end:
    //  · the literal is the small string "srt" — word0 0x00747273 (bytes 73 72 74), word1
    //    0xE300000000000000 = 0xE0|3, the all-ASCII discriminator carrying count 3.
    //  · `hasSuffix` takes the suffix in (x0,x1) and `self` in (x2,x3). This site loads "srt"
    //    into x0/x1 and the `name` String pair into x2/x3, so the RECEIVER is `name`. The
    //    register order is not assumed: a compiled probe of `s.hasSuffix("srt")` emits the same
    //    `mov x3,x1` / `mov x2,x0` / `mov w0,#0x7273` / `movk #0x74,lsl #16` / `mov x1,#0xE3<<56`.
    //  · a true result short-circuits — `tbz w23,#0` falls through to `mov w19,#1` and the
    //    epilogue — which is exactly `||`. The false arm copies `downloadURL` through its value
    //    witness into a stack temp, calls the URL getter, destroys the temp, then compares with
    //    the same "srt" pair (an inline identical-representation fast path, then the general
    //    _stringCompareWithSmolCheck with `expecting` = 0 = .equal).
    // ⚑[tool=export_trie_oracle ref=URLSubtitleInfo.name:0x104c63790 result=name]
    // ⚑[tool=export_trie_oracle ref=URLSubtitleInfo.downloadURL:0x104c63780 result=downloadURL]
    // ⚑[tool=bind_oracle ref=Foundation.URL.pathExtension.getter:0x104109a08 result=pathExtension]
    // ⚑[tool=bind_oracle ref=String.hasSuffix:0x1041114e0 result=hasSuffix]
    public var isSrt: Bool {
        name.hasSuffix("srt") || downloadURL.pathExtension == "srt"
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
