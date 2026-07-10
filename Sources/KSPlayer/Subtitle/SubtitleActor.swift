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
    // init(info:) — witness-verified against the inlined construction at BOTH willSets (FUN_101ab2540
    // selectedSubtitleInfo @0x101ab2688 / FUN_101ab2de4 secondarySubtitleInfo): SubtitleActor metadata accessor
    // (0x101aba99c) -> swift_allocObject -> swift_defaultActor_initialize -> store `info` (existential @actor+0x70..0x80)
    // + field defaults (searchGeneration=0 @+0x88, latestQueryTime=nil @+0x90/98, parts=[]). FULLY INLINED — no
    // standalone init function (locate_class_init P43: "init None" is correct for this final actor's trivial init).
    // `info` is stored once and never reassigned (could be `let`; a `nonisolated let` would additionally enable the
    // deferred size-fit's synchronous `actor.info` read in SubtitleModel.subtitle(currentTime:)).
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
        var result = await Self.delegateSearch(subtitleInfo, with: searchQuery)
        // 898c stage 1 — apply the query's text position to every TEXT part (image parts untouched;
        // query.size is NOT used). If the query carries a full textPosition, stamp it (B, 0x101ab8c1c);
        // else if it carries just a verticalAlign, override that on the part's existing position or the
        // SubtitleModel.textPosition default (A, 0x101ab89c8). render.position ← query+0x28.. / +0x18.
        if let textPosition = query.textPosition {
            for i in result.indices {
                if case .right(var text) = result[i].render {
                    text.position = textPosition
                    result[i].render = .right(text)
                }
            }
        } else if let verticalAlign = query.verticalAlign {
            for i in result.indices {
                if case .right(var text) = result[i].render {
                    var position = text.position ?? SubtitleModel.textPosition
                    position.verticalAlign = verticalAlign
                    text.position = position
                    result[i].render = .right(text)
                }
            }
        }
        // 898c stage 2 — a secondary track stamps its role onto every part (0x101ab8db4). render.styleRole
        // ← query.textRole (query+0x51); text @render+0x49, image @render+0x70.
        if query.textRole != .primary {
            for i in result.indices {
                switch result[i].render {
                case .right(var text):
                    text.styleRole = query.textRole
                    result[i].render = .right(text)
                case .left(var image):
                    image.styleRole = query.textRole
                    result[i].render = .left(image)
                }
            }
        }
        // 898c commit gate (0x101ab8ff0) — only the still-current search adopts results into `parts`.
        if generation == searchGeneration {
            if result.isEmpty {
                // no fresh parts — the display set is the existing parts active at query.time (0x101ab9380)
                result = parts.filter { $0.start <= query.time && query.time < $0.end }
            } else {
                // merge still-active existing parts not already present, dedup by (start,end) (0x101ab9284).
                // ⚑ the 898c non-empty pre-pass (0x101ab9024) builds a discarded scratch + short-circuits to
                //   commit when a result part has empty text.string — that edge case is not modeled here.
                for part in parts where part.start <= query.time && query.time < part.end && part.end != .infinity {
                    if !result.contains(where: { $0.start == part.start && $0.end == part.end }) {
                        result.append(part)
                    }
                }
            }
            parts = result
        } else {
            // 959c (FUN_101ab959c) — the reentrancy-stale path yields the parts at `latestQueryTime`, adopting
            // a non-empty fresh filter of `result` into `parts` as a side effect (this stale query's own
            // generation is never adopted). ⚑ inlined (an isolated helper can't `sending`-return actor parts).
            if let time = latestQueryTime {
                let filtered = result.filter { $0.start <= time && time < $0.end }
                if !filtered.isEmpty {
                    parts = filtered
                    result = filtered            // re-filtering by `time` is a no-op → return it whole
                } else {
                    result = parts.filter { $0.start <= time && time < $0.end }
                }
            } else {
                result = []
            }
        }
        // launder the actor-derived result across the `sending` return (§1 recon-chosen plumbing).
        nonisolated(unsafe) let out = result
        return out
    }

    // Concurrency plumbing (§1 — recon-chosen, binary-invisible; NOT a distinct binary function): the actor
    // delegates its non-Sendable `info`'s async `search` across the isolation boundary via a `sending` hop.
    private static func delegateSearch(_ info: sending any SubtitleInfo, with query: sending KSSubtitleQuery) async -> sending [SubtitlePart] {
        await info.search(with: query)
    }
}
