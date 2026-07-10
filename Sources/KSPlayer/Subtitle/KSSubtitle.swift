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

// SubtitlePart @0x1039f21e8 — STRUCT (was class); payload consolidated into `render: Either` (§8.6).
// Conformances carried from the recon (reverse-walk confirms NumericComparable; the 4 stdlib ones are
// GOT-indirect-blind but xref-count-corroborated — ~5 conformance descriptors). The Comparable +
// NumericComparable extensions (below, unchanged) use only start/end → they transfer faithfully.
public struct SubtitlePart: CustomStringConvertible, Identifiable {
    public var start: Double
    public var end: Double
    public var render: Either<SubtitleImageInfo, SubtitleTextInfo>
    // ⚑ Identifiable.id inferred: the recon CLASS used the synthesized ObjectIdentifier; a struct needs
    //   an explicit id, and the binary has NO stored `id` (3 fields: start/end/render) → computed. M2 verify.
    public var id: Double { start }
    // description = CustomStringConvertible resilient witness 0x101abbd70 → body 0x101abbc34 (P4 M2, session 21).
    // Base cce7002 rendered the removed `text`; Forward keeps the interpolation skeleton and renders `render`
    // via String(describing:). Literals decoded verbatim: "Subtile Group start=" (@0x103d3a390, count 20 — the
    // base "Subtile" typo is CARRIED, not corrected), " end=" (small-string 0x3d646e6520/count 5), " text="
    // (0x3d7478657420/count 6 — label kept as "text="). start/end appended via double interpolation; render via
    // String.init(describing:) + metadata (explicit, matching base's `String(describing: text)`), then appended.
    public var description: String {
        "Subtile Group start=\(start) end=\(end) text=\(String(describing: render))"
    }

    public init(start: Double, end: Double, render: Either<SubtitleImageInfo, SubtitleTextInfo>) {
        self.start = start
        self.end = end
        self.render = render
    }
    // No convenience inits — P43 existence-check RAN + FAILED (session 21), so DROPPED not fabricated.
    // The base class inits init(_:_:_string:)/init(_:_:attributedString:) built the removed `text`.
    // Evidence Forward has no replacement init: 0 SubtitlePart init reflection symbols (only search(with:));
    // the type-metadata accessor 0x101abf1e0 has 0 CODE construction xrefs (2 DATA self/stdlib); every caller
    // (SrtParse/VTTParse/AssParse parsers — Batch-1 audit-confirmed — and SubtitleDecode) builds SubtitlePart
    // INLINE via the memberwise init + SubtitleTextInfo(.right)/SubtitleImageInfo(.left), no init function.
}

public struct TextPosition {
    public var verticalAlign: VerticalAlignment = .bottom
    public var horizontalAlign: HorizontalAlignment = .center
    public var leftMargin: CGFloat = 0
    public var rightMargin: CGFloat = 0
    public var verticalMargin: CGFloat = 10
    public var edgeInsets: EdgeInsets {
        var edgeInsets = EdgeInsets()
        if verticalAlign == .bottom {
            edgeInsets.bottom = verticalMargin
        } else if verticalAlign == .top {
            edgeInsets.top = verticalMargin
        }
        if horizontalAlign == .leading {
            edgeInsets.leading = leftMargin
        }
        if horizontalAlign == .trailing {
            edgeInsets.trailing = rightMargin
        }
        return edgeInsets
    }

    public mutating func ass(alignment: String?) {
        switch alignment {
        case "1":
            verticalAlign = .bottom
            horizontalAlign = .leading
        case "2":
            verticalAlign = .bottom
            horizontalAlign = .center
        case "3":
            verticalAlign = .bottom
            horizontalAlign = .trailing
        case "4":
            verticalAlign = .center
            horizontalAlign = .leading
        case "5":
            verticalAlign = .center
            horizontalAlign = .center
        case "6":
            verticalAlign = .center
            horizontalAlign = .trailing
        case "7":
            verticalAlign = .top
            horizontalAlign = .leading
        case "8":
            verticalAlign = .top
            horizontalAlign = .center
        case "9":
            verticalAlign = .top
            horizontalAlign = .trailing
        default:
            break
        }
    }
}

