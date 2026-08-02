# Session 93 work

Session 92 **cleared step 31** — the `body_fingerprint` blind spot — and found that clearing it
exposed a *fourth* defect in the same tool, which was measured and fixed in the same session. It
then stood up **3 bodies**: `KSSlider` idx15/idx16 orchestrator-direct, and `PixelBuffer` idx35 by
agent, which **completes that class**. `agg_stood_up` 52 -> 55; `wave_standup_size` 123 -> 120
(24 -> 23 classes). The faithful floor did not move, by design.

**The single most valuable thing in this handoff is step 23** — a fully derived divergence that is
deliberately NOT recorded as one, and the reason why.

Note on filenames: this directory does not sort in session order. **Order by the session number.**

## Verify first

1. Run `ps -Ao pid,etime,command | grep -c "MacOS/claude --output-format stream-json"` FIRST. One
   live session prints **4** lines. Print `ps -Ao pid,ppid,etime,command | grep MacOS/claude` and
   confirm there is no SECOND unrelated parent/child pair before touching `reconstruction/` or
   `forward`. `recon_gate --mode handoff` WRITES `reconstruction/handoff_report.json`, so running it
   IS touching `reconstruction/` and this step gates it.
2. Expect `python3 scripts/recon_gate.py --mode handoff` to print **PASS 46 / ANOMALY 0 / FAIL 3**,
   floor **299**, `agg_stood_up` **55**, `wave_standup_size` **120**, `wave_audit_size` **6**,
   `git_head` **fc37388**, `git_ahead_origin` **301**. The 3 permanent FAILs are the unchanged known
   debt: `agg_critical 15`, `agg_high 55`, `agg_unresolved 1`.
3. **The floor HELD at 299 and that is correct.** Fifty-five bodies are stood up; none is auditable,
   so none may count toward FAITHFUL.
4. Run `python3 scripts/recon_progress.py`.
5. **The two-repo split.** Swift sources, the `forward` branch and these handoffs live in
   `/Users/jweaver/Desktop/Work/swift/KSPlayer`. The cwd `/Users/jweaver/Desktop/Work/swift/play`
   holds `scripts/` and `reconstruction/`, both gitignored there. Address KSPlayer with `git -C`;
   run every `scripts/` command from `play`. FFmpegKit is a SIBLING of KSPlayer at
   `/Users/jweaver/Desktop/Work/swift/FFmpegKit`, not inside it.
6. Read MEMORY.md before anything else. The PreToolUse hook fired once in s92 and was right: on a
   `timeout 900 python3 …`. It bans `timeout` outright. Rephrase or split; never weaken it.

## SETTLED — do not re-raise

7. **The durability question is CLOSED by user decision.** The tool/verdict layer stays
   **uncommitted**. Do not propose versioning `scripts/`, `docs/` or `reconstruction/` again. This is
   why s92 produced NO commit and why `head`/`ahead_origin` are unchanged.
8. **The 3 coverage-audit hits are adjudicated** (`reconstruction/wave_coverage_adjudication_s88.json`).
   VideoSwresample 29/31 DONE, FFmpegDecode slot 18 genuinely OPEN. **Confirm, never re-derive.**
9. **The `dyld_info` blocker is CLOSED and its s89 diagnosis is REFUTED.** Do not re-diagnose.
10. **`body_fingerprint` is DONE — all four defects, closed, goldened and measured.** Two
    fabrications (s91), one silent under-count and one allocation-return fabrication (s92). Details
    below because they are the session's substance, but **do not re-open, re-diagnose or re-sweep
    any of them.** 15 goldens now run under `sc_body_fingerprint`.
11. **The verdict corpus is CLEAN** (discharged s91). Do not re-sweep.

## What step 31 cost and bought — the numbers to trust

12. **The fix.** `GLOBALS (named)` was named-only: an offset global with no exported symbol was
    dropped **silently**. There is now a separate `GLOBALS (un-named):` block, one row per address
    the body materialises that the trie does not name, **annotated with its Mach-O section**. The
    named block's contents are byte-for-byte unchanged, and the two blocks are a proven PARTITION
    (overlap 0 bodies across all 706 slots).
