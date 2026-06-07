//
//  SubtitleDecode.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/11.
//

import CoreGraphics
import CoreMedia
import Foundation
import Libavformat
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

class SubtitleDecode: DecodeProtocol {
    // RE field table (SubtitleDecode, 1.3.15 — 6 fields, Forward added 2 over upstream):
    //   1 codecContext  UnsafeMutablePointer<AVCodecContext>?   Upstream
    //   2 subtitle      AVSubtitle                              Upstream
    //   3 startTime     Double                                  Upstream
    //   4 assParse      AssParse?                               FORWARD (made optional)
    //   5 assImageRenderer AssIncrementImageRenderer?           FORWARD ADD
    //   6 isASS         Bool                                    FORWARD ADD
    private var codecContext: UnsafeMutablePointer<AVCodecContext>?
    private var subtitle = AVSubtitle()
    private var startTime = TimeInterval(0)

    /// FORWARD-made-optional: upstream stores a non-optional `AssParse`; the
    /// Forward binary holds it as an optional populated only when the stream is ASS/SSA.
    private var assParse: AssParse?

    /// ASS image renderer for complex subtitle styling (Forward v1.3.15, field #5).
    /// Participates in the `decodeAndProcessSubtitle` no-parts fallback decision:
    /// the manual text-trimming SubtitlePart is only constructed when this renderer
    /// is inactive (the binary guards the fallback on the renderer being nil).
    public var assImageRenderer: AssIncrementImageRenderer?

    /// Whether the current subtitle stream is ASS/SSA format (Forward v1.3.15, field #6).
    public var isASS: Bool = false

    /// PAL8 → ARGB scaler used by the bitmap rect path (`decodeSubtitle`). Not a
    /// documented field-table entry but required for the documented bitmap pipeline.
    private let scale = VideoSwresample(dstFormat: AV_PIX_FMT_ARGB, isDovi: false)

    required init(assetTrack: FFmpegAssetTrack, options: KSOptions) {
        startTime = assetTrack.startTime.seconds
        let codecId = assetTrack.codecpar.codec_id
        isASS = (codecId == AV_CODEC_ID_ASS || codecId == AV_CODEC_ID_SSA)
        do {
            codecContext = try assetTrack.createContext(options: options)
            if let pointer = codecContext?.pointee.subtitle_header {
                let subtitleHeader = String(cString: pointer)
                if isASS {
                    let parse = AssParse()
                    _ = parse.canParse(scanner: Scanner(string: subtitleHeader))
                    assParse = parse
                }
            }
        } catch {
            KSLog(error as CustomStringConvertible)
        }
    }

    func decode() {}

    /// Emit pass — protocol-witness entry that drives the decode pipeline.
    ///
    /// RE: 0x10144d964 (SubtitleDecode.emitFrames, 1.3.15) — reached through the
    /// protocol-witness-table tail-call thunk at 0x10144f0ec (`b 0x10144d964`).
    /// The binary calls `decodeAndProcessSubtitle` (0x10144db10) to obtain the
    /// decoded `SubtitlePart` list, then loops the list allocating one
    /// `SubtitleFrame` per part and handing each to the completion handler. The
    /// per-part `start`/`end` timing is assigned inside `decodeAndProcessSubtitle`,
    /// so this loop only stamps the timebase/timestamp and emits.
    func decodeFrame(from packet: Packet, completionHandler: @escaping (Result<MEFrame, Error>) -> Void) {
        let timestamp = packet.timestamp
        let parts = decodeAndProcessSubtitle(from: packet)
        for part in parts {
            let frame = SubtitleFrame(part: part, timebase: packet.assetTrack.timebase)
            frame.timestamp = timestamp
            completionHandler(.success(frame))
        }
    }

    func doFlushCodec() {}

    /// RE: 0x1000daf54 (SubtitleDecode.deinit_thunk, 1.3.15) — ObjC deinit thunk.
    /// Releases the scaler, frees the AVSubtitle, and tears down the codec context.
    func shutdown() {
        scale.shutdown()
        avsubtitle_free(&subtitle)
        if let codecContext {
            avcodec_close(codecContext)
            avcodec_free_context(&self.codecContext)
        }
    }

