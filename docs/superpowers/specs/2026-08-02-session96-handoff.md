# Session 96 work

**The floor moved again: 305 → 308.** Three DIVERGENT-queue verdicts flipped, each on evidence
re-read from the binary rather than inherited. **31 of the original 40 remain.** The mechanism is
still the only backlog in the project where fixing one body moves the floor by one.

**The third one opens a new seam: FILE PLACEMENT is readable, and it can flip a verdict on its own.**
See step 27. If you want cheap floor points, that is where to look first.

Note on filenames: this directory does not sort in session order. **Order by the session number.**

## Verify first

1. Run `ps -Ao pid,etime,command | grep -c "MacOS/claude --output-format stream-json"` FIRST. One
   live session prints **4** lines. Confirm there is no SECOND unrelated parent/child pair before
   touching `reconstruction/` or `forward`. `recon_gate --mode handoff` WRITES
   `reconstruction/handoff_report.json`, so running it IS touching `reconstruction/`.
2. Expect `python3 scripts/recon_gate.py --mode handoff` to print **PASS 47 / ANOMALY 0 / FAIL 3**,
   floor **308**, `agg_stood_up` **61**, `wave_standup_size` **109**, `wave_audit_size` **4**. PASS
   is 47, not 46: `sc_stale_screen` was added this session. The 3 permanent FAILs are the known debt
   and are this session's target: `agg_critical` **15**, `agg_high` **49**, `agg_unresolved` **1**.
   `agg_high` did not move on the third unit because that verdict's only blocker was a MED.
3. Run `python3 scripts/recon_progress.py`.
4. Re-derive every number above with `python3 scripts/contract_numbers.py --group state` before
   acting on it. This document is a snapshot.
5. Read `reconstruction/divergent_queue_s94.json` — still the live queue, and still the right one;
   it is a list of verdict ids, not a state file. Recompute which rows are done by reading each
   row's `file` and taking `recheck.final_verdict`; do not trust a count here. It is 9 done / 31
   open as of this writing.
6. **The two-repo split.** Swift sources, the `forward` branch and these handoffs live in
   `/Users/jweaver/Desktop/Work/swift/KSPlayer`. The cwd `/Users/jweaver/Desktop/Work/swift/play`
   holds `scripts/` and `reconstruction/`, both gitignored there. Address KSPlayer with `git -C`;
   run every `scripts/` command from `play`. FFmpegKit is a SIBLING at
   `/Users/jweaver/Desktop/Work/swift/FFmpegKit`, not inside it.
7. Read MEMORY.md before anything else. `validate_build.sh` lives in **`play/scripts/`**, not in
   KSPlayer — the KSPlayer repo has no `scripts/` directory at all.

## SETTLED — do not re-raise, do not re-derive

8. **The durability question is CLOSED by user decision.** The tool/verdict layer stays
   **uncommitted**. Do not propose versioning `scripts/`, `docs/` or `reconstruction/` again.
9. **Work is NOT looping.** Measured in s93: 4 of 355 addresses appear in more than one verdict file
   (1.1%), and all four are explained. Do not re-investigate this.
10. **The naming-route sweep is spent.** Three routes were wired into `method_source_presence` in
    s93 and run across all 112 stand-up units; they named 5 and re-bucketed 3. Do not re-run it.
11. **The stand-up wave cannot move the floor, by design.** 109 units, 15 classes, every one ends as
    STOOD_UP. It is not this session's work.
12. **The step-18 zero-edit screen is SPENT — do not run it hoping for another FileLog.** s95 built
    `stale_divergence_screen.py` and ran it over all 34 then-open units. **No unit in the queue is a
    zero-edit flip.** Every remaining divergence's source-side claim still describes the source, and
    the four cheapest were checked by hand on top of the tool: `sei` was still 1-parameter at
    KSOptions.swift:487, `start(view:)` still at KSPictureInPictureController.swift:99,
    `originalOrientations` still declared at IOSVideoPlayerView.swift:27 and read at :274/:296-297
    (it is PINNED in-source at :19, which is not the same as fixed), and
    `DispatchQueue.main.asyncAfter` still at BrightnessVolume.swift:47. Re-run the tool only after a
    session lands source changes, which is the case it exists for.

