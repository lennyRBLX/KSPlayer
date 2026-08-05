# Session 107 work

**Goal, unchanged: drive MEMBER_MISSING to 0.** s106 took it **223 → 180** across 13 commits on
`forward` (`579628d..7fbcbf0`), every one built 4/4 and re-derived with `pin_sweep --every`.

⚠️ **The filename date is not the session order.** Order by session number.

## Verify first

1. `python3 scripts/recon_gate.py --mode handoff`. Expect **PASS 43 · ANOMALY 6 · FAIL 5**.
   The FAILs are `agg_critical` / `agg_high` / `agg_unresolved` (standing fix queue),
   `sc_wave_worklist` (the unanswered s104 design question), and `sc_stale_screen` — see §4.
   `handoff_baseline.json` has NOT been refreshed since s86; the ANOMALYs follow from that.
2. `python3 scripts/pin_sweep.py --every` — expect **MEMBER_MISSING 180**, ACCESS 26, ABSENT 123,
   NOT_IN_TRIE 24, AMBIGUOUS_OVERLOAD 10, TYPE_DIVERGENCE 4. Re-derive; do not quote.
3. `python3 scripts/member_missing_triage.py --sweep <that --json>` — but read §2 first, because
   its cost column is misleading in a specific way.
4. `git -C <KSPlayer> status --porcelain` — expect a CLEAN tree. s106 cleared the three staged
   files s104/s105 were handed.

## 1. ⭐ The one number that should drive planning

`vtable_walk.py <class>` prints `metadata_init`. **Eight of the ten classes holding the most open
rows are `metadata_init=1`, covering ~101 of the 180.** Their stored-property offsets are not in
the static image: `field_offset_vector.py` refuses them by design, and reading the globals anyway
returns 0x0 for every field — "which looks like a real map and is not".

**New tool, s106: `scripts/recover_field_offsets.py`,** gate-wired as `sc_recover_offsets`. It
recovers offset→name from a class's own trie-named accessors: `add x0, x20, #IMM` is the address
handed to `swift_beginAccess`, so it marks a genuine stored-property access. KSOptions yields 21
offsets that way, strictly increasing in `fieldrec`'s independent field-record order. It also emits
globalAddr→name straight from the `vpWvd` symbols.

It unblocked `KSAVPlayer.checkShouldResume` — `options + 0x46` is `enterForgeResumePlay`, a body
s106 had deliberately left undeclared rather than guess.

**Its limit is real and is the defined next piece of work.** Fields that are non-public AND reached
symbolically stay unrecovered: no `vpWvd` to name them, and elimination fails when several are
unnamed at once. Three bodies are fully read and blocked on exactly this —
`MEPlayerItem.isIdle`, `LimitPreLoadIOContext.shouldContinueRead`, `DemuxerIO.update`. Three
recovery routes were tried and all failed (trie name; type-constrained elimination — MEPlayerItem
has 8 Bool fields with only 1 named; position against named neighbours — a solid run of unnamed
globals). The tool prints `NOT RECOVERED — do not guess it`. **Do not** talk yourself past that.

## 2. The triage's cost column is the THUNK, not the work

Saved as a memory, repeated here because it will mislead you at the planning step. The instruction
count is the body AT the row's address. Many rows are 1-instruction branch thunks:

    KSComplexPlayerLayer.removeRemoteControllEvent   1 instr → b → 181 instr
    CacheIOContext.cacheExists / preloadCacheExists  1 instr → b → 115 instr
    KSComplexPlayerLayer PIP delegate trio           1 instr → b → 77-107 instr

A 1-instruction row is cheap ONLY when the tail-call target is an already-declared member
(`MediaPlayerProtocol.frameRate` → `nominalFrameRate` was genuinely free; `KSPlayerError.errorDescription`
→ a 110-instruction `localizedDescription` was not). Sorting ascending puts a cluster of thunks at
the top that are 80-180 instructions each.

## 2a. The cheap seam is EXHAUSTED — measured, not assumed

s106 closed 58 rows and the last ones cost far more per row than the first. At close, the three
cheapest remaining rows were probed and every one bottoms out in a substantial read:

    KSComplexPlayerLayer.pictureInPictureController   2 instr → `mov x0,x1` / `b` → **85 instr**
      (the AVPictureInPictureControllerDelegate `failedToStartPictureInPictureWithError:`; the
       2-instruction body just drops the controller argument)
    CacheOnlyIOContext.entryList                      8 instr, blocked on a field + init (§5d)
    KSOptions.recordDir                               3×7 instr accessors → once-init 0x1019b5938,
      whose chain runs through THREE unnamed helpers (0x10002d984 / 0x1000a538c / 0x1000a48f4) and
      two globals that resolve to nothing: 0x1044e3e10 is zero-initialised at runtime and
      0x103564860 is not a chained-fixup pointer (the rebase decode yields a nonsense target)
    LimitSeparatePreLoadIOContext.cacheList           21 instr → a **108-instr** map-like transform
      at 0x101bab128 over the array at +0x88

⚠️ **That framing was WRONG and is corrected here.** Two of those three landed later in the same
session — the PIP callback (85 instr) and `SubtitleImageInfo.id` (49 instr) — because a body made
of NAMED runtime calls is not expensive, it is a shape you read once and recognise.
`SubtitleImageInfo.id` is four `bind_oracle` lookups: Hasher.init / CGRectStandardize /
Hasher._combine ×4 / Hasher.finalize, and the `fcmp d,#0.0` / `fcsel` before each combine is
`Double.hash(into:)`'s own −0.0 normalisation — which is what proves it is `rect.hashValue` and not
a hand-rolled hash.

**The cost predictor is not instruction count — it is whether the CALLEES RESOLVE.**

    resolve → cheap    SubtitleImageInfo.id           49 instr, 4 got lookups, landed
                       pictureInPictureController…    85 instr, all KSLog machinery, landed
    do not  → costly   LimitSeparatePreLoadIOContext.cacheList  108 instr; its transform
                                                       @0x101bab128 is not in the trie at all
                       KSOptions.recordDir            3×7 instr; three unnamed helpers and two
                                                       globals that decode to nothing
                       MetalSubtitleView.mtkView      63 instr; UITraitCollection.current
                                                       .displayScale and MTKView.drawableSize both
                                                       resolve, but it reads TWO ivars via globals
                                                       0x1044ef5d8/0x1044ef5e0 that NO named
                                                       accessor touches. `playRatio` is settled by
                                                       type (the only `Sd` field of seven); the
                                                       object ivar has four candidates and stays
                                                       open.

Screen a row by resolving its callees first — that is a handful of commands and it sorts the queue
far better than the triage's instruction count.
The seams that DID pay in s106, in the order they paid, are §5c's naming routes — they turn a
100-instruction unknown into a rename or a one-line forward when they apply, and they cost a few
commands to test.

## 2b. `KSComplexPlayerLayer.pictureInPictureController(_:failedToStartPictureInPictureWithError:)`
— read to one missing piece

Nearly complete; recorded so the next session starts from the gap, not the top.

The row's body @0x1019d342c is two instructions, `mov x0, x1` / `b 0x1019d6430` — it drops the
controller argument and tail-calls an 85-instruction handler. That handler is one `KSLog` call:

- `ldrb w8, [0x1044e5173]` / `cmp w8, #2` / `b.lo` — the standard log-level gate. 2 is the CASE
  INDEX for `.error`, per the encoding already recorded at KSOptions.swift.
- `w0 = 2` at the call — the level argument, `.error`.
- `#fileID` = `'KSPlayer/KSPlayerLayer.swift'` (count 28), which also CONFIRMS this class's file
  placement matches the reconstruction.
- `#function` is the 69-character string at 0x103d34b80 — the length matches
  `pictureInPictureController(_:failedToStartPictureInPictureWithError:)` exactly.
- **`w6 = 0x398 = 920`** — the LINE NUMBER in Forward's KSPlayerLayer.swift.
- the error is passed through `_convertErrorToNSError` (`__got 0x104109940`) with the `NSError`
  classref at 0x1044105a8, then interpolated into the message.

**The one missing piece is the message's literal text.** Its segments are assembled by outlined
helpers (0x100029510, 0x1019d5bd8) and the operand at 0x1044e4f78 has NO BIND and does not decode
as a string — it is a metadata cache, not a literal. Do not invent a format string; find the
segments first. Everything else about this member is read.

### MetalPlayView's last three members — all blocked on the SAME thing: unnamed offset globals

`layoutSubviews()` @0x101a602dc (103) · `enterBackground()` @0x101a6095c (93) ·
`enterForeground()` @0x101a60ad0 (156). `enterBackground` was read far enough to show the shape:
two value-witness allocas, then `strb #1` into the field behind global **0x1044ea8f8**, a `ldrb`
test of **0x1044ea928**, and a branch that reaches **0x1044ea8d8**.

⛔ **None of those three globals has a `vpWvd`.** This class exposes only five
(0x8b0 rotation · 8b8 pixelBuffer · 8c0 options · 8c8 renderSource · 8d0 drawable), and the array
is provably NOT index-ordered — 0x8a0 is `metalView` (index 8) while 0x8b0 is `rotation` (index 3),
so no arithmetic maps a global to a field. Semantics suggest 0x8f8 is `isBackground` (a Bool set
true on entering background, and its `vpfi` reads false), but that is a guess and this session has
already been burned once by naming a field on plausibility.

**Cross-reference scan run — here is the map, use it as the starting point:**
```
0x1044ea8f8  7 sites: init · enterBackground · enterForeground · 4 NOT_IN_TRIE
0x1044ea928  8 sites: init · play · pause · enterBackground · enterForeground · 3 NOT_IN_TRIE
0x1044ea8d8  6 sites: init · 5 NOT_IN_TRIE
```
⚠️ **A SECOND pre-existing defect surfaced here — `play()` also does not match its source.**
`play()` @0x101a5f72c opens `ldrb w8,[x20,<0x928>]` / `tbnz w8,#0 → exit`, i.e. it GUARDS on the
0x928 flag and returns early when set; only afterwards does it touch the 2-word field at 0x900.
The source is a bare `displayLink?.isPaused = false` with no guard at all. So `flush()` is not an
isolated case — MetalPlayView's reconstructed bodies disagree with the binary in at least two
places, and **no MetalPlayView body should be used as a cross-reference anchor** until each is
re-verified against the binary directly.

⚑ 0x1044ea928 is therefore a guard flag consulted by `play`, `pause`, `enterBackground` and
`enterForeground`. Candidates from the field list are `isPaused` (index 0), `isBackground` (10),
`renderUseDispatchSourceTimer` (14) and `forcedFrameRetryScheduled` (16); `isPaused` fits the
`play`/`pause` pairing and its `vpfi` reads **true**, which matches the init ending in `pause()`.
That is suggestive, NOT proven — do not write it without a type-revealing site.

✅ **The route that works** — proven twice now — is a BINARY-INTERNAL anchor: find a site where the
same global's field is passed somewhere type-revealing (a conformance witness, a metadata
accessor, a decoded selector unique to one type) and read the name off that. That is how
0x1044ea8a0 was settled as `metalView` (its `.layer` casts to `CAMetalLayer`, and only `MetalView`
declares `layerClass = CAMetalLayer.self`). Scan `__text` for each unknown global, look for such a
site, and only then write the name.

## 2r-RESOLVED. NOT an `@objc` problem — there are UIView EXTENSION twins, and they are missing

✅ **`MetalPlayView.didStartPIP`/`didStopPIP` do NOT need `@objc`, and the declarations landed this
session are correct as written.** Checked properly: an `@objc` member emits a `…To`-suffixed thunk,
and neither has one. The speculation in the previous revision of this section was wrong.

✅ **What the caller actually reaches is a different pair.** The trie holds FOUR symbols:
```
$s8KSPlayer13MetalPlayViewC10didStopPIPyyF              MetalPlayView.didStopPIP()          [declared]
$s8KSPlayer13MetalPlayViewC11didStartPIP2toySo6UIViewC_tF  MetalPlayView.didStartPIP(to:)   [declared]
$sSo6UIViewC8KSPlayerE10didStopPIPyyF                   (extension in KSPlayer):UIView.didStopPIP()      ⛔ MISSING
$sSo6UIViewC8KSPlayerE11didStartPIP2toyAB_tF            (extension in KSPlayer):UIView.didStartPIP(to:)  ⛔ MISSING
```
`KSComplexPlayerLayer`'s PiP delegates call these on `player.view` (typed `UIView`), which is why
the MetalPlayView pair alone cannot satisfy them — exactly the same shape as `UIView.addSub(view:)`,
which this session had to reconstruct for the identical reason.

⚑ Like `addSub`, these are extensions on a foreign (`__C`) type, so `pin_sweep` does NOT list them
as MEMBER_MISSING — they score zero directly while unblocking rows. Expect the MetalPlayView pair
to be what the UIView extensions forward to.

⛔ Still blocking `pictureInPictureControllerDidStopPictureInPicture` @0x1019d62ec: after the
`didStopPIP` send it re-reads `player.view`, calls the private `KSPlayerLayer.addSubtitle(to:)`
(0x1019cf5d8, discriminator `33_B3181…LL`), and finishes in **0x1019d2bb0 — 227 instructions,
NOT_IN_TRIE**.

## [superseded] 2r. `MetalPlayView.didStartPIP`/`didStopPIP` are probably missing `@objc` — verify

Found while reading `KSComplexPlayerLayer.pictureInPictureControllerDidStopPictureInPicture`
@0x1019d62ec (81 instr, reached via the thunk at 0x1019d2bac). That body calls
`player` witness 4 (`view`, named earlier) and then sends **selector `didStopPIP`** to the result:
```
1019d6360  bl 0x103460dc0     ; selref 0x10440b138 = 'didStopPIP'
```
It is an **ObjC message send**, not a Swift direct call. `player.view` is typed `UIView`, which has
no such method, so for the compiler to emit a send the original must expose `didStopPIP()` as
`@objc` and dispatch it dynamically (an `AnyObject` call, or a cast to an @objc-visible type).

