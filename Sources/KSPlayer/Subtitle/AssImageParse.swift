//
//  AssImageParse.swift
//  KSPlayer
//
//  Forward 1.3.17 — NEW ASS-image parser + the incremental image-renderer actor (P4 M1 structure). Bodies → P4 M2.
//
import libass
import SwiftUI
import CoreGraphics
import Foundation

// AssImageParse @0x1039f14f8 — stateless parser (:KSParseProtocol, §8.5).
// parsePart INHERITS the KSParseProtocol extension default `{ [] }` (witness 0x10002d9dc, shared with
// FFmpegSubtitleParse) — ASS-image is rendered via AssIncrementImageRenderer (Batch 5), not this text path.
public final class AssImageParse: KSParseProtocol {
    public init() {}

    // ⚑ s105: the binary declares this member ON THIS CLASS — the trie carries
    // `KSPlayer.AssImageParse.parsePart(scanner: __C.NSScanner) -> [KSPlayer.SubtitlePart]` directly, not as a
    // protocol-witness thunk, so it is an explicit declaration rather than the inheritance the
    // file header assumed. Body 0x10002d9dc is three instructions:
    //   adrp x0, 0x104112000 / ldr x0, [x0, #0xd00] / ret
    // and that GOT slot binds libswiftCore `__swiftEmptyArrayStorage`, i.e. it returns [].
    // ⚑[tool=bind_oracle ref=_swiftEmptyArrayStorage:0x104112d00 result=libswiftCore]
    // Identical to the KSParseProtocol extension default, which is why ICF folded the two onto
    // one address — the fold is the CONSEQUENCE of them matching, not evidence of inheritance.
    public func parsePart(scanner _: Scanner) -> [SubtitlePart] { [] }
    // ⚑ TERMINAL DEFERRAL → P4 M2 (existence-CHECKED session 19, RE-VERIFIED session 25 [2026-07-10] — the block
    //   HOLDS; name recovery EXHAUSTED — safe `false` fallback per the cardinal rule, NOT fabricated. Unblock needs a
    //   symbolicated/app-context build or upstream Forward source; NOT further binary analysis — do NOT re-open as
    //   pending work). RE-VERIFY (P43): recover_swift_function_name → all 4 helpers 'npl'(spurious #file:None); the
    //   3 flag accessors FUN_1019b982c/98fc/99cc + shared reader FUN_101b1d474 → #function None.  ⚑[tool=resolve_fun_pins ref=FUN_1019b982c:0x1019b982c result=RESOLVES_UNIQUELY] = static KSPlayer.KSOptions.isASSUseImageRender.getter : Swift.Bool
    //   ⚠️ THREE OF THE FOUR ARE NOW NAMED (session 63). `recover_swift_function_name` genuinely
    //   fails on them, but the ORPHANED export trie carries an ADDRESS->symbol map, and the flags
    //   are KSOptions statics, so the three accessors have real identities (each named in its own
    //   marker below; together they supersede the FAILED-SEARCH pin). The fourth helper does NOT
    //   resolve, which is now a VERIFIED negative rather than an unverified one.
    //   ⚠️ WHICH accessor backs WHICH of the `flag150/151/152` placeholders in the spine below is
    //   NOT established — the address list and the flag numbering appear in different orders and
    //   nothing here pairs them. Deciding it needs the call sites read at 0x101a96b98. The three
    //   names are evidence; the pairing would be a guess, so it is left open.
    // ⚑[tool=export_trie_oracle ref=KSOptions.isASSUseImageRender.getter:0x1019b982c result=NAMED (static, Bool)]
    // ⚑[tool=export_trie_oracle ref=KSOptions.isSRTUseImageRender.getter:0x1019b98fc result=NAMED (static, Bool)]
    // ⚑[tool=export_trie_oracle ref=KSOptions.preferEffectSubtitle.getter:0x1019b99cc result=NAMED (static, Bool)]
    // ⚑[tool=export_trie_oracle ref=AssImageParse.flagReaderHelper:0x101b1d474 result=absent from the export trie — VERIFIED negative, name unrecovered]
    //   canParse = FUN_101a96b98 (~298i, anchor-verified). Decoded spine:
    //     if flag151, scanner.string.contains(" --> ")  -> scanner.charactersToBeSkipped = nil; scanner.scanString("WEBVTT"); return true
    //     guard scanner.string.contains("Format: Name,") else { return false }
    //     if flag150 { return true };  guard flag152 else { return false }
    //     // deep ASS detection: helpers + a 10-regex ASS-override-tag complexity scan of the text before "[Events]"
    //   BLOCKER — the primitives are deterministically UN-NAMEABLE, so a faithful body cannot be written:
    //   * 3 gate flags @0x104c63150/151/152 = KSOptions PRIVATE static Bools (read by SubtitleDecode.init next to
    //     KSOptions.fontsDir) — no Ghidra symbol (KSOptions.fontsDir got one; these did NOT), absent from field
    //     reflection (statics), getters log no #function, ABSENT from base cce7002.
    //     ⚑[tool=recover_swift_function_name+get_xrefs_to ref=DAT_104c63150/151/152 result=FAILED-SEARCH]
    //   * 4 detection helpers FUN_101a8e3b8/8f72c/90748/910ac (~2500i; parse [Fonts]/Format:/Style:, ASS tags) —
    //     names unrecoverable (#function spurious). ⚑[tool=recover_swift_function_name ref=FUN_101a8e3b8 result=FAILED-SEARCH]
    //   * the 10-regex array lives in SubtitleDecode.swift (\p drawing, \c&H color, \kf karaoke, \an, \t, \r, alpha, \fscy/\fsp).
    //   Reconstructing functionally would FABRICATE 3 KSOptions API statics + 4 method names the binary can't confirm
    //   (§1/P28). Returning false keeps the safe fallback (text-path AssParse); the image-render CONSUMER
    //   (AssIncrementImageRenderer) is Batch 5 (deferred) so NO regression. Unblock: a symbolicated/app-context
    //   build or the upstream Forward source. Full decode -> ledger later.101 + subtitle spec 8.8.
    public func canParse(scanner: Scanner) -> Bool { false }
    // parse 0x101a8f5a8: Forward passes `scanner.string.contains(" --> ") ? <SRT→ASS converter 0x101aa0390>(…) : scanner.string`.
    //   The converter lives in KSParseProtocol.swift (closed lane 10, no Sources decl) → GAP review; until it exists
    //   the plain-content arm is the only one written.
    public func parse(url _: URL, scanner: Scanner) throws -> KSSubtitleProtocol {
        AssIncrementImageRenderer(content: scanner.string)
    }
}

