# Session 94 work

**Raise the floor.** It has been 299 for eight sessions and that is the whole point of this session.

Session 93 established why, measured it, and cleared the two things standing in front of it. What
remains is the work that actually moves the number: **40 DIVERGENT verdicts**, each one a body that
was already audited against a real source counterpart. Fix the source, re-adjudicate to FAITHFUL,
and the floor moves by one. There is no other queue in the project with that property at this size.

Note on filenames: this directory does not sort in session order. **Order by the session number.**

## Verify first

1. Run `ps -Ao pid,etime,command | grep -c "MacOS/claude --output-format stream-json"` FIRST. One
   live session prints **4** lines. Confirm there is no SECOND unrelated parent/child pair before
   touching `reconstruction/` or `forward`. `recon_gate --mode handoff` WRITES
   `reconstruction/handoff_report.json`, so running it IS touching `reconstruction/` and this step
   gates it.
2. Expect `python3 scripts/recon_gate.py --mode handoff` to print **PASS 46 / ANOMALY 0 / FAIL 3**,
   floor **299**, `agg_stood_up` **61**, `wave_standup_size` **109**, `wave_audit_size` **4**. The 3
   permanent FAILs are the known debt: `agg_critical 15`, `agg_high 55`, `agg_unresolved 1` — and
   **those three FAILs are this session's target**, not background noise.
3. Run `python3 scripts/recon_progress.py`.
4. Read `reconstruction/divergent_queue_s94.json` — the 40 units, sorted by divergence count.
5. **The two-repo split.** Swift sources, the `forward` branch and these handoffs live in
   `/Users/jweaver/Desktop/Work/swift/KSPlayer`. The cwd `/Users/jweaver/Desktop/Work/swift/play`
   holds `scripts/` and `reconstruction/`, both gitignored there. Address KSPlayer with `git -C`;
   run every `scripts/` command from `play`. FFmpegKit is a SIBLING at
   `/Users/jweaver/Desktop/Work/swift/FFmpegKit`, not inside it.
6. Read MEMORY.md before anything else.

## SETTLED — do not re-raise, do not re-derive

7. **The durability question is CLOSED by user decision.** The tool/verdict layer stays
   **uncommitted**. Do not propose versioning `scripts/`, `docs/` or `reconstruction/` again.
8. **Work is NOT looping.** Measured in s93: 4 of 355 addresses appear in more than one verdict file
   (1.1%), and all four are explained — `0x10000e52c` and `0x101a32e28` are ICF folds (one address,
   two legitimate owners), `0x101a2220c` and `0x101a6cc58` are the deferral→closer pattern. There is
   no audit / tool-change / re-audit cycle. Do not re-investigate this.
9. **Why the floor froze, and it was not churn.** It climbed 151→299 from s36 to s86, then stopped
   dead, because s86 concluded the audit wave was EMPTY. That conclusion was an artifact of
   `method_source_presence`'s naming vocabulary, not a fact about the binary — but the hidden
   auditable population is **THREE UNITS, not a trove**. Three naming routes were wired in and run
   across all 112 stand-up units in s93; they named 5 and re-bucketed 3. Do not expect more from
   that direction and do not re-run that sweep.
10. **The stand-up wave cannot move the floor, by design.** 109 units, 15 classes. Every one ends as
    STOOD_UP: shape recovered, no counterpart, floor movement zero. It is not this session's work.

## What s93 landed, so you do not redo it

11. **Six bodies stood up, six classes completed**, all adjudicated with
    `verdict_provenance_gate --class` OK: `SphereDisplayModel` idx25/slot50, `MetalSubtitleView`
    idx23/slot40, `Remuxer` idx7/slot22, `FFmpegSubtitleParse` idx2/slot12, `DynamicInfo`
    idx36/slot60, `DoviDisplayModel` idx9/slot47. `agg_stood_up` 55 → 61.
12. **`wave_exclusions.py` + `reconstruction/wave_exclusions.json`** — wave counts are now EXACT
    rather than upper bounds. 9 per-body verdict mentions adjudicated: 7 DONE, 2 OPEN. Every entry
    names a verdict FILE and a STRUCTURED JSON PATH; never a free-text address scan.
