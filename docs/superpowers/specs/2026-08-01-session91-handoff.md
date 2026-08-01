# Session 91 work

Session 90 stood up **7 bodies**, completing `KSAVPlayer` (slot 100) and taking `KSPlayerLayer` to 6 of
12. `agg_stood_up` 39 -> 46; `wave_standup_size` 136 -> 129 (25 classes). The faithful floor did not
move, and that is by design — a STOOD_UP body is audited against nothing and may never enter the floor.
It also cleared the s89 `dyld_info` blocker, refuted its diagnosis, and fixed the silent-empty defect.

Note on filenames: this directory does not sort in session order. **Order by the session number.**

## Verify first

1. Run `ps -Ao pid,etime,command | grep -c "MacOS/claude --output-format stream-json"` FIRST. One
   live session prints **4** lines. Print `ps -Ao pid,ppid,etime,command | grep MacOS/claude` and
   confirm there is no SECOND unrelated parent/child pair before touching `reconstruction/` or
   `forward`. `recon_gate --mode handoff` WRITES `reconstruction/handoff_report.json`, so running it
   IS touching `reconstruction/` and this step gates it.
2. Expect `python3 scripts/recon_gate.py --mode handoff` to print **PASS 44 / ANOMALY 0 / FAIL 3**,
   floor **299**, `agg_stood_up` **46**, `wave_standup_size` **129**, `wave_audit_size` **6**. The 3
   permanent FAILs are the unchanged known debt: `agg_critical 15`, `agg_high 55`, `agg_unresolved 1`.
3. **The floor HELD at 299 and that is correct.** Forty-six bodies are now stood up; none is
   auditable, so none may count toward FAITHFUL.
4. Run `python3 scripts/recon_progress.py`.
5. **The two-repo split.** Swift sources, the `forward` branch and these handoffs live in
   `/Users/jweaver/Desktop/Work/swift/KSPlayer`. The cwd `/Users/jweaver/Desktop/Work/swift/play`
   holds `scripts/` and `reconstruction/`, both gitignored there. Address KSPlayer with `git -C`;
   run every `scripts/` command from `play`. FFmpegKit is a SIBLING of KSPlayer at
   `/Users/jweaver/Desktop/Work/swift/FFmpegKit`, not inside it.
6. Read MEMORY.md before anything else. The PreToolUse hook fired three times in s90 and was right
   every time — on `timeout`, on a bare `llvm-objdump` inside a heredoc comment, and on an unquoted
   heredoc. Rephrase or split; never weaken it.

## SETTLED — do not re-raise

7. **The durability question is CLOSED by user decision.** The tool/verdict layer stays
   **uncommitted**. Do not propose versioning `scripts/`, `docs/` or `reconstruction/` again.
8. **The 3 coverage-audit hits are adjudicated** (`reconstruction/wave_coverage_adjudication_s88.json`).
   s90 re-ran `--coverage-audit standup` and confirmed the output is byte-for-byte the same three
   units with the same slots, addresses and instruction counts. VideoSwresample 29/31 DONE,
   FFmpegDecode slot 18 genuinely OPEN. **Confirm, never re-derive.**
9. **The `dyld_info` blocker is CLOSED and its s89 diagnosis is REFUTED.** It was never resource
   pressure. It dies at 0.00 s user + 0.00 s system in 15 ms, and `cmp(1)` and python's `mmap` die
   identically, while `read(2)` succeeds for all of them. The trigger is **`mmap()` of that path**.
   `_load_binds` now falls back to a SHA-256-verified byte-identical copy and re-verifies the hash on
   every use. Do not re-diagnose this.

## The blocker to clear first

