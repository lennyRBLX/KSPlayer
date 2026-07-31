# Session 76 work

## Verify first

1. Run `python3 scripts/recon_gate.py --mode handoff` from `/Users/jweaver/Desktop/Work/swift/play` — expect **PASS 31 / ANOMALY 0 / FAIL 3**. A run reporting fewer PASSes means you are on a stale `scripts/`. The 3 FAILs are known debt, not regressions: `agg_critical 5`, `agg_high 13`, `agg_unresolved 1`. Floor **281**. Anything else — adjudicate before doing any work.
2. **The head/ahead pins are deliberately not in this document.** They live in `reconstruction/handoff_baseline.json` and the gate checks them for you. If `git_head`/`git_ahead_origin` PASS, the pins are right.
3. Run `python3 scripts/recon_progress.py`. Its STAGES block is hand-maintained prose, not derived. Do not quote its "blocked on unresolved symbols 283" line (hardcoded at `recon_progress.py:105`) and do not quote its View-class field-debt line — it claims 71 REAL_FLAGs, s74 measured 23, and **s75 measured 28**. Treat every number in that block as unverified until you run the tool.
4. **The two-repo split.** Swift sources, the `forward` branch and these handoffs live in `/Users/jweaver/Desktop/Work/swift/KSPlayer`. The cwd `/Users/jweaver/Desktop/Work/swift/play` holds `scripts/` and `reconstruction/`, and both are gitignored there — tool fixes and verdicts are durable on disk but never committed. Address KSPlayer with `git -C`; run every `scripts/` command from `play`.
5. Read `reconstruction/handoff_baseline.json` block `captured_session75`, then `reconstruction/tool_fixes_s75.json`, `reconstruction/s75_gate_blast_radius.json` and `reconstruction/s75_pkgA_model464_blocked.json`. Those three are the index to everything below.
6. **`agg_unresolved 1` is correct and must not be "fixed" by relabelling.** `VideoSwresample_DVbodies_deferral_p3a` reconstructs no body and names three unwritten vtable bodies that exist in the binary. UNRESOLVED is the honest label.

## Do not redo — landed and verified in s75

7. **Package C is DONE (`2ba1cfa`).** `openFormatContext` now takes the whole `Either<URL, AbstractAVIOContext>` and returns three values. The `time: Double` phantom is gone, MEPlayerItem's projection switch is removed (the projection lives inside the function), and the `fileSize: 0` / `ioContext: nil` placeholders are gone from both call sites. `FFmpegSubtitle.init`'s own phantom `time: Double` went with it. Cleared 1 HIGH. Verdict `reconstruction/verdicts/openFormatContext_101a392a0.json` is DIVERGENT on three MED items and **not** on the signature.
8. **Package E's AudioEnginePlayer hunk is DONE (`2a42d39`).** `AudioEngineDynamicsPlayer.nbandEQ` recovered: type, access, `let`, default and field position each read rather than chosen. REAL_FLAG 1 → 0.
9. **Both s74 tool remnants are CLEARED.** `init_thunk_probe` selfcheck 23 → 26; all 42 INIT_THUNK slots re-screened, 8 of 8 flagged resolved, 0 disagreements remain. `l2_field_gate` selfcheck 40 → 63; the `export_trie_names.json` blind spot is closed.
10. **MEMORY.md is renumbered 1..78.** 13 new rules, rule 60 amended, old rule 53 deleted (its `KSPlayerLayerDelegate` precondition landed in s74), rule 77 now says give the takeover prompt in chat. Handoffs and durables citing old rule numbers above 8 are stale — rule 7 kept its number, the old rule 28 is now **rule 34**.

## Premises REFUTED in s75 — do not re-derive