13. **Three naming routes in `method_source_presence`** — fold-immune inversion, `#function` literal
    (gated on the materialization discriminator, not confidence), and the ObjC method list. 21
    selfcheck assertions, the 5 pre-existing goldens unchanged.
14. **`positional_rebucket_screen.py`** — the class-vtable positional argument, with a control and a
    source-provenance check. Use it if you need to test a positional hypothesis; do not trust one
    without it.

## THE WORK — the DIVERGENT queue

The queue is `reconstruction/divergent_queue_s94.json`: **40 verdicts, 37 with a `binary_addr`**,
across 14 classes. Severity spread over all divergences: 10 CRITICAL, 28 HIGH, 30 MED, 27 LOW.

15. **Start with `KSPlayerLayer`.** It holds **13 of the 40** — by far the largest cluster, and
    finishing a class at a time is what makes the pre-commit gate tractable (step 19).
16. **Per unit, in this order.** Read the verdict's `divergences` array. For each entry, re-derive
    the claim against the binary yourself with `llvm-objdump` before touching source — a divergence
    written in an earlier session is a premise, not a fact, and s93 refuted several. Then fix the
    source, rebuild, and re-audit.
17. **Re-adjudicate with `python3 scripts/adjudicate_verdict.py --id <id> --final FAITHFUL
    --evidence "…"`.** Never delete `binary_addr` to get a verdict past its provenance guard. The
    evidence string must state what YOU checked against the binary, not what the old verdict said.
18. **3 of the 40 carry no `binary_addr`** — `KSVideoPlayerView_open…` is one. They are not
    addressable by the normal path; give them the same per-body-field treatment `wave_exclusions`
    uses, or pin them and move on. Do not invent an address for them.
19. **THE THROUGHPUT CONSTRAINT, and it is real.** Source edits are serialised by the pre-commit
    `l2_field_gate`, which blocks on the **CLASS**, not on your diff — so two "independent" edits in
    one file serialise anyway. With 13 of 40 in `KSPlayerLayer`, plan for **one unit, one commit**.
    Do not batch a class's fixes into a single commit hoping the gate will pass.
20. **Run `python3 scripts/verdict_provenance_gate.py --class <C>` on every class you touch**, before
    staging.
21. **Coupled pair — build BOTH before staging EITHER**: `KSPlayerLayer.seek(time:)` (`:601`) and
    `VideoPlayerView.change(definitionIndex:)` (`:371-373`). Re-derive the slot-64 claim first.
22. Top of the queue by divergence count, if you want the densest units first: `Coordinator`
    `0x1019db8e8` (9), `FFmpegDecode` `0x101a2220c` (9), `KSVideoPlayerView_open` `0x101ac99ac` (7,
    no `binary_addr`), `KSPlayerLayer_stop` `0x1019cccd8` (6), `VideoPlayerView_setupU` `0x101b2c1bc`
    (6).

## The audit wave — 4 units, and 3 of them are new

23. `wave_audit_size` is **4**, up from 1. Three units were re-bucketed out of the stand-up wave in
    s93 on READ names, and each has a source counterpart in its own class's scope:
    - `AudioSwresample` idx10/slot23 `0x101a67c34` (368 instr) = `setup(descriptor:)`, source
      `Resample.swift:292`. Named from the in-body `#function` literal.
    - `PlayerTransitionAnimator` idx2/slot16 `0x101b18b50` (306 instr) = `animateTransition(using:)`,
      source `PlayerTransitionAnimator.swift:28`. Named from the ObjC method list; the thunk's own
      `#line` 28 matches the declaration exactly.
    - `KSOptions` idx128/slot222 `0x10002db34` (3 instr) = `wantedAudio(tracks:)`, source
      `KSOptions.swift:432`. **This one carries an already-derived signature divergence**: the binary
      returns `MediaPlayerTrack?`, the source declares `-> Int?`, and the machine code proves it —
      `Optional<Int>.none` emits a TAG word (`mov w1,#1`, control at `0x100077528`) while this body
      emits the all-zero existential nil. 3 instructions for a floor point.
