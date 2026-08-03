# Session 99 — drain the stand-up wave

You are the ORCHESTRATOR. Agents derive; you alone adjudicate, edit source, build and commit.

This session has ONE objective: take the stand-up wave to zero. Unlike the session-98 fix-queue
goal, **this objective is well-posed** — see §1. Read that section before you plan anything, because
it is the reason this handoff exists as its own session rather than as a lane inside another.

`reconstruction/STANDUP_PROTOCOL.md` **supersedes** `reconstruction/AGENT_PROTOCOL.md` for every unit
here. `AGENT_PROTOCOL.md` is an AUDIT contract and its verdict vocabulary is wrong for this work.

## 0. Verify first

1. Run `python3 scripts/recon_gate.py --mode handoff` — expect **PASS 50 / ANOMALY 0 / FAIL 3**. The
   three FAILs (`agg_critical`, `agg_high`, `agg_unresolved`) are the session-98 fix-queue debt.
   They are NOT this session's target and you are not expected to move them.
2. Run `python3 scripts/recon_progress.py` — expect the faithful floor at **328 / 1035**. If it
   disagrees with `python3 scripts/aggregate_verdicts.py`, the BASELINE is stale, not the tool:
   `recon_progress` reads `.faithful_floor` from `reconstruction/handoff_baseline.json` as a pin.
   Session 98 found it 18 behind. `aggregate_verdicts` is authoritative for the floor.
3. Re-derive every wave quantity with `python3 scripts/contract_numbers.py --group state`. This
   document quotes the split ONCE, in §2, as a starting shape only. The wave shrinks as you work it;
   a count is a fact about a moment, not about the project.
4. Read `MEMORY.md`, then `reconstruction/STANDUP_PROTOCOL.md` end to end, then
   `reconstruction/DISPATCH_CONTRACT_s64.md`.
5. Read the session-98 capture blocks in `reconstruction/handoff_baseline.json`, especially
   `captured_session98_FIX_QUEUE_124_TO_52` — its methodological finding applies directly to this
   wave and is restated in §4.

## 1. Why this objective is reachable, and the last one was not

Session 98 was given "drain the fix queue to zero" and could not finish it: seven of its verdicts
record their own unfixability, one of them as the literal instruction `DO NOT WRITE THIS YET`.
Closing those would have required writing code that was never read from the binary.

**A stand-up unit has no such failure mode.** It asserts a recovered SHAPE, and
`STANDUP_PROTOCOL.md` §4 makes *"could not recover"* a first-class, RECORDABLE outcome — provided it
carries the decisive existence check that failed, with its command and its literal output. A unit
whose name is irreducible still completes; it completes as an `UNNAMED` stand-up with a populated
`unrecovered` array.

So the wave can genuinely reach zero without inventing anything. **That is the difference. Do not
import session 98's pessimism into this wave — and equally, do not import this wave's reachability
back into the fix queue.**

## 2. The wave as it stands

6. Regenerate the wave and the presence file in the same breath, then read the `counts` block:
   `python3 scripts/wave_worklist.py --wave standup --json reconstruction/wave_standup.json` and
   `python3 scripts/method_source_presence.py --wave standup`.

At the close of session 98 it was **109 units across 15 classes**, splitting **53 BINARY_ONLY / 56
UNNAMED / 0 SOURCE_MATCH**. `SOURCE_MATCH 0` is the INVARIANT; the other two are not. Two classes
carry 75 of the 109:

| units | instr | class | has source file |
|---|---|---|---|
| 43 | 9880 | SettingsView | no |
| 32 | 9122 | IOSVideoPlayerView | **yes** |
| 7 | 3391 | PreLoadIOContext | yes |
| 4 | 5198 | ThumbnailSession | no |
| 3 | 4780 | Anime4K | yes |
| 3 | 1385 | LimitPreLoadIOContext | yes |
| 3 | 1029 | LimitSeparatePreLoadIOContext | yes |
| 3 | 1071 | VideoSwresample | yes |
| 3 | 199 | KSSlider | yes |
| 2 | 1391 | HLSCacheIOContext | yes |
| 2 | 1055 | MetalShaderExporter | no |
| 1 each | — | AudioSwresample, CustomProgressView, FFmpegDecode, PlayerToolBar | mixed |

7. Note the `has source file` column and do not let it mislead you. **A source file next to a unit is
   not a counterpart.** `IOSVideoPlayerView` has one; its source declares `customizeUIComponents`,
   `resetPlayer`, `onButtonPressed`, `updateUI`, `panGestureBegan`, and its binary declares
   `setupBottomControls`, `handleScreenshot`, `generateFFmpegMenu`, `getVideoMeta`,
   `updateBatteryStatusImageView` — **zero overlap**. Forward replaced the class's whole UI layer.
   Session 86 split the waves on *does the class have a source file* and had to redo it; the
   predicate that decides auditability is *is the METHOD declared in that class's own source scope*.

