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
    // ⚑ s105: the binary declares this member ON THIS CLASS — the trie carries
    // `KSPlayer.FFmpegSubtitleParse.parsePart(scanner: __C.NSScanner) -> [KSPlayer.SubtitlePart]`
    // directly, not as a protocol-witness thunk, so it is an explicit declaration rather than the
    // inheritance the file header assumed. Body 0x10002d9dc is three instructions:
    //   adrp x0, 0x104112000 / ldr x0, [x0, #0xd00] / ret
    // and that GOT slot binds libswiftCore `__swiftEmptyArrayStorage`, i.e. it returns [].
    // ⚑[tool=bind_oracle ref=_swiftEmptyArrayStorage:0x104112d00 result=libswiftCore]
    // Identical to the KSParseProtocol extension default, which is why ICF folded them onto one
    // address — the fold is the CONSEQUENCE of them matching, not evidence of inheritance.
    public func parsePart(scanner _: Scanner) -> [SubtitlePart] { [] }

    public func canParse(scanner: Scanner) -> Bool { true }
}
