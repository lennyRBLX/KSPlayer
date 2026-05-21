//
//  SubtitleParse.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — SubtitleParse_loadAndParse_async at
//  0x101482858. Standalone async load-and-parse driver that creates an
//  NSScanner, strips control characters, iterates the registered parsers
//  using `swift_dynamicCast` to discriminate the SrtParse / AssParse
//  witnesses, and falls back to FFmpegSubtitle when no text parser
//  matches.
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
        return try parse(data: data, preferredEncoding: preferredEncoding)
    }

    /// Synchronous core. Decode `data`, run the registry dispatch, and
    /// return the parts. Surfaces `Failure.undecodable` /
    /// `.noParserMatched` / `.emptyParts` instead of the legacy
    /// `KSPlayerErrorCode` `NSError`s, but `KSSubtitle.parse(data:)`
    /// continues to translate to the legacy codes for its callers.
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
            throw Failure.noParserMatched
        }
        let parts = parser.parse(scanner: scanner)
        if parts.isEmpty {
            throw Failure.emptyParts
        }
        return parts
    }
}