⚑ This session declared `MetalPlayView.didStartPIP(to:)` and `didStopPIP()` (commits a6410fe,
3255eee, corrected in d0fc8f3) WITHOUT `@objc`. Their bodies were read from their own
disassembly and are unaffected; what is in question is only the attribute. Adding `@objc` is the
obvious fix but was NOT applied blind — check whether the binary's method descriptors for those
two carry ObjC entry points (an `@objc` method emits a thunk and appears in the class's ObjC
method list), and add it only if they do.

⛔ The rest of that body is not yet landable: after the `didStopPIP` send it takes `player.view`
again, calls `KSPlayerLayer.addSubtitle(to:)` (0x1019cf5d8 — private, discriminator
`33_B3181…LL`), and finishes in **0x1019d2bb0, a 227-instruction NOT_IN_TRIE body**. Name that
before writing the row.

### `KSMEPlayer.checkShouldResume()` @0x101a43f40 (50 instr) — one field name short

Shape fully read; three of four names resolved:
```
ldrb w8,[x21,#0x47]  cmp #1  b.ne →        ; options.isDLNARunning
  strb wzr,[x20, <0x1044ea1c0>]            ; TARGET = false      ← dead, see below
ldrb w8,[x21,#0x46]  tbz w8,#0 →           ; options.enterForgeResumePlay
  w8 = 1                                   ; true
else ldrb w8,[x20, <0x1044ea1a8>] cmp #1 cset eq   ; playbackState == case 1
strb w8,[x20, <0x1044ea1c0>]               ; TARGET = that
```
- `+0x46` = `KSOptions.enterForgeResumePlay`, `+0x47` = `KSOptions.isDLNARunning` — both from
  `recover_field_offsets` (KSOptions is `metadata_init=1`, so the static vector is unreadable).
- `0x1044ea1a8` = `KSMEPlayer.playbackState : MediaPlaybackState` (`vpWvd`-named); the compare is
  against **case index 1**, which must be resolved against that enum's declaration order.
- ⛔ `0x1044ea1c0` — the field BEING WRITTEN — has **no `vpWvd`** and is NOT_IN_TRIE. Without it
  the row cannot be written.

⚑ Note the first store is DEAD: both the `b.ne` and the fall-through reach the second store to the
SAME global, so the `isDLNARunning` arm's `false` is immediately overwritten. Do not "tidy" that
away when writing the row — reproduce it or explain it, because it is what the binary does and it
suggests the original had an early exit the optimiser removed.

### `ReadCacheIOContext.close()` @0x101bad688 (42 instr) — and a TYPE DIVERGENCE it exposes

Body: copy `self+0x18` to a stack slot, `cbz` on the instance word for the nil arm, else load the
witness at `[wtable, #0x40]` (= slot 7) and `blr` it. The nil arm builds a value from metadata
0x1044f6928 / 0x103572200 and calls 0x10003751c.

⚠️ **`download` is declared `URLContextDownload?` but the binary treats it as a two-word
EXISTENTIAL.** The body reads the instance from `[sp,#0x20]` and a witness table from `[sp,#0x28]`,
then dispatches through that table — a concrete class reference is one word with no witness table
and would be called directly. So the field's real type is `(any DownloadProtocol)?`.
⚑ That matches this repo's own note on `LimitCountPreLoadIOContext`, which records `download` as
"the EXISTENTIAL `any DownloadProtocol`, not the concrete URLContextDownload" for the sibling init
— so the divergence is already known one level up and simply was not applied to this field.

⛔ To land the row: retype `download`, then name DownloadProtocol witness slot 7 (use a conformer's
table and read the trie name — do NOT count requirements; see §2f). Retyping touches the field's
other users, so it is its own unit.

### `KSOptions.colorSpace` — the source has TWO overloads; the binary has ONE. Real divergence.

`pin_sweep` files this under NOT_IN_TRIE with the note "informational, NOT a correction (likely
inlined or an overload)". **That note is too weak — this is a genuine arity divergence**, and it
was worth chasing:

| | |
|---|---|
| source, Model.swift:151 | `static colorSpace(ycbcrMatrix:transferFunction:)` — full reconstructed body |
| source, Model.swift:180 | `static colorSpace(colorPrimaries:)` — full reconstructed body |
| **binary** | `static colorSpace(colorPrimaries:transferFunction:dovi:) -> CGColorSpace?` |

The binary has ONE function taking all three, including a **`dovi:` parameter neither source
overload has at all**. Its trie address 0x1019c1044 is a 1-instruction THUNK (`b 0x1019c6878`);
the real body is **168 instructions @0x1019c6878** — roughly the two source bodies merged plus
Dolby-Vision handling, which is consistent with one function rather than two.

⚑ Do not "fix" this by renaming a parameter. Landing it means reading 0x1019c6878 and replacing
BOTH source overloads with the single 3-parameter function, then updating their call sites.

⚑ This also bears on the EDR helper above: 0x101ac00c8 does `screen` / `currentEDRHeadroom` /
`CGColorSpaceCreateWithName`, which is colour-space selection but with a DIFFERENT shape (screen
headroom, not primaries/transfer). So it is NOT this `colorSpace` — the candidate is ruled out,
and its owner is still unidentified.

### ⭐ 2s-bis. READ A VTABLE SLOT OUT OF THE METADATA — do not do offset arithmetic across a chain

`IOSVideoPlayerView.pause()` dispatches through metadata word `+0x78`. I first tried to attribute
that by arithmetic: `VideoPlayerView`'s `VTableOffset` is 60 words (0x1e0) and its table is 50
entries, so 0x2c0 "is" its slot 28 — which came back `seekToView.setter`, obvious nonsense for a
`pause()` body. **Two** things were wrong, and both are structural, not slips:

1. **The receiver was not `self`.** The `+0x2c0` call is on the object RETURNED by the `+0x78`
   call, not on `self`. Read the prologue before assuming a dispatch is a self-call.
2. **Arithmetic across an inherited range is guesswork.** `+0x78` is metadata word 15 — below
   `VideoPlayerView`'s own table entirely, in territory inherited from further up. `PlayerView`
   answers `refused: no-vtable`, so there is no chain to walk arithmetically.

**The route that works:** read the word straight out of the class metadata and name the pointer.
`export_trie_oracle.py --symbol '$s8KSPlayer18IOSVideoPlayerViewCN'` → 0x1044234e8; word `+0x78`
holds the chained-fixup rebase `0x0010000001b2b75c`, whose low 32 bits + 0x100000000 give
0x101b2b75c = `VideoPlayerView.playerLayer.getter` (and `+0x80` is its setter). No arithmetic, no
chain walk, one lookup. Use this whenever a dispatch offset falls below the class's own
`VTableOffset`.

⚑ Only `--symbol` exists for name→address (`--name` is not a flag), and
  `reconstruction/export_trie_names.json` is a **list of names with no addresses** — it can tell
  you a symbol EXISTS but never where it is.

### `IOSVideoPlayerView.pause()` @0x101b10a54 (91 instr) — ✅ RESOLVED AND LANDED

- ✅ `playPauseButton` is `vpWvd`-named (global 0x1044f0e98, `UIButton`) and already declared
  (IOSVideoPlayerView.swift:63).
- ✅ The image is built from an SF Symbol: x22 is assembled by `mov`+3×`movk` into the 8 bytes
  `70 6c 61 79 2e 66 69 6c` = `"play.fil"`, with x1 carrying the 9th byte `0x6c` (`l`) and count
  byte **0xE9** (= 0xE0|9) — i.e. the small string **`"play.fill"`**. It is bridged via
  `String._bridgeToObjectiveC` and passed to classref 0x104410600 = `UIImage` with selector
  **`systemImageNamed:withConfiguration:`** (selref 0x10440e530).
  ⚑[tool=decode_objc_selector ref=0x10440e530 result='systemImageNamed:withConfiguration:']
