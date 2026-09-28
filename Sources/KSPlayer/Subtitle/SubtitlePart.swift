//
//  SubtitlePart.swift
//  KSPlayer
//
//  Forward 1.3.17 — the Metal-subtitle layout chain behind MetalSubtitleView vtable slot 40
//  (@0x101ac0a90). The file is named by the chain's own evidence: every executor check in it passes
//  #fileID "KSPlayer/SubtitlePart.swift" (cstring 0x103d3a3f0, count 0x1b), and every escape check
//  passes a #filePath of length 0x4c = 76 = "/Users/johnil/Work/git/KSPlayer/Sources/KSPlayer/Subtitle/
//  SubtitlePart.swift". In Forward, SubtitlePart / TextPosition themselves also live in this file
//  (0x101abac2c…0x101abc358). Here they stay in KSSubtitle.swift; moving them is a separate file split.
//  Only the chain is written here. #sourceLocation pins the four closure lines (392/414/474/479) that
//  the binary encodes.
//
import Metal
import CoreFoundation
import CoreGraphics
import Foundation
import SwiftUI

public struct TextPosition {
    public var verticalAlign: VerticalAlignment = .bottom
    public var horizontalAlign: HorizontalAlignment = .center
    public var leftMargin: CGFloat = 0
    public var rightMargin: CGFloat = 0
    public var verticalMargin: CGFloat = 10

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

    // alignment.getter @0x101abb264, 99 instr — the INVERSE of `ass(alignment:)` below.
    // public proven by the property descriptor $s8KSPlayer12TextPositionV9alignmentSSvpMV
    // @0x10356d858; no `…SSvs` and no `…SSvM`, so it is get-only.
    //
    // The body is a flat chain of nine two-part conjunctions, each re-loading both cases —
    // which is what a `switch` over a TUPLE of Equatable structs lowers to (SwiftUI's
    // alignments are structs, so each `case` is an `==` call, not a tag compare). The
    // prologue is `ldp x21, x19, [x20]`: x21 = field 0 tested against VerticalAlignment,
    // x19 = field 1 tested against HorizontalAlignment — the declared order of
    // verticalAlign / horizontalAlign above.
    //
    // Every returned value is a one-character small string: w0 carries the ASCII byte and
    // the shared epilogue sets word1 = 0xE100000000000000 (0xE0|1, all-ASCII, count 1).
    // The nine bytes read 0x31…0x39 = "1"…"9" in numeric-keypad order, and the
    // (.bottom, .center) arm branches into the SAME block as the fallback, which is why
    // "2" appears both as an explicit case and as the default. That case IS tested
    // explicitly at 0x101abb2b0 — it is not folded away — so the source names all nine.
    // ⚑[tool=bind_oracle ref=SwiftUI.VerticalAlignment.bottom:0x10410ec98 result=bottom]
    // ⚑[tool=bind_oracle ref=SwiftUI.VerticalAlignment.center:0x10410eca0 result=center]
    // ⚑[tool=bind_oracle ref=SwiftUI.VerticalAlignment.top:0x10410ec90 result=top]
    // ⚑[tool=bind_oracle ref=SwiftUI.HorizontalAlignment.leading:0x10410eef0 result=leading]
    // ⚑[tool=bind_oracle ref=SwiftUI.HorizontalAlignment.center:0x10410eee8 result=center]
    // ⚑[tool=bind_oracle ref=SwiftUI.HorizontalAlignment.trailing:0x10410eef8 result=trailing]
    public var alignment: String {
        switch (verticalAlign, horizontalAlign) {
        case (.bottom, .leading):
            return "1"
        case (.bottom, .center):
            return "2"
        case (.bottom, .trailing):
            return "3"
        case (.center, .leading):
            return "4"
        case (.center, .center):
            return "5"
        case (.center, .trailing):
            return "6"
        case (.top, .leading):
            return "7"
        case (.top, .center):
            return "8"
        case (.top, .trailing):
            return "9"
        default:
            return "2"
        }
    }
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
}
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// The two keys are once-initialised statics whose init functions (0x101abb894 / 0x101abb8c8) bridge the
// 27-char literals at 0x103d3a3d0 / 0x103d3a3b0 into storage 0x104c63808 / 0x104c63800. The init
// functions are emitted width-first, so width is declared first. They are also read by FUN_1019ea6c4 and
// FUN_1019eba7c (the stroke-drawing side). Neither symbol survives in the trie.
extension NSAttributedString.Key {
    static let subtitleStrokeWidth = NSAttributedString.Key("KSPlayerSubtitleStrokeWidth") // name inferred
    static let subtitleStrokeColor = NSAttributedString.Key("KSPlayerSubtitleStrokeColor") // name inferred
}

