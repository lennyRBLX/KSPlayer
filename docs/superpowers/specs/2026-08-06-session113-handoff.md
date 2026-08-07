# Session 113 work

**The queue is no longer gated on naming.** s112 cleared the CALL axis twice, screened every
remaining reachable row to a wall, and then built the tool for that wall. The wall is the FIELD axis.

The tool paid for itself before the session ended: `KSComplexPlayerLayer.playNextURL` @0x1019d27a8
closed (**67 -> 66**) because two s112 fixes landed on the same row — the gate learned that its
"blocker" `0x1019c835c` is an unspecialized stdlib `firstIndex(of:)` rather than a member to name,
and `recover_field_by_access` DECIDED its one unnamed field global as `isPictureInPictureStoped`
(UNIQUE, byte-class against three field records). That is the pattern to repeat: fix the classifier,
then re-check which rows were only ever blocked by a misclassification.

---

## Verify first

```bash
python3 scripts/recon_gate.py --mode handoff
```
```bash
python3 scripts/recon_progress.py
```
```bash
python3 scripts/pin_sweep.py --every
```

| what | expected |
|---|---|
| gate | `PASS 44   ANOMALY 6   FAIL 4` |
| FAITHFUL FLOOR | 333 / 1035 |
| MEMBER_MISSING | 66 |
| ACCESS | 26 |
| NOT_IN_TRIE | 23 |
| AMBIGUOUS_OVERLOAD | 10 |
| TYPE_DIVERGENCE | 4 |
| total disagreements | 129 |
| build | 4/4 |
| KSPlayer | branch `forward`, tree clean apart from 7 pre-existing untracked s98/s102/s104/s105 spec docs |
| FFmpegKit | `12f0899` on `forward-recon-shim`, 1167 tracked dirty files UNSTAGED. **Never `git add -A` there.** |

The 4 FAILs are pre-existing and were re-confirmed in s112: `sc_wave_worklist` (the OPEN
adjudication of `101a6ce44`, `wave_exclusions.json` entry 8, `adjudicated_session: 93`),
`agg_critical` 6, `agg_high` 24, `agg_unresolved` 1. No verdict file has an mtime at or after
2026-08-05; the newest is 2026-08-04 14:14.

Three selfchecks must print `SELFCHECK PASS`. All live only in `play/scripts/`, which is gitignored:

```bash
python3 scripts/rank_member_missing.py --selfcheck && python3 scripts/name_exhaustion_gate.py --selfcheck && python3 scripts/helper_fingerprint.py --selfcheck
```

`name_exhaustion_gate` must report **14** checks, not 9. s112 added five: the CSE'd-length
`#function` route, the arithmetic path, a negative control, and the two that matter most — the
FALSE EXHAUSTED at `0x1019c835c` and its reason. If it reports 9 the tool has been rolled back.

⚠️ **BEFORE INVENTING ANY APPROVED NAME, READ THE BODY FOR GENERIC-ALGORITHM SHAPE.** `0x1019c835c`
reached EXHAUSTED and sat inside the approved batch, and it is Swift's `firstIndex(of:)` over
`[URL]` — it reads the element STRIDE (`[vwt+0x48]`) and ALIGNMENT (`[vwt+0x50]`) from the
value-witness table and drives the generic `Equatable.==` witness thunk in a loop. Naming it would
have named the standard library. The gate now refuses that shape and the re-sweep reclassified
exactly that one address, but the general lesson stands: a body that computes its own element stride
is stdlib whatever the routes say, and only the disassembly shows it.

1. Read `reconstruction/blocker_classification_s112.json` before any planning. It holds the
   `name_exhaustion_gate` verdict for all 116 distinct unnamed callees, the sweep method, the
   ARTIFACT caveat and the s112 gate-fix record. Do **not** re-derive it per address with the CLI —
   each process rebuilds the image-wide `bl`-target Counter. Run it in ONE process
   (`import name_exhaustion_gate; g.evaluate(va, quiet=True)`), which takes ~20 minutes.

---

## Why naming is not the bottleneck

The population is **49 ARTIFACT · 13 INLINE-INSTEAD · 45 EXHAUSTED · 9 ROUTE-OPEN**. The human
approved inventing names for the EXHAUSTED set in s112; s112 screened it and **40 are eligible**
(all inside KSPlayer `__text`; 5 are Task/actor-shaped and off-limits per s108: `0x1019a26a8`,
`0x1019c80fc`, `0x1019d2bb0`, `0x101a3e510`, `0x101a47ae0`).