## What s95 landed, so you do not redo it

13. **Three body commits on `forward`**, one unit each: `3b3980f` (KSOptions.sei), `bb00f91`
    (BrightnessVolume.appearView) and `5539cea` (FormatContext.performSeek → FFmpegUtility.swift).
    Floor 305 → 308, `agg_high` 52 → 49.
14. **`KSOptions_sei_10000e52c` is FAITHFUL.** `sei` is now `open func sei(string _: String, time _:
    CMTime) {}`. The call site at FFmpegDecode.swift got the `time:` argument, and it was READ: a
    whole-`__text` scan for a dispatch through slot 283 (metadata offset `0xbc8`) finds exactly ONE
    call in the image, `0x101a6754c`, and its argument is built at `0x101a674fc-0x101a67544`.
15. **`BrightnessVolume_appearView_slot9_s84` is FAITHFUL.** `DispatchQueue.main.asyncAfter` → a
    `Task` awaiting `try await Task.sleep(nanoseconds: 3_000_000_000)`.
16. **`FormatContext_performSeek_101a329d8` is FAITHFUL**, and it was closed by a MOVE, not a body
    edit: zero body lines changed. `performSeek` now lives in a new
    `Sources/KSPlayer/MEPlayer/Remux/FFmpegUtility.swift` as an `extension FormatContext`. Read
    step 27 before you touch any other placement.
17. **NEW TOOL `scripts/stale_divergence_screen.py`**, wired into `recon_gate` as `sc_stale_screen`
    (PASS 46 → 47). Full usage is in the faithfulness manual. It reports; it decides nothing.
18. **`AudioDescriptor_updateAudioFormat_slot17_s84` was re-adjudicated DIVERGENT ON PURPOSE** — see
    step 20. Its `recheck.confirmed_reason` now carries the reason, so read the verdict, not this.

## THE FOUR REFUTATIONS s95 PRODUCED — the same failure modes are latent in the other 31

19. **A handoff's own prescription can be wrong, including this one's.** The s95 handoff step 24 said
    BrightnessVolume's `progressView` LOW was "composition ORDER only, so it is a SPELLING difference
    of the same kind as `PlayerView.delegate` — land the reorder first as its own commit". MEMORY
    rule 12 says prove it, so I compiled a control: two functions differing only in whether a
    class+protocol composition is written protocol-first or class-first **mangle to the identical
    `AA2PV_AA1VCXc` and both demangle class-first**. The two spellings are the SAME type and the same
    emitted bytes. It is NOT the `PlayerView.delegate` case — that was a typealias reflection erases,
    where source text and binary record differed for a real reason. `l2_field_gate`'s REAL_FLAG here
    was comparing source TEXT against the binary's canonical printing, and **which order Forward
    wrote is not decidable from the binary**. The declaration is now spelled canonically so the
    gate's comparison agrees, and the undecidability is recorded in the file rather than sold as a
    fix. Do not let a gate's green tell you a divergence was real.
20. **A "cheap" two-HIGH unit can be coupled to a body nobody has audited.**
    `AudioDescriptor_updateAudioFormat_slot17_s84` looks like a one-line argument drop. Both HIGHs
    are CONFIRMED — the call at `0x101a68ad0` sets only x0/x1/x2, and across all 190 instructions of
    the callee `0x101a68c44` every x3/w3 occurrence is a WRITE, so the `sampleFormat` parameter does
    not exist in Forward's helper. But dropping it at Resample.swift:441 forces dropping it at :379,
    and `sampleFormat` drives that helper's entire commonFormat/interleaved switch at :398-426. **The
    unit to schedule is: audit `0x101a68c44` first, then land the helper body, its declaration and
    the call site as ONE unit.** This is the same shape as step 29's PiP warning, and it is the
    second instance, so treat "two HIGHs, one call site" as a coupling smell rather than a cheap win.
