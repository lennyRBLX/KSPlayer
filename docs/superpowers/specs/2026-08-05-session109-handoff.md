# Session 109 handoff — two members landed, and three blockers characterised

**ORIENTATION ONLY. This document authorizes no work.**

## 1. Verify first (do these, then stop)

Run from `/Users/jweaver/Desktop/Work/swift/play`. Confirm each rather than quoting it.

1. `python3 scripts/pin_sweep.py --every` → **MEMBER_MISSING 106**, ACCESS 26,
   NOT_IN_TRIE 24, AMBIGUOUS_OVERLOAD 10, TYPE_DIVERGENCE 4.
2. `python3 scripts/recon_gate.py --mode handoff` → **PASS 44 · ANOMALY 6 · FAIL 4**.
3. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/validate_build.sh` → **4/4**.
4. `git -C ../KSPlayer log --oneline -1` → **dce5752** on **forward**, tree clean (no non-`??`).
5. `python3 scripts/recover_field_offsets.py --selfcheck` and
   `python3 scripts/field_offset_vector.py --selfcheck` → both **SELFCHECK PASS**. These still
   live only on this disk (`play/scripts/` is gitignored). `recover_field_offsets.py --class
   KSPlayerLayer` must still list 7 globals including `0x104c634f0 → player`.

The four FAILs are unchanged from s108 and **confirmed pre-existing** — I traced each to the
verdict that produces it and checked it against the drive window (everything after `280ed2f`,
2026-08-04 18:55:40):

* `sc_wave_worklist` — its only failing line is `1 OPEN-adjudicated addresses vanished from the
  waves: ['101a6ce44']`. Verdict `VideoToolboxDecode_decodeFrame_idx29_101a6ce44_s104.json`,
  written 2026-08-04 12:07. (I confirmed the address and that it is OPEN; I did NOT verify the
  "OPEN since s93" provenance — the verdict on disk is tagged s104.)
* `agg_critical 6` / `agg_high 24` — these ARE the file counts in
  `reconstruction/fix_queue/{CRITICAL,HIGH}`. The 30 entries trace to 13 verdicts, session-tagged
  s81/s84/s85/s104 plus one untagged, mtimes 2026-07-30 15:50 → 2026-08-04 14:14. All predate
  the window.
* `agg_unresolved 1` = `VideoSwresample_DVbodies_deferral_p3a`, 2026-07-30 11:44.

Note s108's §1 expected HEAD `4168fb7`; it was already `a70261d` at takeover, because the s108
handoff's own commit landed after its §1 was written. Only the two doc files differ.

---

## 2. What moved

MEMBER_MISSING **108 → 106**. No other bucket moved; the gate line is unchanged.

* `b58e654` — `URLSubtitleInfo.isSrt` @0x101aa3914 (90 instr):
  `name.hasSuffix("srt") || downloadURL.pathExtension == "srt"`.
* `dce5752` — `TextPosition.alignment` @0x101abb264 (99 instr): the ASS numpad map — nine
  `(VerticalAlignment, HorizontalAlignment)` cases returning "1".."9", default "2".

For both, `public` is proven by a `vpMV` property descriptor and get-only by the ABSENCE of
`…vs` / `…vM` from the trie. Do not infer either from the class's access level.

**Use the triage's demangled field.** `member_missing_triage.py --json` emits, per row, the
address, the instruction count AND the fully demangled signature. That third field is the
cheapest signature source in the pipeline and removes the need to re-derive arity or labels for
any of the remaining 106 rows.

**New technique — settle a calling convention with a compiled probe.** `String.hasSuffix` put
the literal in (x0,x1) and the field in (x2,x3); which is `self` decides the member. Instead of
assuming, compile `public func probe(_ s: String) -> Bool { s.hasSuffix("srt") }` with
`xcrun swiftc -O -emit-assembly`. It reproduces the site's exact sequence, including the literal
encoding, so the receiver is settled by construction. Reach for this whenever a multi-word
`self` makes receiver-vs-argument ambiguous — it is far cheaper than reasoning about the ABI.

---

## 3. A correction to a source file

`Sources/PreLoadIOContext/URLContextDownload.swift:65-67` claims `read` / `write` / `seek`
"are devirtualized in the binary (no readable body) … NOT reconstructed". **That is false.**
All four members have readable bodies and I disassembled them:
`read` @0x101b91078 (30), `seek` @0x101b910f0 (24), `fileSize` @0x101b91150 (18),
`close` @0x101b91198 (22). They are blocked for a different reason (§4), not for want of a body.
Correct the comment when the file is next touched.

---

## 4. Blocked: the PreLoadIOContext download chain is ONE knot, not four rows

s108 §5 recorded "Four rows need both fixes". The same unnameable FFmpeg entry points are
reached from at least three classes:

* `URLContextDownload` — the four above, calling the entry points DIRECTLY.
* `HLSCacheIOContext` — `fileSize` @0x101b975e0, `seek` @0x101b9757c (and `read` @0x101b97480 by
  shape). These are the same bodies one indirection deeper: load `self.download` at +0x18, then
  that object's `context` at +0x18, then call the same `0x1030c07ac`. The compiler INLINED
  `URLContextDownload.seek` into them.
* `ReadCacheIOContext` — `read`/`seek`/`close`/`fileSize` are unread but sit on the same
  `download` field; expect the same shape.

So no row in the knot can land before the root does, and fixing the root plausibly unblocks all
of them together. Rank it as one unit, not as N cheap rows.

Blocker re-confirmed by running it, not by quoting:
`ffmpeg_name_oracle --function 0x101b91078 --expect 0x1030c0994:ffurl_read_complete,0x1030bf914:ffurl_read`
→ the first is `CONSISTENT_AMBIGUOUS` (consistent fingerprint, 93 instr / 372 B, avformat/avio.o,
but shared by 6 indexed symbols with the discriminator UNAVAILABLE — "NOT identity proof"); the
second is `UNKNOWN_SYM`.

What is readable and should not be re-derived (self is x20, the arm64 swiftself register):
all four take `swift_beginAccess(&self.context /*+0x18*/, …)` then nil-check
(`0x104112d88 → _swift_beginAccess`, `0x104112e40 → _swift_endAccess`). `read`'s nil arm returns
`0xdfb9b0bb` = `-0x20464F45` = `-MKTAG('E','O','F',' ')` = AVERROR_EOF, and its non-nil path
branches on a Bool at `[x20,#0x21]`. `seek`/`fileSize` return -1 on nil, and `fileSize` passes
`x1=0, w2=0x10000` — AVSEEK_SIZE, which is the argument that identifies `0x1030c07ac` as the
seek entry. `close` takes the **modify** access (flags 0x21, the only one with a matching
`swift_endAccess`) and passes `&self.context`, a `URLContext **`. The argument SHAPES are
dispositive even where the NAMES are not provable.

---

## 5. Blocked: `parse(url:scanner:)` is a protocol evolution

`FFmpegSubtitleParse.parse` @0x101a9eff4 (46) and `AssImageParse.parse` @0x101a8f5a8 (73) are
both `parse(url: Foundation.URL, scanner: __C.NSScanner) throws -> KSPlayer.KSSubtitleProtocol`.
Source's `KSParseProtocol` declares `parse(scanner:) -> [SubtitlePart]`. Forward added a `url:`
parameter, made it `throws` and changed the return type — a cross-file change touching the
protocol and every conformer. Do not land one conformer alone.

`FFmpegSubtitleParse.parse`'s body is fully read and small, so the unit is cheap ONCE the
protocol moves: `swift_allocObject(FFmpegSubtitle.metadata, 168, 15)`, then an unnamed init at
0x101a9f27c taking a copied `URL` with self in x20, guarded by `cbnz x21` (swifterror), boxed
into the indirect return as a `KSSubtitleProtocol` existential. i.e. `try FFmpegSubtitle(url: url)`;
`scanner` is unused.
`0x101a9f0ac` = type metadata accessor for `FFmpegSubtitle`;
`0x1041da3a8` = protocol witness table for `FFmpegSubtitle : KSSubtitleProtocol`;
`0x101a9f27c` = NOT_IN_TRIE.

---

## 6. Blocked: MetalPlayView — and a positional mapping that is REFUTED

`enterBackground` @0x101a6095c (93), `enterForeground` @0x101a60ad0 (156), `layoutSubviews`
@0x101a602dc (103). `enterBackground` is structurally read — set one Bool field true, return
early if either of two other Bool fields is set, then compute `1.0 / <Float field>` and call a
method on an object field — and blocked on FIVE field identities.

`recover_field_offsets --class MetalPlayView` names only 5 globals (0x1044ea8b0 `rotation`, 8b8
`pixelBuffer`, 8c0 `options`, 8c8 `renderSource`, 8d0 `drawable`) and those are exactly the
class's `public` fields. The body uses 0x1044ea8d8, 8e8, 8f8, 908, 928, and every remaining field
is `private` (`export_trie_oracle --class MetalPlayView`: displayLink, forcedFrameRetryScheduled,
fps, isBackground, isPaused, metalView all private), so none emits a `vpWvd`.

**Do not map them positionally.** The five named globals are consecutive in field-record order
(idx 3..7 at 8b0..8d0, step 8), which makes `global(idx) = 0x1044ea898 + 8*idx` look right. It is
refuted: it sends 0x1044ea8f8 to idx 12 `displayLink`, and that site is a **byte** store of 1.
`fieldrec --class MetalPlayView --module KSPlayer` gives the 17-field order; the globals are not
a dense array over it. This is s108 §6's "~74 rows needing per-class field derivation" met
concretely — the derivation is the unit, and it is per class, not per member.

---

## 7. The KSPictureInPictureProtocol blocker is WIDER than the 13 KSComplexPlayerLayer rows

s108 §6 records `KSComplexPlayerLayer` (13 rows) as blocked behind `KSPictureInPictureProtocol`,
which the binary gives 10 requirements against source's 5. **`KSAVPlayer.configPIP` @0x1019ab4dc
(62 instr) is behind the same gap**, and `KSMEPlayer.configPIP` @0x101a445c8 (64) is its twin by
shape. Count that protocol as gating at least 15 rows, not 13.

`configPIP` is otherwise READ, and is a one-liner once the requirement exists:

* a `swift_once` guard on 0x1044e5178, then a read access on the static
  `0x104c632c0` = `static KSPlayer.KSOptions.pictureInPictureType :
  KSPictureInPictureProtocol.Type` — already declared at `KSOptions.swift:1133`. `ldp x21, x22`
  splits it into (concrete metatype, witness table).
* `objc_msgSend(self+0x38, 'layer')` → `objc_retainAutoreleasedReturnValue` →
  `objc_opt_self(AVPlayerLayer)` → `swift_dynamicCastObjCClassUnconditional`. So the argument is
  `<the view at self+0x38>.layer as! AVPlayerLayer`.
  `0x104410bc0` = `__objc_classrefs AVFoundation _OBJC_CLASS_$_AVPlayerLayer`;
  selref 0x10440bf70 = `'layer'`.
* `ldr x8,[x22,#0x18]; blr x8` with the metatype as swiftself and the cast layer in x0 — i.e. a
  STATIC requirement at witness slot +0x18 taking an `AVPlayerLayer`. Source's five requirements
  (`isPictureInPictureActive`, `start(layer:)`, `didStart(layer:)`, `stop(restoreUserInterface:)`,
  `static play(layer:)`) contain no such member, so this is one of the five the binary has and
  source lacks.
* `csel x21, xzr, x22, eq` then `stp x20, x21` into the `pipController` field
  (offset global 0x104c63060, named) under a modify access — so the requirement returns an
  OPTIONAL conformer: a null object stores a nil existential rather than (obj, witness).

Deriving that one requirement's name and signature unblocks two rows immediately and is a
prerequisite for the KSComplexPlayerLayer 13 regardless.

## 8. `KSAVPlayer.readyToPlay()` is READ IN FULL and blocked only by a helper's signature

Body @0x1019a402c (130 instr, vtable slot 93), and its deferred closure @0x1019a4234 (51 instr)
which the s89 verdict left closed — **I opened it**. Nothing about this member is unknown:

    public func readyToPlay() {
        options.readyTime = CACurrentMediaTime()
        runOnMainThread { [weak self] in
            guard let self else { return }
            delegate?.readyToPlay(player: self)
        }
    }

The closure is the same shape as `process(error:)`'s continuation: `swift_weakLoadStrong` + `cbz`
is `guard let self`, `swift_unknownObjectWeakLoadStrong` on 0x104c63068 + `cbz` is `delegate?`,
and the call is witness slot **+0x8** = req0 `readyToPlay(player:)`. The body changes no KSAVPlayer
stored property — notably it does NOT set `isReadyToPlay`.

**It does not compile, and the reason is a real divergence, not a spelling problem.**
`MediaPlayerDelegate` is `@MainActor`-isolated, so the call needs MainActor context. This tree's
helper is `runOnMainThread(block: @escaping @Sendable () -> Void)` using `MainActor.run(body:)`
(Core/Utility.swift:368), which gives the block no static isolation — so line
`delegate?.readyToPlay(player: self)` fails with *"sending value of non-Sendable type
'any MediaPlayerDelegate' risks causing data races"*.

Forward's helper has EVOLVED, and the binary says exactly how: the `Thread.isMainThread` true arm
calls a **`MainActor.assumeIsolated`** specialization and the false arm creates a **`Task` whose
operation is `@MainActor`**. That pair is the lowering of a helper whose block is `@MainActor`,
not `@Sendable`:

    func runOnMainThread(_ block: @escaping @MainActor () -> Void)

**I made the signature change and measured what it actually costs. The grep count is a red
herring: 33 call sites exist, and exactly ONE breaks.** Every other caller already compiles
against a `@MainActor` block. The single failure is `AudioBaseOutput.swift:178`:

    runOnMainThread { [weak self] in
        self?.prepare(audioFormat: render.audioFormat)
    }

which now sends a non-Sendable `self` (`AudioBaseOutput` is a plain `public class`) and a
non-Sendable `render` into a MainActor-isolated closure — two `#SendingRisksDataRace` errors.
**`@preconcurrency` does not downgrade them**; I re-added it and re-built to check, and the errors
are unchanged, so keeping that attribute is not a way out.

Hoisting `render.audioFormat` into a local would remove one of the two, but `self` remains, and
clearing it means giving `AudioBaseOutput` a Sendable conformance — a claim about Forward's
concurrency model that this binary does not make. I did not invent it. Both edits were reverted
and the tree is green at `cf8cd09`, build 4/4.

So the unit is: **the helper signature plus a decision about `AudioBaseOutput`'s Sendability.**
That second half needs either a reading of Forward's own AudioBaseOutput or an explicit call from
the human. It is one contained obligation, not a 33-site refactor — which is the opposite of what
the call-site count suggests, and the reason to measure by compiling rather than by grepping.

## 9. `KSOptions.makeDecode(packet:)` — a RELOCATION, and the last blocker is an init arity

`KSOptions.makeDecode(packet: KSPlayer.Packet) -> KSPlayer.DecodeProtocol` @0x1019b604c is only
52 instructions and all of it is read:

* `ldr x22,[x19,#0x40]` then `cbz → brk #1` — a force unwrap. +0x40 is `Packet.assetTrack`, and
  that is not positional guesswork: `Packet` is `metadata_init=0`, so `field_offset_vector Packet`
  gives real static offsets (duration 0x10, timestamp 0x18, position 0x20, size 0x28, corePacket
  0x30, isFlush 0x38, **assetTrack 0x40**, InstanceSize 0x48).
* a virtual call on self at `[x8,#0x5f0]`. KSOptions `VTableOffset = 94 words (0x2f0)`, so the slot
  is `(0x5f0-0x2f0)/8` = **96** = 0x1019b5fe0 =
  `KSOptions.process<A: MediaPlayerTrack>(assetTrack: A)` — already declared. The generic call
  passes the FFmpegAssetTrack metadata (0x101a21c14) and the
  `FFmpegAssetTrack : MediaPlayerTrack` conformance (0x10356a680) as x1/x2.
* then a tail call into the 362-instruction helper @0x1019b611c (NOT_IN_TRIE) with the indirect
  return, whose result is returned unchanged. That helper is the decoder selection, and all three
  arms are NAMED: `SubtitleDecode.init(assetTrack:options:)` @0x101a6914c (note `options:
  KSOptions?`, optional), `FFmpegDecode.init(assetTrack:options:)` @0x101a21d60, and the
  `VideoToolboxDecode` metadata accessor @0x101a6f3dc.

**This is a relocation, not a new member.** Source has
`SyncPlayerItemTrack.makeDecode(assetTrack: FFmpegAssetTrack)` (MEPlayerItemTrack.swift:330) with
exactly that three-way `autoreleasepool` body. Forward moved it onto `KSOptions`, changed the
parameter to the `Packet`, derives `assetTrack` from it, and added the `process(assetTrack:)` call.

**Blocker.** The VideoToolboxDecode arm cannot be written: `pin_sweep` already reports
`VideoToolboxDecode.init` as NOT_IN_TRIE with `source (options, session)` against
`binary (assetTrack, options, asynchronous)`. So this row waits on that init's arity change — the
same class of evolution as §5, and one more instance of the pattern that every remaining row is
gated by a signature change, a chain, a field derivation, or an unnameable symbol.

## 10. `Anime4KPreset.autoSelect(for:)` — UNBLOCKED, just large. Start here.

**Correction to this document's own framing.** §4–§9 could be read as "everything left is blocked."
That is not true, and this row is the counterexample: it has no protocol evolution, no chain, no
unnameable symbol, and no field-derivation problem. `Anime4KPreset` is an **enum** — its "0 offset
globals" is the correct answer for a type with no stored properties, not a gap. The only reason it
did not land this session is size.

`static Anime4KPreset.autoSelect(for: __C.MTLDevice?) -> Anime4KPreset` @0x101a7bb14,
extent 0x101a7bb14-0x101a7bf98, 289 instr. The algorithm is already identified from its resolved
call set, so the next session does not have to discover it:

* `uname` (libSystem, __got 0x10410c698) after a `bzero` (0x10410bd68) — it reads `utsname`.
* `Mirror.init(reflecting:)` (0x104112aa0), `Mirror.children` (0x104112ab0), `Mirror` metadata
  (0x104112ab8), `_AnySequenceBox._makeIterator` (0x104111ff8) and `_AnyIteratorBox.next`
  (0x104112198), with `swift_dynamicCast` (0x104112df8) on each child, and
  `String._uncheckedFromUTF8` (0x1041113f0) plus `String.append` (0x104111448).
  That is the standard `utsname.machine` → model-identifier idiom: reflect the C char tuple,
  cast each child, append the bytes.
* `StringProtocol.contains(_:)` (Foundation, __got 0x10410a6d0) — the model string is then matched
  by SUBSTRING, repeatedly, and each match selects a case.
* the `MTLDevice?` parameter is nil-checked at 0x101a7bb88 (`cbz x20`).
* returns are bare case indices: `mov w0,#0x4` @0x101a7be6c and `mov w0,#0x1` @0x101a7bf04 are
  already visible (case 4 = `modeAHQ`, case 1 = `modeAFast` against the 12-case order in
  Anime4KPreset.swift:37-49). Two local helpers, 0x101a7c6b4 and 0x101a7c664, are called from the
  string-building loop.

What remains is mechanical: decode the `contains` literals and enumerate the remaining
`mov w0,#N` returns with their guards. Note the s107 lesson recorded in this file's sibling
commit — a small string's discriminator is `0xA0|n` when it holds any non-ASCII byte, and only
`0xE0|n` when it is all-ASCII; device identifiers are ASCII, but any Chinese UI string in the
same function is not.

## 11. THE REFRAMING: "0 offset-globals" does NOT mean blocked — check for STATIC metadata first

This is the most useful thing the session produced, and it invalidates part of §6's reasoning.

I twice treated `recover_field_offsets --class X` returning **0 offset-globals** as evidence that a
class needed expensive per-class derivation. That is wrong. That tool answers the
`metadata_init=1` question — "which runtime offset globals can I name from accessors". A class or
value type with **static** metadata has no offset globals *because its offsets are immediates*, and
they can be read directly:

    python3 scripts/field_offset_vector.py <Type> --module <Module>     # classes with static metadata
    # and for a struct/enum, straight out of its static metadata symbol:
    #   $s…VN  → word0 kind, word1 descriptor, then a UInt32 field-offset vector at +16

That second route is what unblocked `SubtitlePart.change` (3 bodies in one row): reading
`SubtitleTextInfo` @0x1041daee0 and `SubtitleImageInfo` @0x1041daca0 gave exact offsets, which is
how +0x5a was proven to be `usesForcedPosition` and +0x80 `SubtitleImageInfo.styleRole` rather than
counted off.

**Classified so far** (`field_offset_vector <cls> --module KSPlayer` over the queue's owners):

* **STATIC — offsets readable now:** `Anime4KPipeline` (0xe0), `AssImageParse` (0x10),
  `DirectoryWatcher` (0x78), `DoviDisplayModel` (0x58), `FFmpegSubtitleParse` (0x10),
  **`IOSVideoPlayerView` (0x330 — all 38+ fields named, `originalSuperView` 0xf0 …
  `displayTitleLabel` 0x238)**.
* **RUNTIME — genuinely need anchor recovery:** `AssIncrementImageRenderer`, `DynamicInfo`,
  and `MetalPlayView` (§6 stands for those).
* The PreLoadIOContext-module owners need `--module PreLoadIOContext`; the sweep timed out before
  reaching them, so that classification is unfinished, not negative.

So `DirectoryWatcher.watchModify`/`watchNew` (379/434) and `IOSVideoPlayerView.showPromptMessage`
(152) / `updateVideMetaLabel` (233) are **large, not blocked**. Re-read §4–§9 with that in mind:
the genuinely-gated set is smaller than this document first implied.

**Two rows really are unrecoverable, and now confirmed by address.**
`IOSVideoPlayerView.toggleBottomSlimProgress()` and `IOSVideoPlayerView.updateTitle(_:)` both
resolve to **0x10198eb18**, the deleted-method fold whose four instructions end in a `brk` through
`_swift_deletedMethodError`. Their names are in the trie and their code is gone, so no amount of
work recovers a body. These are s108 §5's "two rows with no recoverable body"; they are these.

**`showPromptMessage` — the OUTER function is fully read; only its closure body remains.**
`IOSVideoPlayerView.showPromptMessage(_ message: String)` @0x101b0cfb8, 152 instr. It does exactly
one thing:

    DispatchQueue.main.async { [weak self] in … }

Every piece of that is named, not inferred: `swift_unknownObjectWeakInit` (__got 0x1041130e0) into
a 24-byte box is the `[weak self]`; the 40-byte context holds that box at +0x10 and the `String`
parameter's two words at +0x18/+0x20; `DispatchQueue.main` is __got 0x1041134d8 and the call is
`DispatchQueue.async(group:qos:flags:execute:)` __got 0x1041134f0. The `DispatchQoS.unspecified`
(0x104113398) and the empty `DispatchWorkItemFlags` built through `SetAlgebra.init(_:)`
(0x104111bb8) over `__swiftEmptyArrayStorage` are the DEFAULT arguments materialised at the call
site — they are not written in the source. The `_Block_copy`/`_Block_release` pair (0x10410bb38 /
0x10410bb50) around a stack block whose `isa`, invoke pointer 0x100004aec and descriptor
0x1041dd930 are assembled inline is just the `@convention(block)` bridge for `execute:`.

**Where to resume.** The `execute:` pointer 0x101b15e5c is a 3-instruction reabstraction thunk —
`ldp x0,x1,[x20,#0x10]` / `ldr x2,[x20,#0x20]` / `b 0x101b0d218` — so the real closure is
**0x101b0d218, extent 0x101b0d218-0x101b0d630, 262 instr**, i.e. bigger than the function that
installs it. Two things about it are already decoded:

* it opens with a `@MainActor` assertion — `swift_task_isCurrentExecutor` then, on failure,
  `swift_task_reportUnexpectedExecutor` with `w1 = 0x21` (count 33), `w2 = 1` (ASCII) and
  `w3 = 0x4ed`. The literal at 0x103d3aad0 decodes to **`KSPlayer/IOSVideoPlayerView.swift`**, so
  the closure sits at **line 1261** of Forward's own IOSVideoPlayerView.swift.
* then `swift_beginAccess`(flags 0) + `swift_unknownObjectWeakLoadStrong` on the box at +0x10 with
  a `cbz` — the `guard let self else { return }`.

The remaining ~250 instructions are the UIKit work, and `IOSVideoPlayerView`'s field offsets are
all readable (see the STATIC list above), so this is a straight read with no blocker in front of it.
It was left unfinished rather than guessed at.

**The closure's whole call set is already resolved — 46 targets, so do not re-derive it.**
Non-ObjC: `String._bridgeToObjectiveC`, `Array._bridgeToObjectiveC`, `MainActor.shared` + its
metadata + `Actor.unownedExecutor` (the isolation check), `_Block_copy`/`_Block_release`,
`swift_allocObject`, `swift_beginAccess`, `swift_release`, `swift_task_isCurrentExecutor`,
`swift_task_reportUnexpectedExecutor`, `swift_unknownObjectWeakLoadStrong`, and the usual
`objc_retain*`/`objc_release*`/`objc_opt_self` family. Three local helpers are NOT_IN_TRIE:
0x100006158 (witness-table accessor), 0x100029510, 0x10002d984 (mangled-name type instantiation).

The 19 ObjC selectors spell the whole behaviour, in the order they appear:

    removeFromSuperview · setText: · setTranslatesAutoresizingMaskIntoConstraints:
    addSubview: · bringSubviewToFront: · safeAreaLayoutGuide
    topAnchor · centerXAnchor · widthAnchor · heightAnchor
    constraintEqualToAnchor: · constraintEqualToAnchor:constant:
    constraintGreaterThanOrEqualToConstant: · constraintLessThanOrEqualToAnchor:multiplier:
    activateConstraints: · setAlpha: · animateWithDuration:animations:
    cancelPreviousPerformRequestsWithTarget:selector:object: · performSelector:withObject:afterDelay:

i.e. a prompt/toast: tear down any existing prompt view, build a label carrying the `message`
parameter, pin it under the safe-area top and centred with width/height constraints, activate them,
fade it in with a UIView animation, and reschedule a delayed dismissal (the
`cancelPreviousPerformRequests…` / `performSelector:…afterDelay:` pair).

**What is still genuinely unread**, and what the next session must take from the binary rather than
from this paragraph: which `IOSVideoPlayerView` field holds the prompt view, every Auto Layout
constant, the animation duration, and the `afterDelay:` value plus the selector it performs. Those
are immediates and offsets in the body — all readable, none of them guessed here.

## 12. §6's blocker does not exist — and the tool already knew. Read this as a process failure.

**Correction to my own first draft of this section.** I derived the value→field route by hand,
wrote it up as a new technique, and was wrong about the "new". `recover_field_offsets` already has
it, added in s107 as `name_global_by_value(cls, glob, module)`. It answers every case I
hand-derived, in one call:

    name_global_by_value("IOSVideoPlayerView", 0x1044f1000) -> 'promptLabel'
    name_global_by_value("IOSVideoPlayerView", 0x1044f0ea8) -> 'title'
    name_global_by_value("MetalPlayView",      0x1044ea8f8) -> 'isBackground'

The third is the one that matters: **MetalPlayView, the class §6 pinned as needing anchor
recovery.** The tool names its private globals outright. My hand derivation independently
reproduced all three answers, which is how the tool turned out to have them — corroboration, not
discovery.

**So why did §6 record a blocker?** Because `field_offset_vector`'s **CLI refuses MetalPlayView**
("has metadata_init=1 … the static image holds no field offsets") while its own
**`resolve()` succeeds** on the same class and returns 17 fields with real offsets. I hit exactly
that refusal, believed it, and wrote §6 around it. `name_global_by_value` calls `resolve()`, not
the CLI, which is why it works where the command line says it cannot.

That CLI/library split is a real defect and the actionable item here — it is a trap that has now
cost two write-ups. Either the CLI's refusal is too strict, or `resolve()` is returning offsets the
CLI is right to distrust; **one of them is wrong and a golden should decide which** before the
route is leaned on across the ~74 rows §6 assigned to per-class derivation.

Pending that, the naming is well corroborated. For MetalPlayView every prediction is confirmed by
the LOAD WIDTH at its use site in `enterBackground` — a discrimination a wrong mapping could not
fake:

    0x1044ea8f8 = 0x82 → isBackground                   `strb` 1  — and the method is enterBackground
    0x1044ea928 = 0xa8 → renderUseDispatchSourceTimer   `ldrb`
    0x1044ea8d8 = 0x08 → isPaused                       `ldrb`
    0x1044ea908 = 0xa0 → backgroundTimer                `ldr x` (object)
    0x1044ea8e8 = 0x18 → fps                            `ldr s0` + `fcvt d0,s0` — a 32-bit FLOAT

Three Bools as bytes, the Float in a single-precision register, the timer as a word. The dense-index
mapping §6 refuted got `0x1044ea8f8` wrong; this gets it right and says `isBackground`, inside a
method called `enterBackground`.

**The lesson, which is MEMORY rule 4 verbatim: compute a fact with its tool, never recall it.**
§6 recalled a limitation instead of calling `name_global_by_value`. I then hand-derived instead of
calling it too. The route existed the whole time.

### superseded first draft of this section — kept for provenance

§6 says MetalPlayView's five private offset globals cannot be named without anchor recovery, and
records the positional mapping as refuted. **The refutation stands but the conclusion was wrong** —
there is a third route, and it is cheap and deterministic.

An offset global for a `metadata_init=1` class is patched at runtime, but it is **not empty in the
image**. It carries the compile-time offset as its static initialiser, and that value is enough to
name it, because Swift lays stored properties out in declaration order with strictly increasing
offsets. So: read the global's stored word, sort the class's globals by value, and zip against the
field-record order from `fieldrec`.

Read a global's static value with the same helper `fieldrec` already uses:

    import fieldrec; struct.unpack_from('<Q', img, fieldrec.va2off(<global_va>))[0]

**Validated twice, on independently-known answers, before being used.**

*IOSVideoPlayerView* — 0x1044f0ea8 stores 0x260, and the static field-offset vector puts `title`
(idx 41) at 0x260. `recover_field_offsets` independently names that same global `title` off its
accessor. Two routes, one answer. That is what let me name **0x1044f1000 → 0x2a0 → `promptLabel`**,
the field `showPromptMessage`'s closure tears down and rebuilds — a field with no accessor, no
`vpWvd`, and no trie entry.

*MetalPlayView* — the five globals `recover_field_offsets` already names carry
rotation 0x1c / pixelBuffer 0x20 / options 0x30 / renderSource 0x38 / drawable 0x48, which pins the
value↔index zip. It then predicts the five globals §6 called unnameable, and every prediction is
confirmed by the LOAD WIDTH at its use site in `enterBackground` — a discrimination the mapping
could not have faked:

    0x1044ea8f8 = 0x82 → isBackground (10)                   `strb` 1  — and the method is enterBackground
    0x1044ea928 = 0xa8 → renderUseDispatchSourceTimer (14)   `ldrb`
    0x1044ea8d8 = 0x08 → isPaused (0)                        `ldrb`
    0x1044ea908 = 0xa0 → backgroundTimer (13)                `ldr x` (object)
    0x1044ea8e8 = 0x18 → fps (2)                             `ldr s0` + `fcvt d0,s0` — a 32-bit FLOAT

Three Bools load as bytes, the Float loads as a single-precision register, the timer loads as a
word. The dense-index mapping §6 refuted got `0x1044ea8f8` wrong; this one gets it right and says
`isBackground`, in a method named `enterBackground`.

**Status and caution.** The value→field step is *read*; the ascending-order↔declaration-order step
is an *inference*, justified by Swift's layout rule and corroborated five ways here and twice on
IOSVideoPlayerView. Before leaning on it across the ~74 rows §6 assigned to "per-class field
derivation", it should be a **tool with a golden** anchored on the known answers above
(MEMORY rule 11), not a hand method. But the blocker itself is gone: MetalPlayView's
`enterBackground` / `enterForeground` / `layoutSubviews` are now field-complete, and so is the rest
of that class of row.

## 13. `showPromptMessage` is READ IN FULL. It is blocked on `hidePrompt`, a one-member chain.

Every constant, offset and selector below is read. The body is:

    func showPromptMessage(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            promptLabel.removeFromSuperview()
            promptLabel.text = message
            addSubview(promptLabel)
            promptLabel.translatesAutoresizingMaskIntoConstraints = false
            bringSubviewToFront(promptLabel)
            NSLayoutConstraint.activate([
                promptLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 50),
                promptLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                promptLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.8),
                promptLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            ])
            promptLabel.alpha = 0
            UIView.animate(withDuration: 0.3) {
                promptLabel.transform = .identity
                promptLabel.alpha = 1
            }
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hidePrompt), object: nil)
            perform(#selector(hidePrompt), with: nil, afterDelay: 5)
        }
    }

