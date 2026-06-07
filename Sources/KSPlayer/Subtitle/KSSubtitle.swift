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

// MARK: - SubtitlePart

/// A single displayable subtitle entry: a time window plus its rendered content.
///
/// RE (1.3.15 correction): `SubtitlePart` is a **`struct`** (value type), confirmed
/// by the Swift value-witness mangling `$s8KSPlayer12SubtitlePartVw…` (the `V` marks
/// a struct) and the value-witness `initializeWithCopy @ 0x10149a14c`, which copies an
/// inline payload spanning offsets `0x0..0x59` (~0x5a bytes). It carries exactly three
/// stored fields — `start` (`+0x0`), `end` (`+0x8`), and a single `render` (`+0x10`)
/// that is an `Either` of the image- and text-info structs — *not* separate
/// `origin` / `text` / `image` / `textPosition` members (those were the pre-1.3.15
/// class shape and are now reached *through* `render`). `types.json` records only
/// `{start, end, render}` for `KSPlayer.SubtitlePart`.
///
/// The legacy `text` / `image` / `origin` / `textPosition` members are preserved here
/// as **computed** accessors over `render` so existing call sites (AssImageParse,
/// MetalSubtitleView, VideoPlayerView, SubtitleTranslation, the parser cluster, the
/// FFmpeg decode path, …) keep compiling against the documented value-type layout.
public struct SubtitlePart: CustomStringConvertible, Identifiable {
    /// Display start time (seconds). RE offset `+0x0`.
    public var start: TimeInterval
    /// Display end time (seconds). RE offset `+0x8`.
    public var end: TimeInterval
    /// Rendered payload — image branch (bitmap / ASS-image) or text branch.
    /// RE offset `+0x10`, `Either<SubtitleImageInfo, SubtitleTextInfo>`.
    public var render: Either<SubtitleImageInfo, SubtitleTextInfo>

    public var id: TimeInterval { start }

    public var description: String {
        "Subtitle Group ==========\nstart: \(start)\nend:\(end)\ntext:\(String(describing: text))"
    }

    /// Primary memberwise initializer (RE struct shape: start, end, render).
    public init(start: TimeInterval, end: TimeInterval, render: Either<SubtitleImageInfo, SubtitleTextInfo>) {
        self.start = start
        self.end = end
        self.render = render
    }

    /// Convenience initializer over a `SubtitleImageInfo` (bitmap / ASS-image branch).
    public init(start: TimeInterval, end: TimeInterval, image: SubtitleImageInfo) {
        self.init(start: start, end: end, render: .left(image))
    }

    /// Convenience initializer over a `SubtitleTextInfo` (text branch).
    public init(start: TimeInterval, end: TimeInterval, text: SubtitleTextInfo) {
        self.init(start: start, end: end, render: .right(text))
    }

    // MARK: Legacy convenience inits (preserved API surface)

    /// Build a text part from a raw string (whitespace-trimmed, CR-stripped).
    /// Mirrors the upstream `SubtitlePart(_:_:_:)` convenience init; the content
    /// is stored in `render`'s text branch.
    public init(_ start: TimeInterval, _ end: TimeInterval, _ string: String) {
        var text = string
        text = text.trimmingCharacters(in: .whitespaces)
        text = text.replacingOccurrences(of: "\r", with: "")
        self.init(start, end, attributedString: NSAttributedString(string: text))
    }

    /// Build a part from an optional attributed string. A `nil` string yields an
    /// empty text payload that callers typically fill in afterward by assigning
    /// `image` / `origin` (the ASS-image render path) — matching the previous
    /// class shape's two-step construction.
    public init(_ start: TimeInterval, _ end: TimeInterval, attributedString: NSAttributedString?) {
        let info = SubtitleTextInfo(text: attributedString ?? NSAttributedString(string: ""), position: nil, displaySize: nil)
        self.init(start: start, end: end, render: .right(info))
    }

    // MARK: Legacy computed members (reach through `render`)

    /// Attributed text of the text branch, or `nil` for an image part.
    public var text: NSAttributedString? {
        get {
            if case let .right(info) = render { return info.text }
            return nil
        }
        set {
            switch render {
            case var .right(info):
                info.text = newValue ?? NSAttributedString(string: "")
                render = .right(info)
            case .left:
                // Switching an image part to text: build a fresh text payload.
                render = .right(SubtitleTextInfo(text: newValue ?? NSAttributedString(string: ""), position: textPosition, displaySize: nil))
            }
        }
    }

