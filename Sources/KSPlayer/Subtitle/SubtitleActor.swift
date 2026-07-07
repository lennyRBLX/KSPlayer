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

    // FUN_101ab6b5c/6c2c — inlined into SubtitleModel.searchSubtitle's Task at its single call site
    // (`await firstSubtitleActor?.reset(); await secondarySubtitleActor?.reset()`). Invalidates this
    // actor's in-flight search state. ⚑ method name unrecoverable (P28), recon-chosen.
    func reset() {
        searchGeneration += 1
        latestQueryTime = nil
        parts = []
    }

    // KSSubtitleProtocol requirement — witness impl 0x101ab9a44 (WT 0x1041daad0, async-fp 0x10356d4a8).
    // MUST stay `nonisolated`: the requirement carries non-Sendable KSSubtitleQuery/[SubtitlePart], so an
    // actor-isolated witness can't satisfy it. The witness hops onto the actor (9a44 task_switch) into the
    // isolated worker, laundering the non-Sendable crossings via the base's `nonisolated(unsafe)` idiom (P62).
    public nonisolated func search(with query: KSSubtitleQuery) async -> [SubtitlePart] {
        nonisolated(unsafe) let query = query
        return await bumpAndSearch(with: query)
    }

    // 9a5c (isolated) — the on-actor realization of the req: bump the generation, delegate to the gen-search.
    // ⚑ recon-named (P28): the 9a44→9a5c hop implies this isolated worker; source name unrecoverable.
    private func bumpAndSearch(with query: KSSubtitleQuery) async -> sending [SubtitlePart] {
        searchGeneration += 1
        return await search(with: query, generation: searchGeneration)
    }

    // Internal generation-guarded search (0x101ab8864 → 8884 → 8938 → 898c; three call sites: bumpAndSearch
    // above + the two SubtitleModel drivers FUN_101ab438c/4c54). Reentrancy-safe across the `await info.search`:
    // a newer search that bumps searchGeneration during suspension makes this call stale, so it neither records
    // its query time (8884 guard) nor commits its results (898c gate @0x101ab9558).
    func search(with query: KSSubtitleQuery, generation: Int) async -> sending [SubtitlePart] {
        // 8884 — adopt this generation + record the query time (skipped if a newer search already ran)
        if searchGeneration <= generation {
            searchGeneration = generation
            latestQueryTime = query.time
        }
        // 8884 delegate + 8938 receive — the datasource performs the actual (lazy, async) lookup.
        // Launder the non-Sendable info/query across info.search's nonisolated boundary (P62, base idiom;
        // §1 — the exact concurrency plumbing is recon-chosen/under-included, binary-invisible, not a logic claim).
        nonisolated(unsafe) let subtitleInfo = info
        nonisolated(unsafe) let searchQuery = query
        let result = await Self.delegateSearch(subtitleInfo, with: searchQuery)
        // 898c — only the still-current search commits to `parts` (the reentrancy gate)
        if generation == searchGeneration {
            // ⚑ UNRESOLVED → deep (898c FUN_101ab898c, ~700 lines — decoded skeleton in ledger later·120):
            //   the per-part positioning pass writes query.size→render.displaySize, query.textPosition (or the
            //   SubtitleModel.textPosition global via swift_once)→position, query.textRole→styleRole into each
            //   SubtitlePart.render (Either<SubtitleImageInfo, SubtitleTextInfo>), branching on textRole
            //   (query+0x50/+0x51) and the render case via value-witness copies; the empty-result path
            //   (898c @550-660) re-derives the display set from the existing `parts`. Novel Forward geometry
            //   (no base analog) — committing the datasource result UN-positioned pending that reconstruction.
            if !result.isEmpty {
                parts = result
            }
        }
        // 959c — the current-time filter (≈ base KSSubtitle.search(for:), migrated: `part == query.time`).
        // ⚑ APPROXIMATION: the decoded 898c per-branch return differs (still-current → the full committed
        //   `parts`; stale → 959c(result) without committing) — folded into this single time-filter pending
        //   the deep 898c/959c reconstruction (ledger later·120). Faithful gate + delegate above; exact
        //   return/commit branches deferred with the positioning.
        nonisolated(unsafe) let out = parts.filter { $0 == query.time }
        return out
    }

    // Concurrency plumbing (§1 — recon-chosen, binary-invisible; NOT a distinct binary function): the actor
    // delegates its non-Sendable `info`'s async `search` across the isolation boundary via a `sending` hop.
    private static func delegateSearch(_ info: sending any SubtitleInfo, with query: sending KSSubtitleQuery) async -> sending [SubtitlePart] {
        await info.search(with: query)
    }
}
