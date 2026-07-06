//
//  SubtitleActor.swift
//  KSPlayer
//
//  Forward 1.3.17 — NEW per-track subtitle-holder actor (P4 M1 structure). §7.4. Bodies → P4 M2.
//
import Foundation

// SubtitleActor @0x1039f20b8 — `actor` ($defaultActor; type_kind_gate). Populated by the dual
// (primary/secondary) SubtitleModel search. Fields reflection-ordered; conforms KSSubtitleProtocol (§8.5).
public actor SubtitleActor: KSSubtitleProtocol {
    var parts: [SubtitlePart] = []
    var info: any SubtitleInfo
    var searchGeneration: Int = 0 // ⚑ Int store-evidenced (§7.5)
    var latestQueryTime: Double?
    // ⚑ init shape inferred → M2 witness-verify
    init(info: any SubtitleInfo) {
        self.info = info
    }

    // ⚑ UNRESOLVED → P4 M2 (Batch 3): the real search / subtitle(query:) async methods. Signature migrated
    //   to search(with: KSSubtitleQuery) async (session 21, P55 ripple); body still a deferred stub.
    public nonisolated func search(with _: KSSubtitleQuery) async -> [SubtitlePart] { [] }
}
