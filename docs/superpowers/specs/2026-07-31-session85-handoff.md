# Session 85 work

Session 84 ran the audit fan-out. **29 of the 31 AUDIT_ONLY bodies are audited: 7 FAITHFUL, 22
DIVERGENT.** Two remain and they are step 9. The fan-out's real output is the refutation list in
steps 20-27 — read it before you plan anything.

Note on filenames: this file is dated from the real clock (2026-07-31). The session-84 handoff is
named `2026-08-09-...`, a later date than today, so **filenames in this directory do not sort in
session order**. Order by the session number, not the date.

## Verify first

1. **Run `ps -Ao pid,etime,command | grep -c "MacOS/claude --output-format stream-json"` FIRST.**
   Sessions 81 and 82 ran concurrently and clobbered each other's close-out pins. The count is not
   the session count: one live session shows up as 4 lines (a disclaimer wrapper, its child, the
   grep, and the shell). Print the processes with `ps -Ao pid,ppid,etime,command | grep MacOS/claude`
   and check for a second unrelated parent/child pair before touching `reconstruction/` or `forward`.
2. Run `python3 scripts/recon_gate.py --mode handoff` from `/Users/jweaver/Desktop/Work/swift/play` —
   expect **PASS 31 / ANOMALY 0 / FAIL 3**. The 3 FAILs are known debt: `agg_critical 14`,
   `agg_high 48`, `agg_unresolved 1`. Floor **299**.
3. **The critical/high counts nearly tripled and that is the correct outcome, not a regression.**
   s84 opened with `agg_critical 5 / agg_high 17` and closed at 14 / 48. Every new entry is a
   measured divergence in a body that was already written; no source line changed this session.
4. Run `python3 scripts/recon_progress.py`. Its STAGES block is hand-maintained prose and is still
   wrong in both directions. The "blocked on unresolved symbols 283" line is a hardcoded literal at
   `recon_progress.py:105` and is still unverified.
5. **The two-repo split.** Swift sources, the `forward` branch and these handoffs live in
   `/Users/jweaver/Desktop/Work/swift/KSPlayer`. The cwd `/Users/jweaver/Desktop/Work/swift/play`
   holds `scripts/` and `reconstruction/`, both gitignored there. Address KSPlayer with `git -C`;
   run every `scripts/` command from `play`. **s84 changed no source, so `head` and `ahead_origin`
   move only by this handoff's own commit.**
6. Read `reconstruction/handoff_baseline.json` block `captured_session84`, then the 29 verdicts
   matching `reconstruction/verdicts/*_s84.json`. The s80-s83 durables remain valid background
   EXCEPT where steps 20-27 refute them.

## The work

### The two unaudited bodies (do these first)

7. **`VideoPlayerView.setupUIComponents()` slot 40 @`0x101b2c1bc`, 541 instr**, source
   `VideoPlayerView.swift:180`. Cache `VideoPlayerView_slot40_101b2c1bc_s81` is already on disk.
8. **`FFmpegDecode.decodeFrame(from:completionHandler:)` slot 13 @`0x101a2220c`, 677 instr**, source
   `FFmpegDecode.swift:40`. Cache `FFmpegDecode_slot13_101a2220c_s81` is on disk. This is the only
   MEPlayer body in the backlog; read FFmpeg struct fields BY NAME from
   `/Users/jweaver/Desktop/Work/swift/FFmpegKit/.Script/` (a SIBLING of KSPlayer, not inside it).
