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

## 8. Not started, deliberately

`SubtitlePart.change` (3 overloads @0x101abb3f0 / 0x101abb524 / 0x101abb6c0) — whole-struct
copies guarded on a Bool at +0x81; needs SubtitlePart's full named layout, i.e. §6's problem
again. The `changePlaybackTime` chain and the `SubtitleModel` `Task` closure were left alone:
s108 §6 describes them precisely so that resuming them is a decision rather than a default, and
nothing this session changed that.
