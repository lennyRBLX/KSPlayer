# Session 87 work

Session 86 was meant to run the AUDIT wave. It found the wave does not exist. The predicate that
built it was wrong, 91 of its 97 units had nothing to audit against, and the six that did were
already adjudicated. No body was audited and no verdict was written, because dispatching an audit
agent at any of those 91 produces exactly what the split exists to prevent: a confident comparison
against nothing. **Session 87 runs the STAND-UP wave, which is now the entire remaining body queue.**

Note on filenames: this directory does not sort in session order. **Order by the session number.**

## Verify first

1. Run `ps -Ao pid,etime,command | grep -c "MacOS/claude --output-format stream-json"` FIRST. One
   live session prints **4** lines (a disclaimer wrapper, its child, the grep, the shell). Print
   `ps -Ao pid,ppid,etime,command | grep MacOS/claude` and confirm there is no SECOND unrelated
   parent/child pair before touching `reconstruction/` or `forward`. This blocked s86 at takeover: a
   second session was live, idle, and cwd'd into `play/`, having written 99 seconds earlier. Sessions
   81 and 82 ran concurrently and clobbered each other's close-out pins.
2. `recon_gate --mode handoff` **writes `reconstruction/handoff_report.json`** (`DEFAULT_REPORT`, and
   the `write_text` at the end of its main). Running it IS touching `reconstruction/`, so step 1 is
   its precondition, not a formality beside it.
3. Run `python3 scripts/recon_gate.py --mode handoff` from `/Users/jweaver/Desktop/Work/swift/play`
   — expect **PASS 39 / ANOMALY 0 / FAIL 3**. The 3 FAILs are known debt: `agg_critical 15`,
   `agg_high 55`, `agg_unresolved 1`. Floor **299**. PASS rose 38 -> 39 because s86 wired
   `sc_method_presence` in.
4. **The floor did not move in s86 and that is correct.** No body was audited. The session's output
   was a refutation and two tool corrections, not a verdict.
5. Run `python3 scripts/recon_progress.py`.
6. **The two-repo split.** Swift sources, the `forward` branch and these handoffs live in
   `/Users/jweaver/Desktop/Work/swift/KSPlayer`. The cwd `/Users/jweaver/Desktop/Work/swift/play`
   holds `scripts/` and `reconstruction/`, both gitignored there. Address KSPlayer with `git -C`;
   run every `scripts/` command from `play`. FFmpegKit is a SIBLING of KSPlayer at
   `/Users/jweaver/Desktop/Work/swift/FFmpegKit`, not inside it.
7. Read MEMORY.md before anything else — 21 every-turn hard rules, a routed context index keyed by
   TRIGGER, and an "enforced elsewhere" list so you do not re-check by hand what a hook or gate
   already decides.
8. A PreToolUse hook is LIVE (`scripts/command_shape_hook.py`, wired on `Bash`). If it blocks you the
   stderr names the check.

## What s86 refuted — do not re-derive

9. **The AUDIT wave had ZERO freshly auditable units.** `wave_worklist` split the body waves on
   *does the owning CLASS have a source file*. The predicate that decides auditability is *is the
   METHOD declared in that class's own source scope*. Over the 97 units it had routed to AUDIT:
   **67 BINARY_ONLY, 24 UNNAMED, 6 SOURCE_MATCH** — and all 6 were already adjudicated FAITHFUL
   except one explicit P3 deferral. Measured by `method_source_presence.py`, goldens included.