Provenance for each non-obvious piece:

* the field is `promptLabel` — `name_global_by_value("IOSVideoPlayerView", 0x1044f1000)` → `promptLabel`,
  and the field record gives `So7UILabelC`, a NON-optional `UILabel` already declared at
  IOSVideoPlayerView.swift:129. No optional-chaining anywhere, consistent with that.
* constants are inline immediates: `0x4049000000000000` = **50.0**, `0x4042000000000000` = **36.0**,
  `[0x10347fea8]` = **0.8**, `0x3fd3333333333333` = **0.3**, `movi.2d v0,#0` = alpha **0**,
  `fmov d0,#1.0` = alpha **1**, `fmov d0,#5.0` = **afterDelay 5**.
* `NSLayoutConstraint` is `__objc_classrefs` 0x104410670; `UIView` 0x1044105e8; `NSObject` 0x104410758.
* the four constraints come from selectors `constraintEqualToAnchor:constant:`,
  `constraintEqualToAnchor:`, `constraintLessThanOrEqualToAnchor:multiplier:` and
  `constraintGreaterThanOrEqualToConstant:` in that store order (+0x20/+0x28/+0x30/+0x38 of a
  64-byte 4-element array bridged by `Array._bridgeToObjectiveC`).
* the animation block @0x101b0d630 sets `setTransform:` with an identity matrix — the stack image is
  `(1,0),(0,1),(0,0)` — then `setAlpha: 1.0`. Its own `@MainActor` assertion carries line **1278**.
