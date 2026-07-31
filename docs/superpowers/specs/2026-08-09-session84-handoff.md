# Session 84 work

This session is an **audit fan-out**: one orchestrator, N agents, 31 bodies. The agent protocol in
steps 12–21 is the substance — read it before dispatching anything.

## Verify first

1. **Run `ps -Ao pid,etime,command | grep -c "MacOS/claude --output-format stream-json"` FIRST.** Sessions 81 and 82 ran CONCURRENTLY in these repositories and each clobbered the other's close-out pins. If more than one session is live, stop and resolve it with the human before touching `reconstruction/` or committing on `forward`. `reconstruction/handoff_baseline.json` is the damage surface: one shared file, last writer wins.
2. Run `python3 scripts/recon_gate.py --mode handoff` from `/Users/jweaver/Desktop/Work/swift/play` — expect **PASS 31 / ANOMALY 0 / FAIL 3**. The 3 FAILs are known debt: `agg_critical 5`, **`agg_high 17`**, `agg_unresolved 1`. Floor **292**.
3. **The session-83 handoff's Verify-first is STALE — supersede it, do not follow it.** It predicts `PASS 30 / ANOMALY 1 / FAIL 3` and floor baseline 287. Both were true when written and are not now. Its step 4 asks you to adjudicate `KSPlayerLayer_playBack_slot72_s81` because `recheck` was null: that was DONE at 16:02 via `adjudicate_verdict.py --overturned`, the pin being the undecidable public-vs-open (rule 34). Do not re-adjudicate it.
4. Run `python3 scripts/recon_progress.py`. Its STAGES block is hand-maintained prose and is still WRONG in both directions. The MEASURED field-debt replacement is `reconstruction/s80b_field_debt_census.json`. The "blocked on unresolved symbols 283" line is a hardcoded literal at `recon_progress.py:105` and is still unverified.
5. **The two-repo split.** Swift sources, the `forward` branch and these handoffs live in `/Users/jweaver/Desktop/Work/swift/KSPlayer`. The cwd `/Users/jweaver/Desktop/Work/swift/play` holds `scripts/` and `reconstruction/`, both gitignored there — tools, verdicts and durables never appear in a commit. Address KSPlayer with `git -C`; run every `scripts/` command from `play`.
6. Read `reconstruction/handoff_baseline.json` block `captured_session81_audit_batch`, then `reconstruction/s81_audit_batch_and_kSPlayerLayer_trie_refutation.json`. The s80/s82/s83 durables remain valid background EXCEPT where steps 22–25 refute them.
7. **Floor accounting.** 292 = 286 (s80 close) + 1 (s82 `ControllerTimeModel`) + 5 (s81 audit batch: `KSPlayerLayer.playBack`, `PlayerView.pause`, `PlayerView.play`, `VideoPlayerView.panGestureChanged`, `IOSVideoPlayerView.isHorizonal`). `agg_high` 13 → 17 over the same span: 3 from `Coordinator_playerCurrentTimeTotalTime_s81`, 1 from `KSPlayerLayer_pause_slot61_s81`. New measured debt, not regression.
8. **Four of the 9 audits done so far came back DIVERGENT.** Do not plan on 31 more floor points. `KSPlayerLayer.pause` is a 6-statement source body against a 2-statement binary. Expect this fan-out to produce more measured debt than floor movement, and treat that as the correct outcome.

## The work: 31 AUDIT_ONLY bodies

9. **The queue is fully staged — do not re-derive it.** `screen_real_methods.py --all` over 234 REAL_METHOD slots gives route AUDIT_ONLY 40 (bodies that ALREADY EXIST in source, name recovered OWNER_MATCH, no verdict). 9 are done. All 31 remaining have their verbatim prefetch caches on disk, extents measured, and fingerprints captured at `scratchpad/fp33.txt` (regenerate with `body_fingerprint.py --json` if the scratchpad is gone).
10. **The 31, cheapest first** — 6,146 instructions total, median 157:

