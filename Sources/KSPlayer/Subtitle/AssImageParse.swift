//
//  AssImageParse.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — SubtitleParseRegistry first entry.
//  Parses ASS subtitle events into structured data for image-based rendering via
//  AssIncrementImageRenderer or AssImageRenderer (libass pipeline).
//
//  This file hosts two related types, matching the cluster map for SubtitleSystem:
//    - AssImageParse        — the KSParseProtocol parser (7 Ghidra functions)
//    - AssSubtitleParser    — owns parseFormattedBlock @ 0x10147d50c (5648B mega
//                             SSA inline-override-tag parser), called by
//                             SubtitleDecode.buildSSAAttributedString.
//

import CoreGraphics
import Foundation
import Libass
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// ASS subtitle parser for image-based rendering.
///
/// Unlike the standard AssParse (which produces NSAttributedString), AssImageParse
/// extracts ASS events and renders them through the libass pipeline to produce
/// bitmap images. This is the first parser tried in the parse registry:
/// [AssImageParse, AssParse, VTTParse, SrtParse, FFmpegSubtitleParse]
///
/// AssImageParse is preferred over AssParse when complex ASS effects (blur,
/// animations, vector drawings) are present that NSAttributedString cannot reproduce.
public class AssImageParse: KSParseProtocol {
    /// The libass-based renderer used to produce subtitle images.
    private var imageRenderer: AssImageRenderer?

    /// Parsed style map from the ASS header (for fallback info).
    private var styleMap = [String: ASSStyle]()

    /// Event column keys from [Events] Format line.
    private var eventKeys = ["Layer", "Start", "End", "Style", "Name",
                             "MarginL", "MarginR", "MarginV", "Effect", "Text"]

    /// PlayRes dimensions from [Script Info].
    private var playResX: Float = 384.0
    private var playResY: Float = 288.0

    /// The full ASS header text (Script Info + Styles) for libass.
    private var headerText: String = ""

    public init() {}

    // MARK: - KSParseProtocol

    /// Detect ASS format and initialize the libass renderer with the header.
    /// Returns true only when useLibassForASS is on, indicating that image-based
    /// rendering is preferred over text-based.
    ///
    /// RE: 0x1014778e4 region — the registry probes each parser's content-parse
    /// entry; for AssImageParse the witness ultimately drives this detection path.
    public func canParse(scanner: Scanner) -> Bool {
        // Only claim ASS parsing if libass rendering is enabled
        guard KSOptions.useLibassForASS else { return false }

        let savedIndex = scanner.currentIndex
        guard scanner.scanString("[Script Info]") != nil else {
            scanner.currentIndex = savedIndex
            return false
        }

        // Parse Script Info section for PlayRes
        var headerLines = ["[Script Info]"]
        while scanner.scanString("Format:") == nil, !scanner.isAtEnd {
            if scanner.scanString("PlayResX:") != nil {
                playResX = scanner.scanFloat() ?? 384.0
                headerLines.append("PlayResX: \(Int(playResX))")
            } else if scanner.scanString("PlayResY:") != nil {
                playResY = scanner.scanFloat() ?? 288.0
                headerLines.append("PlayResY: \(Int(playResY))")
            } else {
                if let line = scanner.scanUpToCharacters(from: .newlines) {
                    headerLines.append(line)
                }
            }
            _ = scanner.scanCharacters(from: .newlines)
        }

        // Parse styles
        guard let keys = scanner.scanUpToCharacters(from: .newlines)?.components(separatedBy: ",") else {
            scanner.currentIndex = savedIndex
            return false
        }
        let trimmedKeys = keys.map { $0.trimmingCharacters(in: .whitespaces) }

        let styleLines = processStyles(scanner: scanner, formatKeys: trimmedKeys)

        _ = scanner.scanString("[Events]")
        if scanner.scanString("Format: ") != nil || scanner.scanString("Format:") != nil {
            guard let eventFormatKeys = scanner.scanUpToCharacters(from: .newlines)?.components(separatedBy: ",") else {
                scanner.currentIndex = savedIndex
                return false
            }
            eventKeys = eventFormatKeys.map { $0.trimmingCharacters(in: .whitespaces) }
        }

        // Build the full header for libass
        headerText = headerLines.joined(separator: "\n") + "\n\n"
            + "[V4+ Styles]\n"
            + "Format: " + trimmedKeys.joined(separator: ", ") + "\n"
            + styleLines.joined(separator: "\n") + "\n\n"
            + "[Events]\n"
            + "Format: " + eventKeys.joined(separator: ", ") + "\n"

        // Initialize libass renderer
        imageRenderer = createRenderer()

        return true
    }

