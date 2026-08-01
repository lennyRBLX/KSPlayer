# Session 90 work

Session 89 stood up **11 bodies**, completing `KSVideoPlayerModel` (2/2) and `KSComplexPlayerLayer`
(3/3) and taking `KSAVPlayer` to 6 of 7. `agg_stood_up` 28 -> 39; `wave_standup_size` 147 -> 136.
The faithful floor did not move, and that is by design — a STOOD_UP body is audited against nothing
and may never enter the floor.

Note on filenames: this directory does not sort in session order. **Order by the session number.**

## Verify first

1. Run `ps -Ao pid,etime,command | grep -c "MacOS/claude --output-format stream-json"` FIRST. One
   live session prints **4** lines. Print `ps -Ao pid,ppid,etime,command | grep MacOS/claude` and
   confirm there is no SECOND unrelated parent/child pair before touching `reconstruction/` or
   `forward`. `recon_gate --mode handoff` WRITES `reconstruction/handoff_report.json`, so running it
   IS touching `reconstruction/` and this step gates it.
2. **Before the gate, run `dyld_info -fixups "$BIN"` once and check it exits 0.** See step 6 — two
   selfchecks depend on it and it was being killed at the end of s89. If it exits 0, expect
   `python3 scripts/recon_gate.py --mode handoff` to print **PASS 44 / ANOMALY 0 / FAIL 3**. If it is
   still killed, expect **PASS 42 / ANOMALY 0 / FAIL 5**, the two extra FAILs being `sc_superclass`
   and `sc_witness_table`. Either way floor **299**, `agg_stood_up` **39**, `wave_standup_size`
   **136**, `wave_audit_size` **6**. The 3 permanent FAILs are the unchanged known debt:
   `agg_critical 15`, `agg_high 55`, `agg_unresolved 1`.
3. **The floor HELD at 299 and that is correct.** Thirty-nine bodies are now stood up; none is
   auditable, so none may count toward FAITHFUL.
4. Run `python3 scripts/recon_progress.py`.
5. **The two-repo split.** Swift sources, the `forward` branch and these handoffs live in
   `/Users/jweaver/Desktop/Work/swift/KSPlayer`. The cwd `/Users/jweaver/Desktop/Work/swift/play`
   holds `scripts/` and `reconstruction/`, both gitignored there. Address KSPlayer with `git -C`;
   run every `scripts/` command from `play`. FFmpegKit is a SIBLING of KSPlayer at
   `/Users/jweaver/Desktop/Work/swift/FFmpegKit`, not inside it.
6. Read MEMORY.md before anything else. The PreToolUse hook fired twice in s89 and was right both
   times, on `2>/dev/null` against a possibly-absent path. Rephrase or split; never weaken it.

## SETTLED — do not re-raise

7. **The durability question is CLOSED by user decision.** The tool/verdict layer stays
   **uncommitted**. Do not propose versioning `scripts/`, `docs/` or `reconstruction/` again.
8. **The 3 coverage-audit hits are adjudicated** (`reconstruction/wave_coverage_adjudication_s88.json`).
   s89 re-ran `--coverage-audit standup` and confirmed the output is byte-for-byte the same three
   units with the same slots, addresses and instruction counts. VideoSwresample 29/31 DONE,
   FFmpegDecode slot 18 genuinely OPEN. **Confirm, never re-derive.** The exclusion file of step 26
   below is what actually retires the re-reporting.

## The blocker to clear first

9. **`dyld_info -fixups` was being SIGKILLed on Forward-TF at the end of s89** — exit 137, 0 s, no
   output — while the control `dyld_info -fixups /bin/ls` still exits 0. It dies specifically on the
   88 MB image, consistent with a resource kill (Ghidra holding 191,991 functions plus four
   concurrent agents). No script was edited in s89. Retry it on a fresh machine state; if it works,
   `sc_superclass` and `sc_witness_table` return to PASS on their own.
10. **The latent defect it exposed is the durable finding, and it outlives the blocker.**
    `superclass_conformance_gate._load_binds()` catches EVERY exception and returns an EMPTY dict, so
    a killed `dyld_info` is indistinguishable from "this type has no external conformances".
    `decode_witness_table` delegates to it, so two gates degrade to the same silent false negative.
    It was caught ONLY because both selfchecks carry known-answer controls (Anime4KError wants 2).
    **Fix it: make `_load_binds()` distinguish `resolution failed` from `no binds`, and make callers
    REFUSE rather than report zero. Do NOT weaken the selfcheck to accommodate it** (MEMORY rule 8).
    This is the same failure shape as the s88 `field_offset_vector` defect — a tool returning a
    confident, entirely fictional empty answer.