10. **The load-bearing case is IOSVideoPlayerView** — 32 units and 9122 instructions of that wave.
    Its source declares `customizeUIComponents`, `resetPlayer`, `onButtonPressed`, `isHorizonal`,
    `updateUI(isFullScreen:)`, `updateUI(isLandscape:)`, `player(layer:state:)`,
    `set(resource:definitionIndex:isSetUrl:)`, `change(definitionIndex:)`, `panGestureBegan`,
    `panGestureChanged`, `judgePanGesture`, `addNotification`, `orientationChanged`,
    `canPerformAction`, `documentPicker`. Its binary declares `setupBackgrounds`,
    `setupTopLeftButtons`, `setupTopRightButton`, `setupSideButtons`, `setupCenterControls`,
    `setupBottomControls`, `setupVideoInfoLabels`, `setupScreenshotPreview`, `setupTopStatusBar`,
    `customAutoFadeOutViewWithAnimation`, `handlePlayPause`, `handleScreenshot`, `handleJumpForward`,
    `handleJumpBack`, `dismissScreenshotPreview`, `updateTimeLabel`,
    `updateNetworkStatusImageView`, `updateBatteryStatusImageView`, `startSpeedUpdateTimer`,
    `updateNetworkSpeed`, `showPromptMessage`, `hidePrompt`, `handleSubtitleMenuButtonTapped`,
    `handleAspectFillButtonTapped`, `showUnifiedSettings`, `showAudioMenu`, `createSubtitleSubMenu`,
    `generateFFmpegMenu`, `generateURLMenu`, `openFilePicker`, `updateVideMetaLabel`, `getVideoMeta`.
    **Zero overlap.** Forward replaced the class's whole UI layer.
11. **A bare name match is not evidence.** `KSPlayerLayer.reset()` "matches" `PlayerToolBar.reset()`,
    `DisplayModel.reset()` and `SubtitleActor.reset()`, and is declared by none of them. Every hit is
    attributed to its enclosing type header before it counts. This is the scope negative control in
    `method_source_presence --selfcheck`; do not weaken it.
12. **NOT_IN_TRIE at a body address does not mean unnameable.** `FFmpegDecode` slot 15 body
    `0x101a233c8` exports nothing, yet the vtable descriptor's Impl `0x101a23330` is a
    ONE-INSTRUCTION `b 0x101a233c8` thunk, and THAT address exports
    `KSPlayer.FFmpegDecode.doFlushCodec()`. Slot 17 chains `0x101a236d4 -> 0x101a23330 ->
    0x101a233c8`, so slots 15 and 17 share one body — the linker folded `doFlushCodec()` and
    `decode()`, byte-identical at `FFmpegDecode.swift:209-215` and `:223-228`. Chasing that pattern
    across all 25 unnamed units recovers exactly **one** name. The other 24 have `Impl == body addr`.
13. **7 audit units were already adjudicated FAITHFUL and the worklist could not see them.**
    `_verdicted_addrs()` read only the top-level `binary_addr`; a multi-body verdict has none and
    records each body inside `bodies[].addr` as free text. Fixed by REPORTING
    (`wave_worklist --coverage-audit`), never by filtering — a greedy free-text scan would have
    dropped 5 LIVE units, because a verdict's `bounds` field names the extent END, which is the NEXT
    slot's entry address (KSPlayerLayer 56/62/73/75 and KSAVPlayer 96 are each mentioned only so).
14. Everything s84 and s85 refuted still holds. In particular s85's five VideoPlayerView field
    absences, the `FFmpegDecode.decodeFrame` packet-type result, and PlayerView's vtable.

## Session 87 — the STAND-UP WAVE (175 units, 30 classes)

**The unit list is generated and on disk. Do not re-derive it by hand.**
`python3 scripts/wave_worklist.py --selfcheck` asserts the counts below AND that the two body waves
still PARTITION the 181 unverdicted REAL_METHOD slots.

15. Regenerate and read the worklist:
    `python3 scripts/wave_worklist.py --wave standup --json reconstruction/wave_standup.json`.
    Largest first: SettingsView 43 units / 9880 instr · IOSVideoPlayerView 32 / 9122 ·
    ThumbnailQueue 15 / 1057 · Anime4KPipeline 13 / 2459 · KSPlayerLayer 12 / 1355 · KSAVPlayer 7 /
    626 · PreLoadIOContext 7 / 3391 · KSSlider 5 · VideoSwresample 5 · ThumbnailSession 4 / 5198 ·
    Anime4K 3 / 4780 · KSComplexPlayerLayer 3 · LimitPreLoadIOContext 3 ·
    LimitSeparatePreLoadIOContext 3 · then sixteen classes of 1-2 units.