- ✅ The opening is `super.pause()` — see 2s-bis above for how `+0x78` was attributed, and the
  member's own doc comment for why `super.` rather than a re-spelled `playerLayer?.pause()`
  (the sibling `play()` carries the superclass's SECOND statement, which a re-spelling could not).
- ✅ Globals 0x1044f0f88 / 0x1044f0f90 named — see 2u below. This is the first case where a field
  had to be named with NO `vpWvd` symbol available at all.

## 2u. NAMING A FIELD WITH NO `vpWvd` — anchor a store RUN, do not trust its order

`IOSVideoPlayerView` exports exactly **18** `vpWvd` symbols and none is a config, so the symbolic
route was simply unavailable for 0x1044f0f88 / 0x1044f0f90. Offset arithmetic was out too — the
18 recovered globals run 0xe20…0xea0 for field indices 6…23 but then jump straight to `title`
(index 41) at 0xea8, so they are emission-ordered, not index-ordered. What worked:

1. **Find the initializer's store run.** Scan `__text` for `adrp 0x1044f0000` + `ldr` with the
   target imm12, then look for the site where several land together. At 0x101b131d4 three configs
   are built and stored back-to-back, then `str xzr` to a fourth global.
2. **Anchor the run on VALUES, not on its order.** Order alone would be an assumption. Two members
   of this run are pinned independently of it: 0xf90 receives pointSize **15.0**, and only
   `toolBarPlayButtonConfig`'s `vpfi` (0x10199b3fc) uses 15.0; 0xf58 receives **`xzr`**, and only
   an Optional can be nil — index 52, `topStatusLeadingConstraint`. With positions 3 and 4 fixed,
   the run is field-record order and 0xf88 = `playButtonConfig`.
3. **Look for an ICF corroboration.** `playButtonConfig`'s `vpfi` (0x10199ef50) is a bare `b` to
   `jumpButtonConfig`'s body — initializers fold only when textually identical, which is exactly
   why 0xf98 and 0xf88 both receive 32.0. A third independent agreement.

⚑ `recover_field_offsets.py --global` REQUIRES `--class`; without it the tool errors rather than
  searching, and the error is easy to mistake for "not found".
⚑ A `vpfi` is frequently INLINED — scanning for `bl` to the three vpfi addresses returned zero
  call sites even though init plainly initializes all three. Absence of a call site is not absence
  of the initializer; fingerprint its CONSTANTS in the caller instead.

## 2v. `0xA0|count` IS A SMALL STRING — the `0xE0` rule is ASCII-only

`READING_THE_BINARY.md` said the small-string discriminator is `0xE0 | count`. That is the
**all-ASCII** form only; a small string containing any non-ASCII byte uses `0xA0 | count`.

`Anime4KPreset.displayName`'s `.disabled` arm is the case in point: its second word is
`0xA600000000000000`, which reads as "not a small string" under the `0xE0` rule and would have been
left undecoded, while the first word `0x0000ad97e9b385e5` is simply the UTF-8 run
`e5 85 b3 e9 97 ad` = 关闭. When the top byte is `0xA0|n`, decode the two words as `n` raw UTF-8
bytes, low word first.

⚑ That arm was reached by a jump-table byte pointing at a **bare `ret`** rather than at a switch
  arm, so what it returned was the x0/x1 pair built at the TOP of the function. A table entry that
  lands on a `ret` is a real case, not a default — do not skip it.

⚑ **This is mirrored here on purpose.** `play/docs/` is gitignored, exactly like `play/scripts/`,
  so the edit to `READING_THE_BINARY.md` exists ONLY on this disk. Only
  `KSPlayer/docs/superpowers/specs/` is tracked. Any durable correction to a routed-context doc has
  to be copied into a spec or it does not survive the machine. This joins
  `recover_field_offsets.py` and `method_source_presence.py` on the disk-only list.

## 2w. TWO GATE GOLDENS WENT RED BECAUSE THE WORK SUCCEEDED — repaired, not relaxed

`recon_gate --mode handoff` went PASS 42 / FAIL 6 → **PASS 44 / FAIL 4**. Both repairs are in
`play/scripts/`, which is **gitignored**, so they exist only on this disk — recorded here for the
same reason 2v is.

**`sc_placement_sweep`** — its two NEGATIVE controls asserted that
`MediaPlayerProtocol.subtitlesTracks` (0x1019dffb8) and `.videoFormat` (0x1019e04f0) read
`NOT_IN_SOURCE`. This session declared both, so the controls failed *because the goal was met*.
This is `golden-anchored-on-mutable-path-rots` in its purest form: a control keyed on a member's
ABSENCE, inside a project whose entire purpose is to end absences.

- The expectation was NOT relaxed. Re-anchoring on a different absent property was tried first and
  is **impossible**: the sweep now reports **zero** `NOT_IN_SOURCE` property getters — that seam is
  closed.
- Both rows flipped to POSITIVE controls (`MATCH`, plus `fileid == MediaPlayerProtocol.swift`), so
  the same code path is still asserted, in the direction that is now true.
- Falsifiability was re-expressed so it **cannot rot**: the property matcher must return `[]` for a
  name absent from the type's scope, and a hit for one present. That holds no matter how much of
  the binary gets reconstructed — which is exactly what a body-anchored control cannot promise.

**`sc_stale_screen`** — the long-standing red. Repaired by the protocol the fixture states for
itself: `[248, 390, 463] → [287, 429, 502]`, all three moving by exactly **+39**, and
`git diff -U0 ab45e5f..HEAD -- Sources/KSPlayer/AVPlayer/KSPlayerLayer.swift` restricted to hunks
above old line 248 is `added=41 removed=2`, **net +39**. The delta matches the diff, so the spans
themselves are untouched — this session declared `reachEndOfStream`, `makeUIView`, `pipStop` and
two `KSComplexPlayerLayer` PiP delegates above them.
⚑ The *uniform* +39 is a second, independent check: it proves nothing was inserted BETWEEN the
  spans. Matching a single span would not have caught that.

**Still red, and NOT this session's** (do not attribute them to the member work):
`agg_critical 6`, `agg_high 24`, `agg_unresolved 1`, and `sc_wave_worklist`. The last one is
`0x101a6ce44` = `VideoToolboxDecode.decodeFrame(from:completionHandler:)`,
OPEN in `wave_exclusions.json` since **s93** and now vanished from the waves because the member is
declared (VideoToolboxDecode.swift:52). Its residual work is small and bounded: verify the four
`// P3 lastPosition->maxTimestamp` compile-placeholders at VideoToolboxDecode.swift:145, :146,
:148, :153. That is a faithfulness defect sitting in LANDED source — worth a session, but it is
adjudication debt, not a MEMBER_MISSING row.

## 2x. ⭐ `KSPictureInPictureProtocol` IS HALF MISSING — 10 requirements in the binary, 5 in source

This is the **single highest-leverage open item** found this session. It blocks the largest
remaining MEMBER_MISSING cluster (`KSComplexPlayerLayer`, 13 rows) at its first member.

`KSComplexPlayerLayer.pause()` @0x1019d1bc0 (68 instr) is read end to end and is three statements:

```
isPictureInPictureStoped = false                      // strb wzr, [self, <global 0x104c63520>]
player.pause()                                        // MediaPlayerProtocol witness wt+0x128
MPNowPlayingInfoCenter.default().playbackState = .paused   // state 2
player.pipController?.<req4>()                        // KSPictureInPictureProtocol witness wt+0x28
```

- `isPictureInPictureStoped` is DECISIVE by elimination: the class has exactly **3** fields
  (`urls`, `isPictureInPictureStoped`, `enterBackgroundTask`) and only one is a `Bool`.
- `player` is `KSPlayerLayer`'s field 5, the class's only 2-word `_p` existential.
- ⚑[tool=bind_oracle ref=__objc_classrefs:0x104410a10 result=_OBJC_CLASS_$_MPNowPlayingInfoCenter]
  ⚑[tool=decode_objc_selector ref=0x10440b040 result='defaultCenter']
  ⚑[tool=decode_objc_selector ref=0x10440d8c8 result='setPlaybackState:']
  `w2 = 2` is `MPNowPlayingPlaybackState.paused`.
- ⚑[tool=export_trie_oracle ref=0x101a3d3d0 result=KSMEPlayer.pipController.getter:KSPictureInPictureProtocol?]

**The blocker.** The protocol descriptor @0x1039ecde0 declares `NumRequirements = 10`. The source
declares **5**, and not even in the binary's order. Walking `KSPictureInPictureController`'s witness
table @0x1041d45a0, slot by slot:

**The table is VALIDATED before it is used.** `wt[0]` → conformance descriptor 0x1035676b0, whose
`.protocol` field resolves to **0x1039ecde0** — the same descriptor the count came from. So these
ten slots really are this protocol's ten requirements, in order.

**Kinds come from the descriptor, not from guessing at bodies.** The `ProtocolRequirement` array
sits at `descriptor + 24 + 12*NumRequirementsInSignature` = 0x1039ece04, 8 bytes per entry
(`Flags:u32`, `DefaultImplementation:rel32`); kind is the low nibble of Flags, `0x10` is
`IsInstance`. That is what separates a getter from a method from an init — the witness body cannot.

| slot | wt off | kind (from flags) | witness | name |
|------|--------|-------------------|---------|------|
| req0 | 0x08 | Getter, instance | 0x1019c7680 → sel `isPictureInPictureActive` | **`var isPictureInPictureActive: Bool { get }`** ✓ in source |
| req1 | 0x10 | Method, instance | 0x1019c7698 → 0x1019c769c | ⛔ unnamed; large body doing generic-metadata work |
| req2 | 0x18 | **Init** | 0x1019c779c → sel `initWithPlayerLayer:` | **`init(playerLayer:)`** — MISSING from source |
| req3 | 0x20 | **Init** | 0x1019c74e4 | **`init(contentSource: AVPictureInPictureControllerContentSource)`** — MISSING from source |
| req4 | 0x28 | Method, instance | 0x1019c77d8 → sel `invalidatePlaybackState` | ⛔ unnamed (see below) |
| req5 | 0x30 | Method, instance | 0x1019c77e0 → sel `valueForKey:` | ⛔ unnamed; takes a String, returns indirectly |
| req6 | 0x38 | Method, instance | 0x1019c75cc | `start(layer:)` ✓ in source |
| req7 | 0x40 | Method, instance | 0x1019c75d4 | `didStart(layer:)` ✓ in source |
| req8 | 0x48 | Method, instance | 0x1019c7648 | `stop(restoreUserInterface:)` ✓ in source |
| req9 | 0x50 | Method, **STATIC** | 0x10000e52c | **`static func play(layer:)`** ✓ in source |

Three things fall out that no amount of body-reading would have given:

1. **req9 is the ONLY static requirement**, and `static func play(layer:)` is the source's only
   static one. That is a decisive, unique match — and its witness is the ICF-folded empty body at
   0x10000e52c, so `KSPictureInPictureController.play(layer:)` is genuinely `{}`.
2. **req2 and req3 are `Init` requirements.** The source protocol has no initializer requirement at
   all. req3's witness is trie-named `__allocating_init(contentSource:)`, and a witness must match
   its requirement's full name, so the requirement label is read, not inferred; req2's selector
   `initWithPlayerLayer:` maps mechanically to `init(playerLayer:)`.
3. **The five missing requirements are CONTIGUOUS at positions 1–5.** The source's five sit at
   0, 6, 7, 8, 9. So the repair is an insertion between `isPictureInPictureActive` and
   `start(layer:)`, not a reshuffle — which also means the source's relative order was never wrong,
   only incomplete.

Still unnamed: req1, req4, req5. A protocol emits no per-requirement symbol, so their labels are
not in the trie; the only evidence is one conformer's forwarding selectors.

⚑ **Why `pause()` was NOT written.** Its last statement needs req4's NAME, and Swift emits **no**
  per-requirement symbol for a protocol — only `Mp` and `TL`, both present and neither carrying
  requirement names. The only evidence for req4 is that this one conformer's witness forwards to
  `invalidatePlaybackState`. Bolting a guessed requirement onto a public protocol would propagate
  the guess into every conformer, so the protocol is its own unit and should be re-derived whole,
  the way s98 did `PixelBufferProtocol`'s missing four.

⚑ Finding the protocol's own symbols needs the **compressed** spelling. `KSPictureInPictureProtocol`
  inside `KSPictureInPictureController`'s conformance mangles to `AA0bcD8ProtocolAA`, so a substring
  search for `PictureInPictureProtocol` misses the `WP` and `Mc` entirely — §2h again. Where the
  name IS spelled out, the length prefix is the identifier's own character count:
  `26KSPictureInPictureProtocol` and `28KSPictureInPictureController`. Using the controller's 28
  for the protocol returns nothing, which reads exactly like "the symbol does not exist".

## 2t. TWO rows have NO RECOVERABLE BODY — deleted methods. Measured, not assumed.

`IOSVideoPlayerView.toggleBottomSlimProgress` and `IOSVideoPlayerView.updateTitle` both resolve to
**0x10198eb18**, whose four instructions are `stp` / `mov` / `bl` / `brk #0x1`, and that `bl` goes
through __got 0x104112df0 = **`swift_deletedMethodError`**. 376 symbols share the address.

⇒ The trie NAMES these members (their method descriptors survive) but their implementations were
eliminated. There is no body to read, so there is nothing faithful to write — an empty body would
assert "does nothing", which is not what a deleted method means. **These two rows cannot be closed
by reconstruction.** Do not spend time on them; do not declare them as no-ops.

⚑ Scope MEASURED across the whole queue rather than guessed: exactly **2** rows sit on the
deleted-method fold and **0** sit on the empty-body fold 0x10000e52c. So this is a bounded
curiosity, not a systemic drain — the remaining 124 rows do have bodies.

⚑ Distinguish the two folds, they are easy to confuse and mean opposite things:
`0x10000e52c` = a bare `ret` ⇒ a REAL empty body, safe to declare as `{}` (that is how
`UIView.didStartPIP`/`didStopPIP` landed). `0x10198eb18` = `swift_deletedMethodError` ⇒ NO body.

## 2s. ⭐ THE SINGLE HIGHEST-LEVERAGE UNBLOCK: expose libavformat's `ffurl_*` in FFmpegKit's shim

This is one decision, it is the human's to make (it edits an external dependency), and it unblocks
a whole cluster. **Do this before grinding more rows.**

`FFmpegKit`'s `avformat_shim.h` declares `URLContext` but none of the `ffurl_*` entry points, so
every body that drives a URLContext directly fails to compile with
`cannot find 'ffurl_…' in scope`. Verified by building — the `fileSize` attempt went 3/4 and was
reverted.

**Symbols identified from their own bodies** (the FFmpeg name oracle is ambiguous for both —
59 candidates for the first — so each was read, not looked up):
- **0x1030c07ac = `ffurl_seek`** — `h->prot` at +0x8, `prot->url_seek` at +0x38, `mov x0,#-0x4e`
  = AVERROR(ENOSYS) when null, and `and w2,w2,#0xfffdffff` clearing bit 17 = AVSEEK_FORCE.
- **0x1030c0554 = `ffurl_closep`** — takes `URLContext**`, `ldr x20,[x0]` = `h = *hh`, `cbz`
  early-return, `ldr w8,[x20,#0x2c]` = `h->is_connected`, `prot->url_close` at
  `[[x20,#0x8],#0x40]`, then `tbnz` on bit 1 of `prot->flags` (+0x84) = URL_PROTOCOL_FLAG_NETWORK.

**Rows this gates — FOUR now CONFIRMED by reading, not guessed by shape:**
| row | addr | body |
|---|---|---|
| `URLContextDownload.fileSize` | 0x101b91150 | `ffurl_seek(context, 0, AVSEEK_SIZE)`, `-1` when nil |
| `HLSCacheIOContext.fileSize` | 0x101b975e0 | same call, reaching `context` one hop further |
| `HLSCacheIOContext.seek` | 0x101b9757c | `ffurl_seek(context, offset, whence)`, `-1` when nil |
| `URLContextDownload.close` | 0x101b91198 | `ffurl_closep(&context)` under a MODIFY access, nil-guarded |

⚑ `HLSCacheIOContext.seek` and `fileSize` share a reach: `self+0x18` then `+0x18` again — the
inner object is the one holding the `URLContext`. Both nil-guard it and return `-1`.
Still unread but the same shape: `URLContextDownload.read`/`seek`, and the `close`/`seek` pairs on
`CacheOnlyIOContext` / `LimitSeparatePreLoadIOContext` / `ReadCacheIOContext`.

⚑ Do NOT substitute a public API (`avio_*`) for these: the bodies pass `URLContext*`, which is
libavformat-internal, and `avio_seek` takes an `AVIOContext*`. It would compile and be a different
call.

## 2q. NEGATIVE RESULT — two routes to a global→field-name tool, both closed. Don't rebuild them.

The recurring blocker is naming an offset global in a `metadata_init=1` class when it has no
`vpWvd`. Two plausible mechanisations were tried this session and BOTH fail; record them so the
next session doesn't spend the time.

**(1) "Read the metadata completion function's stores."** The idea: the completion function copies
runtime-computed offsets into the per-field globals in field order, so the store sequence gives
global→index. Scanned all of `__text` for `ADRP` + `STR` (64-bit, unsigned offset) targeting any of
MetalPlayView's seven known globals: **zero hits**. Nothing in `__text` writes those globals with
that instruction pair, so there is no store sequence to read. (The runtime almost certainly writes
them itself via the `fieldOffsets` buffer passed to `swift_initClassMetadata`, leaving no
per-global store in the image.)

**(2) "The globals are one contiguous array in field order."** Tempting, and locally true:
rotation(3)=0x8b0 · pixelBuffer(4)=0x8b8 · options(5)=0x8c0 · renderSource(6)=0x8c8 ·
drawable(7)=0x8d0 — five consecutive indices at stride 8, which extrapolates to base 0x898.
⛔ **Refuted by a stronger anchor.** That base makes 0x8a0 index 1 = `formatDescription`, but the
init casts `<0x8a0>.layer` to `CAMetalLayer` and only `MetalView` declares
`layerClass = CAMetalLayer.self` — so 0x8a0 is `metalView`, index 8. Contiguity holds for the 3–7
run and NOT across the class. It also predicts the array ends at 0x918, yet `play`/`pause`/
`enterBackground` all index self by **0x928**, which is outside it.

⇒ Global→name has TWO reliable routes. Try them in this order — the second is cheaper and was
missed for most of this session:

**(a) ELIMINATION on type + `vpWvd` coverage.** Get the class's field list (`l2_field_gate` prints
binary types in order) and its `vpWvd` globals. If N fields share the target's type and exactly
N−1 of them carry a `vpWvd`, the remaining one IS the target. Confirm the width from the store
opcode (`strb` = 1 byte, `strh` = 2, `str` = 8). This named `KSMEPlayer.shouldResumePlayback`
(5 Bools, 4 with `vpWvd`), `Anime4KFrameDump.frameCounter` (2 Ints, the other written by
`configure`), and `LimitCountPreLoadIOContext.moreCount` (2 UInt16s, split by mutability).
⚑ It FAILS when coverage is thin: `KSPlayerLayer` has 3 Bools and only ONE `vpWvd`
(0x104c63508 = `isAutoReplaceAndConstrainPlayerView`), so global 0x104c63520 — the play-state flag
`KSComplexPlayerLayer.pause()` writes — has TWO candidates (`isAutoPlay`, `isWirelessRouteActive`)
and stays open. Both of their accessor triples are ICF-folded onto 0x10198eb18, the deleted-method
fold, so that route is closed too.

**(b) A type-revealing use site** — conformance witness, metadata accessor, or a selector unique to
one type. Slower, but works when (a) is ambiguous. This is how 0x1044ea8a0 became `metalView`.

