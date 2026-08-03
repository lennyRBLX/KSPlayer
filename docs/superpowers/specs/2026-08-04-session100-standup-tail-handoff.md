# Session 100 work

You are the ORCHESTRATOR. Agents derive; you alone adjudicate, edit source, build and commit.

Session 99 took the stand-up wave from 109 units to 75 and left a large, perishable body of derived
intelligence behind. Your objective is to finish the wave — **and §2 tells you why the remaining 75
are cheaper than they look.**

## Verify first

1. Run `python3 scripts/recon_gate.py --mode handoff` — expect **PASS 50 / ANOMALY 0 / FAIL 3**. The
   three FAILs (`agg_critical` 7, `agg_high` 19, `agg_unresolved` 1) are session-98 fix-queue debt.
   They are NOT this session's target and you are not expected to move them.
2. Run `python3 scripts/recon_progress.py`. The faithful floor is **328** and it did not move in
   session 99, **by design** — `aggregate_verdicts` counts STOOD_UP in its own bucket because a body
   audited against nothing may not raise the floor. This session's progress numbers are the STOOD_UP
   count and the wave size, not the floor.
3. Re-derive every wave quantity with `python3 scripts/contract_numbers.py --group state`. Do not
   quote a count from this document; a count is a fact about a moment.
4. Read `MEMORY.md`, then `reconstruction/STANDUP_PROTOCOL.md` end to end (it SUPERSEDES
   `AGENT_PROTOCOL.md` for every unit here), then `reconstruction/DISPATCH_CONTRACT_s64.md`.
5. Read **`reconstruction/S99_STANDUP_INTELLIGENCE.md`**, **`S99_DERIVED_SettingsView.md`** and
   **`S99_DERIVED_IOSVideoPlayerView.md`** before you plan or dispatch anything. They are the reason
   §2 is true, and together they carry the whole of session 99's derivation for the remaining 75.
6. Read the `captured_session99_STANDUP_109_TO_75` block in `reconstruction/handoff_baseline.json`.

## 1. Where the wave stands

Session 99 landed **31** STOOD_UP verdicts (stood_up 61 → 92) and reclassified **3** units out of the
stand-up wave into the audit wave. The stand-up wave is now **75 units across 2 classes** —
SettingsView 43 and IOSVideoPlayerView 32 — and the audit wave is 4.

**The `SOURCE_MATCH 0` invariant was FALSE when session 99 opened, and the cause was a stale cache.**
`reconstruction/method_presence_cache.json` had been written before three source bodies existed, so
`PreLoadIOContext` idx21/idx54 and `LimitSeparatePreLoadIOContext` idx30 were classified BINARY_ONLY
when their own class's source declares them (PreLoadIOContext.swift:476 and :535,
LimitSeparatePreLoadIOContext.swift:622). The cache was regenerated (backup:
`method_presence_cache.pre_s99.bak`) and those three are now audit units. Re-derive the classification
with the cache bypassed — `MSP.classify(cls, idx, addr, use_cache=False)` — before trusting any bucket.

## 2. The remaining 75 are already derived — do NOT re-dispatch blind

Session 99 ran 14 derivation agents covering all 109 units. The 43 SettingsView and 32
IOSVideoPlayerView units were fully derived; their verdicts were simply not written before the session
ended. **The derivation was preserved in full**, across three files you must read before you
dispatch anything:

- `reconstruction/S99_STANDUP_INTELLIGENCE.md` — the class-level structural findings.
- `reconstruction/S99_DERIVED_SettingsView.md` — per-unit shape for all 43 SettingsView units.
- `reconstruction/S99_DERIVED_IOSVideoPlayerView.md` — per-unit shape for all 32 IOSVideoPlayerView units.

Those two per-unit files are **agent-derived and NOT fully orchestrator-verified** — session 99
re-verified the class-level facts and the naming routes, not every per-unit claim. Each entry carries
its own evidence; re-read the load-bearing instructions with the xcrun-resolved disassembler before a
claim enters a verdict (MEMORY rule 5). **You should not need a fresh derivation round for these 75 —
you need a verification round and then the writer.** The findings most likely to save you time:

7. The SettingsView **25-entry unexported field-offset table at `0x1044f1400`–`0x1044f14c0`**. This is
   the single most valuable finding of session 99. `field_offset_vector` refuses the class and it
   exports zero `vpWvd` globals, but the table exists, entry *i* is field record *i*, and the mapping
   is forced by size/alignment plus nine independent @objc-selector anchors. Read the file before you
   tell any agent that SettingsView field names are unrecoverable — that premise, which session 99's
   own briefs asserted, is wrong.
8. The **merged-body forwarder map**: several SettingsView units are 5–7 instruction constant-suppliers
   that tail-branch into a shared outlined body, so the selector names the entry point and the
   behaviour lives elsewhere. Eight stepper bodies forward to three shared implementations; idx156/158
   pass a *function pointer* consumed by `blr`, which no branch-target scan will find.
9. The IOSVideoPlayerView **menu call tree** (idx168 → idx176 → {idx177, idx178}; idx185 → idx186) and
   the two bodies that carry `#file`/`#line` (idx176 lines 1472/1473, idx186 lines 1799/1807).

## 3. Use the new naming route — it is the difference between 1 name and 33

10. Run `python3 scripts/objc_trampoline_oracle.py --class <C>` on every class before dispatching.
    A MainActor-isolated `@objc` method's IMP is a 4-instruction stub that puts the real body in **x4**
    (selector takes an argument) or **x3** (it takes none) and the DECLARATION line in the adjacent
    `w3`/`w2`, then tail-branches to a shared helper that does `blr` on it. The body address is never a
    branch target, so `method_source_presence.name_via_objc`'s `_calls_within` scan structurally cannot
    see it: across the wave it named 1 body where this oracle names 33.