    /// Stage 1 of the two-stage decode — the actual FFmpeg subtitle decode driver.
    ///
    /// RE: 0x10144db10 (SubtitleDecode.decodeAndProcessSubtitle, 1.3.15, 1224B).
    /// Calls the reimplemented `avcodec_decode_subtitle2` (`FUN_1023e1398`), and on
    /// success computes CMTime-based timing then calls `decodeSubtitle` (stage 2,
    /// 0x10144e020) to process the resulting rects.
    ///
    /// Timing (from the decompile):
    ///   start = packet_position + start_display_time / 1000.0   (minus startTime if past it)
    ///   end   = start + duration, or `.infinity` when duration == 0
    /// where duration is `(end_display_time - start_display_time) / 1000.0`, falling
    /// back to the packet duration (converted through the track timebase) when zero.
    ///
    /// Fallback text-trimming path: when `decodeSubtitle` yields no parts AND no ASS
    /// image renderer is active, the binary constructs a SubtitlePart manually —
    /// trims `CharacterSet.whitespaces`, removes `\r\n` then `\n`, wraps as an
    /// `NSAttributedString`, and writes `{start, end, attributedString}` with the
    /// `isTextOnly` flag set. `FUN_1023120d8` (avsubtitle cleanup) runs on exit.
    private func decodeAndProcessSubtitle(from packet: Packet) -> [SubtitlePart] {
        guard let codecContext else {
            return []
        }
        var gotSubtitle = Int32(0)
        // FUN_1023e1398: reimplemented avcodec_decode_subtitle2 (validates
        // "Codec not subtitle decoder", dispatches the codec vtable at +0x88,
        // validates "Invalid UTF-8 in decoded subtitles text").
        let result = avcodec_decode_subtitle2(codecContext, &subtitle, &gotSubtitle, packet.corePacket)
        if result < 0 || gotSubtitle == 0 {
            return []
        }
        let timestamp = packet.timestamp
        var start = packet.assetTrack.timebase.cmtime(for: timestamp).seconds + TimeInterval(subtitle.start_display_time) / 1000.0
        if start >= startTime {
            start -= startTime
        }
        var duration = 0.0
        if subtitle.end_display_time != UInt32.max {
            duration = TimeInterval(subtitle.end_display_time - subtitle.start_display_time) / 1000.0
        }
        if duration == 0, packet.duration != 0 {
            duration = packet.assetTrack.timebase.cmtime(for: packet.duration).seconds
        }
        let end = duration == 0 ? TimeInterval.infinity : start + duration

        var parts = decodeSubtitle(subtitle, start: start, end: end)
        // Fallback: rect processing produced nothing and no incremental ASS image
        // renderer is driving output — synthesize a plain text part from the raw
        // AVSubtitle so the cue still shows. Guarded on `assImageRenderer == nil`
        // per the binary (when the renderer is active it owns the visual output).
        if parts.isEmpty, assImageRenderer == nil, let raw = rawText(from: subtitle) {
            var text = raw.trimmingCharacters(in: .whitespaces)
            text = text.replacingOccurrences(of: "\r\n", with: "")
            text = text.replacingOccurrences(of: "\n", with: "")
            if !text.isEmpty {
                parts.append(SubtitlePart(start, end, attributedString: NSAttributedString(string: text)))
            }
        }
        // The decode pipeline relies on an empty-part sentinel to clear stale cues
        // when subtitles arrive out of order (end < start would otherwise strand
        // the previous cue on screen).
        if parts.isEmpty {
            parts.append(SubtitlePart(start, end, attributedString: nil))
        } else {
            // SubtitlePart is a value type (struct), so stamp the computed timing
            // into each element in place by index — a `for part in parts` copy would
            // be a `let` binding and would not write back to the array.
            for index in parts.indices {
                parts[index].start = start
                parts[index].end = end
            }
        }
        // FUN_1023120d8: AVSubtitle cleanup on exit.
        avsubtitle_free(&subtitle)
        return parts
    }

