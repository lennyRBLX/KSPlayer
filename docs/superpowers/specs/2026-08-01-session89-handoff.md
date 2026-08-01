# Session 89 work

Session 88 completed **Anime4KPipeline: 13 of 13 bodies stood up**, built the field-offset resolver
the last four handoffs asked for, and closed the durability question that had been carried as
blocking since s84. The faithful floor did not move, and that is by design — `agg_stood_up` is where
this wave accrues.

Note on filenames: this directory does not sort in session order. **Order by the session number.**

## Verify first

1. Run `ps -Ao pid,etime,command | grep -c "MacOS/claude --output-format stream-json"` FIRST. One
   live session prints **4** lines. Print `ps -Ao pid,ppid,etime,command | grep MacOS/claude` and
   confirm there is no SECOND unrelated parent/child pair before touching `reconstruction/` or
   `forward`. `recon_gate --mode handoff` WRITES `reconstruction/handoff_report.json`, so running it
   IS touching `reconstruction/` and this step gates it.
2. Run `python3 scripts/recon_gate.py --mode handoff` from `/Users/jweaver/Desktop/Work/swift/play`
   — expect **PASS 44 / ANOMALY 0 / FAIL 3**. PASS rose 43 -> 44 (`sc_field_offset`). The 3 FAILs
   are the unchanged known debt: `agg_critical 15`, `agg_high 55`, `agg_unresolved 1`. Floor **299**,
   `agg_stood_up` **28**, `wave_standup_size` **147**, `wave_audit_size` **6**.
3. **The floor HELD at 299 and that is correct.** Twenty-eight bodies are now stood up; none is
   auditable, so none may count toward FAITHFUL.
4. Run `python3 scripts/recon_progress.py`. Its stale "97 in classes WITH source / 84 NO source"
   line is **FIXED** — it no longer computes a split with the s86-refuted predicate, and now names
   `wave_worklist.py` as the owner of that partition. Do not reintroduce a split there.
5. **The two-repo split.** Swift sources, the `forward` branch and these handoffs live in
   `/Users/jweaver/Desktop/Work/swift/KSPlayer`. The cwd `/Users/jweaver/Desktop/Work/swift/play`
   holds `scripts/` and `reconstruction/`, both gitignored there. Address KSPlayer with `git -C`;
   run every `scripts/` command from `play`. FFmpegKit is a SIBLING of KSPlayer at
   `/Users/jweaver/Desktop/Work/swift/FFmpegKit`, not inside it.
6. Read MEMORY.md before anything else. The PreToolUse hook (`scripts/command_shape_hook.py`) fired
   three times in s88 and was right every time — on a bare `timeout`, on `2>/dev/null` against a
   possibly-absent path, and on a compound command that mixed a `--macho` call with a ranged one. It
   also fires on a bare tool name inside ordinary PROSE, which is what caught a verdict string.
   Rephrase or split; never weaken it.

## SETTLED in s88 — do not re-raise

7. **The durability question is CLOSED by user decision.** The tool/verdict layer stays
   **uncommitted**: *"Losing these files is unlikely, they do not need to be put on git, and can be
   kept uncommitted."* This retires the "DURABILITY RISK" item that s84–s88 each carried forward as
   blocking. Recorded in the `ksplayer-recon-git-topology` memory. **Do not propose versioning
   `scripts/`, `docs/` or `reconstruction/` again, and do not carry it into another handoff as an
   open decision.**
   While confirming it, one stale claim in that memory was corrected: KSPlayer `forward` no longer
   tracks only `Sources/` — `git ls-files docs` returns 17 handoff specs. Handoff PROSE is versioned;
   the tools and verdicts are not, deliberately.

8. **The 3 coverage hits are adjudicated** (`reconstruction/wave_coverage_adjudication_s88.json`).
   VideoSwresample slot 29 `0x101a662e8` and slot 31 `0x101a66c6c` are **DONE** — slot 29's P2
   deferral is closed by `VideoSwresample_setup_s29_p3a.json`, and both addresses were re-read off
   the vtable. FFmpegDecode slot 18 `0x101a23404` is **genuinely OPEN** (P3, DV decode crux, upstream
   body kept).
   **CORRECTION to the s88 handoff's framing:** this was *not* free progress. `aggregate_verdicts`
   increments `faithful` once per **VERDICT FILE**, not per body, so both VideoSwresample bodies were
   already inside the 299. It bought 646 instructions of wave hygiene and **zero** floor movement.
   The worklist still re-reports all 3 every session because the adjudication has nowhere
   deterministic to land — see step 17.