| class | slot | addr | instr | member |
|---|---|---|---|---|
| BrightnessVolume | 7 | `0x101aff150` | 32 | `move(to: UIView)` |
| KSPlayerLayer | 64 | `0x1019ccf9c` | 39 | `seek(time:completion:)` |
| AudioDescriptor | 17 | `0x101a68a74` | 41 | `updateAudioFormat()` |
| PlaneDisplayModel | 17 | `0x101a81a10` | 46 | `set(frame:encoder:)` |
| PlaneDisplayModel | 16 | `0x101a81f08` | 51 | `pipeline(pixelBuffer:)` (private) |
| VideoPlayerView | 41 | `0x101b2a96c` | 56 | `customizeUIComponents()` |
| KSPlayerResource | 4 | `0x101b16ba4` | 66 | `hash(into:)` |
| BrightnessVolume | 9 | `0x101aff5b8` | 84 | `appearView()` (private) |
| PlayerView | 13 | `0x1019fde2c` | 85 | `onButtonPressed(type:button:)` |
| SphereDisplayModel | 26 | `0x101a8c200` | 88 | `set(frame:encoder:)` |
| KSPlayerLayer | 78 | `0x1019cedcc` | 97 | `wirelessRouteActiveDidChange` (private) |
| KSAVPlayer | 95 | `0x1019a4b58` | 108 | `play()` |
| SphereDisplayModel | 27 | `0x101a8c360` | 108 | `touchesMoved(touch:)` |
| VideoPlayerView | 42 | `0x101b2af10` | 153 | `change(definitionIndex:)` |
| KSPlayerLayer | 65 | `0x1019cd038` | 157 | `seek(time:autoPlay:completion:)` |
| PlayerView | 18 | `0x1019fe194` | 163 | `set(url:options:)` |
| KSPlayerLayer | 70 | `0x1019ce474` | 175 | `changeLoadState<A>(player:)` |
| KSPlayerLayer | 63 | `0x1019cccd8` | 177 | `stop()` |
| KSPlayerLayer | 60 | `0x1019cc5f8` | 186 | `play()` |
| KSPlayerLayer | 74 | `0x1019ce7d0` | 201 | `finish<A>(player:error:)` |
| BrightnessVolume | 8 | `0x101aff1d0` | 204 | `volumeIsChanged` (private) |
| FileLog | 1 | `0x1019e38d0` | 220 | `log(level:message:)` |
| KSPlayerLayer | 55 | `0x1019cb674` | 251 | `set(url:options:)` |
| KSPlayerLayer | 68 | `0x1019cd5e0` | 266 | `prepareToPlay()` |
| KSAVPlayer | 94 | `0x1019a4300` | 313 | `seek(time:completion:)` |
| KSPlayerLayer | 79 | `0x1019cef60` | 314 | `audioInterrupted` (private) |
| IOSVideoPlayerView | 146 | `0x101b08f3c` | 342 | `updateUI(isLandscape:)` |
| KSPlayerLayer | 69 | `0x1019cda08` | 356 | `readyToPlay<A>(player:)` |
| IOSVideoPlayerView | 145 | `0x101b08664` | 410 | `updateUI(isFullScreen:)` |
| VideoPlayerView | 40 | `0x101b2c1bc` | 541 | `setupUIComponents()` |
| FFmpegDecode | 13 | `0x101a2220c` | 677 | `decodeFrame(from:)` |

11. **Batch them by CLASS, not by size.** 8 of the 31 are `KSPlayerLayer` and they share a source file, a vtable and a dispatch table; auditing them together means resolving `vtable_walk KSPlayerLayer --metadata-offset` once instead of eight times. Same for `BrightnessVolume` (3), `PlaneDisplayModel`/`SphereDisplayModel` (4, near-identical Metal bodies), `VideoPlayerView` (3), `IOSVideoPlayerView` (2), `KSAVPlayer` (2), `PlayerView` (2).

## How to orchestrate the agents

12. **The division of labour is fixed by MEMORY rules 60 and 62 and is not negotiable: AGENTS GATHER, THE ORCHESTRATOR DECIDES.** An agent returns raw tool output. It never returns "this looks faithful", never writes a verdict file, never runs `adjudicate_verdict.py`, never touches the git index, never runs `validate_build.sh` (rule 61) and never edits a tool (rule 59). One orchestrator writes and adjudicates every verdict, after re-reading each load-bearing claim against the binary itself.
13. **Give each agent exactly ONE body.** A per-class agent that returns eight bodies' output in one blob makes the orchestrator's verification pass harder, not easier, and a single agent's context limit becomes a silent truncation risk — which is exactly how s81 nearly recorded a false divergence (step 25).
14. **The agent's required output envelope**, verbatim, no prose between sections:
    - `EXTENT:` the `function_extents.py <addr>` line
    - `FINGERPRINT:` full `body_fingerprint.py <addr>` output
    - `BLR:` every `blr` line from `llvm-objdump -d` over the extent, with the 6 instructions before each — **`body_fingerprint` does NOT capture indirect calls** (step 19)
    - `DISASM:` the complete `llvm-objdump -d --start-address --stop-address` output for the extent
    - `SOURCE:` the source declaration and body, with file path and line numbers
    - `RESOLVED:` for every dispatch offset, witness index and unnamed callee in the body, the output of `vtable_walk` / `decode_witness_table` / `export_trie_oracle --addr … --owner <Class>` that names it — raw, not summarised
    - `UNRESOLVED:` a list of anything it could not name, with the exact command it ran and the exact result token