10. **`body_fingerprint.py` FABRICATES a field touch, and that tool's GLOBALS list has been the
    field-naming route since s80.** Confirmed against the binary in s90: for `KSPlayerLayer` slot 56
    it reports `0x104c63300 direct field offset for KSPlayer.KSOptions.outputURL`, a field the body
    never touches. It paired the STALE `adrp x8, 0x104c63000` at `0x1019cbb94` with the
    `ldr x8, [x8, #0x300]` at `0x1019cbc60` — but x8 is reloaded as the object's isa
    (`ldr x8, [x23]` at `0x1019cbc4c`) and masked (`and x8, x9, x8` at `0x1019cbc5c`), so `#0x300`
    is a CLASS VTABLE dispatch, not a field offset. **Fix: invalidate the adrp/register pairing when
    the register is redefined between the `adrp` and the `ldr`.** Same failure family as the s88
    `field_offset_vector` defect and the s89 `_load_binds` defect. Write the golden on slot 56 —
    it is a known-answer case — and then run the fixed tool on every reconstructed class (MEMORY
    rule 10) before trusting one result.
11. **Then re-check the verdict corpus for contamination.** Any verdict that took a GLOBALS entry
    without reading the `adrp`/`ldr` pair out of the disassembly may name a field the body never
    touches. s90's own seven were checked pair-by-pair and are clean; earlier sessions were not.

## Also open on the tools

12. **`field_offset_vector.py` refuses for a FALSE reason.** It builds `$s8KSPlayer13KSPlayerLayerCN`
    without module-name word substitution; the real symbol `$s8KSPlayer0A5LayerCN` exists at
    `0x1044218b0`. The refusal is still the CORRECT outcome (`metadata_init=1` means no static
    offsets exist), but the message misinforms and the check would misfire wherever the substitution
    differs. Fix the mangle construction, keep the refusal.
13. **`decode_witness_table.py --wt` CRASHES on a cross-module conformer.** `--wt 0x104182678`
    (`Components.PlayerViewModel`) dies with an unhandled `read_mem` failure inside `_name_at`.
    Make it refuse with a message rather than raise — the s90 fix already established that a failed
    resolution must be distinguishable from an empty answer.

## What s90 landed

14. **Seven bodies, all STOOD_UP, all adjudicated, `verdict_provenance_gate --class` OK on both
    touched classes.** `KSAVPlayer` slot 100. `KSPlayerLayer` slots 53, 56, 57, 59, 75, 80. Verdicts
    in `reconstruction/verdicts/*_s90.json`.
15. **Four agents, one body each for the four largest units (226/208/191/177 instr), ALL returned
    `UNGROUNDED: 0`.** Every load-bearing claim was re-verified against the binary by the orchestrator
    before it entered a verdict — including reading the raw witness words out of memory rather than
    trusting an agent's own inline Mach-O walk.
16. **The step-10 fix in full.** `_load_binds()` had FOUR silent-empty paths; the live one was that
    `subprocess.run` WITHOUT `check=True` returns exit 137 with empty stdout and **raises nothing**.
    It now raises `BindResolutionError` on a failed resolution (memoized as an error, never as `{}`)
    and returns `{}` only for a genuine no-binds image. Both callers refuse. A 3-part control was
    ADDED and MUTATION-TESTED: restoring the pre-fix `_load_binds` makes the selfcheck FAIL.
    **Blast radius measured: 636 conformances silently dropped across 347 of 1064 classes.**
17. **Two candidate fixes were REJECTED on evidence, and both rejections are reusable.** The
    disassembler's `--bind` table works on the real path but MISSES 377 slots including 9 protocol
    descriptors (`AsyncIteratorProtocol`, `AsyncSequence`) — it would have reintroduced the same class
    of false negative. And a per-slot refusal broke the documented s53 two-part validity filter on 63
    legitimate non-conformance xrefs. **The correct discriminator is bind-table membership, and it is
    sound ONLY BECAUSE `_load_binds` now refuses** — under a silently-empty table "absent" means
    nothing.

## The method — what to carry forward

18. **The step-13 vpWvd technique held up across all seven bodies** and reached fields on OTHER
    classes through the first (`MEPlayerItem.options`, `KSOptions.dynamicRange`,
    `MetalSubtitleView.dynamicRange`, `SubtitleModel.selectedSubtitleInfo`). Keep briefing it.