// AssIncrementImageRenderer @0x1039f1534 — NEW `actor` ($defaultActor; type_kind_gate). Fields reflection-ordered
// (uuid/header/subtitles/fontsDir/renderer/basicFontSize), types §8.3/§8.6.
final actor AssIncrementImageRenderer: KSSubtitleProtocol { // §8.5-gap: KSSubtitleProtocol conformer (reverse-walk-confirmed)
    private let uuid: UUID = UUID()                                                  // ⚑ UUID inferred (GOT-indirect) → recon/mangle-evidenced
    private var header: String?
    // ⚑ s105 RETYPE: the tuple elements are Int64, not Double (l2 field record
    // `[(subtitle: String, start: Int64, duration: Int64)]`).
    private var subtitles: [(subtitle: String, start: Int64, duration: Int64)] = [] // §8.6
    // ⚑[tool=field_surface ref=AssIncrementImageRenderer.fontsDir:idx3 result=let String?] Set by init(fontsDir:header:) 0x101a92d2c.
    private let fontsDir: String?
    private var renderer: AssImageRenderer
    // L7 b4: no initializer expression — both Forward inits (0x101a92b90 / 0x101a92d2c) store
    //   Int(KSOptions.subtitleFontSize) and Forward emits no pfi for this field.
    private var basicFontSize: Int
    // L7 pilot c: the invented `init(renderer:)` (no callers) is removed — Forward's vtable holds two
    // init slots, init(content:) and init(fontsDir:header:).
    // flush 0x101a8f210: libass events are dropped only when the shared renderer is still ours.
    func flush() {
        if renderer.uuid == uuid {
            ass_flush_events(renderer.currentTrack)
        }
        subtitles = []
    }

    // add: AssImageRenderer has no Forward add body — the ass_process_chunk call is inlined at every site.
    func add(subtitle: String, start: Int64, duration: Int64) {
        if renderer.uuid == uuid {
            if var buffer = subtitle.cString(using: .utf8) {
                ass_process_chunk(renderer.currentTrack, &buffer, Int32(buffer.count), start, duration)
            }
        }
        subtitles.append((subtitle, start, duration))
    }

    // init(content:) 0x101a92b90
    init(content: String) {
        fontsDir = nil
        header = nil
        basicFontSize = Int(KSOptions.subtitleFontSize)
        renderer = AssImageRenderer(content: content, uuid: uuid)
    }

    // init(fontsDir:header:) 0x101a92d2c — Default style font size becomes the base, header rewritten via 0x101a960dc;
    //   the renderer comes from the shared fontsDir pool (0x101a9667c) or a private header track (0x101a94d08).
    init(fontsDir: String?, header: String) {
        self.fontsDir = fontsDir
        self.header = header
        basicFontSize = Int(KSOptions.subtitleFontSize)
        for line in header.components(separatedBy: "\n") {
            if line.hasPrefix("Style: Default") {
                let parts = line.components(separatedBy: ",")
                if parts.count > 2, let fontSize = Int(parts[2]), fontSize > 0 {
                    basicFontSize = fontSize
                    self.header = Self.rewriteHeader(basicFontSize: fontSize, header: header)
                }
                break
            }
        }
        if let fontsDir {
            renderer = AssImageRenderer.renderer(fontsDir: fontsDir, uuid: uuid)
        } else {
            renderer = AssImageRenderer(header: header, uuid: uuid)
        }
    }

    // explicit deinit 0x101a94270: drops this fontsDir's pooled renderers.
    deinit {
        if let fontsDir {
            AssImageRenderer.renderers.removeValue(forKey: fontsDir)
        }
    }

    // INFERRED name — static helper 0x101a960dc (basicFontSize: Int, header: String) -> String, direct-called from
    //   init(fontsDir:header:) 0x101a92d2c and updateTextStyle. Rewrites the `Style: Default` font size to
    //   Int(KSOptions.subtitleFontSizeScale * basicFontSize).
    static func rewriteHeader(basicFontSize: Int, header: String) -> String {
        for line in header.components(separatedBy: "\n") where line.hasPrefix("Style: Default") {
            let parts = line.components(separatedBy: ",")
            guard parts.count > 2 else {
                return header
            }
            if let fontSize = Int(parts[2]), fontSize > 0 {
                let newSize = Int(KSOptions.subtitleFontSizeScale * Double(basicFontSize))
                if fontSize != newSize {
                    return header.replacingOccurrences(of: line, with: line.replacingOccurrences(of: parts[2], with: newSize.description))
                }
            }
            return header
        }
        return header
    }

    func updateTextStyle() {
        guard let header else {
            return
        }
        let newHeader = Self.rewriteHeader(basicFontSize: basicFontSize, header: header)
        if newHeader != header {
            self.header = newHeader
            renderer.update(header: newHeader, uuid: uuid)
            ass_flush_events(renderer.currentTrack)
            for subtitle in subtitles {
                if var buffer = subtitle.subtitle.cString(using: .utf8) {
                    ass_process_chunk(renderer.currentTrack, &buffer, Int32(buffer.count), subtitle.start, subtitle.duration)
                }
            }
        }
    }

    // INFERRED name — helper 0x101a93800 (direct call from the search witness 0x101a944ec): reclaims the pooled
    //   renderer when another actor took it over, replaying the header + buffered events.
    private final func currentRenderer() -> AssImageRenderer {
        guard renderer.uuid != uuid, let fontsDir else {
            return renderer
        }
        let renderer = AssImageRenderer.renderer(fontsDir: fontsDir, uuid: uuid)
        guard renderer.uuid != uuid else {
            return renderer
        }
        if let header {
            renderer.update(header: header, uuid: uuid)
            self.renderer = renderer
        }
        for subtitle in subtitles {
            if var buffer = subtitle.subtitle.cString(using: .utf8) {
                ass_process_chunk(renderer.currentTrack, &buffer, Int32(buffer.count), subtitle.start, subtitle.duration)
            }
        }
        return renderer
    }

    // ⚑[tool=member_surface ref=AssIncrementImageRenderer.search(with:) result=Forward sync (no Ya); body has no swift_task_* call]
    // Forward 0x101a937c4 (mangled `…search4with…tF`, no Ya) is actor-isolated sync: the async witness 0x101a944ec hops
    //   to the actor, then `currentRenderer().search(with: query)` (0x101a93800 → 0x101a93b14). KEPT nonisolated `[]`:
    //   the isolated form fails Swift 6 (non-Sendable KSSubtitleQuery / [SubtitlePart] across the protocol requirement)
    //   → GAP until those types are Sendable.
    nonisolated func search(with _: KSSubtitleQuery) -> [SubtitlePart] { [] }
}