/// FUN_101abc398 (0xca4 B). The only caller is MetalSubtitleView slot 40 (bl @0x101ac0b34).
/// Registers: d0 = playRatio, d1/d2 = size, x0 = fontWidthMode, x1 = parts. The result comes back in
/// x0/x1 = (images, texts), stored by the caller to subtitleImages (0x5c0) and pendingTexts (0x5c8).
/// ⚑ The type of `fontWidthMode` is inferred as Int: the callee spills it as a full x-register and
///   tests it with a 64-bit `cmp x8, #1`. A Bool or native enum would be tested with a byte/`tbz` form.
///   The slot-40 caller passes the literal 1.
@MainActor
func layoutSubtitle(playRatio: Double, size: CGSize, fontWidthMode: Int, parts: [SubtitlePart]) -> ([SubtitleImageInfo], [SubtitleTextInfo]) { // name inferred
    var images = [SubtitleImageInfo]()
    var texts = [SubtitleTextInfo]()
    for part in parts {
        switch part.render {
        case var .left(info):
            var rect = info.rect
            let displaySize = info.displaySize
            // The zero tests run in this order: displaySize.height, displaySize.width, size.width, size.height.
            if displaySize.height != 0, displaySize.width != 0, size.width != 0, size.height != 0 {
                let widthScale = size.width / displaySize.width
                let heightScale = size.height / displaySize.height
                // Constants 2.32 (0x40028f5c28f5c28f @0x103564790) and 2.34 (0x4002b851eb851eb8 @0x103564788).
                let scale = playRatio > 2.32 && playRatio < 2.34 ? widthScale : min(widthScale, heightScale)
                rect = CGRect(x: rect.origin.x * scale, y: rect.origin.y * scale, width: rect.size.width * scale, height: rect.size.height * scale)
                let imageScale = KSOptions.subtitleImageScale
                if imageScale != 1.0 {
                    let midX = rect.midX
                    let midY = rect.midY
                    rect.size.width *= imageScale
                    rect.size.height *= imageScale
                    rect.origin.x = midX - rect.width * 0.5
                    rect.origin.y = midY - rect.height * 0.5
                }
                rect.origin.x += (size.width - displaySize.width * scale) * 0.5
                let offsetY = (size.height - displaySize.height * scale) * 0.5
                rect.origin.y += offsetY
                // fcmp h, maxY; fcsel mi → the offset is added a second time when the rect overflows.
                if rect.maxY > size.height {
                    rect.origin.y += offsetY
                }
                // Only the ORIGIN of CGRectIntegral is taken: v2/v3 of its result are dropped and the
                // pre-integral width and height are stored.
                rect.origin = rect.integral.origin
                let offset = KSOptions.subtitleImageOffset
                rect.origin.x += offset.width
                rect.origin.y += offset.height
            }
            info.rect = rect
            images.append(info)
        case let .right(info):
            texts.append(info)
        }
    }
    var textInfos = [SubtitleTextInfo]()
    // FUN_101abf7ec is the Dictionary(grouping:by:) specialisation with this closure inlined. Its executor check is at line 0x188.
#sourceLocation(file: "/Users/johnil/Work/git/KSPlayer/Sources/KSPlayer/Subtitle/SubtitlePart.swift", line: 392)
    let groups = Dictionary(grouping: texts) { info in
        var position = info.position ?? KSOptions.textPosition
        if KSOptions.stripSubtitleStyle, !info.usesForcedPosition {
            let textPosition = KSOptions.textPosition
            position.leftMargin = textPosition.leftMargin
            position.rightMargin = textPosition.rightMargin
            position.verticalMargin = textPosition.verticalMargin
        }
        return position
    }
#sourceLocation()
    for infos in groups.values {
        let first = infos[0]
        let displaySize = first.displaySize ?? CGSize(width: 384, height: 216)
        let fitSize = size.within(ratio: playRatio)
        let scale = min(fitSize.width / displaySize.width, fitSize.height / displaySize.height)
        var position = first.position ?? KSOptions.textPosition
        if KSOptions.stripSubtitleStyle, !first.usesForcedPosition {
            let textPosition = KSOptions.textPosition
            position.leftMargin = textPosition.leftMargin
            position.rightMargin = textPosition.rightMargin
            position.verticalMargin = textPosition.verticalMargin
        }
        let subtitleOffset = KSOptions.subtitleOffset
        let letterbox: Double
        // The branch is (playRatio > 1) XOR (height < width); 16/9 = 0x3ffc71c71c71c71c @0x1034e5b68.
        if (playRatio > 1) == (size.width > size.height) {
            let viewRatio = size.height == 0 || size.width == 0 ? 16.0 / 9.0 : size.width / size.height
            letterbox = playRatio < viewRatio ? floor((size.height - fitSize.height) * 0.5) : 0
        } else {
            letterbox = floor((size.height - fitSize.height) * 0.5)
        }
        let fontWidth = fontWidthMode == 1 ? fitSize.width : max(fitSize.width, fitSize.height)
#sourceLocation(file: "/Users/johnil/Work/git/KSPlayer/Sources/KSPlayer/Subtitle/SubtitlePart.swift", line: 414)
        let strings = infos.map { $0.attributedString(scale: scale, width: fontWidth) }
#sourceLocation()
        let text = NSMutableAttributedString()
        for index in 0 ..< strings.count {
            if index > 0 {
                // The separator is the small string "\n" (w0 = 0xa, x1 = 0xe1<<56).
                let attributes = strings[index - 1].separatorAttributes(next: strings[index])
                text.append(NSAttributedString(string: "\n", attributes: attributes))
            }
            text.append(strings[index])
        }
        if text.length != 0 {
            if scale != 1 {
                position.leftMargin *= scale
                position.rightMargin *= scale
                position.verticalMargin *= scale
            }
            position.verticalMargin += fitSize.height * subtitleOffset + letterbox
            textInfos.append(SubtitleTextInfo(text: text, position: position, displaySize: fitSize, styleRole: first.styleRole, usesForcedPosition: first.usesForcedPosition))
        }
    }
    return (images, textInfos)
}