## What s89 landed

11. **Eleven bodies, all STOOD_UP, all adjudicated, `verdict_provenance_gate --class` OK on all three
    touched classes.** `KSVideoPlayerModel` slots 37, 38. `KSComplexPlayerLayer` slots 10, 11, 12.
    `KSAVPlayer` slots 93, 96, 97, 98, 99, 102. Verdicts in `reconstruction/verdicts/*_s89.json`.
12. **Four agents, one body each for the four largest units (167/139/130/128 instr), ALL returned
    `UNGROUNDED: 0`.** Every load-bearing claim was re-verified against the binary by the orchestrator
    before it entered a verdict.

## The method — the session's main reusable output

13. **For a `metadata_init=1` class, name fields by SYMBOL, not by offset.** Step 14 of the s89
    handoff was confirmed on all four target classes: `field_offset_vector.py` refuses them. It goes
    deeper than "runtime-initialized" — the offset globals are in a ZERO-FILL region, and
    `field_offset_vector`'s own reader returns `unreadable VA 0x104c63068 (outside every
    LC_SEGMENT_64)`. Those words have **no static value in the file at all**.
    But the same runtime addressing makes most field access SYMBOLIC: a touch compiles to
    `adrp`+`ldr` against an exported `...vpWvd` word, and
    `python3 scripts/export_trie_oracle.py --addr <that word>` returns e.g.
    `direct field offset for KSPlayer.KSAVPlayer.delegate : KSPlayer.MediaPlayerDelegate?` — naming
    the field, its OWNING TYPE and its DECLARED TYPE. That is strictly better than a number, and it
    reaches fields on OTHER classes reached through the first. **The anchor-site budget step 22 asked
    for was mostly not needed.**
14. **But the orchestrator refuted its own generalisation, and this is the part to carry forward.**
    `metadata_init=1` does NOT imply every access is symbolic. `KSAVPlayer.playerView` is read at the
    CONSTANT immediate `self+0x38` (found independently in slots 98 and 102), and `mediaPlayerTracks`
    goes through an UNEXPORTED global `0x1044e46f8`. KSAVPlayer exports exactly **18** `vpWvd` globals
    for **28** fields. So constant-offset and unexported-global sites still need anchor-site recovery;
    the `vpWvd` route is a naming technique, not a guarantee.
15. **Exclusivity flags are a deterministic read/write discriminator.** `swift_beginAccess`'s third
    argument reads **0** for a read, **1** for an untracked modify, **0x21** (Modify|Tracking) for a
    tracked modify — and only the `0x21` site carries a matching `swift_endAccess`. Consistent across
    all eleven bodies.
16. **Enum raw values ARE readable — pass the DESCRIPTOR ADDRESS, not `--class`.**
    `fieldrec.py --class MediaLoadState --module KSPlayer` fails with `no classmap row` because the
    classmap carries no enums (step 30 below), but `fieldrec.py 0x1039ed988` works and bypasses the
    classmap entirely: `idle/loading/playable`. Likewise `0x1039ed96c` -> MediaPlaybackState (6 cases)
    and `0x1039edf0c` -> LogLevel (8 cases). Get the descriptor from the trie via the enum's `...OMn`
    symbol. This retired an unrecovered item mid-session.
17. **`weak` IS reflection-visible** — the field-record type tail `Xw` encodes it
    (`KSAVPlayer.delegate` = `_pSgXw`), agreeing with the `_swift_unknownObjectWeakLoadStrong` call
    the body makes. The `iuo-not-reflection-visible` memory covers `T!` vs `T?`, **not** weak. An
    earlier draft in s89 claimed otherwise and was corrected.
18. **An exported accessor symbol is NOT evidence that an accessor body exists.**
    `KSComplexPlayerLayer`'s `isPictureInPictureStoped` and `enterBackgroundTask` getters and setters
    ALL resolve to one address `0x10198eb18`, whose entire 4-instruction body is a
    `_swift_deletedMethodError` trap, ICF-folded. Such a symbol yields no offset and no behaviour.
19. **The `zpl` false anchor is SYSTEMATIC, not a one-off.** `recover_swift_function_name.py` returned
    `#function: zpl (confidence=medium, labels=0)` anchored on `0x103566c60` for THREE different
    unnamed callees (`0x101a03fd4`, `0x1019a26a8`, `0x1019c80fc`). It is disproved positively:
    `name_type_at_addr` shows `0x103566c60` is the type mangle `ScPSg` (= `Swift.TaskPriority?`),
    whose raw bytes `7a706c00` merely spell "zpl". All three were rejected. The tool's TRUE anchor on
    KSAVPlayer slot 97 (`labels=2`, counts match) was accepted — **the s88 discriminator separates
    them cleanly and should now be trusted.**
