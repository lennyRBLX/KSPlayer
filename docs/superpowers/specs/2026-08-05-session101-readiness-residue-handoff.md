# Session 101 work

You are the ORCHESTRATOR. Agents derive; you alone adjudicate, edit source, build and commit.

Session 100 attacked the READINESS MODEL rather than the body queue, and found that most of what
was "blocked" was the model mis-measuring. INIT_THUNK went 27 blocked → 0 and COMPUTED_ACCESSOR
52 → 22 with only ONE body actually reconstructed. That vein is now mined out: every remaining
block was measured and is genuine. Read §3 before you look for another shortcut — I looked four
times and the binary refused each one.

## Verify first

1. Run `python3 scripts/recon_gate.py --mode handoff` — expect **PASS 50 / ANOMALY 0 / FAIL 3**.
   The three FAILs (`agg_critical` 7, `agg_high` 19, `agg_unresolved` 1) are session-98 fix-queue
   debt and are NOT a session-101 target unless the human says so.
2. Run `python3 scripts/recon_progress.py`. ⚠️ **Its WORK BUCKETS and KNOWN DEBT lines are stale by
   construction** — see §4.1. Do not plan from them.
3. Re-derive every wave quantity with `python3 scripts/contract_numbers.py --group state`. The
   wave → presence → contract chain was regenerated at the end of s100 in the documented order.
4. Read `MEMORY.md`, then `reconstruction/STANDUP_PROTOCOL.md` and
   `reconstruction/DISPATCH_CONTRACT_s64.md`.
5. Read the `captured_session100` block in `reconstruction/handoff_baseline.json`, then the two
   finding documents in §3.

## 1. What session 100 changed

**Floor 328 → 329.** One body reconstructed and landed: commit `ffa63fc` on `forward`,
`MetalRender.makePipelineState`. Forward takes `(vertexFunction: String, fragmentFunction: String,
bitDepth: Int32)` — two Strings, no `isSphere: Bool` — and builds the `MTLVertexDescriptor` only
when the vertex function is `"mapSphereTexture"`, where the old source built it unconditionally.
10 call sites in `DisplayModel.swift` updated, `validate_build.sh all` 4/4, audited FAITHFUL. That
single unit unblocked 13 bodies.

**Three new golden-gated dims in `scripts/topo_readiness.py`.** Each fixes the same shape of bug —
a rule that existed but was applied to callees only, or not wired at all:

- **dim 5** — a positively-identified `ALLOCATING_THUNK` is compiler-emitted, so it is neither a
  leaf nor blocked. `classify_shape` called these "substantive" because their callee list contains
  the init they delegate to.
- **dim 6** — a `HELPER`-classified callee is `callable`. `classify_compiler_helpers.py` has said
  since s58 that these "falsely gate 461 blocked bodies", and `topo_readiness.py` had **never read
  `universe_classification_s58b.json`**. Only a positive HELPER lifts; SOURCE and UNSURE keep
  blocking.
- **dim 7** — the value-witness recognizer `_indirect_all_witness` was wired into `_v2_decide`
  only, i.e. when judging a CALLEE. A body whose every `blr` is value-witness glue blocked itself
  while the identical body, seen as somebody else's callee, was `callable`.

**A latent false-ready closed.** `_indirect_all_witness` returned `True` *vacuously* for a body
that parsed to zero instructions, despite its docstring promising "fetch-fail => False". Harmless
while its only caller pre-guarded on a cached count; a false READY once dim 7 called it for the
body itself. Now returns False on no parsed instructions and on no indirect site seen.

**INIT_THUNK 27 blocked → 0, and the bucket was 40% misfiled.** `classify_accessor_slots` assigned
INIT_THUNK from the vtable descriptor kind ALONE and then asserted a body shape the descriptor does
not carry. Re-screening all 42 kind-1 slots with `init_thunk_probe.py` (the s62 fix; the re-screen
the stage ledger asked for had never been run) shows 17 are not plain thunks — up to
`CacheIOContext.init` at 836 instructions. Those 17 are re-filed to REAL_METHOD, where **6 remain
blocked and visibly counted**; nothing was hidden. Per-slot record:
`reconstruction/init_slot_rescreen_s100.json`.

## 2. Two goldens had rotted, silently

Both were green-looking and wrong, and both are now property-based:

- `topo_readiness`'s `_STALE_V1_REPORT` fixture pointed at the tool's own default `--out`, so the
  first full v2 run overwrote the "stale v1" fixture and the provenance control went red while the
  guard it tested was correct.
- The dim 6 UNSURE control named specific addresses, which were then re-adjudicated — rotting the
  control I had just written.

