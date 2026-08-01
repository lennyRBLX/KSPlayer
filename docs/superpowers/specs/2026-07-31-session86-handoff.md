# Session 86 work

Session 85 closed the AUDIT_ONLY backlog (31/31), split MEMORY.md into knowledge/control, landed
four tool sweeps, re-verified the faithful floor against a tool defect, and killed a four-handoff-old
hardcoded literal. **Session 86 runs the AUDIT WAVE.** Sessions 87 and 88 run the two waves after
it; the plan for all three is "The wave sequence" below and the unit lists are already on disk.

Note on filenames: this file and the session-85 handoff are BOTH dated 2026-07-31 (the real clock).
Filenames here do not sort in session order. **Order by the session number.**

## Verify first

1. Run `ps -Ao pid,etime,command | grep -c "MacOS/claude --output-format stream-json"` FIRST. One
   live session prints **4** lines (a disclaimer wrapper, its child, the grep, the shell). Print
   `ps -Ao pid,ppid,etime,command | grep MacOS/claude` and confirm there is no SECOND unrelated
   parent/child pair before touching `reconstruction/` or `forward`. Sessions 81 and 82 ran
   concurrently and clobbered each other's close-out pins.
2. Run `python3 scripts/recon_gate.py --mode handoff` from `/Users/jweaver/Desktop/Work/swift/play`
   — expect **PASS 38 / ANOMALY 0 / FAIL 3**. The 3 FAILs are known debt: `agg_critical 15`,
   `agg_high 55`, `agg_unresolved 1`. Floor **299**.
3. **The floor did not move in s85 and that is correct.** Both bodies it audited were DIVERGENT.
   `agg_critical` 14 -> 15 and `agg_high` 48 -> 55 are the eight divergences those two audits
   MEASURED (1 CRITICAL + 7 HIGH; the verdicts also carry 3 MED and 4 LOW). No source line changed.
4. Run `python3 scripts/recon_progress.py`. Two of its lines are now DERIVED on demand; the rest of
   the STAGES block is historical narrative and is labelled as such in the source.
5. **The two-repo split.** Swift sources, the `forward` branch and these handoffs live in
   `/Users/jweaver/Desktop/Work/swift/KSPlayer`. The cwd `/Users/jweaver/Desktop/Work/swift/play`
   holds `scripts/` and `reconstruction/`, both gitignored there. Address KSPlayer with `git -C`;
   run every `scripts/` command from `play`. FFmpegKit is a SIBLING of KSPlayer at
   `/Users/jweaver/Desktop/Work/swift/FFmpegKit`, not inside it.
6. **MEMORY.md changed SHAPE in s85 — read it before anything else.** It is no longer 85 numbered
   rules: 21 every-turn hard rules, a 24-route context index keyed by TRIGGER, and an
   "enforced elsewhere" list so you do not re-check by hand what a hook or gate already decides.
   `play/docs/superpowers/ENFORCEMENT_MAP.md` holds the taxonomy and the disposition of all 85
   former rules; read it first if you are unsure where a new rule belongs.
7. **A PreToolUse hook is LIVE** (`scripts/command_shape_hook.py`, wired on `Bash`). It BLOCKS eight
   command shapes that used to be prose rules — bare `llvm-objdump`, `--macho` on a ranged call,
   `timeout`, `cd` into another repo instead of `git -C`, unquoted heredoc, `validate_build.sh`
   without `DEVELOPER_DIR=`, `2>/dev/null` on an absence-shaped command, wrong `scripts/` cwd. If it
   blocks you the stderr names the check. 18-case golden, negatives included.
8. Read `reconstruction/handoff_baseline.json` block `captured_session85`, then the two s85 verdicts
   `VideoPlayerView_setupUIComponents_slot40_s85.json` and `FFmpegDecode_decodeFrame_slot13_s85.json`.
   The s80-s84 durables remain valid background EXCEPT where "Premises REFUTED" below refutes them.

## The wave sequence — s86, s87, s88

