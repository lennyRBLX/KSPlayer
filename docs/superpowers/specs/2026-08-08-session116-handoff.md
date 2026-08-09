# Session 116 handoff — 5 verdicts closed (+D2 of a sixth), and a concurrency hazard

Take state from `python3 scripts/recon_gate.py --mode handoff`, never from this file. The numbers
below are what I measured at the end of s116; re-derive them.

|                | takeover | end of s116 |
|----------------|----------|-------------|
| CRITICAL       | 6        | 6           |
| HIGH           | 24       | **18**      |
| MED            | 17       | **16**      |
| LOW            | 13       | **11**      |
| UNRESOLVED     | 1        | 1           |
| faithful floor | 356      | **361**     |

## ⚠️ READ THIS FIRST — several sessions were running on this repo at once

s116 lost a lot of time attributing peer-session writes to rogue subagents. Peer `423a9ab5`
authored commits `21ba771` (CustomProgressView) and `7942514` (KSVideoPlayerModel) and was staging
`PointerImagePipeline.swift`; peer `bd0d87c3` was also live. Every session commits under the same
git identity, so `git log --format=%an` cannot separate them.

Two concrete hazards, both hit:

1. **The git index is shared.** `git add <my-file>` followed by `git commit` swept a peer's
   in-progress file into commit `703f761`, which then contained a tree that had never been built.
   Undone with `git rm --cached` + `commit_unit.sh --amend` → `678f209`.
   **Fix: commit with a pathspec** — `scripts/commit_unit.sh -F <msg> -- <explicit path>`. That
   commits only your paths regardless of what else is staged, and does not disturb the peer's
   staging. Used for `9948bcb`; it works.
2. **Builds collide.** `validate_build.sh` fails with `unable to attach DB … database is locked`.
   Retry once; it is not your bug.

Detection: `ls -lt /private/tmp/claude-501/-Users-jweaver-Desktop-Work-swift-play/` — every dir that
is not your own session id is a peer. Their `scratchpad/` names their in-flight commits.
Memory: `concurrent-sessions-race-on-one-repo`.

## Landed (mine)

Also landed after the list below: `9948bcb` (Anime4KPipeline.loadPreset), `05d095f`
(IOSVideoPlayerView.updateUI — all 342 instructions) and `0e3f556`
(canPreload -> canContinuePreload, which closes D2 of LimitSeparatePreLoadIOContext.more).

- `528dccf` KSOptions idx128-130 placement. `wantedAudio`/`audioFrameMaxCount`/`isAudioRateByFilter`
  moved between `syncDecodeAudio` and `fontsDir`, matching vtable order. The file's own comment
  block had asserted that position for sessions while declaring them ~460 lines away.
  **Still misplaced and NOT in that verdict:** `playable` (binary idx121, source 464) and
  `wantedSubtitle` (binary idx143, source 677). Separate units.
- `65971b8` `PreLoadIOContext.addTimeIndex` — all 301 instructions. Lower-bound binary search,
  two-sided monotonicity rejection, exact-hit no-op, insert. **Also refuted the source's
  `defer { _timeIndexLock.unlock() }`**: the binary unlocks at 0x101ba7b18 *before* the KSLog at
  0x101ba7b1c, so a function-scope defer is the wrong shape.
- `678f209` `KSPlayerLayer.select(subtitleInfo:isSecondary:)` stood up (was absent entirely).
  Unblocks two `KSVideoPlayerView.openURL` CRITICALs.
- `240952a` AudioDescriptor — all three divergences **refuted**, root relocated to the helper.
- `9948bcb` `Anime4KPipeline.loadPreset` — all 156 instructions, 13-case shader table inlined.

## Derived but NOT landed — start here, do not re-derive

**`KSPlayerLayer_structural_placement_s76` D1 — THE COUNT IS STALE BY NINE.** The verdict says
"KSPlayerLayer carries 11 pre-existing l2_field_gate REAL_FLAGs (subtitleView, _state,
playerTickClock, playerTickTask, bufferingStartTime, subtitleModel,
isAutoReplaceAndConstrainPlayerView, _isPipActive, state, urls, startTime)". Measured now:

    l2_field_gate --file …/KSPlayerLayer.swift --class KSPlayerLayer
    => 19 fields | PASS 4 · UNCHECKED 13 · REAL_FLAG 2
       REAL_FLAG (must resolve): _isPipActive, urls

Nine of the eleven have since resolved to PASS or UNCHECKED. The remaining debt is TWO fields, both
"in source, absent in binary reflection". `_isPipActive` is already acknowledged in-file as
"source-only scaffolding (zero trie hits)"; `urls` (:278) backs `set(urls:options:)`. Removing either
has call-site consequences, so it is still a unit — but a two-field one, not an eleven-field one.