19. **And its step-14 limit fired twice more.** `KSOptions.isAutoPlay` is read at the CONSTANT
    immediate `KSOptions+0x45` and was recovered only by ANCHOR SITE (the class's own trie-named
    getter at `0x1019b4c00` uses the identical `add x0, x20, #0x45`); and `MEPlayerItem`'s field at
    offset global `0x104c636b8` exports NO symbol and was named `io` by TYPE instead. Brief both.
20. **`vtable_walk` idx N = `vtable_impl_oracle` slot N+VTableOffset, again.** KSPlayerLayer's
    VTableOffset is 27, so idx56/57/59/80 are impl-oracle slot83/84/86/107. Never join the two tools
    on the string "slot".
21. **The `zpl` false anchor now has a CAUSE, not just a disproof.** `0x103566c60` is the
    `Swift.TaskPriority?` mangle that EVERY `Task { }` creation site references, which is why
    `recover_swift_function_name.py` keeps anchoring unrelated Task-creating bodies to it. It fired a
    fourth time in s90 on `0x101a03fd4`. Reject on `labels=0`; a true anchor has labels>=2.
22. **A `#function` discriminator is a FILE discriminator.** `33_B3181C2628785004269C41BC3433122FLL`
    appears on BOTH `KSPlayerLayer` and `KSComplexPlayerLayer` symbols, so it does not distinguish
    `private` from `fileprivate`, and it does not imply direct dispatch — slot 80 is discriminated-
    private AND occupies vtable idx80 AND is reached by six direct `bl` sites.
23. **An `AsyncFunctionPointer` makes a `Task { }` closure recoverable.** A `Task` operation argument
    that `name_type_at_addr` reports as `category: unmapped` is the pair {rel32 to the async body,
    uint32 ExpectedContextSize}. Slot 100's `0x103566c80` resolved to `0x1019b2128` with context size
    0x20; do not record such a closure as unrecovered without trying this.

## Body-level premises the names would have got wrong

24. `KSAVPlayer.process(error:)` processes **nothing** — it never writes `KSAVPlayer.error` (field
    record 20) and touches no stored property in its own extent. It is a `Task { @MainActor }` hop
    with weak self that hands the error to the delegate.
25. `KSPlayerLayer.playerDidClear(player:)` **DISCARDS its `player`** — the 3-instruction thunk
    overwrites x0 with x1, the target never reads x0/x1 at entry, and what reaches the delegate is
    `mov x0, x20`, THE LAYER.
26. `makeUIView()` **makes nothing** — a pure read-through to `player.view`, with no nil check.
27. `changePlaybackTime(player:time:)` **changes no time**, and never touches the class's OWN
    `player` property — the generic parameter shadows it completely.
28. `replace(playerItem:)` writes `self.url` **only** on the `Either.left(URL)` case, and drives
    `state` only to `.initialized`; its slot-56 sibling writes `.initialized` AND `.preparing`.
29. `addSubtitle(to:)` **adds nothing** when `subtitleView.superview` is already the target — it
    brings the view to front and returns, but it notifies the delegate on BOTH paths.

## Session 91 — continue the STAND-UP wave

30. Regenerate the worklist and its DERIVED presence file in the same breath, never read either blind:
    `python3 scripts/wave_worklist.py --wave standup --json reconstruction/wave_standup.json` then
    `python3 scripts/method_source_presence.py --wave standup --json
    reconstruction/method_presence_standup.json`. Expect **129 units / 25 classes**.
31. **Finish `KSPlayerLayer`: six units left**, all NAMED — slots 58 `change(state:)` `0x1019cc0ac`
    (115 instr), 62 `reset()` `0x1019ccbc0` (70), 73 `reachEndOfStream(player:)` `0x1019ce750` (32),
    76 `select(subtitleInfo:isSecondary:)` `0x1019ceb00` (133), 77 `pipStop(restoreUserInterface:)`
    `0x1019ced14` (46), 81 `replaceAndConstrainPlayerView(player:replacing:)` `0x1019cf8d4` (122).
