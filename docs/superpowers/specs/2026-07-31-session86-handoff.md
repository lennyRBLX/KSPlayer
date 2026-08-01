# Session 86 work

Session 85 closed the AUDIT_ONLY backlog: **31 of 31 bodies are audited.** Both remaining bodies
came back DIVERGENT, so the floor did not move — that is the arithmetic working, not a stall.
Three source commits landed. The tool units (steps 8-13) and two of the four fix-queue units
(steps 15-16) were NOT done this session and are the largest remaining block of specified work.
Steps 25-27 say which of it is safe to run N-wide and which is not.

Note on filenames: this file and the session-85 handoff are BOTH dated 2026-07-31 (the real clock).
Filenames in this directory do not sort in session order. **Order by the session number.**

## Verify first

1. Run `ps -Ao pid,etime,command | grep -c "MacOS/claude --output-format stream-json"` FIRST. One
   live session prints **4** lines (a disclaimer wrapper, its child, the grep, the shell). Print
   `ps -Ao pid,ppid,etime,command | grep MacOS/claude` and confirm there is no SECOND unrelated
   parent/child pair before touching `reconstruction/` or `forward`. Sessions 81 and 82 ran
   concurrently and clobbered each other's close-out pins.
2. Run `python3 scripts/recon_gate.py --mode handoff` from `/Users/jweaver/Desktop/Work/swift/play`
   — expect **PASS 31 / ANOMALY 0 / FAIL 3**. The 3 FAILs are known debt: `agg_critical 15`,
   `agg_high 55`, `agg_unresolved 1`. Floor **299**.
3. **The floor did not move this session and that is correct.** Both bodies audited in s85 were
   DIVERGENT, so 299 is unchanged from s84. `agg_critical` 14 -> 15 and `agg_high` 48 -> 55 are the
   eight new divergences those two audits MEASURED (1 CRITICAL + 7 HIGH; the two verdicts also
   carry 3 MED and 4 LOW). No source line was changed by an audit.
4. Run `python3 scripts/recon_progress.py`. Its STAGES block is hand-maintained prose and is still
   wrong in both directions. The "blocked on unresolved symbols 283" line is a hardcoded literal at
   `recon_progress.py:105` and is **still unverified** — it has been carried unchecked since s80.
5. **The two-repo split.** Swift sources, the `forward` branch and these handoffs live in
   `/Users/jweaver/Desktop/Work/swift/KSPlayer`. The cwd `/Users/jweaver/Desktop/Work/swift/play`
   holds `scripts/` and `reconstruction/`, both gitignored there. Address KSPlayer with `git -C`;
   run every `scripts/` command from `play`. FFmpegKit is a SIBLING of KSPlayer at
   `/Users/jweaver/Desktop/Work/swift/FFmpegKit`, not inside it.
6. Read `reconstruction/handoff_baseline.json` block `captured_session85`, then the two verdicts
   `reconstruction/verdicts/VideoPlayerView_setupUIComponents_slot40_s85.json` and
   `reconstruction/verdicts/FFmpegDecode_decodeFrame_slot13_s85.json`. The s80-s84 durables remain
   valid background EXCEPT where steps 17-22 refute them.
7. **The gathering-agent protocol now lives at `reconstruction/AGENT_PROTOCOL.md`, not in
   `scratchpad/`.** s85 found the scratchpad copy gone at takeover and had to regenerate it. The new
   location is durable, beside `AUDIT_AGENT.md` and `DISPATCH_CONTRACT_s64.md`, which both survived.

## The tool sweeps — what s85 LANDED

**Two new tools and one repaired tool. `scripts/` is gitignored in KSPlayer, so none of this is in
a commit — it exists only on disk in `play/scripts/`. Re-run each `--selfcheck` at takeover.**

L1. **`scripts/fieldrec.py` — NEW, `--selfcheck` PASS.** Reads Swift reflection FIELD RECORDS
    straight out of the Mach-O: the MEMORY rule 84 authority for every absence claim. Golden is
    anchored on five independently-established answers (VideoPlayerView 20 fields, PlayerView 5,
    FFmpegDecode 9, KSOptions 84, and the `doviProfile` symref). **It decodes the ctrl-0x02
    SYMBOLIC REFERENCE correctly**, which is the trap that cost s85 a commit: a reader that splits
    a mangle on NUL truncates `02 5f 43 4e 00 53 67` to `b'\x02_CN'` and loses both the referent
    (`__got 0x104112A00` -> `_$ss5UInt8VMn`) and the `Sg`. The golden regression-guards that case.