13. **Why the section, and why it is read from LC_SEGMENT_64.** An un-named global is otherwise
    unclassifiable. `llvm-objdump --section-headers` prints the SECTION name only, and this image has
    **two `__const` sections** — `0x10347b000` in `__TEXT` and `0x104114700` in `__DATA_CONST`. A
    name-keyed reader silently keeps one and mislabels every address in the other, so the section
    table is parsed from the load commands. Zero-fill sections resolve too (`__DATA,__common` holds
    the KSOptions field offsets and has no file bytes).
14. **THE MEASURED BLIND SPOT: 112 of 706 bodies** reported ZERO named globals while materialising an
    address in a field-offset-capable section — their field touches were invisible. 424 bodies gained
    un-named globals; 2417 pairings total. Worst: `IOSVideoPlayerView` 16, `SubtitleModel` 16,
    `SettingsView` 15, `ControllerTimeModel` 9, `KSVideoPlayerModel` 8, `KSPlayerLayer` 7. **Any
    field-touch claim made before s92 on a `metadata_init=1` class deserves re-reading.**
15. **The change exposed a FOURTH defect, and s91's declined refinement was WRONG — for a reason s91
    could not have seen.** s91 declined the caller-saved clobber on a measurement showing 0 affected
    pairings; **that measurement was over the NAMED block.** Re-measured over 706 slots / 4293
    pairings, the broad x0..x17 rule kills 44, **0 of them named**. 43 are ONE shape:
    `adrp x0,PG` / `add x0,x0,#OFF` materialises closure-context metadata, `bl _swift_allocObject`
    **returns a NEW x0**, then `add x0,x0,#0x10` projects the box payload — and the tool read that as
    metadata+0x10. Fictional, 43 times.
