# Session 88 work

Session 87 settled what a verdict MEANS for a body with no source counterpart, built and gate-wired
the tooling to count it, and then **completed ThumbnailQueue: 15 of 15 bodies stood up.** The
faithful floor did not move, and that is by design, not a shortfall — a stand-up body has no source
counterpart and may never enter the faithful floor. `agg_stood_up` is where this work accrues.

Note on filenames: this directory does not sort in session order. **Order by the session number.**

## Verify first

1. Run `ps -Ao pid,etime,command | grep -c "MacOS/claude --output-format stream-json"` FIRST. One
   live session prints **4** lines. Print `ps -Ao pid,ppid,etime,command | grep MacOS/claude` and
   confirm there is no SECOND unrelated parent/child pair before touching `reconstruction/` or
   `forward`. `recon_gate --mode handoff` WRITES `reconstruction/handoff_report.json`, so running it
   IS touching `reconstruction/` and this step gates it.
2. Run `python3 scripts/recon_gate.py --mode handoff` from `/Users/jweaver/Desktop/Work/swift/play`
   — expect **PASS 43 / ANOMALY 0 / FAIL 3**. PASS rose 39 -> 43 across s87 (`test_standup`,
   `agg_stood_up`, `wave_audit_size`, `wave_standup_size`). The 3 FAILs are the unchanged known
   debt: `agg_critical 15`, `agg_high 55`, `agg_unresolved 1`. Floor **299**, `agg_stood_up`
   **15**, `wave_standup_size` **160**, `wave_audit_size` **6**.
3. **The floor HELD at 299 and that is correct.** Fifteen bodies were stood up; none is auditable,
   so none may count toward FAITHFUL. Read `agg_stood_up` for this wave's progress.
4. Run `python3 scripts/recon_progress.py`. ⚠️ Its "REAL_METHOD remainder" line still prints the
   PRE-s86 split ("97 in classes WITH source ... 84 ... NO source"). That prose is STALE — the
   corrected split is audit 6 / standup 160. Fix the string or delete it; do not quote it onward.
5. **The two-repo split.** Swift sources, the `forward` branch and these handoffs live in
   `/Users/jweaver/Desktop/Work/swift/KSPlayer`. The cwd `/Users/jweaver/Desktop/Work/swift/play`
   holds `scripts/` and `reconstruction/`, both gitignored there. Address KSPlayer with `git -C`;
   run every `scripts/` command from `play`. FFmpegKit is a SIBLING of KSPlayer at
   `/Users/jweaver/Desktop/Work/swift/FFmpegKit`, not inside it.
6. Read MEMORY.md before anything else. A PreToolUse hook is LIVE
   (`scripts/command_shape_hook.py`); if it blocks you the stderr names the check. It fired four
   times in s87 and was right every time — including once on a bare tool name appearing inside
   ordinary prose, and once on a compound command that mixed a `--macho` call with a ranged one.
   Rephrase or split; never weaken it.

## What s87 settled — do not re-derive

7. **The verdict KIND for a stand-up unit is `STOOD_UP`**, and it is enforced, not conventional.
   `aggregate_verdicts.py` counts it in its OWN bucket and never in `faithful`. The choice was
   grounded, not picked: that file dispatches on an if/elif chain whose `else` branch only WARNS, so
   any new word nothing was taught to count contributes ZERO while the run still exits 0. Reusing
   `FAITHFUL` would have inflated the floor with bodies audited against nothing; reusing
   `UNRESOLVED` would have turned 1 known debt into 176 and destroyed that gate's signal.
8. **`adjudicate_verdict.py` REFUSES `STOOD_UP` in two cases**, so the word cannot become an escape
   hatch from an audit: when the verdict carries `source_lines` (a body WITH a counterpart must be
   audited, not stood up), and when it carries `divergences`. `sc_adjudicate` is now 12/12.
9. **`scripts/test_standup_verdict.py` is the golden**, wired as `test_standup`. Its load-bearing
   assertion is the NEGATIVE CONTROL: an unrecognized word must still be skipped and must NOT be
   absorbed into the new bucket. It also pins that a counter LABEL containing "FAITHFUL" would
   silently redefine the floor, because `recon_gate` extracts it with `FAITHFUL:\s*(\d+)`.
10. **`reconstruction/STANDUP_PROTOCOL.md` is the agent contract for this wave** and supersedes
    `AGENT_PROTOCOL.md` for stand-up units only. Seven agents were held to it across two batches and
    all seven returned the exact envelope with `UNGROUNDED: 0`.