That approval does not unblock the queue, because s112 closed two CALL-axis blockers and the rows
behind them still did not become writable:

- `AVSampleBufferDisplayLayer.enqueue(imageBuffer:formatDescription:)` @0x101a61f60 — name RECOVERED
  from the `#function` default argument in argument position. Landed, and it closed
  `MetalPlayView.enterForeground` (68 → 67).
- `CacheIOContext.fetchedSize`'s `didSet` @0x101b863f0 — name recovered the same way, from a
  register-built SMALL string. Landed. It cleared `readComplete`'s last unnamed callee and the row
  **still did not open**, because of the FIELD axis.

2. Read `KSOptions.swift` around the `displayEnum*` block and `CacheIOContext.swift` around
   `fetchedSize` before planning. Both carry s112's measured negatives, and one RETRACTION —
   `35d70fe` retracts a wrong claim from `c8e4fc1`. Do not re-derive the retracted inference.

---

## 3. The unit: a field-recovery tool for `metadata_init=1` classes

This is the gate on MEMBER_MISSING → 2. It is deterministic, it is reusable across many rows, and it
does not exist.

**The problem, stated exactly.** A class with `metadata_init=1` has no static field-offset vector.
Its stored-property accesses load the offset from a per-field global. Some of those globals are
exported and the trie names them outright; the rest are non-public, and on this image they sit in
`__DATA,__common`, which is **zero-fill** — the offset value is not in the file at all. So both
static routes are closed and `recover_field_offsets` correctly answers `NOT RECOVERED`.

**The route that is open.** The ACCESS SHAPE at each use site is readable and carries the type:

| shape | implies |
|---|---|
| `ldrb w` / `strb` | `Bool` or `UInt8` |
| `ldr w` / `str w` | 32-bit — `Int32`, `Float` |
| `ldr x` + `adds`/`b.vs` | **signed** 64-bit — `Int64` |
| `ldr x` + `adds`/`b.hs` | **unsigned** 64-bit — `UInt64` |
| `ldr d` | `Double` |
| load followed by `swift_retain` / `objc_retain` | a class reference |
| two-word load, second word used as a table | a class-constrained existential |

`fieldrec` gives the class's fields IN ORDER with their mangled types, so the tool can bind an
unresolved global to the set of type-compatible fields that are not already bound by an exported
global, and report UNIQUE or refuse as AMBIGUOUS.

**s112 BUILT THE FIRST CUT.** `scripts/recover_field_by_access.py` exists, `--selfcheck` reports 13
checks, and it is goldened on two KNOWN answers recovered from access shape alone with the trie
names withheld: `CacheIOContext.stopOnLimitReached` as a byte access (`ldrb` + `cmp #1`) and
`fetchedSize` as a SIGNED dword (`ldr x` + `adds` + `b.vs`). It also carries two honest negatives —
SPILLED (distinct from ABSENT) and a global the body never touches. It is documented in the durable
inventory. Three bugs were caught by its own goldens while building it and are worth not
reintroducing: taking only the FIRST materialisation of an offset (a body re-loads the same offset
into several registers, so the first cut reported SPILLED for two fields whose access is plainly
there); parsing `fieldrec`'s bytes-repr type as literal text; and hand-building the class mangle,
which fails under backreference compression (`CacheIOContext` in `PreLoadIOContext` is `05CacheC0`).

**SPILL TRACKING IS DONE TOO** (s112). The scanner follows the offset through a stack slot, and only
slots written from a register provably holding this field's offset, so an unrelated slot cannot leak
in. `0x104c63938` in `readComplete` is now reachable: spilled at 0x101b8a154, reloaded at 0x101b8a37c,
used one instruction later by `ldrb w8, [x21, x8]`. Hand-verified before the golden was changed —
slot `[sp,#0x20]` is written exactly once and read exactly once in that body.

4. **What is left on `0x104c63938` is a DISCRIMINATOR, not reachability.** It is provably byte-class
   and four independent bodies agree — `readComplete` @0x101b8a0f8 (through the spill), `close`
   @0x101b8c83c, `fileSize` @0x101b8c178, `seek` @0x101b8a77c. Three of them READ it (`ldrb` +
   `cmp #1`); `fileSize` WRITES it — see the table below, which the all-accesses mode uncovered and
   the first-access-only scan could not. The tool still refuses, because 7 candidates survive after
   excluding `stopOnLimitReached`:
   `isJudgeEOF`, `saveFile`, `isReadComplete`, `eof`, `_isClosed`, `isInterleaved`, `isFirstFileSize`.