## What s88 landed

9. **Anime4KPipeline is COMPLETE — all 13 REAL_METHOD slots stood up, adjudicated, provenance gate
   OK.** Slots 64, 65, 66, 69, 70, 72, 73, 74, 75, 77, 78, 79, 81. Verdicts in
   `reconstruction/verdicts/Anime4KPipeline_*_s88.json`.
10. **`scripts/field_offset_vector.py` — the offset resolver s84–s88 listed as UNBUILT.** Reads the
    runtime field-offset vector: metadata VA from the trie symbol `$s<len><Module><len><Class>CN`,
    displacement from descriptor +40 (`FieldOffsetVectorOffset`, in WORDS), then **one u64 per field**
    in field-record order; InstanceSize at metadata +0x30, AlignMask +0x34. Golden-gated on
    ThumbnailQueue's three-way answer and wired as `sc_field_offset`.
11. **The batching lesson held.** Orchestrator derived slots 64, 65, 66, 73, 74, 79, 81 directly
    (2–73 instr each); one agent per large body for 69, 70, 72, 75, 77, 78 (152–768 instr). Six
    agents, **all returned `UNGROUNDED: 0`** against `STANDUP_PROTOCOL.md`.

## Premises s88 REFUTED — the highest-value output

12. **The orchestrator's own brief was wrong twice.** Slots 72 and 78 were briefed as UNNAMED; both
    are nameable from the body's own `#function` literal — `loadShaderFiles(_:)` and
    `updatePerformanceMetrics(frameTime:)`. **`method_source_presence` does not try that route, so
    the wave's UNNAMED bucket (now 70) OVERSTATES unnameability.** Two of Anime4KPipeline's three
    UNNAMED units were nameable; only slot 79 is genuinely unnamed.
13. **`recover_swift_function_name.py` returns FALSE high-confidence names.** It names Anime4K idx45
    `0x101a76090` `CenterResizeVertex` — a shader-name string that merely sits nearby — at
    `confidence=high`, `labels=0`. **The discriminator, verified on all three cases:** trust it only
    when `labels>=1` AND the body itself materializes the literal (an `adrp`/`add` then the
    `_StringObject` `sub #0x20` bias, passed to a log witness) AND the character count it loads
    matches the name's length. Memory: `recover-swift-function-name-false-anchors`.
14. **The "field-offset vector once per class" plan applies to ONE of the five target classes.**
    `KSAVPlayer`, `KSComplexPlayerLayer` and `KSVideoPlayerModel` are `metadata_init=1`;
    `KSPlayerLayer` has no exported metadata symbol. Only Anime4KPipeline was readable.
15. **The new tool caught a defect in ITSELF during the rule-10 sweep.** A class with
    `metadata_init != 0` has no offsets in the static image: reading it returns `InstanceSize 0x0`
    and `0x0` for EVERY field — a confident, entirely fictional map. **299 of 1039 classes are
    affected**; only 249 have both static metadata and an exported `...CN`. Now a hard error with a
    golden negative control. Memory: `field-offset-vector-metadata-init`.
16. **Three body-level premises the names alone would have got wrong.**
    `beginFrameRendering(force:)` **never reads `force`** — the parameter is dead, so it does not
    bypass the in-flight check. `isUpscaleSupported` does **not** produce the `cachedUpscaleSupport`
    cache (zero stores to self; all six stores are `sp` spills), refuting the brief's hypothesis.
    `loadPreset`'s `.disabled` early return sits **after** all three side effects, so it skips only
    the log — the disabled case is handled inside `loadShaderFiles`, an interlock between two bodies.

## The Anime4KPipeline shape, for whoever writes the source

17. **A four-body cache protocol.** `configure` (70) is the SOLE producer of `cachedUpscaleSupport`
    @0x31; `cachedUpscaleSupportStatus` (74) is a pure PEEK with no recompute-on-miss;
    `updateTargetResolution` (64) and `updateUpscalePolicy` (73) invalidate by writing the raw byte
    **2** = `Optional<Bool>`'s nil; `loadPreset` (69) uses only HALF that idiom (nils the cache,
    does not clear `configured`). `isUpscaleSupported` (75) computes the same predicate live and
    statelessly.