11. **Wave SIZES are no longer asserted inside `wave_worklist --selfcheck`.** They moved to
    `recon_gate` as `wave_audit_size` / `wave_standup_size` pins, whose `pin` kind raises an ANOMALY
    on change so a human adjudicates each move against the baseline. A size necessarily changes
    every time a verdict lands; asserting it in a selfcheck turned that selfcheck red on a session
    that had done nothing wrong, and training the "just bump the number" reflex is how a real
    regression gets waved through. The selfcheck keeps the assertions that survive progress: the
    self-adjusting PARTITION, the dispatchability property, and address-keyed coverage anchors.

## What s87 landed

12. **ThumbnailQueue is COMPLETE — all 15 REAL_METHOD slots stood up, adjudicated, provenance gate
    OK.** Slots 10, 11, 12, 13, 14, 15, 16, 17, 19, 20, 21, 23, 24, 25, 26. Verdicts in
    `reconstruction/verdicts/ThumbnailQueue_*_s87.json`.
13. **A batching lesson worth reusing: derive small bodies YOURSELF.** Batch 2's eight bodies (23-62
    instr each) were read directly by the orchestrator, not dispatched. An agent round-trip costs
    2-4k tokens of report to verify; a 26-instruction body costs ~30 lines to read. Dispatch agents
    for the LARGE bodies (slots 11 at 168 instr and 12 at 184 went to agents) and derive the rest.
    This roughly tripled throughput per unit of context versus batch 1.
14. **The ThumbnailQueue field-offset map, established THREE independent ways that agree exactly**:
    `pendingIndices 0x10 · generatedSet 0x18 · skippedSet 0x20 · lock 0x28 · id 0x30 · count 0x40 ·
    duration 0x48`, InstanceSize `0x50`, AlignMask `0x7`. (a) anchor sites across five bodies,
    (b) the trie-named accessors `count.getter` @`0x10097c5e4` and `duration.getter` @`0x1000969b0`,
    (c) **the runtime field-offset vector at metadata `0x1044e9910` + `0x50`**
    (`FieldOffsetVectorOffset` = 10 words), read straight out of `__DATA`.
15. **(c) is the offset resolver that the s84-s87 handoffs have listed as UNBUILT.** It is a
    deterministic read: `export_trie_oracle --symbol '$s<Class>CN'` for the metadata address, the
    descriptor's `FieldOffsetVectorOffset` for the displacement, then one `u64` per field in
    field-record order. **Build it as a tool** (step 30) — it retires the anchor-site hand method.
16. **The class helper glossary, all resolved through the bind table, not inferred**: `0x10345cb74`
    `_swift_beginAccess` · `0x10345cb80` `_swift_bridgeObjectRelease` · `0x10345cb98`
    `_swift_bridgeObjectRetain` · `0x10345cce8` `_swift_endAccess` · `0x10345cf88`
    `_swift_isUniquelyReferenced_nonNull_native` · `0x10345cfc4` `_swift_release` · `0x1034599c4`
    `Swift.Hasher._hash(seed:_:)` · `0x104112d00` `__swiftEmptyArrayStorage` · `0x104112d10`
    `__swiftEmptySetSingleton` · `0x1041123c0` `_$ss22_minimumMergeRunLengthyS2iF` · objc stubs
    `0x103464ae0` = selector `lock` and `0x10346e620` = selector `unlock` (selrefs `0x10440c080` ->
    `0x1039893c0`, `0x10440e750` -> `0x103999f20`, via `dyld_info -fixups`).
17. **Shape findings that a name alone would have got wrong.** `clear()` empties `pendingIndices`
    and nothing else, whereas `reset()` REBUILDS it to a `count`-length array AND empties
    `generatedSet` — the two are not synonyms, and neither touches `skippedSet`.
    `seek(toTime:)` inlines `index(forTime:)` then TAIL-CALLS `seek(toIndex:)`, but its
    `duration <= 0` path `ret`s instead, so it is a NO-OP rather than seeking to 0.
    `putBack(i)` is a guarded move: if `generatedSet` already contains `i` it does nothing.
    `restoreCached(where:)` runs its predicate over the DENSE RANGE `0..<count`, not over
    `pendingIndices`, so it POPULATES `generatedSet` and then filters `pendingIndices` against it —
    materially different from its sibling `restoreCached(Set<Int>)`, which filters against the
    argument set.
18. **`seek(toIndex:)` is a three-way partition, not a sort by distance.** One pass sends
    `element > index` to one local, `element < index` to another, and `element == index` to NEITHER;
    the above-target partition is sorted ASCENDING and the below-target DESCENDING (predicate
    `0x1019529d8` is `cmp x9,x8` / `cset w0,lt`, i.e. `b < a`); the result is
    `[target if already pending] ++ (>index asc) ++ (<index desc)`. It REBUILDS the array rather
    than reordering in place, it never enqueues work that was not already pending, and its bounds
    check is a GRACEFUL early return — the body contains ZERO `brk`.
