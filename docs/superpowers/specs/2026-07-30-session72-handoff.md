# Session 72 work

## Verify first

1. Run `python3 scripts/recon_gate.py --mode handoff` — expect **PASS 29 / ANOMALY 0 / FAIL 2**. The 2 FAILs are the known aggregate debt, not a regression: `agg_critical 7`, `agg_high 15` (both FELL in s71, from 8 and 18). Pins: head **`8ed1153`**, ahead **254**, floor **276**, tree clean. Anything else — adjudicate before doing any work.
2. Run `python3 scripts/recon_progress.py`. Expect floor 276/1035, stages 10/18. **Do not quote its "blocked on unresolved symbols 283" line — that number is HARDCODED at `recon_progress.py:105` and is not derived.**
3. **The two-repo split.** Swift sources and the `forward` branch live in `/Users/jweaver/Desktop/Work/swift/KSPlayer`. The cwd `/Users/jweaver/Desktop/Work/swift/play` holds `scripts/` and `reconstruction/`, **and both are gitignored there** — verdicts and tool fixes are durable on disk but are never committed, and `play` will keep reporting a clean tree no matter how much you change. Only KSPlayer source changes get commits. Address KSPlayer with `git -C` (Rule 13); run every `scripts/` command from `play` (Rule 12).
4. Read `reconstruction/handoff_baseline.json` block `captured_session71` — it is long because s71 refuted several inherited premises, and every refutation in it was re-verified against the binary by the orchestrator, not taken from an agent.
5. Read `reconstruction/h1_searchSubtitle_evidence_s71.json` before starting Package H2. It is the ONLY durable record of the H1 derivation; that agent landed nothing and its transcript is gone. Note it separates **orchestrator_verified** from **agent_claims_NOT_independently_verified** — treat the second list as needing your own `llvm-objdump` check before you build on it.

## Do not redo (landed + verified in s71)

6. Treat as DONE — 8 commits on `forward`, `2d5293d..8ed1153`: `40aa612` CircularBuffer `isClearItem` + UInt widths + the track inits' 4th argument; `dec4432` nextPowerOf2 zero-guard removed; `f95ec9c` `SyncPlayerItemTrack.isNeedKeyFrame`; `b645af3` doviData optionality; `02a2082` Package I; `37d6117` Package G; `b831bdc` Package F; `8ed1153` Package E.
7. **`CircularBuffer.init` is SETTLED — do not re-derive it.** `init(initialCapacity: UInt, sorted: Bool, expanding: Bool, isClearItem: Bool)`, trie symbol `$s8KSPlayer14CircularBufferC15initialCapacity6sorted9expanding11isClearItemACyxGSu_S3btcfC`, corroborated by `__swift5_fieldmd` order `[_buffer, condition, headIndex, tailIndex, expanding, sorted, isClearItem, destroyed, mask, maxCount, fps]`. Its verdict `CircularBuffer_init_101a16198` is FAITHFUL. **An earlier session had already recorded all of this and two later sessions re-derived it from scratch** — grep `reconstruction/verdicts/` for the class before deriving any signature (MEMORY rule 54).
8. **`FUN_101a33460` and `FUN_101a383c0` are MERGED bodies**, shared by three Frame specializations. The thunks `0x101a3340c` / `0x101a33428` / `0x101a33444` supply ONLY x4/x5 (the metadata pair) and x6 (the CircularBuffer init entry, called via `blr x19`), so **x0..x3 are the real Swift arguments**. Do not infer arity from register count in a body of this shape.
9. **Do not re-attempt `0x101b7e700` as a source body.** It is dead, ICF-folded code: both operands arrive indirectly in x0/x1 with no swiftself, it is absent from the vtable and from every method descriptor, and its sole incoming edge is a 4-byte alias that is itself unreferenced. The `didSet` hypothesis is refuted and `DemuxerIO_slot29_method_101b812b0` stands untouched.
10. **`RemuxerIOAction.reconstruct` throws — confirmed, not refuted.** Prologue saves x28..x30 but NOT x21; the `mov x21,x25` / `mov x25,x21` shuttle reaches the epilogue; both call sites emit `mov x21,#0` and test x21 after. Its name is ground truth from the `#function` literal.

## Facts to use, not rediscover