Memory written: `golden-anchored-on-mutable-path-rots`. **Before writing any golden, ask whether a
run of the tool can change its own fixture, and whether the control enters through the same door
production does.** The dim 5 control originally passed a SYNTHETIC callee list and so never
exercised the prefilter it existed to cover — which is how an `objc_allocWithZone` miss got past
it; caught only by reading the instructions.

## 3. The 17 remaining COMPUTED_ACCESSOR blocks — every blocker READ, do not re-derive

Session 100 ended at **17** (from 52). Findings:
`S100_FINDING_makePipelineState_divergence.md`, `S100_FINDING_published_accessor_blockers.md`,
`S100_FINDING_playerview_playerLayer_didset.md`.

**THE SCREEN IS DONE.** Every one of the blockers was read, not sized. The result is a clean size
split, and it is why four "the structural vein is exhausted" calls during the session were wrong:

- **<= 32 instructions => compiler glue or a misclassification.** All now cleared:
  `0x101abff3c` / `0x101ac0004` (20 each, outlined value-witness copy/assign — dim 8),
  `0x101b15cc4` (8, released by dim 8), `0x1019b6d54` (26, a SHARED OUTLINED SETTER taking the
  field offset as a pointer-to-global and the observer as a function pointer — hand-adjudicated
  SOURCE -> HELPER, releasing KSOptions#100 and #103).
- **>= 82 instructions => a genuine body.** Spot-checked at the boundary: `0x101b2e124` (82) reads
  `VideoPlayerView.isMaskShow` and builds animation blocks; `0x101b13374` (72) is a
  `CustomProgressView` initializer wiring itself from a `PlayerView`'s toolBar;
  `0x1019d5978` (32) is `KSPlayerLayer.player`'s outlined setter with a REAL didSet body
  (`FUN_1019c925c`) behind it — one caller, offset baked in, so unlike `0x1019b6d54` it is genuine.

So the remaining tail is real reconstruction, and the cheap screens are spent.

**The 17 decompose as:**

- **4** behind the two `Combine.Published` keypath accessors (`0x1019d98dc` gw=1, `0x1019def64`
  gw=2; no blocking callee, no indirect). Held ONLY by dim 1b's `_genuine_work == 0` threshold.
  Lifting them reverses the s42 keypath exclusion BY NAME — a human call. dim 8's negatives assert
  they still block, so that guard is provably intact.
- **2** (`KSAVPlayer#45`, `#59`) behind indirect dispatch. Devirtualisation pays **ZERO** here —
  both carry a non-vtable site (`ldr x8,[x21,#0x40]`, `ldr x8,[x27,#0x8]`) and
  `_indirect_all_witness` requires every site to be glue. Sized twice, corrected once. Do not build it.
- **11** behind one blocker each, 82-364 instructions, all read and all genuine.

### ⭐ SOME BLOCKERS ARE ALREADY FAITHFUL AND MERELY UNVERDICTED

The most useful discovery of the tail. `VideoPlayerView.isMaskShow`'s didSet (`0x101b2e124`, 82
instr) needed **NO SOURCE CHANGE** — the reconstruction already matched Forward. It was blocked
purely because it carried no FAITHFUL verdict, which is what `topo_readiness` requires to admit a
callee to its DONE set. Audited and adjudicated; floor 331 -> 332.

That reverses the working assumption. The first three units all needed rewrites, so the tail was
being costed as "16 rewrite-then-audit units". It is not: **an unknown fraction is audit-only**,
which is far cheaper per body. Try the audit first on every remaining blocker whose class has
source, and only reach for a rewrite when the comparison actually fails.

Method note from that unit: check a ternary as a TRUTH TABLE, not by reading the decompile's branch
order. `alpha` verified as isMaskShow=false -> 0.0, true+selected -> 0.0, true+unselected -> 1.0,
which is `isMaskShow && !isLock ? 1.0 : 0.0`; and `isLock` is `{ lockButton.isSelected }` at :91,
INLINED, not diverged.

### Partial, for whoever takes `KSAVPlayer#78`

`0x1019a24a8` (128 instr) is `playbackState`'s didSet (KSAVPlayer.swift:230-239). Structure matches
— `if playbackState != oldValue { ...; if playbackState == .finished (raw 4) { ... } }`. The OPEN
question is the middle call: source calls `playOrPause()` directly, the binary calls
`FUN_1019a26a8(FUN_1019b293c, FUN_1019b2c64, &DAT_1041d4280, &DAT_1035671a8)` — two function
pointers plus metadata, with a `MainActor` cast and a `TaskPriority` local. Establish whether that
is a compiler-emitted actor hop (because `playOrPause` is `@MainActor`) or a real divergence
BEFORE writing a verdict either way.

## 3.5 ⭐ NEW ORACLE — `scripts/bind_oracle.py`, and the BIND vs REBASE distinction

A chained fixup is one of two things, and they need different reads:

