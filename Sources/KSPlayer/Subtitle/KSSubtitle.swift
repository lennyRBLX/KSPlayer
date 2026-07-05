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
    // ⚑ UNRESOLVED → P4 M2: the recon description referenced the removed `text`; the binary body renders
    //   `render` (image-or-text). Minimal faithful placeholder until the witness decode:
    public var description: String { "SubtitlePart(start: \(start), end: \(end))" }

    public init(start: Double, end: Double, render: Either<SubtitleImageInfo, SubtitleTextInfo>) {
        self.start = start
        self.end = end
        self.render = render
    }
    // ⚑ UNRESOLVED → P4 M2: the recon convenience inits [init(_:_:_string:) / init(_:_:attributedString:)]
    //   built `text`; the binary builds `render` (.left(SubtitleImageInfo) / .right(SubtitleTextInfo)).
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
    func search(for time: TimeInterval) -> [SubtitlePart]
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
    public var selectedSubtitleInfo: (any SubtitleInfo)? // ⚑ recon @Published+didSet; binary = plain stored (no `_`) → M2
    public var secondarySubtitleActor: SubtitleActor?
    public var secondarySubtitleInfo: (any SubtitleInfo)?
    public var searchInfos: [URLSubtitleInfo] = []
    // ⚑ init shape inferred → M2 witness-verify
    public init(options: KSOptions) {
        self.options = options
    }

    // ⚑ UNRESOLVED → P4 M2: recon `init()` — the binary added `options`; consumers still construct SubtitleModel().
    //   Convenience default kept as the consumer-ripple bridge; M2 verifies the real init / options wiring.
    public convenience init() { self.init(options: KSOptions()) }

    // ⚑ UNRESOLVED → P4 M2: addSubtitle(info:) (FUN_101ab3a3c — dedupe-by-subtitleID + replace/append, +bool param)
    public func addSubtitle(info: any SubtitleInfo) {}

    // ⚑ UNRESOLVED → P4 M2: subtitle(currentTime:) (primary/secondary part lookup via SubtitleActor)
    public func subtitle(currentTime: TimeInterval) -> Bool { false }

    // ⚑ UNRESOLVED → P4 M2: searchSubtitle (FUN_101ab68d8 — generation/sequence bump + query-time reset + clear Published + generation-Task)
    public func searchSubtitle(query: String?, languages: [String]) {}
}
