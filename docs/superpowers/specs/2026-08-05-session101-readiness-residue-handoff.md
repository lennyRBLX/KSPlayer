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

## 3. The 22 remaining COMPUTED_ACCESSOR blocks — measured, do not re-derive

Read `reconstruction/S100_FINDING_makePipelineState_divergence.md` and
`reconstruction/S100_FINDING_published_accessor_blockers.md` first. The decomposition:

- **4 bodies** behind two blockers held ONLY by dim 1b's `_genuine_work == 0` threshold
  (`0x1019d98dc` scores 1, `0x1019def64` scores 2; neither has a blocking callee or an indirect
  site). Both are `Combine.Published` accessors that call `_swift_getKeyPath` twice — which is the
  case `topo_readiness`'s s42 block excludes BY NAME, on the grounds that "a false-accessor would
  DROP real work — never acceptable". **Lifting these reverses that decision. It is a human call,
  and relaxing the threshold to `<= 2` is NOT the way to do it.**
- **1 body** behind devirtualisation. `vtable_walk KSAVPlayer --metadata-offset 0x458` resolves to
  slot 101 `impl=0x10002d9d4`, which already classifies `callable` — but the other indirect sites
  are stored function pointers in object fields (`ldr x8,[x21,#0x40]`, `ldr x8,[x23,#0x8]`), not
  vtable dispatches, and `_indirect_all_witness` requires EVERY site to be glue. Net payoff at most
  1 body against receiver-class inference plus the subclass-override question. Sized, not built.
- **~17 bodies** each behind a SOURCE blocker gating exactly 1. These need real reconstruction.

**Cost, measured on two units, not estimated.** `makePipelineState` was the outlier and it is
spent. The next most tractable, `DynamicInfo.init(displayFPSBlock:accessLogEvent:)` @`0x1019df2f0`
(slot 35, 110 instr), has NO source counterpart and expands into a cluster: its `metadataBlock`
closure `FUN_1019df4a8` is a 3-instruction adapter into an unnamed 68-instruction helper
`0x1019c2f60`, and `FUN_1019e0e38` is a 2-instruction adapter into another unnamed body
`0x1019df4b4`. Writing that init faithfully means characterising those first. `MediaPlayerProtocol.swift`
already documents slot 35 as CONFIRMED-but-deferred and its s34 sibling verdict names it a
prerequisite-linked unit — that groundwork is real, the closure cluster is what remains.


## 3.5 ⭐ NEW ORACLE — chained-fixup binds are readable (`scripts/bind_oracle.py`)

The project had been treating dyld chained-fixup binds as unreadable. That was wrong, and it cost
real deferrals. `bind_oracle.py` walks the bind table (**39,899 sites**, cached at
`reconstruction/bind_table.txt`) and resolves any `__got` slot, ObjC classref or import to its
symbol. The belief came from `dyld_info` crashing on this image — a bug in that ONE reader, not a
property of the binary.

Session 99 deferred six classrefs in `S99_DERIVED_IOSVideoPlayerView.md` as "chained-fixup BINDs,
so the class name is not readable by chasing the pointer" (idx131, idx140). **All six resolve on
the first try** — UIImage, UIImageSymbolConfiguration, UIStackView, UIImageView,
UITapGestureRecognizer, UISwipeGestureRecognizer — and they are now the tool's positive goldens.

**Action for session 101:** re-check every pre-s100 deferral of the form "classref / __got /
import is a chained-fixup bind, not readable". They are all suspect. Memory:
`chained-fixup-binds-are-readable`.

It already discharged one blocker in §3: `__got 0x104112d00` binds `__swiftEmptyArrayStorage` and
`0x104112d08` binds `__swiftEmptyDictionarySingleton`, which together ESTABLISH (no longer infer)
that `DynamicInfo`'s `metadataBlock` closure returns `[:]`.

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