⛔ NEVER offset arithmetic. Checked on three classes and it is index-ordered on NONE of them:
MetalPlayView (0x8a0 = field 8 while 0x8b0 = field 3), KSMEPlayer (0x130 = field 13 while
0x140 = field 1), KSPlayerLayer (0x500 = field 15 right after 0x4f8 = field 6). The globals are
allocated per-field but NOT in field order, and only for a subset of fields.

## 2c-CORRECTION (read this BEFORE §2c — §2c below is WRONG)

⛔ **§2c is my own error, made in this session's first turn and repeated since. The s105 plan was
NOT refuted; my grep was invalid.** Retract it.

`MetalPlayView` has **`metadata_init=1`**. For such a class, field accesses do NOT use literal
offsets — they load the offset from a per-field global and index with a register:
`ldr x8,[<global>]` / `str …,[x0,x8]`. §2c searched `init(options:)` for literal `#0x1c` / `#0x48` /
`#0x78` / `#0xa0` and concluded "those assignments are not in `init(options:)` at all". That
instruction form **cannot occur** for this class, so the search could only ever return nothing. It
was a false negative, not a finding.

✅ Re-run correctly, `init(options:)` @0x101a5eda8 references the offset globals directly —
`#0x8a0` (displayView) ×2 · `#0x8a8` (metalView) ×2 · `#0x8b8` (pixelBuffer) · `#0x8bc` · `#0x8c0`
(options) · `#0x8c8` (renderSource) · **`#0x8d0` (drawable)** · `#0x8d8` · `#0x8e0` · `#0x8e8` ·
`#0x8f0` · `#0x8f8`. The assignments are there. **Follow the s105 plan.**

⚑ Generalise: when hunting a field access in ANY `metadata_init=1` class, grep for the field's
OFFSET GLOBAL (`ldr` from `0x1044ea8xx`), never for a literal `#0xNN`. Check `vtable_walk`'s
`metadata_init` flag before choosing which form to search for.

⚑ Two further corrections to §2c's framing:
- `init(frame:)` @0x103396154 IS inside `__text` and IS an 11-instruction
  `fatalError`-style trap — that part of §2c stands.
- REAL_FLAG 11 does **not** block commits (it is a WARN); see §2p. MetalPlayView committed four
  times this session.

⚑ **Six of the eight "unknown default" fields do not need the init at all** — they carry a `vpfi`,
read this session:
  `isPaused` @0x10002c740 → `mov w0,#1` = **true** (⚑ NOT false — writing `= false` here is exactly
  the fabrication the standing rule forbids) · `isBackground` @0x10002dab0 → **false** ·
  `dovi` @0x10011a290 → `mov x0,#0` / `mov w1,#0x100` = **nil** · `rotation` → **0** (landed) ·
  `backgroundTimer` @0x10199ae4c and `flickerDetector` @0x10199afb4 have REAL initializer bodies,
  not constants. Only `drawable` and `renderUseDispatchSourceTimer` have no `vpfi` and must come
  from the init.

### `MetalPlayView.drawable` — init site LOCATED, type pinned, body not yet read

Applying the corrected method above (grep the offset global, not a literal) finds it immediately:
`init(options:)` touches drawable's global `#0x8d0` exactly once, at **0x101a5f0ec**, and the
surrounding block is the construction:
- `ldr x0,[0x104410d20]` → an ObjC classref through `objc_opt_self`, then `bl 0x10345ccb8` with
  `(x19, class, 0, 0, 0)` — a dynamic cast of an already-computed object.
- `add x21, x25, x8` forms `&self.drawable` (x25 = self).
- the block references witness table **0x1041d9e70 = `$sSo12CAMetalLayerC8KSPlayer8DrawableACWP`**,
  i.e. the **`CAMetalLayer : Drawable`** conformance.

So `drawable` is a stored existential holding a `CAMetalLayer`. `Drawable` itself already exists
(Drawable.swift:28), so no type stand-up is needed. Its accessors confirm stored, not computed:
the getter @0x101a5ec80 is a `beginAccess` on the offset global plus an outlined indirect copy
(`bl 0x1001263e0`) into the sret — no computation.

⚑ It has **no `vpfi`**, so there is no declaration default and `= something` would be fabrication;
the value must come from this init block.

**The chain is now read end to end** — and it contains a surprise that must be settled before the
row is written:
```
101a5eefc  ldr  x19, [x8, #0x8a0]      ; the *displayView* offset global
101a5ef00  stur x19, [x29, #-0xd0]     ; saved
…
101a5f098  ldur x8,  [x29, #-0xd0]
101a5f09c  ldr  x19, [x25, x8]         ; x25 = self  →  self.<field@0x8a0>
101a5f0ac  bl   0x1034646a0            ; selref 0x10440bf70 = 'layer'
101a5f0e0  bl   0x10345ccb8            ; dynamic cast, class from classref 0x104410d20
101a5f0ec  ldr  x8, [x8, #0x8d0]       ; drawable's offset global
101a5f0f0  add  x21, x25, x8           ; &self.drawable
```
i.e. `drawable = <field@0x8a0>.layer as CAMetalLayer`.

## ⛔⛔ OPEN DEFECT — `flush()` DOES NOT MATCH THE BINARY, and two of this session's commits depend on it

**Verify this first, before any further MetalPlayView work.** Hypothesis (b) is refuted: the stack
slot `[x29,#-0xd0]` is written exactly ONCE in the whole init (at 0x101a5ef00, from the 0x8a0
global) and read at 0x101a5f098 — no overwrite. That leaves (c), and (c) now looks likely.

Re-reading `flush()` @0x101a60488 branch-by-branch:
```
101a60510  bl 0x103463f40            ; 'isHidden' on the 0x8a0 field
101a60514  tbz w0,#0 → 0x101a60564   ; isHidden FALSE goes here
101a60518  ldr 0x8a8 → 'layer' → dynamic cast (classref 0x104410d18) → bl 0x103461e80   ; isHidden TRUE
101a60564  ldr 0x8d0 (drawable) → beginAccess → outlined copy 0x1001263e0               ; isHidden FALSE
```
The source reconstructs it as
`if displayView.isHidden { metalView.clear() } else { displayView.displayLayer.flushAndRemoveImage() }`.
The TRUE arm plausibly matches `metalView.clear()` if that inlines to `layer as! …`, but the FALSE
arm in the binary reads **`drawable`** (0x8d0) — it does not touch a `displayLayer` accessor at all.
So the reconstructed `flush()` and the binary disagree on the else branch.

⚠️ **Consequence for commits a6410fe and 3255eee.** This session named 0x1044ea8a0 `displayView`
BY CROSS-REFERENCE FROM `flush()`'s source — "flush sends isHidden to 0x8a0 and its source says
`displayView.isHidden`". If `flush()` is itself mis-reconstructed, that inference is unsound, and
`didStartPIP` / `didStopPIP` may name the wrong field. Their SHAPE (the `isHidden` guard, the
`addSub` direction, `frame = bounds`) is read directly from their own bodies and is unaffected —
only the field's NAME is at risk.

⚑ The offset-global arithmetic cannot rescue it either: the five `vpWvd` globals map indices 3→7
onto 0x8b0→0x8d0 at stride 8, and extending that run backward gives 0x8a0 → index 1
(`formatDescription`) and 0x8a8 → index 2 (`fps`) — neither of which can answer `isHidden` or
`.layer`. So the global array is NOT simply index-ordered across this class, and no arithmetic
route to these two names exists. Find an independent anchor (a body whose source is verified
against the binary, not merely plausible) before trusting either name.

⛔ **The original surprise, still unresolved:** 0x1044ea8a0 was read as `displayView`, not `metalView` — and that assignment is not a
guess, it is what `flush()` proves (§2p): flush sends `isHidden` to 0x8a0 and calls `clear()` on
0x8a8, matching its source `if displayView.isHidden { metalView.clear() }`. But
`displayView` is an `AVSampleBufferDisplayView`, whose layer is an `AVSampleBufferDisplayLayer`,
NOT a `CAMetalLayer` — so a `CAMetalLayer` cast of *its* layer should not succeed.
Either (a) the cast is conditional (`as?`) and this is a deliberately-failing path, (b) the
saved offset at [x29,#-0xd0] is overwritten between 0x101a5ef00 and 0x101a5f098 by a store this
read did not cover, or (c) the displayView/metalView assignment is inverted and `flush()`'s
reconstruction is itself wrong. **Check (b) first** — scan the intervening ~100 instructions for
another `stur … [x29,#-0xd0]` — then (a) by identifying 0x10345ccb8 and the classref 0x104410d20.
Do not write the row until this resolves; all three readings produce different, plausible source.

## 2c. ⚠️ [RETRACTED — see 2c-CORRECTION above] `MetalPlayView` §3.1 — the s105 plan's PREMISE IS REFUTED, do not follow it

`metalplayview_field_types_s105.md` says the unit is "a full body read of 436 instructions" whose
payoff is "transcribing the eight assignments" from `init(options:)` @0x101a5eda8. **There are no
such assignments.** Re-derived this session:

- The field offsets re-derive exactly as that doc records them (vector @0x104422c28, 17 fields:
  isPaused 0x8 · rotation 0x1c · drawable 0x48 · dovi 0x78 · isBackground 0x82 · backgroundTimer
  0xa0 · renderUseDispatchSourceTimer 0xa8 · flickerDetector 0xb0 · forcedFrameRetryScheduled 0xc9).
- Across all 436 instructions of `init(options:)`, the offsets `0x1c / 0x48 / 0x78 / 0xa0` appear
  **zero** times in any instruction form, and the whole store set is only: `[x8]`, `[x8,#0x8]`,
  `[x8,#0x10]`, `[x8,#0x18]`, `[x0,#0x8]`, `[x21]`, `[x21,#0x18]`, `[x23]`. None is a field store
  at a missing field's offset.
- `__allocating_init` @0x101a5ed78 is 12 instructions — allocate, call through. No stores.
- **`init(frame:)` is NOT "outside __text"**, as that doc states. It is at 0x103396154, well inside
  `__text` (which ends 0x103451708), and it is 11 instructions ending `bl 0x10345b8b4` / `brk #0x1`
  — a `fatalError("init(frame:) has not been implemented")` trap. It initialises nothing.

So whoever takes this unit should NOT start by hunting eight stores. Find where the fields are
actually written first — an outlined initialisation helper called from `init(options:)` is the
obvious candidate, since that body makes many calls. Until that is answered the eight defaults
remain unknown, and `= false` on the Bools is still fabrication.

**Why it is worth doing anyway:** `l2_field_gate` re-derives REAL_FLAG 11 on this class (9 fields
in binary absent from source, plus `isDovi` and `displayLayerDelegate` present in source and absent
from the binary), and that blocks every commit to `MEPlayer/MetalPlayView.swift` — which is where
FOUR of the callee-resolution screen's top rows live (`rotation` ×3 bodies, `drawable`,
`didStartPIP`, `didStopPIP`). Clearing it unblocks 7 MetalPlayView rows at once.

⚑ Note the file path: the class lives in `Sources/KSPlayer/MEPlayer/MetalPlayView.swift`, not
`Metal/`, which is where an `l2_field_gate --file` invocation will fail if taken from the doc.

### `KSComplexPlayerLayer.pause()` @0x1019d1bc0 (68 instr) — read except ONE field name

```swift
override public func pause() {
    <field@0x104c63520> = false
    player.pause()
    MPNowPlayingInfoCenter.default().playbackState = .paused
    …                                    // tail not yet read
}
```
Everything except the field is resolved:
- witness `[x21,#0x128]` = slot 36. NOT_IN_TRIE at KSMEPlayer, but it is a one-instruction thunk —
  **follow it** → 0x101a4390c = `KSMEPlayer.pause()`. (Third time this escalation has worked.)
- classref 0x104410a10 = `OBJC_CLASS_$_MPNowPlayingInfoCenter`; selrefs 0x10440b040 =
  `defaultCenter`, 0x10440d8c8 = `setPlaybackState:`; the argument is `mov w2, #2`, and
  `MPNowPlayingPlaybackState` case 2 is `.paused`.

⛔ **Blocked only on naming global 0x104c63520.** It has NO `vpWvd`. The cross-reference scan finds
16 sites in 12 functions — `KSPlayerLayer.play` · `pause` · `seek` · `readyToPlay` · both inits ·
`set(url:options:)` · `replace(item:…)` · `KSComplexPlayerLayer.pause` · `playNextURL` · 2
NOT_IN_TRIE. That profile is a **play-state flag** (cleared on pause, touched by every transition),
and `isAutoPlay` is the obvious source candidate.
⚑ **The accessor route was tried and is closed for this class.** KSPlayerLayer's only Bool with a
real `vpWvd` is `isAutoReplaceAndConstrainPlayerView` @**0x104c63508** — not 0x520. And the
obvious candidate cannot be reached that way: `isAutoPlay`'s getter, setter AND modify all resolve
to **0x10198eb18**, the deleted-method fold, as do `isWirelessRouteActive`'s — their accessors were
stripped, so no named body reads the global. Known KSPlayerLayer globals are 0x4f0 `player` ·
0x500 `subtitleModel` · 0x508 `isAutoReplaceAndConstrainPlayerView` (and 0x528 `urls` on the
subclass); 0x510/0x518/0x520 are unnamed.

⚑ It was NOT written. Every naming site is a *reconstructed body*, and this session proved twice
(§2p, and the `flush`/`play` defects) that MetalPlayView-style source cross-references can be
wrong. Needs a type-revealing binary site — or accept it only once some body in that set has been
verified instruction-by-instruction against the binary.

## 2d. `KSComplexPlayerLayer` — 16 rows, per-class setup ALREADY PAID (start here)

The class is declared (KSPlayerLayer.swift:891) with all 3 fields, so this is pure member work.
`set(urls:)` landed this session; **15 rows remain**. Everything below is re-derived, not quoted —
reuse it instead of paying it again:

