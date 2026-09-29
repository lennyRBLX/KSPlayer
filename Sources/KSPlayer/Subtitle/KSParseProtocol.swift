//
//  KSParseProtocol.swift
//  KSPlayer-7de52535
//
//  Created by kintan on 2018/8/7.
//
import CoreText
import Foundation
import SwiftUI

// FUN_101aa1e6c — the shared SrtParse/VTTParse cue scan. Skips lines until one contains " --> ", splits it
// `.components(separatedBy: " --> ")` (must be 2 parts), normalizes each comma-decimal to "." and trims the
// end's first space-token (WebVTT cue settings), then accumulates the following text lines (a `\n` per line
// break). Returns nil at end-of-input / a non-2-part timing line. Both parsePart bodies call this (one function).
private func scanSubtitleCue(_ scanner: Scanner) -> (start: String, end: String, text: String)? {
    var line: String?
    repeat {
        line = scanner.scanUpToCharacters(from: .newlines)
        _ = scanner.scanCharacters(from: .newlines)
    } while !(line?.contains(" --> ") ?? false) && !scanner.isAtEnd
    guard let line else { return nil }
    let timeArray = line.components(separatedBy: " --> ")
    guard timeArray.count == 2 else { return nil }
    let startString = timeArray[0].replacingOccurrences(of: ",", with: ".")
    // binary force-subscripts split[0] (traps on empty per FUN_1019f14c0 / SoftwareBreakpoint 0x101aa237c),
    // not `.first` — the split of a count==2 timeArray[1] is non-empty in practice.
    let endString = String(timeArray[1].split(separator: " ")[0]).replacingOccurrences(of: ",", with: ".")
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
    return (start: startString, end: endString, text: text)
}

// Build a text SubtitlePart (.right(SubtitleTextInfo)) — inlined per-body in the binary; a shared helper here.
private func makeTextSubtitlePart(start: Double, end: Double, text: String) -> SubtitlePart {
    // Forward SrtParse.parsePart 0x101aa0eb0 / VTTParse.parsePart 0x101aa1110 call the SRT/HTML tag helper
    // FUN_101a9bd1c for the cue text (no TextPosition / build(textPosition:) on this path).
    let textInfo = SubtitleTextInfo(
        text: text.parseHTMLTags(),
        position: nil, // SRT/VTT do not store textPosition — disasm-evidenced (SrtParse audit-confirmed)
        displaySize: nil,
        styleRole: .primary,
        usesForcedPosition: false
    )
    return SubtitlePart(start, end, render: .right(textInfo))
}

// [SubtitlePart]: KSSubtitleProtocol — WT 0x1041da3d8, async fp 0x10356ca60 → 0x101aa0e6c → FUN_101aa0cec.
//   Linear scan over the (sorted) parts: collect those covering query.time, stop at the first later start.
extension [SubtitlePart]: KSSubtitleProtocol {
    // ⚑[tool=member_surface ref=Array<SubtitlePart>.search(with:) result=Forward sync (no Ya); body has no swift_task_* call] — sync witness of the async req
    public func search(with query: KSSubtitleQuery) -> [SubtitlePart] {
        var result = [SubtitlePart]()
        for part in self {
            if part.start <= query.time, query.time < part.end {
                result.append(part)
            } else if query.time < part.start {
                break
            }
        }
        return result
    }
}

public class SrtParse: KSParseProtocol {
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
    public func parsePart(scanner: Scanner) -> [SubtitlePart] {
        // Forward @0x101aa0f30-0x101aa0f60 releases each cue string right after its use (start after
        // parseDuration, end after parseDuration, text after the tag parse): the tuple is destructured
        // into three independent lets. Binding `cue` and projecting keeps all three alive to the end.
        guard let (start, end, text) = scanSubtitleCue(scanner) else {
            return []
        }
        return [makeTextSubtitlePart(start: start.parseDuration(), end: end.parseDuration(), text: text)]
    }
    public static func parsePart(scanner: Scanner) -> (start: String, end: String, text: String)? {
        scanSubtitleCue(scanner)
    }
}
#if !canImport(UIKit)
import AppKit
#else
import UIKit
#endif
public protocol KSParseProtocol {
    func canParse(scanner: Scanner) -> Bool
    func parsePart(scanner: Scanner) -> [SubtitlePart]
    // Requirement is parse(url:scanner:) throws -> KSSubtitleProtocol: FFmpegSubtitleParse WT 0x1041da388 → 0x101a9eff4,
    //   SrtParse WT 0x1041da3e8 → default 0x101aa08c4.
    func parse(url: URL, scanner: Scanner) throws -> KSSubtitleProtocol
}

public extension KSOptions {
    // public: Forward exports the property descriptor `$s8KSPlayer9KSOptionsC14subtitleParsesSayAA15KSParseProtocol_pGvpZ`
    // (export trie) and reads the storage under swift_beginAccess in URL.parseSubtitle.
    @used nonisolated(unsafe) static var subtitleParses: [KSParseProtocol] = [AssParse(), VTTParse(), SrtParse()]
}

public extension String {}