19. **A class-wide exclusivity pattern, consistent across all 15 bodies**: `swift_beginAccess` with
    flag operand `0x0` or `0x1` is NOT paired with `swift_endAccess`; flag `0x21` IS.
    `restoreCached(where:)` opens the SAME field under `0x21` and then `0x00` in one body, which is
    the clearest in-image evidence that the flag discriminates write from read. The ABI meaning of
    the bits was deliberately NOT asserted — it was not read from this binary.

## Premises s87 REFUTED — the highest-value output

20. **"Slots 18/22/27/28/29 are Getters" was INCOMPLETE.** Slots 0, 3 and 6 are Getters too. The
    orchestrator handed that premise to five agents; one refuted it from `vtable_walk` output the
    orchestrator already had.
21. **"retrySkipped is the largest body in the class" was WRONG.** Slot 12 `seek(toIndex:)` is 184
    instr against retrySkipped's 151. The refutation was sitting in the orchestrator's own
    `wave_standup.json`, unchecked.
22. **`vtable_walk.py` and `vtable_impl_oracle.py` number the same entry differently**, reported
    independently by three agents. `vtable_walk` prints the descriptor INDEX; `vtable_impl_oracle`
    prints the absolute metadata slot (index + `VTableOffset` 17). **A consumer conflating the two
    columns is off by 17.** Every worklist and every s87 verdict uses the INDEX convention.
23. **A `NOT_IN_TRIE` getter can still be a one-instruction thunk.** `pendingCount.getter`
    @`0x101a2def8` is `b 0x101a2e1e0` — the s86 FFmpegDecode Impl-thunk pattern recurring here.
24. **A `dump_binary_field_types.py` crash reported by TWO agents did NOT reproduce**, and they
    reported it at two DIFFERENT lines. **If you fan out widely, expect Ghidra-backed tools to flake
    under concurrency and re-run before believing an agent's tool-failure claim.**

## Session 88 — continue the STAND-UP wave

25. Regenerate the worklist and its DERIVED presence file in the same breath, never read either
    blind: `python3 scripts/wave_worklist.py --wave standup --json reconstruction/wave_standup.json`
    then `python3 scripts/method_source_presence.py --wave standup --json
    reconstruction/method_presence_standup.json`. Expect 160 units / 29 classes, 87 NAMED /
    73 UNNAMED, SOURCE_MATCH 0. Then run `--coverage-audit standup` and adjudicate its 3 hits.
26. **Adjudicate the 3 coverage hits FIRST — they may be free progress.** `VideoSwresample` slots 29
    and 31 already carry per-body verdicts (`FAITHFUL` and `FAITHFUL_SPINE + 1 DEFERRED`) that the
    worklist cannot see because they live in `bodies[].addr`; that is ~646 instructions possibly
    already done. `FFmpegDecode` slot 18 @`0x101a23404` is a real open deferral.
27. **Next cheap NAMED classes, in this order**: `Anime4KPipeline` 13 units / 2459 instr (10 NAMED),
    `KSAVPlayer` 7 / 626 (all NAMED), `KSComplexPlayerLayer` 3 / 253, `KSVideoPlayerModel` 2 / 82,
    `KSPlayerLayer` 12 / 1355 (all NAMED; s86 established all 12 are binary-only). Do the class-level
    derivation ONCE per class (vtable, field-offset vector, helper glossary) — that is what made
    ThumbnailQueue cheap.
28. **Batch by CLASS; dispatch ONE BODY PER AGENT for large bodies and derive small ones yourself**
    (step 13). Hold every agent to `reconstruction/STANDUP_PROTOCOL.md`.
29. **CHECK YOUR OWN PREMISES against the worklist before writing them into a brief.** Two of s87's
    refutations were of orchestrator premises checkable in seconds (steps 20, 21).
30. **Build the field-offset resolver of step 15** as a new `scripts/` tool (name it when you build
    it; `handoff_completeness_lint` BLOCKS on a handoff naming a script not yet on disk, which is why
    it is unnamed here). Golden-gate it on ThumbnailQueue's known answer from step 14 — all 7 offsets
    plus InstanceSize `0x50` — and add a negative control so it cannot silently fall back to
    field-record ORDER when the metadata read fails.
