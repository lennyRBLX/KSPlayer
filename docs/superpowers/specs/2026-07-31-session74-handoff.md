# Session 74 work

## Verify first

1. Run `python3 scripts/recon_gate.py --mode handoff` from `/Users/jweaver/Desktop/Work/swift/play` — expect **PASS 28 / ANOMALY 0 / FAIL 3**. The 3 FAILs are known debt, not regressions: `agg_critical 7`, `agg_high 16`, `agg_unresolved 1`. Floor **277**, tree clean. Anything else — adjudicate before doing any work.
2. **The head/ahead pins are deliberately not written in this document.** They live in `reconstruction/handoff_baseline.json` and the gate checks them for you (MEMORY rule 55, and rule 62 now says the same). A handoff's own commit cannot contain its own hash, so a pin written in prose is stale the moment it is written — that is exactly what happened to the s72 handoff, which claimed head `8ed1153`/254 when the truth was `7587432`/255, and it cost reconciliation time. If `git_head`/`git_ahead_origin` PASS, the pins are right.
3. Run `python3 scripts/recon_progress.py`. Expect floor 277/1035, stages 10/18. **Do not quote its "blocked on unresolved symbols 283" line — that number is HARDCODED at `recon_progress.py:105` and is not derived.**
4. **The two-repo split.** Swift sources, the `forward` branch, and **these handoffs** live in `/Users/jweaver/Desktop/Work/swift/KSPlayer`. The cwd `/Users/jweaver/Desktop/Work/swift/play` holds `scripts/` and `reconstruction/`, and **both are gitignored there** (`.gitignore:129` and `:95`) — verdicts and tool fixes are durable on disk but never committed, and `play` reports a clean tree no matter what you change. Address KSPlayer with `git -C` (rule 13); run every `scripts/` command from `play` (rule 12).
5. Read `reconstruction/handoff_baseline.json` blocks `captured_session72` and `captured_session73`.
6. **`agg_unresolved 1` is correct and must not be "fixed" by relabelling.** `VideoSwresample_DVbodies_deferral_p3a` reconstructs no body and names three unwritten vtable bodies that exist in the binary. UNRESOLVED is the honest label.
7. **Do NOT read `reconstruction/fix_queue/` as the list of open divergences — it is STALE.** `aggregate_verdicts` writes it but never purges it, so it still holds entries for `CircularBuffer_init_101a16198` and `FormatContext_subtitleAssetTrackMap_101a36488`, both of which are now FAITHFUL. Derive the real list from the verdicts: every divergence whose verdict's `final` is `DIVERGENT`. Purging the queue is package **T2** below.

## Do not redo — landed and verified in s72 and s73

8. **Package L is DONE.** `adjudicate_verdict.py`'s decompile-cache guard is now scoped to body verdicts, mirroring `verdict_provenance_gate.py:78` (`"binary_addr" in v`). Selfcheck **9/9**. All five previously-unadjudicable verdicts are settled and the "unrecognized verdict state" warnings are gone.
9. **Package M is DONE** (`f419d26` + `76e65f6`). DemuxerIO: four `= nil` drops, `ioAction` retyped to non-optional `DemuxerIOAction`, five methods reordered to `process, setDelegate, readLoop, readPacket, cancelReading`, and the actor, its `State`, its `Event`, `DemuxerIODelegate` and the five methods all made `public`. `DemuxerIO_structural_M2` is FAITHFUL.
10. **`a2c8fed` removed a `duration:` parameter that never existed** from `FormatContext.init` and its two call sites.
11. **A new deterministic tool exists: `scripts/vtable_impl_oracle.py`** (selfcheck 17/17, golden anchored on DemuxerIO). Use it on any class whose access you need to settle — see step 15.

## Premises REFUTED — each verified against the binary by the orchestrator, do not re-derive

