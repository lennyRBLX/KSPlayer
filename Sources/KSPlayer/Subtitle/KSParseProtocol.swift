//
//  KSParseProtocol.swift
//  KSPlayer-7de52535
//
//  Created by kintan on 2018/8/7.
//
import Foundation
import SwiftUI
#if !canImport(UIKit)
import AppKit
#else
import UIKit
#endif
public protocol KSParseProtocol {
    func canParse(scanner: Scanner) -> Bool
    func parsePart(scanner: Scanner) -> SubtitlePart?
}

public extension KSOptions {
    static var subtitleParses: [KSParseProtocol] = [AssImageParse(), AssParse(), VTTParse(), SrtParse(), FFmpegSubtitleParse()]
}

public extension String {}

public extension KSParseProtocol {
    func parse(scanner: Scanner) -> [SubtitlePart] {
        var groups = [SubtitlePart]()

        while !scanner.isAtEnd {
            if let group = parsePart(scanner: scanner) {
                groups.append(group)
            }
        }
        groups = groups.mergeSortBottomUp { $0 < $1 }
        return groups
    }

    // MARK: - Shared async URL parse machinery (SrtParse / VTTParse)

    /// Async entry point that loads a subtitle by URL and returns a ready
    /// `KSSubtitleProtocol`. Dispatches on the file extension: `.sup` (bitmap
    /// PGS) goes straight to the FFmpeg actor path; every other extension is
    /// fetched and routed through the text-parser registry.
    ///
    /// RE: 0x1014825a8 (parse_setup, 1.3.15, 156B) — the async state-machine
    /// entry. It captures the URL/user-agent into the async frame, materialises
    /// the `CharacterSet`/`URL` type metadata, and `swift_task_switch`es into
    /// `parse_checkExtAndDispatch`. Reconstructed as the public async front door;
    /// the three lowered binary stages are kept as separate calls below
    /// (parse_setup → checkExtAndDispatch → continuation).
    func parseSetup(url: URL, userAgent: String? = nil) async throws -> KSSubtitleProtocol {
        try await parseCheckExtAndDispatch(url: url, userAgent: userAgent)
    }

    /// Extension check + dispatch stage.
    ///
    /// RE: 0x101482644 (parse_checkExtAndDispatch, 1.3.15, 380B). Reads
    /// `url.pathExtension`; if it equals `"sup"` (word constant `0x707573`) the
    /// binary constructs an `FFmpegSubtitle` and returns it through the protocol
    /// conformance descriptor `0x103a27988`. Otherwise it allocates a
    /// continuation (`parse_continuation`) and kicks off the file read via
    /// `FUN_1013d7204`, resuming in the continuation.
    func parseCheckExtAndDispatch(url: URL, userAgent: String? = nil) async throws -> KSSubtitleProtocol {
        if url.pathExtension == "sup" {
            // Bitmap PGS subtitles: hand directly to the FFmpeg actor.
            let subtitle = FFmpegSubtitle()
            return subtitle
        }
        let data = try await url.data(userAgent: userAgent)
        return try await parseContinuation(url: url, data: data)
    }

    /// Async continuation stage: with the file bytes in hand, run the text
    /// parser registry and wrap the result.
    ///
    /// RE: 0x1014827c0 (parse_continuation, 1.3.15, 152B, vtable-reachable). On a
    /// successful read it `swift_task_switch`es into
    /// `SubtitleParse_loadAndParse_async` (0x101482858); on failure it propagates
    /// the error out of the async frame.
    func parseContinuation(url: URL, data: Data) async throws -> KSSubtitleProtocol {
        let registry = SubtitleParseRegistry(parsers: KSOptions.subtitleParses)
        let driver = SubtitleParse(registry: registry)
        let subtitle = KSSubtitle()
        do {
            subtitle.parts = try driver.parse(data: data, preferredEncoding: nil)
        } catch SubtitleParse.Failure.noParserMatched, SubtitleParse.Failure.undecodable {
            // No text parser claimed the bytes — fall back to the FFmpeg-driven
            // load (which itself falls through to the FFmpegSubtitle actor),
            // matching loadAndParse_async's no-match tail.
            subtitle.parts = try await driver.loadAndParseAsync(url: url)
        }
        return subtitle
    }
}

public class AssParse: KSParseProtocol {
    /// `internal` (not `private`): the SSA dialogue path in `SubtitleDecode`
    /// (`resolveSSAStyle` @0x10147b080, MEPlayer/SubtitleDecode.swift) reads this
    /// style map cross-file to resolve a Dialogue line's named `Style` row. Both
    /// types live in the KSPlayer module, so module-default access suffices.
    var styleMap = [String: ASSStyle]()
    private var eventKeys = ["Layer", "Start", "End", "Style", "Name", "MarginL", "MarginR", "MarginV", "Effect", "Text"]
    /// PlayResX/PlayResY from the `[Script Info]` section. RE field #3: the
    /// binary stores a single `CGSize` (the `0x4078000000000000` / `0x4072000000000000`
    /// defaults are IEEE-754 *doubles* = 384.0 / 288.0), not two `Float`s.
    private var displaySize = CGSize(width: 384, height: 288)