**`openFormatContext` D1 — ITS BLOCKER IS NOT A NAMING BLOCKER, and the verdict cites the wrong
address.** The divergence says the interrupt-callback install "needs the un-reconstructed registry
predicate FUN_101a34af4". Read from disassembly at 0x101a395cc-dc:

    101a395cc  ldr x8, [x19, #0x28]
    101a395d0  ldr x27, [x8, #0x18]          the opaque
    101a395d4  adrp/add -> 0x101a34dc0       the CALLBACK pointer
    101a395dc  stp x8, x27, [x0, #0xd8]      formatCtx->interrupt_callback = {fn, opaque}

The installed callback is **0x101a34dc0**, not 0x101a34af4. 0x101a34dc0 is a 23-instruction
`@convention(c)` thunk: `swift_once` on token 0x1044e9ab8 (init 0x101a349c4), load the static from
0x1044e9ac0 into x20 (swiftself), `bl 0x101a34af4`, `and w0,w0,#1`, return. So 0x101a34af4 is the
PREDICATE the thunk calls, not the callback itself.

And it needs no name: `name_exhaustion_gate --addr 0x101a34af4` returns **INLINE-INSTEAD** — one
call site image-wide, "no independent identity: inline the expression at the call site". So the
verdict's framing ("un-reconstructed registry predicate", implying a naming gate) is wrong twice
over. What is actually required is reading its 69 instructions and inlining them in the closure. Its
call set is `objc_msgSend 'lock'` (0x103464ae0) / `'unlock'` (0x10346e620), 0x1001ad3c4, and runtime
exclusivity/retain — i.e. a locked registry lookup returning Bool, across 6 branches.

**`KSPlayerLayer.readyToPlay(player:)` @0x1019cda08** (1 CRITICAL + 1 HIGH + 2 LOW) — derived this
session, NOT written. 0x1019cda08-0x1019cdf98, 1424 B, 356 instr. Trie:
`readyToPlay<A where A: KSPlayer.MediaPlayerProtocol>(player: A) -> ()` (generic, OWNER_MATCH).

The D1 prologue, read from disassembly:

    1019cda80  ldr x8,[x22,#0x28] / blr    player.view  (MediaPlayerProtocol witness +0x28)
    1019cda9c  bl 0x1019cf5d8              addSubtitle(to: view)
    1019cdaac  str xzr, [x21, x8]          bufferedCount = 0   (x8 = *0x1044e6188)
    1019cdab4  x19 = *0x104c634e0          options
    1019cdc68  bl swift_conformsToProtocol the audioRecognizes walk
    1019cde38  bl swift_allocObject        56-byte closure context, 5 captures at +0x10..+0x30
    1019cde60  bl 0x101a03fd4              the Task creation shim

`0x1019cf5d8` is trie-named `KSPlayerLayer.(addSubtitle in _B3181C2628785004269C41BC3433122F)(to: __C.UIView) -> ()`
— PRIVATE (the `(… in _<discriminator>)` mangling) and **absent from source**, so D1 cannot be written
without standing it up first. That is the unit's real gate.

⚠️ **THE TASK IS REAL, and a naive grep says otherwise.** Searching the extent for
`swift_task_create` / `ScMMa` / `ScPMa` returns NOTHING, which reads as "no Task here" and would have
made me record D1's Task claim as refuted. It is wrapped: `swift_allocObject` builds a 56-byte
context with five captures, and `bl 0x101a03fd4` (NOT_IN_TRIE, 163 instr) is the emitted `Task { }`
shim, called with x0=x1=0 and the async function pointer in x3. Check for the *shape* — allocObject
context + a 5-arg call with two leading nils — not for the runtime symbol name.

REMAINING FOR THIS UNIT: stand up `addSubtitle(to:)`, transcribe the conformsToProtocol walk, and
read the Task closure (prior sessions record it as an async CONTINUATION CHAIN, i.e. several
functions, not one). D3 is already dischargeable as written — the verdict itself says the macOS
window block and the iOS-14.2 PiP block are "correctly absent from an iOS image — platform-gated,
not a divergence."

**`KSPlayerLayer.set(url:options:)` @0x1019cb674** (2 CRITICAL + 1 MED + 1 LOW) — **DERIVED THIS
SESSION, and D3 is outright REFUTED.** 0x1019cb674-0x1019cba60, 1004 B, 251 instr, only 6 branches.

D1 CONFIRMED from the trie: `KSPlayer.KSPlayerLayer.set(url: Foundation.URL, options: KSPlayer.KSOptions?) -> ()`,
OWNER_MATCH, 1 symbol. The parameter IS Optional and `cbz x24` @0x1019cb6fc is its nil test.

⚠️ **D3 IS FALSE.** It claims the KSOptions byte offsets "could not be tool-read … KSOptions emits no
vpWvd globals". Both resolve immediately with the module flag, and KSOptions emits dozens of vpWvd
globals:

    recover_field_offsets --class KSOptions --module KSPlayer --offset 0x45  ->  isAutoPlay
    recover_field_offsets --class KSOptions --module KSPlayer --offset 0x58  ->  playerTypes

THE BODY, read from disassembly:

    1019cb6fc  cbz x24 ->                if let options {
    1019cb71c    str x24, [x22, x21]       self.options = options      (x21 = *0x104c634e0 = options)
    1019cb748    ldrb w21, [x24, #0x45]    options.isAutoPlay
    1019cb75c    strb w21, [x22, x8]       self.isAutoPlay = …         (x8 = *0x104c63520)
                                          }
    1019cb794  blr x21                   the url assignment through [x28+0x10]
    1019cb7c8  ldr x8, [x24, #0x58]      options.playerTypes
    1019cb7cc  ldr x9, [x8, #0x10]       .count
    1019cb7d0  cbz x9 ->                 empty -> fall back
    1019cb7d4    ldp x26, x27, [x8,#0x20]  first element (metatype + witness)
    1019cb7e0    bl 0x1019b20bc            type metadata accessor for KSPlayer.KSAVPlayer
    1019cb7e8    x27 = 0x1041d3f78         KSAVPlayer's MediaPlayerProtocol witness table
    1019cb814  bl swift_getObjectType    type(of: self.player)   (player = *0x104c634f0)
    1019cb818  cmp x0, x26
    1019cb81c  b.eq ->                   same type -> skip construction
    1019cb8ec  bl 0x1034523a4            URL.==  (self.url vs the new url; url = *0x104c634f8)
    1019cb8f0  tbz w0,#0 ->              URLs DIFFER -> assign + replace path
    1019cb8fc    ldrb w8, [x22, x8]        self.isAutoPlay
    1019cb904    b.ne ->                   not auto-play -> epilogue
    1019cb91c    ldr x8, [x8, #0x2b8]      metadata +0x2b8 = vtable slot 60
    1019cb920    b 0x1019cba04             -> Impl 0x1019cc5f8 = KSPlayerLayer.play()   TRIE-NAMED
    1019cb924  (differ) beginAccess w2=0x21 modify on url, assign, endAccess, then 0x1019c9a68

So the shape is: assign options + isAutoPlay when non-nil; pick
`options.playerTypes.first ?? KSAVPlayer.self`; construct a replacement when it differs from
`type(of: player)`; and on the same-URL path call `play()` only when `isAutoPlay`.

STILL UNNAMED (D4, all real trie negatives): 0x1019d5978 (construct-and-store), 0x1019c9a68 /
0x1019c9cd4 (the state helper). 0x104c63520 also refuses `recover_field_offsets`; it is `isAutoPlay`
by role — assigned from the confirmed `options.isAutoPlay` and later gating `play()`, and the class
declares `isAutoPlay` — but that is inference, not a read, so mark it as such if you write it.

**`PlayerView.set(url:options:)` @0x1019fe194** (3 HIGH + 1 MED + 1 LOW), 163 instr, idx18/slot33.
- Its signature MATCHES source (`KSOptions` non-optional). The KSPlayerLayer Optional shape does
  **not** carry over — the mangles differ by exactly `CSg` vs `Ct`.
- D1: binary branches on `playerLayer != nil` (metadata +0x78 = `playerLayer.getter`); source
  constructs unconditionally. Reuse path compares URLs (`URL.==` @0x1034523a4) then does a
  three-step delegate dance and calls `KSPlayerLayer.set` idx55 @0x1019cb674.
- D2: the nil arm constructs through `KSOptions.playerLayerType` (swift_once @0x1044e51f0), not the
  concrete type, via idx51/slot78 Init @0x1019ca3c4, whose mangle is
  `__allocating_init(url:options:delegate:)` — `options` NON-optional, `delegate` Optional.
- D3: `srtControl` is not merely untouched — it is **absent from PlayerView's reflection field
  records entirely** (NumFields=5: playerLayer, delegate, toolBar, playTimeDidChange, backBlock)
  and no trie symbol names it, while `toolBar` yields four.
- ⚠️ The delegate dance at 0x1019fe2e4-0x1019fe358 WAS read from disassembly this session:
  `tbz w25,#0` skips a `delegate = self` block when the URLs are UNEQUAL, and the common path then
  sets delegate = nil, calls slot-55 `set`, and sets delegate = self again. The ordering really is
  that redundant-looking; it is not a misreading.
- ⛔ **D3 IS WHY THIS FILE STILL CANNOT FLIP, and it is a field-debt unit, not a statement fix.**
  `srtControl` is absent from PlayerView's reflection field records, so the source's
  `public let srtControl = SubtitleModel()` (:68) and `srtControl.url = url` (:168) are both
  divergent — but the property has **15 uses across `VideoPlayerView.swift` and
  `IOSVideoPlayerView.swift`** (selectedSubtitleInfo, subtitleInfos, the srtButton menu, the
  auto-select-embedded-subtitle path). Removing it is a cross-file change with a 15-site blast
  radius and is its own unit. Nothing inside `set(url:options:)` can close it.

  So even with D1 and D2 fully derived and the delegate dance verified, this file is gated on the
  `srtControl` field-debt sweep. Budget that first, or accept that writing D1+D2 moves no counter
  (the verdict flips per FILE).

**`IOSVideoPlayerView.updateUI(isLandscape:)` @0x101b08f3c** (2 HIGH + 1 LOW) — best-positioned
remaining target, and **the expensive half is now done**. 0x101b08f3c-0x101b09494, 1368 B, 342 instr.
**All eight constraint properties already exist** at IOSVideoPlayerView.swift:144-151, so nothing is
blocked on a stand-up.

All 23 `setConstant:` sends (stub 0x103468ea0) are resolved, each guarded by its own `cbz x0`
because the constraints are Optional. Field names come from `field_offset_vector IOSVideoPlayerView`
joined against the offset each `0x1044f0fXX` global holds — **not** guessed from the access site:

    global      offset  field
    0x1044f0f30 0x2d8   topLeftBackgroundLeadingConstraint
    0x1044f0f38 0x2e0   topRightBackgroundTrailingConstraint
    0x1044f0f40 0x2e8   leftBackgroundViewLeadingConstraint
    0x1044f0f48 0x2f0   bottomBackgroundLeadingConstraint
    0x1044f0f50 0x2f8   bottomBackgroundTrailingConstraint
    0x1044f0f58 0x2c8   topStatusLeadingConstraint
    0x1044f0f60 0x2d0   topStatusTrailingConstraint
    0x1044f0f68 0x300   bottomBackgroundHeightConstraint

THREE blocks, and A and C are identical:

    A  0x101b090f4-0x101b091a8   8 sends   15 · -15 · 33 · 15 · -15 · 25 · -25 · 100
    B  0x101b0925c-0x101b092f4   7 sends   20 · -20 · 33 · 20 · -20 · 30 · -30   (NO height send)
    C  0x101b09334-0x101b093e8   8 sends   15 · -15 · 33 · 15 · -15 · 25 · -25 · 100

in the field order listed above (topLeft, topRight, leftBackground, bottomLeading, bottomTrailing,
topStatusLeading, topStatusTrailing, height). ⚠️ The verdict's "15/-15/20/-20/25/-25/30/-30" is
WRONG — there is no 20/-20 in block A at all, `leftBackgroundViewLeadingConstraint` is always 33,
and the height is 100. Two constants are raw doubles, not `fmov` immediates, and must be decoded
rather than read: `mov x8,#0x800000000000 / movk x8,#0x4040,lsl #48` = **33.0** and
`mov x8,#0x4059000000000000` = **100.0**.

THE ARM CONDITIONS ARE ALSO RESOLVED. `mov x19, x0` @0x101b08f5c makes x19 = `isLandscape`. Block A
is gated by `cbz x22` @0x101b090dc, and x22 is `UIDevice.current.userInterfaceIdiom` — the selectors
decode as 0x1034604c0 = `'currentDevice'` and 0x10346e920 = `'userInterfaceIdiom'`, reached from the
`__objc_classrefs` UIDevice entry at 0x104410510. `UIUserInterfaceIdiom.phone` is 0, so `cbz x22`
means **phone takes the non-A path**:

    NOT phone              -> block A   (15 -15 33 15 -15 25 -25 100)
    phone AND isLandscape  -> block C   (identical values to A)
    phone AND portrait     -> block B   (20 -20 33 20 -20 30 -30) then falls into the shared
                                        height send at 0x101b093e8 via `cbnz x0` @0x101b09304

Because A and C are identical this collapses to one rule: **portrait-on-phone gets the 20/30
spacing, everything else gets 15/25, and the height is 100 in all three.** Note the height send on
the B path is reached by `cbnz x0` + `brk #0x1` rather than the `cbz x0, <skip>` used everywhere
else — on that path a nil height constraint TRAPS, i.e. it is force-unwrapped there and optional
everywhere else. That asymmetry is real and must survive into the source.

0x103469d20 decodes as `'setHidden:'`, and its receiver x21 is `topMaskView` — field offset 0x80,
which belongs to **VideoPlayerView**, not IOSVideoPlayerView (whose own fields start at 0xf0). The
phone/portrait arm passes w2 = 1 literally; the phone/landscape arm computes w2 from a count == 0
test (`ldr x22,[x0,#0x10]` / `cmp x22,#0` / `cset w2,eq`).

D2 IS CONFIRMED against the field vector: `maskImageView` (0x168), `landscapeButton` (0x170) and
`lockButton` (VideoPlayerView 0xe0) exist as fields but **no offset global in this extent resolves to
any of them** — the body only ever loads 0x1044f0f30-f68 (the eight constraints) and 0x1044f18a0
(topMaskView @0x80). The source's phone block at :322-337 genuinely has no counterpart.

THE `setHidden:` RECEIVERS ARE ALL RESOLVED. x21 is used for TWO different objects and that is the
trap — do not carry the first binding forward:

    x21 (first, @0x101b08f6c)  self.topMaskView          via global 0x1044f18a0 -> offset 0x80
                                                         (a VideoPlayerView field)
    x25                        self.toolBar              via global 0x1044e7508 -> offset 0x20
    x26                        toolBar.playbackRateButton  global 0x1044e7468 -> PlayerToolBar 0x38
    x28                        toolBar.srtButton           global 0x1044e7438 -> PlayerToolBar 0x8
    x21 (rebound, @0x101b08ff8 and again @0x101b091b0)  toolBar.srtButton

So the writes are:
  · `topMaskView.isHidden = <topBarShowInCase test>`      — matches source :445-449
  · `toolBar.playbackRateButton.isHidden = false` (w2=0)  — matches source :450
  · phone AND portrait:  `toolBar.srtButton.isHidden = true` (w2=1)     — matches source :457
  · phone AND landscape: `toolBar.srtButton.isHidden = <count == 0>`    — matches source :455

x27 IS RESOLVED: global 0x1044e74e8 -> offset 0x8 -> **`PlayerView.playerLayer`**
(`field_offset_vector PlayerView`: playerLayer 0x8, delegate 0x10, toolBar 0x20). So
`ldr x8,[x20,x27]` / `cbz x8, 0x101b0930c` @0x101b091b8 is a nil test on `self.playerLayer`, and the
nil arm sets `toolBar.srtButton.isHidden = true` (w2=1 @0x101b09310).

THE LANDSCAPE `isEmpty` CHAIN IS RESOLVED TOO — and it REFUTES the source's spelling:

    ldr x22,[x8,x9]  with x9 = *(0x104c63500)  ->  KSPlayerLayer.subtitleModel   [vpWvd symbol]
    swift_getKeyPath(0x10356fd18)   0x10345cdd8 -> __got 0x104112ee0 _swift_getKeyPath
    swift_getKeyPath(0x10356fd40)
    0x1034532ec -> __got 0x10410ce50
        Combine.Published._enclosingInstance(_:wrapped:storage:) static subscript GETTER
    ldr x22,[x0,#0x10] / cmp x22,#0 / cset w2,eq        -> `.isEmpty`

So the statement is
`toolBar.srtButton.isHidden = playerLayer.subtitleModel.<@Published ...>.isEmpty`
— reached through `playerLayer.subtitleModel`, NOT through a `srtControl` on the view. That matters
twice over: PlayerView's reflection records carry no `srtControl` at all (PlayerView D3 above), so
the source's `srtControl.subtitleInfos` is wrong on BOTH halves of the path.

THE PROPERTY IS `subtitleInfos`. ⚠️ **An earlier revision of this file said it was NOT, and that was
wrong — the reasoning was unsound and is corrected here.** The bad inference: this tree records
keypath pairs per property in KSSubtitle.swift (`parts` = d1e8/d210, `subtitleInfos` = d140/168,
`flag` = d240/d268, all on page 0x10356d), and this body's pair is 0x10356fd18/0x10356fd40 on a
different page, which I read as "a fourth, unattributed property."

**A keypath PATTERN is emitted per USE SITE, not per property.** The same property referenced from
two files gets two pattern addresses. Address difference proves nothing; you must compare what the
patterns resolve to. Doing that:

    kp 0x10356fd18  root -> 0x103c2e927   value -> 0x103c2e92d
    kp 0x10356d140  root -> 0x103c2e927   value -> 0x103c2e92d    <- IDENTICAL, both fields
    kp 0x10356d1e8  root -> 0x103c2e927   value -> 0x103c2f075    <- `parts`, different value type

(the words at pattern+0x08 / +0x0c are relative pointers; resolve as `addr + offset + word`.) The
shared value descriptor's mangled bytes begin `Say` + a symbolic reference + `_pG`, i.e.
`Array<any Protocol>` — matching `subtitleInfos: [any SubtitleInfo]`, and NOT
`searchedSubtitleInfos: [URLSubtitleInfo]` or `parts: [SubtitlePart]`. The storage keypaths are
byte-identical across all three (`08000080 fdffff03`), which is the generic `_x` backing projection.

So the statement is:

    toolBar.srtButton.isHidden = playerLayer.subtitleModel.subtitleInfos.isEmpty

The source's `srtControl.subtitleInfos.isEmpty` has the right PROPERTY and the wrong PATH — the
binary reaches it through `playerLayer.subtitleModel`, and PlayerView carries no `srtControl` field
at all.

Corroboration, not part of the proof: the only other user of this keypath pair is
`IOSVideoPlayerView.(createSubtitleSubMenu in _99D4461AEE15ECA71DEBF361B80F60DD)(title:isSecondary:)`
@0x101b0e6a4 — a subtitle menu builder, which is what you would expect to read the subtitle list.

Note `field_offset_vector SubtitleModel` cannot help here: the class has `metadata_init=1`, so its
metadata is initialized at RUNTIME and the static image holds no field offsets — it returns 0x0 for
every field, which looks like a real map and is not.

This body is now fully read.

**The UNRESOLVED verdict's premise is dead.** `VideoSwresample_DVbodies_deferral_p3a` defers on
"unverifiable with current tools … NOT protocol witness tables". `decode_witness_table.py` was
built 2026-08-01, two days *after* that verdict. Measured this session:
- PixelBufferProtocol descriptor 0x1039f108c, NumRequirements 40 — confirmed by reading desc+0x10.
- Source declares 22 requirements expanding to exactly 40 ABI slots, and the kind sequence matches
  the binary **position-for-position, zero mismatches**.
- 39 of 40 witness slots carry a trie-recovered `CVBufferRef` member name (23 directly, 16 through
  one/three-instruction thunks plus named `__got` CoreVideo/CoreMedia key binds). The 40th is an
  ICF-folded `return 0` shared by 568 symbols.
- So the claimed "12 unidentified" delta is **zero**.
⚠️ Correction to that verdict's own text: `transfer` is slot **30** @0x101a666f8; 0x101a66c6c is
slot 31. The UNRESOLVED label is still honest — the three DV bodies (131 / 349 / 591 instr, all
NOT_IN_TRIE) are genuinely unwritten — but the stated *reason* no longer holds.

**`LimitSeparatePreLoadIOContext.more()` @0x101ba5398** (1 HIGH + 1 MED + 1 LOW) — the largest
*closable* unit left, and the one I would start a fresh session on. 0x101ba5398-0x101ba5a5c, 1732 B,
433 instr, vtable idx30. Source body is a bare `0`, so the compiled override returns 0 unconditionally
and the separate-preload path never runs.

Callees resolved (all four in-image, trie-named except one):

    0x101ba5a5c  LimitSeparatePreLoadIOContext.(canContinuePreload in _D3E0B2D6…)(at: UInt64) -> Bool
    0x101ba4e30  LimitSeparatePreLoadIOContext.findDiscontinuousPos          (per the verdict)
    0x101b8ccac  CacheIOContext.addEntry(logicalPos:buffer:size:) throws -> ()
    0x101b86044  CacheIOContext.(updateSpeedSample in _D69EFE14…)(newPos: UInt64) -> ()
    0x101b95bfc  NOT_IN_TRIE  (a real negative)
    0x1019b4074 / 0x1019c0094  KSOptions.logLevel / logger unsafeMutableAddressor — the 2 KSLog sites

**MOST OF THIS BODY IS NOW DERIVED.** A verbatim cache was generated for it this session
(`reconstruction/decompiles/LimitSeparatePreLoadIOContext_more_101ba5398.txt`, ANCHOR_VERIFIED
true). The shape, in order:

1. lazily allocate `loadMoreBuffer` via `_swift_slowAlloc(bufferSize, -1)` when nil;
2. `findDiscontinuousPos()` returning (pos, ok);
3. on ok: read `bufferSize` (self+0x14), take a MODIFYING access on self+0x50, substitute self+0x80
   when self+0x50 == `UInt64.max`, then `canContinuePreload(at:)`;
4. on true: a BINARY SEARCH over the array at self+0x88 for the first `CacheFileEntry` whose
   `position` exceeds pos (`(lo+hi)/2` with `SCARRY8` overflow trap, retain/release per probe, and a
   bridged-array fallback through `thunk_FUN_101b91580`), then clamp `entry.position - pos` to
   `bufferSize`;
5. if self+0x50 != `moreUrlPos`: call `moreDownload`'s witness +0x30 (seek), KSLog, then
   `moreUrlPos = self+0x50`;
6. read through `moreDownload`'s witness +0x28 into `loadMoreBuffer`;
7. EOF handling — on the `-0x20464f45` sentinel (= AVERROR_EOF) with size-1 < 0, set `eof` when
   `isJudgeEOF`, and return `0xdfb9b0bb`;
8. otherwise `CacheIOContext.addEntry(logicalPos:buffer:size:)` (**throws**), advance self+0x50 with
   a carry trap, raise self+0x48 to the new max, `updateSpeedSample(newPos:)`, and store into
   `fakeUrlPos` and `moreUrlPos`.

BOTH KSLog STRINGS ARE DECODED (D3 said `result=not-attempted`): the message prefix is
`'[CacheIOContext] more ffurl_seek2 '` (34 chars @0x103d3fa40, i.e. stored 0x103d3fa20 + 0x20), the
`#fileID` is `'PreLoadIOContext/LimitSeparatePreLoadIOContext.swift'` (52 @0x103d3f9b0), the
`#function` is the small string `more()`, and `#line` is 0xba = **186** — matching the source
comment's second site.

⛔ **THE ONE THING THAT BLOCKS WRITING IT.** Five self offsets are used numerically and cannot be
soundly named yet: **0x48, 0x50, 0x80, 0x88** (0x14 IS solid — `AbstractAVIOContext.bufferSize`, per
its own declaration comment `readLimit@+0x10, bufferSize@+0x14`). Ghidra names the others
symbolically from reflection (`loadMoreBuffer`, `moreUrlPos`, `moreDownload`, `fakeUrlPos`,
`CacheIOContext::isJudgeEOF`, `CacheIOContext::eof`, `CacheFileEntry::position`) but not these.

⚠️ **CORRECTION — an earlier revision of this file called this a `field_offset_vector.py` bug
("it hardcodes the KSPlayer module prefix, fixing it is a one-line change"). That was WRONG on both
counts and would have sent you to fix a tool that is working.** The tool has a `--module` flag and
its own docstring names this exact case; I had simply invoked it without one, and its
KSPlayer-shaped error message hid the real answer. Invoked correctly:

    python3 scripts/field_offset_vector.py CacheIOContext --module PreLoadIOContext
    -> CacheIOContext has metadata_init=1 -- its metadata is initialized at RUNTIME, so the
       static image holds no field offsets. Reading it anyway returns 0x0 for InstanceSize and
       0x0 for every field, which looks like a real map and is not.

Same for `LimitSeparatePreLoadIOContext`. So the blocker is a genuine property of the binary, not
tooling, and it is the case `[[field-offset-vector-metadata-init]]` already documents. The tool is
right to refuse.

THE ROUTE that works is the one the refusal names — the trie-named accessors — and
`recover_field_offsets.py` implements it. **Three of the four are now RECOVERED**, and the class
that owns them is `PreLoadIOContext`, not the two I tried first:

    python3 scripts/recover_field_offsets.py --class PreLoadIOContext --module PreLoadIOContext --verbose
      0x50  urlPos       (setter @0x101ba6e04, getter @0x100a4e368)
      0x80  loadedSize   (getter @0x101ba9e44)
      0x88  cacheList    (getter @0x101ba4244)

⚠️ **AND THIS IS WHY THE NO-GUESSING RULE EARNS ITS KEEP.** An earlier revision of this file listed
"plausible" candidates: `0x88 looks like entryList`, `0x50/0x80 like logicalPos/urlPos`. Measured:
0x88 is **cacheList**, not entryList. 0x80 is **loadedSize**, not urlPos. Only 0x50 was right. Two
of three plausible-looking guesses were wrong, in a body where a wrong field name would have
compiled cleanly and silently read the wrong memory.

Note the same probe on `CacheIOContext` and on `LimitSeparatePreLoadIOContext` returns NOT RECOVERED
for all four offsets — the accessors that touch them by constant immediate belong to
`PreLoadIOContext`. Probe every class in the chain, not just the one the method is declared on.

✅ **0x48 DOES NOT NEED A NAME — THE UNIT IS UNBLOCKED.** It is never `more()`'s own field access:
it belongs to `urlPos`'s `didSet`, which the compiler INLINED into `more()`.

Proof — the `urlPos` setter @0x101ba6e04 (29 instr, the address `recover_field_offsets` reports for
`urlPos offset=0x50`) is instruction-for-instruction the same shape as `more()`'s tail:

    101ba6e2c: str  x19, [x20, #0x50]      urlPos = newValue
    101ba6e30: cmn  x19, #0x1
    101ba6e34: b.eq 0x101ba6e58             ... skip the didSet when newValue == UInt64.max
    101ba6e38: ldr  x8, [x20, #0x48]
    101ba6e3c: cmp  x19, x8
    101ba6e40: csel x8, x19, x8, hi         self[0x48] = max(newValue, self[0x48])
    101ba6e44: str  x8, [x20, #0x48]
    101ba6e4c: bl   0x101b86044             updateSpeedSample(newPos:)

`more()` reproduces exactly that at 0x101ba5980/0x101ba598c followed by the same
`bl 0x101b86044`. So the whole "max into 0x48 then updateSpeedSample" sequence in `more()` is
produced by writing **`urlPos = newPos`** — one statement — and the 0x48 field is `urlPos`'s
observer's business, in a different member's body.

⚠️ This is worth generalising: an unnameable offset inside a body may not belong to that body at
all. Before hunting a field name, check whether the surrounding instruction sequence reproduces a
known accessor's shape — a `didSet`/`willSet` inlined at the assignment site looks exactly like a
foreign field access. Probing `recover_field_offsets.py --offset 0x48` across all seven classes in
the chain returns NOT RECOVERED every time, which is correct and was never going to be the answer.

So `more()`'s tail is: `urlPos = newPos`, then the `fakeUrlPos` and `moreUrlPos` stores. Nothing in
this unit is blocked on a name any more. Its use is distinctive and should make it identifiable from a
sibling body: after a successful read it is a running maximum —
`self[0x48] = max(self[0x48], newPos)` — i.e. a high-water mark updated only on the success path,
immediately before `updateSpeedSample(newPos:)`. Name it from an anchor site in another body, then
this unit is writable end to end.

⚠️ **THE ANCHOR-SITE ROUTE HAS A TRAP, and I nearly walked into it.** Disassembling
0x101b86000-0x101bac000 and grepping `(ldr|str) xN, [xM, #0x48]` finds ~20 sites. One of the most
promising, a load/store pair at 0x101b96868/0x101b96890, sits inside
`PreLoadIOContext.CacheOnlyIOContext.seek(offset:whence:)` @0x101b96820 — a seek writing a position
field at +0x48, which looks like exactly the identification you want.

**It is not transferable.** `CacheOnlyIOContext` is a DIFFERENT class from `PreLoadIOContext`, and
both have `metadata_init=1`, so neither has a statically fixed layout. Two classes using the same
offset number says nothing about them being the same field. Any anchor site must be on a receiver
whose class is *established* to be `PreLoadIOContext` (or a subclass sharing its layout prefix)
before its meaning transfers — so the route is: name the owning function of each site, check its
owner class, and only then read the semantics. The other candidate pair at 0x101b85fe0 is
NOT_IN_TRIE, so it cannot be attributed at all.

⛔ **DO NOT WRITE THIS BODY FROM THE DECOMPILE — IT LINEARIZES TWO SYMMETRIC TAILS INTO ONE.**
This is the last thing s116 established and it is the most important one for whoever writes it.

Reading 0x101ba5688-0x101ba570c from DISASSEMBLY (not the cache) shows a *second* KSLog site and a
*second* `urlPos` tail, distinct from the one at 0x101ba5980:

    101ba5690: mov  w6, #0xa6            #line 166  <- the FIRST log site (the other is 186)
    101ba569c: blr  x8                   the LogHandler witness call
    101ba56b4: tbnz x21, #0x3f, …        sign test on the new position
    101ba56cc: ldr  x8, [x19, #0x48]
    101ba56d0: cmp  x21, x8
    101ba56d4: csel x8, x21, x8, hi
    101ba56d8: stp  x8, x21, [x19, #0x48]   <- writes 0x48 AND 0x50 in ONE stp
    101ba56e4: bl   0x101b86044          updateSpeedSample(newPos:)
    101ba56f4: str  x8, [x19, x9]        x9 = *(0x1044f5c40) = fakeUrlPos
    101ba5700: str  x8, [x19, x9]        x9 = *(0x1044f5c48) = moreUrlPos
    101ba5708: mov  w24, #-0x1           the -1 return on the other edge

Note the `stp x8, x21, [x19, #0x48]` — a single paired store covering 0x48 and 0x50 — which is the
`urlPos = …` setter inlined again, exactly as at 0x101ba5980. So the body has TWO such tails on
different paths, and the Ghidra cache presents them as one. A source written from the cache would
have one log site instead of two and one tail instead of two: structurally wrong, and it would
compile and pass every gate.

This is why rule 28 exists. Read the branch structure from `llvm-objdump` first, then use the cache
only to orient inside each block.

**VERIFIED FROM DISASSEMBLY (not the cache), so it can be transcribed directly.**

Prologue and gate, 0x101ba53e4-0x101ba545c:

    101ba53e4: bl   0x101ba4e30        findDiscontinuousPos — returns pos in x0, Bool in w1
    101ba53ec: cmp  w8, #0x1
    101ba53f0: b.ne 0x101ba553c        !ok -> the other arm
    101ba53f4: ldr  w25, [x19, #0x14]  bufferSize
    101ba5408: bl   beginAccess(self+0x50, w2=1)   MODIFY on urlPos
    101ba540c: ldr  x22, [x19, #0x50]
    101ba5410: cmn  x22, #0x1
    101ba5414: b.ne 0x101ba5430        urlPos != UInt64.max -> use it
    101ba5428: bl   beginAccess(self+0x80, w2=0)   READ on loadedSize
    101ba542c: ldr  x22, [x19, #0x80]              ... else fall back to loadedSize
    101ba5438: bl   0x101ba5a5c        canContinuePreload(at:)
    101ba543c: tbz  w0, #0x0, 0x101ba5708          false -> return -1

The lower-bound search, 0x101ba54a0-0x101ba5514:

    101ba54a8: adds x8, x23, x20       lo + hi, trapping (b.vs)
    101ba54b0: add  x9, x8, x8, lsr #63
    101ba54b4: asr  x25, x9, #1        mid = (lo + hi) / 2
    101ba54b8: ldur x27, [x19, #0x88]  entryList (the STORED field — see the cacheList note)
    101ba54bc: tst  x27, #0xc000000000000001 / b.ne   bridged-array fallback
    101ba54dc: add  x8, x27, x25, lsl #3            stride 8 -> element is a CLASS REFERENCE
    101ba54e0: ldr  x26, [x8, #0x20]                entry
    101ba54e8: bl   swift_retain
    101ba54f0: ldr  x8, [x26, x8]                   entry.position (x28 = its offset global)
    101ba54f4: cmp  x22, x8
    101ba54f8: b.hs 0x101ba5490        pos >= entry.position -> raise lo
    101ba5504: mov  x24, x26           else keep this entry as the running best
    101ba5508: mov  x20, x25           and hi = mid
    101ba5510: b.lt 0x101ba54a8        loop while lo < hi

i.e. the first entry whose `position` exceeds `pos`, kept in x24, with retain/release per probe.
Element stride 8 plus the retain confirms `[CacheFileEntry]` is an array of class references.

The `!ok` arm, 0x101ba553c-0x101ba55a4 — it is NOT a no-op, it seeks and logs:

    101ba553c: mov  x22, x0            pos, from findDiscontinuousPos
    101ba5548: add  x0, x19, x8        x8 = *(0x1044f5c50) = moreDownload
    101ba554c: ldp  x21, x23, [x0, #0x18]   the existential: instance + witness table
    101ba5558: tbnz x22, #0x3f, trap        sign check (the Int64 conversion of pos)
    101ba5560: ldr  x8, [x23, #0x30]        witness +0x30 = seek(offset:whence:)
    101ba5568: mov  w1, #0x0                whence = 0
    101ba5574: blr  x8                      moreDownload.seek(offset: Int64(pos), whence: 0)
    101ba557c: bl   KSOptions.logLevel.unsafeMutableAddressor
    101ba5598: cmp  w8, #0x3 / b.lo 0x101ba56b0    log only when logLevel >= 3
    101ba55a0: adrp/add 0x103d3f9b0               the #fileID literal

then it falls into the 0x101ba56b0 tail (`mov w24, #0x1`, the `stp` urlPos write, return 1). Note
`moreDownload` is read here as a NON-optional two-word existential — relevant to the standing
`PreLoadIOContext_download_existential` optionality verdict.

The post-search size clamp, 0x101ba5710-0x101ba5764:

    101ba5710: cbz  x24, 0x101ba5750   no entry found -> skip the clamp
    101ba5718: ldr  x20, [x24, x8]     entry.position
    101ba5724: subs x8, x20, x22       entry.position - pos   (b.lo -> trap on borrow)
    101ba5730: cmp  w9, #0x1 / b.lt    skip when size < 1
    101ba573c: cmp  x8, x9  / b.hs     skip when the difference >= size
    101ba5744: lsr  x9, x8, #31 / cbnz -> trap    the Int32 range check
    101ba574c: str  x8, [sp, #0x18]    size = Int32(entry.position - pos)
    101ba5750: ldr  x20, [x19, #0x50]  urlPos
    101ba575c: ldr  x8, [x19, x28]     x28 = *(0x1044f5c48) = moreUrlPos
    101ba5764: b.eq 0x101ba58f0        urlPos == moreUrlPos -> skip the seek entirely

**EVERY REGION OF THIS BODY IS NOW READ FROM DISASSEMBLY.** The last one, 0x101ba5768-0x101ba57c8,
is structurally IDENTICAL to the `!ok` arm at 0x101ba553c — same `ldp x24,x25,[x0,#0x18]` existential
load of `moreDownload`, same sign check, same `ldr x8,[x25,#0x30]` witness +0x30 = `seek(offset:whence:)`
with `w1 = 0`, same `logLevel >= 3` gate before the log. The two differ only in `#line` (166 vs 186).
That identity is exactly why the Ghidra cache folded them into one, and why a source written from the
cache would carry one seek-and-log instead of two.

✅ **THE RETURN DATAFLOW IS TRACED — and it contains a trap that would corrupt a naive read.**

There is exactly ONE return: `mov x0, x24` @0x101ba59fc into the epilogue `ret` @0x101ba5a1c. But
**x24 serves two disjoint roles**, and only some of its writes are return values:

    101ba5478  mov x24, #0x0        SEARCH state — the running "best entry", initialised nil
    101ba5504  mov x24, x26         SEARCH state — best = this entry
    101ba54fc  mov x0, x24          NOT a return: the argument to swift_release(oldBest)
    101ba571c  mov x0, x24          NOT a return: swift_release again
    101ba56b0  mov w24, #0x1        RETURN 1     — the seek-and-log path
    101ba5708  mov w24, #-0x1       RETURN -1    — canContinuePreload was false
    101ba57a4  mov x24, x0          the seek result
    101ba593c  mov x24, x0          the read result
    101ba59cc  mov w24, #0xb0bb / movk #0xdfb9,lsl#16   RETURN 0xdfb9b0bb — the EOF constant

⚠️ The two `mov x0, x24` sites at 0x101ba54fc and 0x101ba571c look exactly like returns and are
`swift_release` arguments for the search's entry pointer. Reading them as returns — or assuming a
single live range for x24 — produces a body that returns an object pointer. Disjoint live ranges
sharing a register is the whole hazard here.

With this, every instruction AND the return plumbing of `more()` are established.

⛔ **AND YET IT STILL CANNOT BE WRITTEN — because of a DEPENDENCY, not a gap in the read.** This is
the definitive scoping answer, and it connects two verdicts nobody had linked.

Both witness dispatches in this body go through `moreDownload`. The source declares
`let moreDownload: (any DownloadProtocol)?` at LimitSeparatePreLoadIOContext.swift:98, with the
comment "⚑ optionality inferred (a nil existential is a zero metadata word; unobservable here)".
**The binary disagrees.** The designated init's own trie mangle, transcribed at :185, reads
`__allocating_init(download: KSPlayer.DownloadProtocol, moreDownload: KSPlayer.DownloadProtocol, …)`
— NO `Sg`, i.e. non-optional on both.

So writing `more()` forces a choice, and both options are wrong today:
  · `moreDownload?.seek(…)` — introduces optional chaining the binary does not have; and the body
    reads the existential with a bare `ldp x24,x25,[x0,#0x18]` and no nil test, so there is nothing
    for the `?` to compile to.
  · drop the `?` — which the standing **`PreLoadIOContext_download_existential`** verdict (MED)
    records as BLOCKED, because `CacheIOContext.swift:211` and
    `LimitSeparatePreLoadIOContext.swift:346` both delegate with `download: nil`, and the real
    argument is built by the unreconstructed deep-FFmpeg URLContext open inside 0x101b90c58.

**`more()` is therefore gated on `download_existential`, which is gated on 0x101b90c58.** Resolve
that chain first; the transcription itself is then mechanical, because everything above is read.

**THE CHAIN WAS WALKED TO ITS TERMINUS and the blocker is REAL AND CURRENT — not stale like so many
others this session.** 0x101b90c58 is fully trie-named (no inference):

    PreLoadIOContext.URLContextDownload.init(url: Foundation.URL, flags: Swift.Int32,
      options: UnsafeMutablePointer<OpaquePointer?>?, interrupt: __C.AVIOInterruptCB,
      isReadComplete: Swift.Bool) throws -> PreLoadIOContext.URLContextDownload

264 instructions, 0x101b90c58-0x101b91078. The CLASS exists — `Sources/PreLoadIOContext/
URLContextDownload.swift` — but that designated init does NOT: the file carries
`UNRESOLVED: real designated init s3 @101b90bc0 → SHARED inner FUN_101b90c58 … Opens an FFmpeg
URLContext (deep IO; stripped calls named only by the P2 oracle) → UNRESOLVED→P8`, and only the
inherited `init(bufferSize:)` is written as the compilable spine.

So the terminus is a 264-instruction FFmpeg URLContext open whose callees are stripped. That is the
actual bottom of this dependency chain, and it is a genuine reconstruction unit — not a stale note,
not a mis-scoping, not a tooling gap.

**AND THE "STRIPPED CALLS" NOTE LOOKS PESSIMISTIC — this unit may be more open than it reads.** Its
264 instructions call 20 distinct targets; the six non-runtime ones are 0x1030c03e4, 0x10323a9d8,
0x101b95540, 0x1019e1f94, 0x1019f59c4 and 0x101b90c44. `ffmpeg_name_oracle --addr` alone does NOT
name them — on 0x10323a9d8 it returns `in_ffmpeg_band: true, n_candidates: 27` and a candidate list,
not a verdict. But **0x10323a9d8 is already CONFIRMED elsewhere in this tree** as `av_dict_get`
(FormatContext.swift carries
`⚑[tool=ffmpeg_name_oracle ref=av_dict_get:0x10323a9d8 result=CONFIRMED] (FUN_10323a9d8, avutil/dict.o
— inside toDictionary)`), which came from the fuller object-file attribution rather than the bare
`--addr` probe.

I then ran that check, and **FOUR OF THE SIX ARE ALREADY NAMED**. The note is stale:

    0x10323a9d8  av_dict_get                                     CONFIRMED in FormatContext.swift:32
    0x1019f59c4  the FFmpeg URL-string helper                    named at Utility.swift:403
    0x101b90c44  a metadata accessor                             named at LimitSeparate…swift:271
    0x1019e1f94  KSPlayer.KSPlayerError.init(errorCode:avErrorCode:)   TRIE-NAMED (OWNER_MATCH)
    0x1030c03e4  NOT_IN_TRIE — in the FFmpeg band; this is the URLContext open itself
    0x101b95540  NOT_IN_TRIE — in-image

`0x1019e1f94` is a particularly good sign: this init `throws`, and its error construction is
`KSPlayerError.init(errorCode:avErrorCode:)`, fully named, so the throw path is already writable.

⚠️ **I FIRST WROTE "this is not a wall — it is one FFmpeg attribution away". THEN I RAN THE
ATTRIBUTION, AND IT FAILED.** `ffmpeg_name_oracle --addr 0x1030c03e4 --resolve` — the discriminating
mode, not the bare probe — returns:

    "fp": [92, 368], "n_fp_candidates": 14, "in_ffmpeg_band": true,
    "status": "UNKNOWN", "survivors": [],
    "why": "no indexed symbol matches instruction-for-instruction"

Fourteen fingerprint candidates, zero instruction-level survivors. The FFmpeg symbol index does not
contain this function, so the route that produced the `av_dict_get` CONFIRMED verdict does **not**
name it. `0x1030c03e4` is the URLContext open at the heart of this init and it stays unnamed.

**So the terminus IS real, and it is measured rather than assumed.** Four of six callees are named,
which makes the unit smaller than its note suggested — but the one that matters most is not, and it
cannot be written around: naming it needs either an FFmpeg index built from the matching build, or a
different discriminator entirely.

That is the true bottom of `URLContextDownload.init` → `download_existential` → `more()`.

⚠️ One caution for whoever opens it: `recover_swift_function_name` on this address returns
`#function: init(url:flags:options:interrupt:isReadComplete:)` at high confidence but reports
CONFLICTING `#file` anchors — `Components/PlayerOptions.swift` (a different module) and
`PreLoadIOContext/CacheIOContext.swift` — plus a bare `'multiple_requests'` literal. Trust the TRIE
name, which is unambiguous; do not take the `#file` from that tool here.

✅ **THE DROPPED ERROR PATH IS NOW READ.** The cache opens with
`/* WARNING: Removing unreachable block (ram,0x101ba5964) */`, and 0x101ba5964 is precisely the
block Ghidra discarded. Read from disassembly:

    101ba5958: mov  x21, #0x0            clear the swifterror register
    101ba595c: bl   0x101b8ccac          addEntry(logicalPos:buffer:size:)  — throws
    101ba5960: cbz  x21, 0x101ba596c     no error -> fall through
    101ba5964: mov  x0, x21
    101ba5968: bl   0x10345ccf4          swift_errorRelease — the CATCH, and it does nothing else
    101ba596c: adds x0, x22, w24, uxtw   continue on both paths

The catch body is empty apart from releasing the error, and control rejoins immediately. That is
**`try? addEntry(logicalPos:…, buffer:…, size:…)`** — one statement, not a `do`/`catch` block.

With this, every instruction of `more()` is accounted for and nothing in the unit is unread. What
is left is purely writing it (plus declaring `canContinuePreload(at:)`, which D2 still gates).

⚠️ Do NOT under-scope this from the instruction count. It is not a straight-line body: ~24 branches
with at least two loop back-edges (0x101ba5490 and 0x101ba54a8, entered from `b.hs` @0x101ba54f8 and
`b.lt` @0x101ba5510), signed arithmetic with overflow traps (`b.vs` @0x101ba54ac), and sign-bit tests
(`tbnz x22,#0x3f` @0x101ba5558, `tbnz x21,#0x3f` @0x101ba56b4). Budget it like `addTimeIndex`
(301 instr, which needed a full derivation pass plus independent verification), not like a
constraint-setter.

✅ **D2 IS CLOSED (commit `0e3f556`).** The verdict recorded `canContinuePreload(at:)` as absent. It
was present all along at 0x101ba5a5c, declared as `canPreload(_ position:)` and explicitly marked
"name inferred (devirt)" — an INVENTED name that was wrong on the name, the argument label and the
access level. The trie gives all three:
`LimitSeparatePreLoadIOContext.(canContinuePreload in _D3E0B2D6…)(at: Swift.UInt64) -> Swift.Bool`,
where the `(… in _<discriminator>)` form is the mangling for a **private** member. Renamed and
re-scoped; body unchanged; build 4/4. It had also collided with
`LimitPreLoadIOContext.canPreload`, a STORED `Bool` on a different class — two unrelated members
sharing a name purely because one was guessed.

**THE `moreDownload` WITNESS OFFSETS ARE MAPPED.** `DownloadProtocol` has 8 requirements
(PlayerDefines.swift:773). Witness word 0 is the conformance descriptor, so requirement *i* sits at
word *i+1* = offset `8*(i+1)`:

    +0x28 = word 5 = requirement 4 = read(buffer:size:)
    +0x30 = word 6 = requirement 5 = seek(offset:whence:)

Both corroborate independently from the call shapes rather than merely fitting: the +0x28 site is
called with `(loadMoreBuffer, size)` and the +0x30 site with `(pos, 0)`.

⚠️ **AND A CORRECTION TO THIS FILE'S OWN EARLIER CLAIM.** It said "0x88 is `cacheList`, not
`entryList`". For *writing source* that is misleading: `cacheList` is a COMPUTED property
(LimitSeparatePreLoadIOContext.swift:634, PreLoadIOContext.swift:465) that forwards to the STORED
`entryList` (CacheIOContext.swift:97). `recover_field_offsets.py` credits an offset to whichever
ACCESSOR touches it, so its answer means "an accessor that reads this offset", not "the stored field
at this offset". The binary search in `more()` walks **`entryList`**.

D3's two KSLog message strings were never decoded; the verdict says so explicitly
(`result=not-attempted`). Decode them rather than carrying the source comment's 34-char prefix.

**`FormatContext` inner init @0x101a350bc** (1 MED) — its stated blocker is now STALE, but the unit
is bigger than the verdict implies. FormatContext.swift:22-27 defers the `ioContext as? PlayList`
arms because "`PlayList` … is a Forward-only protocol NOT yet reconstructed in-tree". **It is
reconstructed** — `public protocol PlayList` with all four requirements in witness-table order at
PlayerDefines.swift:642. So the deferral's reason no longer holds.

⚠️ But before planning it: the body is **1153 instructions** (0x101a350bc-0x101a362c0, 4612 B), and
the cast is NOT in it — a full dump contains no `swift_dynamicCast` and no `swift_conformsToProtocol`
call anywhere in the extent. Find where the cast actually lives (the outer init 0x101a35050, or
MEPlayerItem's FUN_101a512b4 which the source comment says shares it) before attributing the arms to
this address. The three arms the comment names are: `seekByBytes = true`, the
`formatCtx->duration = duration * AV_TIME_BASE` side-effect, and the per-track `languageCode`/`name`
override driven from `audioLanguageCodeMap` / `subtitleLanguageCodeMap`.

**`KSPlayerLayer_structural_placement_s76` D2 — ITS PROPOSED FIX IS REFUTED, and its blocker is
stale.** The verdict says `AVPictureInPictureControllerDelegate` "is NOT among the binary's
conformances for KSPlayerLayer" and that "the conformance belongs on KSComplexPlayerLayer. Lands
with the KSComplexPlayerLayer stand-up (Package I)."

Both halves need re-doing:

1. The stand-up already happened — `public class KSComplexPlayerLayer: KSPlayerLayer` is declared at
   KSPlayerLayer.swift:961, so "lands with Package I" no longer defers anything.
2. `superclass_conformance_gate --file …/KSPlayerLayer.swift` reports
   `KSPlayerLayer super=NSObject confs=['MediaPlayerDelegate']` and
   **`KSComplexPlayerLayer super=KSPlayerLayer confs=[]`** — the target class has NO Swift
   conformance records at all. Moving the conformance there is no better supported than leaving it.

⚠️ The likely reason both are empty is that `AVPictureInPictureControllerDelegate` is an **ObjC**
protocol, and ObjC conformances do not appear in Swift conformance records — which is exactly why
the gate itself reports it as `source-extra (noted, not flagged)` rather than flagging it. So the
verdict drew a placement conclusion from an oracle that cannot see the thing it is about.

I then ran the ObjC route, and it does NOT settle it either:

    objc_trampoline_oracle --class KSPlayerLayer         -> objc method list entries=0
    objc_trampoline_oracle --class KSComplexPlayerLayer  -> objc method list entries=0

Neither class exposes an ObjC method list, so neither oracle places this conformance. Note also that
the two addresses the MEMBER_MISSING ranking labels
`KSComplexPlayerLayer.pictureInPictureControlle…` — 0x1019d62ec and 0x1019d600c — are both
**NOT_IN_TRIE** (the ranking marks 0x1019d62ec a thunk), so they cannot be used to anchor the
placement either; their names in that JSON come from the pin_sweep row, not from the trie at those
addresses.

**Net: the divergence's premise is unverified and its proposed fix is unsupported, by all three
routes tried.** Do not move the conformance on the strength of the verdict. Whoever takes it needs a
route none of these tools provide — most likely reading the class's protocol list out of the ObjC
metadata directly. And note the file cannot flip on D2 alone regardless: D1 is the 11-field
`l2_field_gate` debt sweep on KSPlayerLayer, which is its own unit.

**`AudioDescriptor.audioFormat(...)` @0x101a68c44** — pinned at the declaration in `240952a`.
Forward's helper does not switch on sampleFormat: no `br x` in the extent, and
`101a68eb8: mov w2, #0x1` sets commonFormat unconditionally. Not rewritten because the two
`cmp x8,x23` metatype comparisons and the layoutTag derivation were not read.

**`Anime4KPipeline.loadShaderFiles(_:)` @0x101a79b84** — now declared, body pinned. 498 instr,
unread. Until it is written, `anime4Ks` stays empty and loadPreset's KSLog reports 0 shaders.

## Two verdict-hygiene findings that will save you time

1. **s84/s104 verdict `source_lines` are systematically stale.** Every agent that checked found the
   path wrong (sources are in the SIBLING `KSPlayer` repo, not under `play/`) and the lines off by
   17-177. Re-derive the declaration line before quoting a verdict.
2. **A verdict can be measuring an optimizer artifact.** AudioDescriptor's three divergences were
   dead-argument elimination (twice) and the exclusivity ABI (once). Before writing a fix, ask
   whether the "divergence" is something the compiler did. The tell for the ABI one: only a
   **tracked** access (flags bit 0x20) takes an `endAccess`; image-wide over
   0x101990000-0x101b00000 there are 3354 begins against 306 ends, split
   2161 x 0x0 / 669 x 0x1 / 511 x 0x21 / 5 x 0x20.

## Also worth knowing

- Committing a change to `Resample.swift` trips the decompile-cache provenance gate on five
  **VideoSwresample** verdicts whose `.json` sidecars never existed. Fixed properly by regenerating
  them — build a one-off worklist and run `prefetch_decompiles.py --worklist <file> --force`. Do not
  hand-write a sidecar (P27). Note two verdicts name ids (`_s29_`, `_s31_`) that differ from the
  `.txt` files on disk (`_slot29_`, `_slot31_`).
- MEMBER_MISSING is 56 rows (fresh `pin_sweep --every` → `mm_triage_s116.json` →
  `mm_rank_s116.json`, ranked with the banked s115 helper cache). Three rows read end to end:
  `CacheIOContext.fileSize`, `CacheOnlyIOContext.read`, `KSMEPlayer.sourceDidOpenedSync` — all
  still need the field/type/named-but-undeclared axes screened before dispatch.