    /// Extract a single raw text/ASS string from the decoded AVSubtitle for the
    /// fallback path (the binary reads the first text/ass rect verbatim).
    private func rawText(from subtitle: AVSubtitle) -> String? {
        for i in 0 ..< Int(subtitle.num_rects) {
            guard let rect = subtitle.rects[i]?.pointee else {
                continue
            }
            if let text = rect.text {
                return String(cString: text)
            } else if let ass = rect.ass {
                return String(cString: ass)
            }
        }
        return nil
    }

    /// Stage 2 of the two-stage decode — the rect processor (NOT an FFmpeg decode call).
    ///
    /// RE: 0x10144e020 (SubtitleDecode.decodeSubtitle, 1.3.15, 3748B). Iterates the
    /// already-decoded `AVSubtitleRect` list and dispatches per-rect on the rect
    /// type field (`*(int*)(rect + 0x4c)`, i.e. `rect.type`):
    ///   - bitmap (type == SUBTITLE_BITMAP): PAL8 → ARGB via VideoSwresample →
    ///     CGImage (`CFDataCreate` / `CGDataProviderCreateWithCFData` /
    ///     `CGColorSpaceCreateDeviceRGB` / `CGImageCreate`), composited into one PNG.
    ///   - text / ASS: routed through `parseSSADialogueLine` (the SubtitleDecode-owned
    ///     SSA dialogue parser), NOT delegated to `AssParse.parsePart`.
    /// `start`/`end` are propagated to every produced part (the binary writes the
    /// computed CMTime seconds into each SubtitlePart's timing fields).
    private func decodeSubtitle(_ subtitle: AVSubtitle, start: TimeInterval, end: TimeInterval) -> [SubtitlePart] {
        var parts = [SubtitlePart]()
        var images = [(CGRect, CGImage)]()
        var origin: CGPoint = .zero
        var attributedString: NSMutableAttributedString?
        for i in 0 ..< Int(subtitle.num_rects) {
            guard let rect = subtitle.rects[i]?.pointee else {
                continue
            }
            if i == 0 {
                origin = CGPoint(x: Int(rect.x), y: Int(rect.y))
            }
            if rect.type == SUBTITLE_BITMAP {
                if let image = scale.transfer(format: AV_PIX_FMT_PAL8, width: rect.w, height: rect.h, data: Array(tuple: rect.data), linesize: Array(tuple: rect.linesize))?.cgImage() {
                    images.append((CGRect(x: Int(rect.x), y: Int(rect.y), width: Int(rect.w), height: Int(rect.h)), image))
                }
            } else if let ass = rect.ass {
                // Text/ASS rect: drive the SubtitleDecode-owned SSA dialogue parser.
                let scanner = Scanner(string: String(cString: ass))
                let dialogueParts = parseSSADialogueLine(scanner: scanner, start: start, end: end)
                parts.append(contentsOf: dialogueParts)
            } else if let text = rect.text {
                if attributedString == nil {
                    attributedString = NSMutableAttributedString()
                }
                attributedString?.append(NSAttributedString(string: String(cString: text)))
            }
        }
        if images.count > 0 {
            if images.count > 1 {
                origin = .zero
            }
            // Subtitles need transparency: jpg is opaque; tif renders with a green
            // background on iOS; heic blocks the main thread on display — so png.
            // SubtitlePart is a value type (struct): build the image branch directly
            // via SubtitleImageInfo at `origin` rather than the legacy two-step
            // `part.image = …; part.origin = …` mutation (illegal on a `let` struct,
            // and order-fragile because the `image` setter reads `origin`).
            if let data = CGImage.combine(images: images)?.data(type: .png, quality: 0.2),
               let image = UIImage(data: data)?.cgImage
            {
                let displaySize = CGSize(width: image.width, height: image.height)
                let info = SubtitleImageInfo(rect: CGRect(origin: origin, size: displaySize), image: image, displaySize: displaySize)
                parts.append(SubtitlePart(start: start, end: end, image: info))
            }
        }
        if let attributedString {
            parts.append(SubtitlePart(start, end, attributedString: attributedString))
        }
        return parts
    }