16. **The name-recoverability screen that the s86 handoff scheduled as its own wave is DONE**, as a
    by-product of the corrected split. Of the 175 stand-up units, **102 are NAMED** (bucket
    `BINARY_ONLY` — the trie gives a full demangled signature) and **73 are UNNAMED**.
    **Size the session from the 102.**
    ⚠️ `reconstruction/method_presence_standup.json` is derived FROM the wave file, so step 15
    stales it. Regenerate it in the same breath, never read it blind:
    `python3 scripts/method_source_presence.py --wave standup --json reconstruction/method_presence_standup.json`.
    s86 wrote that file against the pre-correction 84-unit wave and caught it only on re-read.
    The 97-unit measurement that justified the correction is preserved separately at
    `reconstruction/method_presence_s86_refutation_97units.json`; it is evidence, not a worklist.
17. **Write the stand-up agent protocol BEFORE dispatching anything.**
    `reconstruction/AGENT_PROTOCOL.md` is an AUDIT contract — it assumes a source body to compare
    against, and every unit in this wave lacks one. The deliverable per unit is the recovered SHAPE:
    arity, parameter and return types from the mangled name where nameable, field records, extent,
    call set, dispatch set — plus an explicit statement of what could NOT be recovered. Not
    FAITHFUL/DIVERGENT, which is meaningless with nothing to compare. Keep the raw-output envelope,
    the derive-only rule and the hard prohibitions unchanged.
18. **Decide the verdict KIND for a stand-up unit before writing the first one, and teach
    `aggregate_verdicts` to handle it, or the floor arithmetic will silently mis-count these.** This
    is now on the critical path, not adjacent to it: it governs ~97% of the remaining body queue.
    Check what `agg_faithful` does with an unknown verdict word before you choose the word.
19. **Batch by CLASS, dispatch ONE BODY PER AGENT.** Batching by class amortises the vtable walk;
    merging several bodies of one class into one agent cross-contaminates findings between them.
20. **Give each agent the source RANGE where one exists, and tell it to read the WHOLE body.** For a
    stand-up unit there is usually no range — say so explicitly rather than leaving it blank, or the
    agent will invent a counterpart.
21. Write every premise so the agent can refute it (address, owner, slot, extent, prior findings). A
    refuted premise is the most valuable thing a gathering agent returns.
22. **The orchestrator re-verifies every load-bearing claim against the binary itself and writes and
    adjudicates every verdict.** Run `verdict_provenance_gate.py --class <C>` on every class touched.
23. Anime4K is 3 units but 4780 instructions, ThumbnailSession 4 units / 5198, and PreLoadIOContext
    7 / 3391 — budget those like ten ordinary bodies each.
24. **Several of these are plainly outlined out of a source body.** Forward's `setup*` set on
    IOSVideoPlayerView sits against source `customizeUIComponents`; the CC-create body at
    `0x101a23404` (FFmpegDecode slot 18, still open) sits against the inline block in
    `decodeFrame`. Identifying the source a binary-only method was outlined FROM is a legitimate
    stand-up finding — but it is a finding, not a licence to write a FAITHFUL verdict against a
    body that does not exist.

## The one remaining AUDIT unit

25. `python3 scripts/wave_worklist.py --wave audit --json reconstruction/wave_audit.json` now emits
    6 units across 2 classes, and `--coverage-audit audit` reports all 6 as already named in a
    per-body verdict field. Adjudicated in s86: FFmpegDecode 15/16 and VideoToolboxDecode 30/32 are
    FAITHFUL outright; VideoToolboxDecode 31 is a FAITHFUL spine whose deferral is closed by
    `VideoToolboxDecode_shutdown_s31_p3a.json`; **VideoToolboxDecode slot 29
    `decodeFrame(from:completionHandler:)` @`0x101a6ce44` (572 instr) is the only genuinely open
    one.** It is an explicit `deferred_to_P3` DV-crux body, coupled to the DV/HDR work and gated on
    the protocol-witness verifier. Do not take it as a warm-up.

## What NOT to wave, in any session