5. Routes for that discriminator, with the cheap one already eliminated:
   - ❌ **Accessors — CLOSED.** None of the 7 has an exported getter/setter on `CacheIOContext`. The
     only symbols are `vpfi` default-initializers, and only for 5 of them: `isJudgeEOF`, `eof`,
     `_isClosed`, `isInterleaved`, `isFirstFileSize`. `saveFile` and `isReadComplete` have no
     `CacheIOContext` symbol at all, which is itself a finding — both are designated-init PARAMETERS
     (they appear as init labels on the sibling classes), so they carry no declaration default.
   - The three private ones share the file-private discriminator `33_D69EFE1402863CA716A3171C7DB6DFB9`.
   - ✅ **DONE — `all_accesses()` shipped.** A single linear pass with a LIVE-REGISTER SET. Keep that
     set: s112 first tried it as a quick ad-hoc scan matching `[xBase, <reg>]` anywhere after `<reg>`
     had held the offset, and it was unusable — the offset lands in `x8`, `x8` is scratch and is
     immediately reused for OTHER field offsets, so it attributed other fields' accesses to this one
     and three unrelated bodies returned identical hit lists. With clobber tracking each body has
     exactly ONE access (7 -> 1 on `fileSize`), and that is what the table below rests on.
     A false WRITE site would name the wrong field.

**The constraint set on `0x104c63938`, as tight as deterministic evidence gets today:**

| body | access |
|---|---|
| `readComplete` @0x101b8a0f8 | `ldrb` (read, reached through the spill) |
| `close` @0x101b8c83c | `ldrb` (read) |
| `seek` @0x101b8a77c | `ldrb` (read) |
| **`fileSize` @0x101b8c178** | **`strb` @0x101b8c44c — the WRITE** |

The write is read in full at 0x101b8c418-0x101b8c45c, and it is a plain `= true` under a guard:

```
ldr  x8, [x20, #0x48] / cmp x22, x8 / csel hi / str      ; field@+0x48 = max(x22, field@+0x48)
ldrb w8, [x20, <global 0x104c63930>] / cmp w8, #1 / b.ne ; if <field@0x930> {
mov  w9, #0x1 / strb w9, [x20, <global 0x104c63938>]     ;     <field@0x938> = true
ldrb w8, [x20, <global 0x1044f3870>] / tbnz w8, #0       ;     if !<inherited field> {
```

⚠️ **0x104c63930 is a SECOND unnamed byte-class global on this class** and it is the guard. Naming
either one probably names both.

⚠️ **Adjacency is NOT a route, and this run proves it.** The four globals 0x920/0x928/0x930/0x938 sit
at stride 8, and the first two are `stopOnLimitReached` (field record 22) and `fetchedSize` (23). If
the run continued in field-record order, 0x930 and 0x938 would be `firstSeekTime` (24, a Double) and
`seekOffsets` (25, an Array) — but both are read with `ldrb`, so they are Bools and the ordering does
NOT hold. That is MEMORY's "offset globals are not in field-record order" demonstrated on this exact
run; do not reach for it as a shortcut.

**s112 also mapped the class's METHOD surface, which is the productive route from here.** The trie
carries 65 addressed `CacheIOContext` symbols (search for `16PreLoadIOContext05CacheC0C` — the class
mangles as `05CacheC0` under backreference compression, so the plain spelling finds nothing). Small
trie-NAMED methods that touch exactly one field bind that field's global by their own name:

- **`enableReadComplete()` @0x101b8a768 is five instructions and does one thing:** `strb #1` into the
  field behind global **0x1044f3878**. The method's name comes from the trie, so that global is
  `isReadComplete` — and it is NOT 0x104c63938, which ELIMINATES `isReadComplete` from the candidate
  list. Treat this as strong name-anchored evidence rather than a settled binding: a differently
  named flag could in principle gate read-completion.
- **`shouldContinueRead()` @0x101b8a0e0** returns `!field@0x1044f3848` (`ldrb` / `mov w9,#1` /
  `bic w0, w9, w8`), so 0x1044f3848 is a Bool whose negation gates continued reading.