11. **My own `l2_field_gate` change carried three defects, and only a corpus sweep found them.** The worst returned a WRONG type as a read one: `rsplit(' : ')` truncated every dictionary type, so `[Swift.Int32 : KSPlayer.FFmpegAssetTrack]` came back as `FFmpegAssetTrack]`. Every field that motivated the feature is a plain nominal type, which is exactly why the goldens were blind. **A tool's goldens do not cover a tool's blast radius — sweep the corpus (rule 50).**
12. **Package A's blocker is not what the s75 brief said.** It called `Model.swift:464` a one-line rule-7 respelling. The respelling is necessary — the mangle has no `Sg`, with `MetalPlayView.pixelBuffer` (same module, same protocol, WITH `Sg`) as a same-image control — but not sufficient. See step 24.
13. **`nbandEQ` belongs to `AudioEngineDynamicsPlayer`, not `AudioEnginePlayer`.** The s75 brief named the wrong class; the file was right. `AudioEnginePlayer`'s own six binary fields are `engine`, `sourceNode`, `timePitch`, `lastPrepareTime`, `minDelayAfterPrepare`, `volume`, and it needed no edit.
14. **The post-open nil check in `openFormatContext` is `cbz x26` at `0x101a39c0c`, not `0x101a39bc0`.** That address is the `ldur`. Corrected in source.
15. **View-class field debt is 28, not 23 and not 71.** Measured live after the trie signal was wired in. Handoff s75 step 23's "measured 14 → 0" is dead — re-scope Package E from a live sweep.

## Tool state

16. **`l2_field_gate` has a third binary type signal.** `fetch_property_type_from_trie` is offline (no Ghidra), class-scoped by construction, and ranked BELOW the field record so no prior PASS or FLAG can flip — it only fills gaps that previously read `bin=None`. It refuses rather than guesses when the matched accessors disagree.
17. **`init_thunk_probe` gained `noalloc_kind`**, populated only when a body performs no allocation, splitting the uninformative `NOT_A_THUNK` shape into `FATALERROR_STUB` / `REAL_BODY_NOALLOC` / `UNDECIDED_NOALLOC`. Purely additive; every shape string and consumer is untouched.
18. **STILL DEFERRED, and this is a judgement to re-make rather than inherit:** wiring `binding_gate` into the hook. It needs a live Ghidra program and a corpus-wide class enumeration. s75 left an offline enumeration of all 215 declared nominal types under `reconstruction/` — the stage-1 sweep, whose output is `reconstruction/s75_trie_sweep_stage1.json`. It is a derivation artifact, not a gated tool: it has no selfcheck and is not wired into `recon_gate`. Evaluate promoting it into `scripts/` with a golden before building a second enumeration.

## Ready to apply — unblocked, nothing outstanding

19. **I · `KSComplexPlayerLayer` stand-up.** 44 symbols in the binary, zero in the reconstruction. **Do this first: it gates J, which is worth 4 HIGH.** Read `reconstruction/kscomplexplayerlayer_inventory_s66.json`, and note that its `KSPlayerLayerDelegate` requirement count of 12 is WRONG — the descriptor at `0x1039ecebc` reads `NumRequirements = 11` three independent ways.
20. **G · `FormatContext.swift`.** Unblocked by C landing. File-disjoint from K now that C is done.
21. **K · `MEPlayerItem.swift`.** Unblocked by C landing.
22. **F · INIT_THUNK harvest.** The worklist at `reconstruction/pkgF_init_thunk_worklist_s74.json` now carries `fixed_probe_*_s75` columns and is trustworthy. **41 of 42 slots carry a full trie signature: harvest them, they need no derivation.** Scope F clear of whatever classes G, K and I touch.
23. **The 63 residual sweep candidates** in `reconstruction/s75_trie_sweep_stage1.json` are untriaged. They block no package. Give them to a background agent, not the critical path. Most are known normalization classes (nested-type qualifiers, generic parameter names, `@Published` backing storage, closure argument labels, composition order, IUO); a real divergence tail is mixed in.

## Blocked, and on what