11. **The bind-table column, restated because it cost four independent readers time in s71.** The symbol is the **8th whitespace token** = `awk $8` = Python `f[7]`. The inherited phrasing "field 7, not field 5" is correct only 0-indexed; in awk terms `$7` is the DYLIB. Golden-control every such reader before use: `0x103458554` / `0x103458548` / `0x10345856c` must return the CMTime `init(value:timescale:)` / `-` / `seconds` symbols.
12. **Ghidra REST is on port 8089**, `prefetch_decompiles.py`'s documented default. A ping to 8192 returns connection-refused and looks exactly like a dead server.
13. **Resolving a `0x1034xxxxx` stub**: it is `adrp x16 / ldr x16,[x16,#off] / br x16`; disassemble with a **12-byte** window, because 16 bytes swallows the next stub's `adrp` and silently gives a wrong page. A `br x16` masks to `0xd61f0000`, not `0xd61f0200` — a wrong mask here fails the golden control rather than lying, which is the point of running it.
14. **A `__got` slot missing from `--macho --bind` output may still be a bind** — grep the bind table case-insensitively, because it prints addresses in UPPERCASE hex (`0x104112E48`). Only if it is genuinely absent is it an internal chained-fixup rebase (bit 63 clear ⇒ target `(value & 0xFFFFFFFFF) + 0x100000000`).
15. **Swift string literals carry a +32 nativeBias**, emitted as `add #0xNNN; sub #0x20`. A small string lives in two registers with a discriminator `0xE0 | count` in the top byte of the second — that is how `"aac_adtstoasc"` (count 13) was decoded in s71 from a source that claimed `"aac_adts"`.
16. **`l2_field_gate`'s unscoped property-symbol matching is a live false-positive source.** It PASSed `DemuxerIO.retryCount` as `Int` on a match belonging to another class; only its own hedge text (`[unscoped match — not class-proven; verify]`) flagged it. When an unscoped gate result and a class-scoped trie symbol disagree, the trie wins.
17. **`ffmpeg_name_oracle` has a `--resolve` mode and its `--candidate` mode is unsound** — never use `--candidate`. Invoke as `--addr 0x… --resolve`. `av_bsf_get_by_name` @`0x102957ca0` returns **UNKNOWN**, not CONFIRMED, and source's "(oracle-CONFIRMED)" annotation on it was false.

## How this session is orchestrated

18. Hold the division of labour fixed: an agent **derives and proposes** (evidence package, proposed source diff as TEXT, draft `verdict` field), and the orchestrator alone re-verifies load-bearing claims against the binary with `llvm-objdump` (Rule 49), runs `validate_build.sh`, runs the class gates, stages, commits, and writes `recheck.final_verdict` via `adjudicate_verdict.py` (Rules 33, 50).
19. **Forbid agents from writing to any file under `/Users/jweaver/Desktop/Work/swift/KSPlayer`.** In s71 six concurrent agents returned text diffs and the orchestrator applied them; two packages touched neighbouring files and would have collided.
20. **Give each agent its own scratchpad subdirectory.** In s71 concurrent agents overwrote each other's helper scripts inside the shared session scratchpad, and it reached the orchestrator too — a stub resolver silently returned another agent's output format mid-verification.
21. Write every agent prompt so its premises can be refuted (Rule 47): give the address, its exact extent from `LC_FUNCTION_STARTS` measured by you, the trie name, the claim the agent is asked to **test rather than confirm**, and an explicit statement that "absent from the trie" means unnamed, not absent (Rule 4). In s71 this produced four premise refutations that would otherwise have been built on.
22. **Persist every derivation-only agent's output to `reconstruction/` before the session ends.** H1's evidence survived only because it was written to a durable at the end; nothing else would have carried it to H2.

## Package L — the Package D adjudication blocker (run alone, tool change, do this FIRST)