31. `SettingsView` is 43 units / 9880 instr and **all 43 are UNNAMED**; `IOSVideoPlayerView` is 32 /
    9122, all NAMED but with zero source overlap. Together they are ~47% of the remaining wave. Leave
    both until the cheap NAMED classes are exhausted.
32. Budget `Anime4K` 3 units / 4780 instr, `ThumbnailSession` 4 / 5198 and `PreLoadIOContext` 7 /
    3391 like ten ordinary bodies each.

## The one remaining AUDIT unit

33. `VideoToolboxDecode` slot 29 `decodeFrame(from:completionHandler:)` @`0x101a6ce44` (572 instr)
    is the only genuinely open audit unit — an explicit `deferred_to_P3` DV-crux body, coupled to the
    DV/HDR work and gated on the protocol-witness verifier. Do not take it as a warm-up.

## What NOT to wave, in any session

34. **Source edits.** The pre-commit `l2_field_gate` blocks on the CLASS, not on your diff, so two
    "independent" edits in one file serialise anyway. Land derivations as specs during the wave, then
    apply them one unit and one commit at a time.
35. **Class-shape changes that ripple to consumers** (DisplayModel's `(frame:encoder:)` arity,
    VideoPlayerView's stored-property set, FFmpegDecode's signature). Single-threaded.
36. `GENERATED_ACCESSOR` (322 slots) is not a candidate at all: it collapses into declarations.

## Still open, not scheduled into a wave

37. `vtable_walk.py` resolves a bare class NAME to the FIRST classmap row, wrong across a
    cross-module collision (`PlayerView` is Notelet `0x1039e919c` before KSPlayer `0x1039ee210`).
    Take a module, prefer KSPlayer, ERROR on ambiguity — `fieldrec.desc_for_class` already implements
    that contract; copy it. Fold in the slot-numbering fix of step 22 at the same time.
38. `decode_string_literal.py` misses computed counts and the `_StringObject` bias direction.
39. `l2_field_gate`'s `merge_binary_type` should fall back to the trie's `.setter`/`.getter` type
    when there is no mangled property symbol. 11 REAL_FLAGs + 7 UNCHECKED on KSPlayerLayer wait on
    it — but the 205 unannotated stored properties (25.5% of 803, across 33 classes) are bigger.
40. Fix queue, coupled — **build both before staging either**: `KSPlayerLayer.seek(time:)` (`:601`)
    and `VideoPlayerView.change(definitionIndex:)` (`:371-373`). Re-derive the slot-64 claim first.
41. `Coordinator.player(layer:currentTime:totalTime:)`, the `startRecord` CRITICAL, **A · KSOptions**,
    the `T!` vs `T?` normalizer, Package F init bodies, MetalPlayView/`Drawable`, and extending the
    classmap to structs and enums are unchanged. See s84-handoff steps 26-32.
42. ⚠️ **DURABILITY RISK — now the FIRST thing to decide, because the work is being run as a LOOP.**
    `KSPlayer/docs/superpowers/` contains ONLY `specs/`. Every tool, gate, hook, protocol and
    worklist — including `method_source_presence.py` (the wave-split authority) and
    `STANDUP_PROTOCOL.md` (the contract for the whole remaining queue) — exists ONLY on this disk
    under `play/`, which gitignores `docs/` and `scripts/`. **All 15 s87 verdicts are unversioned:
    `reconstruction/` is gitignored in `play` and absent from `KSPlayer`, so nothing but this
    handoff's prose survives in git.** A one-off session could tolerate that; a repeating loop
    compounds unversioned state every iteration. s87 deliberately did NOT copy files across
    piecemeal, because a second copy that silently diverges is the worse failure. **Decide where this
    layer is versioned before running another iteration.** Backups:
    `reconstruction/_scripts_backup_s71_8cb7b40`, `reconstruction/MEMORY_s85_pre_split_backup.md`.

## Close out

43. Adjudicate every body with `adjudicate_verdict.py` (never delete `binary_addr` to pass the
    provenance guard). Run `verdict_provenance_gate.py --class <C>` on every class you touch.
44. Update `reconstruction/handoff_baseline.json` with a `captured_session88` block and refresh
    `head`, `ahead_origin`, `faithful_floor`, `stood_up_floor`, `wave_standup_size` and
    `wave_audit_size`. **Re-run `recon_gate --mode handoff` AFTER updating the baseline.** Take
    `ahead_origin` from `git rev-list --count origin/forward..forward`.
45. Record how many bodies landed, the verdict split, and every premise refuted — the refutations
    have been the highest-value output of the last eighteen sessions, above the code. Then write the
    session-89 handoff from the FINAL state, not by patching a mid-session draft. **Do not write the
    takeover prompt into it — give the prompt in chat.**