**The unit lists are generated and on disk. Do not re-derive them by hand.**
`python3 scripts/wave_worklist.py --selfcheck` asserts the counts below AND that the two body waves
PARTITION the 181 unverdicted REAL_METHOD slots — nothing double-counted, nothing lost.

| wave | session | units | classes | file |
|---|---|---|---|---|
| AUDIT    | **86** | 97 | 22 | `reconstruction/wave_audit.json` |
| STAND-UP | 87 | 84 | 9 | `reconstruction/wave_standup.json` |
| DERIVE   | 88 | 13 + 37 | — | `reconstruction/wave_derive.json` |

The split between the first two is **does the owning class have a SOURCE FILE**. With source there
is something to compare the binary against — the s84/s85 audit shape. Without source there is
nothing to audit; the unit is "recover the shape", a different job with a different verdict kind.
An audit agent pointed at a source-less class produces a confident comparison against nothing, so
the tool routes them apart and its golden asserts SettingsView never lands in the audit wave.

### Session 86 — the AUDIT WAVE (97 units, 22 classes)

9. Regenerate and read the worklist:
   `python3 scripts/wave_worklist.py --wave audit --json reconstruction/wave_audit.json`.
   Largest first: IOSVideoPlayerView 32 units / 9122 instr · KSPlayerLayer 12 / 1355 ·
   KSAVPlayer 7 / 626 · PreLoadIOContext 7 / 3391 · KSSlider 5 / 299 · VideoSwresample 5 / 1717 ·
   VideoToolboxDecode 4 / 642 · Anime4K 3 / 4780 · FFmpegDecode 3 / 177 · LimitPreLoadIOContext 3 ·
   LimitSeparatePreLoadIOContext 3 · AudioSwresample 2 · HLSCacheIOContext 2 · then twelve
   single-unit classes.
10. **Batch by CLASS, dispatch ONE BODY PER AGENT.** Batching by class amortises the vtable walk
    (one `vtable_walk` per class, not per body). Merging several bodies of one class into a single
    agent cross-contaminates findings between them — s84 kept them separate for exactly that reason.
11. Every agent runs under `reconstruction/AGENT_PROTOCOL.md`: raw-output envelope, gather only, no
    verdict, no source edit, no git index, no build. **The orchestrator re-verifies every
    load-bearing claim against the binary itself and writes and adjudicates every verdict.**
12. **Give each agent the source RANGE, not a starting line, and tell it to read the WHOLE body.**
    s85's own first draft of the FFmpegDecode verdict asserted two false absences because it had
    read :40-189 of a body that runs to :207; the agent caught both. This is the single
    highest-value change to the agent prompt.
13. Write every premise so the agent can refute it (address, owner, slot, extent, source range,
    prior findings). A refuted premise is the most valuable thing a gathering agent returns.
14. **Treat KSPlayerLayer as suspect.** s84 found 8 of its lifecycle methods DIVERGENT (play slot
    60, stop 63, set(url:options:) 55, prepareToPlay 68, readyToPlay 69, changeLoadState 70, finish
    74, pause 61) and s85 found its field records do not match its source properties. Expect
    divergence; do not let an agent's "matches" pass without your own read.
15. Anime4K is 3 units but 4780 instructions, and PreLoadIOContext 7 units / 3391 — budget those
    like ten ordinary bodies each, not three and seven.
16. Adjudicate every body with `adjudicate_verdict.py`; run `verdict_provenance_gate.py --class <C>`
    on every class you touch. Verdict schema and the FAITHFUL bar are in
    `play/docs/superpowers/VERDICTS_AND_HANDOFFS.md`.

### Session 87 — the STAND-UP WAVE (84 units, 9 classes)

17. `python3 scripts/wave_worklist.py --wave standup --json reconstruction/wave_standup.json`.
    SettingsView 43 / 9880 instr · ThumbnailQueue 15 / 1057 · Anime4KPipeline 13 / 2459 ·
    ThumbnailSession 4 / 5198 · KSComplexPlayerLayer 3 · KSVideoPlayerModel 2 ·
    MetalShaderExporter 2 · CustomProgressView 1 · DoviDisplayModel 1.