18. **Frame accounting is asymmetric.** `beginFrameRendering` claims a slot only when
    `inFlightFrameCount == 0`; `cancelFrameRendering` decrements both counters but clamps only the
    in-flight one (`bic x8,x8,x8,asr #63`); `encode` decrements the reservation and never touches
    in-flight.
19. **Two fps thresholds, both decoded:** 0.033 (30 fps) in `getPerformanceStats`, 0.05 (20 fps) in
    slot 79 and `updatePerformanceMetrics`. `onDowngradePreset` is typed `(() -> ())?` — it takes
    **no** argument despite the name. `maxHistoryCount` @0xb8 is never loaded; the cap 30 is
    constant-folded because the field record declares it `let Si`.
20. **Sub-word packing is real and load-bearing here** — `preset 0x20`/`usePrecompiled 0x21` and
    `configured 0x88`/`supported 0x89`. A single `strh wzr,[x,#0x88]` in `loadShaderFiles` writes
    both Bools at once, confirming the map from a body. Anchor-site inference would likely have
    mis-assigned these.

## Session 89 — continue the STAND-UP wave

21. Regenerate the worklist and its DERIVED presence file in the same breath, never read either
    blind: `python3 scripts/wave_worklist.py --wave standup --json reconstruction/wave_standup.json`
    then `python3 scripts/method_source_presence.py --wave standup --json
    reconstruction/method_presence_standup.json`. Expect **147 units / 28 classes, 77 NAMED /
    70 UNNAMED, SOURCE_MATCH 0**. Then run `--coverage-audit standup` and adjudicate its 3 hits
    against step 8 — they are already settled, so this should cost one minute, not a re-derivation.
22. **Next cheap NAMED classes, in this order:** `KSAVPlayer` 7 units / 626 instr (all NAMED),
    `KSComplexPlayerLayer` 3 / 253 (all NAMED), `KSVideoPlayerModel` 2 / 82 (all NAMED),
    `KSPlayerLayer` 12 / 1355 (all NAMED; s86 established all 12 are binary-only).
    **All four are `metadata_init=1` or have no metadata symbol (step 14), so the offset resolver
    will REFUSE them.** Budget for anchor-site offset recovery per class, or do the cheaper thing
    first: their offsets may be recoverable from trie-named accessors.
23. **Before briefing any UNNAMED unit, run `recover_swift_function_name.py` on it yourself** and
    apply the step-13 discriminator. s88 briefed two units as unnameable that were not. The 70
    UNNAMED units are the obvious place this pays: `SettingsView` alone is 43 of them.
24. **Batch by CLASS; dispatch ONE BODY PER AGENT for large bodies and derive small ones yourself.**
    Hold every agent to `reconstruction/STANDUP_PROTOCOL.md`. Note its §1 still quotes the s87-era
    "175 stand-up units ... 102 BINARY_ONLY" — the contract is unaffected but the number is stale;
    fix it when no agent is in flight (MEMORY rule 7).
25. **CHECK YOUR OWN PREMISES against the worklist before writing them into a brief** (step 12).

## Open work this session created or sharpened

26. **The coverage-audit adjudication has nowhere to land.** The worklist re-reports the same 3 hits
    every session. Build an explicit adjudicated-exclusion file that `wave_worklist` reads, with a
    selfcheck asserting every entry still resolves to a real verdict FIELD. **Never a greedy
    free-text address scan** — that would drop 5 LIVE units via `bounds` mentions, the s87 defect.
27. **Re-screen the 70 UNNAMED units through the `#function` route** (steps 12–13). If the
    Anime4KPipeline hit rate (2 of 3) generalises even weakly, this materially changes what the rest
    of the wave costs.
28. **`Anime4KPreset`'s 11 constant `[String]` shader-path arrays** at `0x1044ec348`–`0x1044ec930`
    plus `0x1044e3de8` are undecoded — they are array-storage objects, not `_StringObject` literal
    pairs, and reading them means opening `FUN_101a78d80`, which the protocol forbids an agent from
    doing. Orchestrator work.
29. **`PixelBufferProtocol` carries 40 requirements in the binary.** Witness offsets cannot be read
    off the source declaration. Recorded as a shape fact in the slot 70 and 75 verdicts, not
    adjudicated — the protocol's own reconstruction is separate work.