extension SubtitleTextInfo {
    /// FUN_101abd03c. `self` is passed indirectly in x20; d0 = scale, d1 = width; it returns the NSMutableAttributedString.
    /// The two enumerate blocks carry escape checks (len 0x4c, lines 0x1da/0x1df, col 0x3e) and executor
    /// checks (0x101abdd54 / 0x101abdefc), so the method is MainActor-isolated.
    @MainActor
    func attributedString(scale: Double, width: Double) -> NSMutableAttributedString { // name inferred
        let newText = NSMutableAttributedString(attributedString: text)
        let length = newText.length
        if length == 0 {
            return newText
        }
        let style = KSOptions.textStyle(role: styleRole)
        let range = NSRange(location: 0, length: length)
        if newText.attributes(at: 0, effectiveRange: nil).isEmpty || KSOptions.stripSubtitleStyle {
            var attributes = [NSAttributedString.Key: Any]()
            attributes[.font] = KSOptions.textFont(width: width, style: style)
            attributes[.foregroundColor] = style.textColor
            if style.textShadowColor != UIColor.clear {
                let shadow = NSShadow()
                shadow.shadowOffset = style.textShadowOffset
                shadow.shadowColor = style.textShadowColor
                shadow.shadowBlurRadius = style.textShadowBlurRadius
                attributes[.shadow] = shadow
            }
            newText.addAttributes(attributes, range: range)
        } else {
            if scale != 1.0 {
#sourceLocation(file: "/Users/johnil/Work/git/KSPlayer/Sources/KSPlayer/Subtitle/SubtitlePart.swift", line: 474)
                newText.enumerateAttribute(.font, in: range) { value, range, _ in
                    if let font = value as? UIFont {
                        newText.addAttribute(.font, value: font.withSize(floor(scale * font.pointSize)), range: range)
                    }
                }
                newText.enumerateAttribute(.kern, in: range) { value, range, _ in
                    if let kern = value as? CGFloat {
                        newText.addAttribute(.kern, value: scale * kern, range: range)
                    }
                }
#sourceLocation()
            }
            if newText.attributes(at: 0, effectiveRange: nil)[.font] == nil {
                newText.addAttribute(.font, value: KSOptions.textFont(width: width, style: style), range: range)
            }
            if newText.attributes(at: 0, effectiveRange: nil)[.foregroundColor] == nil {
                newText.addAttribute(.foregroundColor, value: style.textColor, range: range)
            }
        }
        newText.addAttribute(.subtitleStrokeWidth, value: style.textStrokeWidth, range: range)
        newText.addAttribute(.subtitleStrokeColor, value: style.textStrokeColor, range: range)
        return newText
    }
}