* the outer closure's assertion carries line **1261**, both against
  `KSPlayer/IOSVideoPlayerView.swift` (literal @0x103d3aad0, 33 bytes).
* ⚑ nothing sets a non-identity transform before the animation, so the `.identity` is a RESET —
  consistent with `hidePrompt` leaving a transform behind.

**The blocker, and it is small.** `#selector(hidePrompt)` needs `hidePrompt` to exist, and it is
not in source. It is not a MEMBER_MISSING row either, because it is a private `@objc` method whose
Swift symbol is unexported — `$s8KSPlayer18IOSVideoPlayerViewC10hidePromptyyF` is NOT IN TRIE, and
`pin_sweep` works off the trie. **`objc_trampoline_oracle --class IOSVideoPlayerView` finds it
anyway**: selector `hidePrompt`, line 1289, imp 0x101b0d9c8 — a 4-instruction `@objc` shim that
passes the file/line context and branches to the shared MainActor-asserting trampoline
0x101b0b460. The real body is **0x101b0d70c, extent 0x101b0d70c-0x101b0d84c, 80 instr**: it builds
TWO blocks and calls a `UIView.animate(withDuration:animations:completion:)` variant, so it is its
own small unit (body + 2 closures).

Land `hidePrompt` first; `showPromptMessage` is then a paste of the block above.

