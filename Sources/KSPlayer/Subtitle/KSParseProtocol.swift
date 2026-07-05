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
    func parsePart(scanner: Scanner) -> [SubtitlePart]
    func parse(scanner: Scanner) -> [SubtitlePart]
}

public extension KSOptions {
    nonisolated(unsafe) static var subtitleParses: [KSParseProtocol] = [AssParse(), VTTParse(), SrtParse()]
}

public extension String {}

public extension KSParseProtocol {
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
    private var eventKeys = ["Layer", "Start", "End", "Style", "Name", "MarginL", "MarginR", "MarginV", "Effect", "Text"]
    private var displaySize: CGSize = .zero
    // ⚑ PARTIAL → P4 M2: canParse (FUN_101a97464 ~1048i) + parsePart (FUN_101a99ef0 ~911i) reconstruct the FAITHFUL
    //   CORE ASS parsing (base-original-derived + binary-structure-confirmed: [Script Info]/PlayResX·Y→displaySize/
    //   Style:→styleMap/[Events]→eventKeys/Dialogue→SubtitlePart). The Forward binary canParse ALSO references
    //   _NSTemporaryDirectory + URL/NSURL/initWithString: + helpers (FUN_1019ac888/1019afaf8/1019c2014/101a984c8/
    //   101a989b0) = a Forward ADDITION (likely ASS embedded-font extraction to a temp dir) NOT yet reconstructed.
    //   render:Either field values (position/displaySize/styleRole/usesForcedPosition) audit-flagged below.
    public func canParse(scanner: Scanner) -> Bool {
        guard scanner.scanString("[Script Info]") != nil else {
            return false
        }
        var playResX = Float(0.0)
        var playResY = Float(0.0)
        while scanner.scanString("Format:") == nil {
            if scanner.scanString("PlayResX:") != nil {
                playResX = scanner.scanFloat() ?? 0
            } else if scanner.scanString("PlayResY:") != nil {
                playResY = scanner.scanFloat() ?? 0
            } else {
                _ = scanner.scanUpToCharacters(from: .newlines)
            }
        }
        displaySize = CGSize(width: CGFloat(playResX), height: CGFloat(playResY))
        guard var keys = scanner.scanUpToCharacters(from: .newlines)?.components(separatedBy: ",") else {
            return false
        }
        keys = keys.map { $0.trimmingCharacters(in: .whitespaces) }
        var styleMap = [String: ASSStyle]()
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
        self.styleMap = styleMap
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
        let textInfo = SubtitleTextInfo(
            text: text.build(textPosition: &textPosition, attributed: attributes),
            position: textPosition, // ⚑ ASS stores textPosition (original `part.textPosition = textPosition`) → M2 audit-verify
            displaySize: nil, // ⚑ render:Either field → M2 audit-verify (FUN_101a99ef0)
            styleRole: .primary, // ⚑ parse produces primary → M2 audit-verify
            usesForcedPosition: false // ⚑ → M2 audit-verify
        )
        return [SubtitlePart(start: start, end: end, render: .right(textInfo))]
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
        let result = scanner.scanString("WEBVTT")
        if result != nil {
            scanner.charactersToBeSkipped = nil
            return true
        } else {
            return false
        }
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
        var decimal: String?
        repeat {
            decimal = scanner.scanUpToCharacters(from: .newlines)
            _ = scanner.scanCharacters(from: .newlines)
        } while decimal.flatMap(Int.init) == nil
        let startString = scanner.scanUpToString("-->")
        _ = scanner.scanString("-->")
        guard let startString, let endString = scanner.scanUpToCharacters(from: .newlines) else {
            return []
        }
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
        let start = startString.parseDuration()
        let end = endString.parseDuration()
        func makePart(start: Double, end: Double, text: String) -> SubtitlePart {
            var textPosition = TextPosition()
            let textInfo = SubtitleTextInfo(
                text: text.build(textPosition: &textPosition),
                position: nil, // VTT does not store textPosition — disasm-evidenced (SrtParse audit-confirmed)
                displaySize: nil,
                styleRole: .primary,
                usesForcedPosition: false
            )
            return SubtitlePart(start: start, end: end, render: .right(textInfo))
        }
        if text.contains("><c>") {
            return vttCueComponents(text).map { component in
                makePart(start: component.start.map { $0.parseDuration() } ?? start,
                         end: component.end.map { $0.parseDuration() } ?? end,
                         text: component.text)
            }
        }
        return [makePart(start: start, end: end, text: text)]
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
        var decimal: String?
        repeat {
            decimal = scanner.scanUpToCharacters(from: .newlines)
            _ = scanner.scanCharacters(from: .newlines)
        } while decimal.flatMap(Int.init) == nil
        let startString = scanner.scanUpToString("-->")
        // skip spaces and newlines by default.
        _ = scanner.scanString("-->")
        if let startString,
           let endString = scanner.scanUpToCharacters(from: .newlines)
        {
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
            var textPosition = TextPosition()
            let textInfo = SubtitleTextInfo(
                text: text.build(textPosition: &textPosition),
                position: nil, // SRT does not store textPosition (original discarded it) — disasm-evidenced (zeroed region)
                displaySize: nil,
                styleRole: .primary,
                usesForcedPosition: false
            )
            return [SubtitlePart(start: startString.parseDuration(), end: endString.parseDuration(), render: .right(textInfo))]
        }
        return []
    }
}