16. **Why the shipped rule is `x0` ONLY and not `x0..x17`.** The 44th casualty is NOT a fabrication.
    `ThumbnailSession` slot 26 has `adrp x9` @`0x101a2b130`, then `b.hs 0x101a2b158` @`0x101a2b140`
    jumps **OVER** the intervening `bl _swift_retain` straight to `ldr x20,[x9,#0x2d0]` @`0x101a2b158`
    — the call is not on the path that reaches the use, and `0x1044e52d0` is in `__DATA,__data`, so a
    broad rule DELETES a probable real field touch. Narrowing to x0 (AAPCS64's return register) kills
    exactly the 43 fictions and keeps that one. **Deleting a real touch is worse than the noise.**
17. **Soundness was PROVEN, not argued.** All 2417 surviving un-named pairings were re-derived
    **independently of the tool's own register map** — 2394 by direct `adrp` back-walk plus 23 via
    `adrp`/`add` chains, each with the base register verified untouched between definition and use.
    **0 unexplained.** The first pass of that checker disagreed with the tool 53 times and **the
    checker was wrong, not the tool** (it did not reconstruct add-chains); reading the binary settled
    it. That is MEMORY rule 9 working.
18. **Both new behaviour goldens were mutation-tested over all 706 slots**, not asserted: slot 58's
    `0x1044e6190` is MISSING on the pre-fix tool; `IOSVideoPlayerView` slot 159's `0x1041dd770` IS
    emitted without the x0 pop; `ThumbnailSession` slot 26's `0x1044e52d0` IS deleted under the broad
    rule. 15/15 goldens pass and the 9 pre-existing s81/s85/s91 ones are unchanged.

## What s92 landed on the wave

19. **Three bodies, all STOOD_UP, all adjudicated, `verdict_provenance_gate` OK on both classes.**
    `KSSlider` idx15 (slot 30, 59 instr) and idx16 (slot 31, 41 instr), orchestrator-direct.
    `PixelBuffer` idx35 (slot 67, 324 instr), by one agent under `STANDUP_PROTOCOL.md`, which
    returned 23 findings with **UNGROUNDED 0** — and every load-bearing claim was re-run against the
    binary before it entered the verdict, including re-counting the `AV_PIX_FMT` enumerators from the
    build headers rather than taking the agent's word for them. Verdicts
    `KSSlider_idx{15,16}_slot{30,31}_s92.json` and `PixelBuffer_idx35_slot67_s92.json`.
20. **`PixelBuffer` is COMPLETE for the wave** (23 classes left). **`KSSlider` is NOT** — idx17/18/19
    (slots 32/33/34) remain, and they are the gesture handlers: `locationInView:`, `maximumValue`,
    `minimumValue`, `frame`, `setValue:`, `state`. Cheap (55/62/82 instr) and the natural next batch.
20b. **The agent path worked and is worth repeating at this size.** One 324-instruction body, 62 tool
    calls, ~16 minutes, zero ungrounded claims — and it independently reproduced the idx-vs-slot trap
    on a class the orchestrator had not touched, which is what turned that from a KSSlider quirk into
    a wave-wide finding. Brief agents with the traps you have already confirmed and ask them to
    report what they find, not to assume it.

## Premises the names would have got wrong

21. **THE WORKLIST'S `slot` IS THE VTABLE IDX, WAVE-WIDE.** `slot = VTableOffset + idx`. On KSSlider
    (`VTableOffset=15`) worklist "slot 15" is `idx15 slot30`, and the *real* slots 15/16/17 are
    `Getter/Setter/Modify` with **`Impl=NULL`** — bodiless accessor descriptors. On PixelBuffer
    (`VTableOffset=32`) worklist "slot 35" is `idx35 slot67`. **Two independent classes, one derived
    by the orchestrator and one by an agent** — that is what makes it wave-wide rather than a quirk.
    Citing the worklist number as a slot does not merely mislabel, it names a different descriptor.
    Handoff step 35. Cite both numbers in every verdict.
22. **Step 35's `PlayerView` collision hits a SECOND tool.** `vtable_impl_oracle.py "$BIN" PlayerView`
    resolves to Notelet `0x1039e919c` and then prints *"no class descriptor named 'PlayerView'"* —
    while `conformance_walker.py` returns the real KSPlayer descriptor `0x1039ee210` in the same
    session. Treat "refused: no-vtable" / "no class descriptor" on a class you know exists as the
    collision, not as a fact about the binary.
23. **An un-named global's ADDRESS ORDER is not field order.** KSSlider's `isPlayable` is field 4 of 5
    yet holds the LOWEST global address (`0x1044e75c0`), below all three un-named ones. Never assign a
    field name by adjacency; prove ownership from the anchor site (which object register the offset is
    applied to).
24. **The delegate call CLOBBERS self.** In both KSSlider bodies `mov x20, x0` installs the delegate as
    swiftself, so any reading that treats x20 as the KSSlider afterwards is wrong. Same trap shape as
    s91's slot-73 discarded-receiver finding.
25. `KSSlider` idx15 and idx16 are **not** a getter/setter pair and not one method at two sites: they
    are sibling notifications differing in ONE scalar — `mov x0,#0x0` vs `mov w0,#0x3` into the same
    one-requirement witness. **It is the PAIR that proves the argument is an enum tag**; either body
    alone reads as a constant. Derive such siblings together.

## Contract numbers are now DERIVED, and three of them were wrong

23A. **`contract_numbers.py` is new and gate-wired as `sc_contract_numbers` (PASS 45 -> 46).** Every
    number an agent CONTRACT asserts now has a deriver. Prose cites a quantity as
    `⚑[derive=<id> value=<n>]` for a stable binary fact, or as a **valueless** `⚑[derive=<id>]` for
    project state that legitimately moves every session. `--check` re-derives all 21 pinned sites
    across 5 files and exits 1 on drift; mutation-tested by reintroducing the old wrong number.
23B. **`AGENT_PROTOCOL.md` and `function_extents.py` both asserted LC_SYMTAB is "stripped to 385
    entries all aliased to ONE address". Wrong in all three parts.** Derived: nsyms
    **7609**, defined N_SECT symbols **403**, occupying **33** distinct addresses, the dominant one
    `0x10198eb18` carrying **371** — and that is precisely the bogus `KSOptions.readyTime` label
    every ranged disassembly comes back with. The ADVICE built on it (ignore the label, take bounds
    from LC_FUNCTION_STARTS) was always right, **which is why it survived twelve sessions** — nobody
    re-checks a number whose conclusion is correct. The selfcheck carries a NEGATIVE control that no
    deriver reproduces 385.
23C. **The ICF numbers were correct** and verify to the digit: 1,711 of 41,244 exported addresses
    (4.1%) carry more than one symbol, one carrying 605. They are now derived rather than copied
    across four files.
23D. **`STANDUP_PROTOCOL` §1 quotes no wave count at all now.** It had rotted twice: 175/102/73 from
    s87 while the truth was 123/53/70, and the s92 correction to 123/24 was stale *within the same
    session*. A wave count is a fact about a moment, not about the project.
23E. **What was deliberately NOT converted, and why it would be a mistake to.** Golden anchors — a
    golden's literal IS its point (rule 11), and deriving it makes it self-fulfilling.
    `handoff_baseline.json` — a self-deriving tripwire is vacuous; the whole design is that derived
    state is compared against a frozen snapshot. Policy thresholds (`len(evidence) < 40`,
    `index < 26`). And **the numbers in handoffs and memory files** — those are point-in-time
    RECORDS, and rewriting "the faithful count moved from 146 to 147" to today's value destroys the
    record. The gate/hook CODE was already clean: `recon_gate` takes every expectation from the
    baseline JSON, and the only integer literals in the gates are the alphabet, IEEE-754 bit
    patterns, and that evidence-length floor.

## THE ONE TO READ FIRST — a derived divergence that is deliberately not a divergence

23. **`PixelBuffer` idx35 is `cgImage()`, and Forward WIDENED it — but the verdict is STOOD_UP.**
    Two independent orderings select the same source member: `PixelBufferProtocol`'s descriptor
    (`0x1039f108c`, `NumRequirements=40`) has **only five Method requirements, req35–req39**, so this
    body is the FIRST protocol method, and the source protocol's method order begins with `cgImage()`;
    and in the class vtable the five Methods are idx32–idx36, so this body is the FOURTH, and the
    source class's fourth method is `cgImage()`. Arity 0, returns `CGImageRef?`.
    **The divergence, fully derived:** the source at `PixelBufferProtocol.swift:269` tests
    `if format == AV_PIX_FMT_RGB24` — ONE format. The binary switches on **THREE**:
    `{2: RGB24, 25: ARGB, 26: RGBA}` (values re-counted from `FFmpeg-n8.1.1/libavutil/pixfmt.h`,
    each unique), selecting codes 0/4/3. It also replaces `CGImage.make` with a 52-byte
    `PointerImagePipeline` and `scale.shutdown()` with an inlined `swift_deallocClassInstance`.
    **Why it is NOT recorded as DIVERGENT:** the name is a REASONED identification, not a read one —
    four routes failed (trie, `Impl`-thunk, the witness thunk `0x101a8b79c`,
    `recover_swift_function_name`). `STANDUP_PROTOCOL.md` §3 is explicit that a reasoned origin is a
    finding and not a licence. **This is the strongest RE-BUCKETING candidate in the wave**: upgrade
    the identification to a read name and the unit moves to the AUDIT wave carrying a specified,
    already-derived divergence. Do not act on it as a divergence before re-bucketing.
23b. **`method_source_presence` can route an AUDITABLE body into the stand-up wave.** It buckets on
    whether the METHOD can be named, so for a class whose source survives, a positional match it
    cannot see is invisible to it. Same overstatement already recorded for
    `recover_swift_function_name`'s route, in a different tool. Worth a re-screen of the wave.
23c. **ADJACENT REFUTATION, banked.** `PixelBuffer`'s field records give `hdr10PlusData`,
    `displayInfo`, `contentInfo` and `ambientViewingEnvironment` a **`Sg` tail — `Foundation.Data?`,
    OPTIONAL** (all four share `__got 0x104109c60`). The reconstruction source writes them
    non-optional and its `⚑` comment calls the record "symbolic/unmapped". The record is neither.
    `PixelBufferProtocol.swift:174-176`.

## Names recovered — reuse them, do not re-derive them

26. **`KSSliderDelegate`**, protocol descriptor `0x1039ee4c4`, `NumRequirements=1`. Route: the field
    record's `symref->__got 0x1041079e8` is neither bound nor exported (a chained fixup); reading it
    with fixups applied gives the descriptor, whose Name is the rel32 at `+0x08` -> `0x1035696a0` ->
    `"KSSliderDelegate"`. **Sole conformer `PlayerView`** (conformer_desc `0x1039ee210`, witness table
    `0x1041d6368`), requirement-0 witness `0x101a0120c`.
27. **KSSlider field offsets**: `0x1044e75c0` = `isPlayable : Swift.Bool` (the only `vpWvd` of the 5
    fields); `0x1044e75d8` = `delegate` (proven by weak + existential shape — `_pSgXw` is the only
    such field record); `{0x1044e75c8, 0x1044e75d0}` = `{tapGesture, panGesture}` **as a set**, both
    force-unwrapped and sent `setEnabled:NO`. Which is which is OPEN — see step 30.

## Still open on the tools

28. **`field_offset_vector.py` refuses for a FALSE reason.** It builds `$s8KSPlayer13KSPlayerLayerCN`
    without module-name word substitution; the real symbol `$s8KSPlayer0A5LayerCN` exists. The refusal
    is still the CORRECT outcome, but the message misinforms. **Unchanged from s91.**
29. **`decode_witness_table.py --wt` CRASHES on a cross-module conformer** (`--wt 0x104182678`). Make
    it refuse with a message rather than raise. **Unchanged from s91.**
30. **Both vtable tools need the `fieldrec.desc_for_class` contract** (take a module, prefer KSPlayer,
    ERROR on ambiguity) and the idx-vs-slot fix. Now known to affect `vtable_impl_oracle` as well as
    `vtable_walk` — step 22. **This is the highest-value tool fix left**: it currently blocks naming
    `KSSliderDelegate` requirement 0, which is one vtable lookup away (`PlayerView` metadata offset
    `0x110`).
31. **`conformance_walker.py` WORKS on `KSSliderDelegate`** — the s91 report that it returns zero
    conformances is specific to `MediaPlayerTrack`, not general. Re-scope that entry before acting on
    it. It still requires a `name:descriptor_addr` spec and dies with a bare `ValueError` on a bare
    name.
32. **`name_type_at_addr.py` mis-decodes a protocol descriptor** — on `0x1039ee4c4` it returns
    `length 4294953340, type null`. Same misdecode family as the s91 `0x103567808` entry.
33. `decode_string_literal.py` misses computed counts and the `_StringObject` bias direction.
33b. **`prefetch_decompiles.py` has NO golden** and `handoff_completeness_lint` has been WARNing about
    it. It is on the provenance path for every verdict in the wave, so this is worth closing: add
    `scripts/test_prefetch_decompiles.py` or a `--selfcheck`. Pre-existing, not new in s92.
34. `l2_field_gate`'s `merge_binary_type` should fall back to the trie's `.setter`/`.getter` type when
    there is no mangled property symbol. The 205 unannotated stored properties (25.5% of 803, across
    33 classes) are the bigger prize.
35. **Extend the classmap to structs and enums.** `fieldrec.py <descriptor_addr>` works and was used
    again; `--class` failing on every enum is a trap each session rediscovers.
36. **The coverage-audit adjudication still has nowhere to land.** Build an explicit
    adjudicated-exclusion file that `wave_worklist` reads, with a selfcheck asserting every entry still
    resolves to a real verdict FIELD. **Never a greedy free-text address scan** — the s87 `bounds` trap.

## Session 93 — continue the STAND-UP wave

37. Regenerate the worklist and its DERIVED presence file in the same breath, never read either blind:
    `python3 scripts/wave_worklist.py --wave standup --json reconstruction/wave_standup.json` then
    `python3 scripts/method_source_presence.py --wave standup --json
    reconstruction/method_presence_standup.json`. Expect **120 units / 23 classes**, SOURCE_MATCH 0.
38. **Finish `KSSlider` first** — idx17/18/19, 199 instr total, one class to gate, and the two derived
    verdicts give you the class facts and the delegate protocol for free. Then re-screen the wave for
    step 23b before spending an agent on anything large.
39. **The cheap NAMED classes are exhausted.** What remains is dominated by `SettingsView` 43 units /
    9880 instr (all UNNAMED) and `IOSVideoPlayerView` 32 / 9122 (all NAMED, zero source overlap).
    Together ~58% of the wave.
40. **Before briefing any UNNAMED unit, run `recover_swift_function_name.py` on it yourself** and apply
    the labels>=2 discriminator. All 5 KSSlider units returned a clean `#function: None` — a genuine
    negative, so the `zpl`/labels=0 false-anchor trap did not arise. It will on SettingsView.
41. **Batch by CLASS; one body per agent for large bodies, derive small ones yourself.** s92 was
    orchestrator-direct at 41–59 instr. Hold every agent to `reconstruction/STANDUP_PROTOCOL.md`; its
    §1 stale count was fixed in s92 and now states the invariant plus the regenerate command.
42. **Give every agent the vpWvd technique AND its limit** — and now also the s92 additions: the
    un-named globals block with its sections, and that **ownership must be proven from the anchor
    site, never from adjacency or from the section alone**.
43. Budget `Anime4K` 3 units / 4780 instr, `ThumbnailSession` 4 / 5198 and `PreLoadIOContext` 7 / 3391
    like ten ordinary bodies each.
44. `VideoToolboxDecode` slot 29 `decodeFrame(from:completionHandler:)` @`0x101a6ce44` (572 instr) is
    the only genuinely open AUDIT unit — an explicit `deferred_to_P3` DV-crux body. Not a warm-up.

## Open work, unchanged or sharpened

45. **The two un-named-field identifications are now easier and should be re-attacked.** `0x104c63520`
    (written by KSPlayerLayer slot 56 with `options.isAutoPlay`) and `0x1044e6190` (written by slot 58,
    proven Double, reasoned as `shouldSeekTo`). **`body_fingerprint` now prints un-named globals, so
    the "find a body that writes the global alongside a trie-NAMED field" search is a scan of the new
    block rather than a hand disassembly sweep.** Same technique settles KSSlider's
    tapGesture/panGesture (step 27): find the body that CREATES the two recognizers, where the
    allocated class is readable, and read the store target.
46. **Two KSPlayerLayer-local helpers are pinned by many verdicts:** `0x1019c9a68` (336 B, 84 instr)
    and `0x1019c9cd4` (1188 B, 297 instr, `#file KSPlayer/KSPlayerLayer.swift`), the latter called from
    slots 56, 57, 59 and 62 — naming it closes four `unrecovered` entries at once.
47. **`0x103567808` is worth one more attempt** with the AsyncFunctionPointer reading, since
    `0x103567a30` in the same argument position DOES decode.
48. **Two module-wide shared helpers pinned by four verdicts:** `0x101a04674` (98 instr, 27 direct
    callers, `assumeIsolated`-shaped) and `0x101a03fd4` (163 instr, 53 direct callers, `Task`-creating).
    Both NOT IN TRIE. The highest fan-in unnamed bodies left in KSPlayer.
49. Fix queue, coupled — **build both before staging either**: `KSPlayerLayer.seek(time:)` (`:601`) and
    `VideoPlayerView.change(definitionIndex:)` (`:371-373`). Re-derive the slot-64 claim first.
50. The `startRecord` CRITICAL, **A · KSOptions**, the `T!` vs `T?` normalizer, Package F init bodies,
    MetalPlayView/`Drawable`, `PixelBufferProtocol`'s 40 requirements, and `Anime4KPreset`'s 11
    undecoded shader-path arrays are unchanged. See the s84 and s89 handoffs.

## What NOT to wave, in any session

51. **Source edits.** The pre-commit `l2_field_gate` blocks on the CLASS, not on your diff, so two
    "independent" edits in one file serialise anyway. Land derivations as specs during the wave, then
    apply them one unit and one commit at a time.
52. **Class-shape changes that ripple to consumers** (DisplayModel's `(frame:encoder:)` arity,
    VideoPlayerView's stored-property set, FFmpegDecode's signature). Single-threaded.
53. `GENERATED_ACCESSOR` (322 slots) is not a candidate at all: it collapses into declarations.

## Close out

54. Adjudicate every body with `adjudicate_verdict.py --id … --final … --evidence …` (never delete
    `binary_addr` to pass the provenance guard). Its guard requires a `decompile_cache` block with
    `verbatim: true`, and `verdict_provenance_gate.py` additionally requires the prefetch sidecar to
    EXIST on disk — so run `prefetch_decompiles.py --worklist <file>` for each unit even when you read
    the body from the disassembler. **The flag is `--worklist`, not `--json`.** s92 used
    `reconstruction/s92_standup_units.json`, whose shape is
    `{"units": [{id, address, class, subsystem, kind, symbol, demangled_sig, slot, instr}]}` — note
    `address`, not `addr`, and the top-level `units` key. Do not hand-annotate that cache (P27). Run
    `verdict_provenance_gate.py --class <C>` on every class you touch.
55. Update `reconstruction/handoff_baseline.json` with a `captured_session93` block and refresh `head`,
    `ahead_origin`, `faithful_floor`, `stood_up_floor`, `wave_standup_size` and `wave_audit_size`.
    **Re-run `recon_gate --mode handoff` AFTER updating the baseline.** Take `ahead_origin` from
    `git rev-list --count origin/forward..forward`.
56. Record how many bodies landed, the verdict split, and every premise refuted — the refutations have
    been the highest-value output of the last twenty sessions, above the code. Then write the
    session-94 handoff from the FINAL state, not by patching a mid-session draft. **Do not write the
    takeover prompt into it — give the prompt in chat.**