**Reusable lesson:** a private `@objc` method is invisible to `pin_sweep` and to the export trie,
but `objc_trampoline_oracle --class <X>` lists it with its selector, line and imp. Reach for that
whenever a `#selector(...)` or `performSelector:` names something the trie denies.

## 14. `updateVideMetaLabel` — decoded down to its keys, blocked on a 582-instruction prerequisite

`IOSVideoPlayerView.updateVideMetaLabel()` @0x101b11704, 233 instr. Its shape and every literal
are read; what stops it is a second undeclared private method, and this one is not small.

It touches exactly four fields, named by value rather than position —
`name_global_by_value("IOSVideoPlayerView", …)`:

    0x1044f0fa8 → codecLabel      0x1044f0fb0 → resolutionLabel
    0x1044f0fb8 → fpsLabel        0x1044f0fc0 → bitrateLabel

and the four dictionary keys decode from the small-string immediates as
**"Codec Format"**, **"Resolution"**, **"Frame Rate"**, **"Bitrate"** — one per label, in that
pairing order. The body is four repetitions of the same shape: look the key up, and on the
found path `setText:`, on the not-found path `setAlpha:` with `movi.2d v0,#0` (alpha 0). The only
other calls are `String._bridgeToObjectiveC` and the bridge-object retain/release family.

**The blocker.** The dictionary comes from
`IOSVideoPlayerView.(getVideoMeta in _99D4461AEE15ECA71DEBF361B80F60DD)() -> [Swift.String : Swift.String]`
@0x101b11aa8 — private, hence the discriminator, hence absent from source. Unlike `hidePrompt`
(80 instr, landed this session) it is **582 instructions**, extent 0x101b11aa8-0x101b123c0. That is
its own unit and a large one; `updateVideMetaLabel` is a short paste once it exists.

⚑ Note the asymmetry worth checking when someone picks this up: the not-found path sets `alpha = 0`
but nothing in this body sets alpha back to 1, so either `getVideoMeta` always populates all four
keys or the reset lives elsewhere. Read it; do not assume.

## 15. DirectoryWatcher: the bodies EXIST under invented names — this is a rename, not a write

Rule 13 ("audit a body that already exists before you write a new one") pays off here, and the
current source is provably wrong in a way worth recording even before the fix lands.

`DirectoryWatcher.swift` already reconstructs both addresses, but under **self-declared inferred**
names and signatures:

    source (today)                                          binary (read from the trie)
    ─────────────────────────────────────────────────────   ────────────────────────────────────
    startWatching(url:handler:qos:)        @0x101a04e78  →   watchModify(fileURL:completion:)
    startWatchingParent(url:handler:qos:)  @0x101a0578c  →   watchNew(fileURL:completion:)

