//
//  SubtitleParseRegistry.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — SubtitleParseRegistry_init at 0x101480b90,
//  6 call sites (FUN_101480df8, FUN_101480cd8, FUN_101480d18, FUN_101480d84,
//  SubtitleParse_loadAndParse_async, plus one more catalog entry).
//  Holds the fixed 5-parser registry consumed by SubtitleParse.
//

import Foundation

/// Registry of `KSParseProtocol` parsers tried in priority order.
///
/// The Forward binary contains a dedicated `SubtitleParseRegistry` type
/// whose initializer installs the canonical five parsers
/// `[AssImageParse, AssParse, VTTParse, SrtParse, FFmpegSubtitleParse]`.
/// In upstream KSPlayer the same set was carried on
/// `KSOptions.subtitleParses`; this reconstruction preserves both APIs:
/// `KSOptions.subtitleParses` remains the public configuration surface
/// (apps can prepend / append parsers there) while
/// `SubtitleParseRegistry` provides the typed-class wrapper that the
/// binary uses internally and that the dispatch path in
/// `SubtitleParse.loadAndParse_async` reads from.
public final class SubtitleParseRegistry {
    /// The shared registry instance read by `SubtitleParse`. Lazy so the
    /// parsers are not constructed at process start when subtitles may
    /// never be needed.
    public static let shared = SubtitleParseRegistry()

    /// Ordered parser list. Order matters: the first parser whose
    /// `canParse(scanner:)` returns true wins, so `AssImageParse` must
    /// precede `AssParse`, and `FFmpegSubtitleParse` must be last as the
    /// catch-all fallback.
    public private(set) var parsers: [KSParseProtocol]

    /// Initialise the registry with the canonical 5-parser set from the
    /// Forward binary. Equivalent to `SubtitleParseRegistry_init @
    /// 0x101480b90`.
    public init(parsers: [KSParseProtocol]? = nil) {
        self.parsers = parsers ?? SubtitleParseRegistry.defaultParsers()
    }

    /// The default parser set, in the binary's documented priority order.
    public static func defaultParsers() -> [KSParseProtocol] {
        [
            AssImageParse(),
            AssParse(),
            VTTParse(),
            SrtParse(),
            FFmpegSubtitleParse(),
        ]
    }

    /// Prepend a parser ahead of the built-ins. Useful for app-specific
    /// overrides where a custom parser should outrank the defaults.
    public func register(_ parser: KSParseProtocol, asFirst: Bool = false) {
        if asFirst {
            parsers.insert(parser, at: 0)
        } else {
            // Insert before the FFmpeg fallback so the catch-all stays last.
            if let fallbackIndex = parsers.lastIndex(where: { $0 is FFmpegSubtitleParse }) {
                parsers.insert(parser, at: fallbackIndex)
            } else {
                parsers.append(parser)
            }
        }
    }

    /// Remove every parser of the given concrete type from the registry.
    public func unregister<T: KSParseProtocol>(_: T.Type) {
        parsers.removeAll { $0 is T }
    }

    /// Find the first parser whose `canParse(scanner:)` returns true.
    /// Mirrors the dispatch in `SubtitleParse_loadAndParse_async @
    /// 0x101482858` which uses `swift_dynamicCast` to discriminate the
    /// witness tables.
    public func selectParser(for scanner: Scanner) -> KSParseProtocol? {
        parsers.first { $0.canParse(scanner: scanner) }
    }
}