26. **Source edits.** The pre-commit `l2_field_gate` blocks on the CLASS, not on your diff, so two
    "independent" edits in one file serialise anyway (s85 lost a commit to exactly this). Land
    derivations as specs during the wave, then apply them one unit and one commit at a time.
27. **Class-shape changes that ripple to consumers** (DisplayModel's `(frame:encoder:)` arity,
    VideoPlayerView's stored-property set, FFmpegDecode's signature). Single-threaded.
28. **Several bodies of one class into one agent** — see step 19.
29. `GENERATED_ACCESSOR` (322 slots) is not a candidate at all: it collapses into declarations.

## Still open, not scheduled into a wave

30. `vtable_walk.py` resolves a bare class NAME to the FIRST classmap row, wrong across a
    cross-module collision (`PlayerView` is Notelet `0x1039e919c` before KSPlayer `0x1039ee210`).
    **Unit:** take a module, prefer KSPlayer, ERROR on ambiguity — `fieldrec.desc_for_class` already
    implements that contract; copy it. Then re-run every class and diff. This now also sits under
    `method_source_presence`, which shells out to `vtable_walk` for its thunk fallback.
31. `decode_string_literal.py` misses computed counts and the `_StringObject` bias direction; s85
    decoded four literals by hand from `mov`/`movk` immediates, and that hand method is the spec.
32. A field-offset-global resolver from field-record order + an anchor site (the proven pattern:
    `pause()` @`0x1019ccb3c` stores `wzr` through `0x104c63520`, pinning `isAutoPlay`).
33. `l2_field_gate`'s `merge_binary_type` should fall back to the trie's `.setter`/`.getter` type
    when there is no mangled property symbol. 11 REAL_FLAGs + 7 UNCHECKED on KSPlayerLayer wait on
    it — but the 205 unannotated stored properties (25.5% of 803, across 33 classes) are the bigger
    hole.
34. Fix queue, coupled — **build both before staging either**: `KSPlayerLayer.seek(time:)` (`:601`)
    and `VideoPlayerView.change(definitionIndex:)` (`:371-373`). Re-derive the slot-64 claim before
    editing; s85 did not. Note s86 established that KSPlayerLayer's 12 unverdicted slots are all
    binary-only, so do not expect the surrounding methods to be comparable either.
35. `Coordinator.player(layer:currentTime:totalTime:)`, the `startRecord` CRITICAL, **A · KSOptions**,
    the `T!` vs `T?` normalizer, Package F init bodies, MetalPlayView/`Drawable`, and extending the
    classmap to structs and enums are unchanged. See s84-handoff steps 26-32.
36. ⚠️ **DURABILITY RISK, unresolved and now larger.** `play/.gitignore` ignores `docs/` AND
    `scripts/`, and neither is in KSPlayer. Every tool, doc, hook and worklist exists ONLY on this
    disk — including `method_source_presence.py`, which is now the wave-split authority and whose
    loss would silently restore the wrong predicate. Backups are
    `reconstruction/_scripts_backup_s71_8cb7b40` and `reconstruction/MEMORY_s85_pre_split_backup.md`.
    **Decide where this layer is versioned.**

## Close out

37. Adjudicate every body with `adjudicate_verdict.py` (never delete `binary_addr` to pass the
    provenance guard). Run `verdict_provenance_gate.py --class <C>` on every class you touch.
38. If the pre-commit gate blocks on a class you did not touch, check whether a FAITHFUL spelling
    exists before reaching for `--no-verify` — MEMORY only permits it when none does.
39. Update `reconstruction/handoff_baseline.json` with a `captured_session87` block and refresh
    `head`, `ahead_origin`, `faithful_floor`. **Re-run `recon_gate --mode handoff` AFTER updating the
    baseline.** Take `ahead_origin` from `git rev-list --count origin/forward..forward`.
40. Record how many bodies landed, the verdict split, and every premise refuted — the refutations
    have been the highest-value output of the last seventeen sessions, above the code. Then write the
    session-88 handoff from the FINAL state, not by patching a mid-session draft. **Do not write the
    takeover prompt into it — give the prompt in chat.**
