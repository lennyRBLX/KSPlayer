//
//  SubtitleParse.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — SubtitleParse_loadAndParse_async at
//  0x101482858. Standalone async load-and-parse driver that creates an
//  NSScanner, strips control characters, iterates the registered parsers
//  using `swift_dynamicCast` to discriminate the SrtParse / AssParse
//  witnesses, and falls back to the FFmpegSubtitle actor when no text
//  parser in the registry matches.
//
//  The async entry point owns the no-match → FFmpegSubtitle fallback tail
//  (the actor needs the source URL to open its own AVFormatContext); the
//  synchronous `parse(data:)` core owns the registry dispatch and the
//  swift_dynamicCast witness discrimination.
//

import Foundation

/// Driver that loads subtitle bytes from a URL (or decodes from a Data
/// blob) and dispatches them to the first matching parser in
/// `SubtitleParseRegistry`.
///
/// Upstream KSPlayer inlines this work inside
/// `KSSubtitle.parse(data:encoding:)`; the Forward binary factors it
/// out into a standalone class with an async entry point. This
/// reconstruction preserves the binary's structure (so the API surface
/// the rest of the Forward sources expects is available) while keeping
/// the inline `KSSubtitle.parse(data:)` path working by delegating to
/// the same dispatch core.
public final class SubtitleParse {
    /// Errors emitted by the load-and-parse driver.
    public enum Failure: Error {
        /// None of the registry's parsers could claim the content.
        case noParserMatched
        /// The bytes could not be decoded under any of the candidate
        /// `String.Encoding`s.
        case undecodable
        /// A parser claimed the content but produced zero parts.
        case emptyParts
    }

    /// Runtime discriminator returned by the `swift_dynamicCast` probes the
    /// binary performs in the dispatch fall-through. The Forward decompile
    /// casts the selected parser against the `AssParse` and `SrtParse`
    /// witness tables and branches on the result: `1` means the cast hit the
    /// `AssParse` witness, `2` means it hit the `SrtParse` witness, `0` means
    /// neither (a non-text parser such as `AssImageParse` /
    /// `FFmpegSubtitleParse`). Reconstructed as a typed enum so the
    /// fall-through ordering (AssParse before SrtParse) is explicit rather
    /// than buried in raw witness-table pointer comparisons.
    ///
    /// RE: `SubtitleParse_loadAndParse_async @ 0x101482858` — "Uses
    /// `swift_dynamicCast` to detect SrtParse (returns 2) vs AssParse
    /// (returns 1)."
    public enum ParserWitness: Int {
        /// Cast missed both text witnesses (image/FFmpeg parser).
        case other = 0
        /// `swift_dynamicCast` hit the `AssParse` witness table.
        case ass = 1
        /// `swift_dynamicCast` hit the `SrtParse` witness table.
        case srt = 2
    }

    private let registry: SubtitleParseRegistry
    private let candidateEncodings: [String.Encoding]

    public init(registry: SubtitleParseRegistry = .shared, candidateEncodings: [String.Encoding]? = nil) {
        self.registry = registry
        self.candidateEncodings = candidateEncodings ?? SubtitleParse.defaultEncodings
    }