    /// Parse a single ASS Dialogue event and render it to an image-based SubtitlePart.
    public func parsePart(scanner: Scanner) -> SubtitlePart? {
        return parseSubtitleEvent(scanner: scanner)
    }

    // MARK: - AssImageParse internals (7-function Ghidra surface)

    /// Style processor — consumes successive `Style:` lines from the header and
    /// fills `styleMap`, returning the reformatted `Style:` lines for the libass
    /// header. Kept as a distinct step (API-surface preservation) rather than
    /// inlined into canParse.
    ///
    /// RE: 0x1014777a0 (AssImageParse.processStyles, 1.3.15)
    private func processStyles(scanner: Scanner, formatKeys keys: [String]) -> [String] {
        var styleLines = [String]()
        while scanner.scanString("Style:") != nil {
            _ = scanner.scanString("Format: ")
            guard let values = scanner.scanUpToCharacters(from: .newlines)?.components(separatedBy: ",") else {
                continue
            }
            styleLines.append("Style: " + values.joined(separator: ","))

            var dic = [String: String]()
            for i in 1 ..< min(keys.count, values.count) {
                dic[keys[i]] = values[i]
            }
            if let name = values.first {
                styleMap[name] = dic.parseASSStyle()
            }
        }
        return styleLines
    }

    /// Construct the libass renderer instance from the parsed PlayRes dimensions
    /// and load the assembled header into it. Kept distinct (API-surface
    /// preservation) rather than inlined into canParse.
    ///
    /// RE: 0x1014776ec (AssImageParse.createRenderer, 1.3.15)
    private func createRenderer() -> AssImageRenderer {
        let renderer = AssImageRenderer(
            videoWidth: Int32(playResX > 0 ? playResX : 1280),
            videoHeight: Int32(playResY > 0 ? playResY : 720)
        )
        renderer.loadHeader(headerText)
        return renderer
    }

    /// Parse one ASS `Dialogue:` event and render it to an image-based
    /// `SubtitlePart`, falling back to a text part if libass rendering fails.
    ///
    /// This is the public-facing entry of the two-overload `parseSubtitleEvent`
    /// pair. The format-detection overload (`parseSubtitleEvent(headerScanner:)`)
    /// is kept separate per API-surface preservation.
    ///
    /// RE: 0x101473bf4 (AssImageParse.parseSubtitleEvent (1), 1.3.15)
    ///     — the 1.3.15 binary entry at 0x101473bf4 tail-calls the real impl;
    ///       the consolidated body lives here.
    private func parseSubtitleEvent(scanner: Scanner) -> SubtitlePart? {
        let isDialogue = scanner.scanString("Dialogue") != nil
        guard isDialogue || !scanner.isAtEnd else { return nil }

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
        _ = scanner.scanCharacters(from: .newlines)

        guard let startString = dic["Start"], let endString = dic["End"] else {
            return nil
        }
        let start = startString.parseDuration()
        let end = endString.parseDuration()

        guard let text = dic["Text"] else { return nil }

        // Build the dialogue line for libass rendering. Trailing whitespace from
        // the Text column is stripped via trimTrailingChars before render.
        var dialogueLine = text.replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
        trimTrailingChars(&dialogueLine)

        // Render via libass to get a bitmap image.
        if let renderer = imageRenderer {
            let startMs = Int64(start * 1000)
            let durationMs = Int64((end - start) * 1000)

            if let result = renderer.renderToUIImage(text: dialogueLine, pts: startMs, duration: durationMs) {
                // SubtitlePart is a struct (RE struct shape: start, end, render); the
                // image/origin computed setters mutate `render`, so `part` must be `var`.
                // Order matters: assign `image` first (promotes to the .left image branch
                // and seeds rect from origin), then `origin` (only effective once .left).
                var part = SubtitlePart(start, end, attributedString: nil)
                part.image = result.image
                part.origin = result.origin
                return part
            }
        }

        // Fallback: return text-based part if image rendering fails.
        var textPosition = TextPosition()
        if let style = dic["Style"], let assStyle = styleMap[style] {
            textPosition = assStyle.textPosition
        }
        return SubtitlePart(start, end, attributedString: dialogueLine.build(textPosition: &textPosition))
    }

