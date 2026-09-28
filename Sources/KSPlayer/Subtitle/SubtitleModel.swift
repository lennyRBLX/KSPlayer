import CoreFoundation
import CoreGraphics
import Foundation
import SwiftUI
#if canImport(Translation) && !os(tvOS) && !os(watchOS)
import Translation
#endif

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
                    translationSessionConf = .init(source: source, target: target)
                } else {
                    translationSessionConf = nil
                }
            }
            #endif
        }
    }
    private var _translationSessionConf: Any?
    #if canImport(Translation) && !os(tvOS) && !os(watchOS)
    // Forward vtable slots 6/7/8: this typed view sits between its `_translationSessionConf` box (3/4/5)
    // and `_translationSession` (9/10/11) — declaration order, not the old end-of-body spot.
    // ⚑[tool=vtable_surface ref=SubtitleModel#6 result=var-translationSessionConf-GSM]
    // FUN_101aaffa0 — store the new Configuration into `_translationSessionConf` (self+0x18), then drop the live  ⚑[tool=resolve_fun_pins ref=FUN_101aaffa0:0x101aaffa0 result=RESOLVES_UNIQUELY] = KSPlayer.SubtitleModel.translationSessionConf.setter : Translation.TranslationSession.Configuration?
    // `_translationSession` (self+0x38) when the new config is nil/empty (forcing a rebuild). The binary reads NO
    // prior value: the clear fires on a value-witness `==` of the new config against an empty one, NOT new-vs-old.
    // ⚑ exact `==` spelling M2-verify (reconstructed to the proven behavior: clear-when-nil).
    /// ⚑[tool=export_trie_oracle ref=SubtitleModel.translationSessionConf.getter:0x101aafec0 result=56-instr]
    /// The binary carries this as a COMPUTED PROPERTY — getter @0x101aafec0, setter @0x101aaffa0,
    /// modify, and a `vpMV` — not as a named method. This reconstruction previously spelled the
    /// setter as `private func updateTranslationSessionConfiguration(_:)`, which has no symbol in
    /// the trie; its four call sites are property assignments in the original and are rewritten
    /// as such.
    ///
    /// Getter, read: `swift_beginAccess` on `self+0x18` (`_translationSessionConf`), an outlined
    /// copy of the `Any?` to a stack slot, `cbz` on the type word for the nil arm, then a
    /// `TranslationSession.Configuration` metadata fetch and a dynamic cast with **flags 6**
    /// (conditional + take) — i.e. `as?`, not `as!`. That matches this file's own line 358, which
    /// already spells the same cast.
    ///
    /// Setter: unchanged behaviour, and the prior note stands — the binary reads NO prior value;
    /// the `_translationSession` clear fires on the NEW config being nil, not on new-vs-old.
    /// `public` is PROVEN by the `vpMV` above, not chosen — pin_sweep's ACCESS check flags an
    /// internal spelling here immediately.
    @available(iOS 18, macOS 15, *)
    public var translationSessionConf: TranslationSession.Configuration? {
        get {
            _translationSessionConf as? TranslationSession.Configuration
        }
        set {
            _translationSessionConf = newValue
            if newValue == nil {
                _translationSession = nil
            }
        }
    }
    #endif
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
    private var subtitleDataSources: [any SubtitleDataSource] = []
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
    // NON-OPTIONAL in the binary — the field mangle carries no `Sg`. Set by init(url:options:)
    // @0x101ab34a0, the only designated initialiser Forward carries.
    // ⚑[tool=field_surface ref=SubtitleModel.url result=forward Foundation.URL (not URL?/URL!)]
    public var url: URL
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
                        translationSessionConf = .init(source: source, target: target)
                    }
                }
                #endif
            } else {
                #if canImport(Translation) && !os(tvOS) && !os(watchOS)
                if #available(iOS 18, macOS 15, *) {
                    translationSessionConf = nil   // FUN_101ab2540 nil path
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

    // query.size (438c/4c54 @0x469c): integer-truncated aspect fit of screenSize to playRatio (FUN_1019e7800 —  ⚑[tool=resolve_fun_pins ref=FUN_1019e7800:0x1019e7800 result=RESOLVES_UNIQUELY] = (extension in KSPlayer):__C.CGSize.within(ratio: Swift.Double) -> __C.CGSize
    // letterbox when playRatio ≤ height/width, else pillarbox). ⚑ gated in-binary by an `actor.info` Bool witness
    // (info wtable+0x50) whose identity is UNVERIFIED, so the size-fit region of 438c/4c54 is a known divergence
    // pending that decode; represented unconditionally here.
    /// ⚑[tool=export_trie_oracle ref=SubtitleModel.playSize.getter:0x101ab33fc result=41-instr]
    /// ⚑ RENAMED from `private func playSize`, which has ZERO symbols in the trie —
    /// an invented name. The binary carries `SubtitleModel.playSize : __C.CGSize` as a computed
    /// property with a `vpMV` (public), and its getter is only 41 instructions because it
    /// DELEGATES: it reads `screenSize` through the `@Published` enclosing-instance keypath
    /// subscript (two `swift_getKeyPath` + `Published._enclosingInstance` getter), loads
    /// `playRatio` from its own `vpWvd` (offset global 0x104c637e0), and tail-calls
    /// `0x1019e7800` = `(extension in KSPlayer):__C.CGSize.within(ratio:)`.
    /// ⚑[tool=export_trie_oracle ref=SubtitleModel.playRatio:0x104c637e0 result=vpWvd-named]
    /// ⚑[tool=export_trie_oracle ref=CGSize.within(ratio:):0x1019e7800 result=85-instr]
    public var playSize: CGSize {
        screenSize.within(ratio: playRatio)
    }

    // Forward: init(url:options:) @0x101ab34a0 (allocating 0x101aaf2c8) — no init(options:).
    // ⚑[tool=export_trie_oracle ref=SubtitleModel.init(url:options:):0x101ab34a0 result=OWNER_MATCH]
    public init(url: URL, options: KSOptions) {
        self.options = options
        self.url = url
        for dataSource in KSOptions.subtitleDataSources {
            addSubtitle(dataSource: dataSource)
        }
    }

    public func addSubtitle(info: any SubtitleInfo) {
        addSubtitle(info: info, rebindSelection: true)
    }

    // @0x101ab3a3c (slot 96 — the real body; slot 95 above forwards with rebindSelection=true).
    // Dedupe-by-subtitleID with REPLACE (base cce7002 only SKIPPED-if-present — the Forward
    // divergence). `rebindSelection` gates the re-point of selected/secondary to the new instance
    // (@0x101ab3d64 rebindSelectionIfNeeded(to:), a real vtable slot 97 — called @0x101ab3cdc, not inlined).
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
            rebindSelectionIfNeeded(to: info)
        }
    }

    // slot 97 @0x101ab3d64 (private) — sole call site addSubtitle(info:rebindSelection:) @0x101ab3cdc.
    private func rebindSelectionIfNeeded(to info: any SubtitleInfo) {
        if selectedSubtitleInfo?.subtitleID == info.subtitleID,
           selectedSubtitleInfo !== info {
            selectedSubtitleInfo = info
        }
        if secondarySubtitleInfo?.subtitleID == info.subtitleID,
           secondarySubtitleInfo !== info {
            secondarySubtitleInfo = info
        }
    }

    // FUN_101ab3fec (synchronous producer) prepares the actor snapshots, adjusted times and
    // invalidation tokens before creating the inherited task. The task merges both actor results,
    // validates the current query windows, and publishes through the existing guarded path.
    public func subtitle(currentTime: TimeInterval, playRatio: Double, screenSize: CGSize) {
        guard currentTime.isFinite else { return }
        self.playRatio = playRatio
        let currentScreenSize = self.screenSize
        if currentScreenSize.width != screenSize.width || currentScreenSize.height != screenSize.height {
            self.screenSize = screenSize
        }

        let firstActor = firstSubtitleActor
        let secondaryActor = secondarySubtitleActor
        let primaryTime: Double?
        if let firstActor {
            primaryTime = currentTime - firstActor.info.delay - subtitleDelay
        } else {
            primaryTime = nil
        }
        let secondaryTime: Double?
        if let secondaryActor {
            secondaryTime = currentTime - secondaryActor.info.delay - subtitleDelay
        } else {
            secondaryTime = nil
        }
        let generation = subtitleSearchGeneration
        let sequence = subtitleSearchSequence &+ 1
        subtitleSearchSequence = sequence
        latestPrimarySubtitleQueryTime = primaryTime
        latestSecondarySubtitleQueryTime = secondaryTime
        let capturedPlayRatio = playRatio
        let capturedScreenSize = screenSize
        nonisolated(unsafe) let strongSelf = self
        Task {
            var newParts = [SubtitlePart]()

            if let firstActor, let primaryTime {
                var size = capturedScreenSize
                if !firstActor.info.isSrt || (capturedPlayRatio > 1) != (capturedScreenSize.height < capturedScreenSize.width) {
                    size = capturedScreenSize.within(ratio: capturedPlayRatio)
                } else {
                    let aspect = capturedScreenSize.width == 0 || capturedScreenSize.height == 0
                        ? 16.0 / 9.0
                        : capturedScreenSize.width / capturedScreenSize.height
                    if capturedPlayRatio < aspect {
                        size = capturedScreenSize.within(ratio: capturedPlayRatio)
                    }
                }
                let query = KSSubtitleQuery(time: primaryTime, size: size,
                                            verticalAlign: nil, textPosition: nil, textRole: .primary)
                newParts += await firstActor.search(with: query, generation: sequence)
            }

            if let secondaryActor, let secondaryTime {
                var size = capturedScreenSize
                if !secondaryActor.info.isSrt || (capturedPlayRatio > 1) != (capturedScreenSize.height < capturedScreenSize.width) {
                    size = capturedScreenSize.within(ratio: capturedPlayRatio)
                } else {
                    let aspect = capturedScreenSize.width == 0 || capturedScreenSize.height == 0
                        ? 16.0 / 9.0
                        : capturedScreenSize.width / capturedScreenSize.height
                    if capturedPlayRatio < aspect {
                        size = capturedScreenSize.within(ratio: capturedPlayRatio)
                    }
                }
                let position = KSOptions.secondaryTextPosition
                let query = KSSubtitleQuery(time: secondaryTime, size: size,
                                            verticalAlign: position.verticalAlign,
                                            textPosition: position, textRole: .secondary)
                newParts += await secondaryActor.search(with: query, generation: sequence)
            }

            guard strongSelf.subtitleSearchGeneration == generation else { return }
            if sequence != strongSelf.subtitleSearchSequence {
                guard !newParts.isEmpty else { return }
                for part in newParts {
                    let role: SubtitleTextRole
                    switch part.render {
                    case let .left(image):
                        role = image.styleRole
                    case let .right(text):
                        if text.text.string.isEmpty { return }
                        role = text.styleRole
                    }
                    let queryTime = role == .secondary ? strongSelf.latestSecondarySubtitleQueryTime
                                                       : strongSelf.latestPrimarySubtitleQueryTime
                    guard let queryTime, part.start <= queryTime, queryTime < part.end else { return }
                }
            }
            guard newParts != strongSelf.parts else { return }

            #if canImport(Translation) && !os(tvOS) && !os(watchOS)
            if #available(iOS 18, macOS 15, *),
               let first = newParts.first,
               case let .right(textInfo) = first.render,
               let session = strongSelf._translationSession as? TranslationSession {
                guard let response = try? await session.translate(textInfo.text.string) else {
                    strongSelf.publishIfCurrent(newParts, generation: generation, sequence: sequence)
                    return
                }
                guard strongSelf.stillCurrent(newParts, generation: generation, sequence: sequence) else { return }
                if strongSelf.translationSessionConf?.source != response.sourceLanguage {
                    strongSelf.translationSessionConf?.source = response.sourceLanguage
                }
                let attributed = NSMutableAttributedString()
                if KSOptions.showTranslateSourceText {
                    attributed.append(textInfo.text)
                    attributed.append(NSAttributedString(string: "\n"))
                }
                let translated = response.targetText.replacingOccurrences(of: "\n\n", with: "\n")
                attributed.append(NSAttributedString(string: translated))
                // SubtitleTextInfo.text is `let` in Forward (field_surface), so the copy is rebuilt, not mutated.
                let newTextInfo = SubtitleTextInfo(text: attributed, position: textInfo.position, displaySize: textInfo.displaySize, styleRole: textInfo.styleRole, usesForcedPosition: textInfo.usesForcedPosition)
                let translatedPart = SubtitlePart(first.start, first.end, render: .right(newTextInfo))
                strongSelf.publishIfCurrent([translatedPart], generation: generation, sequence: sequence)
                return
            }
            #endif

            strongSelf.publishIfCurrent(newParts, generation: generation, sequence: sequence)
        }
    }

    // Slot 99 @0x101ab68d4 — a 4-byte, ONE-instruction body: `b 0x101ab68d8`, i.e. a tail call into
    // invalidateParts() below. Its trie name carries NO private discriminator, so it is not private.
    // Declaration position is FORCED by the vtable, not chosen: slot 99 sits between subtitle(currentTime:)
    // (slot 98) and the five dead-stripped Method slots 100–104, so it must be declared here.
    // ⚑[tool=export_trie_oracle ref=SubtitleModel.cleanParts:0x101ab68d4 result=access-undecidable] not-private is proven by the absent discriminator and at-least-internal by the cross-type caller inside KSPlayerLayer.seek @0x1019cd1f0; internal vs public is not decidable for a method, and MethodDescriptor.Impl reads nothing on this non-final class (reconstruction/impl_oracle_refuted_s74.json). `public` follows the file's existing convention.
    public func cleanParts() {
        invalidateParts()
    }

    // The resume-tail predicate: the generation snapshot still matches AND (when the sequence moved) every part is
    // still within its role's latest-query half-open [start,end) window. Re-run after the iOS-18 translate `await`
    // since generation/sequence may have changed during it. `@inline(__always)` to match the binary's
    // tail-inlined-into-every-funclet codegen (5aa8 entry @0x5aa8 over newParts / 5aa8 publish @0x6360 over the
    // translated part / 664c @0x674c over newParts).
    @inline(__always)
    // generation/sequence carry SubtitleModel's field type, which the field records give as UInt64.
    private final func stillCurrent(_ items: [SubtitlePart], generation: UInt64, sequence: UInt64) -> Bool {
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
    private final func publishIfCurrent(_ items: [SubtitlePart], generation: UInt64, sequence: UInt64) {
        if stillCurrent(items, generation: generation, sequence: sequence) { parts = items }
    }

    // Forward dead slots 100-104 (Impl 0) hold the five methods whose trie symbols all sit on the dead stub
    // 0x10198eb18; `stillCurrent`/`publishIfCurrent` have no Forward symbol (inlined), so they take no slot.
    // Order inside 100-104 is an inference: dead slots carry no name.
    // ⚑[tool=vtable_surface ref=KSPlayer.SubtitleModel#100-104 result=dead slots ↔ Forward-dead methods]
    private func nextSubtitleSearchSequence(primaryQueryTime: Double?, secondaryQueryTime: Double?) -> UInt64 { 0 }

    private func invalidateRenderedPartsForSelectionChange() {}

    private func invalidateSubtitleSearches() {}

    private func shouldApplySubtitleResult(searchGeneration: UInt64, searchSequence: UInt64, newParts: [SubtitlePart]) -> Bool { false }

    private func areSubtitlePartsStillCurrent(_ p0: [SubtitlePart]) -> Bool { false }

    // Slot 105 @0x101ab68d8 — NOT the base network datasource search (later·115 mis-ID, corrected session 22): a  ⚑[tool=resolve_fun_pins ref=FUN_101ab68d8:0x101ab68d8 result=RESOLVES_UNIQUELY] = KSPlayer.SubtitleModel.(invalidateParts in _912797C474A4D482F764324552AD86D2)() -> ()
    // generation-invalidation + actor-reset trigger. Bumps the model generation/sequence, resets both
    // query-times + `parts`, then resets both actors (0x101ab6acc→6b5c/6bc4/6c2c chain). Session 74: this
    // body had been declared as `searchSubtitle(query:languages:)` with both args ignored — a CONFLATION.
    // The trie names it `invalidateParts()`, zero-arg and PRIVATE (discriminator _912797…); the real
    // searchSubtitle is a distinct 2312-byte body at slot 109, written out below.
    // NOT private: KSPlayerLayer.seek calls this immediately before the player seek, so the
    // binary reaches it across a class boundary.
    func invalidateParts() {
        subtitleSearchGeneration &+= 1
        subtitleSearchSequence &+= 1
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
    private var searchInfos: [URLSubtitleInfo] = []

    // ⚑ pre-hop helpers (FUN_101ab9d00, one level ABOVE the 5 core funclets): the skip gates (char 0x92/0x93)
    //   and per-track adjusted query times (0x990/0x9c0) are computed before the executor hop and read by the
    //   core as spilled slots. Exact skip predicate + delay formula are UNVERIFIED (best-effort); the core's
    //   faithfulness is unaffected (it only reads the spilled results). Optional return models the skip gate.
    private final func primarySubtitleQueryTime(_ currentTime: TimeInterval) -> Double? {
        currentTime - (selectedSubtitleInfo?.delay ?? 0) - subtitleDelay
    }

    private final func secondarySubtitleQueryTime(_ currentTime: TimeInterval) -> Double? {
        currentTime - (secondarySubtitleInfo?.delay ?? 0) - subtitleDelay
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
                    let infos = try await SubtitleModel.delegateSearch(source, query: query, languages: languages)
                    strongSelf.subtitleInfos.append(contentsOf: infos)
                    strongSelf.searchInfos.append(contentsOf: infos)
                    strongSelf.searchedSubtitleInfos.append(contentsOf: infos)
                } catch {
                    KSLog(error)
                }
            }
        }
    }

    // ⚑ UNRESOLVED → P4 M2: recon `init()` has no Forward counterpart. Kept only as the bridge for
    //   PlayerView.srtControl (UIKit, out of scope) and KSVideoPlayer.Coordinator.subtitleModel
    //   (a field Forward does not have). The placeholder URL is not Forward's.
    public convenience init() { self.init(url: URL(string: "about:blank")!, options: KSOptions()) }

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
               (try? info.downloadURL.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) != true {
                return
            }
            if let cache = subtitleDataSources.first(where: { $0 is CacheSubtitleDataSource }) as? CacheSubtitleDataSource {
                cache.addCache(fileURL: url, downloadURL: info.downloadURL)
            }
        }
    }
}

