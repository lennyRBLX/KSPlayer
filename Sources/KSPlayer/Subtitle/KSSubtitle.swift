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

    // ⚑[tool=export_trie_oracle ref=$s8KSPlayer12SubtitlePartV__6renderACSd_SdAA6EitherOyAA0B9ImageInfoVAA0b4TextG0VGtcfC result=start/end are UNLABELLED (`__6render`), RECOVERED]
    public init(_ start: Double, _ end: Double, render: Either<SubtitleImageInfo, SubtitleTextInfo>) {
        self.start = start
        self.end = end
        self.render = render
    }
    // ⚠️ THE "NO CONVENIENCE INITS" FINDING IS REFUTED. The session-21 P43 existence-check ran in
    // good faith with `nm` + reflection symbols, and those tools cannot see the ORPHANED export
    // trie. Its premise — "0 SubtitlePart init reflection symbols" — is false FIVE times over; the
    // trie carries four convenience inits besides the designated one, including the very
    // `init(_:_:attributedString:)` the note below says was removed:
    //   $s8KSPlayer12SubtitlePartV__16attributedStringACSd_SdSo012NSAttributedE0CtcfC
    //   $s8KSPlayer12SubtitlePartV__4textACSd_SdAA0B8TextInfoVtcfC
    //   $s8KSPlayer12SubtitlePartV__5imageACSd_SdAA0B9ImageInfoVtcfC
    //   $s8KSPlayer12SubtitlePartVyACSd_SdSStcfC          (fully unlabelled, third param String)
    // They are NOT added here: each needs a body reconstructed from its own decompile, which is a
    // unit of its own. What is corrected now is the CLAIM that they do not exist.
    // ⚑[tool=export_trie_oracle ref=SubtitlePart.init x4 result=EXIST — supersedes the session-21 P43 negative]
    // --- superseded session-21 note, kept for provenance: ---
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
}