// AssImageRenderer @0x1039f1584 — Forward 1.3.17. vtable 3, 7 stored fields (reflection-authoritative:
// uuid/library/renderer/currentTrack/alignments/margins/size). Absent from the export trie (no private discriminator
// recovered, so no `private` on the type).
final class AssImageRenderer: KSSubtitleProtocol { // §8.5-gap: KSSubtitleProtocol conformer (reverse-walk-confirmed, pre-commit gate)
    // INFERRED name — lazy static DAT_1044ee018 (swift_once → [:]): fontsDir → pooled renderers, read/written by
    //   the factory 0x101a9667c and AssIncrementImageRenderer.deinit 0x101a94270.
    nonisolated(unsafe) static var renderers: [String: [AssImageRenderer]] = [:]
    // ⚑[tool=field_surface ref=AssImageRenderer:fieldmd result=var/let/let/var/var/var/var]
    //   uuid / currentTrack widened from private: AssIncrementImageRenderer reads them directly (flush/add/updateTextStyle
    //   and 0x101a93800 load the fields without an accessor call).
    var uuid: UUID = UUID()
    private let library: OpaquePointer?                    // ass_library* (§8.6)
    private let renderer: OpaquePointer?                   // ass_renderer* (§8.6)
    var currentTrack: UnsafeMutablePointer<ass_track>? // §8.3 (libass; reflection-resolved)
    private var alignments: [Int32]
    private var margins: [(left: Int32, right: Int32, vertical: Int32)]
    // size didSet 0x101a94538: frame + storage size follow the render size.
    private var size: CGSize = .zero {
        didSet {
            guard size != oldValue else {
                return
            }
            ass_set_frame_size(renderer, Int32(size.width), Int32(size.height))
            ass_set_storage_size(renderer, Int32(size.width), Int32(size.height))
        }
    }

