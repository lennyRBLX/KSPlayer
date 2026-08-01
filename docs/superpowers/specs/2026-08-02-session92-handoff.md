# Session 92 work

Session 91 stood up **6 bodies** and **completed `KSPlayerLayer`** — the class now has zero stand-up
units left. `agg_stood_up` 46 -> 52; `wave_standup_size` 129 -> 123 (25 -> 24 classes). The faithful
floor did not move, and that is by design — a STOOD_UP body is audited against nothing and may never
enter the floor. It also cleared the s91 `body_fingerprint` blocker, found that the defect was two
bugs rather than one, proved the verdict corpus uncontaminated, and then fixed a *second*
`body_fingerprint` defect that an agent surfaced.

Note on filenames: this directory does not sort in session order. **Order by the session number.**

## Verify first

1. Run `ps -Ao pid,etime,command | grep -c "MacOS/claude --output-format stream-json"` FIRST. One
   live session prints **4** lines. Print `ps -Ao pid,ppid,etime,command | grep MacOS/claude` and
   confirm there is no SECOND unrelated parent/child pair before touching `reconstruction/` or
   `forward`. `recon_gate --mode handoff` WRITES `reconstruction/handoff_report.json`, so running it
   IS touching `reconstruction/` and this step gates it.
2. Expect `python3 scripts/recon_gate.py --mode handoff` to print **PASS 44 / ANOMALY 0 / FAIL 3**,
   floor **299**, `agg_stood_up` **52**, `wave_standup_size` **123**, `wave_audit_size` **6**. The 3
   permanent FAILs are the unchanged known debt: `agg_critical 15`, `agg_high 55`, `agg_unresolved 1`.
3. **The floor HELD at 299 and that is correct.** Fifty-two bodies are now stood up; none is
   auditable, so none may count toward FAITHFUL.
4. Run `python3 scripts/recon_progress.py`.
5. **The two-repo split.** Swift sources, the `forward` branch and these handoffs live in
   `/Users/jweaver/Desktop/Work/swift/KSPlayer`. The cwd `/Users/jweaver/Desktop/Work/swift/play`
   holds `scripts/` and `reconstruction/`, both gitignored there. Address KSPlayer with `git -C`;
   run every `scripts/` command from `play`. FFmpegKit is a SIBLING of KSPlayer at
   `/Users/jweaver/Desktop/Work/swift/FFmpegKit`, not inside it.
6. Read MEMORY.md before anything else. The PreToolUse hook fired twice in s91 and was right both
   times — on a bare `llvm-objdump` written inside verdict PROSE in a heredoc, and on an unquoted
   heredoc. Rephrase or split; never weaken it.

## SETTLED — do not re-raise

7. **The durability question is CLOSED by user decision.** The tool/verdict layer stays
   **uncommitted**. Do not propose versioning `scripts/`, `docs/` or `reconstruction/` again.
8. **The 3 coverage-audit hits are adjudicated** (`reconstruction/wave_coverage_adjudication_s88.json`).
   VideoSwresample 29/31 DONE, FFmpegDecode slot 18 genuinely OPEN. **Confirm, never re-derive.**
9. **The `dyld_info` blocker is CLOSED and its s89 diagnosis is REFUTED.** The trigger is `mmap()` of
   that path; `_load_binds` falls back to a SHA-256-verified byte-identical copy. Do not re-diagnose.
10. **`body_fingerprint`'s stale-adrp fabrication is CLOSED, goldened and measured.** Do not re-open
    it. What it was, for the record, because the handoff under-described it: TWO bugs of one family,
    not one. (i) The adrp register map was never invalidated when the register was REDEFINED between
    the `adrp` and the `ldr`. (ii) The operand regex was UNANCHORED, so a register-form
    `add x20, x8, x9` was read as `x8 + 0` and REBOUND x20 to a stale global, poisoning every later
    read off x20. The golden is on slot 56 and it FAILS on the pre-fix tool — that is the mutation
    test, keep it that way.
11. **The verdict corpus is CLEAN.** Step 11 of the s91 handoff is discharged. 37 verdict files
    reference an affected body; 4 mentioned a fabricated member and all 4 are explained — two are
    s90's own *records* of this defect, one matched a class's own name, and
    `KSAVPlayer_updateLoadState_97` cites `0x1019a5054` only because that is slot 98's ENTRY = slot
    97's extent END (the s87 `bounds` trap), and slot 97 keeps all six field touches under the fixed
    tool. Do not re-sweep this.

## What the two tool fixes cost and bought — the numbers to trust