24. **A · KSOptions — blocked on the VideoVTBFrame construction shape.** `python3 scripts/locate_class_init.py --class VideoVTBFrame` finds FOUR construction sites — `0x101a30780`, `0x101a6dcac`, `0x101a25ec0`, `0x101a661c0` — and every one reports `init None`. The compiler refuses the respelling with `Model.swift:491:5: return from initializer without initializing all stored properties`. Every escape is closed: no vpfi so no declaration default, rule 7 forbids `!`, and there is no init to read. **The unblocking unit is: derive the construction shape from the four inlined sites and recover the init the compiler inlined away.** Swift required one in the original source, so it is recoverable from the field writes, not invented. Full record in `reconstruction/s75_pkgA_model464_blocked.json`.
25. **B · `KSVideoPlayerView.openURL` — unchanged.** Blocked on `KSVideoPlayerModel`, which has zero occurrences in `Sources/`, and on `KSPlayerLayer.select(subtitleInfo:isSecondary:)`, absent from source. All derivation is done; evidence at `reconstruction/pkgB_openURL_*`.
26. **E remainder — blocked on types absent from source.** `MetalPlayView` needs a `Drawable` protocol absent from source, retirement of `DisplayLayerDelegate` together with `KSMEPlayer.swift:142,:337,:579`, and an `init(options:)` rewrite. `FFmpegAssetTrack` needs a `VideoToolboxDecode.swift` companion decision, and its `rotation` divergence is now ENFORCED by the gate — `FFmpegAssetTrack.swift:57` already carries a ⚑ saying the binary reads `UInt16` while source keeps `Int16` because `MediaPlayerProtocol` requires it. That is a deliberate strengthening, not a regression.

## Collision map — respect this when dispatching

27. **`FormatContext.swift` is written by G and H; `MEPlayerItem.swift` by K.** C is landed, so **G and K are now file-disjoint from each other and may run in parallel.** H still follows G. I touches a new class and collides with nothing.
28. **Check inheritance before declaring two packages disjoint.** File-level disjointness is necessary, not sufficient — a protocol migration reaches every conformer and every subclass of one.

## How to orchestrate — the throughput plan

29. **One orchestrator (rule 62).** Agents derive and propose; the orchestrator alone re-verifies against the binary, builds, gates, stages, commits, and writes `recheck.final_verdict` via `adjudicate_verdict.py`. Multiple orchestrators break the single-writer property that makes the faithful floor mean anything.
30. **Make agents return raw tool output, never a conclusion (rule 60).** The binary is immutable, so `llvm-objdump`, trie queries and `function_sizes` parallelize freely. Dispatch one agent per claim, each returning raw disassembly, and adjudicate the bytes yourself. Raw output is refutable by inspection; a conclusion is not.
31. **Build each unit alone before you stage it (rule 20).** Never batch a build across units — every commit on `forward` must independently build, or bisectability and per-unit verifiability are both lost. Use one target only to read a compiler error you will discard; use four targets before you stage.
32. **Run only one build or commit hook at a time (rule 21), and do only read-only work while it runs (rule 22).** Both read the working tree, and two concurrent builds contend on derived data. Verification and agent dispatch fill that machine time — s75 sat idle through two >5-minute hooks.
33. **Write every agent prompt so its premises can be refuted (rule 58)**, give each its own scratchpad, and fence it hard against writing to the KSPlayer repo or to `scripts/`.
34. **Correct the brief's own errors before dispatching.** s75 caught five, s74 caught four, and every correction held. Read every address, owning class and field name in this document from the binary before you use it (rule 67).

## Close out

35. Update `reconstruction/handoff_baseline.json` with a `captured_session76` block and refresh `head`, `ahead_origin` and `faithful_floor`. **Re-run `recon_gate --mode handoff` AFTER updating the baseline** — the gate reads the baseline at start, so a pre-update run reports progress as ANOMALIES. Take `ahead_origin` from `git rev-list --count origin/forward..forward`.
36. Record which packages landed, which were dispatched but not landed, and every premise the session refuted — the refutations have been the highest-value output of the last five sessions, above the code.
37. Write the session-77 handoff in this format at `docs/superpowers/specs/`, from the FINAL state rather than by patching a mid-session draft. **Do not write the takeover prompt into it (rule 77) — give the prompt in chat.**