    // INFERRED name — static factory 0x101a9667c (fontsDir: String, uuid: UUID) -> AssImageRenderer.
    static func renderer(fontsDir: String, uuid: UUID) -> AssImageRenderer {
        if var renderers = renderers[fontsDir], renderers.count > 0 {
            for renderer in renderers where renderer.uuid == uuid {
                return renderer
            }
            if renderers.count == 1 {
                let renderer = AssImageRenderer(fontsDir: fontsDir)
                renderers.append(renderer)
                Self.renderers[fontsDir] = renderers
                return renderer
            }
            return renderers.randomElement()!
        }
        let renderer = AssImageRenderer(fontsDir: fontsDir)
        renderers[fontsDir] = [renderer]
        return renderer
    }

    // init(content:uuid:) 0x101a946bc
    init(content: String, uuid: UUID) {
        library = ass_library_init()
        ass_set_extract_fonts(library, 1)
        renderer = ass_renderer_init(library)
        ass_set_fonts(renderer, KSOptions.defaultFont?.path, nil, Int32(ASS_FONTPROVIDER_CORETEXT.rawValue), nil, 0)
        self.uuid = uuid
        var content = content
        if !content.contains("[Events]") {
            if let range = content.range(of: "Dialogue:") {
                content.insert(contentsOf: "[Events]\n", at: range.lowerBound)
            }
        }
        if !content.contains("Format: Layer") {
            if let range = content.range(of: "[Events]") {
                content.insert(contentsOf: "\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text", at: range.upperBound)
            }
        }
        if var buffer = content.cString(using: .utf8) {
            currentTrack = ass_read_memory(library, &buffer, buffer.count, nil)
        }
        alignments = []
        margins = []
        updateStyles()
    }