//  Forward 1.3.17 — NEW per-track subtitle-holder actor (P4 M1 structure). §7.4. Bodies → P4 M2.
// SubtitleActor @0x1039f20b8 — `actor` ($defaultActor; type_kind_gate). Populated by the dual
// (primary/secondary) SubtitleModel search. Fields reflection-ordered; conforms KSSubtitleProtocol (§8.5).
public actor SubtitleActor: KSSubtitleProtocol {
    var parts: [SubtitlePart] = []
    nonisolated(unsafe) let info: any SubtitleInfo
    // UInt64. NOT read from this class's own field records — dump_binary_field_types reports
    // searchGeneration as `unmapped` here — but it is assigned to and from SubtitleModel's
    // subtitleSearchGeneration, which IS record-read as UInt64, so the pair must agree. The old
    // `Int store-evidenced` note rested on a 64-bit store, which cannot distinguish signedness.
    var searchGeneration: UInt64 = 0
    var latestQueryTime: Double?
    // init(info:) — witness-verified against the inlined construction at BOTH willSets (FUN_101ab2540
    // selectedSubtitleInfo @0x101ab2688 / FUN_101ab2de4 secondarySubtitleInfo): SubtitleActor metadata accessor
    // (0x101aba99c) -> swift_allocObject -> swift_defaultActor_initialize -> store `info` (existential @actor+0x70..0x80)
    // + field defaults (searchGeneration=0 @+0x88, latestQueryTime=nil @+0x90/98, parts=[]). FULLY INLINED — no
    // standalone init function (locate_class_init P43: "init None" is correct for this final actor's trivial init).
    // RE-VERIFIED session 63: SubtitleActor has ZERO owner-position symbols in the orphaned export trie —
    //   it appears only as the TYPE of SubtitleModel's private firstSubtitleActor/secondarySubtitleActor
    //   fields. The "no init symbol" negative is now VERIFIED, not merely unfalsified.
    // ⚑[tool=export_trie_oracle ref=SubtitleActor result=0 owner-position symbols — VERIFIED negative]
    // `info` is stored once and never reassigned. `nonisolated(unsafe)` enables the synchronous
    // size-fit reads in SubtitleModel.subtitle(currentTime:playRatio:screenSize:).
    init(info: any SubtitleInfo) {
        self.info = info
    }

    // FUN_101ab6b5c/6c2c — inlined into SubtitleModel.searchSubtitle's Task at its single call site
    // (`await firstSubtitleActor?.reset(); await secondarySubtitleActor?.reset()`). Invalidates this
    // actor's in-flight search state. ⚑ method name unrecoverable (P28), recon-chosen.
    func reset() {
        searchGeneration &+= 1
        latestQueryTime = nil
        parts = []
    }

    // KSSubtitleProtocol requirement — witness impl 0x101ab9a44 (WT 0x1041daad0, async-fp 0x10356d4a8).
    // MUST stay `nonisolated`: the requirement carries non-Sendable KSSubtitleQuery/[SubtitlePart], so an
    // actor-isolated witness can't satisfy it. The witness hops onto the actor (9a44 task_switch) into the
    // isolated worker, laundering the non-Sendable crossings via the base's `nonisolated(unsafe)` idiom (P62).
    public nonisolated func search(with query: KSSubtitleQuery) async -> [SubtitlePart] {
        nonisolated(unsafe) let query = query
        return await bumpAndSearch(with: query)
    }

    // 9a5c (isolated) — the on-actor realization of the req: bump the generation, delegate to the gen-search.
    // ⚑ recon-named (P28): the 9a44→9a5c hop implies this isolated worker; source name unrecoverable.
    @used private func bumpAndSearch(with query: KSSubtitleQuery) async -> sending [SubtitlePart] {
        // Forward reads and writes the actor's generation at +0x88 directly.
        let generationSlot = Unmanaged.passUnretained(self).toOpaque()
            .advanced(by: 0x88).assumingMemoryBound(to: UInt64.self)
        let generation = generationSlot.pointee &+ 1
        generationSlot.pointee = generation
        return await search(with: query, generation: generation)
    }

    // Internal generation-guarded search (0x101ab8864 → 8884 → 8938 → 898c; three call sites: bumpAndSearch
    // above + the two SubtitleModel drivers FUN_101ab438c/4c54). Reentrancy-safe across the `await info.search`:
    // a newer search that bumps searchGeneration during suspension makes this call stale, so it neither records
    // its query time (8884 guard) nor commits its results (898c gate @0x101ab9558).
    // generation/sequence carry SubtitleModel's field type, which the field records give as UInt64.
    func search(with query: KSSubtitleQuery, generation: UInt64) async -> sending [SubtitlePart] {
        // 8884 — adopt this generation + record the query time (skipped if a newer search already ran)
        if searchGeneration <= generation {
            searchGeneration = generation
            latestQueryTime = query.time
        }
        // 8884 delegate + 8938 receive — the datasource performs the actual (lazy, async) lookup.
        // Launder the non-Sendable info/query across info.search's nonisolated boundary (P62, base idiom;
        // §1 — the exact concurrency plumbing is recon-chosen/under-included, binary-invisible, not a logic claim).
        nonisolated(unsafe) let subtitleInfo = info
        nonisolated(unsafe) let searchQuery = query
        var result = await Self.delegateSearch(subtitleInfo, with: searchQuery)
        // 898c stage 1 — apply the query's text position to every TEXT part (image parts untouched;
        // query.size is NOT used). If the query carries a full textPosition, stamp it (B, 0x101ab8c1c);
        // else if it carries just a verticalAlign, override that on the part's existing position or the
        // SubtitleModel.textPosition default (A, 0x101ab89c8). render.position ← query+0x28.. / +0x18.
        if let textPosition = query.textPosition {
            for i in result.indices {
                if case .right(var text) = result[i].render {
                    text.position = textPosition
                    result[i].render = .right(text)
                }
            }
        } else if let verticalAlign = query.verticalAlign {
            for i in result.indices {
                if case .right(var text) = result[i].render {
                    var position = text.position ?? SubtitleModel.textPosition
                    position.verticalAlign = verticalAlign
                    text.position = position
                    result[i].render = .right(text)
                }
            }
        }
        // 898c stage 2 — a secondary track stamps its role onto every part (0x101ab8db4). render.styleRole
        // ← query.textRole (query+0x51); text @render+0x49, image @render+0x70.
        if query.textRole != .primary {
            for i in result.indices {
                switch result[i].render {
                case .right(var text):
                    text.styleRole = query.textRole
                    result[i].render = .right(text)
                case .left(var image):
                    image.styleRole = query.textRole
                    result[i].render = .left(image)
                }
            }
        }
        // 898c commit gate (0x101ab8ff0) — only the still-current search adopts results into `parts`.
        if generation == searchGeneration {
            if result.isEmpty {
                // no fresh parts — the display set is the existing parts active at query.time (0x101ab9380)
                result = parts.filter { $0.start <= query.time && query.time < $0.end }
            } else {
                // merge still-active existing parts not already present, dedup by (start,end) (0x101ab9284).
                // ⚑ the 898c non-empty pre-pass (0x101ab9024) builds a discarded scratch + short-circuits to
                //   commit when a result part has empty text.string — that edge case is not modeled here.
                for part in parts where part.start <= query.time && query.time < part.end && part.end != .infinity {
                    if !result.contains(where: { $0.start == part.start && $0.end == part.end }) {
                        result.append(part)
                    }
                }
            }
            parts = result
        } else {
            // 959c (FUN_101ab959c) — the reentrancy-stale path yields the parts at `latestQueryTime`, adopting
            // a non-empty fresh filter of `result` into `parts` as a side effect (this stale query's own
            // generation is never adopted). ⚑ inlined (an isolated helper can't `sending`-return actor parts).
            if let time = latestQueryTime {
                let filtered = result.filter { $0.start <= time && time < $0.end }
                if !filtered.isEmpty {
                    parts = filtered
                    result = filtered            // re-filtering by `time` is a no-op → return it whole
                } else {
                    result = parts.filter { $0.start <= time && time < $0.end }
                }
            } else {
                result = []
            }
        }
        // launder the actor-derived result across the `sending` return (§1 recon-chosen plumbing).
        nonisolated(unsafe) let out = result
        return out
    }

    // Concurrency plumbing (§1 — recon-chosen, binary-invisible; NOT a distinct binary function): the actor
    // delegates its non-Sendable `info`'s async `search` across the isolation boundary via a `sending` hop.
    private static func delegateSearch(_ info: sending any SubtitleInfo, with query: sending KSSubtitleQuery) async -> sending [SubtitlePart] {
        await info.search(with: query)
    }
}
