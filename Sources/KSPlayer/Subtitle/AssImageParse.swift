//
//  AssImageParse.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — SubtitleParseRegistry first entry
//  Parses ASS subtitle events into structured data for image-based rendering via
//  AssIncrementImageRenderer or AssImageRenderer (libass pipeline).
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
/// bitmap images. This is the first parser tried in the Forward parse registry:
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
    /// Returns true only when enableHDRSubtitle or useLibassForASS is on,
    /// indicating that image-based rendering is preferred over text-based.
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
        guard var keys = scanner.scanUpToCharacters(from: .newlines)?.components(separatedBy: ",") else {
            scanner.currentIndex = savedIndex
            return false
        }
        keys = keys.map { $0.trimmingCharacters(in: .whitespaces) }

        var styleLines = [String]()
        styleLines.append("Format: " + keys.joined(separator: ", "))

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
            styleMap[values[0]] = dic.parseASSStyle()
        }

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
            + styleLines.joined(separator: "\n") + "\n\n"
            + "[Events]\n"
            + "Format: " + eventKeys.joined(separator: ", ") + "\n"

        // Initialize libass renderer
        let renderer = AssImageRenderer(
            videoWidth: Int32(playResX > 0 ? playResX : 1280),
            videoHeight: Int32(playResY > 0 ? playResY : 720)
        )
        renderer.loadHeader(headerText)
        imageRenderer = renderer

        return true
    }

    /// Parse a single ASS Dialogue event and render it to an image-based SubtitlePart.
    public func parsePart(scanner: Scanner) -> SubtitlePart? {
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

        let start: TimeInterval
        let end: TimeInterval
        if let startString = dic["Start"], let endString = dic["End"] {
            start = startString.parseDuration()
            end = endString.parseDuration()
        } else {
            if isDialogue {
                return nil
            } else {
                return nil
            }
        }

        guard let text = dic["Text"] else { return nil }

        // Build the dialogue line for libass rendering
        let dialogueLine = text.replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")

        // Render via libass to get a bitmap image
        if let renderer = imageRenderer {
            let startMs = Int64(start * 1000)
            let durationMs = Int64((end - start) * 1000)

            if let result = renderer.renderToUIImage(text: dialogueLine, pts: startMs, duration: durationMs) {
                let part = SubtitlePart(start, end, attributedString: nil)
                part.image = result.image
                part.origin = result.origin
                return part
            }
        }

        // Fallback: return text-based part if image rendering fails
        var textPosition = TextPosition()
        if let style = dic["Style"], let assStyle = styleMap[style] {
            textPosition = assStyle.textPosition
        }
        let cleanText = dialogueLine
        return SubtitlePart(start, end, attributedString: cleanText.build(textPosition: &textPosition))
    }
}
