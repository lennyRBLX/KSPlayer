# Session 100 work

You are the ORCHESTRATOR. Agents derive; you alone adjudicate, edit source, build and commit.

**This is an ORIENTATION handoff. It does not authorize any work.** Session 99 ended with the
stand-up wave partly drained and its remaining derivation preserved on disk, and the right next move
depends on a judgement the human has not made yet — see §2. Verify the state, read the context, report
what you find, and **stop**.

## Verify first

1. Run `python3 scripts/recon_gate.py --mode handoff` — expect **PASS 50 / ANOMALY 0 / FAIL 3**. The
   three FAILs (`agg_critical` 7, `agg_high` 19, `agg_unresolved` 1) are session-98 fix-queue debt.
   They are NOT a session-100 target unless the human says so.
2. Run `python3 scripts/recon_progress.py` — the faithful floor is **328**. It did not move in session
   99 and that is BY DESIGN: `aggregate_verdicts` counts STOOD_UP in its own bucket, because a body
   audited against nothing may not raise the floor. The stand-up progress numbers are the STOOD_UP
   count and the wave size, never the floor.
3. Re-derive every wave quantity with `python3 scripts/contract_numbers.py --group state`. Do not quote
   a count from this document; a count is a fact about a moment, and session 99 shipped a stale one.
4. Read `MEMORY.md`, then `reconstruction/STANDUP_PROTOCOL.md` end to end — it SUPERSEDES
   `reconstruction/AGENT_PROTOCOL.md` for every unit in this wave and its verdict vocabulary is the
   only correct one here — then `reconstruction/DISPATCH_CONTRACT_s64.md`.
5. Read `reconstruction/S99_STANDUP_INTELLIGENCE.md`, `reconstruction/S99_DERIVED_SettingsView.md` and
   `reconstruction/S99_DERIVED_IOSVideoPlayerView.md`. Together they carry the whole of session 99's
   derivation for the 75 units that remain.
6. Read the `captured_session99_STANDUP_109_TO_75` block in `reconstruction/handoff_baseline.json`.

## 1. Stop after step 6

7. Do **not** dispatch an agent, write a verdict, edit a source file, run a build, or touch the git
   index until the human has given you a directive. Report: the gate result, the live wave split from
   step 3, and — if you disagree with anything in §2, §3 or §4 — say so with the command output that
   establishes it. Then wait.

## 2. The judgement the human has not made

8. The stand-up wave is **75 units across 2 classes** — SettingsView 43, IOSVideoPlayerView 32 — and
   the audit wave is 4. All 75 were fully derived in session 99 and the derivation is on disk (step 5).
   They were never written to verdicts.
9. The open question is what those 75 are worth *now*. A stand-up moves the faithful floor by **zero**;
   its value is the intelligence it banks for a later reconstruction. The remaining units are the two
   largest, most UI-shaped classes in the wave, and the fix queue (§4) is what actually holds the floor
   down. **Finishing the wave and draining the fix queue are competing claims on this session, and the
   human decides between them.** Do not assume the wave.
10. If the human does choose the wave: the 75 need a **verification round plus the writer**, not a
    fresh derivation round. The per-unit files are agent-derived and NOT fully orchestrator-verified —
    session 99 re-verified the class-level facts and the naming routes, not every per-unit claim — so
    each entry is a lead carrying its own evidence that must be re-read against the binary with the
    xcrun-resolved disassembler before it enters a verdict (MEMORY rule 5).

## 3. Facts session 99 established that change how you would work

11. **The wave's `SOURCE_MATCH 0` invariant was FALSE when session 99 opened.**
    `reconstruction/method_presence_cache.json` predated three source bodies, so `PreLoadIOContext`
    idx21/idx54 and `LimitSeparatePreLoadIOContext` idx30 read as BINARY_ONLY while their own class's
    source declares them (PreLoadIOContext.swift:476 and :535, LimitSeparatePreLoadIOContext.swift:622).
    They are audit units now. Re-derive any bucket with the cache bypassed —
    `MSP.classify(cls, idx, addr, use_cache=False)` — before trusting it.
12. **Regenerate the wave → presence → contract chain in that order, and give the presence step its
    `--json` flag.** `python3 scripts/method_source_presence.py --wave standup` prints to stdout and
    leaves `reconstruction/method_presence_standup.json` untouched; only
    `--json reconstruction/method_presence_standup.json` refreshes the artifact
    `contract_numbers.py` reads. Session 99 shipped a split of 53/56 summing to 109 against a 75-unit
    wave for exactly this reason.
13. **Use `python3 scripts/objc_trampoline_oracle.py --class <C>` before deciding any body is unnamed.**
    A MainActor-isolated `@objc` IMP is a 4-instruction stub that puts the real body in **x4** (selector
    takes an argument) or **x3** (it takes none) and the DECLARATION line in the adjacent `w3`/`w2`,
    then tail-branches to a shared helper that `blr`s it — so the body address is never a branch TARGET
    and `method_source_presence.name_via_objc`'s `_calls_within` scan structurally cannot see it. Across
    the wave it named 1 body where this oracle names 33.
14. The oracle REFUSES a body reached by more than one selector. Honour that: IOSVideoPlayerView
    `0x101b0de50` is reached by `handleUnifiedSettingsButtonTapped` (line 1310) AND
    `handleSettingsButtonTapped` (line 1343) while the trie names it `showUnifiedSettings`.
15. That line number is the **@objc entry point's declaration line**, never the body's, and its `#file`
    companion names the file Forward COMPILED. Both are ORIGIN evidence, never evidence that a source
    counterpart exists.