public extension KSParseProtocol {
    // Default body @0x10002d9dc — 3 instructions, `adrp/ldr` the __got slot 0x104112d00 then `ret`.
    // That slot is a dyld bind to libswiftCore `__swiftEmptyArrayStorage` (`dyld_info -fixups`), so the
    // return really is the empty-array singleton and not a heap allocation: `[]`, nothing else.
    // Shared as the witness by every conformer that does not override it (FFmpegSubtitleParse slot 1,
    // AssImageParse — see those files).
    func parsePart(scanner: Scanner) -> [SubtitlePart] { [] }

    // Default @0x101aa08c4: the merged [SubtitlePart] is returned as the KSSubtitleProtocol existential.
    func parse(url _: URL, scanner: Scanner) throws -> KSSubtitleProtocol {
        var groups = [SubtitlePart]()

        while !scanner.isAtEnd {
            groups.append(contentsOf: parsePart(scanner: scanner))
        }
        groups = groups.mergeSortBottomUp { $0 < $1 }
        return groups
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

    // FUN_101a9bd1c (unnamed, 141 insns) — SRT/WebVTT cue text → attributed string: plain runs up to "<" are
    // appended as-is, "<font …>" goes through the font-tag scanner (FUN_101a9bf50), "<i>" / "</i>" are dropped,
    // anything else is taken up to the next newline.
    func parseHTMLTags() -> NSMutableAttributedString { // INFERRED name — Forward 0x101a9bd1c
        let attributedString = NSMutableAttributedString()
        let scanner = Scanner(string: self)
        scanner.charactersToBeSkipped = nil
        while !scanner.isAtEnd {
            if let text = scanner.scanUpToString("<") {
                attributedString.append(NSAttributedString(string: text))
            }
            if scanner.scanString("<font") != nil, let fontString = scanner.scanFontTag() {
                attributedString.append(fontString)
            } else if scanner.scanString("<i>") != nil {
            } else if scanner.scanString("</i>") != nil {
            } else if let text = scanner.scanUpToCharacters(from: .newlines) {
                attributedString.append(NSAttributedString(string: text))
            }
        }
        return attributedString
    }

    func splitStyle() -> [(String, String?)] {
        let scanner = Scanner(string: self)
        scanner.charactersToBeSkipped = nil
        var result = [(String, String?)]()
        var sytle: String?
        while !scanner.isAtEnd {
            if scanner.scanString("{") != nil {
                sytle = scanner.scanUpToString("}")
                _ = scanner.scanString("}")
            } else if let text = scanner.scanUpToString("{") {
                result.append((text, sytle))
            } else if let text = scanner.scanUpToCharacters(from: .newlines) {
                result.append((text, sytle))
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

extension Scanner {
    // FUN_101a9bf50 (unnamed, 1069 insns; self = scanner in x20) — the rest of a "<font" tag: face= / name=
    // (ASS-style "1c&H…" / "3c&H…" colours), color="#…" / color=#…, color="name" / color=name, then the
    // text up to "</font>" (an enclosing <i>…</i> makes the font italic).
    func scanFontTag() -> NSAttributedString? { // INFERRED name — Forward 0x101a9bf50
        var attributes = [NSAttributedString.Key: Any]()
        var fontName: String?
        if scanString(" face=\"") != nil, let face = scanUpToString("\""), scanString("\"") != nil {
            fontName = face
        }
        if scanString(" name=\"") != nil, let name = scanUpToString("\""), scanString("\"") != nil {
            if let range = name.range(of: "^([A-Za-z0-9]+)", options: .regularExpression) {
                fontName = String(name[range])
            }
            if let range = name.range(of: "1c&H[A-F0-9]{6}", options: .regularExpression) {
                attributes[.foregroundColor] = UIColor(assColor: String(name[range].dropFirst(4)))
            }
            if let range = name.range(of: "3c&H[A-F0-9]{6}", options: .regularExpression) {
                attributes[.strokeColor] = UIColor(assColor: String(name[range].dropFirst(4)))
            }
        }
        var font: UIFont?
        if let fontName {
            let fontSize = KSOptions.subtitleFontSize
            font = UIFont(name: fontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
        }
        if scanString(" color=\"#") != nil, let hex = scanInt(representation: .hexadecimal), scanString("\"") != nil {
            attributes[.foregroundColor] = UIColor(rgb: hex)
        }
        if scanString(" color=#") != nil, let hex = scanInt(representation: .hexadecimal) {
            attributes[.foregroundColor] = UIColor(rgb: hex)
        }
        if attributes[.foregroundColor] == nil {
            if scanString(" color=\"") != nil, let name = scanUpToString("\""), scanString("\"") != nil {
                attributes[.foregroundColor] = htmlNamedColor(name)
            } else if scanString(" color=") != nil, let name = scanUpToCharacters(from: CharacterSet(charactersIn: " >")) {
                attributes[.foregroundColor] = htmlNamedColor(name)
            }
        }
        _ = scanUpToString(">")
        guard scanString(">") != nil, var text = scanUpToString("</font>") else {
            return nil
        }
        _ = scanString("</font>")
        if text.hasPrefix("<i>"), text.hasSuffix("</i>") {
            text.removeFirst(3)
            text.removeLast(4)
            font = font?.italic
        }
        attributes[.font] = font
        return NSAttributedString(string: text, attributes: attributes)
    }
}

// FUN_101a9ebc4 (unnamed, 268 insns) — HTML colour name (lowercased) → UIColor, nil when unknown.
func htmlNamedColor(_ name: String) -> UIColor? { // INFERRED name — Forward 0x101a9ebc4
    switch name.lowercased() {
    case "white":
        return .white
    case "yellow":
        return .yellow
    case "red":
        return .red
    case "green":
        return .green
    case "blue":
        return .blue
    case "cyan":
        return .cyan
    case "magenta":
        return .magenta
    case "black":
        return .black
    case "orange":
        return .orange
    case "gray", "grey":
        return .gray
    case "purple":
        return .purple
    default:
        return nil
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

// §8.5 corrected: VTTParse superclass = SrtParse (descriptor SuperclassType@+0x14; recon/§8.5 guessed : KSParseProtocol).
public class VTTParse: SrtParse {
    override public func canParse(scanner: Scanner) -> Bool {
        // Forward unified canParse into a shared string-contains helper (FUN_101aa1068), parameterized by the
        // needle — SrtParse `contains(" --> ")`, VTTParse `contains("WEBVTT")` (NOT the base-original
        // scanString("WEBVTT") anchored check; the binary uses `scanner.string.contains`). audit-confirmed.
        let result = scanner.string.contains("WEBVTT")
        if result {
            scanner.charactersToBeSkipped = nil
        }
        return result
    }

    /**
     00:00.430 --> 00:03.380
     简中封装 by Q66
     */
    // Forward 1.3.17 VTTParse.parsePart (0x101aa1110): SAME cue scan as SrtParse (shared FUN_101aa1e6c), then —
    //   when the text has WebVTT inline-timestamp/class spans (`.contains("><c>")`) — split it into karaoke
    //   components and emit ONE SubtitlePart per component (a cue → multiple parts, which is why the return is
    //   [SubtitlePart]); otherwise emit a single part. Multi-part split = FUN_101a9b838 (vttCueComponents).
    override public func parsePart(scanner: Scanner) -> [SubtitlePart] {
        // Forward @0x101aa1160-0x101aa1184: start/end strings are released right after parseDuration →
        // destructured cue tuple (see SrtParse.parsePart). The map closure also destructures its element:
        // Forward's loop keeps the per-iteration `cmp x28,x8; b.cs brk` bounds check (0x101aa1210), which
        // swiftc emits for `{ (a, b, c) in }` but eliminates for a single `component in` parameter.
        guard let (start, end, text) = scanSubtitleCue(scanner) else {
            return []
        }
        let startTime = start.parseDuration()
        let endTime = end.parseDuration()
        if text.contains("><c>") {
            return vttCueComponents(text).map { (componentStart, componentEnd, componentText) in
                makeTextSubtitlePart(start: componentStart.map { $0.parseDuration() } ?? startTime,
                                     end: componentEnd.map { $0.parseDuration() } ?? endTime,
                                     text: componentText)
            }
        }
        return [makeTextSubtitlePart(start: startTime, end: endTime, text: text)]
    }

    // FUN_101a9b838 — WebVTT inline-timestamp (karaoke) cue splitter: `<HH:MM:SS.mmm><c>text</c>` segments →
    //   timed components; each component's end = the NEXT component's start timestamp (nil for the last).
    //   audit_workflow FAITHFUL (recheck differential-fuzzed ~1.7M inputs, 0 mismatches). removeLast() is
    //   UNCONDITIONAL per the binary (scanUpToString never returns a non-nil empty string, so it never traps).
    private func vttCueComponents(_ text: String) -> [(start: String?, end: String?, text: String)] {
        let scanner = Scanner(string: text)
        scanner.charactersToBeSkipped = .newlines
        var pairs = [(timestamp: String?, text: String)]()
        while !scanner.isAtEnd {
            var timestamp: String?
            while scanner.scanString("<") != nil {
                if var ts = scanner.scanUpToString("><c>") {
                    ts.removeLast()
                    timestamp = ts
                }
                _ = scanner.scanString("><c>")
                if scanner.isAtEnd { break }
            }
            guard let segText = scanner.scanUpToString("<") ?? scanner.scanUpToCharacters(from: .newlines) else {
                continue
            }
            pairs.append((timestamp, segText))
            _ = scanner.scanString("</c>")
        }
        return pairs.enumerated().map { index, pair in
            (start: pair.timestamp,
             end: index + 1 < pairs.count ? pairs[index + 1].timestamp : nil,
             text: pair.text)
        }
    }
}

// Forward 0x1019e7290 / 0x1019e7374 (exported `$sSa8KSPlayers5UInt8VRszlE6appendyys6UInt16VF` / `…UInt32VF`):
// little-endian byte appends through inout self (one append per byte, low byte first).
public extension Array where Element == UInt8 {
    mutating func append(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func append(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }
}
