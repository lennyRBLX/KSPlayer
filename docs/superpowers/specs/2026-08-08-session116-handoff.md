# Session 116 handoff — 5 commits, 4 verdicts closed, and a concurrency hazard

Take state from `python3 scripts/recon_gate.py --mode handoff`, never from this file. The numbers
below are what I measured at the end of s116; re-derive them.

|                | takeover | end of s116 |
|----------------|----------|-------------|
| CRITICAL       | 6        | 6           |
| HIGH           | 24       | **20**      |
| MED            | 17       | **16**      |
| LOW            | 13       | **12**      |
| UNRESOLVED     | 1        | 1           |
| faithful floor | 356      | **360**     |

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
- ⚠️ I did NOT finish verifying the delegate dance at 0x1019fe2e4-0x1019fe358 myself. Read it
  before writing: `tbz w25,#0` skips a `delegate = self` block when the URLs are UNEQUAL, and the
  common path then sets delegate = nil, calls set, and sets delegate = self again. That ordering
  looks redundant and must be confirmed, not assumed.

**`IOSVideoPlayerView.updateUI(isLandscape:)` @0x101b08f3c** (2 HIGH + 1 LOW) — best-positioned
remaining target. 0x101b08f3c-0x101b09494, 1368 B, 342 instr. **All eight constraint properties
already exist** at IOSVideoPlayerView.swift:144-151, so nothing is blocked on a stand-up. Structure
mapped: 23 sends to the `setConstant:` stub 0x103468ea0, each guarded by its own `cbz x0` (the
constraints are Optional); two arms split at `tbz w0,#0` @0x101b08f7c and `tbz w19,#0` @0x101b091b4
(w19 = isLandscape). What remains is reading the 23 constants and pairing each with its constraint.

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
