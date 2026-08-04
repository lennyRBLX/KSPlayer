# Session 106 work

**Goal, unchanged from s105: drive MEMBER_MISSING to 0.** It is the dominant term in the
`Correctness sweep` stage and closing it closes the stage.

**Do NOT open this the way s105 did.** That session verified state, triaged the whole queue, then
picked the cheapest individual row anywhere in the corpus and repeated. That worked while a cheap
seam existed and is now exhausted — the median body was 16 instructions at s105 open and is 30 at
s105 close. Row-at-a-time cherry-picking now pays the per-class setup cost (field offsets, witness
tables, callee naming) once per ROW instead of once per CLASS, and it leaves the two structural
blockers untouched. §1 and §2 below are the different opening.

⚠️ **The filename date is not the session order.** Order by session number.

## Verify first

1. `python3 scripts/recon_gate.py --mode handoff`. Expect FAILs on `agg_critical`, `agg_high`,
   `agg_unresolved` (the standing fix queue) and `sc_wave_worklist` (the s104 design question in
   the s105 handoff §4.1 — still unanswered, still not rot). `handoff_baseline.json` has NOT been
   refreshed since s86, so the `agg_faithful` / `agg_stood_up` / wave-size / git anomalies are
   expected. Do not refresh it without the human.
2. `python3 scripts/pin_sweep.py --every` — expect **MEMBER_MISSING 223**. Re-derive; do not quote
   this number onward.
3. `python3 scripts/member_missing_triage.py --sweep <the --json you just wrote>` — the queue split
   by COST. This tool is new in s105 and is the thing to plan from.
4. `git -C <KSPlayer> status --porcelain` — expect the SAME three modified files s105 was handed
   and never touched. They are §1.
5. Read `MEMORY.md`, `reconstruction/STANDUP_PROTOCOL.md`, `reconstruction/DISPATCH_CONTRACT_s64.md`.
6. Read `reconstruction/metalplayview_field_types_s105.md` — a fully-scoped unit waiting to be run.

## 1. ⛔ START HERE — the human's §2 decision gates 44 rows, a fifth of the queue

s104 left three files modified and uncommitted; s105 was told to leave them alone and did, for 34
commits. They are still there. The blocker is unchanged: `isConvertNALSize` on `FFmpegAssetTrack`
is a source-only stored `let`, absent from the reflection field records AND from the export trie,
and the pre-commit `l2_field_gate` names it. It is the human's M1 call — land the two fixes via
`bash scripts/commit_unit.sh --deferral <file>` naming it, or drop the field and its use site in
`VideoToolboxDecode.swift`.

**What s105 learned that the s105 handoff did not say:** those three files are not just a dirty
tree, they are a *queue blocker*. Editing a file that carries staged content means a pathspec
commit would sweep the human's in-flight change in with yours. Four types live in them:

| type | rows | file |
|---|---|---|
| KSAVPlayer | 17 | KSAVPlayer.swift |
| MediaPlayerProtocol | 15 | MediaPlayerProtocol.swift |
| FFmpegAssetTrack | 9 | FFmpegAssetTrack.swift |
| MediaPlayerTrack | 3 | MediaPlayerProtocol.swift |

**44 rows — 20% of the whole queue — behind one decision.** Land §1 and they all become workable.
The 15 `MediaPlayerProtocol` rows are `PROTOCOL_REQUIREMENT`: no body exists, signature only, so
they are the cheapest 15 rows left in the corpus once the file is free.

## 2. THEN: work a CLASS end to end, largest first — not a row at a time

The remaining mass is concentrated. Twelve classes hold 152 of the 223 rows; 31 classes hold the
46-row tail. Per-class read cost, derived at s105 close (re-derive it):

| class | rows | total instr | max body |
|---|---|---|---|
| KSOptions | 30 | 2323 | 350 |
| KSAVPlayer | 17 | 996 | 167 |
| KSComplexPlayerLayer | 17 | 1817 | 648 |
| CacheIOContext | 15 | 4758 | 1638 |
| MediaPlayerProtocol | 15 | 528 | 130 |
| KSMEPlayer | 10 | 781 | 381 |
| FFmpegAssetTrack | 9 | 262 | 64 |
| LimitPreLoadIOContext | 9 | 3749 | 2255 |
| IOSVideoPlayerView | 8 | 693 | 233 |
| KSPlayerLayer | 8 | 971 | 226 |
| HLSCacheIOContext | 7 | 1542 | 798 |
| MetalPlayView | 7 | 503 | 156 |