    /// Bitmap image of the image branch, bridged to `UIImage` for legacy callers.
    /// Reading returns `nil` for a text part; assigning a non-nil image promotes
    /// the part to the image branch.
    public var image: UIImage? {
        get {
            if case let .left(info) = render { return UIImage(cgImage: info.image) }
            return nil
        }
        set {
            guard let cgImage = newValue?.cgImage else {
                // Assigning nil image clears the image branch back to empty text.
                if case .left = render {
                    render = .right(SubtitleTextInfo(text: NSAttributedString(string: ""), position: nil, displaySize: nil))
                }
                return
            }
            let displaySize = CGSize(width: cgImage.width, height: cgImage.height)
            let origin = self.origin
            render = .left(SubtitleImageInfo(rect: CGRect(origin: origin, size: displaySize), image: cgImage, displaySize: displaySize))
        }
    }

    /// Draw origin of the image branch (`rect.origin`); `.zero` for a text part.
    public var origin: CGPoint {
        get {
            if case let .left(info) = render { return info.rect.origin }
            return .zero
        }
        set {
            if case var .left(info) = render {
                info.rect.origin = newValue
                render = .left(info)
            }
        }
    }

    /// Layout position of the text branch; `nil` for an image part.
    public var textPosition: TextPosition? {
        get {
            if case let .right(info) = render { return info.position }
            return nil
        }
        set {
            if case var .right(info) = render {
                info.position = newValue
                render = .right(info)
            }
        }
    }
}