public extension SubtitleInfo {
    var id: String { subtitleID }
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
    // ⚑ DAT_104c63248 (module-level static Bool; get FUN_1019bb6c0 / set FUN_1019bb700) — read in the iOS-18  ⚑[tool=resolve_fun_pins ref=FUN_1019bb6c0:0x1019bb6c0 result=RESOLVES_UNIQUELY] = static KSPlayer.KSOptions.showTranslateSourceText.getter : Swift.Bool  ⚑[tool=resolve_fun_pins ref=FUN_1019bb700:0x1019bb700 result=RESOLVES_UNIQUELY] = static KSPlayer.KSOptions.showTranslateSourceText.setter : Swift.Bool
    //   translate success funclet 5aa8@0x6148: when true, the translated subtitle prepends the ORIGINAL text
    //   ("original\ntranslation"). Exact source name/owner unrecoverable (P28) → recon-named here.
    nonisolated(unsafe) public static var showsOriginalWithTranslation = false
    nonisolated(unsafe) public static var textItalic = false
    nonisolated(unsafe) public static var textPosition = TextPosition()
    nonisolated(unsafe) public static var audioRecognizes = [any AudioRecognize]()
    // §7.3 — 24 fields in binary reflection order. @Published-backed → `_x` in field metadata;
    // `_translationSessionConf`/`_translationSession` are manual `_`-backings (computed accessors; the iOS18
    // TranslationSession is boxed for availability). Method bodies → P4 M2.
    //
    // ⚑ ACCESSOR-SLOT COLLAPSE (session 59). The descriptor is 112 slots; 0…93 are property accessors in
    // strict getter/setter/modify TRIPLES (kind 2/3/4 read from MethodDescriptorFlags — kind 4 is
    // ModifyCoroutine, NOT a read coroutine). Two families of those slots carry no source at all and
    // collapse into the declarations below; recorded here so they are not re-mined as bodies:
    //   • EVERY `modify` slot. Proven by compiling an `open class` probe (P110): a stored var, a get+set
    //     computed var and a `didSet` var each emit exactly getter/setter/modify while a get-only var emits
    //     ONLY a getter — so the third member of every triple is the synthesized `modify` coroutine. Each
    //     body is a yield-once ramp, and for the plain stored properties the resume funclet is literally
    //     `_swift_endAccess` (0x100046b24 → 0x10003ba24 → 0x10345cce8), SHARED between properties.
    //   • EVERY `@Published` accessor. The bodies call Combine's property-wrapper static subscript with the
    //     `\.x` / `\._x` keypath pair: GOT slots 0x10410ce50/e58/e48 bind (dyld_info -fixups) to
    //     `Combine.Published.subscript(_enclosingInstance:wrapped:storage:)` get/set/modify (…luigZ/luisZ/
    //     luiMZ); the `$x` projection's accessors call `Combine.Published.projectedValue` get/set
    //     (0x10410ce38/e40). All compiler-synthesized property-wrapper machinery.
    // Keypath-pair → property (patterns at 0x10356d…, emitted in declaration order; d140/d168 and d1e8/d210
    // were pinned by earlier sessions and anchor the rest): d140/d168 subtitleInfos · d198/d1c0
    // searchedSubtitleInfos · d1e8/d210 parts · d240/d268 flag · d288/d2b0 subtitleTranslateY · d2d0/d2f8
    // screenSize — corroborated by each getter's return register (flag `ldr x0` = 1 word · subtitleTranslateY
    // `ldr s0` = Float · screenSize `ldp d0,d1` = CGSize). Field offsets come from runtime globals because
    // `Published<T>` is a resilient Combine type, so SubtitleModel's layout is not statically known.
    //
    // @0x101aaf314 — `translation` didSet. Slots 0/1/2 are its accessors and carry NO source: the setter
    // @0x101aafdd0 is the synthesized didSet forwarder (`swift_beginAccess` → `ldrb` oldValue → `strb`
    // newValue → `bl 0x101aaf314`) and the modify @0x101aafe14 is the yield-once ramp over self+0x10.
    // Toggling ON (re)builds the iOS-18 TranslationSession.Configuration only when a subtitle is selected but no
    // config exists yet (the selectedSubtitleInfo willSet covers the subtitle-change side); toggling OFF clears it.
    // Configuration(source: subtitle language, target: Locale.current.language) — byte-confirmed via the
    // FUN_101aaf314 init call (x0=source=subtitle-lang buffer, x1=target=current-lang @0x101aafc14/c18) + the
    // committed `conf.source = response.sourceLanguage` consistency (subtitle(currentTime:)).
    public var translation: Bool = false {
        didSet {
            guard oldValue != translation else { return }
            #if canImport(Translation) && !os(tvOS) && !os(watchOS)
            if #available(iOS 18, macOS 15, *) {
                if translation {
                    guard _translationSessionConf as? TranslationSession.Configuration == nil else { return }
                    let source = selectedSubtitleInfo?.subtitleLanguage
                    let target = Locale.current.language
                    guard source != target else { return }
                    updateTranslationSessionConfiguration(.init(source: source, target: target))
                } else {
                    updateTranslationSessionConfiguration(nil)
                }
            }
            #endif
        }
    }
    private var _translationSessionConf: Any?
    private var _translationSession: AnyObject?
    #if canImport(Translation) && !os(tvOS) && !os(watchOS)
    // Descriptor group g4 = slots 12/13/14 (getter 0x101ab05e8 · setter 0x101ab0634 · modify 0x101ab0688) —
    // the TYPED view over the `_translationSession` box, sitting between that box (g3, slots 9/10/11) and
    // `subtitleDataSources` (g5): exactly the `_x`-box + typed-accessor idiom §7.3 already records for the
    // two `_`-backings. 43 of the 112 method descriptors carry Impl rel==0 — a genuine NULL, so the link
    // step eliminated the never-virtually-dispatched accessors; g3/g5 are among them, which is why the two
    // boxes contribute no bodies while their typed views (g2/g4) do.
    // Getter = `_translationSession as? TranslationSession`: self+0x38 loaded, then `swift_dynamicCastClass`
    // against the metadata from 0x103452cec, whose GOT slot 0x104110ff0 binds (dyld_info -fixups) to
    // `Translation/_$s11Translation0A7SessionCMa` = Translation.TranslationSession. The cast is CONDITIONAL
    // (dynamicCastClass + null-test → nil, not …Unconditional), hence `as?` not `as!`.
    // The modify @0x101ab0688 is the synthesized computed-property coroutine (getter inlined into a temp,
    // yield, continuation 0x101ab06f4 writes back) — no source, see the collapse note above.
    // ⚑ P28: the property's own name is stripped (recover_swift_function_name 0x101ab05e8 → no #function,
    //   no labels) → recon-named for the type it yields.
    @available(iOS 18, macOS 15, *)
    public var translationSession: TranslationSession? {
        get { _translationSession as? TranslationSession }
        set {
            _translationSession = newValue
            // 0x101ab0634: after the store, `cbz` @0x101ab065c → `bl 0x101ab68d8` @0x101ab0660. A non-nil
            // session invalidates the in-flight query (generation/sequence bump + query-time/parts reset) so
            // the next tick re-queries and translates.
            if newValue != nil {
                // ⚑[tool=export_trie_oracle ref=SubtitleModel.invalidateParts:0x101ab68d8 result=OWNER_MATCH] `bl 0x101ab68d8` @0x101ab0660 (re-read this session) calls slot 105 = `(invalidateParts in _912797…)()` DIRECTLY and materialises no arguments. The old pin here spelled this `searchSubtitle(query: nil, languages: [])` on the theory that the callee ignored two arguments; the trie shows the callee is zero-arg and the two-argument reading was the conflation this package removes.
                // ⚑[tool=disassemble ref=SubtitleModel.translationSession.setter:0x101ab0660 result=thunk-elision-undecidable] the residual: `cleanParts()` would inline its own one-instruction `b 0x101ab68d8` body and emit this identical `bl`. `invalidateParts()` is the direct target and is in-class, so it is the minimal claim.
                invalidateParts()
            }
        }
    }
    #endif
    private var subtitleDataSources: [any SubtitleDataSource] = KSOptions.subtitleDataSources
    @Published public private(set) var subtitleInfos: [any SubtitleInfo] = []
    @Published public private(set) var searchedSubtitleInfos: [URLSubtitleInfo] = []
    // slots 30/31/32 (keypaths d1e8/d210) + the `$parts` projection 33/34/35 — all Combine machinery.
    @Published public private(set) var parts: [SubtitlePart] = []
    public var subtitleDelay: Double = 0.0 // s — slots 36/37/38, offset var 0x104c637c8, getter returns d0
    public var dynamicRange: DynamicRange = .sdr // ⚑ default inferred → M2; slots 39/40/41, 0x104c637d0, getter ldrb
    public var options: KSOptions // slots 42/43/44, offset var 0x104c637d8, getter `ldr x0` + swift_retain
    @Published public var flag: Int = 0 // slots 45/46/47 (keypaths d240/d268)
    @Published public var subtitleTranslateY: Float = 0
    public var playRatio: Double = 1
    @Published public var screenSize: CGSize = .zero
    // UInt64, not Int. The earlier `Int store-evidenced` note came from a 64-bit STORE, which
    // cannot distinguish signedness; the field record's type mangle can, and reads UInt64.
    private var subtitleSearchGeneration: UInt64 = 0
    private var subtitleSearchSequence: UInt64 = 0
    private var latestPrimarySubtitleQueryTime: Double?
    private var latestSecondarySubtitleQueryTime: Double?
    // NON-OPTIONAL in the binary — the field mangle carries no `Sg`, as this line already noted.
    // Written as the sanctioned IUO stand-in rather than a bare `URL`, because the search didSet
    // still assigns nil and the construction that would make it non-optional is M2.
    public var url: URL!
    private var firstSubtitleActor: SubtitleActor?
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
                select(subtitleInfo: info)              // shared with secondary  ⚑[tool=resolve_fun_pins ref=FUN_101ab8250:0x101ab8250 result=RESOLVES_UNIQUELY] = KSPlayer.SubtitleModel.(select in _912797C474A4D482F764324552AD86D2)(subtitleInfo: KSPlayer.SubtitleInfo) -> ()
                #if canImport(Translation) && !os(tvOS) && !os(watchOS)
                // FUN_101ab2540 translation branch: build a Configuration from the new subtitle's language and the
                // current locale, skipping when they already match (nothing to translate).
                if translation, #available(iOS 18, macOS 15, *) {
                    let source = info.subtitleLanguage
                    let target = Locale.current.language
                    if source != target {
                        updateTranslationSessionConfiguration(.init(source: source, target: target))
                    }
                }
                #endif
            } else {
                #if canImport(Translation) && !os(tvOS) && !os(watchOS)
                if #available(iOS 18, macOS 15, *) {
                    updateTranslationSessionConfiguration(nil)   // FUN_101ab2540 nil path
                }
                #endif
                firstSubtitleActor = nil
            }
        }
    }
    private var secondarySubtitleActor: SubtitleActor?
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
                select(subtitleInfo: info)
            } else {
                secondarySubtitleActor = nil
            }
        }
    }
    private var searchInfos: [URLSubtitleInfo] = []
    // ⚑ init shape inferred → M2 witness-verify
    public init(options: KSOptions) {
        self.options = options
    }

    // ⚑ UNRESOLVED → P4 M2: recon `init()` — the binary added `options`; consumers still construct SubtitleModel().
    //   Convenience default kept as the consumer-ripple bridge; M2 verifies the real init / options wiring.
    public convenience init() { self.init(options: KSOptions()) }

    // Two vtable slots, not one: binary slot 95 @0x101ab3a34 is `mov w2,#0x1 ; b 0x101ab3a3c`
    // and slot 96 @0x101ab3a3c is the real body. Both carry their own MethodDescriptor
    // (records 0x1039f2030 / 0x1039f2038, whose Impl fields sit at +4 = 0x1039f2034 / 0x1039f203c —
    // re-read raw this session) and their own metadata vtable word (0x1044ef358 / 0x1044ef360).
    //
    // This was previously spelled as ONE method with `reselect: Bool = true`. That spelling is
    // WRONG and cannot produce the binary: a Swift default argument emits ONE vtable entry plus a
    // separate default-argument *generator* that is not in the vtable, so it yields 111 slots where
    // the binary has 112. PROVEN by compiling both spellings (session 58):
    //
    //   one decl + default arg  -> sil_vtable has a single `addSubtitle(info:rebindSelection:)` entry
    //   two overloads           -> sil_vtable has BOTH, adjacent, 1-arg FIRST (declaration order)
    //
    // and the 1-arg overload's codegen on a devirtualizable self-call is exactly
    //   `mov w2, #1 ; b <addSubtitle(info:rebindSelection:)>`
    // i.e. instruction-for-instruction the binary's slot 95. So the source is an overload PAIR.
    // Slot 95's trie name carries NO private discriminator, so this 1-arg overload is not private.
    // Trie: `KSPlayer.SubtitleModel.addSubtitle(dataSource: KSPlayer.SubtitleDataSource) -> ()`,
    // WITH a method descriptor. KSPlayerLayer.changeLoadState calls this; my first pass reached
    // into `subtitleDataSources` directly and widened it, which compiled and matched by type but
    // was not the member the binary names.
    public func addSubtitle(dataSource: any SubtitleDataSource) {
        subtitleDataSources.append(dataSource)
    }

    public func addSubtitle(info: any SubtitleInfo) {
        addSubtitle(info: info, rebindSelection: true)
    }

    // @0x101ab3a3c (slot 96 — the real body; slot 95 above forwards with rebindSelection=true).
    // Dedupe-by-subtitleID with REPLACE (base cce7002 only SKIPPED-if-present — the Forward
    // divergence). `rebindSelection` gates the re-point of selected/secondary to the new instance
    // (@0x101ab3d64, single-call-site helper inlined).
    // Session 74: the P28 "`reselect` param name unrecoverable" pin is RETIRED, and the access narrowed —
    // the trie resolves this address to `(addSubtitle in _912797…)(info:rebindSelection:)`, i.e. the second
    // label is `rebindSelection` and the method is PRIVATE. Both call sites are in this file (the 1-arg
    // overload above and select(subtitleInfo:) below), so the narrowing is closed.  ⚑[tool=export_trie_oracle ref=SubtitleModel.addSubtitle:0x101ab3a3c result=OWNER_MATCH] = KSPlayer.SubtitleModel.(addSubtitle in _912797C474A4D482F764324552AD86D2)(info: KSPlayer.SubtitleInfo, rebindSelection: Swift.Bool) -> ()
    private func addSubtitle(info: any SubtitleInfo, rebindSelection: Bool) {
        if let index = subtitleInfos.firstIndex(where: { $0.subtitleID == info.subtitleID }) {
            subtitleInfos[index] = info
        } else {
            subtitleInfos.append(info)
        }
        if rebindSelection {
            if let sel = selectedSubtitleInfo, sel.subtitleID == info.subtitleID, sel !== info {
                selectedSubtitleInfo = info
            }
            if let sec = secondarySubtitleInfo, sec.subtitleID == info.subtitleID, sec !== info {
                secondarySubtitleInfo = info
            }
        }
    }

    // Slot 111 @0x101ab8250 — shared helper invoked by BOTH select willSets on the newly-selected info (2 call sites).  ⚑[tool=resolve_fun_pins ref=FUN_101ab8250:0x101ab8250 result=RESOLVES_UNIQUELY] = KSPlayer.SubtitleModel.(select in _912797C474A4D482F764324552AD86D2)(subtitleInfo: KSPlayer.SubtitleInfo) -> ()
    // Activates it, registers it (addSubtitle rebindSelection:false to avoid re-select recursion), and caches a
    // remote / iCloud-ubiquitous download via a CacheSubtitleDataSource. Session 74: the P28 "method name
    // unrecoverable" pin that stood here is RETIRED — the trie resolves this address uniquely to
    // `select(subtitleInfo:)`, private (discriminator _912797…), which the marker above already recorded.
    // Forward divergence (P59): base cached only `!isFileURL`; Forward also caches (isFileURL && isUbiquitousItem).
    private func select(subtitleInfo: any SubtitleInfo) {
        subtitleInfo.isEnabled = true
        addSubtitle(info: subtitleInfo, rebindSelection: false)
        if let info = subtitleInfo as? URLSubtitleInfo {
            if info.downloadURL.isFileURL,
               (try? info.downloadURL.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem != true {
                return
            }
            if let url, let cache = subtitleDataSources.first(where: { $0 is CacheSubtitleDataSource }) as? CacheSubtitleDataSource {
                cache.addCache(fileURL: url, downloadURL: info.downloadURL)
            }
        }
    }

    #if canImport(Translation) && !os(tvOS) && !os(watchOS)
    // FUN_101aaffa0 — store the new Configuration into `_translationSessionConf` (self+0x18), then drop the live  ⚑[tool=resolve_fun_pins ref=FUN_101aaffa0:0x101aaffa0 result=RESOLVES_UNIQUELY] = KSPlayer.SubtitleModel.translationSessionConf.setter : Translation.TranslationSession.Configuration?
    // `_translationSession` (self+0x38) when the new config is nil/empty (forcing a rebuild). The binary reads NO
    // prior value: the clear fires on a value-witness `==` of the new config against an empty one, NOT new-vs-old.
    // ⚑ exact `==` spelling M2-verify (reconstructed to the proven behavior: clear-when-nil).
    @available(iOS 18, macOS 15, *)
    private func updateTranslationSessionConfiguration(_ configuration: TranslationSession.Configuration?) {
        _translationSessionConf = configuration
        if configuration == nil {
            _translationSession = nil
        }
    }
    #endif

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
            // (self._translationSessionConf, self+0x18, via a _modify coroutine FUN_101ab03c8; get/set_source  ⚑[tool=resolve_fun_pins ref=FUN_101ab03c8:0x101ab03c8 result=RESOLVES_UNIQUELY] = KSPlayer.SubtitleModel.translationSessionConf.modify : Translation.TranslationSession.Configuration?
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
            let translatedPart = SubtitlePart(first.start, first.end, render: .right(newTextInfo))
            // 5aa8: RE-RUN the resume tail after the translate await, then publish the fresh 1-element array
            // (0x101ab6360 re-guard → 0x63cc _set_subscript).
            publishIfCurrent([translatedPart], generation: generation, sequence: sequence)
            return
        }
        #endif

        parts = newParts     // publish — set_subscript on keypaths d1e8/d210 → @Published `parts` (5430@0x58c0)
    }

    // Slot 99 @0x101ab68d4 — a 4-byte, ONE-instruction body: `b 0x101ab68d8`, i.e. a tail call into
    // invalidateParts() below. Its trie name carries NO private discriminator, so it is not private.
    // Declaration position is FORCED by the vtable, not chosen: slot 99 sits between subtitle(currentTime:)
    // (slot 98) and the five dead-stripped Method slots 100–104, so it must be declared here.
    // ⚑[tool=export_trie_oracle ref=SubtitleModel.cleanParts:0x101ab68d4 result=access-undecidable] not-private is proven by the absent discriminator and at-least-internal by the cross-type caller inside KSPlayerLayer.seek @0x1019cd1f0; internal vs public is not decidable for a method, and MethodDescriptor.Impl reads nothing on this non-final class (reconstruction/impl_oracle_refuted_s74.json). `public` follows the file's existing convention.
    public func cleanParts() {
        invalidateParts()
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

    // query.size (438c/4c54 @0x469c): integer-truncated aspect fit of screenSize to playRatio (FUN_1019e7800 —  ⚑[tool=resolve_fun_pins ref=FUN_1019e7800:0x1019e7800 result=RESOLVES_UNIQUELY] = (extension in KSPlayer):__C.CGSize.within(ratio: Swift.Double) -> __C.CGSize
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
    // generation/sequence carry SubtitleModel's field type, which the field records give as UInt64.
    private func stillCurrent(_ items: [SubtitlePart], generation: UInt64, sequence: UInt64) -> Bool {
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
    // generation/sequence carry SubtitleModel's field type, which the field records give as UInt64.
    private func publishIfCurrent(_ items: [SubtitlePart], generation: UInt64, sequence: UInt64) {
        if stillCurrent(items, generation: generation, sequence: sequence) { parts = items }
    }

    // Slot 105 @0x101ab68d8 — NOT the base network datasource search (later·115 mis-ID, corrected session 22): a  ⚑[tool=resolve_fun_pins ref=FUN_101ab68d8:0x101ab68d8 result=RESOLVES_UNIQUELY] = KSPlayer.SubtitleModel.(invalidateParts in _912797C474A4D482F764324552AD86D2)() -> ()
    // generation-invalidation + actor-reset trigger. Bumps the model generation/sequence, resets both
    // query-times + `parts`, then resets both actors (0x101ab6acc→6b5c/6bc4/6c2c chain). Session 74: this
    // body had been declared as `searchSubtitle(query:languages:)` with both args ignored — a CONFLATION.
    // The trie names it `invalidateParts()`, zero-arg and PRIVATE (discriminator _912797…); the real
    // searchSubtitle is a distinct 2312-byte body at slot 109, written out below.
    // NOT private: KSPlayerLayer.seek calls this immediately before the player seek, so the
    // binary reaches it across a class boundary.
    func invalidateParts() {
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

    // Slot 109 @0x101ab6c88, extent 0x101ab6c88..0x101ab7590 (2312 B / 578 instr, LC_FUNCTION_STARTS, no
    // interior function start). Normal frame (stp x28,x27,[sp,#-0x60]!) and a plain `ret` @0x101ab7558 —
    // NOT async; the mangling ends in a plain `F` (no `K`, no `Ya`). x0/x1 = query String, x2 = languages,
    // x20 = self.  ⚑[tool=export_trie_oracle ref=SubtitleModel.searchSubtitle:0x101ab6c88 result=OWNER_MATCH] = KSPlayer.SubtitleModel.searchSubtitle(query: Swift.String, languages: [Swift.String]) -> ()
    //
    // Four limbs, in binary order:
    //  1. 0x101ab6d28–0x101ab7150 — Published modify on `subtitleInfos` (keypaths 0x10356d140/0x10356d168,
    //     outer stride 16 = [any SubtitleInfo]), each element scanned against the stride-8 `searchInfos`
    //     array. The predicate is a BARE pointer compare (`cmp x19,x22` @0x101ab6e4c, `cmp x19,x21`
    //     @0x101ab6fe4) with NO `==` witness call anywhere in the loop, hence `===` and not SubtitleInfo.==.
    //     Survivors are compacted back into the SAME buffer behind isUniquelyReferenced+COW, i.e.
    //     `removeAll(where:)`, not `filter`.
    //  2. 0x101ab7158–0x101ab7188 — `searchInfos = []`: beginAccess(MODIFY, w2=1), old value loaded, the
    //     empty-array singleton stored, bridgeObjectRelease. Proven to run AFTER limb 1, not before.
    //  3. 0x101ab718c–0x101ab7280 — `subtitleDataSources` (static self+0x40) filtered by
    //     swift_conformsToProtocol against descriptor 0x1039f1af4, whose name field reads
    //     'SearchSubtitleDataSource'. The (instance, witness) PAIR is stored, so the element type is
    //     `any SearchSubtitleDataSource` — `compactMap { $0 as? … }`, not `filter { $0 is … }`.
    //  4. 0x101ab7284–0x101ab752c — one `Task` per datasource. Flags 0x1c00 (@0x101ab7478/0x101ab7498),
    //     identical to the outlined Task.init helper at 0x101a03fd4, so `Task {}` and not `Task.detached`;
    //     futureResultType Void; priority Optional<TaskPriority> = .none. The await continuation splits on
    //     a non-nil x20 (@0x101ab7654), i.e. the awaited requirement THROWS → `try await`. On success the
    //     three appends land in this order: subtitleInfos (upcast via witness table 0x1041da4f8 =
    //     URLSubtitleInfo : SubtitleInfo), searchInfos (raw), searchedSubtitleInfos (raw).
    // The error arm @0x101ab7888 gates on KSOptions.logLevel and calls KSLog at level index 2 (.error);
    // its literals read #file 'KSPlayer/SubtitleModel.swift', #function 'searchSubtitle(query:languages:)',
    // #line 343 (`mov w6,#0x157` @0x101ab79b8).
    //
    // ⚑[tool=export_trie_oracle ref=SubtitleModel.searchSubtitle:0x101ab6c88 result=access-undecidable] public vs internal is not provable for a METHOD: only vpMV/vpZMV prove public and those are property markers, and MethodDescriptor.Impl reads nothing here because SubtitleModel is a non-final class (see reconstruction/impl_oracle_refuted_s74.json). `public` is the pre-existing spelling and the sole call site is cross-module.
    // ⚑[tool=disassemble ref=SubtitleModel.searchSubtitle:0x101ab73b4 result=isolation-site-undecidable] MainActor.shared is materialised AT this Task, and SubtitleModel is proven NOT type-level @MainActor by invalidateParts' nil actor slot (`stp xzr,xzr,[x0,#0x10]` @0x101ab6a00). But `Task { @MainActor in }` and `@MainActor func searchSubtitle` are byte-identical here; the closure spelling is the minimal claim.
    // ⚑[tool=disassemble ref=SubtitleModel.searchSubtitle:0x101ab73a4 result=P62-launder-undecidable] self is captured by a bare swift_retain; the `nonisolated(unsafe)` launders emit the same code and are present only for the KSPlayer target's Swift 6 strict concurrency (Package.swift gives .swiftLanguageMode(.v5) to ProAVPlayer only).
    // ⚑[tool=export_trie_oracle ref=AssrtSubtitleDataSource.searchSubtitle:0x101aa6c50 result=query-non-optional] SubtitleDataSource.swift:113 declares the awaited requirement `query: String?` while every conformer demangles `query: Swift.String`. Build-neutral here (implicit optional promotion, and String? is bit-identical to String at the ABI); deferred to its own package.
    // ⚑[tool=recover_swift_function_name ref=SubtitleModel.searchSubtitle:0x101ab6c88 result=KSPlayer/SubtitleModel.swift] the #file literal names SubtitleModel.swift while this class lives in KSSubtitle.swift. Deferred to the file-topology package.
    public func searchSubtitle(query: String, languages: [String]) {
        subtitleInfos.removeAll { info in searchInfos.contains { $0 === info } }
        searchInfos = []
        nonisolated(unsafe) let strongSelf = self
        for dataSource in subtitleDataSources.compactMap({ $0 as? SearchSubtitleDataSource }) {
            nonisolated(unsafe) let source = dataSource
            Task { @MainActor in
                do {
                    let infos = try await Self.delegateSearch(source, query: query, languages: languages)
                    strongSelf.subtitleInfos.append(contentsOf: infos)
                    strongSelf.searchInfos.append(contentsOf: infos)
                    strongSelf.searchedSubtitleInfos.append(contentsOf: infos)
                } catch {
                    KSLog(error)
                }
            }
        }
    }

    // Concurrency plumbing (§1 — recon-chosen, binary-invisible; NOT a distinct binary function), the same
    // `sending` hop SubtitleActor.delegateSearch already uses for the identical shape: the datasource is a
    // non-Sendable existential and the requirement is nonisolated async, so awaiting it from the MainActor
    // Task sends the receiver out of the MainActor region. `nonisolated(unsafe)` does NOT suppress that —
    // it governs isolation checking, not region-based send analysis — so the value is transferred through a
    // `sending` parameter instead. `private static` ⇒ final ⇒ no vtable slot, so slot order is untouched.
    private static func delegateSearch(_ dataSource: sending any SearchSubtitleDataSource,
                                       query: String,
                                       languages: [String]) async throws -> sending [URLSubtitleInfo]
    {
        try await dataSource.searchSubtitle(query: query, languages: languages)
    }
}