- `canReadFromNetwork()` @0x101b885ac is a vtable thunk (`ldr x0,[x8,#0x388]; br x0`) — an override
  point, no field access. `resetSpeedSample()` @0x101b86038 writes CONSTANT offsets +0x58/+0x60/+0x68,
  which is worth knowing structurally: not every stored property on this class goes through a global.

⚠️ **This class's offset globals span TWO regions** — `0x1044f3xxx` and `0x104c63xxx` — and both are
runtime-initialised. The first reads as 0x0 in the file, the second is not backed by file content at
all, so `recover_field_offsets` refuses both and is right to. Do not treat a global's region as
evidence about which field it is.

⚠️ The last step from all of this to ONE name is still NOT a derivation — do not close it by picking
the candidate whose name reads best against a `fileSize` write. One route remains untried: look for a
site comparing against 2, which would settle the `Bool?` `isInterleaved`, since `Optional<Bool>`
stores `.none` as 2 and every site seen so far compares against 1.
   - ✅ **Still open:** a 3-valued tag compare would settle the `Bool?` `isInterleaved`, since an
     `Optional<Bool>` stores `.none` as 2 — every site seen so far compares against 1 only.

6. Run the extended tool over EVERY reconstructed class before trusting one result (MEMORY rule 10).
   The s112 sweep over `CacheIOContext`, `MetalSubtitleView`, `MetalPlayView` and
   `ReadCacheIOContext` returned sane maps; `MetalSubtitleView`'s independently matches the map
   proven in `f1483d3`, which is a useful ongoing control.

---

## 7. The rows it unblocks, and what else each needs

7. `CacheIOContext.readComplete(buffer:size:isReadComplete:)` @0x101b8a0f8, 412 instructions. CALL
   axis already clear. Needs `0x104c63938` named, plus the dispatch offsets `0x1e0` and `0x398` read.
8. `ReadCacheIOContext.fileSize` @0x101bad320, 218 instructions. s112 took this one furthest — it is
   an 8-field class, so the candidate set is small enough to be worth finishing.
   - `logicalPos` binds to **0x104c639e0** from its own getter @0x101bacad4 (a single-field accessor
     binds its global outright — the cheapest binding route there is, and it works on any class with
     an exported accessor).
   - **0x1044f6910** is dword-class: read in `read` and `seek`, read-modify-written in `fileSize`.
   - **0x1044f6918** is byte-class and is the ONLY byte global touched anywhere in `read`, `seek` or
     `fileSize`: `ldrb` in the first two, `strb` in `fileSize`.
   - 0x1044f6928 shows no global-indexed access in any of them.
   - The class has exactly TWO byte-class fields, `onlyCache` (record 2) and `eof` (record 3), so
     0x1044f6918 is one of those two — and **that is where it stops.**

   ⚠️ **Do not finish this one semantically. The two readings point in OPPOSITE directions**, which is
   why it is still open rather than merely unfinished:
   - `read()` would surely consult a "serve strictly from cache, no network" flag ⇒ argues `onlyCache`.
   - `fileSize()` overwriting a caller-supplied policy flag is odd; a private `var` with a `false`
     default being set when a size probe hits the end is natural ⇒ argues `eof`.

   Hard facts that do NOT break the tie, recorded so they are not re-derived: `onlyCache` has ZERO
   trie symbols on this class and appears as an init LABEL
   (`init(download:md5:bufferSize:onlyCache:)` @0x101bacd64), so it is an init parameter with no
   declaration default; `eof` has a `vpfi` @0x10002dab0, so it does have one. All three initialisers
   write their fields through CONSTANT offsets, not through offset globals, so the init route cannot
   bind `onlyCache` to a global either.

