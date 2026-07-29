//
//  KSParseProtocol.swift
//  KSPlayer-7de52535
//
//  Created by kintan on 2018/8/7.
//
import CoreText
import Foundation
import SwiftUI
#if !canImport(UIKit)
import AppKit
#else
import UIKit
#endif
public protocol KSParseProtocol {
    func canParse(scanner: Scanner) -> Bool
    func parsePart(scanner: Scanner) -> [SubtitlePart]
    func parse(scanner: Scanner) -> [SubtitlePart]
}

public extension KSOptions {
    internal nonisolated(unsafe) static var subtitleParses: [KSParseProtocol] = [AssParse(), VTTParse(), SrtParse()]
}

public extension String {}

public extension KSParseProtocol {
    // Default body @0x10002d9dc — 3 instructions, `adrp/ldr` the __got slot 0x104112d00 then `ret`.
    // That slot is a dyld bind to libswiftCore `__swiftEmptyArrayStorage` (`dyld_info -fixups`), so the
    // return really is the empty-array singleton and not a heap allocation: `[]`, nothing else.
    // Shared as the witness by every conformer that does not override it (FFmpegSubtitleParse slot 1,
    // AssImageParse — see those files).
    func parsePart(scanner: Scanner) -> [SubtitlePart] { [] }

    func parse(scanner: Scanner) -> [SubtitlePart] {
        var groups = [SubtitlePart]()

        while !scanner.isAtEnd {
            groups.append(contentsOf: parsePart(scanner: scanner))
        }
        groups = groups.mergeSortBottomUp { $0 < $1 }
        return groups
    }
}