    /// RE: 0x10147eb1c (AssParse.deinit_releaseEventFormat, 1.3.15) — the binary
    /// has an explicit deinit that releases the `eventKeys` array storage. In
    /// Swift this teardown is ARC-synthesized for the stored `[String]`, so no
    /// custom body is required; documented here for traceability.
    /// RE: 0x100032ca4 (AssParse.dealloc, 1.3.15) — ObjC dealloc thunk for the
    /// NSObject-bridged class; compiler/runtime-generated.

    /// RE: 0x10147bd14 (AssParse.canParse, 1.3.15) — extracts PlayResX/PlayResY
    /// into `displaySize` and builds the style map + event keyset.
    public func canParse(scanner: Scanner) -> Bool {
        guard scanner.scanString("[Script Info]") != nil else {
            return false
        }
        while scanner.scanString("Format:") == nil {
            if scanner.scanString("PlayResX:") != nil {
                displaySize.width = scanner.scanDouble().map(CGFloat.init) ?? displaySize.width
            } else if scanner.scanString("PlayResY:") != nil {
                displaySize.height = scanner.scanDouble().map(CGFloat.init) ?? displaySize.height
            } else {
                _ = scanner.scanUpToCharacters(from: .newlines)
            }
        }
        guard var keys = scanner.scanUpToCharacters(from: .newlines)?.components(separatedBy: ",") else {
            return false
        }
        keys = keys.map { $0.trimmingCharacters(in: .whitespaces) }
        while scanner.scanString("Style:") != nil {
            _ = scanner.scanString("Format: ")
            guard let values = scanner.scanUpToCharacters(from: .newlines)?.components(separatedBy: ",") else {
                continue
            }
            var dic = [String: String]()
            for i in 1 ..< keys.count {
                dic[keys[i]] = values[i]
            }
            styleMap[values[0]] = dic.parseASSStyle()
        }
        _ = scanner.scanString("[Events]")
        if scanner.scanString("Format: ") != nil {
            guard let keys = scanner.scanUpToCharacters(from: .newlines)?.components(separatedBy: ",") else {
                return false
            }
            eventKeys = keys.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return true
    }

    // Dialogue: 0,0:12:37.73,0:12:38.83,Aki Default,,0,0,0,,{\be8}原来如此
    // ffmpeg soft-decoded subtitle
    // 875,,Default,NTP,0000,0000,0000,!Effect,- 你们两个别冲这么快\\N- 我会取消所有行程尽快赶过去
    /// RE: parsePart dispatches ASS Dialogue lines; pairs with
    /// `buildAttributedStringAttrsFromStyle` @0x10147924c for style resolution.
    public func parsePart(scanner: Scanner) -> SubtitlePart? {
        let isDialogue = scanner.scanString("Dialogue") != nil
        var dic = [String: String]()
        for i in 0 ..< eventKeys.count {
            if !isDialogue, i == 1 {
                continue
            }
            if i == eventKeys.count - 1 {
                dic[eventKeys[i]] = scanner.scanUpToCharacters(from: .newlines)
            } else {
                dic[eventKeys[i]] = scanner.scanUpToString(",")
                _ = scanner.scanString(",")
            }
        }
        let start: TimeInterval
        let end: TimeInterval
        if let startString = dic["Start"], let endString = dic["End"] {
            start = startString.parseDuration()
            end = endString.parseDuration()
        } else {
            if isDialogue {
                return nil
            } else {
                start = 0
                end = 0
            }
        }
        var attributes: [NSAttributedString.Key: Any]?
        var textPosition: TextPosition
        if let style = dic["Style"], let assStyle = styleMap[style] {
            attributes = assStyle.attrs
            textPosition = assStyle.textPosition
            if let marginL = dic["MarginL"].flatMap(Double.init), marginL != 0 {
                textPosition.leftMargin = CGFloat(marginL)
            }
            if let marginR = dic["MarginR"].flatMap(Double.init), marginR != 0 {
                textPosition.rightMargin = CGFloat(marginR)
            }
            if let marginV = dic["MarginV"].flatMap(Double.init), marginV != 0 {
                textPosition.verticalMargin = CGFloat(marginV)
            }
        } else {
            textPosition = TextPosition()
        }
        guard var text = dic["Text"] else {
            return nil
        }
        text = text.replacingOccurrences(of: "\\N", with: "\n")
        text = text.replacingOccurrences(of: "\\n", with: "\n")
        var part = SubtitlePart(start, end, attributedString: text.build(textPosition: &textPosition, attributed: attributes))
        part.textPosition = textPosition
        return part
    }
}

public struct ASSStyle {
    let attrs: [NSAttributedString.Key: Any]
    let textPosition: TextPosition
}

// MARK: - HTML-style <c> Override Tag Processing

/// One segment of an `<c>…</c>` style-linked colour run, produced by
/// `AssParse.processStyleOverrideTags`. The binary emits a 0x30-byte (6×8-byte,
/// i.e. 3-`String`) element per segment: the segment's own style token, the
/// preceding segment's style token (the back-link the second pass installs), and
/// the segment's text content. Consumed only by `SrtParse.parseSrtContent` and
/// `FFmpegSubtitleParse.convertSrtToAss` to rebuild coloured cue runs.
public struct StyleLinkSegment {
    /// This segment's `<c>` style token (the word between `<c` and `>`), or "".
    public var styleToken: String
    /// The previous segment's style token (forward/back chain link), or "".
    public var previousStyleToken: String
    /// The literal text content carried by this segment.
    public var content: String