9. `MetalSubtitleView.draw` @0x101ac0e24 — ⚠️ **NOT the row to start on. An earlier paragraph in this
   same handoff said it was; that was wrong and this replaces it.**

   Its FIELD AXIS genuinely is clean, and that part stands: `0x1044ef5b0`, `0x1044ed178` and
   `0x104c63708` take ZERO indexed field accesses in the body, and the only two indexed globals are
   `0x1044ef5c0` -> `subtitleImages` and `0x1044ef5c8` -> `pendingTexts`, both named in `f1483d3`.

   But the COST is not 242 instructions, because **INLINE-INSTEAD IS TRANSITIVE** and nothing in the
   ranking shows that. `draw` calls `0x101ac11ec` (101 instr, INLINE-INSTEAD, so it must be inlined
   rather than named); that body calls three more, and every one of them is INLINE-INSTEAD too:

   | address | instructions | verdict |
   |---|---|---|
   | `0x101ac0e24` `draw` | 242 | the row |
   | `0x101ac11ec` | 101 | INLINE-INSTEAD |
   | `0x101ac1444` | **2396** | INLINE-INSTEAD |
   | `0x101ac23b4` | 508 | INLINE-INSTEAD |
   | `0x101ac25b0` | 244 | INLINE-INSTEAD |

   **~3,500 instructions that must all be read and expressed as ONE inlined body**, not 242. That is
   a 14x understatement, and it is the same family of error as "the triage instruction count is the
   thunk" — the row's own extent says nothing about the bodies that fold into it.

10. **The closure is now MEASURED for all 12 ready rows** — `reconstruction/inline_closure_cost_s112.json`,
    in bytes. The result is narrower than the `draw` case suggested, and that matters for planning:
    **eleven of the twelve have NO closure at all** (ranked cost == true cost). `draw` is the lone
    outlier at 968 -> 16112 bytes, 17x, its three largest inlined bodies being `0x101ac1444` (2396),
    `0x1019eba7c` (2172) and `0x1019eaf04` (2128).

    So `rank_member_missing`'s instruction column is accurate for most rows and catastrophically low
    for a few. Check the closure before picking a row; do NOT assume every row hides one. The walk is
    cheap if done right: follow any callee that is absent from the export trie and has exactly ONE
    call site image-wide, using `name_exhaustion_gate.call_sites`' counter built ONCE — calling
    `evaluate()` per callee is far too slow and will time out.

    Ranked by TRUE cost, the ready rows are: `AssIncrementImageRenderer.flush` 284 (libass-blocked),
    `KSComplexPlayerLayer.change` 508 and `KSAVPlayer.readyToPlay` 520 (both Task-closure, s108
    off-limits), `CacheIOContext.clearOtherCache` 700 (the TYPE trap), `ReadCacheIOContext.fileSize`
    872 (the 2-way field tie), `CacheIOContext.close` 1136 (the 7-way field tie), then everything
    else above 1500. **Every one of the cheap rows is blocked by something this handoff already
    names** — which is the honest reason the count did not move further, stated as a measurement
    rather than as a judgement.

---

## 10. Rows to leave alone, with the reason

Do not spend the session re-discovering these.

10. `CacheIOContext.clearOtherCache` @0x101b8d948 — the TYPE trap. Body transcribed, ranker says
    READY, cannot be written: `tmpURL` is `URL?` in source where the binary's `vpWvd` has no `Sg`.
11. `KSAVPlayer.readyToPlay` @0x1019a402c and `KSComplexPlayerLayer.change` @0x1019d1890 — both read
    "ready" only because `0x101a04674` verdicts ARTIFACT on a fan-in-only signal. It is a Task-closure
    standup, off-limits per s108.
12. `AssIncrementImageRenderer.*` — cleared only by `0x10245f0e0`, which is libass. **The libass
    naming unit is TRACTABLE and s112 established how**, which the earlier note did not know:
    libass ships as a STATIC ARCHIVE with a full symbol table — **192 defined text symbols** — at
    `FFmpegKit/Sources/libass.xcframework/ios-arm64/libass.framework/libass`. Thin it with
    `lipo -thin arm64`, then `ar x`, giving 20 `.o` files with real names. So this is a MATCHING
    problem against a named corpus, not an unnameable one.
    ⚠️ It is not a solved one. `ffmpeg_name_oracle --addr 0x10245f0e0 --resolve` returns UNKNOWN with
    `in_ffmpeg_band: false` — its index is FFmpeg only and does not cover libass; extending it is the
    unit. A whole-corpus MNEMONIC-SEQUENCE match of `0x10245f0e0` (38 instructions) against all 192
    functions found NO exact hit, so the linked build differs from the shipped one and the match must
    be structural rather than literal.
    **Two matching routes were tried and BOTH came back negative. Do not repeat them:**
    - *Exact mnemonic sequence.* `0x10245f0e0`'s 38-mnemonic sequence matched NO libass function.
    - *Call profile.* Forward's body calls `_free` x5 and nothing else. Exactly two libass functions
      call `_free` five times: `_ass_renderer_done` (72 instr, but 12 other calls — not the profile)
      and `_text_info_done` (22 instr, `_free` x5 only — the profile matches exactly). That looked
      like a unique hit and it is REFUTED: `nm` shows `_text_info_done` as lowercase **`t`**, a
      file-local static in `ass_render.o`, absent from the 192 external symbols. Swift in another
      translation unit cannot call it, so it cannot be `0x10245f0e0`.

    The `_ass_flush_events` guess is also unsupported — it was suggestive only because the blocked row
    is named `.flush` and the sizes were close, and neither test backs it.

    So the shipped archive genuinely differs from the linked build, and the unit needs a matcher that
    survives that: normalise for inlining, or match on string/constant operands rather than shape. ARTIFACT is right
    for "may I invent a Swift name" and WRONG as "no source counterpart": this is C you must call by
    name. Screen every ARTIFACT on the address range (`>= 0x102000000` is library code) before
    feeding it to `rank_member_missing --helpers`.