Three separate corrections, all read rather than inferred:

1. **the names** — `watchModify` / `watchNew`. The source comments say "name inferred" at both
   sites, so this replaces a guess with the trie's answer.
2. **the labels** — `url:` → `fileURL:`, `handler:` → `completion:`.
3. **the arity** — the demangled signatures are
   `(fileURL: Foundation.URL, completion: @Sendable (Swift.Bool) -> ()) -> ()`: **two parameters**.
   Source declares a third, `qos: DispatchQoS`, and its own comment admits it was read off decompiler
   `param_3`. There is no such parameter. The `DispatchQoS` in the body is the argument to
   `DispatchQueue.global(qos:)`, not an input. **That invented parameter is a live divergence in
   the tree right now**, independent of whether the rename lands.

Also note the completion is `(Bool) -> ()`, not the `() -> Void` the source declares.

**What stops the rename landing.** The closures currently stub as `handler()`. Under the real
signature they must pass a `Bool`, and that value is computed inside the event handler, which is
NOT reconstructed: `setEventHandler`'s block @0x101a06254 is an 18-instruction partial-apply
forwarder (it recomputes the URL's size/alignment from the value witness to find the capture
offsets) onto the real body **0x101a05464, 102 instr**, which weak-loads self and goes on into
Foundation calls. `watchNew`'s equivalent is @0x101a06364 → its own body. Writing `completion(true)`
would be inventing a raw value, so it was not written.

Read 0x101a05464 and both rows land together as a rename plus a two-line signature fix.

## 16. A FAILED attempt, recorded: `LimitPreLoadIOContext.shouldContinueRead` and the private field

I landed this row, the ACCESS bucket went 26 → 27, and I reverted it (`86a8262`). The reasoning
that produced it is worth keeping because the trap is reusable.

**What I did.** The row's body @0x101b8a0e0 is 6 instructions and ICF-folded across
`CacheIOContext` / `PreLoadIOContext` / `LimitPreLoadIOContext` — one field's negation,
`bic w0, w9, w8` with `w9 = 1`. `CacheIOContext.shouldContinueRead()` is already declared as
`!_isClosed`. I reasoned: the fold means the subclass's compiled body is byte-identical, so its
source body is also `!_isClosed`, so `_isClosed` must be visible from the subclass's file, so it is
at least `internal`. I widened it and wrote the override.

**Why that is wrong.** `pin_sweep` immediately flagged
`ACCESS CacheIOContext._isClosed — source internal / binary private`: the field's symbol carries a
per-file discriminator `33_<hash>LL`, which is the definitive `private`/`fileprivate` marker. I had
checked only that it emits no `vpWvd` global, which rules out **public** and says nothing about
private-vs-internal. **The discriminator is the private test; the absent vpWvd is not.**

**What that implies about the row itself** — and this is the part that needs adjudicating, because
it contradicts s108 §3. If `_isClosed` really is private, a body in `LimitPreLoadIOContext.swift`
cannot read it, so the subclass's body cannot be the identical `!_isClosed` the fold requires.
Then the symbol at 0x101b8a0e0 under the subclass's name is the INHERITED method surfacing at the
shared address — exactly the `OWNER_MATCH` illusion s108 §3 itself warns about — and the row would
be a false positive after all.

**My evidence was weaker than I stated.** I verified `override_table=True` on the CLASS and treated
it as proof that THIS member is in that table. It is not: the class has other overrides, and no
tool in `scripts/` dumps override-table ENTRIES — `vtable_walk` only reports the flag. Deciding
this row needs a tool that lists the entries, or a different discriminator. Until then it should
stay open rather than be landed on either reading.

## 17. NEW TOOL `override_table.py` — and it settles §16 against me

The §16 failure was a missing tool, so I built it: `play/scripts/override_table.py` lists a class's
override-table ENTRIES, which nothing in `scripts/` could do — `vtable_walk` reports only the
boolean flag. **`play/scripts/` is gitignored, so this lives on one disk**, exactly like s108 §4's
fixes. If it is gone, this section is the spec: the entries follow the vtable's, as
`[OverrideTableHeader {NumEntries}] [NumEntries x {Class, Method, Impl}]`, each field a relative
pointer resolved against its OWN address; `Class`/`Method` are relative-INDIRECTABLE (low bit set =
via a GOT slot), `Impl` is a plain relative direct pointer, and a zero `Impl` is a removed override.
It reads the Mach-O directly through `fieldrec.va2off` — no Ghidra connection — and reuses
`vtable_walk.vtable_header_offset_generic` so the header arithmetic has one owner.

Validated before use, per MEMORY rule 11, and swept per rule 10:

* `--selfcheck` passes: a positive (the table parses, is non-empty, every non-zero Impl lands in
  `__text`, every entry names a base descriptor) plus two negatives — a class with the flag CLEAR
  is **refused** rather than read as an empty table (otherwise "no entries" and "no table" become
  indistinguishable and every override looks inherited), and an unknown class errors.
* Swept over all **1039** classmap rows: 104 parsed, 820 correctly refused (no override table),
  115 refused (no vtable), **0 exceptions and 0 Impls outside `__text`**.

**What it decides.** For `LimitPreLoadIOContext`:

    python3 scripts/override_table.py --class LimitPreLoadIOContext --module PreLoadIOContext --impl 0x101b8a0e0
    YES  index=4

So `shouldContinueRead` IS a genuine override — **s108 §3 was right, and §16's speculation that it
"would be a false positive after all" was wrong.** Both of my readings this session were wrong in
opposite directions; the tool is the thing that settles it.