32. **Partial derivations already on disk for four of them, re-verify before use:** slot 73 reads
    `delegate` (`0x1044e6138`) weakly and dispatches a `KSPlayerLayerDelegate` witness — it is the
    same 32-instr/128-B shape as slot 75's target `0x1019d58f8` but a DISTINCT address, and identity
    was NOT proven. Slot 62 touches `subtitleModel` (`0x104c63500`),
    `SubtitleModel.selectedSubtitleInfo` (`0x104c637f0`) and `player` (`0x104c634f0`), calls
    `_swift_getKeyPath` twice and the Combine `Published` enclosing-instance subscript. Slot 77
    touches `player` and dispatches witness offsets 0x48 and 0xf8 — **read the ORDER from the
    disassembly**, because 0xf8 is `pipController.getter` and a dispatch on THAT existential is not a
    `MediaPlayerProtocol` offset.
33. **MediaPlayerProtocol witness offsets already named** (witnesses start at `wt+0x08`, so
    `offset = 8 + 8*index`): 0x28 = req4 `view.getter` (an ICF fold of 2 symbols — pass `--owner`),
    0x48 = req8 `playbackState.getter`, 0x50 = req9 `loadState.getter`, 0x58 = req10
    `isPlaying.getter`. `KSPlayerLayerDelegate` has 11 requirements; 0x50 = req9
    `playerDidAddSubtitle`, and Coordinator parks req5..req10 on the folded empty default
    `0x10000e52c`.
34. **Before briefing any UNNAMED unit, run `recover_swift_function_name.py` on it yourself** and
    apply the step-21 discriminator. The 70 UNNAMED units are where this pays; `SettingsView` alone is
    43 of them.
35. **Batch by CLASS; one body per agent for large bodies, derive small ones yourself.** The s90 split
    was: orchestrator direct for 3-32 instr, one agent each for 177-226 instr. Hold every agent to
    `reconstruction/STANDUP_PROTOCOL.md`. Its §1 still quotes the s87-era "175 stand-up units ... 102
    BINARY_ONLY"; the contract is unaffected but the number is stale — fix it when no agent is in
    flight (MEMORY rule 7).
36. **Give every agent the step-18 vpWvd technique AND the step-19 limit.** All four s90 agents used
    both and all four returned `UNGROUNDED: 0`.

## Open work, unchanged or sharpened

37. **Handoff step 38's unnamed field is nearly closed.** The offset global `0x104c63520` is written
    by slot 56 with `options.isAutoPlay`. Only `isAutoPlay` and `isWirelessRouteActive` lack a
    `vpWvd`; `isAutoPlay`'s `vg`/`vs`/`vM` all ICF-fold onto the deleted-method trap `0x10198eb18`;
    and the POSITIONAL route is REFUTED (`0x104c63508` is field 17
    `isAutoReplaceAndConstrainPlayerView`, BELOW `0x520`). Strong reasoned identification =
    `isAutoPlay`. To PROVE it, find a body that writes `0x104c63520` alongside a second, named field
    whose declaration order is known.
38. **Two unnamed KSPlayerLayer-local helpers are now pinned by three verdicts each:** `0x1019c9a68`
    (336 B, 84 instr) and `0x1019c9cd4` (1188 B, 297 instr, `#file KSPlayer/KSPlayerLayer.swift`).
    Neither is a vtable Impl and neither is a branch thunk. `0x1019c9cd4` takes a Bool-shaped w0 and
    is called from slots 56, 57 and 59 — naming it would close three `unrecovered` entries at once.
39. **The coverage-audit adjudication still has nowhere to land.** Build an explicit
    adjudicated-exclusion file that `wave_worklist` reads, with a selfcheck asserting every entry
    still resolves to a real verdict FIELD. **Never a greedy free-text address scan** — that would
    drop 5 LIVE units via `bounds` mentions, the s87 defect.
40. **Extend the classmap to structs and enums.** The descriptor-address workaround
    (`fieldrec.py 0x1039ecea0`) works and was used five times in s90, but `--class` failing on every
    enum is a trap each session rediscovers.
41. `SettingsView` is 43 units / 9880 instr, all UNNAMED; `IOSVideoPlayerView` is 32 / 9122, all NAMED
    with zero source overlap. Together ~58% of the remaining wave. Leave both until the cheap NAMED
    classes are exhausted — but see step 34.
