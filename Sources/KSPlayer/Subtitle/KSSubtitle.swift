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

    // ⚑ UNRESOLVED → P4 M2: subtitle(currentTime:) (primary/secondary part lookup via SubtitleActor)
    public func subtitle(currentTime: TimeInterval) -> Bool { false }

    // ⚑ UNRESOLVED → P4 M2: searchSubtitle (FUN_101ab68d8 — generation/sequence bump + query-time reset + clear Published + generation-Task)
    public func searchSubtitle(query: String?, languages: [String]) {}
}
