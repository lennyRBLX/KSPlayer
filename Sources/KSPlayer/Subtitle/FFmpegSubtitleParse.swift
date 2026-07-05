//
//  FFmpegSubtitleParse.swift
//  KSPlayer
//
//  Forward 1.3.17 — NEW stateless FFmpeg subtitle parser (P4 M1 structure). 0 fields (§8.3). Bodies → P4 M2.
//
import Foundation

// FFmpegSubtitleParse @0x1039f16c4 — stateless parser (:KSParseProtocol, §8.5).
public class FFmpegSubtitleParse: KSParseProtocol {
    public init() {}
    // ⚑ UNRESOLVED → P4 M2: canParse / parsePart bodies
    public func canParse(scanner: Scanner) -> Bool { false }
    public func parsePart(scanner: Scanner) -> SubtitlePart? { nil }
}