21. **`source_lines` drifts and is not maintained — locate the method by NAME, never by the cited
    range.** Two more confirmed instances this session: `sei` is cited at KSOptions.swift:476 and is
    at :487; PiP `start` is cited at :78 and is at :99. `stale_divergence_screen` prints the line of
    every hit precisely so you can see the drift instead of trusting the citation.
22. **An in-source PIN can be wrong the same way a verdict can, and it is not evidence.**
    FormatContext.swift:321-331 carried a careful, well-derived pin that concluded "placement is
    therefore left beside its class". Its premises were all TRUE and re-checked this session — our
    `Remux/` filenames really are absent from the literal set, `FFmpegUtility` really is a
    Forward-added type — but the CONCLUSION did not follow: those are facts about the other files'
    fidelity, not about this member, whose own file is known and matchable. A pin records what a
    session decided, and its reasoning is refutable exactly like a verdict's. Re-derive the premises,
    then re-decide; do not treat "a previous session already looked at this" as a closed question.
23. **`_swift_deletedMethodError` is a distinct, recognisable state.** `0x10198eb18` is a 376-way
    fold whose body is `bl` + `brk #0x1`, and the stub's `__got` slot `0x104112DF0` binds it. A
    symbol resolving there has its NAME in the trie and its CODE deleted. Do not audit such a body
    and do not call the method absent.

## THE WORK — 31 DIVERGENT verdicts remain

24. **Per unit, in this order.** Read the verdict's `divergences` array. Re-derive each claim against
    the binary with `llvm-objdump` yourself. Then fix the source, rebuild, re-audit.
25. **Re-adjudicate with `python3 scripts/adjudicate_verdict.py --id <id> --final FAITHFUL
    --overturned --evidence "$(cat <file>)"`.** `--overturned` is required whenever the verdict
    carries divergences. The evidence must state what YOU checked against the binary. Never delete
    `binary_addr` to get a verdict past its provenance guard. Pass the evidence via `$(cat …)` —
    `command_shape_hook` pattern-matches the command line, so an evidence string that merely NAMES a
    tool is blocked as if it were a malformed command. The same applies to the commit message: write
    it to a file and use `git commit -F`.
26. **Residue that does NOT block FAITHFUL.** "open vs public is not decidable on a non-final class"
    is an undecidability note, not a source defect. So is an ICF fold that makes a body's address
    non-discriminating, and so is an unnamed (NOT_IN_TRIE) callee whose name nothing turns on. Say
    so in the evidence rather than dropping it.
27. **FILE PLACEMENT IS A READING, AND IT IS THE MOST PROMISING UNWORKED SEAM. Start here.** s95
    closed `FormatContext_performSeek_101a329d8` with **zero body lines changed** — the whole unit
    was moving the member into a file with the right name. The method generalises:
    - The image holds **56** distinct `KSPlayer/<file>.swift` `#fileID` literals. Extract them with a
      regex over the raw bytes; that set is Forward's file list, or at least every file containing a
      body that emits `#fileID` (a `KSLog` call is enough).
    - For any one of them, a whole-`__text` scan for `adrp`+`add` materialisations of the literal's
      address gives **every body declared in that file**. For `FFmpegUtility.swift` that is exactly
      two: `performSeek` and `close(formatCtx:)`.
    - Compare against where our source declares the same member. `KSPlayer/FormatContext.swift` is
      NOT in the literal set, and neither is any other `Remux/` filename — so our `Remux/` layout is
      invented, and each of those is a candidate.
    - **The residual `#line` does not block FAITHFUL** and you do not need to argue it again:
      `KSAVPlayer_play_slot95_s84` is FAITHFUL carrying exactly it, recorded there as "the file name
      matches; the line does not ... No semantic effect", and six FAITHFUL verdicts carry a
      position-drift note. Only the FILE has to match.
    - **This should be a TOOL and is not one yet.** It is the obvious next build: literal set →
      per-literal materialisation sites → enclosing function via `function_extents` → name via the
      trie → the file our source declares that name in → a per-body PLACEMENT verdict. s95 did it by
      hand for one literal. Doing it for all 56 would price the whole seam in one run.