L2. **`scripts/field_presence_sweep.py` — NEW, `--selfcheck` PASS.** The corpus-wide presence diff
    (source stored properties vs binary field records, both directions), with a superclass walk so
    inherited storage is not false-flagged, and `$__lazy_storage_$_x` / `$defaultActor` normalised
    so every correct `lazy var` and `actor` is not reported as a divergence. **RESULT: 118 classes
    swept — 77 clean, 13 with source properties that DO NOT EXIST in the binary (43 fields), 16
    with binary-only fields, 19 with no source declaration.** It independently reproduced three
    refutations it was never told about (`VideoPlayerView.longPressGesture`,
    `IOSVideoPlayerView.originalOrientations`, and KSPlayerLayer's field set), which is the
    strongest evidence it is right. The 13, with their absent fields, are step 8d.
L3. **`scripts/body_fingerprint.py` — ALL THREE DEFECTS FIXED, `--selfcheck` PASS, and MEMORY rule
    50 discharged over the whole corpus (264 bodies with a `binary_addr`: 0 crashes, 0 mojibake).**
    (a) The objc-stub selector decode is now gated on the target lying inside `__objc_stubs`, so a
    plain Swift call into `__text` reads NOT IN TRIE instead of `objc_msgSend[<mojibake>]`.
    (b) An `add rd, rs, #imm` now REBINDS rd to the full effective address. The real defect was a
    STALE REGISTER MAP, not a missing displacement: after `adrp x24,PG` + `add x24,x24,#0x880` the
    map still held PG for x24, so a later zero-offset `ldr` through x24 recovered the PAGE BASE and
    named it (the bogus `YouTubePlayerKit…PlaybackState.allCases` line).
    (c) `DISPATCH OFFSETS` now requires the loaded register to be BLR'd before it is redefined.
    On `VideoPlayerView.setupUIComponents` it went 15 -> **1** (`0x328`), matching the body's single
    `blr`; across all 264 bodies the histogram is now 0:168, 1:59, 2:28, 3:5, 4:4.
L4. **The 13 classes whose source declares storage the binary does not have** (from L2; each is a
    class-shape unit, NOT a statement fix, and each needs its non-field consumers checked too):
    VideoPlayerView 8 (cancellable, navigationBar, titleLabel, subtitleLabel, subtitleBackView,
    originalPlaybackRate, speedTipLabel, longPressGesture) · PlaneDisplayModel 6 (indexCount,
    indexType, primitiveType, indexBuffer, posBuffer, uvBuffer — **this EXPLAINS s84's finding that
    the binary draws with `drawPrimitives`, not `drawIndexedPrimitives`: the index buffers do not
    exist**) · KSPictureInPictureController 5 (binary has ZERO field records) · KSAVPlayer 4
    (the external-playback set) · KSPlayerLayer 4 (_isPipActive, state, urls, startTime) ·
    Coordinator 2 · MetalPlayView 2 · PlayerView 1 (srtControl) · AudioGraphPlayer 1 ·
    FFmpegAssetTrack 1 · MetalView 1 · AudioFrame 1 · IOSVideoPlayerView 1.
L5. **The UNCHECKED hole is now MEASURED corpus-wide: 205 of 803 source stored properties (25.5%)
    across 33 classes are written `var x = …` with no annotation and are therefore invisible to the
    type gate.** Worst: KSOptions 62/84, IOSVideoPlayerView 23/64, MEPlayerItem 20/42,
    VideoPlayerView 19/27, PlayerToolBar 12/16. This is far larger than the 11 REAL_FLAGs of step 12
    and it does not appear in any FAIL count. Annotating them from the binary's field records is
    mechanical and deterministic — but it is a SOURCE edit, so per step 27 it must be done
    per-class with its own build and commit, and must NOT be waved across agents.

## The tool units — still open

8. **`vtable_walk.py` resolves a class name to the WRONG descriptor when two modules declare the
   same simple name.** RE-VERIFIED in s85 against the binary: `reconstruction/classmap_1.3.17.jsonl`
   line 877 is `PlayerView`/Notelet desc `0x1039e919c` and line 913 is `PlayerView`/KSPlayer desc
   `0x1039ee210`; `lookup_desc` returns the first. **Unit:** make `lookup_desc` take a module, prefer
   KSPlayer, and ERROR on ambiguity rather than silently taking the first. Then re-run every class in
   the corpus (MEMORY rule 50) and diff. `fieldrec.desc_for_class` already implements exactly this
   contract (prefer KSPlayer, raise on ambiguity) — copy it rather than reinventing it.
9. **`body_fingerprint.py`'s remaining gap.** L3 fixed the three measured defects, but the tool
   still reports a dispatch only when the destination register is BLR'd inside the SAME extent; a
   tail-called or outlined dispatch would be missed. No body in the 264-body rule-50 run showed
   that shape, so it is a known limit rather than an observed bug. **Unit:** add a golden with a
   tail-call body if one is ever found.
10. **`decode_string_literal.py` misses computed counts** and attaches spurious counts to unrelated
    adrp targets — it failed on FileLog.log, KSPlayerLayer slot 68 and BrightnessVolume slot 8.
    **Unit:** model the `orr`/`add`-derived count registers, and add the `_StringObject` 32-byte bias
    direction. s85 decoded four literals in slot 40 BY HAND from the `mov`/`movk` immediates
    ("play.fill", "arrow.counterclockwise", "lock.open", "lock") — that hand method is the spec.
11. **The trie's field-offset coverage is partial.** Of KSPlayerLayer's 17 fields only 7 export a
    `vpWvd` symbol; KSOptions exports none at all. **Unit:** a resolver that names a field-offset
    global from (a) field-record order plus (b) an anchor site — the proven pattern is `pause()`
    @`0x1019ccb3c`, whose first instruction pair stores `wzr` through `0x104c63520`, pinning it as
    `isAutoPlay` against source `:325`.
12. Teach `l2_field_gate`'s `merge_binary_type` to fall back to the trie's `.setter`/`.getter` symbol
    type when there is no mangled property symbol. KSPlayerLayer has 11 REAL_FLAGs and 7 UNCHECKED
    fields waiting on it. **Note:** s85 measured KSOptions at `PASS 22 · UNCHECKED 62 · REAL_FLAG 0`
    — 62 of 84 fields are unverifiable purely because the source writes `var x = …` without an
    annotation. That is a bigger hole than the 11 REAL_FLAGs and it is invisible in the FAIL counts.
13. **DONE in s85 — see L1.** `scripts/fieldrec.py` now exists with a `--selfcheck` golden,
    including the ctrl-0x02 symref regression guard. Nothing is open here.

## The fix queue — two of four landed

14. Steps 15-16 are what remains of the s85 fix queue. Each is its own unit and its own commit
    (MEMORY rule 20). **Landed in s85:** FileLog.log (67f4cec), CMTime.init(seconds:) (d23612a), plus
    an unplanned prerequisite, KSOptions.doviProfile (85bb872).
15. **`KSPlayerLayer.seek(time:)`** (`KSPlayerLayer.swift:601`): the binary's slot 64 is
    `seek(time:completion:)` and it forwards the caller's completion into the 3-argument overload;
    the source declares `seek(time:)` and supplies a fresh empty closure at `:602-603`. **Verify the
    slot-64 claim against the binary before editing (MEMORY rule 68) — s85 did not re-derive it.**
16. **`VideoPlayerView.change(definitionIndex:)`** (`VideoPlayerView.swift:371-373`): replace the
    trailing guarded `seek(time: shouldSeekTo) { _ in }` with
    `asset.options.startPlayTime = shouldSeekTo` BEFORE the `super.set` call. KSOptions+0x30 =
    `startPlayTime`, read from its own `vpWvd` at `0x103567480`. **These two are coupled** — :372
    currently calls a two-argument `seek(time:)` with a trailing closure, so changing the
    KSPlayerLayer declaration in step 15 can break or fix this call site. Build both before staging
    either.

## Premises REFUTED or CORRECTED in s85 — do not re-derive

17. **`VideoPlayerView.navigationBar`, `.titleLabel` and `.speedTipLabel` DO NOT EXIST in the
    binary**, and neither do `.subtitleLabel` or `.subtitleBackView`. Established from the FIELD
    RECORDS (the MEMORY rule 84 authority), read directly out of the Mach-O: VideoPlayerView's
    FieldDescriptor `0x103cbf530` holds exactly **20** records and none of the five is among them;
    superclass PlayerView (KSPlayer, desc `0x1039ee210`) holds **5** (playerLayer, delegate, toolBar,
    playTimeDidChange, backBlock) and has none of them either. The source declares all five ON
    VideoPlayerView at `:78`, `:79`, `:80`, `:81`, `:109`. This is the same class of refutation as
    s84's `originalOrientations` / `longPressGesture`, but it is now established from field records
    rather than from the trie, and it carries ~9 source statements.
18. **`setupUIComponents` is three statements shorter at the tail than the source.** The tail is
    exactly `bl 0x101b2ed64` (addConstraint, unnamed in trie, identified by its OWN body — it opens
    with the `setThumbImage:forState:` pair of `:753-757`), then ONE `blr` through metadata+`0x328`
    = slot 41 = `customizeUIComponents()`, then `layoutIfNeeded`. **`setupSrtControl()` is never
    called**, and it is not inlined into either function.
19. **The cleanest corroboration found in s85, and a template worth reusing:** `addConstraint`
    @`0x101b2ed64` emits **9** `setTranslatesAutoresizingMaskIntoConstraints:` where its own source
    `:765-775` has **11** — short by exactly `navigationBar` and `titleLabel`. A count taken in a
    DIFFERENT function independently confirmed the absence.
20. **`FFmpegDecode.decodeFrame`'s SIGNATURE diverges.** The binary takes
    `from: UnsafeMutablePointer<__C.AVPacket>` (mangled `SpySo8AVPacketVG`); the source takes
    `from packet: Packet`, and `Packet` is a `final class` at `Model.swift:232` (mangling
    `AA6PacketC`). Proved at the mangle level, so MEMORY rule 51 is satisfied. Every
    `packet.assetTrack` / `.corePacket` / `.size` / `.position` access in the source body has no
    counterpart reachable from a bare AVPacket pointer.
21. **`FFmpegDecode`'s FFmpeg call set is not the source's.** Oracle-CONFIRMED in the extent:
    `avcodec_free_context` @`0x102d53ac8` (called TWICE), `avcodec_receive_frame` @`0x10294dba0`,
    `avcodec_flush_buffers` @`0x10294d260`. The source's decodeFrame calls neither free_context nor
    flush_buffers. `0x102a1a424` is called four times and is **UNKNOWN** — `--candidate
    avcodec_send_packet` is REFUTED with its sole mismatch at index 11, `ldr w8,[x21,#0x154]` vs the
    indexed lib's `ldr w8,[x21,#0xa4]`: the same instruction against a different AVCodecContext
    layout. **A re-index is NOT the fix, and s85 proved it:** Forward's own version strings are
    `Lavc62.28.101` / `Lavf62.12.101`, and the xcframeworks `ffmpeg_name_oracle.LIBS` already indexes
    (`FFmpegKit/Sources/Libav*.xcframework/ios-arm64/…`) carry exactly `Lavc62.28.101` /
    `Lavf62.12.101`. Same version on both sides, so VERSION SKEW IS REFUTED as the explanation and
    re-indexing would be a no-op. **Unit:** find the real cause — either a build-CONFIGURE
    difference that moves an AVCodecContext field between two same-version builds, or the
    simpler possibility that `0x102a1a424` is genuinely NOT avcodec_send_packet. Until one of those
    is established, the oracle's REFUTED verdict stands at face value and the callee stays UNKNOWN.
    Do NOT assume the name.
22. **The nine-way side-data dispatch is not in `decodeFrame`.** The AVFrameSideDataType values from
    `FFmpegKit/.Script/FFmpeg-n8.1.1/libavutil/frame.h` are A53_CC=1, MASTERING_DISPLAY=11,
    CONTENT_LIGHT=14, HDR_PLUS=17, SEI_UNREGISTERED=20, DOVI_RPU=23, DOVI_METADATA=24,
    HDR_VIVID=25, AMBIENT=26. The COMPLETE compare-immediate set of the 677-instruction extent is
    `#0x0, #0x1, #0x2, #0x18`. Seven of the nine never appear. `0x101a67274` IS called at
    `0x101a22984`, confirming the direction of the source's own DEFERRED comment at `:41-45`.
23. **`FFmpegDecode` has a vtable method the source class lacks:** slot 18 = `0x101a23404`, NOT IN
    TRIE (unnamed, not absent). The source declares exactly five members. `decodeFrame` calls it at
    `0x101a22630`. The source comment at `:65-66` calls it a free function; it is a real method.
24. **MEPlayer is under-audited.** `decodeFrame` was the only MEPlayer body in the backlog and it
    diverges in signature, call set, a ~70-line block, error/logging behaviour AND class shape. Treat
    the rest of MEPlayer as unverified.

## What is safely BATCHABLE, and what is not

This is the s85 answer to "what else can be waved without hurting disassembly matching". The
dividing line is not size, it is **who writes**. An agent that only READS is safe to run N-wide; a
deterministic tool is better still, because it has no hallucination surface and costs no tokens.

25. **Safe to wave — the body-audit fan-out, unchanged.** One body per agent, the raw-output
    envelope in `reconstruction/AGENT_PROTOCOL.md`, orchestrator writes and adjudicates every
    verdict. Proven in s84 (29 bodies) and s85 (2 bodies). Ready pool: `REAL_METHOD` 234 total /
    50 ready and `COMPUTED_ACCESSOR` 108 total / 55 ready, from `classify_accessor_slots`. Bodies
    are independent, agents never write, so there is no shared state to corrupt.
    **One rule to add to the next wave's prompts:** *read the WHOLE source body before writing any
    divergence phrased as an absence in the source.* s85's orchestrator drafted two false claims
    about `decodeFrame` from a partial read (:40-189 of a body that runs to :207) and the agent
    caught both. Give agents the source RANGE, not a starting line.
26. **Better as a deterministic tool sweep than as a wave** — higher value per token than any agent
    wave currently queued, and each is one script over the whole corpus rather than N agents:
    (a) **Field-record vs source-declaration diff for every class in the classmap.** This produced
    BOTH of s85's largest findings essentially for free — the three absent VideoPlayerView
    properties (step 17) and the `doviProfile` type fix (85bb872). It is `fieldrec` + a source
    parser over ~1000 classmap rows. Build it FIRST (step 13).
    (b) The `UNCHECKED` sweep of step 12 — 62 of KSOptions' 84 fields are unverifiable only because
    the source writes `var x = …` with no annotation. Mechanical, per class, deterministic.
    (c) The `ffmpeg_name_oracle` re-index against FFmpeg-n8.1.1 (step 21) — one job that unblocks
    every FFmpeg name in MEPlayer at once.
    (d) The three `body_fingerprint` defects (step 9) — fixing them improves EVERY future audit,
    so it compounds across the whole remaining backlog.
27. **Do NOT wave these.** (a) **Source edits.** The pre-commit `l2_field_gate` blocks on the CLASS,
    not on your diff — s85 had two genuinely independent fixes in one file serialize on each other
    (see step 29 of Close out). Parallel editors would collide on the git index too, which is why
    MEMORY rules 61-62 exist. (b) **Class-shape jobs** — DisplayModel's `(frame:encoder:)` arity,
    VideoPlayerView's stored-property set, FFmpegDecode's signature — each ripples through
    consumers and must be single-threaded. (c) **Several bodies of ONE class into one agent.** s84
    batched by class only to amortise the vtable walk, and still kept one body per agent; merging
    them cross-contaminates findings between bodies.

## Still blocked, and on what

28. `Coordinator.player(layer:currentTime:totalTime:)`, the `startRecord` CRITICAL, **A · KSOptions**,
    the `T!` vs `T?` normalizer, Package F init bodies, KSComplexPlayerLayer, MetalPlayView/`Drawable`,
    the DisplayModel `(frame:encoder:)` class-shape job, and extending the classmap to structs and
    enums are all unchanged. See s84-handoff steps 26-32 and s85-handoff steps 28-31.

## Close out

29. Adjudicate every body you audit with `adjudicate_verdict.py` (MEMORY rule 41). Never delete
    `binary_addr` to get a verdict past its provenance guard (rule 81). Run
    `verdict_provenance_gate.py --class <C>` on every class you touch.
30. **The pre-commit `l2_field_gate` blocks on the CLASS, not on your diff.** s85 lost a commit to a
    pre-existing `doviProfile` block in a file it was editing for an unrelated reason. When that
    happens, check whether a FAITHFUL spelling exists before reaching for `--no-verify`: MEMORY rule
    47 only authorises it when no faithful spelling satisfies the gate. Land the blocker as its own
    commit first.
31. Update `reconstruction/handoff_baseline.json` with a `captured_session86` block and refresh
    `head`, `ahead_origin` and `faithful_floor`. **Re-run `recon_gate --mode handoff` AFTER updating
    the baseline.** Take `ahead_origin` from `git rev-list --count origin/forward..forward`.
32. Record how many bodies landed, the FAITHFUL/DIVERGENT split, and every premise the session
    refuted — the refutations have been the highest-value output of the last fifteen sessions, above
    the code. Then write the session-87 handoff in this format at `docs/superpowers/specs/`, from the
    FINAL state rather than by patching a mid-session draft. **Do not write the takeover prompt into
    it (MEMORY rule 77) — give the prompt in chat.**