13. `KSAVPlayer.changePlaybackTime` and the SubtitleModel Task closure — off-limits from s108.
14. `KSOptions.displayEnumVR` / `displayEnumVRBox` — 23 instructions each and still blocked. s112
    measured the full escape: removing `@MainActor` from `DisplayEnum` and both conformers leaves
    EXACTLY five unresolved references — `MotionSensor.shared` ×2, `KSOptions.sceneSize` ×3 — and
    nothing else. The MotionSensor calls are REAL (`SphereDisplayModel.init` @0x101a8bf3c carries the
    `enableSensor` gate `0x1044e5150` and the full CoreMotion sequence), so the unit is small and
    fully enumerated but not free. `let` instead of `var` does NOT help; that was measured.

---

## The worklist your approval actually covers

s112 searched the population nobody had enumerated: rows blocked ONLY by EXHAUSTED addresses that are
approved-eligible (excluding the 5 Task-shaped ones), with no queued dependencies. **Thirteen rows**,
by ranked cost:

| instr | row | blocker(s) |
|---|---|---|
| 4 | `MetalSubtitleView.mtkView` | `101ac0a90` — but its own callee is a 809-instr INLINE-INSTEAD |
| 108 | `Coordinator.isRecord` | `1019d8d28` — **412 instr** |
| 132 | `KSComplexPlayerLayer.stop` @0x1019d2594 | `1019c7410` — **start here, see below** |
| 133 | `KSPlayerLayer.select` | `101ab2540`, `101ab2de4` |
| 158 | `AssIncrementImageRenderer.add` | `1019ad650` |
| 184 | `AssIncrementImageRenderer.updateTextStyle` | `101a9364c`, `101a960dc` |
| 204 | `DynamicInfo.update` | `1019ac164` — only 5 instr |
| 324 | `KSOptions.firstTimeLog` | `1019c1ca4` |
| 350 | `KSOptions.removeHeader` | `1019ac888`, `1019b3b50` |
| 789 | `CacheIOContext.cleanupOldCaches` | four blockers |
| 798 | `HLSCacheIOContext.parseM3U8` | `101b945b0` |
| 1638 | `CacheIOContext.seek` | `1019b1080`, `101b94b98` |
| 1663 | `PlayerView.buildMenusForButtons` | `1019afab0`, `101a0133c` |

**`KSComplexPlayerLayer.stop` @0x1019d2594 is the best-conditioned row in this table, but ⚠️ an
earlier draft of this section predicted it was a fourth false EXHAUSTED and THAT PREDICTION IS
WITHDRAWN — s112 tested it and the evidence does not support it.**

What is established. Its one blocker `0x1019c7410` is 17 instructions: move the caller's args aside,
load a witness from `[x2+0x10]`, build the SMALL STRING `"delegate"` in registers
(`0x6564`/`0x656c`/`0x6167`/`0x6574` = `de`/`le`/`ga`/`te`, discriminator `0xE8` = `0xE0|8`, count 8),
call the witness with it, then tail-call `0x1019c78a4`.

What refutes the artifact prediction:
- it has **4 call sites**, so it is SHARED — not INLINE-INSTEAD, and not a single caller's outlined code;
- it **tail-calls `0x1019c78a4`, a further 72-instruction NOT_IN_TRIE body**, so naming it would pull
  in a second unnamed unit rather than closing the chain;