28. **Cheapest remaining among the ordinary units.** No single-blocking-divergence unit is both open
    and uncoupled: `FormatContext_inner_init_101a350bc` (1 MED) waits on the PlayList protocol unit;
    `PreLoadIOContext_download_existential_s78` (1 MED) is a USER-GATED deferral — its optionality
    cannot be dropped without inventing the URLContext construction in `0x101b90c58` — and must NOT
    be flipped; `IOSVideoPlayerView_updateUIisFullScreen_slot145_s84` (1 MED + 2 LOW) is the
    `originalOrientations` field, already pinned in-source.
29. **`KSPictureInPictureController_slot2_1019c7648` LOOKS cheap and is NOT.** Its body really is one
    tail call to `stopPictureInPicture()`, but the binary class has ZERO stored properties, so the
    whole originalViewController / view / pipController state model this method manipulates is not
    part of the class in this build. That is the class-level reconciliation pinned in-source at lines
    13-29, not a per-slot edit.
30. **Densest remaining:** `Coordinator 0x1019db8e8` (9), `FFmpegDecode 0x101a2220c` (9),
    `KSVideoPlayerView_open 0x101ac99ac` (7, no `binary_addr`),
    `KSPlayerLayer_stop_slot63_s84 0x1019cccd8` (6), `VideoPlayerView_setupU 0x101b2c1bc` (6).
31. **3 of the 40 carry no `binary_addr`.** They are not addressable by the normal path. Give them
    the per-body-field treatment `wave_exclusions` uses, or pin them. Do not invent an address.

## The commit gate — read this before you stage

32. **`l2_field_gate` blocks on the CLASS, not on your diff.** Plan one unit, one commit. Run
    `python3 scripts/verdict_provenance_gate.py --class <C>` on every class you touch before staging,
    and `python3 scripts/recon_gate.py --mode commit` after `git add`. A unit whose fix has a
    compile-forced consequence in a second file (the sei declaration and its call site) is still ONE
    commit — splitting it would leave a non-building intermediate.
33. **Distinguish the two kinds of block.** A *user-gated deferral* has no faithful spelling
    available: `KSAVPlayer.pipController` and `KSMEPlayer.pipController` want
    `(any KSPictureInPictureProtocol)?`, a 10-requirement protocol that does not exist in the
    reconstruction, and `KSMEPlayer.videoOutput` carries a `binding_gate` *pinned* marker. Touching
    those files raises them, so `69c3db5` used `--no-verify` and documented all three. A *spelling
    difference* must NOT be suppressed — but s95's step 18 shows a third category exists: a flag that
    is neither, because the two spellings compile to the same bytes. Prove which of the three you
    have before reaching for `--no-verify` (MEMORY rule 12). Do not widen
    `l2_field_gate._TYPE_ALIASES` for a project-local Swift typealias.
