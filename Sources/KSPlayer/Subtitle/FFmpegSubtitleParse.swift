//
//  FFmpegSubtitleParse.swift
//  KSPlayer
//
//  Forward 1.3.17 — NEW stateless FFmpeg subtitle parser (P4 M1 structure). 0 fields (§8.3). Bodies → P4 M2.
//
import Foundation

// FFmpegSubtitleParse @0x1039f16c4 — stateless parser (:KSParseProtocol, §8.5).
// canParse = `{ true }` (witness 0x10002c740 = `return 1`); parsePart INHERITS the KSParseProtocol
// extension default `{ [] }` (witness 0x10002d9dc, shared with AssImageParse) — FFmpeg subtitles are
// decoded via the FFmpeg subtitle pipeline, not the Scanner text-parse path.
public class FFmpegSubtitleParse: KSParseProtocol {
    public init() {}
    public func canParse(scanner: Scanner) -> Bool { true }
}
