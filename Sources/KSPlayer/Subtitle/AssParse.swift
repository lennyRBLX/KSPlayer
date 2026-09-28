import CoreText
import Foundation
import SwiftUI
#if !canImport(UIKit)
import AppKit
#else
import UIKit
#endif

public class AssParse: KSParseProtocol {
    // ⚑[tool=field_surface ref=AssParse.styleMap:idx0 result=[String : ASSStyle]] Not optional. Its vpfi
    //   0x10011a6c4 is `ldr x0, [__got 0xd08]` / `ret` — the empty-Dictionary singleton, i.e. `[:]`.
    private var styleMap: [String: ASSStyle] = [:]
    private var eventKeys: [String] = ["Layer", "Start", "End", "Style", "Name", "MarginL", "MarginR", "MarginV", "Effect", "Text"]
    private var displaySize: CGSize = .zero
    // Forward 1.3.17 AssParse.canParse (FUN_101a97464, ~1048i) — REORGANIZED vs the base original:  ⚑[tool=resolve_fun_pins ref=FUN_101a97464:0x101a97464 result=RESOLVES_UNIQUELY] = KSPlayer.AssParse.canParse(scanner: __C.NSScanner) -> Swift.Bool
    //   resets styleMap, prechecks `scanner.string.contains("Format: Name,")` (NOT the base
    //   `scanString("[Script Info]")`), writes PlayResX/Y DIRECTLY into displaySize with 384x288
    //   defaults, COLLECTS the Style: lines and processes them AFTER the [Fonts] embedded-font
    //   extraction (uudecode -> NSTemporaryDirectory write -> CTFontManagerRegisterFontsForURL),
    //   then reads the [Events] Format keys. audit_workflow + P42-disasm verified (session 18).
    public func canParse(scanner: Scanner) -> Bool {
        styleMap = [String: ASSStyle]()
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
                    continue
                }
                guard let encoded = fontScanner.scanUpToString("fontname:") else {
                    // binary loops back to scanString("fontname:") on a nil body (skips an empty
                    // entry), NOT break — FUN_101a97464 @390-396 (audit_workflow session 18).  ⚑[tool=resolve_fun_pins ref=FUN_101a97464:0x101a97464 result=RESOLVES_UNIQUELY] = KSPlayer.AssParse.canParse(scanner: __C.NSScanner) -> Swift.Bool
                    continue
                }
                // Path = NSTemporaryDirectory() + "fontsDir/" + fontName (3-part, 2× String.append —
                // P42-disasm-confirmed 0x101a97c6c-cfc: tmp @0x10345ac84, "fontsDir/" small-string @0x101a97c8c). ⚑ URL init form (fileURLWithPath vs string:) minor.
                let url = URL(fileURLWithPath: NSTemporaryDirectory() + ("fontsDir/" + fontName))
                let data = uudecode(encoded)
                try? data.write(to: url)
                // scope .process, error nil — P42-disasm-confirmed `CTFontManagerRegisterFontsForURL(url, w1=1, x2=0)` @0x101a97d6c-d70.
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        // Process the collected Style: lines into styleMap.
        for line in styleLines {
            var values = line.components(separatedBy: ",")
            if values.count < keys.count {
                values.append(contentsOf: [String](repeating: "", count: keys.count - values.count))
            }
            var dic = [String: String]()
            for i in 1 ..< keys.count {
                dic[keys[i]] = values[i]
            }
            styleMap[values[0]] = dic.parseASSStyle()
        }
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
    private final func uudecode(_ string: String) -> Data {
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
        if let style = dic["Style"], let assStyle = styleMap.match(key: style) {
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
            textPosition = TextPosition(leftMargin: 10, rightMargin: 10)
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

extension Dictionary where Key == String {
    public func match(key: String) -> Value? {
        if key.hasPrefix("*") {
            let suffix = String(key[key.index(key.startIndex, offsetBy: 1)...])
            return first { $0.key.hasSuffix(suffix) }?.value
        } else if key.hasSuffix("*") {
            let prefix = String(key[..<key.index(key.endIndex, offsetBy: -1)])
            return first { $0.key.hasPrefix(prefix) }?.value
        } else {
            return self[key]
        }
    }
}
