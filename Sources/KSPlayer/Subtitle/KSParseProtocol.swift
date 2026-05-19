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
    static var subtitleParses: [KSParseProtocol] = [AssParse(), VTTParse(), SrtParse()]
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
}

public class AssParse: KSParseProtocol {
    private var styleMap = [String: ASSStyle]()
    private var eventKeys = ["Layer", "Start", "End", "Style", "Name", "MarginL", "MarginR", "MarginV", "Effect", "Text"]
    private var playResX = Float(1280.0)
    private var playResY = Float(720.0)
    public func canParse(scanner: Scanner) -> Bool {
        guard scanner.scanString("[Script Info]") != nil else {
            return false
        }
        while scanner.scanString("Format:") == nil {
            if scanner.scanString("PlayResX:") != nil {
                playResX = scanner.scanFloat() ?? 0
            } else if scanner.scanString("PlayResY:") != nil {
                playResY = scanner.scanFloat() ?? 0
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
    // ffmpeg 软解的字幕
    // 875,,Default,NTP,0000,0000,0000,!Effect,- 你们两个别冲这么快\\N- 我会取消所有行程尽快赶过去
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
        let part = SubtitlePart(start, end, attributedString: text.build(textPosition: &textPosition, attributed: attributes))
        part.textPosition = textPosition
        return part
    }
}

public struct ASSStyle {
    let attrs: [NSAttributedString.Key: Any]
    let textPosition: TextPosition
}

// MARK: - ASS Override Tag Processing

/// Parsed result from an ASS override tag block (content between `{` and `}`).
/// RE: processStyleOverrideTags at 0x10135fac0
public struct ASSOverrideResult {
    public var attributes: [NSAttributedString.Key: Any]
    public var textPosition: TextPosition
    /// Parsed `\pos(x,y)` override, if present
    public var position: CGPoint?
    /// Parsed `\fad(fadeIn,fadeOut)` in milliseconds, if present
    public var fade: (fadeIn: Int, fadeOut: Int)?
    /// Parsed `\be<n>` edge blur value
    public var edgeBlur: Float?
    /// Parsed `\blur<n>` gaussian blur value
    public var gaussianBlur: Float?
}

public extension AssParse {
    /// Process an ASS override tag block string (content between `{` and `}`).
    /// Parses known tags and returns an `ASSOverrideResult` with the style dictionary
    /// and any positional/effect overrides.
    /// RE: 0x10135fac0
    static func processStyleOverrideTags(
        _ tagBlock: String,
        baseAttributes: [NSAttributedString.Key: Any] = [:],
        basePosition: TextPosition = TextPosition()
    ) -> ASSOverrideResult {
        var attributes = baseAttributes
        var textPosition = basePosition
        var position: CGPoint?
        var fade: (Int, Int)?
        var edgeBlur: Float?
        var gaussianBlur: Float?
        var fontName: String?
        var fontSize: Float?
        var shadow = attributes[.shadow] as? NSShadow

        let subStyleArr = tagBlock.components(separatedBy: "\\")
        for item in subStyleArr {
            let itemStr = item.trimmingCharacters(in: .whitespaces)
            guard !itemStr.isEmpty else { continue }
            let scanner = Scanner(string: itemStr)

            // \pos(x,y)
            if itemStr.hasPrefix("pos(") {
                _ = scanner.scanString("pos(")
                if let x = scanner.scanFloat() {
                    _ = scanner.scanString(",")
                    if let y = scanner.scanFloat() {
                        position = CGPoint(x: CGFloat(x), y: CGFloat(y))
                    }
                }
                continue
            }

            // \fad(fadeIn,fadeOut)
            if itemStr.hasPrefix("fad(") {
                _ = scanner.scanString("fad(")
                if let t1 = scanner.scanInt() {
                    _ = scanner.scanString(",")
                    if let t2 = scanner.scanInt() {
                        fade = (t1, t2)
                    }
                }
                continue
            }

            // \be<n> — edge blur
            if itemStr.hasPrefix("be") {
                _ = scanner.scanString("be")
                if let n = scanner.scanFloat() {
                    edgeBlur = n
                }
                continue
            }

            // \blur<n> — gaussian blur
            if itemStr.hasPrefix("blur") {
                _ = scanner.scanString("blur")
                if let n = scanner.scanFloat() {
                    gaussianBlur = n
                }
                continue
            }

            let char = scanner.scanCharacter()
            switch char {
            case "a":
                // \an<1-9> alignment
                let nextChar = scanner.scanCharacter()
                if nextChar == "n" {
                    textPosition.ass(alignment: scanner.scanUpToCharacters(from: .newlines))
                }
            case "b":
                // \b<0|1> bold
                if let val = scanner.scanInt() {
                    if val == 1 {
                        attributes[.expansion] = Float(1)
                    } else {
                        attributes[.expansion] = Float(0)
                    }
                }
            case "c":
                // \c&H<color>& — primary color shorthand
                attributes[.foregroundColor] = scanner.scanUpToCharacters(from: .newlines).flatMap(UIColor.init(assColor:))
            case "f":
                let nextChar = scanner.scanCharacter()
                if nextChar == "n" {
                    // \fn<name>
                    fontName = scanner.scanUpToCharacters(from: .newlines)
                } else if nextChar == "s" {
                    // \fs<n>
                    fontSize = scanner.scanFloat()
                }
            case "i":
                // \i<0|1> italic
                if let val = scanner.scanInt() {
                    attributes[.obliqueness] = val == 1 ? Float(0.3) : Float(0)
                }
            case "s":
                // \s<0|1> strikethrough
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
                // \u<0|1> underline
                attributes[.underlineStyle] = scanner.scanInt()
            case "1", "2", "3", "4":
                // \1c, \2c, \3c, \4c — color channels
                let twoChar = scanner.scanCharacter()
                if twoChar == "c" {
                    let color = scanner.scanUpToCharacters(from: .newlines).flatMap(UIColor.init(assColor:))
                    if char == "1" {
                        attributes[.foregroundColor] = color
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

        // Apply font if both name and size were specified
        if let fontName {
            let size = CGFloat(fontSize ?? 24)
            let font = UIFont(name: fontName, size: size) ?? UIFont.systemFont(ofSize: size)
            attributes[.font] = font
        } else if let fontSize {
            attributes[.font] = UIFont.systemFont(ofSize: CGFloat(fontSize))
        }

        return ASSOverrideResult(
            attributes: attributes,
            textPosition: textPosition,
            position: position,
            fade: fade,
            edgeBlur: edgeBlur,
            gaussianBlur: gaussianBlur
        )
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

    func splitStyle() -> [(String, String?)] {
        let scanner = Scanner(string: self)
        scanner.charactersToBeSkipped = nil
        var result = [(String, String?)]()
        var sytle: String?
        while !scanner.isAtEnd {
            if scanner.scanString("{") != nil {
                sytle = scanner.scanUpToString("}")
                _ = scanner.scanString("}")
            } else if scanner.scanString("<") != nil {
                // Forward compatibility: support <...> as alternative ASS override delimiters
                sytle = scanner.scanUpToString(">")
                _ = scanner.scanString(">")
            } else {
                // Scan text up to the next override block (either { or <)
                let remaining = self[scanner.currentIndex...]
                let nextBrace = remaining.firstIndex(of: "{")
                let nextAngle = remaining.firstIndex(of: "<")
                let nextDelim: String.Index?
                switch (nextBrace, nextAngle) {
                case let (b?, a?): nextDelim = min(b, a)
                case let (b?, nil): nextDelim = b
                case let (nil, a?): nextDelim = a
                case (nil, nil): nextDelim = nil
                }
                if let delim = nextDelim, delim > scanner.currentIndex {
                    let text = String(self[scanner.currentIndex..<delim])
                    scanner.currentIndex = delim
                    result.append((text, sytle))
                } else if let text = scanner.scanUpToCharacters(from: .newlines) {
                    result.append((text, sytle))
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

public class VTTParse: KSParseProtocol {
    public func canParse(scanner: Scanner) -> Bool {
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
    public func parsePart(scanner: Scanner) -> SubtitlePart? {
        var timeStrs: String?
        repeat {
            timeStrs = scanner.scanUpToCharacters(from: .newlines)
            _ = scanner.scanCharacters(from: .newlines)
        } while !(timeStrs?.contains("-->") ?? false) && !scanner.isAtEnd
        guard let timeStrs else {
            return nil
        }
        let timeArray: [String] = timeStrs.components(separatedBy: "-->")
        if timeArray.count == 2 {
            let startString = timeArray[0]
            let endString = timeArray[1]
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
            return SubtitlePart(startString.parseDuration(), endString.parseDuration(), attributedString: text.build(textPosition: &textPosition))
        }
        return nil
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
    public func parsePart(scanner: Scanner) -> SubtitlePart? {
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
            return SubtitlePart(startString.parseDuration(), endString.parseDuration(), attributedString: text.build(textPosition: &textPosition))
        }
        return nil
    }
}