15. **Write every premise so the agent can refute it (rule 58).** Give it the claimed source location as a CLAIM: "the source body for this symbol is asserted to be `<file>:<lines>` — if the declaration there does not match the demangled symbol's labels, arity or types, say so in `UNRESOLVED` and stop." Do not tell the agent what the body is supposed to do.
16. **Never let an agent name a symbol from an address without `--owner`.** `export_trie_oracle --addr` on a folded address returns OWNER_AMBIG across hundreds of symbols (`0x10000e52c` is a 420-way fold). The owner class comes from the slot, not from the address (rule 27).
17. **The orchestrator's verification pass, per body, is not optional and is not a re-read of the agent's prose.** Re-run the ONE command behind each load-bearing claim yourself. In practice that is: the extent, the name of every called function the verdict depends on, and any dispatch-offset → slot resolution. Everything else can stand on the agent's raw output because it IS raw output.

## Traps that already cost a session — put these in the agent prompt

18. **`function_sizes.py` is useless for Swift symbols on this image** (LC_SYMTAB stripped to 385 aliased entries) and `llvm-objdump -d` labels EVERY range `_$s8KSPlayer9KSOptionsC9readyTimeSdvs`, which owns none of them. Bounds come from `scripts/function_extents.py` (new in s81; golden = 5 known extents + 2 negative controls, 178,886 entries). Ignore the disassembly's header label entirely.
19. **`scripts/body_fingerprint.py` (new in s81) has two KNOWN GAPS and they are recorded, not hidden.** (a) It records `bl`/`b` only, **NOT `blr`** — every witness call, vtable call and closure call is invisible to it, which is why step 14 demands a separate `BLR:` section. (b) A bare `adrp` page can surface as a spurious named "global"; `0x104c63000` reads as a YouTubePlayerKit static and is noise. Its own selfcheck (4 controls, 2 negative) caught four real bugs in it before any audit used it — including `load_trie()` returning `(blob, dataoff)` rather than a `Trie`, which made **every body report zero named globals**. That one is a false-FAITHFUL generator: a body touching two fields looked field-free. If you extend the tool, re-run `--selfcheck` and add a control first (rule 46).
20. **`--file` is required by BOTH `type_kind_gate` and `superclass_conformance_gate`**; without it they die in `TypeError: … not NoneType` (MEMORY rule 85).
21. **Check the POLARITY of every comparison, and BOTH halves of every optional-coalesce.** `IOSVideoPlayerView.isHorizonal` audited FAITHFUL only because `isHorizonal` is `width > height` (`Utility.swift:332`) and the binary's `fcmp d9,d8` + `cset mi` is the commuted form of the same predicate — the opposite register assignment would have been an inverted-condition divergence. Its `?? true` default is a separate `mov w0,#0x1` on its own branch; a body that only checked the value path would have missed it.

## Premises REFUTED in s81 — do not re-derive

22. **"KSPlayerLayer exports ZERO symbols in the trie" is FALSE, and it is load-bearing.** s82-handoff step 38 and s83-handoff step 27 both assert it. `export_trie_oracle --class KSPlayerLayer` returns **185 symbols**, including 11 vpfi declaration defaults and 6 inits. Consequence: `l2_field_gate` prints `_bufferingProgress src=Int bin=None — no mangled property symbol — type not verifiable` while the trie holds `KSPlayerLayer.bufferingProgress.setter : Swift.UInt8` at `0x1019c8a68`, against a source `Int`. **Tool unit, well specified:** make `merge_binary_type` fall back to the trie's `.setter`/`.getter` symbol type when there is no mangled property symbol. KSPlayerLayer has 11 REAL_FLAGs and 7 UNCHECKED fields waiting on exactly that instrument.
23. **Handoff s82 step 22's whole unit did not exist.** `Coordinator` already declares the `KSPlayerLayerDelegate` conformance and all five requirements it implements (`KSVideoPlayer.swift:250`). Settled with `decode_witness_table --wt 0x1041d4d18`: reqs 0–4 point into Coordinator's own code, reqs 5–10 all point at `0x10000e52c`, the ICF-folded empty default. Coordinator takes SIX defaults, not seven — it implements `player(layer:url:)` at `0x1019dbe04`.
24. **That "blocker" was a gate false positive and it is FIXED.** `superclass_conformance_gate.source_inherited()` could not match a QUALIFIED extension path, so a nested type's conformance was invisible. Now nesting-aware; RED 2-of-4, selfcheck PASS, corpus sweep 121 targets / 0 rows changed. A qualifier-blind and a suffix-match fix were both measured and rejected — `AppKitExtend.swift` really declares two different nested `Style` types.
25. **A truncated tool output nearly produced a false DIVERGENT.** s81 read a paged `fp33.txt` entry, saw no `KSOptions.enablePlaytimeGestures` global in `VideoPlayerView.panGestureChanged`, and began writing it up as a missing guard. Re-running the fingerprint directly showed the global present; the body is FAITHFUL. **Absence in a truncated view is not absence in the body** — an agent that returns a summary instead of raw output makes this failure mode invisible, which is the practical reason for rule 60.