    /// Format-detection overload of `parseSubtitleEvent`. Sniffs a raw header
    /// scanner to decide whether the stream is WebVTT (contains `" --> "` and a
    /// `WEBVTT` magic) or ASS (`[Script Info]`). Returns `true` when a known
    /// subtitle container header is recognized.
    ///
    /// The two `parseSubtitleEvent` impls are intentionally kept separate
    /// (API-surface preservation): the 1.3.15 binary has `parseSubtitleEvent (1)`
    /// @ 0x101473bf4 invoking `parseSubtitleEvent (2)` @ 0x10147748c.
    ///
    /// RE: 0x10147748c (AssImageParse.parseSubtitleEvent (2), 1.3.15)
    @discardableResult
    func parseSubtitleEvent(headerScanner scanner: Scanner) -> Bool {
        // VTT branch (DAT_104458771 feature gate in the binary): the cue line
        // contains the " --> " timing arrow.
        let savedIndex = scanner.currentIndex
        if let line = scanner.scanUpToCharacters(from: .newlines), line.contains(" --> ") {
            scanner.currentIndex = savedIndex
            scanner.charactersToBeSkipped = nil
            _ = scanner.scanString("WEBVTT")
            return true
        }
        scanner.currentIndex = savedIndex

        // ASS branch (DAT_104458770 feature gate in the binary): the line
        // contains the "[Script Info]" section header.
        if let line = scanner.scanUpToCharacters(from: .newlines), line.contains("[Script Info]") {
            scanner.currentIndex = savedIndex
            return true
        }
        scanner.currentIndex = savedIndex
        return false
    }

    /// In-place reversal of a parsed element array (e.g. to flip render ordering
    /// of stacked image rects before compositing). The 1.3.15 body is a
    /// half-span swap over a fixed-stride element buffer; expressed here as the
    /// idiomatic Swift reverse.
    ///
    /// RE: 0x1014779b4 (AssImageParse.reverseArray, 1.3.15)
    @discardableResult
    func reverseArray<T>(_ array: inout [T]) -> [T] {
        guard array.count > 1 else { return array }
        array.reverse()
        return array
    }

    /// Remove a fixed count of trailing characters from an event-text string
    /// before rendering (binary cleanup step prior to libass submission).
    /// The 1.3.15 body removes a trailing subrange of the scanned text.
    ///
    /// RE: 0x101477b7c (AssImageParse.trimTrailingChars, 1.3.15)
    func trimTrailingChars(_ string: inout String) {
        while let last = string.last, last == "\n" || last == "\r" || last == " " || last == "\t" {
            string.removeLast()
        }
    }
}

// MARK: - KSParseProtocol witness (parseContent)

public extension AssImageParse {
    /// Protocol-witness content-parse entry point for `KSParseProtocol`.
    ///
    /// This is the symbol the deprecation table reassigned from the
    /// mis-attributed `AssParse_parseContent` to
    /// `AssImageParse_witnessTable_parseContent` — it belongs to AssImageParse,
    /// NOT AssParse. It drives the full content parse: detect via `canParse`,
    /// then iterate `parsePart` to accumulate `[SubtitlePart]`.
    ///
    /// NOTE: the raw 1.3.15 body at 0x1014778e4 is an in-place half-span byte
    /// swap over a 0x20-stride array (a COW-checked reverse). That low-level
    /// reverse is exposed idiomatically as `reverseArray(_:)` above; this method
    /// is the content-parse witness role the registry actually invokes.
    ///
    /// RE: 0x1014778e4 (AssImageParse.witnessTable_parseContent, 1.3.15)
    func parseContent(scanner: Scanner) -> [SubtitlePart] {
        guard canParse(scanner: scanner) else { return [] }
        return parse(scanner: scanner)
    }
}

// MARK: - AssSubtitleParser

/// Owner of the SSA inline-override-tag parser (`parseFormattedBlock`), the
/// largest function in the subtitle system. Used by the FFmpeg/SSA decode path
/// (`SubtitleDecode.buildSSAAttributedString`) to turn a single ASS dialogue
/// text segment — including its `{\...}`-stripped inline `\tag` run — into an
/// attributed string with per-run styling.
///
/// RE: 0x10147d50c region (AssSubtitleParser, 1.3.15)
public final class AssSubtitleParser {
    public init() {}