    public init(styleToken: String, previousStyleToken: String, content: String) {
        self.styleToken = styleToken
        self.previousStyleToken = previousStyleToken
        self.content = content
    }
}

public extension AssParse {
    /// Scan an `<c>…</c>` HTML-style colour-tag token stream and return the
    /// style-linked segment array.
    ///
    /// RE: 0x10147bbb0 (AssParse.processStyleOverrideTags, 1.3.15, 1308B). This
    /// is NOT the standard ASS `{\tag}` override parser (that lives on `String`
    /// below). The binary drives an `NSScanner` whose `charactersToBeSkipped` is
    /// `CharacterSet.newlines`, repeatedly scanning the open-tag literal `<c>`
    /// (word constant `0x3e633c3e`) and close-tag literal `</c>`
    /// (`0x3e632f3c`). During the forward pass it accumulates 0x20-byte
    /// intermediate elements `(styleToken, content)`; a second reverse pass
    /// rewrites them into 0x30-byte output elements that additionally carry the
    /// preceding element's style token (the back-link). The only two callers are
    /// `SrtParse.parseSrtContent` (0x101481288) and
    /// `FFmpegSubtitleParse.convertSrtToAss` (0x101480414).
    func processStyleOverrideTags(_ content: String) -> [StyleLinkSegment] {
        let scanner = Scanner(string: content)
        scanner.charactersToBeSkipped = .newlines

        // Forward pass: collect (styleToken, content) pairs. `currentStyle` is
        // the style token last opened by `<c…>`; text scanned before any tag
        // carries an empty token.
        var intermediate = [(style: String, text: String)]()
        var currentStyle = ""

        while !scanner.isAtEnd {
            if scanner.scanString("<c") != nil {
                // Inside an `<c…>` open tag: capture up to the closing `>` as the
                // style token, then consume the `>`.
                let token = scanner.scanUpToString(">") ?? ""
                _ = scanner.scanString(">")
                currentStyle = token
                // Text that follows this open tag, up to the next delimiter.
                if let text = scanner.scanUpToCharacters(from: CharacterSet(charactersIn: "<")) {
                    intermediate.append((currentStyle, text))
                }
            } else if scanner.scanString("</c>") != nil {
                // Close tag resets to the un-styled token; any trailing text
                // after the close is captured against the empty style.
                currentStyle = ""
                if let text = scanner.scanUpToCharacters(from: CharacterSet(charactersIn: "<")) {
                    intermediate.append(("", text))
                }
            } else if let text = scanner.scanUpToCharacters(from: CharacterSet(charactersIn: "<")) {
                intermediate.append((currentStyle, text))
            } else {
                // No delimiter and no remaining content on this line.
                _ = scanner.scanCharacter()
            }
        }

        guard !intermediate.isEmpty else {
            return []
        }

        // Reverse pass: walk the intermediate array back-to-front installing the
        // back-link (the preceding element's style token), matching the binary's
        // 0x20-byte → 0x30-byte transform, then restore forward order via
        // `reverseArray`.
        var reversedOutput = [StyleLinkSegment]()
        reversedOutput.reserveCapacity(intermediate.count)
        var previousStyle = ""
        for element in intermediate.reversed() {
            reversedOutput.append(StyleLinkSegment(
                styleToken: element.style,
                previousStyleToken: previousStyle,
                content: element.text
            ))
            previousStyle = element.style
        }
        // RE: AssImageParse.reverseArray — restore original document order.
        return reversedOutput.reversed()
    }