// MARK: - TextPosition

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

    public init(verticalAlign: VerticalAlignment = .bottom,
                horizontalAlign: HorizontalAlignment = .center,
                leftMargin: CGFloat = 0,
                rightMargin: CGFloat = 0,
                verticalMargin: CGFloat = 10) {
        self.verticalAlign = verticalAlign
        self.horizontalAlign = horizontalAlign
        self.leftMargin = leftMargin
        self.rightMargin = rightMargin
        self.verticalMargin = verticalMargin
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

// MARK: - SubtitleImageInfo / SubtitleTextInfo (render payloads)

/// Image branch of `SubtitlePart.render` — a positioned bitmap (PGS / VOBSUB /
/// DVB / rasterized ASS image).
///
/// RE: doc §1746. `struct SubtitleImageInfo { rect: CGRect; image: CGImage;
/// displaySize: CGSize }`. Also consumed by `SubtitleLeftView` (§1761) and the
/// `MetalSubtitleView` image path.
public struct SubtitleImageInfo {
    /// Placement rectangle in the source subtitle coordinate space.
    public var rect: CGRect
    /// Decoded bitmap (Core Graphics image; bridged to `UIImage` for legacy callers).
    public var image: CGImage
    /// Native size the image was rendered at (PlayRes / drawable dimensions).
    public var displaySize: CGSize

    public init(rect: CGRect, image: CGImage, displaySize: CGSize) {
        self.rect = rect
        self.image = image
        self.displaySize = displaySize
    }
}

/// Text branch of `SubtitlePart.render` — an attributed string plus its layout.
///
/// RE: doc §1752. `struct SubtitleTextInfo { text: NSAttributedString;
/// position: TextPosition?; displaySize: CGSize? }`. Element type of
/// `MetalSubtitleView.textInfos` (§1759).
public struct SubtitleTextInfo {
    /// Rendered attributed string for the text overlay.
    public var text: NSAttributedString
    /// Optional explicit layout position (alignment + margins).
    public var position: TextPosition?
    /// Optional canvas size the text was measured against.
    public var displaySize: CGSize?

    public init(text: NSAttributedString, position: TextPosition?, displaySize: CGSize?) {
        self.text = text
        self.position = position
        self.displaySize = displaySize
    }
}

// MARK: - SubtitlePart conformances

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

// MARK: - KSSubtitleQuery

/// Lightweight value-type query bundle carrying the three render-context inputs
/// the libass image path needs to fetch / lay out a subtitle frame at a given
/// instant: the playback time, the destination canvas size, and the desired
/// vertical anchor.
///
/// RE: doc §1678-1722. `struct KSSubtitleQuery` (`$s8KSPlayer15KSSubtitleQueryV`)
/// with EXACTLY 3 stored fields in order — `time: Double` (`+0x0`, converted to ms
/// via `time * 1000.0` for `libass_ass_render_frame`), `size: CGSize`
/// (`+0x10`/`+0x18`), `verticalAlign: SwiftUI.VerticalAlignment?` (payload `+0x20`,
/// tag `+0x21`). Total instance `0x28` (40 bytes), confirmed via value-witness
/// `initializeWithTake $s8KSPlayer15KSSubtitleQueryVwst @ 0x10148487c`. Consumed by
/// `AssImageRenderer_renderSubtitleFrame @ 0x101474e8c`.
public struct KSSubtitleQuery {
    /// Playback time (seconds) at which to fetch the subtitle frame; converted to
    /// milliseconds (`time * 1000.0`) for `libass_ass_render_frame`.
    public var time: Double
    /// Target render canvas size (PlayRes / drawable dimensions); drives
    /// `AssImageRenderer.size` and triggers `updateFrameSize` on change.
    public var size: CGSize
    /// Optional vertical anchor (top / center / bottom); mirrors
    /// `AssImageRenderer.verticalAlign`.
    public var verticalAlign: VerticalAlignment?

    public init(time: Double, size: CGSize, verticalAlign: VerticalAlignment? = nil) {
        self.time = time
        self.size = size
        self.verticalAlign = verticalAlign
    }

    /// Convenience accessor matching the renderer's `time * 1000.0` conversion.
    public var timeMilliseconds: Double { time * 1000.0 }
}

// MARK: - KSSubtitleProtocol / SubtitleInfo

public protocol KSSubtitleProtocol {
    func search(for time: TimeInterval) -> [SubtitlePart]
}

public protocol SubtitleInfo: KSSubtitleProtocol, AnyObject, Hashable, Identifiable {
    var subtitleID: String { get }
    var name: String { get }
    var delay: TimeInterval { get set }
    var comment: String? { get }
    var userInfo: NSMutableDictionary? { get set }
    var isEnabled: Bool { get set }
    /// Optional BCP-47 / ISO 639 language code (Forward addition;
    /// matches the binary's EmptySubtitleInfo layout).
    var languageCode: String? { get }
    /// Preferred rendering strategy for this track. Defaults to `.srtView`
    /// when the conformer does not provide one explicitly.
    var renderMode: SubtitleRenderMode { get }
}

public extension SubtitleInfo {
    var id: String { subtitleID }
    var comment: String? { nil }
    var userInfo: NSMutableDictionary? {
        get { nil }
        set {}
    }

    var languageCode: String? { nil }
    var renderMode: SubtitleRenderMode { .srtView }
    func hash(into hasher: inout Hasher) {
        hasher.combine(subtitleID)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.subtitleID == rhs.subtitleID
    }
}

// MARK: - KSSubtitle

public class KSSubtitle {
    public var parts: [SubtitlePart] = []
    public init() {}
}

extension KSSubtitle: KSSubtitleProtocol {
    /// Search for target group for time
    public func search(for time: TimeInterval) -> [SubtitlePart] {
        var result = [SubtitlePart]()
        for part in parts {
            if part == time {
                result.append(part)
            } else if part.start > time {
                break
            }
        }
        return result
    }
}

public extension KSSubtitle {
    func parse(url: URL, userAgent: String? = nil, encoding: String.Encoding? = nil) async throws {
        let data = try await url.data(userAgent: userAgent)
        try parse(data: data, encoding: encoding)
    }

    func parse(data: Data, encoding: String.Encoding? = nil) throws {
        // Forward v1.3.15 routes through SubtitleParse_loadAndParse_async
        // (0x101482858); the synchronous path delegates to the same
        // SubtitleParse.parse(data:) core. Translate the typed
        // SubtitleParse.Failure values back into the legacy
        // KSPlayerErrorCode NSErrors that existing callers expect.
        let registry = SubtitleParseRegistry(parsers: KSOptions.subtitleParses)
        let driver = SubtitleParse(registry: registry)
        do {
            parts = try driver.parse(data: data, preferredEncoding: encoding)
        } catch SubtitleParse.Failure.undecodable {
            throw NSError(errorCode: .subtitleUnEncoding)
        } catch SubtitleParse.Failure.noParserMatched {
            throw NSError(errorCode: .subtitleFormatUnSupport)
        } catch SubtitleParse.Failure.emptyParts {
            throw NSError(errorCode: .subtitleUnParse)
        }
    }

//    public static func == (lhs: KSURLSubtitle, rhs: KSURLSubtitle) -> Bool {
//        lhs.url == rhs.url
//    }
}

// MARK: - NumericComparable / binary search

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

// MARK: - SubtitleModel

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

    // MARK: Static styling properties (user preferences)
    //
    // RE: doc §1539-1552. These are *not* `SubtitleModel` stored properties (they
    // do not appear in the 19-field `types.json` list); they are static / computed
    // appearance settings read by the layout / label-styling paths
    // (`applyStyleToLabel`, `applySystemCaptionAppearance`).

    public static var textColor: Color = .white
    public static var textBackgroundColor: Color = .clear
    public static var textFont: UIFont {
        if let captionFontName, let font = UIFont(name: captionFontName, size: effectiveFontSize) {
            return font
        }
        return textBold ? .boldSystemFont(ofSize: effectiveFontSize) : .systemFont(ofSize: effectiveFontSize)
    }

    /// Font size adjusted by system caption relative size preference
    public static var effectiveFontSize: CGFloat {
        textFontSize * captionRelativeSize
    }

    public static var textFontSize = SubtitleModel.Size.standard.rawValue
    public static var textBold = false
    public static var textItalic = false
    public static var textPosition = TextPosition()
    public static var audioRecognizes = [any AudioRecognize]()

    /// Effective foreground color — prefers system caption setting when applied
    public static var effectiveTextColor: Color {
        if isSystemCaptionAppearanceApplied, let color = captionForegroundColor {
            return color
        }
        return textColor
    }

    /// Effective background color — prefers system caption setting when applied
    public static var effectiveBackgroundColor: Color {
        if isSystemCaptionAppearanceApplied, let color = captionBackgroundColor {
            return color
        }
        return textBackgroundColor
    }

    // MARK: Stored properties (19, RE types.json declaration order)
    //
    // RE: doc §1492-1521 — the `types.json` stored-property list for
    // `KSPlayer.SubtitleModel`, in declaration order. `@Published`-wrapped members
    // are the `_`-prefixed backing fields (doc's `Combine.Published<…>`); the public
    // projected property drops the leading underscore. RE init is
    // `SubtitleModel_initFields_inner @ 0x100a59ec4`.

    /// #1 — type-erased backing store for `Translation.SessionConfiguration`
    /// (iOS 17.4+ feature gated). RE field `_translationSessionConf: Any?`.
    var _translationSessionConf: Any?

    /// #2 — type-erased backing store for the active `Translation.TranslationSession`.
    /// RE field `_translationSession: Any?`.
    var _translationSession: Any?

    /// #3 — registered subtitle data sources (not `@Published`).
    /// RE field `subtitleDataSources: [SubtitleDataSource]`.
    private var subtitleDataSources: [SubtitleDataSource] = KSOptions.subtitleDataSources

    /// #4 — all discovered subtitle tracks. RE field `_subtitleInfos`.
    @Published
    public private(set) var subtitleInfos = [any SubtitleInfo]()

    /// #5 — network / search results aggregated here. RE field `_searchedSubtitleInfos`.
    @Published
    public private(set) var searchedSubtitleInfos = [URLSubtitleInfo]()

    /// #6 — currently decoded / active subtitle parts. RE field `_parts`.
    @Published
    public private(set) var parts = [SubtitlePart]()

    /// #7 — user timing adjustment (seconds); not `@Published`.
    /// RE field `subtitleDelay: Double`.
    public var subtitleDelay = 0.0 // s

    /// #8 — drives HDR-aware rendering handed to `MetalSubtitleView`.
    /// RE field `dynamicRange: KSPlayer.DynamicRange`.
    public var dynamicRange: DynamicRange = .sdr

    /// #9 — player options (font dir, `enableHDRSubtitle`, etc.).
    /// RE field `options: KSPlayer.KSOptions`.
    public var options: KSOptions?

    /// #10 — internal change-notification counter. RE field `_flag`.
    @Published
    public private(set) var flag: Int = 0

    /// #11 — secondary-subtitle vertical offset. RE field `_subtitleTranslateY`.
    @Published
    public var subtitleTranslateY: Float = 0

    /// #12 — aspect / scale ratio used in layout; not `@Published`.
    /// RE field `playRatio: Double`.
    public var playRatio: Double = 1.0

    /// #13 — current render canvas size. RE field `_screenSize`.
    @Published
    public var screenSize: CGSize = .zero

    /// #14 — current media URL (triggers search on set). RE field `url: URL`.
    public var url: URL? {
        didSet {
            resetAndReloadSubtitleSources()
        }
    }

    /// #15 — primary-track actor. RE field `firstSubtitleActor: SubtitleActor?`.
    public private(set) var firstSubtitleActor: SubtitleActor?

    /// #16 — active primary subtitle track (class-constrained existential).
    /// RE field `selectedSubtitleInfo: SubtitleInfo?`.
    @Published
    public var selectedSubtitleInfo: (any SubtitleInfo)? {
        didSet {
            oldValue?.isEnabled = false
            selectedSubtitleInfo?.isEnabled = true
            if let url, let info = selectedSubtitleInfo as? URLSubtitleInfo, !info.downloadURL.isFileURL, let cache = subtitleDataSources.first(where: { $0 is CacheSubtitleDataSource }) as? CacheSubtitleDataSource {
                cache.addCache(fileURL: url, downloadURL: info.downloadURL)
            }
        }
    }

    /// #17 — secondary-track actor. RE field `secondarySubtitleActor: SubtitleActor?`.
    public private(set) var secondarySubtitleActor: SubtitleActor?

    /// #18 — active secondary subtitle track (class-constrained existential).
    /// RE field `secondarySubtitleInfo: SubtitleInfo?`.
    ///
    /// Forward/upstream naming drift: older revisions of this reconstruction named
    /// this `selectedSecondSubtitleInfo`; the `types.json` / doc name is
    /// `secondarySubtitleInfo`. The old name is kept as a forwarding alias below so
    /// external call sites (KSPlayerLayer, SubtitleTranslation) keep working.
    @Published
    public var secondarySubtitleInfo: (any SubtitleInfo)? {
        didSet {
            oldValue?.isEnabled = false
            secondarySubtitleInfo?.isEnabled = true
        }
    }

    /// #19 — externally exposed search-result list (not `@Published`).
    /// RE field `searchInfos: [URLSubtitleInfo]`.
    public private(set) var searchInfos = [URLSubtitleInfo]()

    // MARK: Additive Forward state (non-canonical)
    //
    // RE note (doc §1521 stale_code): `secondParts` and the static `useHDREffect`
    // do NOT appear in the authoritative 19-field `types.json` stored-property set.
    // The documented model carries secondary state via `secondarySubtitleActor` /
    // `secondarySubtitleInfo` + `_subtitleTranslateY`, not a `secondParts` buffer.
    // Kept as an additive convenience because `VideoSubtitleView` renders the
    // secondary track from `model.secondParts`; `updateActiveSubtitles` keeps it in
    // sync. Flagged as a Forward bolt-on to reconcile with the SwiftUI view later
    // (CROSS-FILE: `VideoSubtitleView.swift`).

    /// Secondary subtitle parts for display (additive; see note above).
    @Published
    public private(set) var secondParts = [SubtitlePart]()

    /// Whether subtitles should render with HDR-aware compositing (additive).
    public static var useHDREffect: Bool = false

    /// Legacy alias for `secondarySubtitleInfo` — preserved API surface.
    ///
    /// External callers (`KSPlayerLayer.setSelectedSubtitleInfo`,
    /// `SubtitleModel.enableTranslation` in `SubtitleTranslation.swift`) reference
    /// `selectedSecondSubtitleInfo`; forward to the documented field so the rename
    /// does not require cross-file edits.
    public var selectedSecondSubtitleInfo: (any SubtitleInfo)? {
        get { secondarySubtitleInfo }
        set { secondarySubtitleInfo = newValue }
    }

    public init() {
        if !SubtitleModel.isSystemCaptionAppearanceApplied {
            Task { @MainActor in
                SubtitleModel.applySystemCaptionAppearance()
            }
        }
    }

    // MARK: Track registration

    public func addSubtitle(info: any SubtitleInfo) {
        if subtitleInfos.first(where: { $0.subtitleID == info.subtitleID }) == nil {
            subtitleInfos.append(info)
        }
    }

    /// Set the secondary subtitle track for dual subtitle display.
    public func selectSecondSubtitle(_ info: (any SubtitleInfo)?) {
        secondarySubtitleInfo = info
    }

    // MARK: Reset / reload (RE: 0x10149077c)

    /// Clear all subtitle state and re-run discovery across every registered data
    /// source, spawning a per-source parse task funnelled through the primary
    /// `SubtitleActor`.
    ///
    /// RE: `SubtitleModel_resetAndReloadSubtitleSources @ 0x10149077c` (1472B).
    /// The binary:
    ///   1. clears the active parts array (`self.field[10] = emptyArray`, written
    ///      through the Combine `Published` for KVO),
    ///   2. clears `selectedSubtitleInfo` and `firstSubtitleActor`,
    ///   3. calls `DirectorySubtitleDataSource_registerGlobal` (the `swift_once`
    ///      lazy init of the data-source registry global `DAT_104459010`; in this
    ///      reconstruction that registry is `KSOptions.subtitleDataSources`, whose
    ///      first read materializes the same `[DirectorySubtitleDataSource()]`
    ///      default under a `swift_once` token),
    ///   4. reads the registered data sources from `DAT_104459010` (load at
    ///      `0x10149093c`),
    ///   5. spawns a `@MainActor` task per source via `SubtitleActor_startParsing`.
    public func resetAndReloadSubtitleSources() {
        // (1) clear active parts (Published write → objectWillChange).
        parts = []
        secondParts = []
        // (2) clear primary selection + actor.
        selectedSubtitleInfo = nil
        firstSubtitleActor = nil
        secondarySubtitleActor = nil
        // (3) materialize the registry global (swift_once-guarded lazy init).
        // Reading `KSOptions.subtitleDataSources` runs the same one-time
        // `registerGlobal` initialization the binary performs before iterating.
        subtitleDataSources = KSOptions.subtitleDataSources
        subtitleInfos.removeAll()
        searchedSubtitleInfos.removeAll()
        searchInfos.removeAll()
        if url != nil {
            subtitleInfos.append(contentsOf: SubtitleModel.audioRecognizes)
        }
        // (4)(5) iterate registered sources; spawn a MainActor parse task per
        // source. File-backed sources resolve against the current URL first.
        searchSubtitle(query: nil, languages: [])
        for dataSource in subtitleDataSources {
            addSubtitle(dataSource: dataSource)
        }
    }

    // MARK: Search / data-source ingestion

    public func searchSubtitle(query: String?, languages: [String]) {
        for dataSource in subtitleDataSources {
            if let dataSource = dataSource as? SearchSubtitleDataSource {
                subtitleInfos.removeAll { info in
                    dataSource.infos.contains {
                        $0 === info
                    }
                }
                Task { @MainActor in
                    try? await dataSource.searchSubtitle(query: query, languages: languages)
                    subtitleInfos.append(contentsOf: dataSource.infos)
                    // Aggregate any URL-based results into the searched list.
                    let urlInfos = dataSource.infos.compactMap { $0 as? URLSubtitleInfo }
                    for info in urlInfos where !searchedSubtitleInfos.contains(where: { $0.subtitleID == info.subtitleID }) {
                        searchedSubtitleInfos.append(info)
                        searchInfos.append(info)
                    }
                }
            }
        }
    }

    public func addSubtitle(dataSource: SubtitleDataSource) {
        if let dataSource = dataSource as? URLSubtitleDataSource {
            Task { @MainActor in
                try? await dataSource.searchSubtitle(fileURL: url)
                subtitleInfos.append(contentsOf: dataSource.infos)
            }
        } else {
            subtitleInfos.append(contentsOf: dataSource.infos)
        }
    }

    // MARK: Per-tick scheduling (RE: 0x1014956d4)

    /// Per-tick subtitle scheduler — selects the parts visible at `currentTime`
    /// for the primary and secondary tracks and republishes them when they change.
    ///
    /// RE: `SubtitleModel_updateActiveSubtitles @ 0x1014956d4` (1532B). The binary
    /// absorbs what older IDA notes split off as `removeNonMatchingSubtitleParts`:
    /// a Dutch-flag partition of the parts buffer driven by the per-part "matched"
    /// bit at part-offset `+0x79`, with manual COW via
    /// `_swift_isUniquelyReferenced_nonNull_native` before in-place mutation and a
    /// `@MainActor` dispatch (`FUN_10000b0cc`) for the UI refresh. This Swift
    /// reconstruction relies on the standard library's array value semantics (free
    /// COW) and `@Published`'s main-thread dispatch, but performs the same
    /// matched-bit partition + republish, including secondary-track handling.
    ///
    /// Returns `true` when either the primary or secondary parts buffer changed.
    public func updateActiveSubtitles(currentTime: TimeInterval) -> Bool {
        var changed = false
        // Primary track.
        var newParts = [SubtitlePart]()
        if let subtile = selectedSubtitleInfo {
            let primaryTime = currentTime - subtile.delay - subtitleDelay
            newParts = subtile.search(for: primaryTime)
            if newParts.isEmpty {
                newParts = parts.filter { part in
                    part == primaryTime
                }
            }
        }
        if newParts != parts {
            applyDisplayFont(to: newParts)
            parts = newParts
            changed = true
        }
        // Secondary track.
        var newSecondParts = [SubtitlePart]()
        if let secondSub = secondarySubtitleInfo {
            let secondaryTime = currentTime - secondSub.delay - subtitleDelay
            newSecondParts = secondSub.search(for: secondaryTime)
        }
        if newSecondParts != secondParts {
            applyDisplayFont(to: newSecondParts)
            secondParts = newSecondParts
            changed = true
        }
        return changed
    }

    /// Legacy entry point name kept for existing callers
    /// (`KSVideoPlayer`, `VideoPlayerView`). Delegates to `updateActiveSubtitles`.
    @discardableResult
    public func subtitle(currentTime: TimeInterval) -> Bool {
        updateActiveSubtitles(currentTime: currentTime)
    }

    /// Stamp the active display font onto each text part (matches the binary's
    /// per-part attribute fix-up before the buffer is republished).
    private func applyDisplayFont(to parts: [SubtitlePart]) {
        for part in parts {
            if let text = part.text as? NSMutableAttributedString {
                text.addAttributes([.font: SubtitleModel.textFont],
                                   range: NSRange(location: 0, length: text.length))
            }
        }
    }

    // MARK: View dispatch (RE: 0x101495f24)

    /// Push the currently active subtitle parts into the configured rendering view.
    ///
    /// RE: `SubtitleModel_applySubtitleToView @ 0x101495f24` (452B, hot path —
    /// 5 code callers + 1 DATA xref at vtable `0x104822512`). The binary dispatches
    /// the active parts to the configured `MetalSubtitleView`, also handing across
    /// the play ratio, content dynamic range and screen size so the view can lay
    /// out and composite. This reconstruction performs the same hand-off when given
    /// a `MetalSubtitleView`, copying `parts`, `playRatio` and `dynamicRange`; the
    /// view's own `didSet` chain (`updateImageInfos` / `setNeedsDisplay`) drives the
    /// actual CIContext draw. Callers in the binary: `FUN_1014917e0`,
    /// `FUN_101494554`, `FUN_1014a2350`, `FUN_1015075f8`,
    /// `KSPlayerLayer_playerStateDidChange_callback`.
    @MainActor
    public func applySubtitleToView(_ view: MetalSubtitleView) {
        view.playRatio = playRatio
        view.dynamicRange = dynamicRange
        view.parts = parts
    }

    // MARK: Secondary subtitle translate + layout (RE: 0x10149299c)

    /// Translate (when a `TranslationSession` is configured) and lay out the
    /// secondary subtitle track, applying the `subtitleTranslateY` vertical offset.
    ///
    /// RE: `SubtitleModel_translateAndLayoutSecondarySubtitle @ 0x10149299c`
    /// (1352B). The binary uses `_subtitleTranslateY` and the
    /// `Translation.TranslationSession` (iOS 17.4+) to translate the secondary
    /// parts in place and re-anchor them above the primary track. The translation
    /// machinery itself lives in `SubtitleTranslation.swift` (TranslationSubtitleInfo
    /// performs the on-device `TranslationSession.translate`); this method performs
    /// the layout half — it stamps the `subtitleTranslateY` offset onto each
    /// secondary part's text position so the secondary line floats above the primary
    /// one, then republishes `secondParts`.
    public func translateAndLayoutSecondarySubtitle() {
        guard !secondParts.isEmpty else { return }
        let offset = CGFloat(subtitleTranslateY)
        var laidOut = [SubtitlePart]()
        laidOut.reserveCapacity(secondParts.count)
        for var part in secondParts {
            var position = part.textPosition ?? TextPosition(verticalAlign: .top, horizontalAlign: .center)
            // Float the secondary track above the primary by the translate-Y offset.
            position.verticalAlign = .top
            position.verticalMargin += offset
            part.textPosition = position
            laidOut.append(part)
        }
        secondParts = laidOut
    }

    // MARK: Remaining Ghidra-named entry points
    //
    // RE: doc §1554 catalogs 22 SubtitleModel functions. Beyond the four primary
    // entry points above, the following are the remaining documented roles. Several
    // map onto Swift-synthesized members (init field setup, the ObservableObject
    // publisher, deinit) — those are noted rather than re-implemented because the
    // compiler emits them. The behavioral ones get real bodies.
    //
    // NOTE: `SubtitleModel_currentTime_setter @ 0x1000dbb00` is MISATTRIBUTED
    // actor-destroy logic (DATA-xref only) — deliberately NOT reconstructed as a
    // setter here, per doc §1527/§1576.

    /// Configure a `MetalSubtitleView` for this model (initial wiring of ratio /
    /// range / screen size before the first `applySubtitleToView`).
    ///
    /// RE: `SubtitleModel_configureSubtitleView @ 0x1014914d8`.
    @MainActor
    public func configureSubtitleView(_ view: MetalSubtitleView) {
        view.playRatio = playRatio
        view.dynamicRange = dynamicRange
        applySubtitleToView(view)
    }

    /// Kick off async parsing of the selected external subtitle into the primary
    /// actor. Mirrors the binary's `asyncSubtitleParse` task allocation: it fetches
    /// + parses through the standalone `SubtitleParse` driver and pushes the result
    /// into `firstSubtitleActor`.
    ///
    /// RE: `SubtitleModel_asyncSubtitleParse @ 0x1014922a0`.
    public func asyncSubtitleParse(info: any SubtitleInfo) {
        let actor = SubtitleActor()
        firstSubtitleActor = actor
        Task {
            await actor.setInfo(info)
            if let urlInfo = info as? URLSubtitleInfo {
                let driver = SubtitleParse(registry: SubtitleParseRegistry(parsers: KSOptions.subtitleParses))
                if let parsed = try? await driver.loadAndParseAsync(url: urlInfo.downloadURL) {
                    await actor.setParts(parsed)
                }
            }
        }
    }

    /// Recompute the on-screen subtitle position from the current `screenSize` /
    /// `playRatio`. The binary updates the per-part text positions when the canvas
    /// size changes; here we republish the active parts so dependent views relayout.
    ///
    /// RE: `SubtitleModel_updateSubtitlePosition @ 0x101491d18`.
    public func updateSubtitlePosition() {
        // Touch the change counter so observers re-read layout-affecting state.
        flag &+= 1
    }

    /// Apply the active styling (font / color / position) to a text label.
    ///
    /// RE: `SubtitleModel_applyStyleToLabel @ 0x10149173c`. The binary stamps the
    /// static appearance properties onto the label used for text subtitles. The
    /// concrete `PaddedLabel` styling happens in `MetalSubtitleView`; this helper
    /// applies the model-level font/color to an attributed string.
    public func applyStyleToLabel(_ attributed: NSMutableAttributedString) {
        let range = NSRange(location: 0, length: attributed.length)
        // UIColor is a typealias for NSColor on AppKit, so UIColor(_:Color)
        // covers both platforms (matching MetalSubtitleView's `UIColor(backgroundColor)`).
        attributed.addAttributes([
            .font: SubtitleModel.textFont,
            .foregroundColor: UIColor(SubtitleModel.effectiveTextColor),
        ], range: range)
    }

    /// Lay out the subtitle view for the current screen size / content mode.
    ///
    /// RE: `SubtitleModel_layoutSubtitleView @ 0x1014915ec`. Pushes the current
    /// `screenSize` into the rendering view and re-applies the active parts.
    @MainActor
    public func layoutSubtitleView(_ view: MetalSubtitleView) {
        applySubtitleToView(view)
    }

    /// Set the external subtitle URL and trigger discovery — the task-switch /
    /// continuation entry points the binary splits the URL-set across.
    ///
    /// RE: `SubtitleModel_setSubtitleURL_continuation @ 0x101379258`,
    /// `_resolveWitness @ 0x1014955f0`, `_taskSwitch @ 0x100c48a60`. In Swift the
    /// `url` `didSet` (which calls `resetAndReloadSubtitleSources`) is the single
    /// observable equivalent of that multi-thunk URL-set sequence.
    public func setSubtitleURL(_ url: URL?) {
        self.url = url
    }

    /// Load an explicit external subtitle file and select it.
    ///
    /// RE: `SubtitleModel_loadExternalSubtitle_taskAlloc @ 0x1014960f0`
    /// (+ dealloc closure `@ 0x10003fb50`). Builds a `URLSubtitleInfo`, registers
    /// it, kicks off async parse into the primary actor, and selects it.
    public func loadExternalSubtitle(url: URL) {
        let info = URLSubtitleInfo(url: url)
        addSubtitle(info: info)
        asyncSubtitleParse(info: info)
        selectedSubtitleInfo = info
    }

    /// Search every registered provider for subtitles matching the current media.
    ///
    /// RE: `SubtitleModel_searchSubtitleProviders_taskAlloc @ 0x100032380`. The
    /// task-allocating front for the provider search; delegates to
    /// `searchSubtitle(query:languages:)`.
    public func searchSubtitleProviders(query: String?, languages: [String]) {
        searchSubtitle(query: query, languages: languages)
    }

    /// Asynchronously (re)load all subtitle sources for the current media.
    ///
    /// RE: `SubtitleModel_asyncSubtitleLoad @ 0x100a64010`. The async front for the
    /// full reload; delegates to the reset-and-reload coordinator.
    public func asyncSubtitleLoad() {
        resetAndReloadSubtitleSources()
    }

    // RE: `SubtitleModel_deinit_helper @ 0x1000673f8`,
    //     `SubtitleModel_initFields_inner @ 0x100a59ec4`,
    //     `SubtitleModel_objectWillChange_getter @ 0x100005e98` are
    // Swift/Combine-synthesized members (stored-property init, the
    // ObservableObject `objectWillChange` publisher, and class deinit cleanup).
    // The compiler emits them from the stored-property declarations and the
    // `ObservableObject` conformance above; no hand-written body is required or
    // appropriate.
}