12. **MEMORY rule 7 was WRONG and is amended.** It said "no trailing `Sg` ⇒ write `T!`". A compiled control shows `T!` and `T?` emit the **identical** field-record typeref (`Q?` and `Q!` both → 0x4334; `String?` and `String!` both → 0x4342; the non-optional forms differ). IUO is **not recoverable from reflection at all**. The rule now reads: no trailing `Sg` ⇒ plain `T`, never `T?` and never `T!`. Any verdict spelling a field `T!` on field-record evidence cites something the evidence cannot show.
13. **Ghidra's default `__swiftcall` prototype prepends a phantom `double param_1`**, visible verbatim in the prefetch caches. It had been reconstructed as a REAL parameter in two committed FAITHFUL verdicts, both now DIVERGENT. **Treat any reconstructed signature whose parameter list begins with an unexplained `Double` as suspect until re-read against the trie.** In one of the two, the correct signature was already present in the same file four times over, inside its own `⚑[tool=resolve_fun_pins …]` markers, while the declaration above them contradicted it — so read a file's own markers before trusting its declarations.
14. **`VideoVTBFrame`'s 6 `binding_gate` MISMATCHes are NOT divergences.** `binding_refuted_s62.json` already categorises `VideoSwresample.dovi` — same field name, same optional-DOVI type, same subsystem — as an `IMPLICIT_NIL_OPTIONAL` over-call, and five of the six are optionals of that shape. See `reconstruction/binding_videovtbframe_s72.json`; `isKeyFrame` is a non-optional Bool NOT covered by that precedent. Zero of 288 verdicts record a binding mismatch as a divergence — the mechanism is `binding_refuted_*.json`, not verdict divergences.

## The access oracle — new in s73, use it, and respect its two limits

15. **`MethodDescriptor.Impl` (the int32 at descriptor+4 of each 8-byte vtable record) is NON-NULL iff the member is EXTERNALLY VISIBLE from its module AND the enclosing type is too.** This supersedes the old rule that nothing proves a *type* public. Run `python3 scripts/vtable_impl_oracle.py <mach-o> <ClassName>`, and `--selfcheck` first.
16. **The elimination confound is ruled out — do not re-litigate it.** A control `@inline(never)` *internal* method whose body is provably emitted (0x4264) and provably called (the public `drive` does `bl 0x4264` at 0x41e0) still has a NULL Impl. NULL means "not externally visible", never "body eliminated". An *internal* actor with **every** member spelled `public` emits ALL NULL — no member spelling fakes the enclosing type's visibility.
17. **LIMIT 1 — it cannot separate `public` from `@usableFromInline`, and neither can the export trie.** Both emit a non-null Impl, both get an EXTERNAL (`S`) `Tq` descriptor where internal ones are local (`s`), and **both are listed by the trie** — a control `@usableFromInline` method appears in `dyld_info -exports` exactly as a public one does. So a trie absence is rule-4 UNNAMED, never evidence for `@usableFromInline`. The tiebreak used for DemuxerIO: `@usableFromInline` serves `@inlinable`, and ProAVPlayer has none.
18. **LIMIT 2 — the controls are Xcode 26.4 and Forward was not built with it.** The mitigation is an in-image corroboration the controls could not fake: of DemuxerIO's 25 accessor records exactly three have non-null Impls — one standalone Getter plus two whose Setter+Modify are NULL — which is exactly `public var isEndOfStream` plus the two `public private(set) var`s. It remains a cross-toolchain inference. **Calibrating it against a KSPlayer-module class already known public would close it, and is worth doing before relying on it for a large access change.**

## Facts and traps — use these, do not rediscover them