20. **Handoff step 36 reproduced on a concrete unit.** `vtable_walk` idx93 is `vtable_impl_oracle`
    `slot131` (index + VTableOffset 38), and impl_oracle's own `slot93` is a DIFFERENT entry (idx55,
    a Getter). Anyone joining the two tools on the string "slot" mismatches by `VTableOffset`.

## Body-level premises the names would have got wrong

21. `KSAVPlayer.reset()` tears down **no resources** — no observer or notification removal, no Combine
    cancel, `delegate` read but never nil-ed, and 16 of 28 stored properties untouched. It is a state
    reset, not a teardown.
22. `KSComplexPlayerLayer.pipStart()` writes **nothing** and never sets `isPictureInPictureStoped`;
    the whole body contains exactly one field-offset `adrp`, and the one field it touches is
    INHERITED (`KSPlayerLayer.player`).
23. `playNextURL()` does **not wrap around** — it returns when the current url is the last element —
    and passes `options: nil` to the inherited `KSPlayerLayer.set(url:options:)`.
24. `KSAVPlayer.nominalFrameRate(track:)` never touches `self`: `mov x20,x0` destroys swiftself before
    first use. `updatePlaybackBuffer()` messages `isPlaybackBufferEmpty` but its result is DEAD (both
    `csel` arms identical). `readyToPlay()` writes no self state at all and captures self WEAKLY.
25. `KSVideoPlayerModel.next()` dispatches VIRTUALLY to `playNextURL` while `previous()` dispatches
    STATICALLY to an unnamed body — an asymmetry in an apparently symmetric pair.

## Session 90 — continue the STAND-UP wave

26. Regenerate the worklist and its DERIVED presence file in the same breath, never read either blind:
    `python3 scripts/wave_worklist.py --wave standup --json reconstruction/wave_standup.json` then
    `python3 scripts/method_source_presence.py --wave standup --json
    reconstruction/method_presence_standup.json`. Expect **136 units / 26 classes**. Then run
    `--coverage-audit standup` and confirm against step 8.
27. **Finish `KSAVPlayer`: one unit left**, slot 100 `process(error:)` `0x1019a5158`, 81 instr, NAMED.
    Cheap, and it completes a third class.
28. **Then `KSPlayerLayer`, 12 units / 1355 instr, all NAMED, all binary-only (s86).** Slots 53, 56,
    57, 58, 59, 62, 73, 75, 76, 77, 80, 81. Two are already pinned by s89 work: slot 75
    `playerDidClear` `0x1019ceaf4` is the target `KSAVPlayer.reset()` calls, and slot 81 is
    `replaceAndConstrainPlayerView`. It has NO exported metadata symbol, so the offset resolver
    refuses it — use the step-13 route and expect step-14 exceptions.
29. **Before briefing any UNNAMED unit, run `recover_swift_function_name.py` on it yourself** and
    apply the step-19 discriminator. The 70 UNNAMED units are where this pays; `SettingsView` alone is
    43 of them.
30. **Batch by CLASS; one body per agent for large bodies, derive small ones yourself.** The s89 split
    was: orchestrator direct for 12-96 instr, one agent each for 128-167 instr. Hold every agent to
    `reconstruction/STANDUP_PROTOCOL.md`. Its §1 still quotes the s87-era "175 stand-up units ... 102
    BINARY_ONLY"; the contract is unaffected but the number is stale — fix it when no agent is in
    flight (MEMORY rule 7).
31. **Give every agent the step-13 vpWvd technique in its brief.** All four s89 agents used it and all
    four returned `UNGROUNDED: 0`. Also give them step 14, so they do not over-generalise it.

## Open work, unchanged or sharpened

32. **The coverage-audit adjudication still has nowhere to land.** Build an explicit
    adjudicated-exclusion file that `wave_worklist` reads, with a selfcheck asserting every entry
    still resolves to a real verdict FIELD. **Never a greedy free-text address scan** — that would
    drop 5 LIVE units via `bounds` mentions, the s87 defect.
33. **Extend the classmap to structs and enums** (step 16 makes this concrete): the descriptor-address
    workaround works, but `--class` failing on every enum is a trap each session rediscovers.
34. `SettingsView` is 43 units / 9880 instr, all UNNAMED; `IOSVideoPlayerView` is 32 / 9122, all NAMED
    with zero source overlap. Together ~55% of the remaining wave. Leave both until the cheap NAMED
    classes are exhausted — but see step 29.