12. **Fix 1, the pairing fix.** Measured over **910 bodies / 72 classes** (the 706-slot universe plus
    every address in the verdict corpus): **120 fabricated pairings removed, 0 added**, and **0 of
    the 120 lacked a proven register redefinition** — that last number is the soundness proof, and it
    was computed, not argued. Deduped to what `report()` actually prints: 50 `(global,name)` pairs
    lost across 55 bodies, 35 of them field-offsets. Three were hand-verified against the
    disassembly; the sharpest is `IOSVideoPlayerView` slot 151, credited with `PlayerView.delegate`
    where x20 actually held `playerLayer.player`'s existential and `+0x8` was its WITNESS TABLE WORD.
13. **The refinement that was DECLINED, and why that is evidence and not laziness.** Clobbering
    caller-saved registers at a `bl` was considered and rejected: `objc_retain_xN` is
    register-preserving, so it could produce a false negative, and a measurement showed **0**
    surviving pairings span a `bl`/`blr` in a caller-saved register — it would be a no-op. Decline
    a refinement by measuring it, not by asserting it is unnecessary.
14. **Fix 2, the dispatch fix, which came from an AGENT and was fixed only after the last agent
    landed (MEMORY rule 7).** The dispatch walk dropped a pointer SPILLED to the frame and RELOADED
    across calls — slot 76's `ldr x8,[x27,#0x160]` / `str x8,[sp,#0x8]` / … / `ldr x8,[sp,#0x8]` /
    `blr x8` — and it also read a bare `cbz x19` as a redefinition of x19. Goldened on slot 76 (both
    `0x70` and `0x160` required) with slot 77 as the negative control (exactly `[0x48, 0xf8]`, no
    invented offset). Re-run over all 706 slots: **6 dispatches RECOVERED, 0 removed.**
15. **The agent got the DEFECT right and the CAUSE wrong.** It blamed the `ldp` that loads the
    existential; the real cause was the spill/reload. Both halves of an agent's tool-gap report need
    checking, not just the half that says something is broken.
16. **`body_fingerprint`'s GLOBALS block is NAMED-ONLY, and that is now a recorded blind spot.** An
    offset global with no exported symbol is dropped silently rather than printed as an un-named
    touch. Ten of `KSPlayerLayer`'s 17 fields have no `vpWvd`, so a body read only through that block
    can under-count its field touches by half — slot 58 does exactly that. **Printing un-named
    globals as `<unnamed global 0x…>` is the obvious next fix; it is a behaviour change, so golden
    and measure it over all 706 slots like the other two.**

## What s91 landed

17. **Six bodies, all STOOD_UP, all adjudicated, `verdict_provenance_gate --class KSPlayerLayer` OK.**
    Slots 58, 62, 73, 76, 77, 81. Verdicts in `reconstruction/verdicts/*_s91.json`. Three were
    derived directly by the orchestrator (32/46/70 instr), three by one agent each (115/122/133
    instr); **all three agents returned `UNGROUNDED: 0`**, and every load-bearing claim was
    re-verified against the binary before it entered a verdict.
18. **KSPlayerLayer is COMPLETE for the stand-up wave.** `wave_worklist --wave standup` now returns
    zero units for the class.

## Body-level premises the names would have got wrong

19. `reachEndOfStream(player:)` **DISCARDS its `player`** — x0/x1/x2 are all overwritten before any
    read, and what reaches the delegate is `mov x0, x20`, THE LAYER. Same shape as s90's slot 75.
20. Its delegate requirement (index 5, witness offset `0x30`) lands on the ICF-folded empty default
    `0x10000e52c` in **all three** KSPlayerLayerDelegate conformers, so **the call is a no-op
    everywhere in this image**. The requirement's NAME is irreducible: no `TW` witness thunk for the
    protocol exists in the trie, and zero of the 420 symbols folded at `0x10000e52c` belong to it.
21. **Slot 73 is NOT byte-identical to `0x1019d58f8`** — SHA-256 over the two 128-byte extents
    differs. The s91 handoff left this open; it is now disproven, and necessarily so, since ICF would
    have folded them onto one address.
22. `pipStop(restoreUserInterface:)` **stops nothing itself** and its second dispatch is on
    **KSPictureInPictureProtocol, not MediaPlayerProtocol**. Offset `0x48` there is
    `KSPictureInPictureController.stop(restoreUserInterface:)` (conformance wt `0x1041d45a0`), NOT
    `playbackState.getter`. The ORDER is what disambiguates the two, and a flat set of dispatch
    offsets cannot carry it.