    /// Core ASS/SSA dialogue line parser — the per-rect text/ASS handler invoked by
    /// `decodeSubtitle`.
    ///
    /// RE: 0x10147a4a4 (SubtitleDecode.parseSSADialogueLine, 1.3.15, 3036B). The
    /// binary drives an `NSScanner`: it consumes the `Dialogue` literal, then walks
    /// the event-format key list comma-by-comma (the final field scans up to the
    /// newline) building a `[String: String]` field dictionary. It then reads:
    ///   - `Style`  → `resolveSSAStyle` (named-style lookup, `*`-prefix/suffix aware)
    ///   - `MarginL` / `MarginR` / `MarginV` → override the resolved TextPosition margins
    ///   - `Text`   → strip `\N`/`\n` newline tokens and `\h` hard-space, then
    ///                `buildSSAAttributedString` to assemble the attributed run
    /// The result is a single-element `[SubtitlePart]` (empty on any required-field
    /// miss). `start`/`end` arrive precomputed from `decodeAndProcessSubtitle`.
    private func parseSSADialogueLine(scanner: Scanner, start: TimeInterval, end: TimeInterval) -> [SubtitlePart] {
        _ = scanner.scanString("Dialogue")
        _ = scanner.scanString(":")
        // The Forward event format the binary scans (matches AssParse.eventKeys).
        let eventKeys = ["Layer", "Start", "End", "Style", "Name", "MarginL", "MarginR", "MarginV", "Effect", "Text"]
        var dic = [String: String]()
        for i in 0 ..< eventKeys.count {
            if i == eventKeys.count - 1 {
                dic[eventKeys[i]] = scanner.scanUpToCharacters(from: .newlines)
            } else {
                dic[eventKeys[i]] = scanner.scanUpToString(",")
                _ = scanner.scanString(",")
            }
        }
        guard var text = dic["Text"] else {
            return []
        }
        // Resolve the named style row (may be nil → unstyled defaults downstream).
        let styleName = dic["Style"] ?? ""
        let resolved = resolveSSAStyle(named: styleName)
        var textPosition = resolved?.textPosition ?? TextPosition()
        if let marginL = dic["MarginL"].flatMap(Double.init), marginL != 0 {
            textPosition.leftMargin = CGFloat(marginL)
        }
        if let marginR = dic["MarginR"].flatMap(Double.init), marginR != 0 {
            textPosition.rightMargin = CGFloat(marginR)
        }
        if let marginV = dic["MarginV"].flatMap(Double.init), marginV != 0 {
            textPosition.verticalMargin = CGFloat(marginV)
        }
        // Normalise the ASS line/space escapes (the binary replaces \N and \n with
        // newline removal, and \h with a regular space).
        text = text.replacingOccurrences(of: "\\N", with: "\n")
        text = text.replacingOccurrences(of: "\\n", with: "\n")
        text = text.replacingOccurrences(of: "\\h", with: " ")
        let attributed = buildSSAAttributedString(text: text, style: resolved)
        var part = SubtitlePart(start, end, attributedString: attributed)
        part.textPosition = textPosition
        return [part]
    }