    /// Build `NSAttributedString` attributes (plus a `TextPosition`) from a
    /// parsed `[V4+ Styles]` style dictionary.
    ///
    /// RE: 0x10147924c (AssParse.buildAttributedStringAttrsFromStyle, 1.3.15,
    /// 4696B, LIVE vtable). The binary reads the style dictionary keys directly:
    /// Fontname + Fontsize (→ `UIFont`, falling back to `systemFont`), Angle
    /// (→ rotation via `CGAffineTransformMakeRotation` on the font descriptor),
    /// Bold/Italic/Underline/StrikeOut (SSA truth value is the string `"-1"`,
    /// not `"1"`), PrimaryColour → `.foregroundColor`, BorderStyle == "1" →
    /// Outline → `.strokeWidth` (negative) + OutlineColour → `.strokeColor` and
    /// BackColour + Shadow → `NSShadow`, Alignment + MarginL/R/V →
    /// `TextPosition`. This is the converter counterpart of the inverse
    /// `[String: String].parseASSStyle()` builder below.
    func buildAttributedStringAttrsFromStyle(_ style: [String: String]) -> ([NSAttributedString.Key: Any], TextPosition) {
        var attributes: [NSAttributedString.Key: Any] = [:]
        if let fontName = style["Fontname"], let fontSize = style["Fontsize"].flatMap(Double.init) {
            var font = UIFont(name: fontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
            if let degrees = style["Angle"].flatMap(Double.init), degrees != 0 {
                let radians = CGFloat(degrees * .pi / 180.0)
                #if !canImport(UIKit)
                // macOS/AppKit: NSFontDescriptor uses AffineTransform.
                let matrix = AffineTransform(rotationByRadians: radians)
                #else
                // iOS/tvOS/UIKit: UIFontDescriptor uses CGAffineTransform.
                let matrix = CGAffineTransform(rotationAngle: radians)
                #endif
                let fontDescriptor = UIFontDescriptor(name: fontName, matrix: matrix)
                font = UIFont(descriptor: fontDescriptor, size: font.pointSize) ?? font
            }
            attributes[.font] = font
        }
        if let assColor = style["PrimaryColour"] {
            attributes[.foregroundColor] = UIColor(assColor: assColor)
        }
        // SSA boolean fields are the literal string "-1" for true.
        if style["Bold"] == "-1" {
            attributes[.expansion] = 1
        }
        if style["Italic"] == "-1" {
            attributes[.obliqueness] = 1
        }
        if style["Underline"] == "-1" {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if style["StrikeOut"] == "-1" {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if let spacing = style["Spacing"].flatMap(Double.init) {
            attributes[.kern] = CGFloat(spacing)
        }
        if style["BorderStyle"] == "1" {
            if let strokeWidth = style["Outline"].flatMap(Double.init), strokeWidth > 0 {
                attributes[.strokeWidth] = -strokeWidth
                if let assColor = style["OutlineColour"] {
                    attributes[.strokeColor] = UIColor(assColor: assColor)
                }
            }
            if let assColor = style["BackColour"],
               let shadowOffset = style["Shadow"].flatMap(Double.init),
               shadowOffset > 0
            {
                let shadow = NSShadow()
                shadow.shadowOffset = CGSize(width: CGFloat(shadowOffset), height: CGFloat(shadowOffset))
                shadow.shadowBlurRadius = shadowOffset
                shadow.shadowColor = UIColor(assColor: assColor)
                attributes[.shadow] = shadow
            }
        }
        var textPosition = TextPosition()
        textPosition.ass(alignment: style["Alignment"])
        if let marginL = style["MarginL"].flatMap(Double.init) {
            textPosition.leftMargin = CGFloat(marginL)
        }
        if let marginR = style["MarginR"].flatMap(Double.init) {
            textPosition.rightMargin = CGFloat(marginR)
        }
        if let marginV = style["MarginV"].flatMap(Double.init) {
            textPosition.verticalMargin = CGFloat(marginV)
        }
        return (attributes, textPosition)
    }

    /// Decode an embedded uuencoded font block from the ASS `[Fonts]` section
    /// into raw `Data`.
    ///
    /// RE: 0x101478c20 (AssParse.decodeUUEFontData, 1.3.15, 1580B, LIVE vtable).
    /// The binary splits the block into lines (`SubtitleDecode.splitString`),
    /// then decodes each line as the libass UU variant. The decode is keyed on
    /// fixed groups of **4 characters** (the outer loop computes the next group
    /// start via `index(offsetBy: 4, limitedBy:)` @0x102e170dc and the group
    /// length via `distance(from:to:)` @0x102e1710c). For each of a group's
    /// character positions the binary maps a printable scalar to `(value - 0x21)`,
    /// shifts it left by `(3 - position) * 6` and ORs it into a 24-bit
    /// accumulator. The CR/LF pair scalar (`0xa0d`) and any scalar `< 0x21` or
    /// `> 0xff` are skipped, but a skipped scalar **still consumes its position
    /// slot** (the inner loop's position counter advances regardless), so the
    /// shift stays aligned to the character index, not to the count of valid
    /// sextets. After each group the accumulator is emitted MSB-first with a
    /// byte count keyed on the *group length* (`x22`/`[sp,#0x48]`):
    ///   length 1 or 2 → 1 byte (bits 23..16);
    ///   length 3      → 2 bytes (adds bits 15..8);
    ///   length 4      → 3 bytes (adds bits 7..0).
    /// Returns nil when the line split yields nothing.
    func decodeUUEFontData(_ block: String) -> Data? {
        // The binary delegates line-splitting to `SubtitleDecode.splitString`
        // @0x10144d558 (MEPlayer/SubtitleDecode.swift, a different cluster not in
        // scope here). That helper splits on newlines; we inline an equivalent
        // newline split so this parser has no hard dependency on an
        // as-yet-unreconstructed symbol. See CROSS-FILE note in the agent report.
        let lines = block.split(whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else {
            return nil
        }
        var output = Data()
        for line in lines {
            // Walk the line in fixed windows of up to 4 characters, mirroring the
            // binary's outer `do…while` that steps the cursor by
            // `index(offsetBy: 4, limitedBy: endIndex)`. The final window may hold
            // 1–4 characters.
            let scalars = Array(line.unicodeScalars)
            var groupStart = 0
            while groupStart < scalars.count {
                let groupEnd = min(groupStart + 4, scalars.count)
                let groupLength = groupEnd - groupStart

                // Accumulate this group's sextets into a 24-bit register. The
                // shift is driven by the character's *position within the group*
                // (0→18, 1→12, 2→6, 3→0); skipped characters still consume their
                // slot, so a CR/LF or non-printable byte leaves a zero sextet at
                // that position rather than shifting later bytes up.
                var accumulator: UInt32 = 0
                for position in 0 ..< groupLength {
                    let value = scalars[groupStart + position].value
                    // RE: the binary special-cases the CR/LF pair scalar 0xa0d and
                    // any scalar outside [0x21, 0xff]; all are skipped (contribute
                    // a zero sextet) but still advance the position slot.
                    guard value != 0xa0d, value >= 0x21, value <= 0xff else {
                        continue
                    }
                    let sextet = (value &- 0x21) & 0x3f
                    let shift = (3 - position) * 6
                    accumulator |= sextet << UInt32(shift)
                }

                // Emit MSB-first, with the byte count keyed on the group length
                // exactly as the binary does:
                //   length >= 1 → bits 23..16 (always);
                //   length >= 3 → bits 15..8;
                //   length == 4 → bits 7..0.
                // Note length 2 still emits only one byte (the binary's guard is
                // `2 < groupLength` for the second byte).
                output.append(UInt8((accumulator >> 16) & 0xff))
                if groupLength > 2 {
                    output.append(UInt8((accumulator >> 8) & 0xff))
                    if groupLength == 4 {
                        output.append(UInt8(accumulator & 0xff))
                    }
                }

                groupStart = groupEnd
            }
        }
        return output
    }
}

// swiftlint:disable cyclomatic_complexity
extension String {
    func build(textPosition: inout TextPosition, attributed: [NSAttributedString.Key: Any]? = nil) -> NSAttributedString {
        let lineCodes = splitStyle()
        let attributedStr = NSMutableAttributedString()
        var attributed = attributed ?? [:]
        for lineCode in lineCodes {
            attributedStr.append(lineCode.0.parseStyle(attributes: &attributed, style: lineCode.1, textPosition: &textPosition))
        }
        return attributedStr
    }

    /// Split a line into `(text, styleBlock)` runs on standard ASS `{\tag}`
    /// override blocks. This is the upstream `{\tag}` override system and is
    /// distinct from the `<c>…</c>` HTML colour stream owned by
    /// `AssParse.processStyleOverrideTags` (0x10147bbb0); `<…>` is left as
    /// literal text here so the two override systems do not collide.
    func splitStyle() -> [(String, String?)] {
        let scanner = Scanner(string: self)
        scanner.charactersToBeSkipped = nil
        var result = [(String, String?)]()
        var style: String?
        while !scanner.isAtEnd {
            if scanner.scanString("{") != nil {
                style = scanner.scanUpToString("}")
                _ = scanner.scanString("}")
            } else {
                // Scan text up to the next `{` override block.
                let remaining = self[scanner.currentIndex...]
                if let nextBrace = remaining.firstIndex(of: "{"), nextBrace > scanner.currentIndex {
                    let text = String(self[scanner.currentIndex..<nextBrace])
                    scanner.currentIndex = nextBrace
                    result.append((text, style))
                } else if let text = scanner.scanUpToCharacters(from: .newlines) {
                    result.append((text, style))
                } else {
                    _ = scanner.scanCharacter()
                }
            }
        }
        return result
    }

    func parseStyle(attributes: inout [NSAttributedString.Key: Any], style: String?, textPosition: inout TextPosition) -> NSAttributedString {
        guard let style else {
            return NSAttributedString(string: self, attributes: attributes)
        }
        var fontName: String?
        var fontSize: Float?
        let subStyleArr = style.components(separatedBy: "\\")
        var shadow = attributes[.shadow] as? NSShadow
        for item in subStyleArr {
            let itemStr = item.replacingOccurrences(of: " ", with: "")
            let scanner = Scanner(string: itemStr)
            let char = scanner.scanCharacter()
            switch char {
            case "a":
                let char = scanner.scanCharacter()
                if char == "n" {
                    textPosition.ass(alignment: scanner.scanUpToCharacters(from: .newlines))
                }
            case "b":
                attributes[.expansion] = scanner.scanFloat()
            case "c":
                attributes[.foregroundColor] = scanner.scanUpToCharacters(from: .newlines).flatMap(UIColor.init(assColor:))
            case "f":
                let char = scanner.scanCharacter()
                if char == "n" {
                    fontName = scanner.scanUpToCharacters(from: .newlines)
                } else if char == "s" {
                    fontSize = scanner.scanFloat()
                }
            case "i":
                attributes[.obliqueness] = scanner.scanFloat()
            case "s":
                if scanner.scanString("had") != nil {
                    if let size = scanner.scanFloat() {
                        shadow = shadow ?? NSShadow()
                        shadow?.shadowOffset = CGSize(width: CGFloat(size), height: CGFloat(size))
                        shadow?.shadowBlurRadius = CGFloat(size)
                    }
                    attributes[.shadow] = shadow
                } else {
                    attributes[.strikethroughStyle] = scanner.scanInt()
                }
            case "u":
                attributes[.underlineStyle] = scanner.scanInt()
            case "1", "2", "3", "4":
                let twoChar = scanner.scanCharacter()
                if twoChar == "c" {
                    let color = scanner.scanUpToCharacters(from: .newlines).flatMap(UIColor.init(assColor:))
                    if char == "1" {
                        attributes[.foregroundColor] = color
                    } else if char == "2" {
                        // 还不知道这个要设置到什么颜色上
//                        attributes[.backgroundColor] = color
                    } else if char == "3" {
                        attributes[.strokeColor] = color
                    } else if char == "4" {
                        shadow = shadow ?? NSShadow()
                        shadow?.shadowColor = color
                        attributes[.shadow] = shadow
                    }
                }
            default:
                break
            }
        }
        // Apply font attributes if available
        if let fontName, let fontSize {
            let font = UIFont(name: fontName, size: CGFloat(fontSize)) ?? UIFont.systemFont(ofSize: CGFloat(fontSize))
            attributes[.font] = font
        }
        return NSAttributedString(string: self, attributes: attributes)
    }
}

public extension [String: String] {
    func parseASSStyle() -> ASSStyle {
        var attributes: [NSAttributedString.Key: Any] = [:]
        if let fontName = self["Fontname"], let fontSize = self["Fontsize"].flatMap(Double.init) {
            var font = UIFont(name: fontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
            if let degrees = self["Angle"].flatMap(Double.init), degrees != 0 {
                let radians = CGFloat(degrees * .pi / 180.0)
                #if !canImport(UIKit)
                let matrix = AffineTransform(rotationByRadians: radians)
                #else
                let matrix = CGAffineTransform(rotationAngle: radians)
                #endif
                let fontDescriptor = UIFontDescriptor(name: fontName, matrix: matrix)
                font = UIFont(descriptor: fontDescriptor, size: fontSize) ?? font
            }
            attributes[.font] = font
        }
        // 创建字体样式
        if let assColor = self["PrimaryColour"] {
            attributes[.foregroundColor] = UIColor(assColor: assColor)
        }
        // 还不知道这个要设置到什么颜色上
        if let assColor = self["SecondaryColour"] {
//            attributes[.backgroundColor] = UIColor(assColor: assColor)
        }
        if self["Bold"] == "1" {
            attributes[.expansion] = 1
        }
        if self["Italic"] == "1" {
            attributes[.obliqueness] = 1
        }
        if self["Underline"] == "1" {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if self["StrikeOut"] == "1" {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }

//        if let scaleX = self["ScaleX"].flatMap(Double.init), scaleX != 100 {
//            attributes[.expansion] = scaleX / 100.0
//        }
//        if let scaleY = self["ScaleY"].flatMap(Double.init), scaleY != 100 {
//            attributes[.baselineOffset] = scaleY - 100.0
//        }

//        if let spacing = self["Spacing"].flatMap(Double.init) {
//            attributes[.kern] = CGFloat(spacing)
//        }

        if self["BorderStyle"] == "1" {
            if let strokeWidth = self["Outline"].flatMap(Double.init), strokeWidth > 0 {
                attributes[.strokeWidth] = -strokeWidth
                if let assColor = self["OutlineColour"] {
                    attributes[.strokeColor] = UIColor(assColor: assColor)
                }
            }
            if let assColor = self["BackColour"],
               let shadowOffset = self["Shadow"].flatMap(Double.init),
               shadowOffset > 0
            {
                let shadow = NSShadow()
                shadow.shadowOffset = CGSize(width: CGFloat(shadowOffset), height: CGFloat(shadowOffset))
                shadow.shadowBlurRadius = shadowOffset
                shadow.shadowColor = UIColor(assColor: assColor)
                attributes[.shadow] = shadow
            }
        }
        var textPosition = TextPosition()
        textPosition.ass(alignment: self["Alignment"])
        if let marginL = self["MarginL"].flatMap(Double.init) {
            textPosition.leftMargin = CGFloat(marginL)
        }
        if let marginR = self["MarginR"].flatMap(Double.init) {
            textPosition.rightMargin = CGFloat(marginR)
        }
        if let marginV = self["MarginV"].flatMap(Double.init) {
            textPosition.verticalMargin = CGFloat(marginV)
        }
        return ASSStyle(attrs: attributes, textPosition: textPosition)
    }
    // swiftlint:enable cyclomatic_complexity
}

public class SrtParse: KSParseProtocol {
    /// Millisecond separator in the cue timestamp. SRT uses `,`; `VTTParse`
    /// overrides this with `.`. The binary's `parseEntry` normalises the SRT
    /// `,` form to the `.` form before parsing the duration.
    var cueSeparator: String { "," }

    public func canParse(scanner: Scanner) -> Bool {
        let result = scanner.string.contains(" --> ")
        if result {
            scanner.charactersToBeSkipped = nil
        }
        return result
    }

    /**
     45
     00:02:52,184 --> 00:02:53,617
     {\an4}慢慢来
     */
    /// RE: SrtParse.parseEntry @0x101482044 + SrtParse.parseSrtContent
    /// @0x101481288. `parsePart` reads one cue via `parseEntry`, then routes the
    /// cue body through `parseSrtContent` so that `<c>` colour runs are honoured.
    public func parsePart(scanner: Scanner) -> SubtitlePart? {
        guard let entry = parseEntry(scanner: scanner) else {
            return nil
        }
        let parts = parseSrtContent(start: entry.start, end: entry.end, text: entry.text)
        // `parsePart` returns a single merged part; `KSParseProtocol.parse`
        // accumulates across cues. When a `<c>` run produced multiple coloured
        // segments, fold them into one attributed string covering the cue.
        if parts.count == 1 {
            return parts.first
        }
        let merged = NSMutableAttributedString()
        for part in parts {
            if let attributed = part.text {
                merged.append(attributed)
            }
        }
        guard merged.length > 0 else {
            var textPosition = TextPosition()
            return SubtitlePart(entry.start.parseDuration(), entry.end.parseDuration(), attributedString: entry.text.build(textPosition: &textPosition))
        }
        return SubtitlePart(entry.start.parseDuration(), entry.end.parseDuration(), attributedString: merged)
    }

    /// Per-cue parser: skip the (optional) numeric index, locate the `-->`
    /// timestamp line, normalise the millisecond separator to `.`, and read the
    /// multi-line cue body up to the blank-line terminator.
    ///
    /// RE: 0x101482044 (SrtParse.parseEntry, 1.3.15, 1288B, 5 xrefs incl
    /// convertSrtToAss, parseSrtContent). The binary splits the timestamp line on
    /// `" --> "`, requires exactly two components, then runs
    /// `replacingOccurrences(of: ",", with: ".")` on both endpoints. Returns nil
    /// (the all-zero sentinel) when no valid `-->` line is found before EOF.
    func parseEntry(scanner: Scanner) -> (start: String, end: String, text: String)? {
        // Advance to the timestamp line. For SRT the binary skips the numeric
        // index; either way it scans lines until one contains " --> " (or EOF).
        var timeLine: String?
        repeat {
            timeLine = scanner.scanUpToCharacters(from: .newlines)
            _ = scanner.scanCharacters(from: .newlines)
            if timeLine?.contains(" --> ") ?? false {
                break
            }
        } while !scanner.isAtEnd
        guard let timeLine, timeLine.contains(" --> ") else {
            return nil
        }
        let endpoints = timeLine.components(separatedBy: " --> ")
        guard endpoints.count == 2 else {
            return nil
        }
        // Normalise the cue separator to `.` (no-op for VTT, `,`→`.` for SRT).
        let start = endpoints[0].replacingOccurrences(of: cueSeparator, with: ".")
        let end = endpoints[1].replacingOccurrences(of: cueSeparator, with: ".")

        _ = scanner.scanCharacters(from: .newlines)
        var text = ""
        var newLine: String? = nil
        repeat {
            if let str = scanner.scanUpToCharacters(from: .newlines) {
                text += str
            }
            newLine = scanner.scanCharacters(from: .newlines)
            if newLine == "\n" || newLine == "\r\n" {
                text += "\n"
            }
        } while newLine == "\n" || newLine == "\r\n"
        return (start, end, text)
    }

    /// Top-level SRT cue builder. Builds `SubtitlePart`s from a parsed cue,
    /// honouring `<c>` HTML colour runs.
    ///
    /// RE: 0x101481288 (SrtParse.parseSrtContent, 1.3.15, 800B). The binary
    /// tests the cue body for the `<c>` word constant (`0x3e633c3e`); if present
    /// it delegates to `AssParse.processStyleOverrideTags` (0x10147bbb0) and
    /// emits one `SubtitlePart` per returned style-link segment, otherwise it
    /// emits a single plain `SubtitlePart`. One of only two callers of
    /// `processStyleOverrideTags`.
    func parseSrtContent(start: String, end: String, text: String) -> [SubtitlePart] {
        let startTime = start.parseDuration()
        let endTime = end.parseDuration()
        guard text.contains("<c>") else {
            var textPosition = TextPosition()
            return [SubtitlePart(startTime, endTime, attributedString: text.build(textPosition: &textPosition))]
        }
        let segments = AssParse().processStyleOverrideTags(text)
        guard !segments.isEmpty else {
            var textPosition = TextPosition()
            return [SubtitlePart(startTime, endTime, attributedString: text.build(textPosition: &textPosition))]
        }
        return segments.map { segment in
            var textPosition = TextPosition()
            // Re-emit the segment content through the standard `{\tag}` builder;
            // the `<c>` colour token itself is preserved on the segment for the
            // libass / convertSrtToAss bridge.
            let attributed = segment.content.build(textPosition: &textPosition)
            return SubtitlePart(startTime, endTime, attributedString: attributed)
        }
    }

    /// Strip HTML tags from an SRT cue body using a regular expression,
    /// replacing each matched tag with a single space.
    ///
    /// RE: 0x1014815a8 (SrtParse.cleanupTags, 1.3.15, 1052B, 2 xrefs incl
    /// convertSrtToAss). The binary builds an `NSRegularExpression`, runs
    /// `matches(in:options:range:)` over the whole string, then walks the matches
    /// in reverse replacing each matched range with `" "`.
    func cleanupTags(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) else {
            return text
        }
        var result = text
        let fullRange = NSRange(result.startIndex..., in: result)
        let matches = regex.matches(in: result, options: [], range: fullRange)
        // Reverse iteration keeps earlier ranges valid as we mutate.
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: " ")
        }
        return result
    }

    /// Synthesise an ASS `[V4+ Styles]` block (Format line + a single `Default`
    /// style) for the SRT → ASS bridge.
    ///
    /// RE: 0x1014819c4 (SrtParse.buildDefaultStyleHeader, 1.3.15, 1664B, 3 xrefs
    /// incl convertSrtToAss). The binary assembles the V4+ field list — Name
    /// "Default", Fontname "SF Pro", a computed Fontsize ((base + 5) × scale),
    /// `%08X`-formatted Primary/Secondary/Outline/Back colours, Bold/Italic flags,
    /// fixed Underline/StrikeOut/ScaleX(100)/ScaleY(100)/Spacing/Angle, BorderStyle
    /// 1, Outline/Shadow widths, Alignment 2, fixed margins, and Encoding 1 — then
    /// joins them with "," and prefixes "Style: ".
    func buildDefaultStyleHeader(fontSize: Double = 18, scale: Double = 1.0) -> String {
        let computedSize = Int((fontSize + 5.0) * scale)
        // libass V4+ colours are &HAABBGGRR; the binary formats each via %08X.
        let primary = String(format: "&H%08X", 0x00FF_FFFF)
        let secondary = String(format: "&H%08X", 0x0000_00FF)
        let outline = String(format: "&H%08X", 0x0000_0000)
        let back = String(format: "&H%08X", 0x0000_0000)
        let fields: [String] = [
            "Default",        // Name
            "SF Pro",         // Fontname
            "\(computedSize)", // Fontsize
            primary,          // PrimaryColour
            secondary,        // SecondaryColour
            outline,          // OutlineColour
            back,             // BackColour
            "0",              // Bold
            "0",              // Italic
            "0",              // Underline
            "0",              // StrikeOut
            "100",            // ScaleX
            "100",            // ScaleY
            "0",              // Spacing
            "0",              // Angle
            "1",              // BorderStyle
            outlineWidthDescription, // Outline
            shadowWidthDescription,  // Shadow
            "2",              // Alignment
            marginDescription,       // MarginL
            marginDescription,       // MarginR
            marginDescription,       // MarginV
            "1",              // Encoding
        ]
        return "Style: " + fields.joined(separator: ",")
    }

    /// Default outline width string used by `buildDefaultStyleHeader`. The binary
    /// reads a stored `Double` and emits its `description`; reconstructed as a
    /// constant default.
    private var outlineWidthDescription: String { Double(2).description }
    private var shadowWidthDescription: String { Double(0).description }
    private var marginDescription: String { Double(10).description }
}

/// `VTTParse` is a subclass of `SrtParse` (types.json: `KSPlayer.VTTParse :
/// KSPlayer.SrtParse`). It reuses SRT's multi-line cue-body machinery and
/// differs only in the `WEBVTT` header detection and the `.` millisecond
/// separator. The shared async `parse(url:userAgent:)` dispatcher
/// (`parse_setup`/`checkExtAndDispatch`/`continuation`) lives on the
/// `KSParseProtocol` extension below and is inherited.
public class VTTParse: SrtParse {
    override var cueSeparator: String { "." }

    /**
     00:00.430 --> 00:03.380
     简中封装 by Q66
     */
    /// RE: VTTParse uses the shared SrtParse cue machinery (parse_setup
    /// @0x1014825a8 → parse_checkExtAndDispatch @0x101482644 →
    /// parse_continuation @0x1014827c0). Only the header check differs.
    override public func canParse(scanner: Scanner) -> Bool {
        let result = scanner.scanString("WEBVTT")
        if result != nil {
            scanner.charactersToBeSkipped = nil
            return true
        } else {
            return false
        }
    }
}