9. Dispatch one gathering agent per body against
   `scratchpad/AGENT_PROTOCOL.md` (regenerate it from this handoff if the scratchpad is gone; the
   return-format rule is what keeps the orchestrator's context affordable). Verify every load-bearing
   claim yourself, write and adjudicate both verdicts, then the backlog is 31/31.

### The tool units this fan-out specified

10. **`vtable_walk.py` resolves a class name to the WRONG descriptor when two modules declare the
    same simple name.** `reconstruction/classmap_1.3.17.jsonl` line 877 is `PlayerView`/Notelet
    desc `0x1039e919c` and line 913 is `PlayerView`/KSPlayer desc `0x1039ee210`; `lookup_desc`
    returns the first, so `vtable_walk.py PlayerView` answers `refused: no-vtable`. KSPlayer's
    PlayerView walks normally — VTableOffset 15 words, VTableSize 25, metadata+0x108 = slot 18.
    **Unit:** make `lookup_desc` take a module, prefer KSPlayer, and ERROR on ambiguity rather than
    silently taking the first. Then re-run every class in the corpus (MEMORY rule 50) and diff.
11. **`body_fingerprint.py`'s `DISPATCH OFFSETS` line conflates three different things** and it cost
    time in every wave: real metadata offsets, witness-table byte offsets, and plain adrp-page
    displacements into `__DATA` / `__objc_selrefs` / `__got`. In `IOSVideoPlayerView.updateUI(isLandscape:)`
    only 1 of 10 was a dispatch; in `KSAVPlayer.play()` 0 of 6 were. **Unit:** classify each offset by
    the section its effective address lands in and label it, or drop the ones that are not dispatches.
12. **`decode_string_literal.py` misses counts that are computed rather than `mov`/`movk`-paired**,
    and attaches spurious counts to unrelated adrp targets. It failed on FileLog.log, KSPlayerLayer
    slot 68 and BrightnessVolume slot 8 — three of the four bodies with interesting literals.
    **Unit:** model the `orr`/`add`-derived count registers, and add the `_StringObject` 32-byte bias
    direction (proved on FileLog.log: the add-side string's length matches the count word, the
    sub-side's does not).
13. **The trie's field-offset coverage is partial and that is now measured.** Of KSPlayerLayer's 17
    fields only 7 export a `vpWvd` symbol; `isAutoPlay`, `isWirelessRouteActive`, `bufferedCount`,
    `shouldSeekTo` and `bufferingStartTime` export none, and KSOptions exports none at all while its
    metadata field-offset vector is all-zero in the file. **Unit:** a resolver that names a
    field-offset global from (a) the field-record order plus (b) an anchor site — the pattern that
    worked here is `pause()` @`0x1019ccb3c`, whose first instruction pair stores `wzr` through
    `0x104c63520`, pinning it as `isAutoPlay` against source `:325`.
14. Step 22 of the s84 handoff is still open: teach `l2_field_gate`'s `merge_binary_type` to fall
    back to the trie's `.setter`/`.getter` symbol type when there is no mangled property symbol.
    KSPlayerLayer has 11 REAL_FLAGs and 7 UNCHECKED fields waiting on it.

### The fix queue this fan-out produced

15. Each of these is its own unit and its own commit (MEMORY rule 20). They are ordered by how
    cheaply the binary settles them, not by severity.
16. **`FileLog.log`** (`KSOptions.swift:911`): one line. The binary calls the throwing generic
    `FileHandle.write<T: DataProtocol>(contentsOf:)` and drops the error; the source calls
    `fileHandle.write(data)`.
17. **`CMTime.init(seconds:)`** (`Utility.swift:307`): the binary's inlined site passes
    preferredTimescale 1,000,000,000; the source passes `Int32(USEC_PER_SEC)` = 1,000,000.
18. **`KSPlayerLayer.seek(time:)`** (`:601`): the binary's slot 64 is `seek(time:completion:)` and it
    forwards the caller's completion into the 3-argument overload; the source declares
    `seek(time:)` and supplies a fresh empty closure.
19. **`VideoPlayerView.change(definitionIndex:)`** (`:371-373`): replace the trailing guarded
    `seek(time:)` with `asset.options.startPlayTime = shouldSeekTo` BEFORE the `super.set` call.
    KSOptions+0x30 = `startPlayTime`, read from its own `vpWvd` at `0x103567480`.

## Premises REFUTED in s84 — do not re-derive

20. **"PlayerView has no vtable"** (s81 durable, carried into s84). FALSE, and the reason recorded
    for it was wrong — see step 10. The class-object offsets s81 read were correct; the tool was
    answering about the wrong class.
21. **KSPlayerLayer has a method the reconstruction has never had.** `metadata+0x2a8` → slot 58 →
    `0x1019cc0ac` = `KSPlayer.KSPlayerLayer.change(state: KSPlayer.KSPlayerState) -> ()`
    (OWNER_MATCH). `grep 'func change' KSPlayerLayer.swift` returns only `changeLoadState` and
    `changeBuffering`. Every `state` write routes through it plus the Combine Published setter.
22. **The binary's `state` observer logs different text than the source's.** The inlined willSet
    emits `'state change <old> -> <new>'`; source `:184` spells
    `KSLog("playerStateDidChange - \(newValue)")`.
23. **`MediaPlayback` requirement 14's KSAVPlayer implementation is named `stop()`**, while the
    source protocol declares `shutdown()` (`MediaPlayerProtocol.swift:23`) and KSAVPlayer implements
    `shutdown()` (`:406`). Same slot, different member name.
24. **KSPlayerLayer's field records do not match the source's stored properties.** Binary:
    `_bufferingProgress`, `_loopCount`, `_state`, `subtitleView`, `playerTickClock`, `playerTickTask`,
    `subtitleModel`, `bufferingStartTime`, `isAutoReplaceAndConstrainPlayerView`. Source instead has
    `isPipActive`, `timer`, `urls`, and calls field 14 `startTime` where the binary calls it
    `bufferingStartTime`.
25. **`IOSVideoPlayerView.originalOrientations` does not exist in the binary.** Its FieldDescriptor
    holds 65 records and 0-3 are `originalSuperView`, `originalframeConstraints`, `originalFrame`,
    `fullScreenDelegate`; `export_trie_oracle --class IOSVideoPlayerView --field originalOrientations`
    returns `access UNKNOWN`, and slot 145's extent sends no `supportedInterfaceOrientations`
    selector.
26. **`VideoPlayerView.longPressGesture` does not exist in the binary** — absent from all 20 field
    records and from all 152 trie symbols, while its three siblings are present as vpfi defaults.
27. **Two bodies schedule through `Task` + `Task.sleep` where the source calls directly.**
    `BrightnessVolume.appearView` uses `Task.sleep(nanoseconds: 3_000_000_000)` where the source uses
    `DispatchQueue.main.asyncAfter(deadline: .now() + 3)`; `KSPlayerLayer.audioInterrupted` sleeps
    800,000,000 ns before `play()` where the source calls `play()` outright. There is no libdispatch
    symbol in either body.

## The measured shape of the divergence

28. **The DisplayModel family takes `(frame:encoder:)`, the source takes `(encoder:)`.** Both
    `PlaneDisplayModel` slot 17 and `SphereDisplayModel` slot 26 are arity-2 in the binary;
    `grep -rn 'func set(frame' Sources/` returns nothing. `PlaneDisplayModel.pipeline` likewise takes
    a `PixelBufferProtocol` existential where the source takes `(planeCount:bitDepth:)`. This is a
    class-shape job, not a statement job.
29. **KSPlayerLayer's lifecycle methods are the worst cluster.** `play` slot 60, `stop` slot 63,
    `set(url:options:)` slot 55, `prepareToPlay` slot 68, `readyToPlay` slot 69, `changeLoadState`
    slot 70, `finish` slot 74 and `pause` slot 61 (s81) are all DIVERGENT, most of them by whole
    statements in both directions. Treat KSPlayerLayer.swift as unreliable until it is re-derived.
30. **What IS faithful is small and self-contained**: `BrightnessVolume.move(to:)` and
    `.volumeIsChanged`, `KSPlayerResource.hash(into:)`, `PlayerView.onButtonPressed(type:button:)`,
    `KSPlayerLayer.wirelessRouteActiveDidChange`, `KSAVPlayer.play()`,
    `SphereDisplayModel.touchesMoved`. Bodies with one or two statements and no lifecycle role.

## Still blocked, and on what

31. `Coordinator.player(layer:currentTime:totalTime:)`, the `startRecord` CRITICAL, **A · KSOptions**,
    the `T!` vs `T?` normalizer, Package F init bodies, KSComplexPlayerLayer, MetalPlayView/`Drawable`,
    and extending the classmap to structs and enums are all unchanged. See s84-handoff steps 26-32.

## Close out

32. Adjudicate every body you audit with `adjudicate_verdict.py` (MEMORY rule 41). Never delete
    `binary_addr` to get a verdict past its provenance guard (rule 81). Run
    `verdict_provenance_gate.py --class <C>` on every class you touch.
33. Update `reconstruction/handoff_baseline.json` with a `captured_session85` block and refresh
    `head`, `ahead_origin` and `faithful_floor`. **Re-run `recon_gate --mode handoff` AFTER updating
    the baseline.** Take `ahead_origin` from `git rev-list --count origin/forward..forward`.
34. Record how many bodies landed, the FAITHFUL/DIVERGENT split, and every premise the session
    refuted — the refutations have been the highest-value output of the last fourteen sessions,
    above the code. Then write the session-86 handoff in this format at `docs/superpowers/specs/`,
    from the FINAL state rather than by patching a mid-session draft. **Do not write the takeover
    prompt into it (MEMORY rule 77) — give the prompt in chat.**