- **All 16 addresses** (trie): change 0x1019d1890 · finish 0x1019d20bc · pause 0x1019d1bc0 ·
  play 0x1019d1a8c · stop 0x1019d2594 · reCheckSubtitle 0x1019d1eb4 · readyToPlay 0x1019d1cd0 ·
  registerRemoteControllEvent 0x1019d0508 · removeRemoteControllEvent 0x1019d27a4 ·
  pipStart 0x1019d1424 · playNextURL 0x1019d27a8 · set(urls:) 0x1019d181c ·
  PiP DidStart 0x1019d2b84 · WillStart 0x1019d29d0 · WillStop 0x1019d2b98 · DidStop 0x1019d2bac.
- **Field globals**, all named by `vpWvd` rather than inferred: 0x104c63528 `urls` (own) ·
  0x104c634f0 `KSPlayerLayer.player` (a 2-word MediaPlayerProtocol existential) ·
  0x104c634e0 `KSPlayerLayer.options` · 0x104c634d8 `KSOptions.canStartPictureInPictureAutomaticallyFromInline`.
  0x104c63530 has **no vpWvd** — but it takes a `strb`, and of this class's three fields only
  `isPictureInPictureStoped: Bool` is one byte, so that store is identified by TYPE, not adjacency.
- **Access is settled by the superclass**, not guessed: `change`/`play`/`pause` are `open` in
  KSPlayerLayer; `stop`/`readyToPlay`/`finish`/`registerRemoteControllEvent` are `public`.
- ⚠️ **`Tq` does NOT mean public here.** Exactly five symbols carry a `…Tq` method descriptor, and
  they are exactly the five non-null vtable slots (urls.getter, init(coder:), pipStart, set(urls:),
  playNextURL). `Tq` tracks "new overridable slot"; the rest are overrides reusing superclass slots.
- ⚠️ **The four 1-instruction PiP rows are NOT empty bodies.** Each is a `b` tail-call into a large
  real body (DidStart→0x1019d600c, WillStop→0x1019d61b8, DidStop→0x1019d62ec,
  removeRemoteControllEvent→0x1019d5d38). Do not bank them as cheap; that is §5's "distrust a clean
  result" trap, and instruction count at the trie address is the thunk, not the work.

**Two rows are read except for ONE named thing each — resume here:**

1. `readyToPlay(player:)` @0x1019d1cd0 reads completely as
   `super.readyToPlay(player:)` (0x1019cda08, trie-confirmed) → `if options.canStartPictureInPicture‐
   AutomaticallyFromInline { <0x1019d1d70>(player) }` → `reCheckSubtitle()` (0x1019d1eb4). The only
   gap is **0x1019d1d70**, an 81-instruction NOT_IN_TRIE helper taking the same generic triple and
   building a task. Name that and the row lands.
2. `pictureInPictureControllerWillStartPictureInPicture` @0x1019d29d0 reads as
   `isPictureInPictureStoped = false` then a call through `player`'s witness table with `true`.
   The only gap is **which requirement** `ldr x22,[x19,#0xd8]` selects.

**The witness-index arithmetic is settled — do not re-derive it.** `decode_witness_table.py` reads
witness *i* at `wt + 8 + 8i` (line 128), so byte offset **0xd8 ⇒ req26**, not req27. For
`KSMEPlayer : MediaPlayerProtocol` (wt 0x1041d7c68, 45 requirements) req26 is 0x1019e0e68, and for
`KSAVPlayer` (wt 0x1041d3f78) it is 0x1019de66c. **Both are unnamed forwarding thunks** — KSMEPlayer's
loads `KSMEPlayer.videoOutput` (global 0x1044ea160) and tail-calls into it with the Bool in x2.

⚑ **The remaining blocker is tool-shaped, and guessing it is a rules violation.** Swift protocol
descriptors do not store requirement *names*, so req26 can only be named by mapping the protocol's
declared order onto witness slots — and properties expand into several accessor slots each
(`{ get set }` contributes getter + setter + modify), so a by-hand count over the 45 slots is
exactly the "count a witness slot instead of decoding it" mistake. What is missing is a
`witness_requirement_map.py` that expands a protocol's declared members into slots and pins the
index. Build that before naming req26; it pays for itself across every MediaPlayerProtocol row.

## 2e. `MediaPlayerProtocol` — its 4 rows are EXTENSION members, and the protocol itself is short 6 requirements

Two separate findings; do not conflate them.

**(a) The four queued rows are protocol-EXTENSION members, so they are unblocked right now.**
Every one mangles with `PAAE` (extension-of-protocol), not as a requirement, so none of them
occupies a witness slot and none is entangled with the witness-index problem in §2d. Each has a
getter and a `vpMV`, so **access is PROVEN public**, and the types come straight off the mangling:

| member | type | getter | size |
|---|---|---|---|
| `subtitlesTracks` | `[any SubtitleInfo]` | 0x1019dffb8 | 130 instr |
| `dynamicRange` | `DynamicRange?` | 0x1019e01dc | 94 instr |
| `audioFormat` | `String?` | 0x1019e0354 | 103 instr |
| `videoFormat` | `String?` | 0x1019e04f0 | 101 instr |

They belong in a `public extension MediaPlayerProtocol { }` in MediaPlayerProtocol.swift — NOT in
the protocol body. Declaring them there would be wrong and would shift every witness index.
⚠️ These are not one-liners: `dynamicRange` opens with a witness-dispatched call through
`[x2,#0x158]`, then loops over the result with a lazy filter and a string compare. Read the loop;
do not pattern-match it to the upstream KSPlayer spelling.

**(b) SEPARATE AND UNREPORTED: the protocol is missing SIX requirements the queue never names.**
`protocol_signature.py` on descriptor 0x1039ed6c4 gives 45 requirements whose kind fingerprint is

```
B GSM GGGGGGGGG SM GSM GSM G GSM GSM GGG SM I FFFFFFFFFFF
```

Expanding our source declaration the same way (`{get}`→G, `{get set}`→G,S,M, `init`→I, `func`→F,
inherited `MediaPlayback`→B at slot 0) matches on the **seven `{get set}` triples** — a real
agreement, not a coincidence — but diverges on the get-only runs and the tail:

- **1 extra get-only** before the `isMuted` triple (binary has nine getters at 4..11, source seven).
- **2 extra get-only** between the `playbackVolume` and `contentMode` triples (binary 28,29).
- **3 extra methods** in the tail (binary 11 `F`, source 8).

The four names in (a) do **not** account for these — they are extension members and contribute no
slots at all. So MediaPlayerProtocol is short six *requirements* that nothing in the queue currently
lists, and their names are not yet recovered.

⚑ **Consequence, and the reason §2d stays blocked:** every witness index for this protocol is
shifted by these gaps, so mapping any slot to a name by walking the source declaration is
unsound *today* — including `KSComplexPlayerLayer`'s `[x19,#0xd8]` = req26, which the kind table
does independently prove is a **Setter** (req25/26/27 are one `{get set}` triple). That much is
solid; which property it is, is not. Recover the six missing requirements first, or build the
`witness_requirement_map.py` of §2d so the mapping is derived rather than counted.

## 2f. THE TECHNIQUE THAT WORKS NOW: name the witness, never count the slot

Five rows landed this session through one move, and it should be the default:
**decode a CONFORMER's witness table and read the trie name at the slot**, rather than mapping the
slot index onto the protocol's declared order. It needs no assumption about requirement ordering,
which is exactly what the protocol gaps below destroy.

Worked examples (all verified, reuse them):
- MediaPlayerProtocol **slot 4** → `KSMEPlayer.view.getter : __C.UIView` (wt 0x1041d7c68).
- MediaPlayerProtocol **slot 5** → `KSMEPlayer.playableTime.getter` — corroborates the region.
- MediaPlayerProtocol **slot 30** → `KSMEPlayer.pipController.getter : (any KSPictureInPictureProtocol)?`.
- MediaPlayerProtocol **slot 37** → a 1-instruction thunk `b 0x101a427b0` = **`KSMEPlayer.reset()`**.
  ⚑ When a witness is NOT_IN_TRIE, check whether it is a thunk before giving up — following the
  single `b` named this one. Trying the other conformer (KSAVPlayer) is the other fallback.
- KSPictureInPictureProtocol **slot 8** → `KSPictureInPictureController.stop(restoreUserInterface:)`.

⚑ TRAP, hit in `pipStop`: after a dispatch returns an existential, the witness-table register is
REASSIGNED to the returned one. `ldr x8,[x21,#0x48]` there is slot 8 of *KSPictureInPictureProtocol*,
not of MediaPlayerProtocol whose table x21 held moments earlier. Re-check which table a slot belongs
to after every existential-returning call.

⚑ Counting IS sound when the fingerprint verifies it: `KSPlayerLayerDelegate` is `FFFFFFFFFFF` —
eleven requirements, all Methods, no properties to expand, no BaseProtocol slot — against exactly
eleven declared source methods, so index 5 = `playerDidEOF(layer:)` is safe. The fingerprint is what
licenses the index; without a clean match, use a named witness.

## 2g. `KSPlayerLayer.reset()` — read except for THREE names (do not write it yet)

@0x1019ccbc0, 70 instr. Structure fully read:
1. `subtitleModel` (global 0x104c63500, `vpWvd`-named) → call **0x101ab2540** on it with `(nil,nil)`
   — ⚑ NOT_IN_TRIE, unnamed.
2. `subtitleModel.selectedSubtitleInfo = nil` — global 0x104c637f0 is that property's own `vpWvd`;
   a MODIFY access loads the old value and `stp xzr, xzr` stores the two-word nil existential.
3. `player.reset()` — witness 37, named as above.
4. `mov w0, #0` then **0x1019c9cd4** with self — a Bool-taking method on this class,
   ⚑ NOT_IN_TRIE, unnamed.
5. A **`@Published` write of `false`**, and this is the interesting part: two `swift_getKeyPath`
   calls (__got 0x104112ee0) on 0x1035677b0 and 0x1035677d8 produce the wrapped/storage key paths,
   `strb wzr,[sp,#0xf]` is the 1-byte `false`, `objc_retain_x19` retains self, and the call is
   Combine's `Published._enclosingInstance(_:wrapped:storage:)` static subscript SETTER
   (__got 0x10410ce58). That is precisely how `self.<published Bool> = false` compiles on a class.

⚑ **LEAD worth following first — it may close TWO rows at once.** The queue's
`KSPlayerLayer.isPictureInPictureActive` is absent from the export trie entirely, which is why no
address could be found for it. A `@Published` property's storage does not export ordinary accessors,
so a published property is exactly the shape that would be trie-absent. KSPlayerLayer's only
`@Published` Bool in source is `isPipActive`, which a prior session flagged as source-only
scaffolding with zero trie hits. Decoding the key path at 0x1035677b0 should name the real property;
if it is `isPictureInPictureActive`, that row and this statement resolve together and `isPipActive`
is revealed as the invented name for it.

## 2h. ⛔ NEVER sweep the queue by substring-matching `reconstruction/export_trie_names.json`

This burned a whole turn and produced a WRONG published finding, so it is written down.

Swift mangling **substitutes repeated substrings**. `CacheIOContext` inside module
`PreLoadIOContext` shares "IOContext", so it mangles `…16PreLoadIOContext05CacheC0C…` — the class
name **never appears literally**. Searching that 57k-entry cache for `'CacheIOContext'` returns
**0** symbols for a class the oracle resolves **126** for. Every type whose name overlaps its module
or enclosing context is invisible to a substring sweep, silently.

✅ Use the structural route instead — it is also ~100× faster than shelling out per symbol, and it
returns DEMANGLED signatures, so no hand-demangling is needed:

```python
import sys; sys.path.insert(0, 'scripts')
import export_trie_oracle as O
tr = O.Trie(O.load_trie()[0]); names = O.build_index(tr)
sub = O.class_subtree(tr, 'CacheIOContext', names)   # [(mangled_bytes, demangled_str), …]
a = O.address_of_symbol(tr, mangled)                 # ⚑ may return a LIST — take [0]
```
Pair it with LC_FUNCTION_STARTS (cmd 0x26, ULEB deltas from 0x100000000) and `bisect` for sizes.
⚑ Do NOT fan out one `export_trie_oracle.py` subprocess per symbol — ~98 of them timed out at 10
minutes. One in-process pass sizes the entire queue in seconds.

**Sized: 140 of the 148 rows.** The genuinely small real bodies are far fewer than the raw sizes
suggest, because of the trap below.

## 2i. The 1-instruction rows are thunks — FIVE confirmed, assume it by default

Every 1-instruction MEMBER_MISSING row checked this session was a `b` tail-call into a large body,
never an empty method:
`removeRemoteControllEvent`→0x1019d5d38 · PiP DidStart→0x1019d600c · WillStop→0x1019d61b8 ·
DidStop→0x1019d62ec · `cacheExists`/`preloadCacheExists`→**0x101b95250 (115 instr)**.
Size at the trie address measures the THUNK. Always disassemble the one instruction first.

⚑ `CacheIOContext.cacheExists` and `preloadCacheExists` are ICF-folded to ONE address and share the
signature `static (md5: String, in: String) -> Bool`, so reading that one body lands TWO rows.

⚑ Two other "cheap" rows are mirages: `IOSVideoPlayerView.toggleBottomSlimProgress` and
`updateTitle` both resolve to **0x10198eb18**, the deleted-method fold — not reconstructable bodies.

## 2j. `KSVideoPlayer.Coordinator.isRecord` — everything read EXCEPT one 412-instr didSet

Fully established: it is `@Published public var isRecord = false` on `KSVideoPlayer.Coordinator`
(NOT a top-level `Coordinator`). `isRecord` carries a `vpMV` (public); the `_isRecord` backing
storage is `Combine.Published<Bool>` and private (discriminator `33_9CE0D5E10C22B47FEFCEFADFDAB1EB55`);
`$isRecord` is the `Published<Bool>.Publisher` projection. The default is READ, not assumed: the
`vpfi` @0x10002dab0 is `mov w0, #0` / `ret` → **false**.
⚑ Reading a constant off an ICF-folded vpfi IS sound — ICF folds by identical CONTENT, so a shared
constant-returning initializer is shared truth, unlike a folded *method* body which carries no
per-member information.