18. **Run a NAME-RECOVERABILITY SCREEN FIRST, as its own cheap wave.** These classes are in the
    classmap with real vtables, but `export_trie_oracle --class SettingsView` returns
    `no orphan subtree found` — the class exists, its member NAMES do not. Screen all 9 with
    `export_trie_oracle --class` plus `resolve_fun_pins.py --addr` per slot BEFORE dispatching 43
    agents at work that may bottom out in "cannot be named". Split the wave into name-recoverable
    and name-blocked, and size the session from the recoverable half.
19. **The stand-up wave needs its own agent protocol — write it before dispatching.**
    `AGENT_PROTOCOL.md` is an AUDIT contract; it assumes a source body to compare against, and a
    stand-up unit has none. The deliverable per unit is the recovered SHAPE — arity, parameter and
    return types from the mangled name where nameable, field records, extent, call set, dispatch set
    — plus an explicit statement of what could NOT be recovered. Not FAITHFUL/DIVERGENT, which is
    meaningless with nothing to compare.
20. Decide the verdict KIND for a stand-up unit before writing the first one, and teach
    `aggregate_verdicts` to handle it, or the floor arithmetic will silently mis-count these.

### Session 88 — the DERIVATION-ONLY HALVES

21. `python3 scripts/wave_worklist.py --wave derive --json reconstruction/wave_derive.json`.
    Two kinds: **13 class-shape units and 37 fix-spec units.**
22. **Class-shape units (13)** — classes whose source declares stored properties the binary does not
    have, from `field_presence_sweep`. VideoPlayerView 8 (cancellable, navigationBar, titleLabel,
    subtitleLabel, subtitleBackView, originalPlaybackRate, speedTipLabel, longPressGesture) ·
    PlaneDisplayModel 6 (indexCount, indexType, primitiveType, indexBuffer, posBuffer, uvBuffer —
    **this is why s84 saw `drawPrimitives` and not `drawIndexedPrimitives`: the index buffers do not
    exist**) · KSPictureInPictureController 5 (binary has ZERO field records) · KSAVPlayer 4 ·
    KSPlayerLayer 4 · Coordinator 2 · MetalPlayView 2 · PlayerView 1 · AudioGraphPlayer 1 ·
    FFmpegAssetTrack 1 · MetalView 1 · AudioFrame 1 · IOSVideoPlayerView 1.
23. **Fix-spec units (37)** — every DIVERGENT body with a `binary_addr`. The unit is a
    statement-level spec of what the binary actually does; derivable independently, one body per
    agent.
24. **DERIVING is parallel; WRITING is serial.** The pre-commit `l2_field_gate` blocks on the CLASS,
    not on your diff, so two "independent" source edits in one file serialise anyway (s85 lost a
    commit to exactly this). Land the derivation as specs during the wave, then apply them one unit
    and one commit at a time.

## What NOT to wave, in any session

25. **Source edits** — per step 24; the gate blocks per class and parallel editors collide on the
    git index. MEMORY already forbids an agent touching the index or running a build.
26. **Class-shape changes that ripple to consumers** (DisplayModel's `(frame:encoder:)` arity,
    VideoPlayerView's stored-property set, FFmpegDecode's signature). Single-threaded.
27. **Several bodies of one class into one agent** — see step 10.
28. `GENERATED_ACCESSOR` (322 slots) is not a candidate at all: it collapses into declarations and
    is not body work.

## What s85 landed (context for the above)

29. **Tools, all with `--selfcheck`, all disk-only** (`scripts/` is gitignored — re-run each golden
    at takeover): `fieldrec.py` (Mach-O field records, the rule-3 absence authority; decodes the
    ctrl-`0x02` symref that a NUL-splitting reader truncates) · `field_presence_sweep.py` (118
    classes: 77 clean, 13 with source properties absent from the binary = 43 fields, 16 binary-only;
    it reproduced three refutations it was never told about) · `dispatch_recheck.py` ·
    `wave_worklist.py` · `command_shape_hook.py` · `test_gate_interface_strings.py` ·
    `test_no_hardcoded_counts.py`.