30. `SettingsView` is 43 units / 9880 instr, all UNNAMED; `IOSVideoPlayerView` is 32 / 9122, all
    NAMED with zero source overlap. Together ~51% of the remaining wave. Leave both until the cheap
    NAMED classes are exhausted — but see step 27, which may change SettingsView's cost.
31. Budget `Anime4K` 3 units / 4780 instr, `ThumbnailSession` 4 / 5198 and `PreLoadIOContext` 7 /
    3391 like ten ordinary bodies each.

## The one remaining AUDIT unit

32. `VideoToolboxDecode` slot 29 `decodeFrame(from:completionHandler:)` @`0x101a6ce44` (572 instr)
    is the only genuinely open audit unit — an explicit `deferred_to_P3` DV-crux body, coupled to the
    DV/HDR work and gated on the protocol-witness verifier. Do not take it as a warm-up.

## What NOT to wave, in any session

33. **Source edits.** The pre-commit `l2_field_gate` blocks on the CLASS, not on your diff, so two
    "independent" edits in one file serialise anyway. Land derivations as specs during the wave, then
    apply them one unit and one commit at a time.
34. **Class-shape changes that ripple to consumers** (DisplayModel's `(frame:encoder:)` arity,
    VideoPlayerView's stored-property set, FFmpegDecode's signature). Single-threaded.
35. `GENERATED_ACCESSOR` (322 slots) is not a candidate at all: it collapses into declarations.

## Still open, not scheduled into a wave

36. `vtable_walk.py` resolves a bare class NAME to the FIRST classmap row, wrong across a
    cross-module collision (`PlayerView` is Notelet `0x1039e919c` before KSPlayer `0x1039ee210`).
    Take a module, prefer KSPlayer, ERROR on ambiguity — `fieldrec.desc_for_class` already implements
    that contract; copy it. Fold in the `vtable_walk` INDEX vs `vtable_impl_oracle` absolute-slot
    numbering fix (they differ by `VTableOffset`) at the same time.
37. `decode_string_literal.py` misses computed counts and the `_StringObject` bias direction.
38. `l2_field_gate`'s `merge_binary_type` should fall back to the trie's `.setter`/`.getter` type
    when there is no mangled property symbol. 11 REAL_FLAGs + 7 UNCHECKED on KSPlayerLayer wait on
    it — but the 205 unannotated stored properties (25.5% of 803, across 33 classes) are bigger.
39. Fix queue, coupled — **build both before staging either**: `KSPlayerLayer.seek(time:)` (`:601`)
    and `VideoPlayerView.change(definitionIndex:)` (`:371-373`). Re-derive the slot-64 claim first.
40. `Coordinator.player(layer:currentTime:totalTime:)`, the `startRecord` CRITICAL, **A · KSOptions**,
    the `T!` vs `T?` normalizer, Package F init bodies, MetalPlayView/`Drawable`, and extending the
    classmap to structs and enums are unchanged. See s84-handoff steps 26-32.

## Close out

41. Adjudicate every body with `adjudicate_verdict.py` (never delete `binary_addr` to pass the
    provenance guard). Note its guard requires a `decompile_cache` block with `verbatim: true`, and
    `verdict_provenance_gate.py` additionally requires the prefetch sidecar to EXIST on disk — so run
    `prefetch_decompiles.py` for each unit even when you read the body from the disassembler, which
    is what `STANDUP_PROTOCOL` §6 tells you to do. Do not hand-annotate that cache (P27).
    Run `verdict_provenance_gate.py --class <C>` on every class you touch.
42. Update `reconstruction/handoff_baseline.json` with a `captured_session89` block and refresh
    `head`, `ahead_origin`, `faithful_floor`, `stood_up_floor`, `wave_standup_size` and
    `wave_audit_size`. **Re-run `recon_gate --mode handoff` AFTER updating the baseline.** Take
    `ahead_origin` from `git rev-list --count origin/forward..forward`.
43. Record how many bodies landed, the verdict split, and every premise refuted — the refutations
    have been the highest-value output of the last nineteen sessions, above the code. Then write the
    session-90 handoff from the FINAL state, not by patching a mid-session draft. **Do not write the
    takeover prompt into it — give the prompt in chat.**