23. Run `python3 scripts/recon_gate.py --mode handoff` and confirm the 5 `unrecognized verdict state` warnings still appear for `DemuxerIO_structural_M2`, `VideoSwresample_DVbodies_deferral_p3a`, `VideoSwresample_DVbodies_prepass_p3a`, `VideoToolboxDecode_struct_p3a`, `VideoVTBFrame_struct_p3a`.
24. Confirm the blocker yourself before changing anything: all five have no `decompile_cache` and `binary_addr: null`, `adjudicate_verdict.py:39-40` hard-refuses without `decompile_cache.verbatim`, and `verdict_provenance_gate.py` **exempts** exactly those (it only inspects verdicts carrying a `binary_addr`). The two tools disagree; that is the whole bug.
25. Write a golden anchored on a known answer FIRST (Rule 38), then teach `adjudicate_verdict.py` the same non-body exemption `verdict_provenance_gate.py` already implements, and/or give `aggregate_verdicts.py` a non-code-verdict bucket like its existing `ANCHOR_MISMATCH` one. Run with **no agent in flight** (Rule 48). Do NOT weaken the `decompile_cache` requirement for verdicts that DO carry a `binary_addr` (Rule 36).
26. Then adjudicate the five, using s71's per-file rulings, which the orchestrator verified: `VideoToolboxDecode_struct_p3a` → **FAITHFUL** (its recorded doviData FLAG was silently fixed by commit `26fb2fe`; `l2_field_gate` now reports REAL_FLAG 0) — this is the only one that moves the floor, to 277. `VideoSwresample_DVbodies_deferral_p3a` → **UNRESOLVED** (three unwritten vtable bodies at slots 28/30/32, all present in the binary); this will correctly turn `agg_unresolved` from PASS to FAIL — that is the honest outcome, not a reason to pick another label. `VideoVTBFrame_struct_p3a` → its REAL_FLAG was fixed in `b645af3`, so re-check the gate and adjudicate on the result. `VideoSwresample_DVbodies_prepass_p3a` reconstructs nothing and should leave the counted corpus rather than take a state. `DemuxerIO_structural_M2` — re-run `vtable_anchor_diff.py --only-class DemuxerIO` against a fresh dylib first; s71 refuted its headline "not binary-determinable" accessor residual (the binary's 8 accessor triples map 1:1 onto the 8 `var` stored properties; the 2 `let`s emit none), which if confirmed makes its method-order residual fixable rather than excusable.

## Package B — the last three FormatContext bodies (one agent; run before C)

27. Reconstruct `__allocating_init(io:options:inFormat:interruptBlock:) throws` @**0x101a34e54** (127 instr, extent 0x101a34e54..0x101a35050), trie signature `io: Either<Foundation.URL, AbstractAVIOContext>, options: KSOptions?, inFormat: String?, interruptBlock: (@Sendable () -> Bool)?`; `Either<Left, Right>` already exists at `Utility.swift:772`. **Read `reconstruction/verdicts/openFormatContext_101a392a0.json` before disassembling the callee at 0x101a392a0.**
28. Reconstruct the convenience init body @**0x101a3a0b8** (140 instr; `__allocating_init` 0x101a33e78).
29. Reconstruct the convenience init body @**0x101a3a2e8** (235 instr; `__allocating_init` 0x101a32e14).
30. For each of the three, prefetch its verbatim cache with `prefetch_decompiles.py --worklist <units.json>`, audit against that cache, and land the verdict in the same session the body lands.

## Package C — file topology (one agent; needs B landed first)

31. Enumerate the binary's 54 KSPlayer `#fileID` literals with `llvm-objdump --macho --section=__TEXT,__cstring | grep -oE "KSPlayer/[A-Za-z0-9_]+\.swift"`, diff them against the source tree's basenames, and rule on which reconstruction filenames — the whole `Remux/` directory among them — are inventions; note that `FFmpegUtility` is additionally a Forward-added **type** (14 orphan-trie symbols, no source).
32. Fold in the three file-identity findings s71 produced, each read from a `#file` literal: `performSeek` names `KSPlayer/FFmpegUtility.swift`; `RemuxerIOAction.reconstruct` names `ProAVPlayer/RemuxerIO.swift`, not `RemuxerIOAction.swift`; and `SubtitleModel.searchSubtitle` names `KSPlayer/SubtitleModel.swift`, while the class currently lives in `KSSubtitle.swift`.
33. Only after that ruling, relocate `performSeek` and re-adjudicate `FormatContext_performSeek_101a329d8`.

## Package H2 — the SubtitleModel atomic commit (needs H1, which is DONE)

34. Read `reconstruction/h1_searchSubtitle_evidence_s71.json` and independently verify anything you intend to rely on from its `agent_claims_NOT_independently_verified` list.
35. Land as **one atomic commit**: rename `KSSubtitle.swift:712` to `private func invalidateParts()`; add `public func cleanParts()` (0x101ab68d4 is a 1-instruction `b` into 0x101ab68d8); stand up the real `searchSubtitle(query:languages:)` from the H1 durable; and change the `translationSession` setter call site at `KSSubtitle.swift:365` from `searchSubtitle(query: nil, languages: [])` to `invalidateParts()`. Doing any part alone breaks `KSVideoPlayerView.swift:664`.
36. In the same pass retire the obsolete `⚑ P28 param name unrecoverable` pin at `KSSubtitle.swift:483`: slot96 0x101ab3a3c is trie-verified as `(addSubtitle in _912797…)(info:rebindSelection:)` — private, second label `rebindSelection` not `reselect` — and slot97 0x101ab3d64 as `(rebindSelectionIfNeeded in _912797…)(to:)`. **This is the cautionary precedent for every P28 recon-name: that one turned out wrong once the trie was consulted properly.**