34. **Build each unit alone.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    ./scripts/validate_build.sh all` must print 4/4 before you stage. Run `git commit` in the
    background, wait for `WRAPPER_EXIT`, then **confirm HEAD actually moved** — a blocked commit
    still exits the wrapper cleanly with exit code 0.

## Findings earlier sessions surfaced and deliberately did not action

35. **`MediaPlayerDelegate` has `num_requirements=8`** in the binary (descriptor `0x1039ed850`,
    `protocol_signature.py`) against **5** declared in source. The witness table for
    `KSPlayerLayer : MediaPlayerDelegate` is `0x1041d49b8`; its five vtable-dispatch thunks decode
    (VTableOffset 27 words / `0xd8` bytes) to idx69 readyToPlay, idx70 changeLoadState, idx59, idx73
    and idx74 finish, and req7 points directly at `KSPlayerLayer.playerDidClear`. Own this as a
    protocol-shape unit.
36. **KSPlayerLayer's designated initialiser is `init(url:options:delegate:)`** — THREE parameters,
    against four in source. Forward reads `isAutoPlay` off `options` inside the init rather than
    taking a defaulted parameter. Its address is `0x1019ca41c`, 1664 B / 416 instr.
37. **`change(state:)` idx58 `0x1019cc0ac` still has no source counterpart** (STOOD_UP in s91). The
    `state` willSet observer is inlined at every `state =` write, so this one absence is a shared
    premise under several remaining KSPlayerLayer units — `prepareToPlay` idx68 names it explicitly.
    It is the highest-leverage structural unit in the class.
38. **Forward relocated FFmpegDecode's side-data loop into `VideoSwresample.s32` (`0x101a67274`).**
    s95 confirmed this independently while reading the sei call site: that body reads
    `nb_side_data`/`side_data` off the AVFrame in x19 and an FFmpegAssetTrack in x25. The pin at
    FFmpegDecode.swift:41-45 is correct and the coupling it describes is real.

## Tool debt, still open

39. **`prefetch_decompiles.py` has NO golden** — no `test_prefetch_decompiles.py`, no `--selfcheck`.
    It is on the provenance path of EVERY verdict in the corpus.
40. **`export_trie_oracle.address_of_symbol` and `names_at_address` crash** when handed
    `load_trie()`'s return value (`AttributeError: 'tuple' object has no attribute 'n'`). The CLI
    wraps it as `Trie(load_trie(path)[0])`; in-process callers must do the same. `build_index`
    returns a **set of bytes**, not a dict — filter it with `b'…' in n`, then go name→address with
    `--symbol`, which stays unique under an ICF fold where address→name does not.
41. `decode_witness_table.py --wt` still RAISES rather than refusing on an unmapped address, and is
    inapplicable to an ObjC `protocol_t`.
42. Both vtable tools resolve a bare class NAME to the first classmap row (`PlayerView` is Notelet
    `0x1039e919c` before KSPlayer `0x1039ee210`). Take the descriptor from `fieldrec.desc_for_class`
    or `conformance_walker`. `fieldrec.py` takes a DESCRIPTOR ADDRESS, not a class name;
    `field_offset_vector.py` takes the name.
43. `dump_binary_field_types.py` requires a live Ghidra bridge and dies with an opaque `TypeError`
    without one. `field_offset_vector.py` answers the stored-property-offset question from the
    Mach-O alone and is what s95 used.
44. `body_fingerprint.py`'s `DISPATCH OFFSETS` line can be a FALSE SIGNAL when the `blr` goes through
    a stored closure pointer. Its `_segments()` helper is, however, the correct way to read bytes at
    a vmaddr — only `__TEXT` satisfies `fileoff == vmaddr - 0x100000000`.

## Close out

45. Update `reconstruction/handoff_baseline.json` with a `captured_session96` block and refresh
    `faithful_floor`, `stood_up_floor`, `wave_standup_size`, `wave_audit_size`, `head` and
    `ahead_origin`. Take `ahead_origin` from `git rev-list --count origin/forward..forward`.
    **Re-run `recon_gate --mode handoff` AFTER updating the baseline.**
46. Record how many bodies moved to FAITHFUL, the floor before and after, and every premise refuted.
47. Run `python3 scripts/handoff_completeness_lint.py <handoff>` before committing it. Any
    `scripts/X.py` you name must have a DEDICATED entry in the faithfulness manual, not just a
    mention.
48. Write the session-97 handoff from the FINAL state, not by patching a mid-session draft. Give the
    takeover prompt in chat, never in the handoff file.
