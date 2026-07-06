import Foundation

// FFmpegSubtitle @0x1039f1718 — Forward 1.3.17 `actor` ($defaultActor field record; type_kind_gate).
// §8.3 fields (7, reflection-authoritative: formatContext/decode/subtitleStreamIndex/preTime/startTime/
// endTime/parts) + §8.5 conforms KSSubtitleProtocol directly. Was an empty Phase-1 skeleton. Bodies → P4 M2.
actor FFmpegSubtitle: KSSubtitleProtocol {
    private let formatContext: FormatContext
    private let decode: SubtitleDecode
    private var subtitleStreamIndex: Int32 = 0 // ⚑ Int32 inferred (§8.6)
    private var preTime: Double = 0
    private var startTime: Double = 0
    private var endTime: Double = 0
    private var parts: [SubtitlePart] = []
    // ⚑ init shape inferred → M2 witness-verify (init @0x101a9f27c, alloc 168B)
    init(formatContext: FormatContext, decode: SubtitleDecode) {
        self.formatContext = formatContext
        self.decode = decode
    }

    // ⚑ UNRESOLVED → P4 M2 (Batch 4): subtitle(currentTime:) async + the real parts search. Signature migrated
    //   to search(with: KSSubtitleQuery) async (session 21, P55 ripple); body still a deferred stub.
    nonisolated public func search(with _: KSSubtitleQuery) async -> [SubtitlePart] { [] }
}
