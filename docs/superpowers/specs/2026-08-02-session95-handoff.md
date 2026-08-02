# Session 95 work

**Keep the floor moving.** Session 94 broke an eight-session freeze at 299 and took it to **305**.
The mechanism is proven and it is repeatable: the DIVERGENT queue is the only backlog in the project
where fixing one body moves the floor by one. **34 of the original 40 remain.**

Note on filenames: this directory does not sort in session order. **Order by the session number.**

## Verify first

1. Run `ps -Ao pid,etime,command | grep -c "MacOS/claude --output-format stream-json"` FIRST. One
   live session prints **4** lines. Confirm there is no SECOND unrelated parent/child pair before
   touching `reconstruction/` or `forward`. `recon_gate --mode handoff` WRITES
   `reconstruction/handoff_report.json`, so running it IS touching `reconstruction/`.
2. Expect `python3 scripts/recon_gate.py --mode handoff` to print **PASS 46 / ANOMALY 0 / FAIL 3**,
   floor **305**, `agg_stood_up` **61**, `wave_standup_size` **109**, `wave_audit_size` **4**. The 3
   permanent FAILs are the known debt and are this session's target, not background noise:
   `agg_critical` **15**, `agg_high` **52**, `agg_unresolved` **1**.
3. Run `python3 scripts/recon_progress.py`.
4. Re-derive every number above with `python3 scripts/contract_numbers.py --group state` before
   acting on it. This document is a snapshot.
5. Read `reconstruction/divergent_queue_s94.json` — still the live queue. Recompute which rows are
   done by reading each row's `file` and taking `recheck.final_verdict`; do not trust a count here.
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

## What s94 landed, so you do not redo it

12. **Six commits on `forward`**, one unit each: `69c3db5` (changeBuffering), `76c42a5` (the
    PlayerView delegate spelling), `8ca69b9` (seek), `10ddf11` (pause), `941b765` (handoffs),
    `32641b7` (resetPlayer). Floor 299 → 305.
13. **Six queue verdicts are now FAITHFUL**: `KSPlayerLayer_changeBuffering_slot71_s81` (idx71
    slot98), `KSPlayerLayer_seek_slot64_s84` (idx64 slot91), `KSPlayerLayer_pause_slot61_s81` (idx61
    slot88), `PlayerView_seek_slot16_s81` (idx16 slot31), `PlayerView_resetPlayer_slot17_s81` (idx17
    slot32), `FileLog_log_slot1_s84` (idx1 slot13). `agg_high` 55 → 52.
14. **`KSPlayerLayer.seek(time:autoPlay:completion:)` idx65 was re-typed** to the binary's
    `(@MainActor @Sendable (Bool) -> Void)?`, closing one of its five divergences. Its three
    body-level HIGHs are untouched and it is still DIVERGENT — it is a live queue unit.
15. **PlayerView is now gate-clean** (see step 29) and its geometry is derived: descriptor
    `0x1039ee210`, VTableOffset **15** words, VTableSize 25, `metadata_init` **0**. KSPlayerLayer is
    VTableOffset **27**, `metadata_init` **1**. Derive it per class; the two differ.

## THE WORK — 34 DIVERGENT verdicts remain

16. **Re-derive before you edit. This is the whole lesson of s94.** Three separate premises written
    into earlier verdicts were refuted by re-reading the binary, and each would have produced a
    wrong source edit that still compiled. Read steps 17-19 before choosing a unit.
17. **The three refutations, because the same failure modes are still latent in the other 34:**
    - **A prescription can be confidently wrong.** s84 said KSPlayerLayer.seek's divergence was
      ARITY and told you to give the one-argument `seek(time:)` at :601 a completion parameter. An
      **uncapped** export-trie index (57,138 names) shows THREE `seek` overloads with method
      descriptors for only two; `seek(time:)` is a real Forward method, and having no descriptor is
      exactly why it correctly lives in an extension. The defect was that `seek(time:completion:)`
      was missing entirely. **Build the index with `build_index`, never `Trie.walk()`** — the
      `depth > 64` cap yields 403 terminals and would have hidden this.
    - **A stored `symbol_demangled` may be truncated.** s81 recorded PlayerView.seek's completion as
      `(Swift.Bool) -> ()`; read unbounded it is `(@MainActor @Sendable (Swift.Bool) -> ())?`.
      Re-read every signature with `export_trie_oracle.py --addr … --owner …` to its terminator.
    - **A verdict may name a field it never read.** s81 called pause()'s zeroed Bool `isAutoPlay`
      from statement order alone. Ground it: KSPlayerLayer's designated init at `0x1019ca41c` stores
      KSOptions+`0x45` into the field behind global `0x104c63520`, and
      `$s8KSPlayer9KSOptionsC10isAutoPlaySbvpWvd` holds `0x45`.