public class AssParse: KSParseProtocol {
    private var styleMap: [String: ASSStyle]? // §8.3 [String:ASSStyle]? — populated lazily in canParse
    private var eventKeys: [String] = ["Layer", "Start", "End", "Style", "Name", "MarginL", "MarginR", "MarginV", "Effect", "Text"]
    private var displaySize: CGSize = .zero
    // Forward 1.3.17 AssParse.canParse (FUN_101a97464, ~1048i) — REORGANIZED vs the base original:  ⚑[tool=resolve_fun_pins ref=FUN_101a97464:0x101a97464 result=RESOLVES_UNIQUELY] = KSPlayer.AssParse.canParse(scanner: __C.NSScanner) -> Swift.Bool
    //   resets styleMap, prechecks `scanner.string.contains("Format: Name,")` (NOT the base
    //   `scanString("[Script Info]")`), writes PlayResX/Y DIRECTLY into displaySize with 384x288
    //   defaults, COLLECTS the Style: lines and processes them AFTER the [Fonts] embedded-font
    //   extraction (uudecode -> NSTemporaryDirectory write -> CTFontManagerRegisterFontsForURL),
    //   then reads the [Events] Format keys. audit_workflow + P42-disasm verified (session 18).
    public func canParse(scanner: Scanner) -> Bool {
        styleMap = [:]
        guard scanner.string.contains("Format: Name,") else {
            return false
        }
        while scanner.scanString("Format:") == nil {
            if scanner.scanString("PlayResX:") != nil {
                displaySize.width = CGFloat(scanner.scanFloat() ?? 0)
            } else if scanner.scanString("PlayResY:") != nil {
                displaySize.height = CGFloat(scanner.scanFloat() ?? 0)
            } else {
                _ = scanner.scanUpToCharacters(from: .newlines)
            }
        }
        if displaySize.width == 0 {
            displaySize.width = 384
        }
        if displaySize.height == 0 {
            displaySize.height = 288
        }
        guard let keyLine = scanner.scanUpToCharacters(from: .newlines) else {
            return false
        }
        let keys = keyLine.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        // Collect the Style: lines; the binary processes them AFTER the [Fonts] block below.
        var styleLines = [String]()
        while scanner.scanString("Style:") != nil {
            if let line = scanner.scanUpToCharacters(from: .newlines) {
                styleLines.append(line)
            }
        }
        // [Fonts] embedded-font extraction (Forward 1.3.17 addition; NOT in the base original).
        if scanner.scanString("[Fonts]") != nil, let fontBlock = scanner.scanUpToString("[Events]") {
            let fontScanner = Scanner(string: fontBlock)
            while fontScanner.scanString("fontname:") != nil {
                guard let fontName = fontScanner.scanUpToCharacters(from: .newlines) else {
                    break
                }
                guard let encoded = fontScanner.scanUpToString("fontname:") else {
                    // binary loops back to scanString("fontname:") on a nil body (skips an empty
                    // entry), NOT break — FUN_101a97464 @390-396 (audit_workflow session 18).  ⚑[tool=resolve_fun_pins ref=FUN_101a97464:0x101a97464 result=RESOLVES_UNIQUELY] = KSPlayer.AssParse.canParse(scanner: __C.NSScanner) -> Swift.Bool
                    continue
                }
                // Path = NSTemporaryDirectory() + "fontsDir/" + fontName (3-part, 2× String.append —
                // P42-disasm-confirmed 0x101a97c6c-cfc: tmp @0x10345ac84, "fontsDir/" small-string @0x101a97c8c). ⚑ URL init form (fileURLWithPath vs string:) minor.
                let url = URL(fileURLWithPath: NSTemporaryDirectory() + "fontsDir/" + fontName)
                try? uudecode(encoded).write(to: url)
                // scope .process, error nil — P42-disasm-confirmed `CTFontManagerRegisterFontsForURL(url, w1=1, x2=0)` @0x101a97d6c-d70.
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        // Process the collected Style: lines into styleMap.
        var styleMap = [String: ASSStyle]()
        for line in styleLines {
            let values = line.components(separatedBy: ",")
            guard let name = values.first else {
                continue
            }
            var dic = [String: String]()
            for i in 1 ..< keys.count {
                dic[keys[i]] = values[i]
            }
            styleMap[name] = dic.parseASSStyle()
        }
        self.styleMap = styleMap
        _ = scanner.scanString("[Events]")
        if scanner.scanString("Format: ") != nil {
            guard let eventLine = scanner.scanUpToCharacters(from: .newlines) else {
                return false
            }
            eventKeys = eventLine.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return true
    }

    // FUN_101a984c8 — UUdecode of the ASS `[Fonts]` embedded-font data (Forward 1.3.17 addition;
    // the source symbol name is STRIPPED, ⚑ inferred). This is the ASS/SSA embedded-font encoding
    // (byte = char - 33, i.e. `(scalar &+ 31) & 63`; four 6-bit values pack big-endian into three
    // bytes; no per-line length prefix), producing the raw font Data written to the temp file.
    private func uudecode(_ string: String) -> Data {
        var data = Data()
        for line in string.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let scalars = Array(line.unicodeScalars)
            func sixBit(_ n: Int) -> UInt32 {
                guard n < scalars.count else { return 0 }
                let v = scalars[n].value
                return v > 0x20 ? ((v &+ 31) & 63) : 0
            }
            var i = 0
            while i < scalars.count {
                let group = min(4, scalars.count - i)
                let acc = sixBit(i) << 18 | sixBit(i + 1) << 12 | sixBit(i + 2) << 6 | sixBit(i + 3)
                data.append(UInt8((acc >> 16) & 0xff))
                if group > 2 {
                    data.append(UInt8((acc >> 8) & 0xff))
                }
                if group > 3 {
                    data.append(UInt8(acc & 0xff))
                }
                i += 4
            }
        }
        return data
    }

    // Dialogue: 0,0:12:37.73,0:12:38.83,Aki Default,,0,0,0,,{\be8}原来如此
    public func parsePart(scanner: Scanner) -> [SubtitlePart] {
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
                return []
            } else {
                start = 0
                end = 0
            }
        }
        var attributes: [NSAttributedString.Key: Any]?
        var textPosition: TextPosition
        if let style = dic["Style"], let assStyle = styleMap?[style] {
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
            return []
        }
        text = text.replacingOccurrences(of: "\\N", with: "\n")
        text = text.replacingOccurrences(of: "\\n", with: "\n")
        text = text.replacingOccurrences(of: "\\h", with: " ") // ASS hard-space (FUN_101a99ef0 @472, "\h"->" "; base original lacked it)  ⚑[tool=resolve_fun_pins ref=FUN_101a99ef0:0x101a99ef0 result=RESOLVES_UNIQUELY] = KSPlayer.AssParse.parsePart(scanner: __C.NSScanner) -> [KSPlayer.SubtitlePart]
        let textInfo = SubtitleTextInfo(
            text: text.build(textPosition: &textPosition, attributed: attributes),
            position: textPosition, // ASS textPosition (audit-confirmed)
            displaySize: displaySize, // = self.displaySize (ASS PlayResX/Y); binary copies self+0x20/+0x28 @FUN_101a99ef0:487-490 (NOT nil)  ⚑[tool=resolve_fun_pins ref=FUN_101a99ef0:0x101a99ef0 result=RESOLVES_UNIQUELY] = KSPlayer.AssParse.parsePart(scanner: __C.NSScanner) -> [KSPlayer.SubtitlePart]
            styleRole: .primary, // =0 (audit-confirmed)
            usesForcedPosition: false // =0 (audit-confirmed)
        )
        return [SubtitlePart(start, end, render: .right(textInfo))]
    }
}

public struct ASSStyle {
    let attrs: [NSAttributedString.Key: Any]
    let textPosition: TextPosition
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
        guard let cue = scanSubtitleCue(scanner) else {
            return []
        }
        let start = cue.start.parseDuration()
        let end = cue.end.parseDuration()
        if cue.text.contains("><c>") {
            return vttCueComponents(cue.text).map { component in
                makeTextSubtitlePart(start: component.start.map { $0.parseDuration() } ?? start,
                                     end: component.end.map { $0.parseDuration() } ?? end,
                                     text: component.text)
            }
        }
        return [makeTextSubtitlePart(start: start, end: end, text: cue.text)]
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
    var textPosition = TextPosition()
    let textInfo = SubtitleTextInfo(
        text: text.build(textPosition: &textPosition),
        position: nil, // SRT/VTT do not store textPosition — disasm-evidenced (SrtParse audit-confirmed)
        displaySize: nil,
        styleRole: .primary,
        usesForcedPosition: false
    )
    return SubtitlePart(start, end, render: .right(textInfo))
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
        guard let cue = scanSubtitleCue(scanner) else {
            return []
        }
        return [makeTextSubtitlePart(start: cue.start.parseDuration(), end: cue.end.parseDuration(), text: cue.text)]
    }
}