11. The oracle REFUSES a body reached by more than one selector. Honour that: IOSVideoPlayerView
    `0x101b0de50` is reached by `handleUnifiedSettingsButtonTapped` (line 1310) AND
    `handleSettingsButtonTapped` (line 1343) while the trie names it `showUnifiedSettings`.
12. The line number is the **@objc entry point's declaration line**, never the body's, and its `#file`
    companion names the file Forward COMPILED. Both are ORIGIN evidence, never evidence that a source
    counterpart exists.

## 4. Write verdicts through the writer, not by hand

13. Use `python3 scripts/write_standup_verdict.py --facts <file>`. It re-derives extent, exported
    symbol, ICF fold count, vtable dispatch and `slot = VTableOffset + idx` per file rather than
    letting you type them, and it REFUSES `source_lines`, a non-empty `divergences`, an empty
    `unrecovered`, an instruction count that disagrees with the binary, a non-entry address, or an
    absent idx. Run `--selfcheck` once first.
14. Then set the verdict with `python3 scripts/adjudicate_verdict.py --final STOOD_UP`. Pass the
    evidence by file — `--evidence "$(cat <path>)"` — because `command_shape_hook` matches the whole
    line and cannot tell a tool citation from an invocation.
15. Do **not** write Swift source for these bodies. A stand-up is the intelligence pass; writing the
    source is a separate act, and the body reaches the floor only when it is audited against a verbatim
    decompile and adjudicated FAITHFUL.

## 5. Three tool defects are open, and one is a trap

16. `scripts/field_offset_vector.py:94` hand-builds `$s<len>module<len>clsCN` and omits Swift's `AA`
    module-backreference, so for a class whose name equals its module it reports a FALSE "no exported
    metadata symbol" — the real symbol is `$s16PreLoadIOContextAACN` at `0x1044f62b8`. **Do NOT fix the
    mangler alone.** All four PreLoadIOContext-module classes are `metadata_init=1`, so the offsets are
    genuinely absent from the static image and a mangler-only fix would return a complete, fictional
    all-zero map. Check `metadata_init` FIRST, report that as the reason, then fix the symbol lookup,
    and anchor a golden on both a `metadata_init=1` class and one with a real static vector
    (ThumbnailSession, vector @`0x1044e9768`).
17. `python3 scripts/decode_string_literal.py --addr 0x101b1d474` aborts with an out-of-image read at
    `0x104c63148`.
18. `fieldrec.py` reports 65 field records for IOSVideoPlayerView while `dump_field_bindings.py`
    reports 63. The two disagree by 2 and it is unresolved.

## 6. Pitfalls that cost session 99 time

19. `recover_swift_function_name.py` returned FIVE false anchors this session, all at self-reported
    medium/high confidence with `labels=0`: `CenterResizeVertex` (Anime4K idx45 — actually one half of
    a vertex/fragment shader pair fed to `newFunctionWithName:`), `Fql` (VideoSwresample idx30 — the
    first NUL-terminated run of a mangled-name *table*, a NEW failure mode for that tool),
    `cachedTimeRanges(duration:)` (PreLoadIOContext idx54), `Default` (SettingsView idx151 — element 0
    of a UI-title array) and `Leading` (SettingsView idx168 — element 0 of the alignment array, passed
    to `_swift_arrayDestroy`). Apply the trust test every time: `labels>=1` AND an in-body
    materialization AND a loaded character count equal to the name's length.
20. **Swift's `#function` includes the argument-label list.** Session 99's own brief asked for
    `len("prefetchUpcoming")==16` when the right expectation was `len("prefetchUpcoming(from:)")==23`,
    and nearly rejected a good name. Compute the expected length from the full labelled spelling.
21. `self` is NOT always in x20 — IOSVideoPlayerView idx130 uses x19 and idx143 uses x22. A field sweep
    keyed on x20 alone silently under-reports; track `mov xD, x20` aliases.
22. The IOSVideoPlayerView source file is at
    `/Users/jweaver/Desktop/Work/swift/KSPlayer/Sources/KSPlayer/Video/IOSVideoPlayerView.swift`, it is
    **602 lines** (not ~728), and it is NOT under `play/` — a grep rooted there finds nothing and reads
    silently as "no source".
23. Before concluding ANY member is absent, grep the DEMANGLED export trie, not `Sources/`. Build it
    once: dump `export_trie_oracle.build_index` (57,138 names) through `xcrun swift-demangle` and grep
    that. A hand-built mangled symbol is not a search.

## Close out

24. Re-run `python3 scripts/aggregate_verdicts.py` and `python3 scripts/wave_worklist.py --wave standup`
    and record the STOOD_UP count and the live wave size.
25. Update `reconstruction/handoff_baseline.json`: add a `captured_session100` block and refresh
    `faithful_floor`, `stood_up_floor`, `wave_standup_size`, `wave_audit_size`, `head` and
    `ahead_origin` if the gate reports them as ANOMALY.
26. Run `python3 scripts/handoff_completeness_lint.py <this file>` and then write the session-101
    handoff.
27. Commit on the `forward` branch through `bash scripts/commit_unit.sh -F <msgfile>` and confirm HEAD
    moved — `git commit` exits 0 when the pre-commit hook blocks.

**Durability, worth one line:** `reconstruction/` and `scripts/` are both gitignored in `play`. The 92
stand-up verdicts, `S99_STANDUP_INTELLIGENCE.md`, the two new tools and the 2,174 cached decompiles
live on this disk only.