extension NSAttributedString {
    /// FUN_101abd9b0. `self` in x20 is the preceding line and x0 is the next one. The line-break
    /// separator gets the preceding line's LAST attributes, and it takes the next line's first font
    /// when that font is taller.
    func separatorAttributes(next: NSAttributedString) -> [NSAttributedString.Key: Any] { // name inferred
        var attributes: [NSAttributedString.Key: Any] = length > 0 ? self.attributes(at: length - 1, effectiveRange: nil) : [:]
        let nextAttributes: [NSAttributedString.Key: Any] = next.length > 0 ? next.attributes(at: 0, effectiveRange: nil) : [:]
        if let font = attributes[.font] as? UIFont, let nextFont = nextAttributes[.font] as? UIFont, nextFont.lineHeight > font.lineHeight {
            attributes[.font] = nextFont
        }
        return attributes
    }
}

// SubtitlePart @0x1039f21e8 — STRUCT (was class); payload consolidated into `render: Either` (§8.6).
// Conformances carried from the recon (reverse-walk confirms NumericComparable; the 4 stdlib ones are
// GOT-indirect-blind but xref-count-corroborated — ~5 conformance descriptors). The Comparable +
// NumericComparable extensions (below, unchanged) use only start/end → they transfer faithfully.
public struct SubtitlePart: CustomStringConvertible, Identifiable {
    public let start: Double
    public var end: Double

    /// ⚑[tool=export_trie_oracle ref=KSPlayer.SubtitlePart.isEmpty.getter:0x101abacac result=38-instr]
    /// Same discriminator test, then `objc_msgSend(text, "string")` and a `String` emptiness test:
    /// ⚑[tool=decode_objc_selector ref=0x10440e300 result='string']
    /// the trailing `and x8, x21, #0xffffffffffff` / `ubfx x9, x22, #56, #4` /
    /// `tst x22, #1<<61` / `csel` is the standard count extraction that reads the LARGE
    /// representation's count from the first word and the SMALL one's from the top nibble of the
    /// second — i.e. `String.isEmpty`, not a pointer-null test. The `.left` arm returns `false`,
    /// which is the `?? false` below rather than a `true` default.
    ///
    /// ⚑ The binary inlines the discriminator test here rather than calling `text`'s getter, but
    ///   that does NOT decide the spelling: `text?.string.isEmpty ?? false` and a repeated
    ///   `if case .right` compile to the same code once `text` is inlined. Written in terms of
    ///   `text` because that member is right here; the alternative is indistinguishable.
    public var isEmpty: Bool {
        text?.string.isEmpty ?? false
    }
    public init(_ p0: Double, _ p1: Double, _ p2: String) { fatalError("L7: SubtitlePart.init — Forward body unread") }

    // ⚑[tool=export_trie_oracle ref=$s8KSPlayer12SubtitlePartV__6renderACSd_SdAA6EitherOyAA0B9ImageInfoVAA0b4TextG0VGtcfC result=start/end are UNLABELLED (`__6render`), RECOVERED]
    public init(_ start: Double, _ end: Double, render: Either<SubtitleImageInfo, SubtitleTextInfo>) {
        self.start = start
        self.end = end
        self.render = render
    }
    public init(_ p0: Double, _ p1: Double, attributedString: NSAttributedString) { fatalError("L7: SubtitlePart.init — Forward body unread") }
    public init(_ p0: Double, _ p1: Double, image: SubtitleImageInfo) { fatalError("L7: SubtitlePart.init — Forward body unread") }
    public init(_ p0: Double, _ p1: Double, text: SubtitleTextInfo) { fatalError("L7: SubtitlePart.init — Forward body unread") }