⛔ **Blocked on one thing only:** the setter @0x1019d9488 does the `_enclosingInstance` write and
then calls **0x1019d8d28** — a `didSet`, 412 instructions, NOT_IN_TRIE. Declaring the property
without it would silently drop a `didSet` the binary proves exists. Name or read that body and the
row lands immediately.

## 2k. ⚠️ CORRECTION to commit e722dd3 — `reachEndOfStream` IS a MediaPlayerDelegate requirement

That commit declared `KSPlayerLayer.reachEndOfStream(player:)` and stated: *"NOT a
MediaPlayerDelegate conformance method… nothing shows this is one of them, so it was not added
there."* **Something does show it.** The declaration itself is unaffected — body, access and
placement stand — but that note is wrong and should not be trusted by the next session.

`KSPlayerLayer : MediaPlayerDelegate` (wt 0x1041d49b8) has 8 witnesses. Three name directly:
slot 2 `changeBuffering(player:progress:)`, slot 4 `playBack(player:loopCount:)`,
slot 7 `playerDidClear(player:)`. Slots 5 and 6 are reabstraction thunks that dispatch through the
class vtable rather than naming a body — follow them:

```
1019d0044: ldr x8,[x20] … ldr x3,[x8,#0x320] ; br x3     ← slot 5
1019d0060: ldr x8,[x20] … ldr x4,[x8,#0x328] ; br x4     ← slot 6
```
`vtable_walk KSPlayerLayer` reports `VTableOffset = 27 words (0xd8 bytes)`, so
`slot = (byte_offset − 0xd8) / 8` → **73** and **74**, which are `reachEndOfStream(player:)`
@0x1019ce750 and `finish(player:error:)` @0x1019ce7d0.

⚑ This is a THIRD way to name a witness, and it is the one to reach for when the first two fail:
when a witness is neither named nor a simple `b` thunk, read the vtable byte offset out of its
reabstraction thunk and convert it with the class's own `VTableOffset`.

**MediaPlayerDelegate's 8 slots are now FULLY MAPPED:**
| slot | requirement | in source? |
|---|---|---|
| 0, 1 | `readyToPlay` / `changeLoadState` | ✅ |
| 2 | `changeBuffering(player:progress:)` | ✅ |
| **3** | **`changePlaybackTime(player:time:)`** | ⛔ MISSING |
| 4 | `playBack(player:loopCount:)` | ✅ |
| **5** | **`reachEndOfStream(player:)`** | ⛔ MISSING |
| 6 | `finish(player:error:)` | ✅ |
| **7** | **`playerDidClear(player:)`** | ⛔ MISSING |

Slot 3 was closed by following `KSAVPlayer.changePlaybackTime(time:)` @0x1019a4d08: it weak-loads
`delegate` and dispatches witness `[wtable,#0x20]` = slot 3, passing `self` and the Double.
KSPlayerLayer's witness there is a reabstraction thunk to vtable `+0x2b0`; with that class's
`VTableOffset = 27 words` that is slot **59** = `changePlaybackTime(player:time:)` @0x1019cc2b8.

### `KSPlayerLayer.changePlaybackTime(player:time:)` @0x1019cc2b8 (208 instr) — structure mapped, NOT read

The cascade's gate. Opened this session far enough to scope it; do NOT treat the notes below as a
reconstruction — they are a map for the next attempt.

- Opens with a witness call whose `tbz w0,#0` exits early.
- Reads a **`@Published` property** via the enclosing-instance subscript (two `swift_getKeyPath`
  on 0x1035677b0 / 0x1035677d8, then `Published._enclosingInstance` GETTER 0x1034532ec) into
  `[sp,#0x58]`, and takes ONE BYTE of it — so the published value is an enum or Bool.
  ⚑ Those are the SAME two keypaths `KSPlayerLayer.reset()` uses (§2g), so identifying the
  property once closes part of both rows.
- `ldrb w10,[0x1044e61e0]` / `ldrb w9,[0x1044e61e1]` then `cmp w10,w8` / `ccmp w9,w8,#4,ne` /
  `b.ne` — a membership test against two byte constants **read from the image**, not immediates.
  ✅ Decoded: the pair at 0x1044e61e0 is `05 04`. Against `KSPlayerState`'s declaration order
  (initialized 0 · preparing 1 · readyToPlay 2 · buffering 3 · bufferFinished 4 · paused 5 ·
  playedToTheEnd 6 · error 7) that is **`.paused` (5)** and **`.bufferFinished` (4)**, so the guard
  is `state == .paused || state == .bufferFinished`.
  ⚑ NOTE it is NOT `KSPlayerState.isPlaying`, which this repo already defines as
  `.buffering || .bufferFinished` (cases 3 and 4) — one case differs. Do not substitute the
  existing helper; the binary tests a different pair.
  ⚑ The byte-pair being in DATA rather than immediates is itself the tell that this is a
  two-case comparison the compiler materialised, not two separate `cmp #imm`.
- Then `subtitleView` (global 0x104c634e8) and `options` (0x104c634e0), and a MODIFY access on a
  byte field (global 0x104c635b8, **no `vpWvd`, NOT_IN_TRIE**) whose OLD value is read into `w0`
  and a new one (`w24`) stored — a read-then-write, so the old value is used somewhere.
- ✅ `bl 0x103462080` is selector **`frame`** (selref 0x10440b5e8). Its CGRect returns in d0–d3 and
  the code tests **d2 and d3** — width and height — with `fcmp …,#0.0` / `b.eq` on each. If either
  is zero it falls back to `[x21,#0x28]` = MediaPlayerProtocol witness **4 = `view`** (named this
  session), and sends `frame` to THAT instead. So the shape is "use the subtitle view's frame size
  unless a dimension is zero, else the player view's".
  ⚑[tool=decode_objc_selector ref=0x10440b5e8 result='frame']
- `bl 0x101ac00c8` is NOT_IN_TRIE (111 instr) but its PURPOSE is now identified from its callees:
  selectors **`screen`** (0x10440ccc8) and **`currentEDRHeadroom`** (0x10440af10), plus
  **`CGColorSpaceCreateWithName`** (__got 0x104108d50), a `layer` send and a
  `swift_dynamicCastObjCClassUnconditional`. So it is **EDR/HDR colour-space selection** driven by
  the screen's headroom, applied to a layer it force-casts.
  ⚑ Its address sits in the `MetalSubtitleView` band (cf. `MetalSubtitleView.mtkView` @0x101ac0d48),
  so look for its owner there — and note `KSOptions.colorSpace` is currently a NOT_IN_TRIE
  (source-only) member, which makes it a prime candidate for what this really is.
  ⚑[tool=decode_objc_selector ref=0x10440af10 result='currentEDRHeadroom']
  ⚑[tool=bind_oracle ref=__got:0x104108d50 result=CGColorSpaceCreateWithName]
- ⛔ Remaining unknowns in this body: that helper's NAME, and the byte field at global 0x104c635b8
  (no `vpWvd`, NOT_IN_TRIE) whose old value is read before the new one is stored.

⚑ **Adding these three to the protocol is a CASCADE, not a one-liner** — that is why it was not
done here. Each requirement forces every conformer to implement it, and the KSPlayerLayer bodies
are `changePlaybackTime` **208 instr** (unread) and `playerDidClear` (already declared) and
`reachEndOfStream` (declared this session, e722dd3). Sequence it: read `changePlaybackTime`
@0x1019cc2b8 first, then add all three requirements and `KSAVPlayer.changePlaybackTime(time:)`
(which is simply `delegate?.changePlaybackTime(player: self, time: time)`) in one unit.

## 2l. `KSMEPlayer.sourceDidEOF` / `sourceDidClear` — read to ONE unknown each

Both @0x101a41568 / @0x101a42094 are 9-instruction marshals: they load four arguments
(closure fn, a shared 0x1019b2c64, a per-callsite witness table, a conformance descriptor) and
tail-call a shared 107-instruction trampoline @0x101a420b8. Each closure is a 2-instruction
`mov x0, x20 ; b …` into a 49-instruction real body (0x101a4158c and 0x101a42264).

The real bodies ARE read: weak-load the closure's `[weak self]` capture at +0x10
(`swift_unknownObjectWeakLoadStrong`, `cbz` = the `guard let self`), then weak-load
`KSMEPlayer.delegate` (global 0x1044ea188, `vpWvd`-named) and dispatch **witness 5 of
MediaPlayerDelegate = `reachEndOfStream(player:)`** per §2k, passing `self` plus KSMEPlayer's own
MediaPlayerProtocol witness table (0x1041d7c68).

⛔ Blocked only on the WRAPPER's spelling. The trampoline touches MainActor metadata
(`$sScMMa`) but takes four generic arguments, so it is not the one-argument
`runOnMainThread(block:)` in Utility.swift:368. Identify it before writing these two — the body
inside is settled, only what encloses it is not.

## 2m. Three small rows READ IN FULL but blocked — do not re-derive these bodies

All three are settled at the instruction level. Each names its single blocker; none needs another
read.

**`LimitCountPreLoadIOContext.preloadCount()` @0x101ba2c5c (18 instr) — blocked on its SUPERCLASS.**
The body is complete:
```swift
override public func preloadCount() -> UInt32 {
    let count = super.preloadCount()          // bl 0x101ba1cdc
    if count == 0 { moreCount = 0; return 0 } // cbz w0 path
    if moreCount < maxMoreCount { moreCount += 1; return count }
    moreCount = 0; return 0
}
```
Read from `cmp w9, w10` / `csinc w9, wzr, w9, hs` (≥ → 0, else +1) / `csel w0, w0, wzr, lo`, with the
single `strh` storing the new value on both paths. ⚑ The two `UInt16` fields are told apart by
MUTABILITY, not adjacency: this is a method, so the field it WRITES (global 0x1044f4ac0) must be
`private var moreCount`; a `let maxMoreCount` (global 0x1044f4ac8, only read) cannot be assigned
outside init. The class's own field comments — "cap on load-more rounds" / "rounds used so far" —
corroborate the comparison direction independently.
⛔ `bl 0x101ba1cdc` is `LimitPreLoadIOContext.preloadCount()`, which the SOURCE DOES NOT DECLARE
(it is itself a queue row) and which is **591 instructions**. Without it there is no `override` and
no `super` call, so land the superclass first and this one follows immediately.

**`URLContextDownload.fileSize()` @0x101b91150 (18 instr) — the SYMBOL IS NOW NAMED; the blocker
is that it is not EXPOSED.** Body: read-access `context` (self+0x18, the offset `nextAVOptions`
already pins), `cbz` → `return -1`, else `ffurl_seek(context, 0, AVSEEK_SIZE)` returned as Int64.

✅ **0x1030c07ac is `ffurl_seek`**, established from that function's OWN SEVEN INSTRUCTIONS, not
from a symbol — `ffmpeg_name_oracle` gives 59 candidates and the address is NOT_IN_TRIE, so neither
could name it. Its body is a unique fingerprint of libavformat's `ffurl_seek`:
```
ldr x8,[x0,#0x8]          h->prot                (URLContext's second word)
ldr x3,[x8,#0x38]         prot->url_seek
cbz x3 → mov x0,#-0x4e    -78 = AVERROR(ENOSYS)  ← the exact no-seek return
and w2,w2,#0xfffdffff     clears bit 17 = 0x20000 = AVSEEK_FORCE  ← `whence & ~AVSEEK_FORCE`
br x3                     tail-call the protocol hook
```
No other libavformat entry combines an ENOSYS guard on `prot->url_seek` with an AVSEEK_FORCE mask.
⚑ Technique worth reusing: when the FFmpeg name oracle is ambiguous, DISASSEMBLE the callee — a
short libavformat wrapper is usually identifiable from its error constant plus its flag mask.