19. **Importing a dylib into Ghidra displaces the current program and silently breaks three gate checks** (`preflight`, `sc_init_thunk`, `sc_str_literal`). Close the imported program afterwards and re-run `python3 scripts/preflight_program.py` until it prints `OK program=Forward-1.3.17`.
20. **`vtable_anchor_diff` needs three things aligned or it silently reports 0 classes**: `--src-prog <your dylib>`, `--module ProAVPlayer` (DemuxerIO is NOT in the KSPlayer module), and a `--src-classmap` built for *that* program via `build_module_classmap.py`. Its `[gate]` line prints only when the class actually PAIRED, and its `vt=` is the **source** vtable.
21. **The KSPlayer pre-commit hook takes over 5 minutes.** A foreground `git commit` times out and looks like a failure while the commit is still in flight. Run it in the background, wait for `WRAPPER_EXIT`, then confirm HEAD moved — and check for duplicates before retrying.
22. **`function_sizes.py` keys by SYMTAB name, so stripped addresses are absent from it.** For an extent on a stripped address, parse `llvm-objdump --macho --function-starts` and take the delta to the next start.
23. **A moved code block drags its comments into the staged diff**, so a whole-file reorder can trip the commit gate on pre-existing citations. Give them real markers rather than reaching for `--no-verify`: in s73 `av_read_frame` @`0x1030e6e78` came back **CONFIRMED** from `ffmpeg_name_oracle --addr … --resolve`, and `FUN_101b812b0` came back `NOT_IN_TRIE` from `resolve_fun_pins`.
24. Ghidra REST is on port **8089**. `llvm-objdump --macho --bind`: the symbol is the **8th** whitespace token; grep that table case-insensitively (UPPERCASE hex). A `0x1034xxxxx` stub needs a **12-byte** disassembly window.
25. **Three P28 "name unrecoverable" pins have now dissolved on contact with the trie** (`invalidateParts`, `addSubtitle(info:rebindSelection:)`, `select(subtitleInfo:)`). Test every remaining P28 pin against `export_trie_oracle --addr … --owner <Class>` before inheriting it.

## The plan — 14 packages in 4 tiers

26. **The single most useful planning fact: six packages cover the ENTIRE critical+high debt, exactly.** All 23 CRITICAL+HIGH divergences live in just 8 verdicts across 6 files. `T1` clears 2+2, `A` clears 2+3, `B` clears 2+4, `C` clears 0+1, `J` clears 0+4, `K` clears 1+2 — totalling 7 critical and 16 high. **Nothing else in the backlog touches `agg_critical` or `agg_high`**, so those six are the only path to a green gate; every other package moves the floor but not the FAILs.
27. **Packages are cut by FILE.** That is what makes them single-agent sized and what guarantees two agents' diffs never touch the same file, since the orchestrator applies every diff by hand.

### Tier 0 — orchestrator only, no agent in flight

28. **T1 · Apply Package H2.** The 7-hunk `KSSubtitle.swift` changeset is already derived and its four addresses are trie-verified OWNER_MATCH (`0x101ab6c88` `searchSubtitle(query:languages:)` with a non-optional `String`; `0x101ab68d4` `cleanParts()`, not private, body one instruction `b 0x101ab68d8`; `0x101ab3a3c` `(addSubtitle in _912797…)(info:rebindSelection:)`, private; `0x101ab8250` `(select in _912797…)(subtitleInfo:)`). Read `reconstruction/pkgH2_subtitlemodel_evidence_s72.json`. Apply bottom-up, hunks 7 → 1; hunks 1, 6 and 7 must land together. Two risks the derivation does not resolve: hunk 3 narrows `addSubtitle` to `private` (confirm every caller is in-file, rule 45), and the `KSPlayer` target has no `.swiftLanguageMode(.v5)` so Swift 6 strict concurrency applies to the two `nonisolated(unsafe)` launders — `@MainActor func searchSubtitle` is an equally binary-faithful alternative if the compiler objects. **Clears 2 CRITICAL + 2 HIGH.**
29. **T2 · Tooling window.** Run with no agent in flight (rule 48). Three items: wire `adjudicate_verdict.py --selfcheck` into `recon_gate` (it is 9/9 and nothing runs it; this takes the check count 31 → 32, so update the expected PASS count in the same change); wire `binding_gate` into the hook, reading `binding_refuted_s61/s62.json` and `binding_videovtbframe_s72.json` as known-exception lists; and make `aggregate_verdicts` purge `reconstruction/fix_queue/` before writing, which is the step-7 staleness bug. Write a golden before each (rule 38) and never weaken a gate to pass your own work (rule 36).