    // init(header:uuid:) 0x101a94d08
    init(header: String, uuid: UUID) {
        library = ass_library_init()
        ass_set_extract_fonts(library, 1)
        renderer = ass_renderer_init(library)
        ass_set_fonts(renderer, KSOptions.defaultFont?.path, nil, Int32(ASS_FONTPROVIDER_CORETEXT.rawValue), nil, 0)
        self.uuid = uuid
        currentTrack = ass_new_track(library)
        if var buffer = header.cString(using: .utf8) {
            ass_process_codec_private(currentTrack, &buffer, Int32(buffer.count))
        }
        alignments = []
        margins = []
        updateStyles()
    }

    // init(fontsDir:) 0x101a9501c — pooled renderer, no track until update(header:uuid:).
    init(fontsDir: String) {
        library = ass_library_init()
        ass_set_extract_fonts(library, 1)
        renderer = ass_renderer_init(library)
        ass_set_fonts_dir(library, fontsDir)
        ass_set_fonts(renderer, KSOptions.defaultFont?.path, nil, Int32(ASS_FONTPROVIDER_CORETEXT.rawValue), nil, 0)
        alignments = []
        margins = []
    }

    // deinit 0x101a95d74
    deinit {
        if let currentTrack {
            ass_free_track(currentTrack)
        }
        ass_renderer_done(renderer)
        ass_library_done(library)
    }

    // INFERRED name — 0x101a9364c (header: String, uuid: UUID), direct-called from AssIncrementImageRenderer
    //   updateTextStyle and 0x101a93800: replaces the track with a fresh one built from the header.
    func update(header: String, uuid: UUID) {
        if let currentTrack {
            ass_free_track(currentTrack)
        }
        currentTrack = ass_new_track(library)
        self.uuid = uuid
        if var buffer = header.cString(using: .utf8) {
            ass_process_codec_private(currentTrack, &buffer, Int32(buffer.count))
        }
        size = .zero
        updateStyles()
    }

    // INFERRED name — 0x101a94c20: snapshots the track's original style alignments/margins.
    func updateStyles() {
        if let currentTrack {
            alignments = currentTrack.pointee.alignments
            margins = currentTrack.pointee.margins
        } else {
            alignments = []
            margins = []
        }
    }