**Which sharpens the real question.** Two facts are now both PROVEN and they look incompatible:
the override is real (entry index 4, Impl 0x101b8a0e0, ICF-folded onto the base's body), and
`CacheIOContext._isClosed` is `private` (per-file discriminator). A body in another FILE cannot
read a private field — but Swift's `private` is FILE-scoped, so both hold if Forward declares
`CacheIOContext` and `LimitPreLoadIOContext` **in the same file**. This tree splits them across
`CacheIOContext.swift` and `LimitPreLoadIOContext.swift`, and that split — not the access level —
is what makes the override unwritable here.

So this is a PLACEMENT divergence, and [[fileid-literals-decide-placement]] is the right lens for
it. Do not widen `_isClosed` to land the row; either co-locate the two classes or leave the row
open. §16's commit did exactly the wrong one of those and was reverted.

## 18. `OutputStreamInfo.transcode` — the rename is proven, the CASCADE is not. Attempted, reverted.

Another body already present under an inferred name, found by the same sweep as §15. The rename
itself is not in doubt — **this file already carried the answer in its own marker** and the trie
confirms it, method descriptor and all:

    KSPlayer.OutputStreamInfo.transcode(packet: Swift.UnsafeMutablePointer<__C.AVPacket>,
                                        block: ((Swift.UnsafeMutablePointer<__C.AVPacket>) -> ())?)
                                        -> Swift.Int32

Source declares `buildTranscodeContext(_ packet:completion:)` returning `Void`, self-labelled
"name inferred (devirt slot13)". **Five** things differ: the name, the first label, the second
label, the closure's shape, and the return type.

The `Int32` value is READ, not assumed: the body has exactly ONE `ret` (0x101a1accc), no
tail-branch leaves the function, and nine separate branches converge on the epilogue at
0x101a1aca8 whose first instruction is `mov w0, #0x0`. **Every path returns 0.**

**Why it was reverted.** The closure is `((UnsafeMutablePointer<AVPacket>) -> ())?` — an OPTIONAL
closure over a NON-optional pointer. Source has the optionality on the other side, and so does the
downstream `TranscodeProtocol.transcode(_:output:completion:)` this body forwards to
(`(UnsafeMutablePointer<AVPacket>?) -> Void`), which is the same reconstruction error propagated.
Landing the rename therefore requires either an adapter closure at the call site — which invents a
nil-guard the binary does not have — or changing `TranscodeProtocol` and its three conformers
(`Audio`/`BSF`/`Copy`TranscodeContext) on the strength of an inference.

That inference is actually decent: this file's own note records that the compiler inserted only a
reabstraction thunk (FUN_101a1f1a8) and passes the block through rather than constructing one, and
a reabstraction thunk is what you get when the types match modulo abstraction — not when an
Optional is being bridged. **But §16 was landed on reasoning of exactly that quality and was
wrong**, so it was not landed here.

**And the inference cannot be upgraded — I chased both routes and both are closed.**

1. *The protocol descriptor.* `protocol_signature.py`'s own docstring settles it: a requirement's
   method SIGNATURE "is not emitted by Swift", which is precisely why that tool exists (to tell an
   associated type, which IS stored, from a concrete existential, which is not). So
   `TranscodeProtocol.transcode`'s parameter types are irreducible from the protocol.
2. *The conformers.* A witness must match its requirement, so a concrete
   `Copy`/`BSF`/`AudioTranscodeContext.transcode` symbol would give the types outright. A trie
   sweep over all three class names crossed with `transcode` returns **0 symbols** — all three
   implementations are devirtualized and unnamed.

So no *signature lookup* recovers it. **But the body read does, and I did it — the optionality is
now READ, and the two signatures genuinely differ.**

* `conformance_walker --protocols TranscodeProtocol:0x1039eefa0` gives all five conformers and
  their witness tables (3 requirements each). `CopyTranscodeContext`'s substantive witness is
  **0x101a1bee0** (18 instr): copy input→output, `str x8,[x21,#0x48]` with `x8 = -1` (pts =
  AV_NOPTS_VALUE), then **`blr x19` UNCONDITIONALLY**. No nil test — so the WITNESS's `completion`
  is NON-optional, and source's `TranscodeProtocol` is already right.
* `OutputStreamInfo.transcode`'s `block` really is optional, and the check is explicit. The
  completion handed to the witness is NOT the caller's block: `x2 = 0x101a1f1a8` is a 5-instruction
  partial-apply forwarder onto a CONSTRUCTED closure at **0x101a1af90**, and that closure opens
  `cbz x1, …` / `blr x1` on the block's function pointer — an optional closure invoked only when
  present, i.e. `block?(…)`.

⚑ That also **refutes this file's own note** at the call site, which says "the completion is passed
through, not constructed here". A closure IS constructed; 0x101a1af90 is its body.

**What still blocks the rename** is therefore not the optionality but that constructed closure:
0x101a1af90 is **593 instructions**, and `block?(…)` is only its first step. The current source
already simplifies that site to a bare forward, so landing the rename means either keeping that
simplification while changing the signature — which needs an adapter whose shape is not read — or
reconstructing the 593-instruction closure as its own unit. The second is the honest route.

## 19. `getVideoMeta` — the keys and the value sources are read; the pairing is not

`IOSVideoPlayerView.(getVideoMeta in _99D4461AEE15ECA71DEBF361B80F60DD)() -> [String : String]`
@0x101b11aa8, extent 0x101b11aa8-0x101b123c0, **582 instr**. Private, hence the discriminator,
hence absent from source and from the MEMBER_MISSING queue — but it is the sole blocker on
`updateVideMetaLabel` (§14).

**Keys — read from the small-string immediates**, six of them:

    "Codec Format"   "Resolution"   "Frame Rate"   "Bitrate"   "Color Depth"   "Title"

Note §14 showed `updateVideMetaLabel` consuming only the first four; `Color Depth` and `Title` are
built here and read elsewhere (or not at all — do not assume).

**Value-side literals**, also read: `"%.2f"`, `"FPS"`, `"Kbps"` — so at least one value is a
formatted Double and two carry unit suffixes.

**Callees** — 32 calls, only 6 non-stub, which is what makes this tractable despite its size:

    0x1019e76c4  (extension in KSPlayer):__C.CGSize.string.getter : Swift.String
    0x101a0aeac  (extension in KSPlayer):__C.CMFormatDescriptionRef.naturalSize.getter : __C.CGSize
    0x10199fc68  NOT IN TRIE          0x1019c2f60  NOT IN TRIE
    0x100006158  witness-table accessor (glue)   0x10002d984  mangled-name type instantiation (glue)

So **`"Resolution"` = `formatDescription.naturalSize.string`** — the chain is named end to end.
The two NOT_IN_TRIE locals are the remaining unknowns on the value side.

**The pairing is now largely determined — by ORDER in the body, not by plausibility.** Each literal
is located by its small-string constants, so the sequence is read rather than inferred. Note
`0x6f43` is shared by "**Co**dec Format" and "**Co**lor Depth"; they are separated by the second
`movk` (`0x6564` "de" vs `0x6f6c` "lo"), which is why a naive prefix match finds three sites for
two keys.

Materialisation order through the body (line numbers are into the 582-instruction dump):

    L151 Codec Format · L263 Codec Format · L275 Title · L287 Resolution · L325 Title
    L332 Frame Rate · L360 "%.2f" · L367 "FPS" · L373 Bitrate · L402 "Kbps"
    L408 Color Depth · L453 Frame Rate · L482 "%.2f" · L489 "FPS" · L495 Bitrate · L525 "Kbps"

Each key is followed by its own value pieces, which pins four of the six:

* **Codec Format** = `mediaSubType.description` — `CMFormatDescriptionRef.mediaSubType.getter`
  feeding `_CMFormatDescriptionFourCCConvertible.description.getter`.
* **Resolution** = `formatDescription.naturalSize.string` (both getters named).
* **Frame Rate** = `String(format: "%.2f", …)` then `String.append` of `" FPS"`.
* **Bitrate**  = `String(format: "%.2f", …)` then `String.append` of `" Kbps"`.

Frame Rate and Bitrate appear TWICE (L332/L373 and L453/L495), on either side of the Color Depth
block — so there is a branch, and both arms emit those two keys.

**Frame Rate's value is now read in full structure** (0x101b11ff8-0x101b12068):

    __swift_instantiateConcreteTypeFromMangledName -> swift_allocObject(size 0x48, align 7)
    = the CVarArg array; `ldr s0, [x23,#0x40]` (a 32-bit FLOAT) is stored into it at +0x20,
    with the Float's CVarArg witness/metadata from __got 0x104111870 / 0x1041118a8;
    then String.init(format:_:) with "%.2f", then String.append.

⚑ The appended literal is **"FPS"**, count 3 (`w0 = 0x00535046`, discriminator `0xE3`) — **no
leading space**. `"%.2f"` is likewise exactly 4 chars. So the value is
`String(format: "%.2f", x) + "FPS"`, not `" FPS"`. That is the kind of detail that reads as a typo
and gets silently "fixed"; it is what the binary says.

**What still must be read, not guessed:** the OPERAND of each `%.2f` — the Float at `[x23,#0x40]`
and Bitrate's equivalent — plus the values for **Title** and **Color Depth** (Title's key is
materialised twice, at L275 and L325, which is itself unexplained).

**The register trace is done, and the offset coincidence was real after all.** `x25` IS an
`FFmpegAssetTrack` and `x23` IS its `formatDescription` (0xd0) — proven not by the offset but by
what happens next: `x23` is `objc_retain`ed and passed straight to
`CMFormatDescriptionRef.naturalSize.getter` @0x101a0aeac, which only accepts a format description.
It is `cbz`-guarded first, so `formatDescription` is optional. Two independent reads agree, which
is the bar the bare offset match did not meet.

**The literal's layout is read**: the dictionary is built as an array of alternating
key/value strings — key at `+N`, value at `+N+0x10`, one pair every `0x20`. Confirmed on a pair
whose halves are independently known: `"Frame Rate"` is stored at `[x28,#0x60]` and the
`String(format:)`+`append` result is stored at `[x28,#0x70]`.

**There are TWO arrays, one per branch** — stores run `[x27,#0x50…0xd0]` in one and
`[x28,#0x30…0xb0]` in the other, nine `stp` pairs each. One branch supplies the literal
**`"Unknown"`** (`x20/x21` = 0x6e55/0x6e6b/0x776f/0x6e, count 7) as a VALUE, which is the
fallback arm.