## Packages J1–J3 — the strict chain

37. **J1** — migrate `KSPlayerLayerDelegate` from its 4 source requirements to the 12 the binary declares, updating every conformer; read `reconstruction/kscomplexplayerlayer_inventory_s66.json` first, and do this **before** any stand-up (MEMORY rule 53).
38. **J2** (needs J1) — move `readyToPlay`/`finish` into the class body, retype `state` to `@Published public private(set)` and extract `change(state:)`, add `KSPlayerLayer.addSubtitle(to:)`, and stand up `KSComplexPlayerLayer : KSPlayerLayer`.
39. **J3** (needs J2) — replace `restoreUserInterfaceForPictureInPictureStop` with `player.pipController?.stop(restoreUserInterface: true)`, reduce `KSPictureInPictureController.start`/`.stop` to their one-statement bodies, and flip the two `KSPictureInPictureController` slot verdicts via `adjudicate_verdict.py`.

## Package M — the DemuxerIO whole-file decision

40. Rule on `DemuxerIO.swift` lines 109/111/114/122, which carry `= nil` on `var`s of optional type — forbidden by MEMORY rule 6, and `export_trie_oracle`'s own docstring says a `vpfi` cannot prove such a default either way. s71's Package F left them deliberately, as a whole-file decision rather than a per-line one. Decide all four together.
41. Rule on `DemuxerIO.ioAction` while you are there: `dump_field_type_mangles.py DemuxerIO` field-record index 9 is `let <SYM:1@0x1039f55c0>_p` — a protocol existential with **no trailing `Sg`**, i.e. NOT Optional — against `private let ioAction: DemuxerIOAction?` at line 120. The tool demonstrably emits `Sg` when present (index 11, `delegate`, is `…_pSgXw`). This also bears on `readPacket`'s `ioAction!` force-unwrap.
42. Rule on whether `actor DemuxerIO` should be `public`: it carries `vpMV` property descriptors on three members, and `vpMV` is only emitted for public properties, which requires a public type. No project rule proves a *type* public, so this needs an explicit decision rather than an inference.

## Close out

43. Update `reconstruction/handoff_baseline.json` with a `captured_session72` block, and refresh `head`/`ahead_origin`/`faithful_floor`. **Re-run `recon_gate --mode handoff` AFTER updating the baseline** — the gate reads the baseline at start, so a pre-update run reports the progress as ANOMALIES. Take `ahead_origin` from the gate's own resolver output (the `origin:` line), not from `git rev-list --count origin/main..HEAD`, which reports the fork-base measure and differs.
44. Record in that block which packages landed, which were dispatched but not landed, and every premise the session refuted — s71's refutations were the highest-value output it produced, above the code.
45. Write the session-73 handoff and its takeover prompt in this format.

---

## Takeover prompt for session 72

Session 71 was three things. **Package A** recovered the 4th initializer argument that both `subtitleAssetTrackMap` construction sites emit — and refuted the handoff's premise for it in three separate places, then discovered an earlier session had already recorded the answer in a verdict nobody re-read. **Package K** fixed two gate defects, each with a golden control written and confirmed RED before the fix: `superclass_conformance_gate` could not parse a generic class declaration at all and silently mis-read every generic type in the project, and `l2_field_gate` lacked the `os_unfair_lock` typedef/struct-tag equivalence. **The parallel-safe set** (D, E, F, G, H1, I) was dispatched as six concurrent derive-and-propose agents; four premises were refuted, one agent's proposed fix was wrong and was caught by orchestrator re-verification, and four packages landed after that check. Floor 273 → 276, `agg_critical` 8 → 7, `agg_high` 18 → 15.

1. Read `MEMORY.md` and obey every rule.
2. Read this handoff by path (`docs/superpowers/specs/2026-07-30-session72-handoff.md`).
3. Run `python3 scripts/recon_gate.py --mode handoff`.
4. Run `python3 scripts/recon_progress.py`.
5. Do Package L first and alone — it is a `scripts/` change, and no agent may be in flight while it lands.
6. Dispatch the remaining packages only in the order this handoff sets, and write each agent prompt so its premises can be refuted.
7. Verify each agent claim against the binary with `llvm-objdump` yourself; in s71 this caught a proposed fix that would have written a declaration default the binary does not have.
8. Run every gate on a touched class before you stage it.
9. Commit each landed unit on the `forward` branch after its gate passes.
10. Stop at the first instruction you cannot ground and pin it.