Take ONE class. Resolve its field offsets, its witness tables and its callees ONCE, then read every
body in it and land them as one commit. `FFmpegAssetTrack` (9 rows, 262 instructions, max 64) is
the cheapest real class and is unblocked the moment §1 lands.

**Why this ordering and not cheapest-row-first:** s105 spent most of its turns paying setup cost
repeatedly. Naming one class's callees, decoding one witness table, resolving one field-offset
vector serves every row in that class. The evidence is s105's own best turns — `Anime4KQuality`
(7 rows, one commit) and the `KSOptions` statics (14, then 17, then 3) — every one of them a batch.

## 3. Two structural units, each blocking rows behind it

**3.1 `MetalPlayView` — fully scoped, ready to run.**
`reconstruction/metalplayview_field_types_s105.md` has all nine missing field TYPES resolved,
including `drawable` and `dovi`, which `bind_oracle` reports as NO BIND and `name_type_at_addr`
dereferences out of the image — both are chained-fixup REBASEs and the file shows the decode. It
also has the field-offset vector and the init's extent. What remains is reading
`init(options:)` @0x101a5eda8 (436 instr) for the eight fields that have NO `vpfi` and are
therefore assigned in the init body. Writing `= false` on the Bools instead is fabrication: the
absence of a vpfi is the specific evidence that no declaration default exists. Payoff: 2
MEMBER_MISSING rows AND all 11 REAL_FLAGs, which currently block every commit to the file.

**3.2 `Coordinator.state` / `.isRecord` are coupled.**
`isRecord` is fully derived — `$isRecord` projects `Combine.Published<Swift.Bool>.Publisher`, there
is a `property wrapped field init accessor`, and the `_isRecord` vpfi @0x10002dab0 is
`mov w0,#0 / ret` ⇒ `@Published var isRecord: Bool = false`. It CANNOT be placed: the binary's
field order is `_state, _isMuted, _playbackVolume, _isScaleAspectFill, _isRecord, …` so `_isRecord`
is index 4, and source has no `_state` at index 0 because it declares `state` as a COMPUTED
property forwarding to `playerLayer`. The l2 gate caught this. Standing `state` up as a stored
`@Published` changes the type's layout and behaviour and needs its own evidence.

**3.3 Recorded, not acted on:** `FrameOutput` has FOUR requirements in witness order
`play / pause / flush / invalidate` where the source protocol declares three as
`pause / flush / play`. Requirement order IS the witness-table layout. Reordering ripples to every
conformer's table.

## 4. ⭐ The finding that should change how you read this corpus

**Twelve members were sitting under names nobody had read**, every one behind a confident comment
citing a CORRECT address. Two comments asserted "no symbol in binary (devirtualized)" that one
trie lookup refutes. One asserted inheritance from a protocol extension default that was an ICF
fold misread — the fold is the CONSEQUENCE of two bodies matching, never evidence of inheritance.
On `AudioOutput`, three of four implementors had independently guessed `stop()`, so the wrong name
read as consensus when it was only guesses agreeing with each other.

**The enumeration that finds them, and it is cheap:** for every open row with a body address, grep
that address in its own class's source file. A hit means the body is already reconstructed under a
different name. At s105 close that returned 36 rows; about half proved to be renames and the rest
real divergences, so each hit still needs settling against the demangled signature — a rename and a
signature change look identical in the enumeration until you compare parameters.

⚠️ Renames are not cosmetic. `KSOptions.reset()` only became declarable AFTER `resetTimeLog` got
its right name; while it was still `resetTime()`, writing `reset() { resetTime() }` would have
compiled and been wrong.

## 5. Traps — six of these cost s105 real time

1. **A "blocked" you did not check is not blocked.** s105 deferred `KSPlayerLayer.updateUIView`
   claiming the tree had no macOS `UIView` alias. The grep was truncated with `head -3` and cut off
   `PlayerDefines.swift:31`, which declares exactly that. Run the check before recording a block.