    /// Default decoding fallbacks (UTF-8 → Big5 → GB-18030 → UTF-16),
    /// matching the order `KSSubtitle.parse(data:encoding:)` uses
    /// upstream and the encoding sweep observable in the Forward binary.
    public static let defaultEncodings: [String.Encoding] = [
        .utf8,
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))),
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))),
        .unicode,
    ]

    /// Fetch the subtitle bytes from `url`, decode, scan, and parse.
    ///
    /// RE: `SubtitleParse_loadAndParse_async @ 0x101482858`.
    /// - Parameters:
    ///   - url: Subtitle file URL (local or remote).
    ///   - userAgent: Optional `User-Agent` for HTTP fetches.
    ///   - preferredEncoding: Try this encoding first before the
    ///     defaults. `nil` to use only the defaults.
    /// - Returns: Parsed `[SubtitlePart]` produced by the winning parser.
    public func loadAndParseAsync(url: URL, userAgent: String? = nil, preferredEncoding: String.Encoding? = nil) async throws -> [SubtitlePart] {
        let data = try await url.data(userAgent: userAgent)
        do {
            return try parse(data: data, preferredEncoding: preferredEncoding)
        } catch Failure.noParserMatched {
            // No text parser (ASS/VTT/SRT) in the registry claimed the
            // content. The binary's `loadAndParse_async` does not error here:
            // it falls back to the FFmpegSubtitle actor, which opens its own
            // AVFormatContext and lets FFmpeg detect/decode the format
            // (bitmap PGS/DVB/VOBSUB, embedded, or any text format the
            // scanner parsers missed). Drive that fallback from the URL we
            // already fetched.
            //
            // RE: `SubtitleParse_loadAndParse_async @ 0x101482858` — "Falls
            // back to FFmpegSubtitle on no match."
            return try await fallbackToFFmpegSubtitle(url: url)
        } catch Failure.undecodable {
            // The bytes weren't decodable as any candidate text encoding —
            // that is itself a strong signal of a binary subtitle stream.
            // Hand it to FFmpeg via the same actor fallback rather than
            // surfacing an error to the caller.
            return try await fallbackToFFmpegSubtitle(url: url)
        }
    }

    /// FFmpeg/bitmap/embedded decode fallback. Runs when the fixed text
    /// parser registry produces no match. Mirrors the binary's terminal
    /// `swift_dynamicCast` fall-through which, finding neither the `AssParse`
    /// (`1`) nor the `SrtParse` (`2`) witness, routes the content to the
    /// `FFmpegSubtitle` actor.
    ///
    /// RE: `SubtitleParse_loadAndParse_async @ 0x101482858` (fallback tail).
    private func fallbackToFFmpegSubtitle(url: URL) async throws -> [SubtitlePart] {
        let actor = FFmpegSubtitle()
        let parts = try await actor.loadFile(url: url)
        if parts.isEmpty {
            throw Failure.emptyParts
        }
        return parts
    }

    /// Synchronous registry-dispatch core. Decode `data`, scan, and run the
    /// fixed five-parser registry, returning the winning parser's parts.
    ///
    /// This reproduces the registry-iteration body of the binary's
    /// `loadAndParse_async`: it strips leading control characters with an
    /// `NSScanner` then walks the registered parsers, using the
    /// `swift_dynamicCast`-derived `ParserWitness` discriminator to honour
    /// the documented AssParse-before-SrtParse fall-through ordering. On a
    /// true no-match it raises `Failure.noParserMatched`, which the async
    /// entry points translate into the FFmpegSubtitle fallback (the binary
    /// has no synchronous error exit here — `parse(data:)` is the inlined
    /// dispatch core, the FFmpeg fallback is the async tail).
    ///
    /// Surfaces `Failure.undecodable` / `.noParserMatched` / `.emptyParts`
    /// instead of the legacy `KSPlayerErrorCode` `NSError`s, but
    /// `KSSubtitle.parse(data:)` continues to translate to the legacy codes
    /// for its callers.
    ///
    /// RE: `SubtitleParse_loadAndParse_async @ 0x101482858` (registry
    /// dispatch core; reads global `DAT_104458fd8`, control-char strip,
    /// `swift_dynamicCast` AssParse/SrtParse fall-through).
    public func parse(data: Data, preferredEncoding: String.Encoding? = nil) throws -> [SubtitlePart] {
        let encodings: [String.Encoding] = {
            if let preferredEncoding {
                var list = [preferredEncoding]
                list.append(contentsOf: candidateEncodings.filter { $0 != preferredEncoding })
                return list
            }
            return candidateEncodings
        }()

        var decoded: String?
        for encoding in encodings {
            if let s = String(data: data, encoding: encoding) {
                decoded = s
                break
            }
        }
        guard let text = decoded else {
            throw Failure.undecodable
        }

        let scanner = Scanner(string: text)
        _ = scanner.scanCharacters(from: .controlCharacters)

        guard let parser = registry.selectParser(for: scanner) else {
            // Registry exhausted with no `canParse` hit. Signal no-match so
            // the async driver can fall back to FFmpegSubtitle, rather than
            // treating this as a hard failure.
            throw Failure.noParserMatched
        }

        // Resolve the runtime witness the binary's `swift_dynamicCast`
        // probes would have produced for the selected parser. The cast
        // ordering is AssParse (1) before SrtParse (2); everything else is
        // `.other`. This is observational (it records which witness the
        // dispatch matched) and does not alter which parser runs, exactly as
        // in the decompile where the discriminator only steers the
        // fall-through and the already-selected parser is invoked.
        _ = Self.witness(for: parser)

        let parts = parser.parse(scanner: scanner)
        if parts.isEmpty {
            throw Failure.emptyParts
        }
        return parts
    }

    /// Classify a selected parser against the two text witnesses the binary
    /// checks via `swift_dynamicCast` in the dispatch fall-through.
    ///
    /// Classify a selected parser against the two text witnesses the binary
    /// checks via `swift_dynamicCast`: AssParse cast returns `1`, SrtParse
    /// cast returns `2`, anything else `0`.
    ///
    /// Note: per the RE notes `VTTParse` is meant to be a subclass of
    /// `SrtParse` (they differ only in the ms separator and the WEBVTT
    /// header), in which case an `is SrtParse` probe would also report a
    /// `VTTParse` instance as `.srt` — matching the binary. In the current
    /// KSPlayer source `VTTParse` is still an independent `KSParseProtocol`
    /// class, so it classifies as `.other` here until that subclassing lands
    /// (owned by `KSParseProtocol.swift`, see CROSS-FILE note). Either way
    /// this discriminator is observational and does not change which parser
    /// runs, so the difference is non-load-bearing for dispatch.
    ///
    /// RE: `SubtitleParse_loadAndParse_async @ 0x101482858`.
    static func witness(for parser: KSParseProtocol) -> ParserWitness {
        // Order matters and mirrors the decompile: AssParse probe first.
        if parser is AssParse {
            return .ass
        }
        // SrtParse probe second. Once VTTParse : SrtParse lands, the
        // `is SrtParse` test will also catch VTTParse, as in the binary.
        if parser is SrtParse {
            return .srt
        }
        return .other
    }
}