30. **`body_fingerprint.py` had three defects and they are fixed** — objc-selector decode gated on
    `__objc_stubs` (a `__text` call read as `objc_msgSend[<mojibake>]`), `add rd,rs,#imm` now rebinds
    the register (a STALE MAP, not a missing displacement, produced the bogus page-base global), and
    DISPATCH OFFSETS requires the register to be CALLED. Rule 10 discharged over 264 bodies, 0
    crashes; histogram 0:167 / 1:60 / 2:28 / 3:4 / 4:5 — 97 bodies carry a real dispatch.
31. **The floor is NOT overstated.** `dispatch_recheck` over 340 verdicts / 266 bodies: 212 carry
    phantom offsets, 27 cite one in a dispatch context, **0 had a wrong vtable-or-metadata
    conclusion.** The sweep instead found TWO more defects in s85's own fix — `blr`-only missed TAIL
    calls (`br xD`), and a linear scan walked past an unconditional `b` into another basic block.
    **Twice the tool contradicted an adjudicated verdict and twice the verdict was right.**
32. **The "283" is dead.** `recon_progress` printed `"...%4d bodies" % 283` for four handoffs; the
    number was written in s60 before the export-trie oracle existed and matched no measurement ever.
    Derived now: 280 unique FUN_ pins / 523 refs / 84 nameable / 196 genuine negatives — call
    `resolve_fun_pins.pin_counts()`, never quote a tally from a docstring or from this handoff.
    `test_no_hardcoded_counts.py` makes a literal-in-a-reporter a gate failure.
33. **The UNCHECKED hole is measured:** 205 of 803 source stored properties (25.5%) across 33
    classes are written `var x = …` with no annotation and are invisible to the type gate. Worst:
    KSOptions 62/84, IOSVideoPlayerView 23/64, MEPlayerItem 20/42, VideoPlayerView 19/27.

## Premises REFUTED — do not re-derive

34. **VideoPlayerView.navigationBar, .titleLabel, .speedTipLabel, .subtitleLabel and
    .subtitleBackView DO NOT EXIST in the binary.** From the FIELD RECORDS: FieldDescriptor
    `0x103cbf530` holds exactly 20 records with none of the five; superclass PlayerView
    (`0x1039ee210`) holds 5 and has none either. Source declares all five ON VideoPlayerView.
    `setupUIComponents` is ~9 statements shorter and `setupSrtControl()` is never called.
    Corroborated from a DIFFERENT function: `addConstraint` @`0x101b2ed64` emits 9
    `setTranslatesAutoresizingMaskIntoConstraints:` where its source has 11 — short by exactly
    navigationBar and titleLabel.
35. **FFmpegDecode.decodeFrame takes `UnsafeMutablePointer<__C.AVPacket>`** (`SpySo8AVPacketVG`), not
    the `Packet` CLASS (`AA6PacketC`) — proved at the mangle level. Its CC guard tests `self.isVideo`
    and passes `self.assetTrack`, not the packet's. The side-data loop and the 4-level timestamp
    fallback are both ABSENT. The error type is KSPlayerError, not NSError. FFmpegDecode has a
    binary-only vtable method at slot 18 (`0x101a23404`, NOT_IN_TRIE = unnamed, not absent).
36. **`ffmpeg_name_oracle` version skew is REFUTED.** Forward is `Lavc62.28.101`/`Lavf62.12.101` and
    the indexed xcframeworks are the same build, so a re-index is a NO-OP. `0x102a1a424` stays
    UNKNOWN; find the real cause (a build-configure difference, or it simply is not
    `avcodec_send_packet`) before naming it.