### Tier 1 — parallel-safe agent packages, file-disjoint, ready now

30. **A · KSOptions divergences.** Units `KSOptions_isUseDisplayLayer_1019bec28` (2 CRITICAL + 1 HIGH — a wrong signature and a "massive under-reconstruction", binary is 484 bytes / 121 instructions) and `KSOptions_sei_10000e52c` (2 HIGH). File: `KSOptions.swift`. **Clears 2 CRITICAL + 3 HIGH.** Decisive orchestrator check: `sei`'s binary body is a single `ret` (4 bytes, 1 instruction per LC_FUNCTION_STARTS) — trivially falsifiable — plus trie OWNER_MATCH on both addresses.
31. **B · KSVideoPlayerView.openURL.** Unit `KSVideoPlayerView_openURL_101ac99ac` @`0x101ac99ac` — the largest single divergence cluster. File: `KSVideoPlayerView.swift`. **Clears 2 CRITICAL + 4 HIGH.** Decisive check: the trie signature, and the recorded claim that "the subtitle branch targets a different object and a different operation" reduces to one call-target read.
32. **C · openFormatContext body.** @`0x101a392a0`, extent `0x101a392a0..0x101a3a0b8` (3608 B / 902 instr, orchestrator-measured). Recovered shape `openFormatContext(io: Either<URL, AbstractAVIOContext>, interrupt: IOInterruptContext, options: KSOptions?, inFormat: String?) throws -> (UnsafeMutablePointer<AVFormatContext>, Int64, AbstractAVIOContext?)`; parameter NAMES are not in the trie (free function), only arity and types are grounded. Determine where `fileSize` (x1, from `bl 0x1030fdb5c` on a path C-string; 0 on the fallback at `0x101a399dc`) and `ioContext` (x2; 0 at `0x101a398a8`) are produced. Then fix the declaration at `FormatContext.swift:464` and the `fileSize: 0`/`ioContext: nil` placeholders at `FFmpegSubtitle.swift:44` and `MEPlayerItem.swift:200`. **Clears 1 HIGH.** Decisive check: after landing, those placeholders must be gone.
33. **D · KSPlayerLayerDelegate migration (J1).** Migrate from the 4 source requirements to the 12 the binary declares and update every conformer; read `reconstruction/kscomplexplayerlayer_inventory_s66.json` first. Do this **before** any stand-up (rule 53). Decisive check: `conformance_walker` requirement count.
34. **E · IOSVideoPlayerView field debt.** 50 REAL_FLAGs in one file. Decisive check: `l2_field_gate` REAL_FLAG must go 50 → 0.
35. **F · INIT_THUNK re-screening.** All 42 slots re-screened with the fixed probe — the old shape ceilings misfiled an unknown number. No source edits; the output is a classified worklist, so verification is simply re-running `init_thunk_probe`.

### Tier 2 — gated