    /// Parse one formatted ASS text block (a run of backslash-separated inline
    /// override tags followed by literal text) into an `NSAttributedString`.
    ///
    /// Behaviour reconstructed from the 5648B decompile:
    ///   - If `fontScale == 0` (no styling requested), returns a plain
    ///     `NSAttributedString(string:)` with no attributes (early-out branch).
    ///   - Otherwise splits `block` on `\` (0x5c). For each segment a sub-scanner
    ///     reads the first character and dispatches on the SSA override code:
    ///       `a`  → alignment (`an<n>` / `a<n>`)
    ///       `b`  → bold              (scanInt; 0 = off, else on)
    ///       `c`  → primary colour    (`&Hbbggrr&` hex → UIColor, foreground)
    ///       `fn` → font name, `fs`/`fscx`/`fscy` → font scale
    ///       `i`  → italic            (scanInt)
    ///       `r`  → reset to a named/base style (delegates to resolveSSAStyle)
    ///       `s`  → strike (`s<n>`), `shad` → shadow radius, `sub`/`sup`
    ///       `u`  → underline         (scanInt)
    ///       `1`/`2`/`3`/`4` `c` → primary/secondary/outline/shadow colour
    ///     The accumulated `[NSAttributedString.Key: Any]` is applied to the
    ///     literal text (NSFont, NSForegroundColor, NSStrokeColor, NSShadow,
    ///     NSUnderlineStyle, NSStrikethroughStyle), then wrapped as
    ///     `NSAttributedString(string:attributes:)`.
    ///
    /// - Parameters:
    ///   - block: the raw ASS text segment (already split out of the dialogue).
    ///   - text: the literal display text the attributes apply to.
    ///   - fontScale: master font scale; `0` selects the unstyled early-out.
    ///   - baseAttributes: attributes inherited from the dialogue's style row.
    ///   - basePosition: text position inherited from the dialogue's style row.
    ///   - styleName: the style name used by the `\r` reset tag (may be empty).
    ///
    /// RE: 0x10147d50c (AssSubtitleParser.parseFormattedBlock, 1.3.15)
    public func parseFormattedBlock(
        _ block: String,
        text: String,
        fontScale: Double,
        baseAttributes: [NSAttributedString.Key: Any] = [:],
        basePosition: TextPosition = TextPosition(),
        styleName: String = ""
    ) -> NSAttributedString {
        // Early-out: fontScale == 0 → unstyled string (decompile `param_4 == 0.0`).
        if fontScale == 0 {
            return NSAttributedString(string: text)
        }

        var attributes = baseAttributes
        var fontName: String?
        var resolvedScale = fontScale
        var bold = false
        var italic = false
        var underline = false
        var strike = false

        var primaryColor: UIColor?
        var outlineColor: UIColor?
        var shadowColor: UIColor?

        // Split on backslash; each segment is one inline override token.
        let segments = block.components(separatedBy: "\\")
        for segment in segments {
            let item = segment.trimmingCharacters(in: .whitespaces)
            guard let first = item.first else { continue }
            let scanner = Scanner(string: item)
            _ = scanner.scanCharacter()

            switch first {
            case "a":
                // alignment: \an<n> or \a<n>. (Consumed for completeness; the
                // numeric alignment feeds TextPosition selection upstream.)
                _ = scanner.scanString("n")
                _ = scanner.scanInt()
            case "b":
                if let v = scanner.scanInt() { bold = v != 0 } else { bold = true }
            case "i":
                if let v = scanner.scanInt() { italic = v != 0 } else { italic = true }
            case "u":
                if let v = scanner.scanInt() { underline = v != 0 } else { underline = true }
            case "c":
                // \c&Hbbggrr& — primary colour.
                primaryColor = AssSubtitleParser.scanSSAColor(scanner)
            case "f":
                if scanner.scanString("n") != nil {
                    // \fn<fontname> — read to end-of-line.
                    fontName = scanner.scanUpToCharacters(from: .newlines)
                } else if scanner.scanString("s") != nil {
                    // \fs<size> / \fscx / \fscy — read a scale value.
                    _ = scanner.scanString("cx")
                    _ = scanner.scanString("cy")
                    if let s = scanner.scanFloat() { resolvedScale = Double(s) }
                }
            case "r":
                // \r[<style>] — reset to a named style (or base style).
                let name = scanner.scanUpToCharacters(from: .newlines) ?? styleName
                if let reset = resolveResetStyle(named: name,
                                                 baseAttributes: baseAttributes,
                                                 basePosition: basePosition) {
                    attributes = reset.attrs
                }
            case "s":
                if scanner.scanString("had") != nil {
                    // \shad<n> — shadow radius.
                    if let radius = scanner.scanFloat() {
                        let shadow = NSShadow()
                        shadow.shadowBlurRadius = CGFloat(radius)
                        attributes[.shadow] = shadow
                    }
                } else if scanner.scanString("ub") != nil || scanner.scanString("up") != nil {
                    // \sub / \sup — sub/superscript marker (consumed).
                } else {
                    if let v = scanner.scanInt() { strike = v != 0 } else { strike = true }
                }
            case "1", "2", "3", "4":
                // \1c / \2c / \3c / \4c — primary/secondary/outline/shadow colour.
                _ = scanner.scanString("c")
                let color = AssSubtitleParser.scanSSAColor(scanner)
                switch first {
                case "1": primaryColor = color
                case "3": outlineColor = color
                case "4": shadowColor = color
                default: break // "2" secondary colour: not applied to display run
                }
            default:
                break
            }
        }

        // Assemble font with the accumulated traits.
        attributes[.font] = AssSubtitleParser.makeFont(name: fontName,
                                                       scale: resolvedScale,
                                                       bold: bold,
                                                       italic: italic)
        if let primaryColor {
            attributes[.foregroundColor] = primaryColor
        }
        if let outlineColor {
            attributes[.strokeColor] = outlineColor
        }
        if let shadowColor {
            let shadow = (attributes[.shadow] as? NSShadow) ?? NSShadow()
            shadow.shadowColor = shadowColor
            attributes[.shadow] = shadow
        }
        if underline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if strike {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }

        return NSAttributedString(string: text, attributes: attributes)
    }