24. **`VideoToolboxDecode` slot29 `0x101a6ce44` is far smaller than earlier handoffs claim.** Its DV
    crux is CLOSED by `VideoToolboxDecode_decodeFrame_DVloop_p3a.json` (FAITHFUL, recheck FAITHFUL,
    not overturned) and the loop LANDED in source. What remains open is four
    `lastPosition→maxTimestamp` placeholder sites still carrying live `⚑P3` markers at
    `VideoToolboxDecode.swift:145/146/148/153`. Four field references, not a 572-instruction body.
25. **Do NOT write a STOOD_UP verdict for any of the four.** They have source counterparts, so
    `adjudicate_verdict.py` will refuse it. Note the verdict-filename hazard on `KSOptions`:
    `KSOptions_slot222_1019bea08.json` already exists and is a DIFFERENT method (idx222 / real slot
    316). Cite both idx and slot, and pick a stem that does not collide.

## Standing rules that bite hardest here

26. **Verify every load-bearing agent claim against the binary yourself** before it enters a verdict.
    Separate what you verified from what an agent reported.
27. **Re-derive a signature UNBOUNDED before quoting it.** s93's orchestrator wrote
    `-> [KSPlayer.SubtitlePart]` into an agent contract after a 90-character truncated dump ended at
    `throws ->`, completing it from the SOURCE default. The real return was the existential
    `KSSubtitleProtocol`. Completing a Forward signature from upstream systematically hides the very
    divergence being hunted. A truncated tool output is not a read.
28. **Derive per-class properties per class.** s93 wrote "for a `metadata_init=1` class" into four
    agent contracts; three of the four classes were `metadata_init=0`. Run `vtable_walk.py <C>` first.
29. **Cite BOTH idx and slot** in every verdict (`slot = VTableOffset + idx`).
30. **Never type a count into an agent contract** — use `⚑[derive=<id>]`, gate-checked by
    `sc_contract_numbers`.

## Tool debt, verified open in s93

31. **`prefetch_decompiles.py` has NO golden** — no `test_prefetch_decompiles.py`, no `--selfcheck`.
    It is on the provenance path of EVERY verdict in the corpus. This is the highest-value tool fix
    left and it guards work you are about to do.
32. `decode_witness_table.py --wt` still RAISES rather than refusing:
    `RuntimeError: read_mem(0x107ad5588, 128) failed`. It is also inapplicable to an ObjC
    `protocol_t`, which is a distinct second cause.
33. Both vtable tools still resolve a bare class NAME to the first classmap row (`PlayerView`
    collision). Take the descriptor from `fieldrec.desc_for_class` or `conformance_walker`.
34. `dump_binary_field_types.py` printed `Remuxer.startTime : Swift.Double` where the class-scoped
    field record gives `[Int32:Int64]` — an UNSCOPED property-symbol match. The row is self-flagged
    `scope=unscoped fr_category=unmapped`, but the printed TYPE is a fabrication.
35. `body_fingerprint.py`'s `DISPATCH OFFSETS` line can be a FALSE SIGNAL: on `DynamicInfo` both
    `blr`s go through stored closure pointers read off `self`, not the metadata pointer.
36. `export_trie_oracle.Trie.walk()` has a `depth > 64` cap, so a full root walk yields only 403
    terminals — which equals the LC_SYMTAB count and therefore looks plausible. Use `class_subtree()`
    or an iterative walk.

## Close out

37. Update `reconstruction/handoff_baseline.json` with a `captured_session94` block and refresh
    `faithful_floor`, `stood_up_floor`, `wave_standup_size`, `wave_audit_size`, `head` and
    `ahead_origin`. Take `ahead_origin` from `git rev-list --count origin/forward..forward`.
    **Re-run `recon_gate --mode handoff` AFTER updating the baseline.**
38. Record how many bodies moved to FAITHFUL, the floor before and after, and every premise refuted.
39. Write the session-95 handoff from the FINAL state, not by patching a mid-session draft. Give the
    takeover prompt in chat, never in the handoff file.