## 3. What you are producing, and what it does NOT do

8. A stand-up verdict is written to `reconstruction/verdicts/<id>.json` with, at minimum: `recovered`
   (extent, arity, dispatch, ICF-fold status, field touches, call set, literals, source file/line),
   `unrecovered` (REQUIRED, never empty by default), `class_facts`, `no_counterpart_reason`,
   `decompile_cache`, `source_lines: null`, and an EMPTY `divergences`.
9. Set the verdict only through `python3 scripts/adjudicate_verdict.py --final STOOD_UP`. It REFUSES
   a STOOD_UP that carries `source_lines` or `divergences` — both assert a comparison, and there is
   nothing to compare.

**A stand-up moves the faithful floor by ZERO, by design.** `aggregate_verdicts` counts STOOD_UP in
its own bucket: *a body audited against nothing may not raise the floor.* Expect the floor to end
this session at 328 unless you also do fix-queue work. If you want a progress number, it is the
STOOD_UP count and the wave size — not the floor.

10. Do NOT write Swift source for these bodies this session. The stand-up is the intelligence pass
    that makes a later reconstruction cheap; writing the source is a separate act, and even then the
    body reaches the floor only when it is audited against a verbatim decompile and adjudicated
    FAITHFUL. Fixing source and flipping a verdict are two acts.

## 4. The failure mode that cost session 98 twice

11. **Before concluding any member is absent, grep the demangled export trie — a source-side grep
    proves nothing.** Session 98 twice declared a member nonexistent on a `Sources/` grep when the
    trie had it, and one of those defects was LANDED (it reached into a private array and widened it,
    where `SubtitleModel.addSubtitle(dataSource:)` existed with a method descriptor). Both compiled,
    built 4/4 and passed every gate. See `memory/member-absent-check-trie-not-source.md`.
12. A hand-built mangled symbol is not a search. `$s8KSPlayer13KSPlayerLayerC6change…` reads
    NOT_IN_TRIE while the real symbol is `$s8KSPlayer0A5LayerC6change…` — word substitution hides it.
    Demangle the whole trie once and grep THAT.
13. The mirror error is as easy: having found a member under owner A, do not conclude the source
    misplaced it because a same-named member exists under owner B. Session 98 banked a false
    `audioRecognizes` placement divergence that way and had to retract it.

## 5. Dispatch

14. Parallelise by CLASS, not by unit — one agent per class keeps each agent's context coherent and
    avoids two agents deriving the same `class_facts`. `SettingsView` (43) and `IOSVideoPlayerView`
    (32) should each be split into several agents by unit range.
15. Pre-fetch decompiles before dispatching, with
    `python3 scripts/prefetch_decompiles.py --worklist <file> --out reconstruction/decompiles/`. Its
    worklist shape is `{"units": [{id, address, symbol, file, lines, subsystem, language}, …]}` —
    NOT the module→[type records] shape of `reconstruction/worklist.json`, which is the Phase-0 TYPE
    worklist and a different file. Session 98 lost time to that.
16. Agents derive only: they create no file, touch no git index, run no build, and edit nothing under
    `scripts/`. You re-verify every load-bearing claim against the binary yourself with
    `llvm-objdump` before it enters a verdict (MEMORY rule 5).
17. The per-unit tool set is `STANDUP_PROTOCOL.md` §3: `function_extents.py`, `export_trie_oracle.py`,
    `vtable_walk.py`, `vtable_impl_oracle.py`, `fieldrec.py`, `dump_binary_field_types.py`,
    `decode_string_literal.py`, `decode_int_switch.py`, `decode_string_switch.py`, and
    `recover_swift_function_name.py` for the name checks.
18. When `field_offset_vector.py` refuses a class, that is BY DESIGN for runtime-initialised
    metadata — name every field touch from its exported `…vpWvd` direct-field-offset symbol instead.

## 6. Close out

19. Re-run `python3 scripts/aggregate_verdicts.py` and record the STOOD_UP count and the live wave
    size from `python3 scripts/wave_worklist.py --wave standup`.
20. Update `reconstruction/handoff_baseline.json`: add a `captured_session99` block, and refresh
    `faithful_floor`, `head` and `ahead_origin` if the gate reports them as ANOMALY (it prints
    `progress — update baseline` when it wants this).
21. Run `python3 scripts/handoff_completeness_lint.py <this file>` and then write the session-100
    handoff.
22. Commit on the `forward` branch through `bash scripts/commit_unit.sh -F <msgfile>` and confirm
    HEAD moved — `git commit` exits 0 when the pre-commit hook blocks.

**Durability, worth one line:** `reconstruction/` and `scripts/` are both gitignored in `play`. The
61 existing stand-up verdicts, the 2082 cached decompiles and every tool named above live on this
disk only. Everything this session produces inherits that risk.