35. Budget `Anime4K` 3 units / 4780 instr, `ThumbnailSession` 4 / 5198 and `PreLoadIOContext` 7 / 3391
    like ten ordinary bodies each.
36. `VideoToolboxDecode` slot 29 `decodeFrame(from:completionHandler:)` @`0x101a6ce44` (572 instr) is
    the only genuinely open AUDIT unit — an explicit `deferred_to_P3` DV-crux body. Do not take it as
    a warm-up.
37. **Unnamed callees worth naming, all pinned by s89 verdicts:** `0x1019d3518` (94 instr, the body
    `KSVideoPlayerModel.previous()` calls, stack-allocates a URL exactly as `playNextURL` does),
    `0x1019c835c` (49 instr, an `Optional<Int>` search over `[URL]`), `0x1019a24a8` (128 instr, the
    `playbackState` observer), `0x1019a26a8` (107 instr, a `KSPlayer/Utility.swift` helper called
    twice from slot 97), `0x1019c7a8c` (68 instr, a COW array append). Each has its failing checks
    recorded in its verdict's `unrecovered`.
38. **One unnamed FIELD is pinned and worth an anchor site:** the offset global `0x104c63520`, a Bool
    written `true` by `playNextURL`. Positional inference across neighbouring globals was tested and
    REFUTED (`0x104c63538` is `KSVideoPlayer.Coordinator.playerLayer`, a third type interleaved), so
    it needs a body whose field is independently known.
39. `vtable_walk.py` resolves a bare class NAME to the FIRST classmap row, wrong across a cross-module
    collision. Take a module, prefer KSPlayer, ERROR on ambiguity — `fieldrec.desc_for_class` already
    implements that contract. Fold in the step-20 numbering fix at the same time.
40. `decode_string_literal.py` misses computed counts and the `_StringObject` bias direction.
41. `l2_field_gate`'s `merge_binary_type` should fall back to the trie's `.setter`/`.getter` type when
    there is no mangled property symbol. 11 REAL_FLAGs + 7 UNCHECKED on KSPlayerLayer wait on it — but
    the 205 unannotated stored properties (25.5% of 803, across 33 classes) are bigger.
42. Fix queue, coupled — **build both before staging either**: `KSPlayerLayer.seek(time:)` (`:601`)
    and `VideoPlayerView.change(definitionIndex:)` (`:371-373`). Re-derive the slot-64 claim first.
43. `Coordinator.player(layer:currentTime:totalTime:)`, the `startRecord` CRITICAL, **A · KSOptions**,
    the `T!` vs `T?` normalizer, Package F init bodies, MetalPlayView/`Drawable`, `PixelBufferProtocol`'s
    40 requirements, and `Anime4KPreset`'s 11 undecoded shader-path arrays are unchanged. See the s84
    and s89 handoffs.

## What NOT to wave, in any session

44. **Source edits.** The pre-commit `l2_field_gate` blocks on the CLASS, not on your diff, so two
    "independent" edits in one file serialise anyway. Land derivations as specs during the wave, then
    apply them one unit and one commit at a time.
45. **Class-shape changes that ripple to consumers** (DisplayModel's `(frame:encoder:)` arity,
    VideoPlayerView's stored-property set, FFmpegDecode's signature). Single-threaded.
46. `GENERATED_ACCESSOR` (322 slots) is not a candidate at all: it collapses into declarations.

## Close out

47. Adjudicate every body with `adjudicate_verdict.py` (never delete `binary_addr` to pass the
    provenance guard). Its guard requires a `decompile_cache` block with `verbatim: true`, and
    `verdict_provenance_gate.py` additionally requires the prefetch sidecar to EXIST on disk — so run
    `prefetch_decompiles.py` for each unit even when you read the body from the disassembler. s89 did
    this once for all 24 planned units in a single run against a small hand-built worklist
    (`reconstruction/s89_standup_units.json`, id = `<Class>_<addr-no-0x>`), which is the cheap way.
    Do not hand-annotate that cache (P27). Run `verdict_provenance_gate.py --class <C>` on every class
    you touch.
48. Update `reconstruction/handoff_baseline.json` with a `captured_session90` block and refresh `head`,
    `ahead_origin`, `faithful_floor`, `stood_up_floor`, `wave_standup_size` and `wave_audit_size`.
    **Re-run `recon_gate --mode handoff` AFTER updating the baseline.** Take `ahead_origin` from
    `git rev-list --count origin/forward..forward`.
49. Record how many bodies landed, the verdict split, and every premise refuted — the refutations have
    been the highest-value output of the last twenty sessions, above the code. Then write the
    session-91 handoff from the FINAL state, not by patching a mid-session draft. **Do not write the
    takeover prompt into it — give the prompt in chat.**