37. Everything s84 refuted still holds: PlayerView DOES have a vtable (a `vtable_walk` cross-module
    name collision); KSPlayerLayer has a binary-only `change(state:)` at slot 58; MediaPlayback
    req 14's KSAVPlayer impl is named `stop()` where the source says `shutdown()`;
    IOSVideoPlayerView.originalOrientations and VideoPlayerView.longPressGesture do not exist.

## Still open, not scheduled into a wave

38. **`vtable_walk.py` resolves a bare class NAME to the FIRST classmap row**, wrong across a
    cross-module collision (`PlayerView` is Notelet `0x1039e919c` before KSPlayer `0x1039ee210`).
    **Unit:** take a module, prefer KSPlayer, ERROR on ambiguity — `fieldrec.desc_for_class` already
    implements exactly that contract; copy it. Then re-run every class and diff.
39. `decode_string_literal.py` misses computed counts and the `_StringObject` bias direction; s85
    decoded four literals by hand from `mov`/`movk` immediates, and that hand method is the spec.
40. A field-offset-global resolver from field-record order + an anchor site (the proven pattern:
    `pause()` @`0x1019ccb3c` stores `wzr` through `0x104c63520`, pinning `isAutoPlay`).
41. `l2_field_gate`'s `merge_binary_type` should fall back to the trie's `.setter`/`.getter` type
    when there is no mangled property symbol. 11 REAL_FLAGs + 7 UNCHECKED on KSPlayerLayer wait on
    it — but step 33's 205 unannotated properties are the bigger hole.
42. Fix queue, coupled — **build both before staging either**: `KSPlayerLayer.seek(time:)`
    (`:601`; binary slot 64 is `seek(time:completion:)` and forwards the caller's completion) and
    `VideoPlayerView.change(definitionIndex:)` (`:371-373`; replace the guarded `seek` with
    `asset.options.startPlayTime = shouldSeekTo` BEFORE `super.set` — KSOptions+0x30 = startPlayTime
    from its `vpWvd` at `0x103567480`). Re-derive the slot-64 claim before editing; s85 did not.
43. `Coordinator.player(layer:currentTime:totalTime:)`, the `startRecord` CRITICAL, **A · KSOptions**,
    the `T!` vs `T?` normalizer, Package F init bodies, MetalPlayView/`Drawable`, and extending the
    classmap to structs and enums are unchanged. See s84-handoff steps 26-32.
44. ⚠️ **DURABILITY RISK, unresolved.** `play/.gitignore` lines 128-129 ignore `docs/` AND `scripts/`,
    and neither is in KSPlayer. Every tool, doc, hook and worklist exists ONLY on this disk. Backups
    are `reconstruction/_scripts_backup_s71_8cb7b40` and
    `reconstruction/MEMORY_s85_pre_split_backup.md`. **Decide where this layer is versioned.**

## Close out

45. Adjudicate every body with `adjudicate_verdict.py` (never delete `binary_addr` to pass the
    provenance guard). Run `verdict_provenance_gate.py --class <C>` on every class you touch.
46. **If the pre-commit gate blocks on a class you did not touch**, check whether a FAITHFUL spelling
    exists before reaching for `--no-verify` — MEMORY only permits it when none does. Land the
    blocker as its own commit first, as s85 did for `KSOptions.doviProfile`.
47. Update `reconstruction/handoff_baseline.json` with a `captured_session86` block and refresh
    `head`, `ahead_origin`, `faithful_floor`. **Re-run `recon_gate --mode handoff` AFTER updating
    the baseline.** Take `ahead_origin` from `git rev-list --count origin/forward..forward`.
48. Record how many bodies landed, the FAITHFUL/DIVERGENT split, and every premise refuted — the
    refutations have been the highest-value output of the last sixteen sessions, above the code.
    Then write the session-87 handoff from the FINAL state, not by patching a mid-session draft, and
    make its work section the STAND-UP wave per steps 17-20. **Do not write the takeover prompt into
    it — give the prompt in chat.**