16. **Write any stand-up verdict through `python3 scripts/write_standup_verdict.py --facts <file>`.**
    It re-derives extent, exported symbol, ICF fold count, vtable dispatch and `slot = VTableOffset +
    idx` per file rather than letting you type them, and refuses `source_lines`, a non-empty
    `divergences`, an empty `unrecovered`, an instruction count that disagrees with the binary, a
    non-entry address, or an absent idx. Run `--selfcheck` once first.
17. Set the verdict with `python3 scripts/adjudicate_verdict.py --final STOOD_UP`, and pass the evidence
    by file — `--evidence "$(cat <path>)"` — because `command_shape_hook` matches the whole line and
    cannot tell a tool citation from an invocation.
18. Do **not** write Swift source for a stand-up body. The stand-up is the intelligence pass; writing
    the source is a separate act, and the body reaches the floor only when it is audited against a
    verbatim decompile and adjudicated FAITHFUL.

## 4. Open defects, one of them a trap

19. `scripts/field_offset_vector.py:94` hand-builds `$s<len>module<len>clsCN` and omits Swift's `AA`
    module-backreference, so for a class whose name equals its module it reports a FALSE "no exported
    metadata symbol" — the real symbol is `$s16PreLoadIOContextAACN` at `0x1044f62b8`. **Do NOT fix the
    mangler alone.** All four PreLoadIOContext-module classes are `metadata_init=1`, so the offsets are
    genuinely absent from the static image and a mangler-only fix would return a complete, fictional
    all-zero map. Check `metadata_init` FIRST, report that as the reason, then fix the symbol lookup,
    and anchor a golden on both a `metadata_init=1` class and one with a real static vector
    (ThumbnailSession, vector `@0x1044e9768`).
20. `python3 scripts/decode_string_literal.py --addr 0x101b1d474` aborts with an out-of-image read at
    `0x104c63148`.
21. `scripts/fieldrec.py` reports 65 field records for IOSVideoPlayerView while
    `scripts/dump_field_bindings.py` reports 63. The two disagree by 2 and it is unresolved.
22. The fix queue is what actually holds the floor at 328: `agg_critical` 7, `agg_high` 19,
    `agg_unresolved` 1. Session 98 could not drain it because seven of its verdicts record their own
    unfixability, one as the literal instruction `DO NOT WRITE THIS YET`. Do not import that pessimism
    into the stand-up wave, and do not import the stand-up wave's reachability into the fix queue.

## 5. Pitfalls that cost session 99 time

23. `scripts/recover_swift_function_name.py` returned FIVE false anchors in one session, all at
    self-reported medium/high confidence with `labels=0`: `CenterResizeVertex` (Anime4K idx45 — one
    half of a vertex/fragment shader pair fed to `newFunctionWithName:`), `Fql` (VideoSwresample idx30
    — the first NUL-terminated run of a mangled-name TABLE, a new failure mode),
    `cachedTimeRanges(duration:)` (PreLoadIOContext idx54), `Default` (SettingsView idx151 — element 0
    of a UI-title array) and `Leading` (SettingsView idx168 — element 0 of the alignment array, passed
    to `_swift_arrayDestroy`). Apply the trust test every time: `labels>=1` AND an in-body
    materialization AND a loaded character count equal to the name's length.
24. **Swift's `#function` includes the argument-label list.** A session-99 brief asked for
    `len("prefetchUpcoming")==16` when the right expectation was `len("prefetchUpcoming(from:)")==23`,
    and nearly rejected a good name. Compute the expected length from the full labelled spelling.
25. `self` is NOT always in x20 — IOSVideoPlayerView idx130 uses x19 and idx143 uses x22. A field sweep
    keyed on x20 alone silently under-reports; track `mov xD, x20` aliases.
26. The IOSVideoPlayerView source is at
    `/Users/jweaver/Desktop/Work/swift/KSPlayer/Sources/KSPlayer/Video/IOSVideoPlayerView.swift`, it is
    **602 lines**, and it is NOT under `play/` — a grep rooted there finds nothing and reads silently
    as "no source".
27. Before concluding ANY member is absent, grep the DEMANGLED export trie, not `Sources/`. Build it
    once: dump `export_trie_oracle.build_index` (57,138 names) through `xcrun swift-demangle` and grep
    that. A hand-built mangled symbol is not a search — word substitution hides the real one.

## Close out

Only once the human has given you a directive and you have finished it:

28. Re-run `python3 scripts/aggregate_verdicts.py` and `python3 scripts/wave_worklist.py --wave standup`
    and record the STOOD_UP count and the live wave size.
29. Regenerate the artifact chain per step 12 so the next session's `contract_numbers.py` is coherent.
30. Update `reconstruction/handoff_baseline.json`: add a `captured_session100` block and refresh
    `faithful_floor`, `stood_up_floor`, `wave_standup_size`, `wave_audit_size`, `head` and
    `ahead_origin` if the gate reports them as ANOMALY.
31. Run `python3 scripts/handoff_completeness_lint.py <the session-101 handoff>` and then write that
    handoff.
32. Commit on the `forward` branch through `bash scripts/commit_unit.sh -F <msgfile>` and confirm HEAD
    moved — `git commit` exits 0 when the pre-commit hook blocks.

**Durability, worth one line:** `reconstruction/` and `scripts/` are both gitignored in `play`. The 92
stand-up verdicts, the three S99 derivation files, `objc_trampoline_oracle.py`,
`write_standup_verdict.py` and the 2,174 cached decompiles live on this disk only.