    /// ⚑[tool=export_trie_oracle ref=KSPlayer.SubtitlePart.text.getter:0x101abaf20 result=18-instr]
    /// Both this and `isEmpty` open with the SAME two reads, and neither is a guess:
    ///   `ldrb w8, [x20, #0x81]` / `cmp w8, #1` — the `render` enum's discriminator, and
    ///   `ldr x19, [x20, #0x10]` — its payload.
    /// `Either` is `case left(Left), right(Right)`, so tag 1 is `.right`, and
    /// `SubtitleTextInfo.text` is that struct's FIRST field — which is why the payload word at
    /// +0x10 IS the `NSAttributedString`, with no addend. The `b.ne` arm returns 0, i.e. nil.
    /// The pair of calls around the read (0x1019e75f0 / 0x1019e762c) are the outlined
    /// copy/destroy for the payload; `SubtitleImageInfo` is what makes the frame 0xb0 bytes.
    public var text: NSAttributedString? {
        if case let .right(info) = render {
            return info.text
        }
        return nil
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

    // The three `change` overloads, all instance methods (`…tF`, no `Z`) that mutate self.
    // Every offset below is READ, not positional: the two payload structs' field-offset vectors come
    // straight out of their static metadata —
    //   SubtitleTextInfo  @0x1041daee0 → text 0x00, position 0x08, displaySize 0x38, styleRole 0x49,
    //                                    usesForcedPosition 0x4a
    //   SubtitleImageInfo @0x1041daca0 → rect 0x00, source 0x20, displaySize 0x60, styleRole 0x70
    // and the `Either` payload sits at SubtitlePart +0x10, so add 0x10 to reach the offsets the
    // bodies use. That is what identifies +0x5a as `usesForcedPosition` (0x10+0x4a) and +0x80 as
    // SubtitleImageInfo's `styleRole` (0x10+0x70). The render discriminator is +0x81 throughout,
    // and `cmp #1` selects `.right` — the same tag this file's `text`/`isEmpty` already rely on.

    /// change(textPosition:) @0x101abb3f0, 77 instr. Guarded on the `.right` tag; the `.left` arm is
    /// the bare epilogue, so an image part is left untouched. Beyond writing the 40-byte
    /// TextPosition into +0x18…+0x40 and clearing the Optional tag at +0x40 (0 = `.some`), it also
    /// does `strb w22,[x20,#0x5a]` with `w22 = 1` — `usesForcedPosition` is set to true, and the old
    /// value it read at the top is NOT restored. That store is why this overload differs from the
    /// other two, which preserve that byte.
    public mutating func change(textPosition: TextPosition) {
        if case .right(var info) = render {
            info.position = textPosition
            info.usesForcedPosition = true
            render = .right(info)
        }
    }

    /// change(verticalAlign:) @0x101abb524, 103 instr. Also `.right`-only. It branches on the
    /// `position` Optional tag at +0x40: tag 1 (`.none`) takes a `swift_once`-guarded read of the
    /// static `KSOptions.textPosition` (offset global 0x104c631c0) as the base, tag 0 (`.some`) uses
    /// the stored one — i.e. `?? KSOptions.textPosition`. Only the FIRST TextPosition word is
    /// replaced from the parameter; the remaining four are carried through, which is `verticalAlign`
    /// being the first of the five declared fields. The displaySize/styleRole/usesForcedPosition
    /// region is saved at the top and restored verbatim at 0x101abb670-67c, so this overload does
    /// NOT touch `usesForcedPosition`.
    /// ⚑[tool=export_trie_oracle ref=KSOptions.textPosition:0x104c631c0 result=textPosition]
    public mutating func change(verticalAlign: VerticalAlignment) {
        if case .right(var info) = render {
            var position = info.position ?? KSOptions.textPosition
            position.verticalAlign = verticalAlign
            info.position = position
            render = .right(info)
        }
    }

    /// change(styleRole:) @0x101abb6c0, 117 instr — the only one of the three that handles BOTH
    /// cases. The `.right` arm writes the parameter to +0x59 (SubtitleTextInfo.styleRole) and
    /// restores +0x5a unchanged; the `b.ne` arm at 0x101abb7c8 is not an early return but the
    /// `.left` path, which writes the same parameter to +0x80 (SubtitleImageInfo.styleRole) and
    /// re-stamps the tag at +0x81. Both payload structs carry a `styleRole`, which is what makes the
    /// two-arm form necessary here and impossible in the other two.
    public mutating func change(styleRole: SubtitleTextRole) {
        switch render {
        case .left(var info):
            info.styleRole = styleRole
            render = .left(info)
        case .right(var info):
            info.styleRole = styleRole
            render = .right(info)
        }
    }
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
}

// ResolvedSubtitleTextStyle @0x1039f2258 — resolved, non-optional (+textBackgroundColor @ field-index 9)
// ⚑[tool=field_surface ref=ResolvedSubtitleTextStyle:fieldmd result=12 let]
public struct ResolvedSubtitleTextStyle {
    public let textColor: UIColor
    public let textFontName: String
    public let subtitleFontSize: Double
    public let subtitleFontSizeScale: Double
    public let textBold: Bool
    public let textItalic: Bool
    public let textStrokeColor: UIColor
    public let textStrokeWidth: CGFloat      // ⚑ CGFloat inferred
    public let textShadowOffset: CGSize
    public let textBackgroundColor: UIColor
    public let textShadowBlurRadius: Double
    public let textShadowColor: UIColor
}

// Hashable is proven by the conformance descriptors $s8KSPlayer12TextPositionVSHAAMc / VSQAAMc.
// `==` is the derived one (__derived_struct_equals @0x101abc010 compares the five fields in order).
// hash(into:) @0x101abc088 is hand-written. It hashes a small-string name for each alignment and then
// the three margins. It is needed here as the Dictionary(grouping:) key in SubtitlePart.swift.
extension TextPosition: Hashable {
    public func hash(into hasher: inout Hasher) {
        let vertical: String // name inferred
        switch verticalAlign {
        case .top:
            vertical = "Top"
        case .center:
            vertical = "Center"
        case .bottom:
            vertical = "Bottom"
        default:
            vertical = ""
        }
        hasher.combine(vertical)
        let horizontal: String // name inferred
        switch horizontalAlign {
        case .leading:
            horizontal = "Leading"
        case .center:
            horizontal = "Center"
        case .trailing:
            horizontal = "Trailing"
        default:
            horizontal = ""
        }
        hasher.combine(horizontal)
        hasher.combine(leftMargin)
        hasher.combine(rightMargin)
        hasher.combine(verticalMargin)
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

// SubtitleTextRole @0x1039f2204 — dual-subtitle role; cases descriptor-confirmed
public enum SubtitleTextRole {
    case primary
    case secondary
}

// SubtitleImageInfo @0x1039f215c
// Equatable 0x10356d5d0 (custom `==`, Forward member `== infix`) and Identifiable 0x10356d5f8.
// ⚑[tool=type_surface ref=SubtitleImageInfo:0x1039f215c result=Equatable,Identifiable]
public struct SubtitleImageInfo: Equatable, Identifiable {
    public var rect: CGRect
    public let source: BitmapSource
    public let displaySize: CGSize
    public var styleRole: SubtitleTextRole

    /// ⚑[tool=disassemble ref=SubtitleImageInfo.id.getter:0x101abb9f4 result=3-instr-thunk]
    /// The row's own body loads four Doubles — `ldp d0,d1,[x20]` / `ldp d2,d3,[x20,#0x10]`, i.e.
    /// the 32 bytes at self+0, which is `rect` — and tail-calls a 49-instruction body at
    /// 0x101abba00. Every call in that body is named, and together they are exactly CGRect's
    /// Hashable conformance:
    ///   `Hasher.init()`            __got 0x104112a98  `_$ss6HasherVABycfC`
    ///   `CGRectStandardize`        __got 0x104109018  — the standardize step, taking and
    ///                                                  returning the four Doubles
    ///   `Hasher._combine(UInt64)`  __got 0x104112a80  — called four times, once per component
    ///   `Hasher.finalize() -> Int` __got 0x104112a88
    /// Each combine is preceded by `fcmp d,#0.0` / `fcsel d0,0.0,d,eq` — the `-0.0 → +0.0`
    /// normalisation `Double.hash(into:)` performs so the two zeroes hash alike. No other field of
    /// this struct is loaded and nothing else is called.
    /// Same shape as the sibling `SubtitleTextInfo.id` above, which is `text.hashValue`.
    /// Trie: `KSPlayer.SubtitleImageInfo.id.getter : Swift.Int`; access read from its vpMV.
    public var id: Int {
        rect.hashValue
    }

    // Forward nests these in SubtitleImageInfo: parent chain of AssLayer @0x1039f2194,
    // LayerType @0x1039f21b0 (in AssLayer) and BitmapSource @0x1039f2178; descriptor order
    // 215c (SubtitleImageInfo) < 2178 < 2194 < 21b0 is this declaration order.
    // ⚑[tool=type_surface ref=SubtitleImageInfo.AssLayer:0x1039f2194 result=parent=SubtitleImageInfo]

    // BitmapSource @0x1039f2178 — cases + payloads decoded (was NOT an empty/simple enum)
    public enum BitmapSource {
        case assBlend(layers: [AssLayer], boundingRect: CGRect)
        case palette(bitmap: Data, palette: Data, width: Int, height: Int, stride: Int)   // Data payloads CONFIRMED (Tier 2b): SubtitleDecode.text() builds them via Foundation __DataStorage, and the 0x78 SubtitleImageInfo stride REQUIRES a 56-byte .palette (2×Data+3×Int), not the earlier ⚑-inferred pointers (40-byte). See FUN_101a6a568 cache 285-316.
        case prerendered(any MTLTexture)
    }

    // AssLayer @0x1039f2194
    public struct AssLayer {
        public let bitmap: Data                           // ⚑[tool=field_surface ref=SubtitleImageInfo.AssLayer.bitmap:idx0 result=let Foundation.Data]
        public let color: UInt32                          // ⚑ inferred (packed color word) → M2 verify
        public let type: LayerType
        public let w: Int
        public let h: Int
        public let stride: Int
        public let dstX: Int
        public let dstY: Int

        // LayerType @0x1039f21b0 — cases descriptor-confirmed
        public enum LayerType {
            case character
            case outline
            case shadow
            case other
        }
    }

    public static func == (lhs: SubtitleImageInfo, rhs: SubtitleImageInfo) -> Bool { fatalError("L7: Equatable.==") }
}

// SubtitleTextInfo @0x1039f21cc
// Equatable 0x10356d630 is the derived one (Forward member __derived_struct_equals); Identifiable 0x10356d658.
// ⚑[tool=type_surface ref=SubtitleTextInfo:0x1039f21cc result=Equatable,Identifiable]
public struct SubtitleTextInfo: Equatable, Identifiable {
    public let text: NSAttributedString
    public var position: TextPosition?
    public let displaySize: CGSize?
    public var styleRole: SubtitleTextRole
    public var usesForcedPosition: Bool

    /// ⚑ getter 0x10047dc78, eight instructions and only two of them are the body:
    ///   ldr x20, [x20]        ; self's FIRST field, i.e. `text` — offset 0, no addend
    ///   bl  0x10345868c       ; a stub through __got 0x104113628
    /// and that GOT slot binds `_$sSo8NSObjectC10ObjectiveCE9hashValueSivg`, the ObjectiveC
    /// overlay's `NSObject.hashValue` getter. NSAttributedString is an NSObject, so the whole
    /// body is `text.hashValue` — no other field is loaded and nothing else is called.
    /// ⚑[tool=bind_oracle ref=NSObject.hashValue:0x104113628 result=libswiftObjectiveC]
    /// Trie: `KSPlayer.SubtitleTextInfo.id.getter : Swift.Int`.
    public var id: Int {
        text.hashValue
    }
}

// SubtitleTextStyle @0x1039f2220 — all-optional override
public struct SubtitleTextStyle {
    public var textColor: UIColor?
    public var textFontName: String?
    public var subtitleFontSize: Double?
    public var subtitleFontSizeScale: Double?
    public var textBold: Bool?
    public var textItalic: Bool?
    public var textStrokeColor: UIColor?
    public var textStrokeWidth: CGFloat?     // ⚑ CGFloat inferred (GOT-indirect symref) → recon/mangle-evidenced
    public var textShadowOffset: CGSize?
    public var textShadowBlurRadius: Double?
    public var textShadowColor: UIColor?
    public init(textColor: UIColor?, textFontName: String?, subtitleFontSize: Double?, subtitleFontSizeScale: Double?, textBold: Bool?, textItalic: Bool?, textStrokeColor: UIColor?, textStrokeWidth: CGFloat?, textShadowOffset: CGSize?, textShadowBlurRadius: Double?, textShadowColor: UIColor?) { fatalError("L7: SubtitleTextStyle.init — Forward body unread") }
}