42. Budget `Anime4K` 3 units / 4780 instr, `ThumbnailSession` 4 / 5198 and `PreLoadIOContext` 7 / 3391
    like ten ordinary bodies each.
43. `VideoToolboxDecode` slot 29 `decodeFrame(from:completionHandler:)` @`0x101a6ce44` (572 instr) is
    the only genuinely open AUDIT unit — an explicit `deferred_to_P3` DV-crux body. Do not take it as
    a warm-up.
44. `vtable_walk.py` resolves a bare class NAME to the FIRST classmap row, wrong across a cross-module
    collision. Take a module, prefer KSPlayer, ERROR on ambiguity — `fieldrec.desc_for_class` already
    implements that contract. Fold in the step-20 numbering fix at the same time.
45. `decode_string_literal.py` misses computed counts and the `_StringObject` bias direction.
46. `l2_field_gate`'s `merge_binary_type` should fall back to the trie's `.setter`/`.getter` type when
    there is no mangled property symbol. 11 REAL_FLAGs + 7 UNCHECKED on KSPlayerLayer wait on it — but
    the 205 unannotated stored properties (25.5% of 803, across 33 classes) are bigger.
47. Fix queue, coupled — **build both before staging either**: `KSPlayerLayer.seek(time:)` (`:601`)
    and `VideoPlayerView.change(definitionIndex:)` (`:371-373`). Re-derive the slot-64 claim first.
48. `Coordinator.player(layer:currentTime:totalTime:)` is now PINNED by slot 59: it is
    `KSPlayerLayerDelegate` requirement 1, reached at witness offset 0x10, thunking to `0x1019db8e8`.
    The `startRecord` CRITICAL, **A · KSOptions**, the `T!` vs `T?` normalizer, Package F init bodies,
    MetalPlayView/`Drawable`, `PixelBufferProtocol`'s 40 requirements, and `Anime4KPreset`'s 11
    undecoded shader-path arrays are unchanged. See the s84 and s89 handoffs.

## What NOT to wave, in any session

49. **Source edits.** The pre-commit `l2_field_gate` blocks on the CLASS, not on your diff, so two
    "independent" edits in one file serialise anyway. Land derivations as specs during the wave, then
    apply them one unit and one commit at a time.
50. **Class-shape changes that ripple to consumers** (DisplayModel's `(frame:encoder:)` arity,
    VideoPlayerView's stored-property set, FFmpegDecode's signature). Single-threaded.
51. `GENERATED_ACCESSOR` (322 slots) is not a candidate at all: it collapses into declarations.

## Close out

52. Adjudicate every body with `adjudicate_verdict.py` (never delete `binary_addr` to pass the
    provenance guard). Its guard requires a `decompile_cache` block with `verbatim: true`, and
    `verdict_provenance_gate.py` additionally requires the prefetch sidecar to EXIST on disk — so run
    `prefetch_decompiles.py` for each unit even when you read the body from the disassembler. s90 did
    this once for all 13 planned units in a single run against a small hand-built worklist
    (`reconstruction/s90_standup_units.json`, id = `<Class>_<addr-no-0x>`), which is the cheap way.
    Do not hand-annotate that cache (P27). Run `verdict_provenance_gate.py --class <C>` on every class
    you touch.
53. Update `reconstruction/handoff_baseline.json` with a `captured_session91` block and refresh `head`,
    `ahead_origin`, `faithful_floor`, `stood_up_floor`, `wave_standup_size` and `wave_audit_size`.
    **Re-run `recon_gate --mode handoff` AFTER updating the baseline.** Take `ahead_origin` from
    `git rev-list --count origin/forward..forward`.
54. Record how many bodies landed, the verdict split, and every premise refuted — the refutations have
    been the highest-value output of the last twenty sessions, above the code. Then write the
    session-92 handoff from the FINAL state, not by patching a mid-session draft. **Do not write the
    takeover prompt into it — give the prompt in chat.**