23. `reset()` does not reset the layer — it writes exactly one of its own properties (`@Published
    state = .initialized`) and otherwise reaches OUTWARD: nils `subtitleModel.selectedSubtitleInfo`,
    calls an unnamed SubtitleModel member, forwards `reset()` to the player. Its tail is SHARED with
    slot 63 `stop()`, so the two differ before that tail, not after it.
24. `change(state:)` never writes `_state`. It clears one Double field, drops the idle-timer disable
    on the main thread, and notifies the delegate — the notification being the only unconditional
    part. It allocates the `TaskPriority?` buffer in the PROLOGUE on every call, including the path
    that never reaches the Task.
25. `replaceAndConstrainPlayerView(player:replacing:)` makes **ZERO witness dispatches** through
    either existential (the only three `blr`s are two `___chkstk_darwin` and one value witness). Its
    work lives in an unnamed 204-instruction closure at `0x1019cfabc` — the byte immediately after
    its own extent — reached only through the 3-instruction forwarder `0x1019d6964`, which delivers
    the captures **SWAPPED**: `replacing` in (x0,x1), `player` in (x2,x3).
26. `select(subtitleInfo:isSecondary:)`'s nil case is **not** a separate path — `cbz x0` at entry
    skips only the image-subtitle half; a nil value still reaches the store half and CLEARS the
    property. The property SETTER is never called: the store is inlined, both branches converge on
    ONE shared sequence at `0x1019cecd4`, and the identity guard compares the INSTANCE WORD ONLY.
    Unlike sibling idx 80 `addSubtitle(to:)`, it never touches `delegate`.

## Names recovered this session — reuse them, do not re-derive them

27. **KSPlayerLayerDelegate**: requirement 0 (witness `0x08`) = `player(layer:state:)`, proven through
    the Coordinator thunk `0x1019dbe88` -> `0x1019db4f0`. Requirement 1 (`0x10`) =
    `player(layer:currentTime:totalTime:)` was already pinned by s90's slot 59. Requirement 5 (`0x30`)
    is irreducible (step 20). Requirement 9 (`0x50`) = `playerDidAddSubtitle`.