- §8 refuted the KVC key as a NAME SOURCE — "do not call this body `delegate`" — which is a different
  claim from "this body has no source counterpart". Extending `is_compiler_artifact` on this evidence
  would be weakening the gate to pass a row, which MEMORY forbids outright.

So `stop` is NOT unblocked. What it still has going for it, and why it is worth starting here anyway:
`KSComplexPlayerLayer`'s FIELD axis is fully mapped — `urls` is trie-named, `isPictureInPictureStoped`
was bound by `recover_field_by_access` in s112, `enterBackgroundTask` is the only other field — so it
carries no field-axis debt, which is rare in what remains. The open question is a NAMING one about
`0x1019c7410` + `0x1019c78a4` as a pair, and it is a real question, not a misclassification.

**FIELD-AXIS SCREEN — all 13 rows, done.** `reconstruction/approval_worklist_fieldaxis_s112.json`.
A global counts only if it takes an ACTUAL indexed access in the body; merely appearing in the
disassembly is not a field use.

| instr | row | field axis |
|---|---|---|
| 4 | `MetalSubtitleView.mtkView` | CLEAN — but ~870-instr INLINE-INSTEAD chain |
| 32 | `Coordinator.isRecord` | **CLEAN** |
| 132 | `KSComplexPlayerLayer.stop` | 1 unnamed: `0x1044e61e8` |
| 133 | `KSPlayerLayer.select` | **CLEAN** (2 fields) |
| 158 | `AssIncrementImageRenderer.add` | 3 unnamed |
| 184 | `AssIncrementImageRenderer.updateTextStyle` | 4 unnamed |
| 204 | `DynamicInfo.update` | **CLEAN** (1 field) |
| 324 | `KSOptions.firstTimeLog` | **CLEAN** (12 fields) |
| 350 | `KSOptions.removeHeader` | **CLEAN** (1 field) |
| 789 | `CacheIOContext.cleanupOldCaches` | **CLEAN** |
| 798 | `HLSCacheIOContext.parseM3U8` | 1 unnamed |
| 1638 | `CacheIOContext.seek` | 7 unnamed |
| 1663 | `PlayerView.buildMenusForButtons` | **CLEAN** (1 field) |

**Eight of thirteen are field-clean**, so on those the ONLY remaining gate is naming — which is what
the approval covers. That reverses the impression the rest of this handoff gives, and it is the most
actionable thing in it.

⚠️ It also CORRECTS an earlier s112 claim recorded above: `DynamicInfo.update` was said to carry "its
own unresolvable field global" `0x1044e4690`. It does not. That global appears in the body but takes
no indexed access, so it is not a stored-property use at all. The lesson generalises — **screen on
ACCESSES, never on the global list**, or you will invent blockers that are not there. `KSComplexPlayerLayer.stop`
is the one row where a genuine unnamed field remains (`0x1044e61e8`), so it is NOT the cheapest start
despite its clean call axis.

**Start with `Coordinator.isRecord` (32 instr, clean) or `KSPlayerLayer.select` (133 instr, clean),
not with `stop`.** Both still need their blockers named — `1019d8d28` (412 instr) for the first,
`101ab2540` + `101ab2de4` for the second — but neither carries field-axis debt.


---

## Tool notes s112 paid for

15. `field_offset_vector.py` needs `--module PreLoadIOContext` for that module's classes. Without it
    it looks up a `KSPlayer`-prefixed symbol, fails, and reports "no exported metadata symbol in the
    trie" — which reads as a finding about the class and is really a wrong-module lookup.
16. `decode_string_literal.py --addr <fn>` crashes on a body whose globals include a `__DATA` address
    (it tries to read `KSOptions.logger` as a string). Use `--at <addr> --count <n>` per literal.
17. `name_exhaustion_gate` has a second, still-unfixed `#function` gap: it reads pointer-form literals
    only and misses a SMALL string built in registers. That is how `0x101b863f0` reported "no
    #function candidate" while its `#function` was plainly `fetchedSize` (x4 = `fetchedS`, x5 = `ize`
    under discriminator `0xEB`). Fixing this is a smaller job than step 4 and worth doing first.

---

## Close out

18. Update `handoff_baseline.json` with a `captured_session113` block.
19. Write the session 114 handoff.