36. **G · FormatContext convenience inits.** Three bodies: `__allocating_init(io:options:inFormat:interruptBlock:) throws` @`0x101a34e54` (127 instr), `init(url:options:inFormat:)` @`0x101a3a0b8` (140 instr, thunk `0x101a33e78`), `init(string:options:inFormat:)` @`0x101a3a2e8` (235 instr, thunk `0x101a32e14`). Needs **C**. Read `reconstruction/pkgB_formatcontext_evidence_s72.json`; note its honest limit — #2 and #3 contain the `io:` pipeline INLINED, so a delegating spelling and a duplicated body are indistinguishable in emitted code.
37. **H · File topology ruling.** Enumerate the binary's KSPlayer `#fileID` literals (`llvm-objdump --macho --section=__TEXT,__cstring | grep -oE "KSPlayer/[A-Za-z0-9_]+\.swift"`), diff against the source tree, rule on which reconstruction filenames are inventions. Three findings are already in hand, each read from a `#file` literal: `performSeek` names `KSPlayer/FFmpegUtility.swift`; `RemuxerIOAction.reconstruct` names `ProAVPlayer/RemuxerIO.swift`; `SubtitleModel.searchSubtitle` names `KSPlayer/SubtitleModel.swift` while the class lives in `KSSubtitle.swift`. Needs **C** (file collision). Then relocate `performSeek` and re-adjudicate `FormatContext_performSeek_101a329d8`.
38. **I · KSComplexPlayerLayer stand-up (J2).** 44 symbols in the binary, zero in the reconstruction. Move `readyToPlay`/`finish` into the class body, retype `state` to `@Published public private(set)`, extract `change(state:)`, add `KSPlayerLayer.addSubtitle(to:)`. Needs **D**.
39. **J · PiP controller (J3).** Units `KSPictureInPictureController_slot0_1019c75cc` (3 HIGH) and `_slot2_1019c7648` (1 HIGH). **Clears 4 HIGH.** Needs **I** — and the reason is concrete, not stylistic: the binary's slot0 is `start(layer:)` taking a `KSPlayer.KSComplexPlayerLayer`, so that type must exist before the signature can be written.
40. **K · OutputStreamInfo init + `URL.ffmpegString`, then MEPlayerItem.startRecord.** `MEPlayerItem_startRecord_101a483d4` is 1 CRITICAL + 2 HIGH (source body EMPTY, binary body 183 instructions) and is blocked on two prerequisite units: `(extension in KSPlayer):Foundation.URL.ffmpegString` @`0x1019f59c4`, which does not exist in the reconstruction, and the throwing initializer @`0x101a1d014` (1952 instr) whose 9 argument slots are `x0=formatContext, (x1,x2)=filename String, w3=1, x4=0, x5=0, x6=0, x7=mediaType, [sp]=0` — the current `OutputStreamInfo.init(...)` also occupies 9 slots but has no parameter that can receive x7, so the two signatures cannot both be right. **Clears 1 CRITICAL + 2 HIGH.**
41. **L · MetalPlayView + VideoPlayerView field debt.** 12 + 7 REAL_FLAGs plus the `FFmpegAssetTrack` and `AudioEngineDynamicsPlayer` singles.
42. **M · New-class stand-ups, cheap half.** ThumbnailQueue + Anime4KPipeline, 10 units, names and signatures already recovered. Note the expensive half is NOT this package: SettingsView + CustomProgressView are 11 units, all NOT_IN_TRIE with no class and no recoverable name.

### Tier 3 — needs tooling first

43. **N · Unresolved-symbol tooling.** 283 bodies, the largest single category in the backlog. This is a tool build, so like T2 it runs alone with no agent in flight.

## Collision map — respect this when dispatching

44. **`FormatContext.swift` is written by C, G and H; `MEPlayerItem.swift` by C and K.** That whole group must serialise: **C → G → H**, with K after C. Do not dispatch two of them concurrently.
45. **A, B, D, E and F are genuinely parallel-safe** — five disjoint files, no shared target. That is the widest safe fan-out available.
46. **T1 does not collide with B.** H2 renames a method that `KSVideoPlayerView.swift:664` *calls*, but it does not edit that file.

## How to orchestrate