extension SubtitlePart: Comparable {
    public static func == (left: SubtitlePart, right: SubtitlePart) -> Bool {
        if left.start == right.start, left.end == right.end {
            return true
        } else {
            return false
        }
    }

    public static func < (left: SubtitlePart, right: SubtitlePart) -> Bool {
        if left.start < right.start {
            return true
        } else {
            return false
        }
    }
}

extension SubtitlePart: NumericComparable {
    public typealias Compare = TimeInterval
    public static func == (left: SubtitlePart, right: TimeInterval) -> Bool {
        left.start <= right && left.end >= right
    }

    public static func < (left: SubtitlePart, right: TimeInterval) -> Bool {
        left.end < right
    }
}

public protocol KSSubtitleProtocol {
    // The sole requirement (NumRequirements=1, desc 0x1039f18a0). Forward version-changed the base
    // `search(for time: TimeInterval) -> [SubtitlePart]` (sync) to a query-based ASYNC lookup: the mangled
    // requirement name is `search…KSSubtitleQueryV_tYaF` and both info-class witnesses are async-fp records.
    // Rippled to all 6 conformers (P55, session 21) — the conformance gate checks presence, not signature.
    func search(with query: KSSubtitleQuery) async -> [SubtitlePart]
}

public protocol SubtitleInfo: KSSubtitleProtocol, AnyObject, Hashable, Identifiable {
    var subtitleID: String { get }
    var name: String { get }
    var delay: TimeInterval { get set }
    //    var userInfo: NSMutableDictionary? { get set }
    //    var subtitleDataSouce: SubtitleDataSouce? { get set }
//    var comment: String? { get }
    var isEnabled: Bool { get set }
}

public extension SubtitleInfo {
    var id: String { subtitleID }
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

open class SubtitleModel: ObservableObject {
    public enum Size {
        case smaller
        case standard
        case large
        public var rawValue: CGFloat {
            switch self {
            case .smaller:
                #if os(tvOS) || os(xrOS)
                return 48
                #elseif os(macOS) || os(xrOS)
                return 20
                #else
                if UI_USER_INTERFACE_IDIOM() == .phone {
                    return 12
                } else {
                    return 20
                }
                #endif
            case .standard:
                #if os(tvOS) || os(xrOS)
                return 58
                #elseif os(macOS) || os(xrOS)
                return 26
                #else
                if UI_USER_INTERFACE_IDIOM() == .phone {
                    return 16
                } else {
                    return 26
                }
                #endif
            case .large:
                #if os(tvOS) || os(xrOS)
                return 68
                #elseif os(macOS) || os(xrOS)
                return 32
                #else
                if UI_USER_INTERFACE_IDIOM() == .phone {
                    return 20
                } else {
                    return 32
                }
                #endif
            }
        }
    }

    nonisolated(unsafe) public static var textColor: Color = .white
    nonisolated(unsafe) public static var textBackgroundColor: Color = .clear
    public static var textFont: UIFont {
        textBold ? .boldSystemFont(ofSize: textFontSize) : .systemFont(ofSize: textFontSize)
    }