    // INFERRED name — 0x101a95810 (role: SubtitleTextRole): selective style override from the resolved text style
    //   (only for .secondary with KSOptions.secondaryTextStyle set @0x1044e50c8).
    func setStyleOverride(role: SubtitleTextRole) {
        if role == .secondary, KSOptions.secondaryTextStyle != nil {
            let style = KSOptions.textStyle(role: role)
            var assStyle = ASS_Style(
                Name: nil,
                FontName: nil,
                FontSize: (style.subtitleFontSize + 5) * style.subtitleFontSizeScale,
                PrimaryColour: style.textColor.assStyleColor,
                SecondaryColour: style.textColor.assStyleColor,
                OutlineColour: style.textStrokeWidth > 0 ? style.textStrokeColor.assStyleColor : UIColor.clear.assStyleColor,
                BackColour: style.textShadowColor.assStyleColor,
                Bold: style.textBold ? 1 : 0,
                Italic: style.textItalic ? 1 : 0,
                Underline: 0,
                StrikeOut: 0,
                ScaleX: 1,
                ScaleY: 1,
                Spacing: 0,
                Angle: 0,
                BorderStyle: 1,
                Outline: style.textStrokeWidth,
                Shadow: style.textShadowColor == UIColor.clear ? 0 : max(max(abs(style.textShadowOffset.width), abs(style.textShadowOffset.height)), style.textShadowBlurRadius),
                Alignment: 2,
                MarginL: 10,
                MarginR: 10,
                MarginV: 10,
                Encoding: 1,
                treat_fontname_as_pattern: 0,
                Blur: 0,
                Justify: 0
            )
            "Default".withCString { name in
                style.textFontName.withCString { fontName in
                    assStyle.Name = UnsafeMutablePointer(mutating: name)
                    assStyle.FontName = UnsafeMutablePointer(mutating: fontName)
                    ass_set_selective_style_override(renderer, &assStyle)
                }
            }
            ass_set_selective_style_override_enabled(renderer, Int32(ASS_OVERRIDE_BIT_STYLE.rawValue))
        } else {
            ass_set_selective_style_override_enabled(renderer, Int32(ASS_OVERRIDE_DEFAULT.rawValue))
        }
    }

    // INFERRED name — 0x101a953f4 (scale, textPosition, verticalAlign, textRole): rewrites every style's
    //   Alignment / Margin* from the query, falling back to the snapshot from updateStyles().
    func updateStyle(scale: CGFloat, textPosition: TextPosition?, verticalAlign: VerticalAlignment?, textRole: SubtitleTextRole) {
        guard let currentTrack else {
            return
        }
        setStyleOverride(role: textRole)
        for i in 0 ..< Int(currentTrack.pointee.n_styles) {
            let alignment = i < alignments.count ? alignments[i] : currentTrack.pointee.styles[i].Alignment
            let margin = i < margins.count ? margins[i] : (left: currentTrack.pointee.styles[i].MarginL, right: currentTrack.pointee.styles[i].MarginR, vertical: currentTrack.pointee.styles[i].MarginV)
            if let textPosition {
                let horizontal: Int32 = switch textPosition.horizontalAlign {
                case .leading: 1
                case .center: 2
                case .trailing: 3
                default: (alignment - 1) % 3 + 1
                }
                currentTrack.pointee.styles[i].Alignment = switch textPosition.verticalAlign {
                case .bottom: horizontal
                case .center: horizontal + 8
                case .top: horizontal + 4
                default: horizontal
                }
                currentTrack.pointee.styles[i].MarginL = Int32((scale * textPosition.leftMargin).rounded())
                currentTrack.pointee.styles[i].MarginR = Int32((scale * textPosition.rightMargin).rounded())
                currentTrack.pointee.styles[i].MarginV = Int32((scale * textPosition.verticalMargin).rounded())
            } else if let verticalAlign {
                let horizontal = (alignment - 1) % 3 + 1
                currentTrack.pointee.styles[i].Alignment = switch verticalAlign {
                case .bottom: horizontal
                case .center: horizontal + 8
                case .top: horizontal + 4
                default: horizontal
                }
                currentTrack.pointee.styles[i].MarginL = margin.left
                currentTrack.pointee.styles[i].MarginR = margin.right
                currentTrack.pointee.styles[i].MarginV = margin.vertical
            } else {
                currentTrack.pointee.styles[i].Alignment = alignment
                currentTrack.pointee.styles[i].MarginL = margin.left
                currentTrack.pointee.styles[i].MarginR = margin.right
                currentTrack.pointee.styles[i].MarginV = margin.vertical
            }
        }
    }