## Blocked, and on what

26. **`Coordinator.player(layer:currentTime:totalTime:)` — structural blocker gone, body still DIVERGENT.** `ControllerTimeModel._bufferTime` now exists (s82 `ddb0028`). Four divergences remain in `Coordinator_playerCurrentTimeTotalTime_s81`: the `isPlaying` guard on the layer's Published `state` ∈ {3,4}, the `layer.player.playableTime` read via MediaPlayerProtocol witness slot `0x30`, the `frintp` ceiling where the source truncates, and the cross-clamp. The source's `Task { await model.subtitle(currentTime:) }` has no counterpart. Two residues pinned, not settled: which keypath pair is currentTime vs totalTime, and the source spelling of the ceil + range-check idiom.
27. **`KSPlayerLayer.state` is @Published in the binary and is NOT in the source** (keypath pair `0x103567ce0/0x103567d08`, read with the LAYER as enclosing instance). Source declares a plain `private(set) var` with a `didSet`. Folds into the KSPlayerLayer field work with step 22.
28. **`VideoPlayerView.delayItem`** — field type fully read (`Task<(), Error>?`, private, trailing `Sg`, payload flip only), one write site not two, blocked on the `autoFadeOutViewWithAnimation` funclets `0x101b304b0` / `0x101b305b4` and the keypath pair `0x103570240` / `0x103570268`. Record: `reconstruction/s82_videoplayerview_delayitem_blocked.json`.
29. **The startRecord CRITICAL** — blocked on OutputStreamInfo's construction shape; body fully derived in `reconstruction/s76_startRecord_derived_blocked.json`; the unblocking unit is deriving that shape from `0x101a1d014`'s own 7808-byte body and its other call sites.
30. **A · KSOptions** — blocked on the VideoVTBFrame construction shape (`reconstruction/s75_pkgA_model464_blocked.json`). Same class of blocker as startRecord: an inlined initializer with no readable symbol. A general method for recovering construction shape from inlined sites unblocks both and is still the highest-leverage tool this project could build.
31. **`T!` vs binary `T?` normalizer** — still 6 blocking lines. It is a change to the COMPARISON, not a table entry, and collides with `classify_flags`' `IUO_STANDIN` bucket. Land it alone, with the UNCHECKED count in both columns.
32. **Package F init bodies**, **KSComplexPlayerLayer** (15 bodies, ~2,500 instr), **MetalPlayView**/`Drawable`, and **extending the classmap to structs and enums** are unchanged; see s83-handoff steps 30–33.

## Close out

33. Adjudicate every agent-gathered body yourself with `adjudicate_verdict.py` (rule 41). Never delete `binary_addr` to get a verdict past its provenance guard — prefetch a cache instead (rule 81). Run `verdict_provenance_gate.py --class <C>` on every class you touched.
34. Update `reconstruction/handoff_baseline.json` with a `captured_session84` block and refresh `head`, `ahead_origin` and `faithful_floor`. **Re-run `recon_gate --mode handoff` AFTER updating the baseline.** Take `ahead_origin` from `git rev-list --count origin/forward..forward`.
35. Record how many of the 31 landed, the FAITHFUL/DIVERGENT split, and every premise the session refuted — the refutations have been the highest-value output of the last thirteen sessions, above the code. Then write the session-85 handoff in this format at `docs/superpowers/specs/`, from the FINAL state rather than by patching a mid-session draft. **Do not write the takeover prompt into it (rule 77) — give the prompt in chat.**