18. **SOME UNITS NEED NO SOURCE EDIT AT ALL — screen for them FIRST, they are the cheapest points
    in the queue.** `FileLog_log_slot1_s84` was flipped to FAITHFUL in s94 with **zero** source
    change: its MED described `fileHandle.write(data)`, but an earlier session had already landed
    `try? fileHandle.write(contentsOf: data)` and never re-adjudicated the verdict, so the body had
    been faithful while `recheck.final_verdict` still read DIVERGENT. That is the exact failure mode
    `adjudicate_verdict.py`'s own docstring was written to prevent, and it has now happened at least
    twice more than that docstring records. **Before touching source on any unit, read the cited
    source and check whether the divergence still describes it.**
19. **`source_lines` drifts and is not maintained — locate the method by NAME, never by the cited
    range.** FileLog's verdict says `KSOptions.swift:908-913`; the method is at `:915-928`. s94's own
    commits shifted `KSPlayerLayer.swift` and `PlayerView.swift` further, so several remaining
    verdicts now cite ranges whose first line is a comment or a mid-body statement. Screening the 34
    open units, these cite a range that no longer opens on a declaration:
    `KSPlayerLayer_stop_slot63_s84`, `KSPlayerLayer_prepareToPlay_slot68_s84`,
    `KSPlayerLayer_audioInterrupted_slot79_s84`, `PlayerView_setUrlOptions_slot18_s84`. Recompute
    the range before quoting it; drift is not evidence of anything.
20. **`_swift_deletedMethodError` is a distinct, recognisable state.** `0x10198eb18` is a 376-way
    fold whose body is `bl` + `brk #0x1`, and the stub's `__got` slot `0x104112DF0` binds it. A
    symbol resolving there has its NAME in the trie and its CODE deleted. Do not audit such a body
    and do not call the method absent.
21. **Per unit, in this order.** Read the verdict's `divergences` array. Re-derive each claim against
    the binary with `llvm-objdump` yourself. Then fix the source, rebuild, re-audit.
22. **Re-adjudicate with `python3 scripts/adjudicate_verdict.py --id <id> --final FAITHFUL
    --overturned --evidence "…"`.** `--overturned` is required whenever the verdict carries
    divergences. The evidence must state what YOU checked against the binary. Never delete
    `binary_addr` to get a verdict past its provenance guard. Pass the evidence as
    `--evidence "$(cat <file>)"` — `command_shape_hook` pattern-matches the command line, so an
    evidence string mentioning `llvm-objdump` or `validate_build.sh` is blocked as if it were a
    malformed command.
23. **Residue that does NOT block FAITHFUL.** "open vs public is not decidable on a non-final class"
    is an undecidability note, not a source defect. Say so in the evidence rather than dropping it.
24. **Cheapest remaining units, by shape rather than by count.** `KSOptions_sei_10000e52c` (HIGH ×2:
    add `time: CMTime`, body is a single `ret`; its own note warns you not to fabricate the caller's
    CMTime at `FFmpegDecode.swift:113` — pin it if you cannot read it).
    `BrightnessVolume_appearView_slot9_s84` (HIGH: `DispatchQueue.main.asyncAfter` in source vs a
    Task awaiting `Task.sleep(nanoseconds: 3_000_000_000)` in the binary — but its LOW is a
    pre-existing l2 REAL_FLAG, `progressView` `src=BrightnessVolumeViewProtocol&UIView` vs
    `bin=UIView&BrightnessVolumeViewProtocol`. That is composition ORDER only, so it is a SPELLING
    difference of the same kind as `PlayerView.delegate` — land the reorder first as its own commit
    and the unit then passes the full gate.)
25. **`KSPictureInPictureController_slot2_1019c7648` LOOKS cheap and is NOT.** Its body really is one
    tail call to `stopPictureInPicture()`, but its own `fix` field forbids simply deleting the other
    nine statements: the binary class has ZERO stored properties, so the whole
    originalViewController / view / pipController state model this method manipulates is not part of
    the class in this build, and the removed behaviour has to be located before the source is
    reduced. That is the class-level reconciliation pinned in-source at lines 13-29, not a per-slot
    edit. Do not take it as a quick unit.
26. **Densest remaining:** `Coordinator 0x1019db8e8` (9), `FFmpegDecode 0x101a2220c` (9),
    `KSVideoPlayerView_open 0x101ac99ac` (7, no `binary_addr`),
    `KSPlayerLayer_stop_slot63_s84 0x1019cccd8` (6), `VideoPlayerView_setupU 0x101b2c1bc` (6).
27. **3 of the 40 carry no `binary_addr`.** They are not addressable by the normal path. Give them
    the per-body-field treatment `wave_exclusions` uses, or pin them. Do not invent an address.

## The commit gate — read this before you stage