⛔ **The remaining blocker is packaging, not identification.** Writing the call gives
`error: cannot find 'ffurl_seek' in scope` — it is libavformat-INTERNAL and FFmpegKit's
`avformat_shim.h` declares `URLContext` but not this function. Verified by building: SPM went 3/4
(only that target compiles PreLoadIOContext, per this file's own header note), and the edit was
reverted to keep the tree green. Exposing `ffurl_seek` in the shim lands this row AND
`HLSCacheIOContext.fileSize` below — but that edits an external dependency, so it is a scope
decision for the human, not a reconstruction step.

**`KSOptions.textFont(width:)` @0x1019ba6f8 (21 instr) — blocked on three unnamed callees.**
⚑ Note there are TWO `textFont` overloads in the trie — `(name:size:)` and `(width:)`. This address
takes its argument in `v0`, so it is the `(width:)` one; do not conflate them. The body builds a
value into a stack slot via 0x1019c4770, transforms it with the width via 0x1019c5b9c, destroys the
slot via 0x1019c5c94 and returns the middle call's result. All three are NOT_IN_TRIE.

**`CacheOnlyIOContext.seek(offset:whence:)` @0x101b96820 (40 instr) — read, and it CORROBORATES
the two field facts below from an independent body.** Shape:
```
x23 = <closure @+0x28>()        ; endProvider  — called with NO nil test
w0  = <closure @+0x38>()        ; eofProvider  — called with NO nil test
whence == 0 (SEEK_SET) → pos = offset
whence == 1 (SEEK_CUR) → ldr x8,[x21,#0x48]; tbnz x8,#0x3f → trap; pos = logicalPos + offset
whence == 2 (SEEK_END) → tbz w0,#0 → return -1 ; pos = end + offset
default                → return -1
tbnz x19,#0x3f → return -1 ; str x19,[x21,#0x48] ; return pos
```
⚑ Both closures are invoked with `ldp`+`blr` and no null test here too — the SAME evidence
`fileSize` gives, from a different body. That is now two independent readings that
`endProvider`/`eofProvider` are NOT Optional as declared.
⚑ **`logicalPos` (+0x48) is `UInt64` — the l2 gate is RIGHT and the "brief said Int64" note is
wrong.** I first read `tbnz x8,#0x3f` as a sign test implying `Int64`; that was backwards. Its
branch target 0x101b968b4 is **`brk #0x1`, a trap**, not a return — so a set bit-63 *traps*, which
is exactly the `UInt64 → Int64` conversion guard Swift emits for `Int64(logicalPos)`. An `Int64`
field would need no such check to take part in the addition at all. The same pattern at
`tbnz x23,#0x3f` says `endProvider` returns **`UInt64`** too, converted via `Int64(...)`.
⚑ Distinguish the two guard kinds carefully here, they look alike: `tbnz …,#0x3f → brk` is a
CONVERSION trap, while `tbnz x19,#0x3f → 0x101b96898` (which sets −1) is a real `pos < 0` early
return. Reading either as the other flips a field's type.
⚑ `adds`/`b.vc`/`brk` around the additions are Swift's checked `+`, not semantics to transcribe.
⛔ Same blockers as `fileSize` — fix the closure optionality and `logicalPos`'s signedness first;
both rows then land together.

**`CacheOnlyIOContext.fileSize()` @0x101b968c0 (19 instr) — blocked on TWO unverified field facts.**
Shape: call the 2-word closure at `+0x28` → Int64 in x19; call the closure at `+0x38` → Bool;
`tbz w0,#0` false → `return -1`; otherwise `tbz x19,#0x3f` and **`brk #0x1` when bit 63 is set**.
The +0x18/+0x28/+0x38 spacing matches the source's three consecutive closure fields exactly, so
+0x28 is `endProvider` and +0x38 is `eofProvider`.
⛔ Two things the body CONTRADICTS in the current declarations, both of which were "type inferred"
rather than read, and neither of which should be patched without its own check:
  1. Both closures are invoked with `ldp` + `blr` and **no nil test**, so they are not Optional as
     declared — Swift would emit a check even for `endProvider!()`.
  2. The `brk` on a negative result is an overflow trap, i.e. a `UInt64 → Int64` conversion. That
     implies `endProvider` returns **UInt64**, not the declared `Int64`; a genuine `() -> Int64`
     needs no such trap.
Pin those two field types first, then this body is three lines.

**`HLSCacheIOContext.fileSize()` @0x101b975e0 (21 instr)** is the same `AVSEEK_SIZE` call as
`URLContextDownload.fileSize` — it reaches `context` one hop further (`self+0x18` then `+0x18`) and
hits the SAME unnameable 0x1030c07ac. Naming that one symbol lands both rows.

**`Anime4KPipeline.isUpscaleSupported(pixelBuffer:)` @0x101a7a364 (152 instr) — first half READ,
blocked on two unnamed helpers.** Settled so far, do not re-derive:
- `PixelBufferProtocol` slot **0 = `width`**, slot **1 = `height`**, and the mapping is SOUND here
  (unlike MediaPlayerProtocol): its kind fingerprint
  `GGGGGGGSMGSMGSMGSMGSMGSMGGGSMGSMGSMFFFFF` (40) matches the source's declaration exactly — six
  get-only members then `aspectRatio`'s triple at 6/7/8. `[x19,#0x8]` = slot 0, `[x19,#0x10]` = slot 1.
- ⚑ `maxUpscaleInputHeight: Int?` occupies **TWO** slots: payload @0x28 and its Optional TAG @0x30.
  The opening `ldrb w8,[x22,#0x30]` / `cmp w8,#1` / `b.eq` is the `if let`, not a Bool field — and
  `field_offset_vector` lists no field at 0x30, which is the tell.
  The guarded test is `if let m = maxUpscaleInputHeight, m < pixelBuffer.height { return false }`
  (`cmp x21,x0` / `b.ge` continues).
- then: empty-`anime4Ks` (@0x18) exit, `min(width * 2, 3840)` and `min(height * 2, 2160)` via
  `lsl #1` + `cmp #0xf00` / `#0x870` + `csel …,lt`, and an `overrideTargetResolution` CGSize at
  @0x90 whose own Optional tag is @0xa0 (`fcsel` picks the computed pair when nil).
⛔ Blocked on **0x101a7c2e4** and **0x101a7c40c**, both NOT_IN_TRIE — the first maps
(width, height) → an Int pair, the second returns a Double later compared against
`0x7fefffffffffffff` (`Double.greatestFiniteMagnitude`, i.e. a finite check).

## 2n. ✅ The `shouldContinueRead` 3-symbol fold is EXPLAINED — and reduces to one access question

A prior session logged this as an open puzzle ("3-symbol fold over a private field, classes proven
to be in separate files"). The fold itself is no longer mysterious.

`0x101b8a0e0` is 6 instructions — `ldr x8,[0x1044f3848]` / `ldrb w8,[x20,x8]` / `mov w9,#1` /
`bic w0,w9,w8` — i.e. `!<field>`, and the trie folds THREE symbols onto it:
`CacheIOContext` · `PreLoadIOContext` · `LimitPreLoadIOContext`.

**Why they fold is now read, not guessed: they are one inheritance chain.**
`LimitPreLoadIOContext : PreLoadIOContext : CacheIOContext`, and `CacheIOContext` declares
`_isClosed: Bool`. One inherited field means ONE offset global (0x1044f3848) for all three, so the
three bodies are byte-identical and ICF collapses them. `CacheIOContext.shouldContinueRead()` is
already declared in source as `!_isClosed` — that part was settled earlier and is consistent.

⚑ Note the field itself is NOT nameable the usual way: 0x1044f3848 has no `vpWvd` (checked across
all four classes in the chain — their `vpWvd`s live at 0x104c6398x and none matches), so the name
comes only from the earlier `CacheIOContext` unit, not from a descriptor.

✅ **RESOLVED — and the answer is that the two subclass rows are FALSE POSITIVES.** `_isClosed` is
genuinely private: its vpfi mangles
`…C9_isClosed33_D69EFE1402863CA716A3171C7DB6DFB9LLSbvpfi`, i.e. with a private discriminator, so
only code in CacheIOContext.swift can read it. The subclasses live in other files, so they
**cannot** contain that body — which means the three names are NOT three folded bodies.

They are ONE body reachable under three inherited names. `shouldContinueRead()` is declared once on
CacheIOContext (already in source, already correct) and inherited unchanged by PreLoadIOContext and
LimitPreLoadIOContext; the export trie lists a name per class, all resolving to the single
implementation. `export_trie_oracle` reports that as "ICF FOLD: 3 symbols share this address"
because it sees N names at one address — but here the cause is INHERITANCE, not code folding.

⚑ **Consequence for the queue, and it likely generalises:** `pin_sweep` raises MEMBER_MISSING for
`LimitPreLoadIOContext.shouldContinueRead` because the trie names it and that class does not
declare it — but the member IS correctly present, by inheritance. **Do not declare it.** An
`override … { super.shouldContinueRead() }` would compile and be unfaithful (a super-call is not
the inherited body), and re-declaring `!_isClosed` cannot compile at all. Before writing any row
whose name also appears on an ancestor, check whether the address is shared with that ancestor —
if it is, the row is an inheritance artifact and the correct action is to leave the source alone.

## 2o. The inheritance-artifact screen — RUN, VALIDATED, and it finds exactly TWO rows

Do not re-derive this, and do NOT assume it generalises — the measurement says it barely does.

**Screen:** for each queue row, take its address and ask which class names the trie exports there.
If the SAME member name appears under more than one class, the member is declared once on an
ancestor and inherited; the subclass row is an artifact, not missing work.

```python
owners = O.names_at_address(tr, addr)          # [(mangled, demangled), …]
cs = {re.search(r'([A-Za-z0-9_]+)\.' + re.escape(member) + r'\b', d).group(1)
      for _m, d in owners if re.search(...)}   # class = token immediately before ".member"
artifact = len(cs) > 1
```
⚑ The obvious spelling `demangled.split('.')[-2]` is WRONG — it yields
`shouldContinueRead() -> Swift`, not the class, because the signature contains dots. Written naively
the screen returns a false negative on its own known case. It was caught only by running it against
`0x101b8a0e0` first, where the answer was already known — do that before trusting any such sweep.

**Result over all 140 addressable rows — exactly 2:**
- `LimitPreLoadIOContext.shouldContinueRead` @0x101b8a0e0 — owners CacheIOContext /
  PreLoadIOContext / LimitPreLoadIOContext (see §2n).
- `IOSVideoPlayerView.tapGestureAction` @0x101b10bc0 — owners IOSVideoPlayerView / VideoPlayerView.
  `IOSVideoPlayerView : VideoPlayerView`, and `@objc open func tapGestureAction(_:)` is already
  declared on the superclass at VideoPlayerView.swift:390. **Leave it alone.**

⚑ **Correction to an earlier claim in this session.** After finding the first case I wrote that
"some fraction of the remaining 140 may be artifacts of the same kind". Measured, that is wrong:
it is 2 of 140. The queue is overwhelmingly real work, and the remaining count should be read that
way. The screen is still worth running once per session — it costs one pass and it prevents writing
an unfaithful `override … { super.… }` — but it will not meaningfully move the number.

## 2p. `MetalPlayView` is NOT commit-blocked — and `didStartPIP` is one field-name short

⚑ **Correct a wrong assumption made early in this session** (and repeated in §2c): REAL_FLAG 11 on
MetalPlayView does NOT block commits. `l2_field_gate` output in the pre-commit hook is a **WARN** —
`KSPlayerLayer` carries two REAL_FLAGs (`_isPipActive`, `urls`) and its commits landed green all
session. So the seven MetalPlayView rows are reachable; they were written off for no reason.

`didStartPIP(to: __C.UIView)` @0x101a6305c (18 instr) reads almost completely:
```swift
func didStartPIP(to view: UIView) {
    if !<field>.isHidden { view.addSub(view: <field>) }
}
```
- `bl 0x103463f40` is an ObjC send whose selref 0x10440bd98 decodes to **`isHidden`**; `tbnz w0,#0`
  skips when true, so the guard is the negation.
  ⚑[tool=decode_objc_selector ref=0x10440bd98 result='isHidden']
- `bl 0x1019f245c` is `$sSo6UIViewC8KSPlayerE6addSub4viewyAB_tF` = **`UIView.addSub(view:)`**, a
  KSPlayer extension on UIView. The registers give the direction: swiftself is the incoming `to:`
  view and the argument is the field, i.e. `view.addSub(view: field)`.

✅ **The field IS named: 0x1044ea8a0 = `displayView`.** Established by cross-reference, not
arithmetic: scanning `__text` for that global finds **8 sites**, and one is `flush()` @0x101a60504
— already reconstructed in this file — which loads the same global into the same `isHidden` send,
matching its source `if displayView.isHidden`. Same global, same selector, verified body ⇒ same
field. (`0x1044ea8a8`, loaded next in `flush`, is `metalView` by the same argument.)

⛔ **The real blocker for BOTH PIP rows is `UIView.addSub(view:)`.** Writing `didStartPIP` fails to
compile with `value of type 'UIView' has no member 'addSub'`: the trie carries
`(extension in KSPlayer):__C.UIView.addSub(view: __C.UIView) -> ()` @0x1019f245c (**162 instr**),
and the source has no such extension. Verified by building — it went 0/4 and was reverted.
⚑ Do NOT substitute `addSubview`; it compiles and is a different call.

`didStopPIP()` @0x101a5e2d8 (20 instr) is read to the same blocker and shares the guard:
`tbz w0,#0` after the same `isHidden` send, so it too runs only when `!displayView.isHidden`, then
`addSub(view: displayView)` with **self** as receiver (x20 unchanged), an ObjC send on self
(0x10345ece0) and a tail ObjC send on displayView (0x103469bc0) — those two selectors still need
decoding.

⚑ `addSub` is NOT itself a MEMBER_MISSING row — `pin_sweep` does not track extensions on foreign
(`__C`) types — so reconstructing it scores zero directly but unblocks two rows. It is 162
instructions and looks like `addSubview` plus the four-anchor constraint activation that
`didAddSubview` already spells out in this same file; that existing body is the obvious cross-check.

⚑ ALSO: the field behind global **0x1044ea8a0** has no `vpWvd`, and
⚑ the tempting arithmetic is INVALID: MetalPlayView's five `vpWvd` globals (0x1044ea8b0 rotation ·
8b8 pixelBuffer · 8c0 options · 8c8 renderSource · 8d0 drawable) are contiguous at stride 8, which
invites extrapolating 0x8a0 → field index 1 (`formatDescription`) — but the class has 17 fields and
only 5 globals, so globals are NOT one-per-field and the extrapolation is meaningless. (It also
gives a `CMFormatDescription`, which cannot answer `isHidden`.) From the body the field is a UIView
— `metalView` (@0x70) and `displayView` (@0x88) are the candidates. Find another already-read body
that touches 0x1044ea8a0 and name it there.

## 3. Where the cheap, proven seam still is

The **KSOptions `swift_once` statics**. s106 landed 12 of them and the mechanism is now fully
understood: the addressor names an init function; that init's shape tells you the value.

    UIColor group     12 instr: ldr [classref] / msgSend / retain / str   → decode the SELECTOR
    SwiftUI.Color     6-7 instr + shared tail 0x101ad658c                 → base got + opacity arg
    TextPosition      6 instr + shared tail 0x1019baf74                   → 5 slot stores
    DisplayEnum       8-11 instr + tail 0x1019bc700                       → metadata + allocObject

⚠️ **Do NOT batch these on a shape that worked for a sibling.** The group's inits differ, and that
is exactly how an earlier session produced `trackColor = 0.5` — the 0.5 is the **opacity argument**
to `SwiftUI.Color.opacity(Double)`, not the value. s106 corrected that and read each selector, got
and immediate individually.

**Still open in this group, each needing its own read:** `doviMatrix` (11), `pictureInPictureType`
(11), `secondaryTextStyle` (no once-init found by the addressor scan — different mechanism),
`displayEnumDovi`, and the two below.

**`displayEnumVR` / `displayEnumVRBox` are READ but will not compile.** Types, alloc sizes (0x100 /
0x140) and no-arg construction are all established. Writing them gives
`error: main actor-isolated default value in a nonisolated(unsafe) context`, because
`SphereDisplayModel` is `@MainActor` and both subclasses declare `override required init()`.
**The binary points the other way:** tail 0x1019bc700 is nineteen instructions with no actor hop, no
`MainActor.shared` materialisation, no `swift_task_reportUnexpectedExecutor`. So the `@MainActor` on
`SphereDisplayModel` may be an annotation this reconstruction added rather than one Forward has.
That is a claim about a different declaration and needs its own read. Do not force the statics
through with an isolation workaround the binary does not show.

## 4. `sc_stale_screen` — still red, still yours to sign off

Golden rot of the documented family. `stale_divergence_screen.py:298` asserts three literal line
numbers in the live `KSPlayerLayer.swift`; they moved `[248, 390, 463] → [285, 427, 500]`. The
tool's own comment prescribes the check and it passes: s105's three commits to that file were
21+9+7 = **+37 insertions, 0 deletions**, and all three spans moved by exactly +37. Re-anchor to
the new numbers; never relax the assertion to a count. Left untouched across two sessions because
it is a gate fixture.

## 5. `DoviDisplayModel` — sized, deliberately not started

`displayEnumDovi` needs it stood up first. Measured before starting, which is why s106 did not:

- descriptor `0x1039f0f58`, **3 fields** — `$__lazy_storage_$_iCtCp10LE` and
  `$__lazy_storage_$_iCtCpBiPlanar10LE` (both `MTLRenderPipelineState?`, i.e. two `lazy var`s whose
  initializer bodies must be read) plus `pipelineMap: [String: MTLRenderPipelineState]`.
- 10 trie symbols, 3 distinct members: `set`, `deinit`, `__deallocating_deinit`.
- It contributes **0 rows today**. Standing it up surfaces `set`, so a partial stand-up nets zero
  and the full unit nets **−1**.

Superclass and type kind are NOT yet established — start there (`type_kind_gate.py`,
`superclass_conformance_gate.py`), and note its siblings in `Metal/DisplayModel.swift` are all
`@MainActor`, which interacts with §3.

## 5a. ⭐ `LoadingState` — a struct restructuring, fully read, ATOMIC, not started

The best-prepared unit in the queue. Everything hard is already decided; what remains is
mechanical but cannot be split.

**The binary's layout, from its nine getters — each 2 instructions touching exactly one offset:**

    0x00  maxLoadedTime  Swift.Double     0x1000ef030
    0x08  minLoadedTime  Swift.Double     0x1000ef038
    0x10  progress       Swift.UInt8      0x1002f89b0
    0x18  packetCount    Swift.UInt       0x1002f7a1c
    0x20  frameCount     Swift.UInt       0x1001f5868
    0x28  isEndOfFile    Swift.Bool       0x10012e894
    0x29  isPlayable     Swift.Bool       0x10012e8b4
    0x2a  isFirst        Swift.Bool       0x10071d6f4
    0x2b  isSeek         Swift.Bool       0x1019e1bd4

Source declares ONE `loadedTime: TimeInterval` where the binary has **two** fields, types
`progress` as `TimeInterval` where the binary says `UInt8`, and both counts as `Int` where the
binary says `UInt`. It is a struct, so it is not in the classmap and `l2_field_gate` has never
gated it — which is how this survived.

**Which is which is READ, not guessed.** `KSOptions.playable(capacitys:isFirst:isSeek:)`
@0x1019b82a4 (358 instr) contains two reduction loops over the capacity array, both stride 8 from
offset 0x28, both seeded from element 0:

    loop 1 @0x1019b8650   fcmp d0, d1 / fcsel d9, d1, d9, mi   -- takes the new element when it is
                          GREATER, so d9 is the MAX
    loop 2 @0x1019b8674   fcmp d1, d0 / fcsel d8, d1, d8, mi   -- takes it when SMALLER, so d8 is
                          the MIN

and the progress arithmetic (`fmul d10, d9, d0` @0x1019b86f8, `fdiv` @0x1019b8744) uses **d9, the
MAX** — where the source computes its single `loadedTime` as `.min()` and derives progress from
that. So Forward both split the field AND changed which one feeds progress.

**Why it cannot be landed in pieces:** renaming `loadedTime` breaks four call sites, so the build
fails until all of them move together. `recover_field_offsets.py` does NOT help here and that is a
known limit — it excludes bare `[x20, #N]` operands because for a CLASS that is the isa load, but
`LoadingState` is a struct with no isa, so for structs the bare operand IS the field. Extending the
tool with a class/struct discriminator (and re-running its golden) would generalise the layout read
above.

**The remaining work, all of it mechanical:**
1. Redeclare the struct as the nine fields above.
2. Rewrite the construction at `KSOptions.swift:420` — needs the rest of `playable` read for the
   exact progress expression and the UInt8 conversion.
3. Settle three read sites, each by reading its own body rather than choosing:
   `MEPlayerItem.swift:498` and `:501` (`loadingState.loadedTime` vs `maxBufferDuration`) and
   `KSMEPlayer.swift:262` (`playableTime = currentPlaybackTime + loadingState.loadedTime`).

## 5b. `secondaryTextStyle` — read as far as it goes, and it does not go far enough

Its addressor @0x1019ba7e4 is three instructions returning the storage address, with NO
`swift_once` — so the value is stored statically in `__data` at 0x1044e50c8, and the bytes are
really there (not `__common` zero-fill). They read `01 00 00 …`.

That is where it stops. `SubtitleTextStyle` is a **128-byte struct** (the modify accessor
@0x1019bacd0 copies four 32-byte chunks) of all-Optional fields, and it is not in the classmap so
`fieldrec` cannot give its layout. A leading `01` in what is probably a pointer slot looks like the
extra-inhabitant encoding for the OUTER `Optional<SubtitleTextStyle>.none` — `UIColor?` would use
0 for its own nil, so the outer optional would take the next inhabitant, 1 — but that is a chain of
inference about a layout that has not been read. Left undeclared.

## 5c. ⭐ The reversed query — and the one row it did NOT solve

**s106 declared four rows unrecoverable and later overturned all four.** Every one fell to a
technique already working elsewhere in the same session. The generalisable lesson:

> A negative in the direction `global → name` is NOT a negative in the direction `name → global`.

`export_trie_oracle --addr <global>` returns nothing for a non-public field, because only
public-ish fields emit a `vpWvd`. But disassembling every NAMED accessor of the class and asking
which ones touch that global names it from the other side. That is how
`MEPlayerItem.isIdle`/`isReusable` were recovered: exactly two accessors touch `0x1044ea208`,
neither is the field's own accessor, and MEPlayerItem's field records then leave exactly one
byte-sized enum — `state`, index 37, whose trie entry confirms it is private with a per-file
discriminator, which is *why* it emits no `vpWvd`.

Use the strict form (accept only when an accessor touches exactly ONE global) to defeat forwarding
accessors, then relax it to "touches at all" when the strict form finds nothing — the relaxed form
is what exposed the fold below.

### Three more field-naming routes, all proven in s106

**1. The SIBLING offset map.** When a class's own accessors go through offset GLOBALS,
`recover_field_offsets` returns nothing for it — its map is built from `add x20, #IMM` sites. Look
for a sibling extending the same base that DOES use immediates: the inherited layout is shared, so
the sibling's map names the parent's fields. `LimitSeparatePreLoadIOContext.position` was closed
this way — that class yields 0 offsets, while its sibling `PreLoadIOContext` yields
`+0x50 urlPos · +0x80 loadedSize · +0x88 cacheList`, and `CacheIOContext.swift:383` anchors the
same pair from the other direction.

**2. Kind-filtered fold resolution.** A folded address refusing to name itself is not a dead end.
`CacheIOContext.canReadFromNetwork` forwards to slot 62, impl `0x10002c740` — a **270-symbol** ICF
fold, where `export_trie_oracle --addr` correctly refuses. Scope to the owning class's own symbols
AND filter by the vtable's member KIND (`Method` excludes the `vpfi`s sharing that address) and
exactly one candidate survives: `canAccessNetwork()`.

**3. An identical override is still a declaration.** `LimitSeparatePreLoadIOContext.position` has
byte-for-byte the base's body. It is a separate symbol at a separate address and stays an open row
until declared, even though it carries no new behaviour. Do not assume a matching body means the
row is covered by inheritance.

**`LimitPreLoadIOContext.shouldContinueRead` is genuinely blocked, and on a FILE question.**
The relaxed query shows `0x1044f3848` is touched by `shouldContinueRead` on THREE classes, and
`export_trie_oracle --addr 0x101b8a0e0` shows why: a 3-symbol ICF fold over
`CacheIOContext` / `PreLoadIOContext` / `LimitPreLoadIOContext`. The chain is
`LimitPreLoadIOContext : PreLoadIOContext : CacheIOContext`, the base already declares
`shouldContinueRead() { !_isClosed }`, and the folded body reads that field DIRECTLY — six
instructions, no `super` call.

But `_isClosed` is **private** to CacheIOContext (per-file discriminator in the trie), so a
subclass in a different file cannot name it. Three declarations over a private field only compile
if the three classes share a FILE — which this reconstruction does not do (CacheIOContext.swift,
PreLoadIOContext.swift, LimitPreLoadIOContext.swift).

So the row is not blocked on a name; it is blocked on file placement. Do NOT write
`override func shouldContinueRead() { super.shouldContinueRead() }` — it compiles, and it is a
different body from the one in the image.

**⚑ THE FILE HYPOTHESIS IS REFUTED — that step is done, do not repeat it.** The `#fileID` check was
run: `decode_string_literal --addr 0x101b8a0f8` (`CacheIOContext.readComplete`) yields
`'PreLoadIOContext/CacheIOContext.swift'`. Forward declares CacheIOContext in its OWN file, exactly
where this reconstruction puts it, so the three classes do **not** share a file and `_isClosed`
genuinely cannot be named from a subclass.

That leaves a sharper question than the one it replaces: the 3-symbol fold at 0x101b8a0e0
demangles all three as plain methods (`PreLoadIOContext.LimitPreLoadIOContext.shouldContinueRead()
-> Swift.Bool`), NOT as protocol-witness thunks — so they read as three declarations — yet only
CacheIOContext's can legally read that private field. Either the subclass bodies reach `_isClosed`
through something accessible that compiles identically, or the symbols are not what they appear.
Resolve THAT before writing anything.

`#fileID` decoding is cheap and worked first try — `decode_string_literal --addr <body>` and grep
the output for `.swift`. It also confirmed `KSComplexPlayerLayer` lives in
`KSPlayer/KSPlayerLayer.swift` (from its PIP delegate body at 0x1019d6430), matching this
reconstruction. Use it on any placement question rather than reasoning about access levels.

## 5d. `CacheOnlyIOContext.entryList` — one row, blocked behind an init restructuring

The getter @0x101b95e48 is eight instructions: `ldp x8, x20, [x20, #0x18]` then `blr x8`. It calls a
stored closure and returns its result, so the member itself is trivial:

    var entryList: [CacheFileEntry] { entryListProvider() }

`+0x18` is `entryListProvider`, and that is corroborated independently — CacheOnlyIOContext.swift:51
already records "3 closures (entryListProvider/endProvider/eofProvider @+0x18/+0x28/+0x38)".

**What blocks it is the FIELD, not the member.** `dump_field_type_mangles.py CacheOnlyIOContext`
gives that field as

    let   Say<SYM:2@0x1039f59a4>Gyc      = () -> [CacheFileEntry]

— `let`, and with NO trailing `Sg`, so NOT optional. The source declares
`var entryListProvider: (() -> [CacheFileEntry])?`: wrong binding AND wrong optionality. The
getter's eight instructions contain no nil check of any kind, which independently agrees with
non-optional; writing `entryListProvider!()` would add a check the image does not have.

So the unit is: retype the three provider fields (`entryListProvider`, `endProvider`, `eofProvider`
— all three read `let` and non-optional in the same dump), fix the initializer, then declare
`entryList`. The initializer is the real work: CacheOnlyIOContext.swift:28 records that these are
"assigned after super.init()", which is exactly what a non-optional `let` cannot be. Either they
are phase-1 initialised in Forward, or the init's shape differs — read it before moving anything.

## 6. What s106 got wrong, so you can distrust the same things

- **Two false anchors rejected.** `build_match_release.json` proposes `putPacket` for `0x101a5bc34`
  at similarity 0.5342 with **3603 matches over threshold**; the body is arity-0 and never reads
  x0, so it is `shutdown()`. And `DynamicRange` tag 3 is `.dolbyVision` — raw value 3 would be
  `.hlg`.
- **A build failure caught a false count.** Declaring all three displayEnum statics showed
  MEMBER_MISSING 178 and gave 0/4. A row that closes the sweep while breaking the build is not
  closed. Always run the build before believing a delta.
- **pin_sweep caught an access error.** Declaring five Color statics pushed ACCESS 26 → 31: they
  sit in a `public extension` but carry no `vpMV`, so they are internal. Explicit `internal` put it
  back. **Check ACCESS moved by zero, not just MEMBER_MISSING moved down.**
- **Three mechanical slips late in the session** — a wrong `__got` address computed twice, and one
  mixed-base shell arithmetic error. All caught, none shipped, but they are why s106 stopped at 180
  rather than pushing further; the per-row cost had risen to ~10 tool calls and the error rate with
  it.

## 7. Durability risk, unchanged and now larger

`play/.gitignore` ignores `scripts/` and `docs/`. Both `recover_field_offsets.py` (new, gate-wired)
and `method_source_presence.py` (the wave-split authority) exist **only on this disk**.