**Slot enumeration, done by offset.** Each `stp` writes ONE String (two words), so slots step by
0x10 and a key/value pair spans 0x20. The `x28` array:

    0x20 ?        0x30 "Unknown"    0x40 "Title"      0x50 [x23,#0x20]
    0x60 "Frame Rate"               0x70 the "%.2f"+"FPS" string
    0x80 "Bitrate"                  0x90 the "…Kbps" string
    0xa0 "Color Depth"              0xb0 ?

Keys land on the 0x20 boundaries and values at +0x10, which is self-consistent across the three
pairs whose halves are independently known. The `0x90` slot is written at 0x101b120f8, four bytes
BEFORE "Color Depth" is materialised at 0x101b120fc — that ordering is what places the Kbps string
as Bitrate's value rather than Color Depth's.

**Two cautions, both load-bearing:**

* `x27`'s array opens with `str x8, [x27,#0x20]!` — a PRE-INDEX that also advances `x27` by 0x20.
  Every later `[x27,#N]` is therefore at original `+N+0x20`. Read those offsets shifted or the
  whole second branch comes out misaligned by one slot.
* The two branches are **interleaved in the listing, not sequential**: "Codec Format" is
  materialised at 0x101b11eb8, before any `x28` store, and feeds the `x27` array. So slot contents
  cannot be assigned by reading the dump top-to-bottom; each store must be matched to its own
  branch.

That second point is why the `x28` slots at `0x20` and `0xb0` are left as `?` here rather than
filled in by elimination — and why "Resolution", which is certainly built (both its getters are
named), does not appear in the `x28` list above. It belongs to the other branch. Finishing this
means walking the two branches separately, not completing this table.

## 20. `displayEnumVR` / `displayEnumVRBox` — the recorded blocker VERIFIED, not taken on trust

KSOptions.swift's own note says these two are read but blocked by
`error: main actor-isolated default value in a nonisolated(unsafe) context`, and that the fix
depends on whether `@MainActor` on `SphereDisplayModel` is an over-annotation. Per MEMORY rule 15
I re-checked rather than trusting it, because the getters are only 7 instructions and looked cheap.

The blocker is real. What I confirmed:

* the bodies are the ordinary lazy-static shape — addressor @0x1019bc684 is `swift_once` on token
  0x1044e52b8 returning storage 0x104c632b0; the 7-instruction getter @0x1019bc6c4 tail-calls the
  shared once-then-load helper 0x1000837f0. Nothing exotic; identical in shape to
  `displayEnumPlane`/`displayEnumDovi`, which ARE declared.
* so the difference is purely the initialiser. **Every** `*DisplayModel` class is `@MainActor` in
  this tree — Plane and Dovi included — and those two compile fine. What separates them is that
  Plane and Dovi have no explicit `init`, while `VRDisplayModel`/`VRBoxDisplayModel` declare
  `override required init()`.
* I could not cheaply refute those inits. `vtable_walk` reports **no vtable at all** for either VR
  class (`override_table.py` accordingly answers `no-vtable`), and `export_trie_oracle --class`
  reports **`inits: 0`** for both. But absent-from-the-trie means UNNAMED, not absent (rule 3), and
  an init demonstrably runs: the shared once-init tail does `swift_allocObject` then `blr` an init
  then stores. Both classes also carry stored `let` fields that must be initialised somewhere. So
  the source's `override required init()` is consistent with the binary, and deleting it to unblock
  the statics would be unfounded.

**Conclusion: KSOptions.swift's note is correct as written and these two rows stay blocked.** The
deciding question is unchanged — is `@MainActor` on `SphereDisplayModel` right? — and it is a claim
about a different declaration, needing its own read. Do not re-walk the cheap-getter angle; the
getters were never the problem.

## 21. `MetalSubtitleView.mtkView` — fields all named now; blocked on an 809-instr producer

Early in the session I set this row aside because MetalSubtitleView's fields were unnamed. With
`name_global_by_value` (§12) that is no longer true — **all of them resolve**:

    0x1044ef5a8 metalDrawable   0x1044ef5c0 subtitleImages   0x1044ef5c8 pendingTexts
    0x1044ef5d0 cancellables    0x1044ef5d8 parts            0x1044ef5e0 playRatio

`mtkView(_:drawableSizeWillChange:)` @0x101ac0d48 is a 4-instruction tail-call thunk: it packs the
`CGSize` into (x0,x1), passes `w2 = 0`, and branches to a shared 63-instruction helper
@0x101ac0a90. That helper is now read end to end:

* `w2` selects the size source — `w2 == 1` calls `drawableSize` on self; `w2 == 0` uses the passed
  pair. `mtkView` passes 0, so it uses its `size` argument. (The other caller passes 1.)
* the divisor is `UITraitCollection.current.displayScale` — classref 0x104410730 = `UITraitCollection`,
  selectors `currentTraitCollection` then `displayScale`.
* it reads `parts` and `playRatio`, calls the producer below with
  `(w0 = 1, x1 = parts, d0 = playRatio, d1 = width/scale, d2 = height/scale)`, stores the returned
  PAIR into `subtitleImages` and `pendingTexts`, and finishes with `setNeedsDisplay`.

**The blocker** is that producer: **0x101abc398, 809 instructions**, NOT_IN_TRIE and with no
`#function`. It is not nothing, though — `recover_swift_function_name` recovers its **`#file`**
literal as **`KSPlayer/SubtitlePart.swift`** (27 bytes @0x103d3a3f0), so it is a subtitle
layout/render engine belonging to that file, not to MetalSubtitleView. It returns two arrays in
(x0, x1).

So this row needs that engine reconstructed (or at minimum named) first — and note the helper
@0x101ac0a90 is itself an undeclared private member shared with a second caller, so landing
`mtkView` alone still means declaring the helper.

## 22. `KSAVPlayer.cachedTimeRanges` — guard read, tail outstanding

Getter @0x1019a1244, 76 instr, returning `[KSPlayer.CachedTimeRange]`. The opening guard is read:

* a vtable call on self at metadata `+0x458`. KSAVPlayer's `VTableOffset` is 38 words (0x130), so
  the slot is `(0x458-0x130)/8` = **101**, whose Impl is **0x10002d9d4** — an ICF-folded tiny body
  (the trie name at that address belongs to an unrelated SwiftUI `Namespace` initializer, which is
  the fold, not a mismatch). Result is `cbz`-guarded.
* `__swift_instantiateConcreteTypeFromMangledName` (mangle 0x103566c50) then
  `swift_dynamicCast(..., w4 = 6)` — a CONDITIONAL cast — against the metadata from **0x1019e4db4 =
  type metadata accessor for `KSPlayer.AbstractAVIOContext`**. `tbz` on failure returns the empty
  result.
* then `duration` (offset global **0x104c63070**, named) is read under `swift_beginAccess` and
  `fcmp d8, #0.0` / `b.le` bails when it is not positive.

So the shape is `guard let <slot-101 value> as? AbstractAVIOContext, duration > 0 else { return [] }`.

**Outstanding:** the range-building tail from 0x1019a12e8 — `ldp x19, x21, [sp,#0x40]`, a call to
0x10002abb8, then `ldr x8, [x21,#0x40]` and an indirect call with `v0 = duration`. That is where
the `CachedTimeRange` values are actually produced, and it is unread.

Note this row is NOT the same member as `PreLoadIOContext.cachedTimeRanges(duration:)`, which the
tree already declares — same name, different type, different arity.

## 23. Not started, deliberately

`SubtitlePart.change` (3 overloads @0x101abb3f0 / 0x101abb524 / 0x101abb6c0) — whole-struct
copies guarded on a Bool at +0x81; needs SubtitlePart's full named layout, i.e. §6's problem
again. The `changePlaybackTime` chain and the `SubtitleModel` `Task` closure were left alone:
s108 §6 describes them precisely so that resuming them is a decision rather than a default, and
nothing this session changed that.

---

## §23 — Second half of s109 (post-compaction). MEMBER_MISSING 95 → 86.

State at close: **MEMBER_MISSING 86 · ACCESS 26 · NOT_IN_TRIE 23 · AMBIGUOUS_OVERLOAD 10 ·
TYPE_DIVERGENCE 4**; gate **PASS 44 / ANOMALY 6 / FAIL 4** — identical to the s108 baseline, so
nothing regressed; build 4/4 at every commit; tree clean apart from the pre-existing untracked
`docs/superpowers/specs/*` files. Re-derive all of it with `recon_gate.py --mode handoff` and
`pin_sweep.py --every` rather than quoting these numbers.

### Rows landed
| row | addr | note |
|---|---|---|
| `HLSCacheIOContext.clearCache(for:)` | 0x101b9ad90 | static (no `Tq`); all 28 calls are Foundation/libc stubs |
| `KSOptions.defaultFont` | 0x1019b93a8 | `nil` via `storeEnumTagSinglePayload(dest, 1, 1)` on URL's VWT |
| `KSOptions.recordDir` | 0x1019b598c | documentDirectory urls, `.first?`, `appendingPathComponent("record")` |
| `KSOptions.subtitleDynamicRange` | 0x1019bb404 | `SwiftUI.Image.DynamicRange.high` |
| `KSOptions.translationTarget` | 0x1019ba494 | `Locale.current.language` |
| `KSPlayerLayer.isPictureInPictureActive` | 0x1019d007c | witness 30 then PiP req0, confirmed by selector |
| `KSAVPlayer.configPIP` | 0x1019ab4dc | needed PiP req2 declared as `init?(playerLayer:)` |
| `KSMEPlayer.configPIP` | 0x101a445c8 | needed PiP req3 + `override public required init(contentSource:)` |
| `KSComplexPlayerLayer.pause` | 0x1019d1bc0 | `override` proven by `override_table --impl` (YES index 4) |

### Two corrections to earlier sessions' recorded blockers — both were wrong, and wrong the same way
Both had been written as settled negatives after ONE error message was read and generalised.

1. **PiP req2 was NOT undeclarable.** `KSPictureInPictureController.swift` recorded both init
   requirements as impossible, quoting the `required`-initializer error that `init(contentSource:)`
   produces. req2 fails *differently* — "non-failable initializer requirement cannot be satisfied by
   a failable initializer" — and spelled `init?(playerLayer:)` it builds 4/4. The `?` is
   independently binary-backed: `configPIP`'s `cmp x0,#0` / `csel x21, xzr, x22, eq` rebuilds a nil
   existential, so the failability is readable at the call site.
2. **req3's `required init` IS in the binary.** The same note said declaring it "would put an
   initializer in the source that the binary does not show". The trie carries BOTH entry points —
   `…cfC` allocating @0x1019c74e4 and `…cfc` **initializing** @0x1019c751c — and a purely inherited
   ObjC init emits only the former. The initializing body is `objc_super` + `objc_msgSendSuper2` on
   `initWithContentSource:`, i.e. `super.init(contentSource:)`, which also forces `override`.
   **Generalise the method, not the two results: an "it does not compile" note is only as good as
   the error it quotes, and a per-member re-test is cheap.**

### Tool fix (disk-only — `play/scripts/` is gitignored)
`bind_oracle.py`'s row regex anchored the symbol at end-of-line, so every `(weak_import)` row failed
to match and was **dropped in silence**; `--addr` then answered "NO BIND at this address (not a bind
site)" for addresses that are plainly binds — the exact shape that invites a false "unreadable" pin.
Making the suffix optional recovers **377 rows**, with **0 existing rows changed and 0 lost**, and
`--selfcheck` passes. It was found because `subtitleDynamicRange`'s value is the weak-imported
`SwiftUI.Image.DynamicRange.high`; the chained-fixup word at that `__got` slot decodes to bind
ordinal 0x10d2, one past its neighbour, which is what proved the miss was the parser's.
⚠️ If `scripts/` is ever restored from a backup, re-apply this.

### Still blocked, with the escape routes now MEASURED rather than guessed
- **`KSOptions.displayEnumVR` / `displayEnumVRBox`** — values fully read since s106. Dropping
  `@MainActor` from `SphereDisplayModel` builds 4/4 but changes nothing (the isolation comes from
  the `DisplayEnum` protocol); marking both `override required init()` `nonisolated` just moves the
  error onto `KSOptions.sceneSize` and `super.init()`. Landing two read values would cost three
  isolation edits that `PlayerDefines.swift:179` already states are not binary-derived. Left blocked.
- **`MetalSubtitleView.mtkView(_:drawableSizeWillChange:)`** @0x101ac0a90 — blocked on typing the
  private layout helper @0x101abc398 (not in the trie). The field-offset map is now recorded in
  `MetalSubtitleView.swift`; `{0x5c0, 0x5c8, 0x5d8}` → `{subtitleImages, pendingTexts, parts}` stays
  open. **Do not guess those three from field order** — see below.
- **`KSComplexPlayerLayer.pictureInPictureControllerDidStopPictureInPicture`** @0x1019d62ec — read
  end to end except the 227-instruction tail call at 0x1019d2bb0, which is not in the trie and is its
  own unit. The rest is: `player.view` (witness 0x28) sent `didStopPIP`, then the private
  `KSPlayerLayer.addSubtitle(to:)` @0x1019cf5d8, then `pipController?.stop(restoreUserInterface: false)`.