28. **`l2_field_gate` blocks on the CLASS, not on your diff.** Plan one unit, one commit. Run
    `python3 scripts/verdict_provenance_gate.py --class <C>` on every class you touch before staging,
    and `python3 scripts/recon_gate.py --mode commit` after `git add`.
29. **Distinguish the two kinds of block, because s94 got both.** A *user-gated deferral* has no
    faithful spelling available: `KSAVPlayer.pipController` and `KSMEPlayer.pipController` want
    `(any KSPictureInPictureProtocol)?`, a 10-requirement protocol that does not exist in the
    reconstruction, and `KSMEPlayer.videoOutput` carries a `binding_gate` *pinned* marker and is
    assigned `nil` at `KSMEPlayer.swift:133`. Touching those two files at all raises them, so
    `69c3db5` used `--no-verify` and documented all three. A *spelling difference* is different and
    must NOT be suppressed: `PlayerView.delegate` read `src=ControllerDelegate?` vs
    `bin=PlayerControllerDelegate?` only because `PlayerView.swift:42` declares a typealias that
    reflection erases. That was landed FIRST as its own commit `76c42a5`, after which the seek unit
    passed the **full** gate. **PlayerView still owns two queue units and is now clear.**
30. **Prove which kind you have before reaching for `--no-verify`** (MEMORY rule 12). Do not widen
    `l2_field_gate._TYPE_ALIASES` for a project-local Swift typealias — that table takes only
    aliases for which the toolchain is the authority.
31. **Build each unit alone.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    ./scripts/validate_build.sh all` must print 4/4 before you stage. Run `git commit` in the
    background, wait for `WRAPPER_EXIT`, then **confirm HEAD actually moved** — a blocked commit
    still exits the wrapper cleanly with exit code 0.

## Findings s94 surfaced and deliberately did not action

32. **`MediaPlayerDelegate` has `num_requirements=8`** in the binary (descriptor `0x1039ed850`,
    `protocol_signature.py`) against **5** declared in source. The witness table for
    `KSPlayerLayer : MediaPlayerDelegate` is `0x1041d49b8`; its five vtable-dispatch thunks decode
    (VTableOffset 27 words / `0xd8` bytes) to idx69 readyToPlay, idx70 changeLoadState, idx59, idx73
    and idx74 finish, and req7 points directly at `KSPlayerLayer.playerDidClear`. Own this as a
    protocol-shape unit.
33. **KSPlayerLayer's designated initialiser is `init(url:options:delegate:)`** — THREE parameters,
    against four in source. Forward reads `isAutoPlay` off `options` inside the init rather than
    taking a defaulted parameter. Its address is `0x1019ca41c`, 1664 B / 416 instr.
34. **`change(state:)` idx58 `0x1019cc0ac` still has no source counterpart** (STOOD_UP in s91). The
    `state` willSet observer is inlined at every `state =` write, so this one absence is a shared
    premise under several remaining KSPlayerLayer units — `prepareToPlay` idx68 names it explicitly.
    It is the highest-leverage structural unit in the class.

## Tool debt, still open

35. **`prefetch_decompiles.py` has NO golden** — no `test_prefetch_decompiles.py`, no `--selfcheck`.
    It is on the provenance path of EVERY verdict in the corpus.
36. **`export_trie_oracle.address_of_symbol` and `names_at_address` crash** when handed
    `load_trie()`'s return value (`AttributeError: 'tuple' object has no attribute 'n'`). The CLI
    wraps it as `Trie(load_trie(path)[0])`; in-process callers must do the same.
37. `decode_witness_table.py --wt` still RAISES rather than refusing on an unmapped address, and is
    inapplicable to an ObjC `protocol_t`.
38. Both vtable tools resolve a bare class NAME to the first classmap row (`PlayerView` is Notelet
    `0x1039e919c` before KSPlayer `0x1039ee210`). Take the descriptor from `fieldrec.desc_for_class`
    or `conformance_walker`.
39. `dump_binary_field_types.py` can print a fabricated TYPE on an unscoped property-symbol match.
40. `body_fingerprint.py`'s `DISPATCH OFFSETS` line can be a FALSE SIGNAL when the `blr` goes through
    a stored closure pointer.

## Close out

41. Update `reconstruction/handoff_baseline.json` with a `captured_session95` block and refresh
    `faithful_floor`, `stood_up_floor`, `wave_standup_size`, `wave_audit_size`, `head` and
    `ahead_origin`. Take `ahead_origin` from `git rev-list --count origin/forward..forward`.
    **Re-run `recon_gate --mode handoff` AFTER updating the baseline.**
42. Record how many bodies moved to FAITHFUL, the floor before and after, and every premise refuted.
43. Run `python3 scripts/handoff_completeness_lint.py <handoff>` before committing it.
44. Write the session-96 handoff from the FINAL state, not by patching a mid-session draft. Give the
    takeover prompt in chat, never in the handoff file.