    nonisolated(unsafe) public static var textFontSize = SubtitleModel.Size.standard.rawValue
    nonisolated(unsafe) public static var textBold = false
    // ⚑ DAT_104c63248 (module-level static Bool; get FUN_1019bb6c0 / set FUN_1019bb700) — read in the iOS-18
    //   translate success funclet 5aa8@0x6148: when true, the translated subtitle prepends the ORIGINAL text
    //   ("original\ntranslation"). Exact source name/owner unrecoverable (P28) → recon-named here.
    nonisolated(unsafe) public static var showsOriginalWithTranslation = false
    nonisolated(unsafe) public static var textItalic = false
    nonisolated(unsafe) public static var textPosition = TextPosition()
    nonisolated(unsafe) public static var audioRecognizes = [any AudioRecognize]()
    // §7.3 — 24 fields in binary reflection order. @Published-backed → `_x` in field metadata;
    // `_translationSessionConf`/`_translationSession` are manual `_`-backings (computed accessors; the iOS18
    // TranslationSession is boxed for availability). Method bodies → P4 M2.
    public var translation: Bool = false
    private var _translationSessionConf: Any?
    private var _translationSession: AnyObject?
    public var subtitleDataSources: [any SubtitleDataSource] = KSOptions.subtitleDataSources
    @Published public private(set) var subtitleInfos: [any SubtitleInfo] = []
    @Published public private(set) var searchedSubtitleInfos: [URLSubtitleInfo] = []
    @Published public private(set) var parts: [SubtitlePart] = []
    public var subtitleDelay: Double = 0.0 // s
    public var dynamicRange: DynamicRange = .sdr // ⚑ default inferred → M2
    public var options: KSOptions
    @Published public var flag: Int = 0
    @Published public var subtitleTranslateY: Float = 0
    public var playRatio: Double = 1
    @Published public var screenSize: CGSize = .zero
    public var subtitleSearchGeneration: Int = 0 // ⚑ Int store-evidenced (§7.5)
    public var subtitleSearchSequence: Int = 0 // ⚑ Int store-evidenced (§7.5)
    public var latestPrimarySubtitleQueryTime: Double?
    public var latestSecondarySubtitleQueryTime: Double?
    public var url: URL? // ⚑ §7.5: mangle reads NON-optional; recon URL? w/ search didSet → M2 verify
    public var firstSubtitleActor: SubtitleActor?
    // FUN_101ab2540 — selectedSubtitleInfo willSet (P67: 11 assign-site callers, call-before-store w/ newValue;
    // the prior recon guess @Published+didSet was wrong — binary is plain-stored with a willSet).
    public var selectedSubtitleInfo: (any SubtitleInfo)? {
        willSet {
            guard newValue !== selectedSubtitleInfo else { return }
            subtitleSearchGeneration += 1
            subtitleSearchSequence += 1
            latestPrimarySubtitleQueryTime = nil
            latestSecondarySubtitleQueryTime = nil
            parts = []                                  // clear @Published parts (keypath d1e8/d210 ≠ subtitleInfos d140/168)
            selectedSubtitleInfo?.isEnabled = false     // deactivate old (still-old in willSet); witness+0x40 arg=false
            if let newValue {
                // launder the non-Sendable info across the actor-isolation boundary (base `nonisolated(unsafe)`
                // idiom; P62 concurrency escape — under-included per §1, not a logic change).
                nonisolated(unsafe) let info = newValue
                firstSubtitleActor = SubtitleActor(info: info)
                didSelectSubtitle(info)                 // FUN_101ab8250 (shared with secondary); name P28
                if translation, #available(iOS 18, *) {
                    // ⚑ UNRESOLVED → P4 M2 Task 8: build+store TranslationSession.Configuration
                    //   (source/target Locale.Language) via FUN_101aaffa0 updater; availability-boxed
                    //   (_translationSessionConf/_translationSession). Deferred per user-gated scope (Batch 3).
                }
            } else {
                if #available(iOS 18, *) {
                    // ⚑ UNRESOLVED → P4 M2 Task 8: clear the TranslationSession configuration (FUN_101aaffa0 nil path).
                }
                firstSubtitleActor = nil
            }
        }
    }
    public var secondarySubtitleActor: SubtitleActor?
    // FUN_101ab2de4 — secondarySubtitleInfo willSet (P67: 10 callers). Analogous to the primary minus the
    // primary-only translation box; targets secondarySubtitleActor.
    public var secondarySubtitleInfo: (any SubtitleInfo)? {
        willSet {
            guard newValue !== secondarySubtitleInfo else { return }
            subtitleSearchGeneration += 1
            subtitleSearchSequence += 1
            latestPrimarySubtitleQueryTime = nil
            latestSecondarySubtitleQueryTime = nil
            parts = []
            secondarySubtitleInfo?.isEnabled = false
            if let newValue {
                nonisolated(unsafe) let info = newValue
                secondarySubtitleActor = SubtitleActor(info: info)
                didSelectSubtitle(info)
            } else {
                secondarySubtitleActor = nil
            }
        }
    }
    public var searchInfos: [URLSubtitleInfo] = []
    // ⚑ init shape inferred → M2 witness-verify
    public init(options: KSOptions) {
        self.options = options
    }

    // ⚑ UNRESOLVED → P4 M2: recon `init()` — the binary added `options`; consumers still construct SubtitleModel().
    //   Convenience default kept as the consumer-ripple bridge; M2 verifies the real init / options wiring.
    public convenience init() { self.init(options: KSOptions()) }

    // FUN_101ab3a3c (public entry FUN_101ab3a34 passes reselect=true). Dedupe-by-subtitleID with REPLACE
    // (base cce7002 only SKIPPED-if-present — the Forward divergence). `reselect` (default true) gates the
    // re-point of selected/secondary to the new instance (FUN_101ab3d64, single-call-site helper inlined).
    // ⚑ `reselect` param name unrecoverable (P28) — recon-chosen for the semantic bool the public entry sets true.
    public func addSubtitle(info: any SubtitleInfo, reselect: Bool = true) {
        if let index = subtitleInfos.firstIndex(where: { $0.subtitleID == info.subtitleID }) {
            subtitleInfos[index] = info
        } else {
            subtitleInfos.append(info)
        }
        if reselect {
            if let sel = selectedSubtitleInfo, sel.subtitleID == info.subtitleID, sel !== info {
                selectedSubtitleInfo = info
            }
            if let sec = secondarySubtitleInfo, sec.subtitleID == info.subtitleID, sec !== info {
                secondarySubtitleInfo = info
            }
        }
    }

    // FUN_101ab8250 — shared helper invoked by BOTH select willSets on the newly-selected info (2 call sites).
    // Activates it, registers it (addSubtitle reselect:false to avoid re-select recursion), and caches a remote /
    // iCloud-ubiquitous download via a CacheSubtitleDataSource. ⚑ method name unrecoverable (P28).
    // Forward divergence (P59): base cached only `!isFileURL`; Forward also caches (isFileURL && isUbiquitousItem).
    private func didSelectSubtitle(_ info: any SubtitleInfo) {
        info.isEnabled = true
        addSubtitle(info: info, reselect: false)
        if let info = info as? URLSubtitleInfo {
            if info.downloadURL.isFileURL,
               (try? info.downloadURL.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem != true {
                return
            }
            if let url, let cache = subtitleDataSources.first(where: { $0 is CacheSubtitleDataSource }) as? CacheSubtitleDataSource {
                cache.addCache(fileURL: url, downloadURL: info.downloadURL)
            }
        }
    }

    // FUN_101ab9d00 (async fn, async-FP @0x10506e8dd) → FUN_101ab4338 (arg-spill + executor hop) →
    // FUN_101ab438c (entry body) + funclets 4c04/4c54/53e0/5430 (+ deferred translate 5a34/5aa8/664c). §8:
    // subtitle(currentTime:) migrated the base sync `-> Bool` to async Void — the Bool "did-change" signal was
    // dropped (observers react to @Published `parts`; every terminal tail-calls the continuation with NO
    // return-value store, e.g. 5430@0x101ab5a0c `ldr x0,[x22,#8]; br x0`). The two per-track
    // SubtitleActor.search(with:generation:) results MERGE into `parts` (FUN_1019c7b9c = Array append), are
    // validated against the CURRENT latest query time on the half-open interval [start,end) (fcmp-proven
    // 5430@0x5804 `fcmp start,t;b.hi` + @0x5810 `fcmp t,end;b.pl`), then published via the Combine keypath
    // subscript (d1e8/d210 → `parts`, FUN_101b163b0 = `[SubtitlePart] ==` change-guard). The model's `sequence`
    // snapshot is passed as the actor's reentrancy `generation`.
    // ⚑ DEFERRED (translate follow-up, needs `import Translation`): the iOS-18 TranslationSession.translate
    //   branch (setup inside 438c/4c54/5430 + funclets 5a34/5aa8/664c). Omitted here so the non-translate core
    //   builds on all platforms; the translate region of 438c/4c54/5430 is a known-divergence pending that pass.
    public func subtitle(currentTime: TimeInterval) async {
        // pre-hop (FUN_101ab9d00 → 4338): snapshot the invalidation tokens + per-track adjusted times/skip gates
        // BEFORE the executor hop; the 5 core funclets read these back as spilled async-frame slots.
        let generation = subtitleSearchGeneration        // x22+0x9d0  (4338@0x101ab4344)
        let sequence = subtitleSearchSequence            // x22+0x9b0  (4338@0x101ab4358)
        let size = subtitleDisplaySize()                 // fit(playRatio, screenSize) — computed in 438c/4c54@0x469c
        var newParts = [SubtitlePart]()                  // x22+0x980, initialised empty (438c@0x101ab43c0)

        // PRIMARY (438c → glue 4c04 → resume 4c54): firstSubtitleActor != nil (0x988) && !skipPrimary (char 0x92)
        if let firstSubtitleActor, let primaryTime = primarySubtitleQueryTime(currentTime) {
            let query = KSSubtitleQuery(time: primaryTime, size: size,
                                        verticalAlign: nil, textPosition: nil, textRole: .primary)   // 438c@0x48ac
            newParts += await firstSubtitleActor.search(with: query, generation: sequence)           // → 0x101ab8864
        }
        // SECONDARY (4c54 → glue 53e0 → resume 5430; or from 438c when primary absent): secondarySubtitleActor
        // != nil (0x9b8) && !skipSecondary (char 0x93). query.textPosition = static SubtitleModel.textPosition.
        if let secondarySubtitleActor, let secondaryTime = secondarySubtitleQueryTime(currentTime) {
            let position = SubtitleModel.textPosition                                                 // 438c@0x493c
            let query = KSSubtitleQuery(time: secondaryTime, size: size,
                                        verticalAlign: position.verticalAlign,
                                        textPosition: position, textRole: .secondary)
            newParts += await secondarySubtitleActor.search(with: query, generation: sequence)
        }

        // re-guard + validate + publish (resume-2 FUN_101ab5430; the same tail is inlined into 438c/4c54).
        // A *selection* change during our await bumps `generation` → abandon, keep current parts. (5430@0x5490)
        guard generation == subtitleSearchGeneration else { return }
        // A *newer query* during our await bumps `sequence` → publish only if every gathered part is still valid
        // against the CURRENT latest query time; any miss abandons without publishing. (5430@0x54ac → loop)
        if sequence != subtitleSearchSequence {
            // A newer query ran AND no fresh parts were gathered → abandon WITHOUT publishing, so a superseding
            // time-query race doesn't spuriously clear still-valid `parts`. (438c@0x4844 `count==0 → LAB_101ab4bb0`
            // = release + async-return, no _set_subscript; scoped to the seq!=cur branch only.)
            guard !newParts.isEmpty else { return }
            for part in newParts {
                // per-part query time selected by the part's stamped styleRole (csel 5430@0x57d8: role byte at
                // text +0x201 / image +0x228; secondary(1) → latestSecondary…, else latestPrimary…).
                let role: SubtitleTextRole
                switch part.render {
                case let .left(image):
                    role = image.styleRole
                case let .right(text):
                    if text.text.string.isEmpty { return }     // empty-text part → abandon (5430@0x57b8 `cbz`)
                    role = text.styleRole
                }
                let queryTime = role == .secondary ? latestSecondarySubtitleQueryTime
                                                   : latestPrimarySubtitleQueryTime
                // KEEP iff queryTime != nil && start <= t < end  (half-open [start,end); base NumericComparable
                // `==` is the CLOSED [start,end] — the binary corrects it to half-open, so it is inlined here).
                guard let queryTime, part.start <= queryTime, queryTime < part.end else { return }
            }
        }
        // Skip a redundant publish (and its objectWillChange) when nothing changed. (FUN_101b163b0, 5430@0x5508)
        guard newParts != parts else { return }

        // iOS-18 TranslationSession.translate (SETUP in 438c/4c54/5430 @0x551c–56e8; await cont FUN_101ab5a34): if
        // the first gathered part is text and a translation session is configured (self._translationSession,
        // self+0x38), await the translation and republish — success → FUN_101ab5aa8 (config source-adapt + attributed
        // build + a fresh translated part), error → FUN_101ab664c (untranslated fallback). Both re-run the resume
        // tail since generation/sequence can move during the await. ⚑ residual: the size-fit actor.info witness
        // (subtitleDisplaySize) and the pre-hop skip/time (FUN_101ab9d00) remain deferred — the translate path is done.
        #if canImport(Translation) && !os(tvOS) && !os(watchOS)
        if #available(iOS 18, macOS 15, *),
           let first = newParts.first,
           case let .right(textInfo) = first.render,                    // first render must be text (byte@0x779==1)
           let session = _translationSession as? TranslationSession {    // self._translationSession (self+0x38)
            // FUN_101ab5a34: `try? await` → success(response) [x20==0 → 5aa8] vs error(nil) [swift_errorRelease → 664c].
            guard let response = try? await session.translate(textInfo.text.string) else {
                // 664c error fallback: RE-RUN the resume tail (generation/sequence can move during the translate
                // await), then publish the UNTRANSLATED parts (0x101ab664c → 674c).
                publishIfCurrent(newParts, generation: generation, sequence: sequence)
                return
            }
            // 5aa8 entry (0x101ab5aa8–5d58): re-validate the FULL gathered set against the CURRENT query time
            // BEFORE any translation work — a supersession race during the translate await abandons here.
            guard stillCurrent(newParts, generation: generation, sequence: sequence) else { return }
            // 5aa8 success. Adapt the stored config's source language to the detected one when they differ
            // (self._translationSessionConf, self+0x18, via a _modify coroutine FUN_101ab03c8; get/set_source
            // 0x103452c98/ca4, Response.get_sourceLanguage 0x103452cd4, Locale.Language ==_infix 0x1034573f0@0x6448).
            if var conf = _translationSessionConf as? TranslationSession.Configuration,
               conf.source != response.sourceLanguage {
                conf.source = response.sourceLanguage                    // set_source @0x6100
                _translationSessionConf = conf
            }
            // Build the display attributed string (0x101ab6118): when the static flag is set, prepend the ORIGINAL
            // text + "\n"; then append the translated targetText with "\n\n" collapsed to "\n".
            let attributed = NSMutableAttributedString()
            if SubtitleModel.showsOriginalWithTranslation {              // ⚑ DAT_104c63248 @0x6148 (see static above)
                attributed.append(textInfo.text)                         // original (appendAttributedString @0x6160)
                attributed.append(NSAttributedString(string: "\n"))      // separator (@0x6198)
            }
            let translated = response.targetText.replacingOccurrences(of: "\n\n", with: "\n")   // @0x61ec/@0x6250
            attributed.append(NSAttributedString(string: translated))    // @0x62a8
            // Build the translated part = copy of the first text part with only `text` replaced, then publish a
            // FRESH 1-element array (0x101ab62b0–63cc _set_subscript keypaths d1e8/d210 → @Published parts).
            var newTextInfo = textInfo
            newTextInfo.text = attributed
            let translatedPart = SubtitlePart(start: first.start, end: first.end, render: .right(newTextInfo))
            // 5aa8: RE-RUN the resume tail after the translate await, then publish the fresh 1-element array
            // (0x101ab6360 re-guard → 0x63cc _set_subscript).
            publishIfCurrent([translatedPart], generation: generation, sequence: sequence)
            return
        }
        #endif

        parts = newParts     // publish — set_subscript on keypaths d1e8/d210 → @Published `parts` (5430@0x58c0)
    }

    // ⚑ pre-hop helpers (FUN_101ab9d00, one level ABOVE the 5 core funclets): the skip gates (char 0x92/0x93)
    //   and per-track adjusted query times (0x990/0x9c0) are computed before the executor hop and read by the
    //   core as spilled slots. Exact skip predicate + delay formula are UNVERIFIED (best-effort); the core's
    //   faithfulness is unaffected (it only reads the spilled results). Optional return models the skip gate.
    private func primarySubtitleQueryTime(_ currentTime: TimeInterval) -> Double? {
        currentTime - (selectedSubtitleInfo?.delay ?? 0) - subtitleDelay
    }

    private func secondarySubtitleQueryTime(_ currentTime: TimeInterval) -> Double? {
        currentTime - (secondarySubtitleInfo?.delay ?? 0) - subtitleDelay
    }

    // query.size (438c/4c54 @0x469c): integer-truncated aspect fit of screenSize to playRatio (FUN_1019e7800 —
    // letterbox when playRatio ≤ height/width, else pillarbox). ⚑ gated in-binary by an `actor.info` Bool witness
    // (info wtable+0x50) whose identity is UNVERIFIED, so the size-fit region of 438c/4c54 is a known divergence
    // pending that decode; represented unconditionally here.
    private func subtitleDisplaySize() -> CGSize {
        let w = screenSize.width, h = screenSize.height, r = playRatio
        guard r != 0, w != 0 else { return screenSize }
        return r <= h / w ? CGSize(width: w, height: Double(Int(r * w)))
                          : CGSize(width: Double(Int(h / r)), height: h)
    }

    // The resume-tail predicate: the generation snapshot still matches AND (when the sequence moved) every part is
    // still within its role's latest-query half-open [start,end) window. Re-run after the iOS-18 translate `await`
    // since generation/sequence may have changed during it. `@inline(__always)` to match the binary's
    // tail-inlined-into-every-funclet codegen (5aa8 entry @0x5aa8 over newParts / 5aa8 publish @0x6360 over the
    // translated part / 664c @0x674c over newParts).
    @inline(__always)
    private func stillCurrent(_ items: [SubtitlePart], generation: Int, sequence: Int) -> Bool {
        guard generation == subtitleSearchGeneration else { return false }
        if sequence != subtitleSearchSequence {
            guard !items.isEmpty else { return false }
            for part in items {
                let role: SubtitleTextRole
                switch part.render {
                case let .left(image):
                    role = image.styleRole
                case let .right(text):
                    if text.text.string.isEmpty { return false }
                    role = text.styleRole
                }
                let queryTime = role == .secondary ? latestSecondarySubtitleQueryTime
                                                   : latestPrimarySubtitleQueryTime
                guard let queryTime, part.start <= queryTime, queryTime < part.end else { return false }
            }
        }
        return true
    }

    @inline(__always)
    private func publishIfCurrent(_ items: [SubtitlePart], generation: Int, sequence: Int) {
        if stillCurrent(items, generation: generation, sequence: sequence) { parts = items }
    }

    // FUN_101ab68d8 — NOT the base network datasource search (later·115 mis-ID, corrected session 22): a
    // generation-invalidation + actor-reset trigger. The text `query`/`languages` are UNUSED here — the
    // network search moved into the per-track SubtitleActors (lazy). Bumps the model generation/sequence,
    // resets both query-times + `parts`, then resets both actors (FUN_101ab6acc→6b5c/6bc4/6c2c chain).
    // Signature kept (base + consumer KSVideoPlayerView:664); the args are ignored per the binary body.
    public func searchSubtitle(query _: String?, languages _: [String]) {
        subtitleSearchGeneration += 1
        subtitleSearchSequence += 1
        latestPrimarySubtitleQueryTime = nil
        latestSecondarySubtitleQueryTime = nil
        parts = []
        // base `nonisolated(unsafe) let strongSelf = self` idiom (P62; binary Task ctx retains self@+0x20).
        nonisolated(unsafe) let strongSelf = self
        Task {
            await strongSelf.firstSubtitleActor?.reset()
            await strongSelf.secondarySubtitleActor?.reset()
        }
    }
}