28. **MediaPlayerProtocol** (witnesses start at `wt+0x08`, so `offset = 8 + 8*index`): `0x28` = req4
    `view.getter`, `0x48` = req8 `playbackState.getter`, `0x50` = req9 `loadState.getter`, `0x58` =
    req10 `isPlaying.getter` (confirmed on KSAVPlayer; KSMEPlayer's is an unnamed thunk), `0xf8` =
    req30 `pipController.getter : KSPictureInPictureProtocol?`, `0x130` = req37 `reset()`, `0x160` =
    req43 `select<A: MediaPlayerTrack>(track: A)`. The last two were proven on **both** conformer
    tables through their 1-instruction thunks — do that, it is barely more work than one table.
29. **MediaPlayerTrack**: requirement 13 (`0x70`) = `isImageSubtitle.getter`, via FFmpegAssetTrack
    `wt 0x1041d78b8`. The impl address is a 2-symbol ICF fold; pass `--owner`.
30. **`0x101ab2540` is PINNED BY ROLE across two bodies** even though its name is unreadable: slot 76
    calls it with (new instance, new witness table) immediately before the inlined store into
    `SubtitleModel.selectedSubtitleInfo`, and slot 62 calls it with `(0,0)` immediately before storing
    nil into the same property. Its sibling `0x101ab2de4` occupies the same position for
    `secondarySubtitleInfo`. Each helper's extent ends exactly where that property's getter begins.
    **A role established by two independent bodies is worth more than a guessed name.**

## Still open on the tools

31. **Print un-named globals in `body_fingerprint`** — step 16. Highest value of the three, because it
    is a silent under-count of field touches on every `metadata_init=1` class.
32. **`field_offset_vector.py` refuses for a FALSE reason.** It builds `$s8KSPlayer13KSPlayerLayerCN`
    without module-name word substitution; the real symbol `$s8KSPlayer0A5LayerCN` exists. The refusal
    is still the CORRECT outcome (`metadata_init=1` means no static offsets), but the message
    misinforms. Fix the mangle construction, keep the refusal. **Unchanged from s91.**
33. **`decode_witness_table.py --wt` CRASHES on a cross-module conformer.** `--wt 0x104182678`
    (`Components.PlayerViewModel`) dies with an unhandled `read_mem` failure inside `_name_at`. Make
    it refuse with a message rather than raise. s91 routed around it by reading the witness words out
    of memory directly, which worked and is the pattern to keep. **Unchanged from s91.**
34. **`conformance_walker.py` returns ZERO conformances for MediaPlayerTrack** although two conformers
    exist and are reachable through the trie (`FFmpegAssetTrack`, `AVMediaSelectionTrack`). NEW this
    session. It also requires a `name:descriptor_addr` spec and dies with a bare `ValueError` on a
    bare name.
35. `vtable_walk.py` resolves a bare class NAME to the FIRST classmap row, wrong across a cross-module
    collision. Take a module, prefer KSPlayer, ERROR on ambiguity — `fieldrec.desc_for_class` already
    implements that contract. Fold in the idx-vs-slot numbering fix at the same time.
36. `decode_string_literal.py` misses computed counts and the `_StringObject` bias direction.
37. `l2_field_gate`'s `merge_binary_type` should fall back to the trie's `.setter`/`.getter` type when
    there is no mangled property symbol. 11 REAL_FLAGs + 7 UNCHECKED on KSPlayerLayer wait on it — but
    the 205 unannotated stored properties (25.5% of 803, across 33 classes) are bigger.
38. **Extend the classmap to structs and enums.** The descriptor-address workaround
    (`fieldrec.py 0x1039ecea0`) works and was used repeatedly again this session, but `--class`
    failing on every enum is a trap each session rediscovers.
39. **The coverage-audit adjudication still has nowhere to land.** Build an explicit
    adjudicated-exclusion file that `wave_worklist` reads, with a selfcheck asserting every entry
    still resolves to a real verdict FIELD. **Never a greedy free-text address scan** — that would
    drop 5 LIVE units via `bounds` mentions, the s87 defect, which bit again this session as a false
    contamination hit (step 11).

## Session 92 — continue the STAND-UP wave

40. Regenerate the worklist and its DERIVED presence file in the same breath, never read either blind:
    `python3 scripts/wave_worklist.py --wave standup --json reconstruction/wave_standup.json` then
    `python3 scripts/method_source_presence.py --wave standup --json
    reconstruction/method_presence_standup.json`. Expect **123 units / 24 classes**.
41. **The cheap NAMED classes are nearly exhausted.** With KSPlayerLayer done, what remains is
    dominated by two classes: `SettingsView` 43 units / 9880 instr (all UNNAMED) and
    `IOSVideoPlayerView` 32 / 9122 (all NAMED, zero source overlap). Together ~58% of the wave.
42. **Before briefing any UNNAMED unit, run `recover_swift_function_name.py` on it yourself** and
    apply the labels>=2 discriminator. The 70 UNNAMED units are where this pays; `SettingsView` alone
    is 43 of them.
43. **The `zpl` false anchor fired a FIFTH time** in s91, on slot 81. `0x103566c60` is the
    `Swift.TaskPriority?` mangle that EVERY `Task { }` creation site references. Reject on `labels=0`.
44. **A `#file` anchor is only as good as the CALL it was passed to.** Slots 58 and 81 BOTH
    materialise `KSPlayer/Utility.swift`:22 — it is the inlined main-thread helper's own
    `#fileID`/`#line` default, not either method's location, and neither body calls KSLog. Two bodies
    showing the same false anchor is what makes the pattern recognisable.
45. **Batch by CLASS; one body per agent for large bodies, derive small ones yourself.** The s91 split
    was orchestrator-direct at 32–70 instr and one agent each at 115–133. Hold every agent to
    `reconstruction/STANDUP_PROTOCOL.md`. Its §1 still quotes the s87-era "175 stand-up units … 102
    BINARY_ONLY"; the contract is unaffected but the number is stale — fix it when no agent is in
    flight (MEMORY rule 7).
46. **Give every agent the vpWvd technique AND its limit.** All three s91 agents got both and all
    three returned `UNGROUNDED: 0`. The limit earned its place again: slot 58's only write goes
    through an UNEXPORTED offset global, and the correct output was an offset plus proven type plus an
    explicitly-flagged reasoned name — never a read name.
47. Budget `Anime4K` 3 units / 4780 instr, `ThumbnailSession` 4 / 5198 and `PreLoadIOContext` 7 / 3391
    like ten ordinary bodies each.
48. `VideoToolboxDecode` slot 29 `decodeFrame(from:completionHandler:)` @`0x101a6ce44` (572 instr) is
    the only genuinely open AUDIT unit — an explicit `deferred_to_P3` DV-crux body. Do not take it as
    a warm-up.

## Open work, unchanged or sharpened

49. **Handoff step 37's unnamed field is still open, and s91 found a SECOND of the same kind.** The
    offset global `0x104c63520` is written by slot 56 with `options.isAutoPlay`; the POSITIONAL route
    is REFUTED and the strong reasoned identification is `isAutoPlay`. NEW: `0x1044e6190` on
    KSPlayerLayer is written by slot 58 and is **proven Double** (`str d8` in `seek`, `ldr d8`/`fcmp`
    in `readyToPlay`) with a strong reasoned identification of `shouldSeekTo` (field record 13, `Sd`),
    resting on an init that writes `0x188`/`0x190`/`0x198` in declaration order and then the
    trie-named `isAutoReplaceAndConstrainPlayerView` (field 16, the last). **To PROVE either, find a
    body that writes the global alongside a second, trie-NAMED field whose declaration order is
    known** — the init run is suggestive but its own lower bound is un-named too.
50. **Two unnamed KSPlayerLayer-local helpers are now pinned by more verdicts:** `0x1019c9a68`
    (336 B, 84 instr) and `0x1019c9cd4` (1188 B, 297 instr, `#file KSPlayer/KSPlayerLayer.swift`).
    `0x1019c9cd4` takes a Bool-shaped w0 and is called from slots 56, 57, 59 and now **62** (with
    FALSE) — naming it would close four `unrecovered` entries at once. Neither is a vtable Impl and
    neither is a branch thunk.
51. **`0x103567808` is worth one more attempt.** Slot 58 passes it as the 4th argument to the shared
    Task helper `0x101a03fd4` and `name_type_at_addr` mis-decodes it. Slot 81 passes `0x103567a30` in
    the SAME argument position and that one DOES decode as an AsyncFunctionPointer
    (`{rel32 -> 0x1019b1ff4, ExpectedContextSize 0x20}`). Same slot, same shape — re-attack `0x103567808`
    with the AsyncFunctionPointer reading.
52. **Two module-wide shared helpers are now pinned by four verdicts:** `0x101a04674` (392 B, 98 instr,
    27 direct callers, the `assumeIsolated`-shaped one) and `0x101a03fd4` (652 B, 163 instr, 53 direct
    callers, the `Task`-creating one). Both NOT IN TRIE, neither a class member. They are the highest
    fan-in unnamed bodies left in KSPlayer.
53. Fix queue, coupled — **build both before staging either**: `KSPlayerLayer.seek(time:)` (`:601`)
    and `VideoPlayerView.change(definitionIndex:)` (`:371-373`). Re-derive the slot-64 claim first.
54. The `startRecord` CRITICAL, **A · KSOptions**, the `T!` vs `T?` normalizer, Package F init bodies,
    MetalPlayView/`Drawable`, `PixelBufferProtocol`'s 40 requirements, and `Anime4KPreset`'s 11
    undecoded shader-path arrays are unchanged. See the s84 and s89 handoffs.

## What NOT to wave, in any session

55. **Source edits.** The pre-commit `l2_field_gate` blocks on the CLASS, not on your diff, so two
    "independent" edits in one file serialise anyway. Land derivations as specs during the wave, then
    apply them one unit and one commit at a time.
56. **Class-shape changes that ripple to consumers** (DisplayModel's `(frame:encoder:)` arity,
    VideoPlayerView's stored-property set, FFmpegDecode's signature). Single-threaded.
57. `GENERATED_ACCESSOR` (322 slots) is not a candidate at all: it collapses into declarations.

## Close out

58. Adjudicate every body with `adjudicate_verdict.py --id … --final … --evidence …` (never delete
    `binary_addr` to pass the provenance guard). Its guard requires a `decompile_cache` block with
    `verbatim: true`, and `verdict_provenance_gate.py` additionally requires the prefetch sidecar to
    EXIST on disk — so run `prefetch_decompiles.py` for each unit even when you read the body from the
    disassembler. s91 did this once for all 6 planned units in a single run against a small hand-built
    worklist (`reconstruction/s91_standup_units.json`), whose shape is
    `{"units": [{id, address, class, subsystem, kind, symbol, demangled_sig, slot, instr}]}` — note
    `address`, not `addr`, and note the top-level `units` key; a bare list makes the tool die with
    `'list' object has no attribute 'get'`. Do not hand-annotate that cache (P27). Run
    `verdict_provenance_gate.py --class <C>` on every class you touch.
59. Update `reconstruction/handoff_baseline.json` with a `captured_session92` block and refresh `head`,
    `ahead_origin`, `faithful_floor`, `stood_up_floor`, `wave_standup_size` and `wave_audit_size`.
    **Re-run `recon_gate --mode handoff` AFTER updating the baseline.** Take `ahead_origin` from
    `git rev-list --count origin/forward..forward`.
60. Record how many bodies landed, the verdict split, and every premise refuted — the refutations have
    been the highest-value output of the last twenty sessions, above the code. Then write the
    session-93 handoff from the FINAL state, not by patching a mid-session draft. **Do not write the
    takeover prompt into it — give the prompt in chat.**