- **BIND** — an external import (a UIKit class, a libswiftCore singleton). `bind_oracle.py --addr
  <a>` names it from the Mach-O bind table (**39,899 sites**, cached at
  `reconstruction/bind_table.txt`). Golden-gated on 8 positives + 2 negatives.
- **REBASE** — an internal pointer. It has NO bind row; you must apply the fixup chain. Session 92
  did this correctly for `__got 0x1041079e8` -> `0x1039ee4c4` -> protocol descriptor -> `Name`
  rel32 -> `'KSSliderDelegate'` (verdict `KSSlider_idx15_slot30_s92`).

**A miss from bind_oracle therefore means REBASE — go apply the chain. It never means unreadable.**

⚠️ An earlier draft of this section claimed the project had been treating the bind table as
unavailable. That was WRONG and is corrected here: s92 used `--macho --bind` correctly. What was
actually missing was applying it systematically to ObjC classrefs — `S99_DERIVED_IOSVideoPlayerView`
idx131/idx140 pinned six as "not readable by chasing the pointer", and all six are plain BINDs that
resolve immediately (UIImage, UIImageSymbolConfiguration, UIStackView, UIImageView,
UITapGestureRecognizer, UISwipeGestureRecognizer). They are now the tool's positive goldens.

It also discharged a live blocker in §3: `__got 0x104112d00` binds `__swiftEmptyArrayStorage` and
`0x104112d08` binds `__swiftEmptyDictionarySingleton`, which together ESTABLISH that `DynamicInfo`'s
`metadataBlock` closure returns `[:]` — the fact that let the slot-35 init be written.

**The sweep is DONE — do not redo it.** Every chained-fixup deferral in `reconstruction/*.md` and
`reconstruction/verdicts/*.json` was extracted and run through the oracle. Result: the six
`S99_DERIVED_IOSVideoPlayerView` classrefs resolve (they are BINDs), `0x104108738` in
`FormatContext_subtitleAssetTrackMap` resolves to `AVFoundation _AVMediaTypeSubtitle`, and the rest
— `0x101a7448c`, `0x1039893c0`, `0x103999f20`, `0x1039ee4c4`, `0x1035696a0`, `0x1041079e8`,
`0x1039efb30` — are **NOT bind sites**. They are REBASEs, which is precisely why s92 had to apply
the chain by hand. That is the corrected distinction above, confirmed empirically.

## 4. Open defects

1. **`classify_accessor_slots` drops bodies silently.** It extracts class+slot from a free-text
   readiness id with one regex (`^([A-Za-z_]\w*)#slot(\d+)$`), and the id format has drifted
   (`Class_slotNN_addr`, plus 539 other shapes). A fresh run recognises **443 of 1102** pool entries
   where the s60 run recognised 716 — **273 bodies vanish with no warning**, which is why a re-run
   reports REAL_METHOD 10 instead of 234. **Do not trust a freshly generated `accessor_slots`
   artifact until this is fixed.** Fix by resolving class+slot from the ADDRESS via the classmap,
   and make any unresolvable pool entry a loud count. Anchor a golden on both id spellings.
   Everything in this handoff was measured address-keyed and is unaffected.
2. **`recon_progress.py` reads frozen artifacts.** Its WORK BUCKETS come from
   `accessor_slots_s60b.json` (2026-07-27) and its `new-class stand-ups` debt line from
   `class_presence_s59.json` (2026-07-27). Neither reflects session 99's 92 STOOD_UP verdicts or
   any of session 100. It will still tell you "INIT_THUNK 42 total / 15 ready" and "all 42 slots
   need RE-SCREENING". Both are false; the re-screen is done (§1).
3. **`method_source_presence` accepts a `bl` as a selector anchor.** `_calls_within` masks B and BL
   together by design, so `SettingsView` idx205 `0x101b265c8` is named `tabButtonTapped` when the
   IMP merely CALLS it (`bl` at `0x101b260bc`, with two further calls and the epilogue after). The
   presence split reads 33 BINARY_ONLY / 42 UNNAMED; corrected it is 32 / 43. Blast radius is
   exactly 1 unit in the current wave.
4. `field_offset_vector.py:94` omits Swift's `AA` module-backreference; `decode_string_literal.py
   --addr 0x101b1d474` aborts on an out-of-image read; `fieldrec.py` and `dump_field_bindings.py`
   disagree on IOSVideoPlayerView's field count (65 vs 63). All three carried over from s99.

## 5. Durability

`reconstruction/` and `scripts/` are both gitignored in `play`. The three new dims, the soundness
fix, the two golden repairs, `universe_classification_s100_additions.json` (41 classified
addresses, 5 hand-adjudicated with per-row evidence), `init_slot_rescreen_s100.json`, both finding
documents and the 2,174 cached decompiles live on this disk only. The source change and this
handoff are committed on `forward`.