### The trap worth carrying forward: offset globals are NOT in field-record order
Hit twice, in two unrelated classes, and it silently produces a plausible wrong map.
`MetalSubtitleView` has seven fields whose offsets ascend (0x8, 0x30, 0x38, 0x40, 0x48, 0x50, 0x58)
and seven offset globals whose addresses ascend (0x1044ef5a8…5e0) — and pairing them is WRONG:
0x5d0 is `cancellables`, proved by its init store of `__got 0x104112d10`
(`__swiftEmptySetSingleton`, adjacent to the array singleton at 0xd00 and the dictionary one at
0xd08). `KSComplexPlayerLayer` is the same: `urls` is trie-pinned at 0x104c63528, the *middle* of
its three globals. **Identify a field by what is stored into it — store WIDTH (`strb` ⇒ Bool),
the empty-collection singleton, an immediate like 0x3ff0000000000000 ⇒ 1.0 — or by the type of the
parameter it feeds. Never by position.** That is how `KSComplexPlayerLayer.pause`'s
`isPictureInPictureStoped` and `MetalSubtitleView.playRatio` were pinned, and why the three
MetalSubtitleView arrays are still open: nothing distinguishes three same-typed empty arrays.

### Next-up rows, already scouted (start here rather than re-triaging)
- **`KSVideoPlayer.Coordinator.isRecord`** — an `@Published public var Bool` on a class whose
  siblings `isMuted` / `isScaleAspectFill` are already declared in exactly that form, so the
  declaration is a one-liner. What blocks it is the `didSet`: it emits NO `vw` symbol (neither does
  `isMuted`, which demonstrably has one — `@Published` observers inline into the setter), and the
  setter @0x1019d9488 tail-calls it at **0x1019d8d28 with the old value in x0**. That body is **412
  instructions** — recording start/stop — so it is its own unit. Do not declare the property with a
  missing or invented `didSet`.
- **`MetalPlayView.enterBackground`** @0x101a6095c (93 instr) — needs four MetalPlayView offset
  globals named (0x1044ea8f8 Bool, 0x1044ea928, 0x1044ea8d8, 0x1044ea908); apply the
  identify-by-stored-value rule above, not ordering.
- **`CacheIOContext.clearOtherCache`** @0x101b8d948 (175 instr, 25 calls, none in-module) and
  **`KSOptions.wantedSubtitle`** @0x1019bb974 (175 instr, 11 calls) are the two largest rows whose
  callees are ALL stubs — i.e. big but not devirtualised, the same profile that made `clearCache`
  tractable.

### How the tractable rows were found
`member_missing_triage.py --json`, then for each body disassemble its extent and count `bl` targets
below 0x103451708 (the stub/thunk island floor). Rows with **zero in-module callees** are the ones
that read end-to-end without chasing devirtualised helpers; that ranking picked out `clearCache`,
the four KSOptions statics, both `configPIP`s and `syncPlaybackPosition`. Beware: the triage's
instruction count is the THUNK's, not the body's — five rows that looked like 1-4 instructions were
thunks branching to 107-, 181- and 227-instruction bodies.


---

## §24 — s109 close. MEMBER_MISSING 108 → 80.

Gate **PASS 44 / ANOMALY 6 / FAIL 4** throughout — identical to the s108 baseline, nothing regressed.
Build 4/4 at every commit. Re-derive with `recon_gate.py --mode handoff` and `pin_sweep.py --every`.

### ⚠️ READ THIS FIRST: an UNCOMMITTED sibling-repo edit is load-bearing for five landed rows
`FFmpegKit/Sources/FFmpegKit/include/avformat_shim.h` now declares two internal libavformat
prototypes:

    int64_t ffurl_seek2(void *urlcontext, int64_t pos, int whence);   // url.h:207
    int ffurl_closep(URLContext **h);                                 // url.h:234, AFTER the URLContext typedef

Without them `URLContextDownload.fileSize/seek/close` and `HLSCacheIOContext.fileSize/seek` do not
compile. **That edit is NOT committed**: the FFmpegKit tree carries unrelated uncommitted work
(BuildFFMPEG.swift, avutil_shim.h, several xcframework Info.plists), so committing it would have
swept in someone else's changes. If a clean checkout of FFmpegKit ever replaces that tree, re-apply
both prototypes or those five members stop building.

The shim is the right home for them, not a workaround: `ff_isom_write_vpcc` already sits there for
exactly the same reason (with `//#import <Libavformat/vpcc.h>` commented out beside it), the file
already declares `URLContext` and `ffurl_context_class` for these very sources, and it still carries
a commented-out `//#import <Libavformat/url.h>`. The built Libavformat.framework exports only
avformat/avio/config/os_support/version, which is why the internal header cannot simply be imported.

### Naming an FFmpeg call the oracle cannot narrow
`ffmpeg_name_oracle` returns 59 band candidates for 0x1030c07ac and does NOT include `ffurl_seek`.
That is not a dead end and not a licence to guess — the answer came from three independent places:
1. **This build's own headers.** `libavformat/url.h` defines `ffurl_seek` as a `static inline` that
   only does `return ffurl_seek2(h, pos, whence)`, so it can never survive as a call target; the
   exported symbol is `ffurl_seek2`, whose signature takes `void *`, not `URLContext *`.
2. **A literal inside the binary.** The log string this reconstruction already reads at
   LimitSeparatePreLoadIOContext contains `"more ffurl_seek2 "`.
3. **The call shape.** pos 0 with whence 0x10000 = `AVSEEK_SIZE` (avio.h:468 in this build).
For `close`, the one/two-star ambiguity between `ffurl_close` and `ffurl_closep` is settled by the
ACCESS FLAGS, not by preference: the body opens a second `swift_beginAccess` with flags 0x21
(Modify|Tracking) closed by `swift_endAccess`, and passes `x20+0x18` — the ADDRESS of `context`.
Only the two-star form takes that and nils the caller's pointer.

### Rows landed in the second half
`HLSCacheIOContext.clearCache` · `KSOptions.defaultFont / recordDir / subtitleDynamicRange /
translationTarget` · `KSPlayerLayer.isPictureInPictureActive` · `KSAVPlayer.configPIP` ·
`KSMEPlayer.configPIP` · `KSComplexPlayerLayer.pause` · `LimitPreLoadIOContext.syncPlaybackPosition`
· `URLContextDownload.fileSize / seek / close` · `HLSCacheIOContext.fileSize / seek`.

### Read in full, deliberately NOT declared
- **`CacheIOContext.clearOtherCache`** @0x101b8d948 — transcribed into the source file. Blocked on
  `tmpURL`, whose type is now DERIVED (its `vpWvd` has no `Sg` ⇒ non-optional `URL`, and the source's
  `URL?` was the old inference). Correcting it builds with exactly one error — not initialized at
  `super.init` — and the satisfying value is written by a virtual call at 0x101b8745c inside the
  init's UNRESOLVED region. Do not spell it `URL!`.
- **`ReadCacheIOContext.close`** @0x101bad688 (42 instr) — next in line, needs the weak-reference
  load at 0x10002e588 and the outlined helpers 0x10002abb8 / 0x100012a78 / 0x10003751c typed first.
  Its four siblings are 134–576 instructions and are the cache logic, NOT ffurl delegations.


### §24b — the structural unblocks, which matter more than the row count
Three blockers that had been recorded as settled were re-tested and fell. Each unblocked members
that had been parked for sessions, and the pattern is the same every time: **the note quoted one
symptom and generalised it.**

1. **PiP req2** — `init?(playerLayer:)`. The note predicted a `required`-initializer error; the real
   error is failability, and the binary's own `csel` on the call result says the same.
2. **PiP req3** — `required init(contentSource:)`. The note said the binary "does not show" the
   initializer; the trie carries BOTH `…cfC` (allocating) and `…cfc` (initializing) entry points,
   and a purely inherited ObjC init emits only the former.
3. **`DownloadProtocol`'s eight "deferred residue" requirements** — all eight named in one pass, and
   the technique generalises: read each witness thunk, and it either touches a field offset directly
   (giving you get/set/modify vs a bare `let` read — the ABSENCE of a `swift_beginAccess` is what
   proves `let`) or dispatches `[metadata + N]`, which `vtable_walk --metadata-offset N` turns into
   a slot and an impl. Corroborate the slot→member mapping with the IMPLS, not just the ordering:
   here slots 6 and 8 share 0x10000e52c because `seek` returns its already-in-x0 `offset` and
   `close` is empty, and ICF folds only byte-identical bodies.

**Do this before declaring any row blocked by an empty/partial protocol.** `DownloadProtocol`,
`KSPictureInPictureProtocol` and `VideoOutput` all had unnamed requirements standing between a read
body and a declaration.

### Where the remaining 79 actually are
The cheap rows are gone. What is left is dominated by:
- **large engine bodies** — `CacheIOContext` alone has 162/175/284/412/413/433/789/1638-instruction
  rows; `ReadCacheIOContext` has 134–576; `KSComplexPlayerLayer` has 12 rows including a
  227-instruction helper that `pictureInPictureControllerDidStopPictureInPicture` depends on.
- **type divergences that gate a body** — `CacheIOContext.tmpURL` (non-optional per its `vpWvd`,
  but its initializer is in the init's UNRESOLVED region) blocks `clearOtherCache`, which is
  otherwise read in full and transcribed into the source.
- **non-binary-derived isolation** — `displayEnumVR`/`displayEnumVRBox`, where both escape routes
  are measured and recorded in this file.
- **one field-identity gap** — `MetalSubtitleView`'s three same-typed array fields.
Reaching 0 runs through those, not around them.