    // MARK: - parseFormattedBlock helpers

    /// Resolve the `\r` reset target. When a non-empty style name is given the
    /// real binary delegates to `SubtitleDecode.resolveSSAStyle`; that resolver
    /// lives in the SubtitleDecode cluster. Standalone here we restore the base
    /// style row. See CROSS-FILE note in the file summary.
    private func resolveResetStyle(named name: String,
                                   baseAttributes: [NSAttributedString.Key: Any],
                                   basePosition: TextPosition) -> ASSStyle? {
        // CROSS-FILE: when name is non-empty, SubtitleDecode.resolveSSAStyle
        // (0x10147b080) should resolve it against the dialogue's style map.
        return ASSStyle(attrs: baseAttributes, textPosition: basePosition)
    }

    /// Parse an SSA colour token of the form `&Hbbggrr&` (BGR order, optional
    /// alpha) into a UIColor. Returns nil when the token is malformed.
    private static func scanSSAColor(_ scanner: Scanner) -> UIColor? {
        _ = scanner.scanString("&H") ?? scanner.scanString("H") ?? scanner.scanString("&")
        guard var hex = scanner.scanUpToString("&") ?? scanner.scanUpToCharacters(from: .newlines) else {
            return nil
        }
        _ = scanner.scanString("&")
        hex = hex.trimmingCharacters(in: .whitespaces)
        guard let value = UInt32(hex, radix: 16) else { return nil }
        // SSA packs colour as AABBGGRR (alpha is "transparency": 0 = opaque).
        let r = CGFloat(value & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat((value >> 16) & 0xFF) / 255.0
        let aRaw = CGFloat((value >> 24) & 0xFF) / 255.0
        let alpha = 1.0 - aRaw
        return UIColor(red: r, green: g, blue: b, alpha: hex.count > 6 ? alpha : 1.0)
    }

    /// Build a platform font honouring name, scale and bold/italic traits.
    private static func makeFont(name: String?, scale: Double, bold: Bool, italic: Bool) -> UIFont {
        let size = CGFloat(scale > 0 ? scale : Double(UIFont.systemFontSize))
        #if canImport(UIKit)
        // iOS / tvOS: compose traits through UIFontDescriptor.
        var base: UIFont
        if let name, let named = UIFont(name: name, size: size) {
            base = named
        } else {
            base = UIFont.systemFont(ofSize: size)
        }
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if !traits.isEmpty, let descriptor = base.fontDescriptor.withSymbolicTraits(traits) {
            base = UIFont(descriptor: descriptor, size: size)
        }
        return base
        #else
        // macOS: compose traits through NSFontManager.
        var base: NSFont
        if let name, let named = NSFont(name: name, size: size) {
            base = named
        } else {
            base = NSFont.systemFont(ofSize: size)
        }
        let manager = NSFontManager.shared
        if bold { base = manager.convert(base, toHaveTrait: .boldFontMask) }
        if italic { base = manager.convert(base, toHaveTrait: .italicFontMask) }
        return base
        #endif
    }
}