    // L7 b4: sync — the KSSubtitleProtocol witness 0x101a95e14 calls this sync body 0x101a93b14 (no Ya).
    func search(with query: KSSubtitleQuery) -> [SubtitlePart] {
        let scale = UITraitCollection.current.displayScale
        size = CGSize(width: query.size.width * scale, height: query.size.height * scale)
        updateStyle(scale: scale, textPosition: query.textPosition, verticalAlign: query.verticalAlign, textRole: query.textRole)
        var changed: Int32 = 0
        let millisecond = Int64(query.time * 1000)
        if let frame = ass_render_frame(renderer, currentTrack, millisecond, &changed), changed != 0 {
            let images = frame.pointee.linkedImages()
            if !images.isEmpty {
                // Forward calls the [CGRect] bounding-rect helper 0x1019e7b40 (Forward Utility.swift, not in Sources →
                //   GAP review); its body is inlined here until the decl exists.
                let rects = images.map { CGRect(x: Int($0.dst_x), y: Int($0.dst_y), width: Int($0.w), height: Int($0.h)) }
                let rect: CGRect
                if let minX = rects.map(\.minX).min(), let minY = rects.map(\.minY).min(), let maxX = rects.map(\.maxX).max(), let maxY = rects.map(\.maxY).max() {
                    rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                } else {
                    rect = .zero
                }
                let layers = images.compactMap { image -> SubtitleImageInfo.AssLayer? in
                    guard image.w > 0, image.h > 0, let bitmap = image.bitmap else {
                        return nil
                    }
                    let type: SubtitleImageInfo.AssLayer.LayerType = switch image.type {
                    case IMAGE_TYPE_CHARACTER: .character
                    case IMAGE_TYPE_OUTLINE: .outline
                    case IMAGE_TYPE_SHADOW: .shadow
                    default: .other
                    }
                    return SubtitleImageInfo.AssLayer(bitmap: Data(bytes: bitmap, count: Int(image.stride) * Int(image.h)), color: image.color, type: type, w: Int(image.w), h: Int(image.h), stride: Int(image.stride), dstX: Int(image.dst_x), dstY: Int(image.dst_y))
                }
                if !layers.isEmpty {
                    return [SubtitlePart(query.time, .infinity, image: SubtitleImageInfo(rect: rect, source: .assBlend(layers: layers, boundingRect: rect), displaySize: size, styleRole: .primary))]
                }
            }
        }
        if changed != 0 {
            return [SubtitlePart(query.time, .infinity, "")]
        }
        return []
    }
}

extension ASS_Track {
    // INFERRED name — 0x101a95238: per-style Alignment over n_styles (styles is IUO → trap on nil).
    var alignments: [Int32] {
        (0 ..< Int(n_styles)).map { styles[$0].Alignment }
    }

    // INFERRED name — 0x101a9530c: per-style (MarginL, MarginR, MarginV).
    var margins: [(left: Int32, right: Int32, vertical: Int32)] {
        (0 ..< Int(n_styles)).map { (styles[$0].MarginL, styles[$0].MarginR, styles[$0].MarginV) }
    }
}

extension ASS_Image {
    // INFERRED name — 0x101a8deec: walks `next`, keeping images with a non-empty bitmap.
    func linkedImages() -> [ASS_Image] {
        var images = [ASS_Image]()
        var image: ASS_Image? = self
        while let current = image {
            if current.w != 0, current.h != 0 {
                images.append(current)
            }
            image = current.next?.pointee
        }
        return images
    }
}

extension UIColor {
    // INFERRED name — 0x101a95b48 (self in x20 → UIColor instance member; not Color.swift's `assColor: String` 0x1019e85a4): libass ABGR word, alpha inverted (0 = opaque).
    var assStyleColor: UInt32 {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return 0
        }
        let r = UInt32(min(max(0, (red * 255).rounded()), 255))
        let g = UInt32(min(max(0, (green * 255).rounded()), 255))
        let b = UInt32(min(max(0, (blue * 255).rounded()), 255))
        let a = UInt32(min(max(0, ((1 - alpha) * 255).rounded()), 255))
        return a << 24 | b << 16 | g << 8 | r
    }
}