47. Hold the division of labour fixed: an agent **derives and proposes** (an evidence package, a proposed diff as TEXT, a draft `verdict`), and the orchestrator alone re-verifies load-bearing claims against the binary with `llvm-objdump` (rule 49), runs `validate_build.sh`, runs the class gates, stages, commits, and writes `recheck.final_verdict` via `adjudicate_verdict.py` (rules 33, 50).
48. **Forbid agents from writing anywhere under `/Users/jweaver/Desktop/Work/swift/KSPlayer`, forbid them from editing `scripts/`, and give each its own scratchpad subdirectory.** All three held in s72 and s73 across four concurrent agents with the KSPlayer tree clean throughout.
49. Write every agent prompt so its premises can be refuted (rule 47): the address, its extent measured by YOU from `LC_FUNCTION_STARTS`, the trie name, the claim to **test rather than confirm**, and an explicit statement that "absent from the trie" means unnamed, not absent (rule 4). This is what produced every refutation in steps 12–14.
50. **Persist every derivation-only agent's output to `reconstruction/` before the session ends.** H2's evidence survived only because it was written to a durable; nothing else carries a transcript forward.
51. **Re-verify agent claims yourself.** In s73 an agent's four load-bearing trie claims all held, but the checking is what turned "an agent says the verdict is wrong" into a committed fix — and in s72 the same checking caught a proposed fix that would have written a declaration default the binary does not have. Agents also corrected two of the handoff's own stale line numbers, so the handoff is not authoritative over the file.

## Close out

52. Update `reconstruction/handoff_baseline.json` with a `captured_session74` block and refresh `head`, `ahead_origin` and `faithful_floor`. **Re-run `recon_gate --mode handoff` AFTER updating the baseline** — the gate reads the baseline at start, so a pre-update run reports progress as ANOMALIES. Take `ahead_origin` from the gate's own resolver output (the `origin:` line), not from `git rev-list --count origin/main..HEAD`, which reports the fork-base measure and differs.
53. Record which packages landed, which were dispatched but not landed, and every premise the session refuted — the refutations have been the highest-value output of the last three sessions, above the code.
54. Write the session-75 handoff and its takeover prompt in this format, **in the KSPlayer repo** at `docs/superpowers/specs/`, and do not write head/ahead pins into it.

---

## Takeover prompt for session 74

Sessions 72 and 73 spent most of their value on refutations rather than volume. Session 72 unblocked five permanently-unadjudicable verdicts by scoping `adjudicate_verdict.py`'s cache guard to body verdicts, then found that Ghidra's default `__swiftcall` prototype prepends a phantom `double param_1` — reconstructed as a real parameter in two committed FAITHFUL verdicts, one of them contradicted by its own file's pin markers four times over — and refuted MEMORY rule 7 with a compiled control. Session 73 re-derived the `MethodDescriptor.Impl` access oracle from new controls, built `scripts/vtable_impl_oracle.py` around it, and landed DemuxerIO's whole-file reconstruction plus its access cascade. The floor went 276 → 278 → 276 → 277.

Your session has a plan already cut for it: **14 packages in 4 tiers, and six of them (`T1`, `A`, `B`, `C`, `J`, `K`) cover the entire critical+high debt exactly.** Nothing else moves `agg_critical` or `agg_high`.

1. Read `MEMORY.md` and obey every rule. Note that rules 7, 28 and 62 changed in s72–s73.
2. Read this handoff by path — it is in the **KSPlayer** repo: `/Users/jweaver/Desktop/Work/swift/KSPlayer/docs/superpowers/specs/2026-07-31-session74-handoff.md`.
3. Run `python3 scripts/recon_gate.py --mode handoff` from `/Users/jweaver/Desktop/Work/swift/play`.
4. Run `python3 scripts/recon_progress.py`.
5. Do Tier 0 first and alone — apply Package H2, then the tooling window — because both need no agent in flight.
6. Then dispatch Tier 1 (`A`, `B`, `C`, `D`, `E`, `F`) concurrently; they are five disjoint files plus a screening task and are the widest safe fan-out. Keep `C → G → H` strictly ordered and `K` after `C`.
7. Write every agent prompt so its premises can be refuted, and give each agent its own scratchpad and a hard fence against writing to the KSPlayer repo or to `scripts/`.
8. Verify each agent claim against the binary with `llvm-objdump` yourself before acting on it.
9. Run every gate on a touched class before you stage it; expect the pre-commit hook to take over 5 minutes, so commit in the background and confirm HEAD moved.
10. Commit each landed unit on the `forward` branch after its gate passes.
11. Stop at the first instruction you cannot ground and pin it.