    /// Named-style lookup helper for `parseSSADialogueLine`.
    ///
    /// RE: 0x10147b080 (SubtitleDecode.resolveSSAStyle, 1.3.15, 1168B). Resolves the
    /// dialogue's `Style` field against `AssParse`'s style map. The binary handles
    /// SSA's `*`-prefixed/suffixed style names: a leading `*` (or trailing `*`) marks
    /// a partial-match name, so it strips the marker and matches by prefix/suffix;
    /// an exact key match is attempted first. Returns the resolved `ASSStyle` or nil
    /// when no style row matches (callers then fall back to default styling).
    /// Also referenced cross-cluster by `AssSubtitleParser.parseFormattedBlock`
    /// (the `\r` reset tag) per doc line 2023.
    func resolveSSAStyle(named rawName: String) -> ASSStyle? {
        guard let assParse else {
            return nil
        }
        let map = assParse.styleMap
        // Fast path: exact match.
        if let style = map[rawName] {
            return style
        }
        // SSA `*Name` / `Name*` partial-match markers: strip and match by affix.
        if rawName.hasPrefix("*") {
            let needle = String(rawName.dropFirst())
            if let key = map.keys.first(where: { $0.hasSuffix(needle) }) {
                return map[key]
            }
        } else if rawName.hasSuffix("*") {
            let needle = String(rawName.dropLast())
            if let key = map.keys.first(where: { $0.hasPrefix(needle) }) {
                return map[key]
            }
        }
        return nil
    }

    /// Attributed-string assembly for an SSA dialogue line.
    ///
    /// RE: 0x10147b930 (SubtitleDecode.buildSSAAttributedString, 1.3.15, 572B).
    /// Allocates an `NSMutableAttributedString`, splits the dialogue text into its
    /// inline-override blocks (`splitString`), and for each block delegates to
    /// `AssSubtitleParser.parseFormattedBlock` to produce the styled run, appending
    /// each. The binary special-cases drawing-mode blocks: a block beginning with
    /// `m ` / `m  ` that contains a `pos(` or `move(` directive is an ASS vector
    /// drawing command and is skipped (it carries no display text). Style attributes
    /// and base position come from the resolved `ASSStyle`.
    func buildSSAAttributedString(text: String, style: ASSStyle?) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let parser = AssSubtitleParser()
        let baseAttributes = style?.attrs ?? [:]
        let basePosition = style?.textPosition ?? TextPosition()
        // fontScale 0 selects parseFormattedBlock's unstyled early-out; use the
        // base font's point size when a style is present so styling is applied.
        let fontScale = (baseAttributes[.font] as? UIFont)?.pointSize ?? (style == nil ? 0 : 1)
        let blocks = splitString(text)
        for block in blocks {
            // Skip ASS vector-drawing commands (\p1 "m … pos(/move(") — no text.
            if (block.hasPrefix("m ") || block.hasPrefix("m  ")),
               block.contains("pos(") || block.contains("move(")
            {
                continue
            }
            let run = parser.parseFormattedBlock(
                block,
                text: block,
                fontScale: fontScale,
                baseAttributes: baseAttributes,
                basePosition: basePosition,
                styleName: ""
            )
            result.append(run)
        }
        return result
    }

    /// String split helper — splits an ASS dialogue/text body into its constituent
    /// lines/blocks for `buildSSAAttributedString`.
    ///
    /// RE: 0x10144d558 (SubtitleDecode.splitString, 1.3.15, 1036B). The decompile
    /// walks the string index-by-index splitting on the CR/LF pair (`\r\n`) and on a
    /// bare `\n`, emitting each run as a separate element and preserving a trailing
    /// empty run when the input ends on a separator (the `omittingEmptySubsequences`
    /// flag in the binary is false). Also reused cross-cluster by
    /// `AssParse.decodeUUEFontData` to split embedded-font blocks into lines.
    func splitString(_ string: String) -> [String] {
        // Match the binary's behaviour: split on \r\n and \n, keep empty runs.
        var lines = [String]()
        var current = ""
        var iterator = string.makeIterator()
        var pending: Character? = nil
        while true {
            let char: Character
            if let p = pending {
                char = p
                pending = nil
            } else if let next = iterator.next() {
                char = next
            } else {
                break
            }
            if char == "\r" {
                // Look ahead for the LF half of a CRLF; either way it terminates a run.
                if let next = iterator.next() {
                    if next == "\n" {
                        lines.append(current)
                        current = ""
                    } else {
                        lines.append(current)
                        current = ""
                        pending = next
                    }
                } else {
                    lines.append(current)
                    current = ""
                }
            } else if char == "\n" {
                lines.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        lines.append(current)
        return lines
    }
}