2. **A too-clean tool result is the tell.** Three s105 tool outputs were confidently wrong and NONE
   was caught by a gate — `ACCESSOR 0` across 407 rows, `zero_default` true for all 35 KSOptions
   statics including `SwiftUI.Color`, and `trackColor = 0.5`. All three were caught by noticing the
   answer was implausible.
3. **Silent false negatives in `decode_string_literal`, twice.** It reported NO literals for a body
   with five (small strings are inline immediates, no `adrp`), and then returned None for every
   ASCII small string (the discriminator is 0xE6 with the isASCII flag, not 0xA6). Both fixed and
   goldened. Absence of output is not absence of literals.
4. **Decode a witness slot, never count it.** `AudioOutput.resetTime` dispatches FrameOutput
   requirement 2; counting off the source's declaration order gives `play()` and is wrong. Decode
   the conformer's table (`decode_witness_table --conformances <nominal desc>` then `--wt <addr>`).
   Corroborate with structure: Coordinator's KSPlayerLayerDelegate table has reqs 0-4 with real
   bodies and 5-10 all the canonical empty body, matching five implemented + six defaulted exactly.
5. **The l2 gate blocks on the CLASS, not your diff — including a sibling in the same file, and a
   class in a DIFFERENT file.** `FFmpegSubtitleParse.parsePart` was blocked by a `Double`-vs-`Int64`
   flag on `AssIncrementImageRenderer`. Fix the real divergence; a support-class block never
   justifies the verify bypass. Distinguish the three kinds first: DEFERRAL, SPELLING, and NULL
   (`T!` vs `T?` emit an identical typeref — align the text, record the undecidability, never
   present it as a divergence fixed).
6. **A stored property's ORDER is its layout.** Declare it at its field-record index, not appended.
   Computed members between them occupy no slot. `Packet.isFlush` had to go between `corePacket`
   and `assetTrack` even though two computed properties sit there in source.

## 6. Genuinely undecidable — do not spend time re-deriving these

- **4 `URLContextDownload` FFmpeg callees.** `ffmpeg_name_oracle --addr <a> --resolve` returns
  UNKNOWN with zero survivors for 0x1030c0994, 0x1030bf914, 0x1030c07ac. Call-context is
  suggestive (`fileSize` calls 0x1030c07ac with `0x10000` = AVSEEK_SIZE) but the oracle's own
  contract says a fingerprint that cannot be discriminated is never identity.
- **2 `IOSVideoPlayerView` rows** (`toggleBottomSlimProgress`, `updateTitle`) share a body that is
  `bl swift_deletedMethodError / brk` — a compiler stub with no body to read. Never reconstructable.
- **`SubtitleInfo.language`.** The binary's name really is `language`, and the source's
  `subtitleLanguage` is a DELIBERATE, documented divergence: renaming produces
  `error: ambiguous use of 'language'` at FFmpegAssetTrack.swift:109 against
  `MediaPlayerTrack.language: String?`. That comment was right. Resolving it means disambiguating
  in a file that is part of §1.

## 7. State at s105 close — re-derive before acting

| quantity | value |
|---|---|
| MEMBER_MISSING | **223** (was 407 at s105 open) |
| of the 184 removed | 116 real declarations/corrections · **71 phantom rows from six tool defects** |
| commits | 34, `dea1e23..1faa72e` on `forward`, every one building 4/4 |
| ACCESS | 26 (was 5 — every rise is a member becoming visible to the parser for the first time) |
| body-read rows | 202, ~31k instructions, median 30 |

**71 of the original 407 were never debt.** Five parser defects in `pin_sweep`/`pin_inventory`
(foreign-module owners 35, `internal(set)`/`package` 25, `override` + `mutating` + enum cases 11,
qualified extension names 3) plus two in `decode_string_literal`. All are fixed and goldened, so
they cannot return — but it means any MEMBER_MISSING figure quoted from before s105 was ~17% noise.

## 8. Structural bounds that have not changed

- A STOOD_UP moves the floor and readiness by exactly zero. `load_done()` accepts only FAITHFUL.
- A class must exist before its members can be reconstructed (`class_presence_gate`).
- A verdict flips per FILE, not per divergence.
- `ready_leaves` is not remaining work; ~92% is compiler output.
