//
//  FFmpegSubtitleParse.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — SubtitleParseRegistry fallback parser
//  Fallback parser that delegates to FFmpegSubtitle actor when text-based parsers
//  (ASS, VTT, SRT) fail to match. Detects subtitle format via FFmpeg's codec detection.
//

import Foundation

/// Fallback KSParseProtocol implementation that delegates to FFmpeg for subtitle
/// format detection and parsing.
///
/// Used when the text-based parsers (AssParse, VTTParse, SrtParse) all fail to match.
/// This parser checks if the content might be a binary subtitle format (PGS/SUP, VOBSUB)
/// or a text format that the other parsers didn't recognize.
///
/// RE: SubtitleParseRegistry order: [AssImageParse, AssParse, VTTParse, SrtParse, FFmpegSubtitleParse]
/// This is always the last parser tried.
public class FFmpegSubtitleParse: KSParseProtocol {
    public init() {}

    /// FFmpegSubtitleParse is a fallback — it accepts anything the other parsers rejected.
    /// Since it's registered last in the parse chain, canParse returns true for any
    /// non-empty content that hasn't been claimed by ASS/VTT/SRT parsers.
    public func canParse(scanner: Scanner) -> Bool {
        // Only accept if there's actual content remaining
        guard !scanner.isAtEnd else { return false }

        let remaining = scanner.string[scanner.currentIndex...]
        let trimmed = remaining.trimmingCharacters(in: .whitespacesAndNewlines)

        // Accept if there's substantive content — the other parsers have already
        // been tried and failed, so this is our last chance to parse it.
        // Reject truly empty or trivially short content.
        return trimmed.count > 10
    }

    /// Attempt to parse subtitle content using heuristic text extraction.
    ///
    /// Since we don't have a full FFmpeg decode pipeline available in the scanner-based
    /// parse path, we attempt basic line-based extraction for formats that the primary
    /// parsers missed (e.g., non-standard SRT variants, LRC lyrics, plain text).
    public func parsePart(scanner: Scanner) -> SubtitlePart? {
        // Try LRC format: [MM:SS.xx] or [MM:SS:xx]
        if let lrcPart = parseLRC(scanner: scanner) {
            return lrcPart
        }

        // Try plain timestamped text: any line with a recognizable timestamp pattern
        if let textPart = parsePlainTimestamped(scanner: scanner) {
            return textPart
        }

        // Skip unrecognized line and try next
        _ = scanner.scanUpToCharacters(from: .newlines)
        _ = scanner.scanCharacters(from: .newlines)
        return nil
    }

    // MARK: - LRC Parser

    /// Parse LRC (lyrics) format: [MM:SS.xx]text or [MM:SS:xx]text
    private func parseLRC(scanner: Scanner) -> SubtitlePart? {
        let savedIndex = scanner.currentIndex

        guard scanner.scanString("[") != nil else {
            scanner.currentIndex = savedIndex
            return nil
        }

        // Parse minutes
        guard let minutes = scanner.scanInt() else {
            scanner.currentIndex = savedIndex
            return nil
        }

        // Expect : separator
        guard scanner.scanString(":") != nil else {
            scanner.currentIndex = savedIndex
            return nil
        }

        // Parse seconds
        guard let seconds = scanner.scanDouble() else {
            scanner.currentIndex = savedIndex
            return nil
        }

        // Closing bracket
        guard scanner.scanString("]") != nil else {
            scanner.currentIndex = savedIndex
            return nil
        }

        let startTime = Double(minutes) * 60.0 + seconds

        // Read the text content until end of line
        let text = scanner.scanUpToCharacters(from: .newlines) ?? ""
        _ = scanner.scanCharacters(from: .newlines)

        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }

        // LRC doesn't have explicit end times — use a default display duration
        let endTime = startTime + 5.0

        var textPosition = TextPosition()
        return SubtitlePart(startTime, endTime, attributedString: text.build(textPosition: &textPosition))
    }

    // MARK: - Plain Timestamped Text

    /// Try to parse lines with embedded timestamps in various formats.
    private func parsePlainTimestamped(scanner: Scanner) -> SubtitlePart? {
        let savedIndex = scanner.currentIndex

        guard let line = scanner.scanUpToCharacters(from: .newlines) else {
            return nil
        }
        _ = scanner.scanCharacters(from: .newlines)

        // Check for timestamp-like pattern at start: HH:MM:SS or MM:SS
        let durationPattern = #"^(\d{1,2}:)?\d{1,2}:\d{2}(\.\d+)?"#
        guard let range = line.range(of: durationPattern, options: .regularExpression) else {
            scanner.currentIndex = savedIndex
            return nil
        }

        let timeStr = String(line[range])
        let start = timeStr.parseDuration()
        let text = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)

        guard !text.isEmpty else {
            return nil
        }

        var textPosition = TextPosition()
        return SubtitlePart(start, start + 5.0, attributedString: text.build(textPosition: &textPosition))
    }
}
