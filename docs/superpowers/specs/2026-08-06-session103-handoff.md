# Session 103 work

Session 102 cleared the FIRST CRITICAL of the s98 fix queue and moved the floor for the first time
in two sessions. It closed neither open phase, and the s102 GOAL as written could not be met — see
§6, which states why one of its five requirements is unsatisfiable by construction rather than
merely large.

You are the ORCHESTRATOR. Agents derive; you alone adjudicate, edit source, build and commit.

## Verify first

1. `python3 scripts/recon_gate.py --mode handoff` — expect **PASS 50 / ANOMALY 0 / FAIL 3**. The
   three FAILs are `agg_critical` **6**, `agg_high` 19, `agg_unresolved` 1. `agg_critical` was 7 at
   s102 open; if it reads 7, the s102 adjudication did not land and nothing below is trustworthy.
2. `python3 scripts/aggregate_verdicts.py` — the faithful floor is **333** and DIVERGENT is **13**.
   Confirm both rather than quoting them.
3. `python3 scripts/topo_readiness.py --selfcheck` — expect PASS on every dim including `wave-excl`.
4. `python3 scripts/stale_divergence_screen.py --selfcheck` — expect SELFCHECK PASS. ⚠️ Its
   `stop/live span lines` control is anchored on LINE NUMBERS inside
   `Sources/KSPlayer/AVPlayer/KSPlayerLayer.swift`, so ANY edit to that file rots it. s102 re-anchored
   it once (376→390, 449→463). If it goes red, verify the delta equals your diff's net line change
   before touching the numbers, and never relax the assertion to a count.
5. `python3 scripts/recon_progress.py` — STAGES is **11/18**, unmoved. ⚠️ Its WORK BUCKETS and the
   new-class debt line still read frozen artifacts (§5). Its Correctness-sweep line is now LIVE
   (s102) and costs ~21s of the run.
6. `python3 scripts/class_presence_gate.py` — ABSENT 9 types / 98 work items, NOT the 109/11
   `recon_progress` prints.
7. Read `MEMORY.md`, then `reconstruction/AGENT_PROTOCOL.md` and
   `reconstruction/DISPATCH_CONTRACT_s64.md`.
8. Read `reconstruction/S102_FINDING_osi_init_optional_slots.md` — both sections. The addendum is
   your entry point for step 12.

## 1. State at close — derived, re-derive before acting

| quantity | value |
|---|---|
| faithful floor | **333** (was 332; +1 this session) |
| verdicts | FAITHFUL 333 · STOOD_UP **117** (was 92) · DIVERGENT 13 · UNRESOLVED 1 |
| fix queue | CRITICAL **6** (was 7) · HIGH 19 · MED 16 · LOW 10 |
| stand-up wave | **50** units (was 75) — 27 SettingsView, 23 IOSVideoPlayerView |
| readiness | ready 754 · blocked 305 · done_faithful 320 (unmoved — a STOOD_UP unblocks nothing, §7) |
| stages | **11 of 18**, unmoved — and both open marks are now DERIVED, not literals |
| gate | PASS 50 · ANOMALY 0 · FAIL 3 |

## 2. What session 102 landed — six commits, `ec8b914..b76d699`

Every one built 4/4 and passed the pre-commit gate. The gate blocked twice on missing
`ffmpeg_name_oracle` markers and once on the l2 field gate; each was fixed in source, never with
`--no-verify`.

**The CRITICAL that cleared:** `MEPlayerItem_startRecord_101a483d4`, adjudicated FAITHFUL
(overturned) after its body was written from the binary. Its s85 deferral named two blockers; both
are gone. Four of the nine ABI slots of the OSI designated init `0x101a1d014` were WRONG and are now
derived from the callee's own nil tests — p5 `[String: Any]?`, p6+p7 `String?`, p8 `AVMediaType?`
(was an un-receivable `flag: Int`), p9 `[AVCodecID]?`.

**Two method names recovered from the trie**, superseding inferred ones: `0x101a1b8d4` is
`writeTrailer()` (was `finishWriting()`), `0x101a1bb5c` is `stop()` (was `close()`). Single symbol at
each address, no ICF fold.

**One field was the wrong TYPE:** `Remuxer.mediaType` resolved to Libavutil's C `AVMediaType` enum in
a file importing Libavcodec but not AVFoundation, while the binary `objc_retain`s that field. Now
module-qualified.

**`recon_progress`'s Correctness-sweep line** no longer carries four s63 literals. It derives live
from `pin_sweep.sweep_every()`; new golden `scripts/test_recon_progress.py`, 7 controls, and the
`# no-golden` exemption on that file is gone. Three of the four literals were false: live is
`ACCESS 5 · MEMBER_MISSING 407 · TYPE_DIVERGENCE 5` against the frozen `0 / 448 / 6`.

## 3. ⭐ THE OPEN UNIT — `KSPlayerLayer.set`, half done

`KSPlayerLayer_setUrlOptions_slot55_s84` carries TWO CRITICAL divergences. **Divergence 1 is closed**
(`b76d699`): the parameter is `KSOptions?`, settled from the trie INDEX, which carries exactly two
`KSPlayerLayer.set` symbols — the method and its `method descriptor` — i.e. ONE overload with a
vtable slot. The `if let` guard was READ, not styled: `cbz x24, 0x1019cb760` @`0x1019cb6fc`, and the
nil arm REJOINS rather than returning.

**Divergence 2 is the whole job**: the body is 251 instr, `0x1019cb674-0x1019cba60`. Per the s84
verdict it copies `options.isAutoPlay` into `self.isAutoPlay`, selects a player type from an array
inside options with a `KSAVPlayer` fallback, compares it against the current player's dynamic type
and constructs a replacement when they differ, compares the URLs, writes `state` through Combine,
calls `MediaPlayerProtocol.replace(url:options:)`, then dispatches `play()` and `prepareToPlay()`.

⚠️ **Partial work on this unit moves NO number.** `aggregate_verdicts` keys the severity counts off
`final_verdict == "DIVERGENT"` for the whole FILE, so the verdict flips only when every divergence in
it is resolved. Budget the body, or pick a different unit.

## 3b. The STAND-UP WAVE — 75 → 50, and how to keep going

Twenty-five units stood up, every one through `write_standup_verdict.py` (which re-derives extent,
dispatch, ICF fold and the vtable row itself and REFUSES on a mismatch with your premise, so the
structural half is never typed) and adjudicated with per-unit evidence. Re-derive with
`wave_worklist.py --wave standup`; do not trust this number.

**Work smallest-first and look for families.** The first twelve were 5-7 instruction trampolines
that batched eight at a time because they shared a shape; everything since costs about one working
cycle per unit. Four families were mapped, each identified by a SHARED TAIL-BRANCH TARGET or a
shared spine rather than by any name — that is the only identification available when the trie is a
real negative, which it is for all 27 remaining SettingsView units:

- idx156/158 — `_AVMediaTypeVideo`/`Audio` → `0x101b20598`
- idx180-185 — base global `0x104c631c0` at +0x10/+0x18/+0x20 × two targets, all six combinations
- idx153/161 and idx177/179 — ASCII immediate pairs → `0x101b20c88` / `0x101b24450`
- **idx172/173/174/175** — the associated-object callback family: read a byte field, use its stack
  slot's ADDRESS as an `objc_getAssociatedObject` key on the x0 sender, bridge to `Any`,
  `swift_dynamicCast` to a function type, invoke. Members differ by the type the callback receives,
  established from the STORE WIDTH before any name was known: `strb`→`isOn`, `str s0`→`value`,
  two-word→`text`, and idx172 fetches nothing.

⚠️ **One anomaly is open across all four of that family and should not be smoothed away.**
`objc_getAssociatedObject` takes `(object, key)`; the key here is a STACK ADDRESS, which is not
stable between calls. Four consistent sightings make it a pattern, not an accident — but consistency
is not an explanation and none of the four bodies contains one.

## 3c. ⭐ NEW TOOL — `decode_objc_selector.py`, and use it FIRST

Selfcheck PASS, golden-anchored on `0x10346be40` → `setText:`, which `OutputStreamInfo.swift`
recorded from an independent reading long before the tool existed.

**Run it on every `__objc_stubs` call site before writing a verdict.** It removes the one open item
every UIKit stand-up in this wave carries. The key fact it encodes: an `__objc_selrefs` slot is a
chained REBASE, not a pointer — the target is `image_base + (v & 0xF_FFFF_FFFF)` — so a plain
`struct.unpack` read lands nowhere and the address looks like a dead end.

Its first run decoded all 13 selectors left open across the wave, and every one CONFIRMED the shape
that verdict had already derived from instructions alone (idx144's 0.6/12.0 are
`colorWithAlphaComponent:`/`setCornerRadius:`; idx139's send is `addArrangedSubview:`). **The 25
landed verdicts still record their selrefs, so back-filling those names is a lookup, not a
re-derivation — that is the single highest-leverage follow-up for this wave.**

## 4. A LEAD, deliberately not acted on

`set(urls: [URL], options:)` at `KSPlayerLayer.swift` has **no trie symbol of any kind** — no
descriptor, no body — and the l2 field gate independently WARNs that `urls` is a field in source and
absent from binary reflection. Two independent signals that the `set(urls:)` family is source-only.
**Nothing was removed.** Absence from the trie means UNNAMED, not absent; run it through
`member_gate.py` before deleting a member.

## 5. Open defects — carried forward from s101/s100, all unchanged

1. `classify_accessor_slots` drops bodies silently — fix by resolving class+slot from the ADDRESS.
2. `recon_progress` reads frozen artifacts for WORK BUCKETS (`accessor_slots_s60b.json`) and the
   new-class debt line (`class_presence_s59.json`: 109/11 against a live 98/9).
3. `method_source_presence` accepts a `bl` as a selector anchor; the presence split reads 33/42,
   corrected 32/43.
4. `field_offset_vector.py:94` module-backreference; `decode_string_literal.py --addr 0x101b1d474`
   out-of-image read; `fieldrec.py` vs `dump_field_bindings.py` disagree on IOSVideoPlayerView.

## 6. ⭐ ON THE s102 GOAL — read before accepting a similar one

The s102 goal required driving 14 DIVERGENT bodies to FAITHFUL, clearing 4 audit-wave and 75
stand-up-wave units, and reaching 13/18 stages. One body was driven to FAITHFUL, in six commits.
Three structural facts the goal did not account for, each measured:

- **Requirement (4) is unsatisfiable as written.** A stand-up unit has no source counterpart
  (`method_source_presence --wave standup` returns SOURCE_MATCH 0), so `STANDUP_PROTOCOL` §1 permits
  only STOOD_UP. Those 75 units can never be FAITHFUL, and by the §7 rule they move the floor and
  readiness by exactly zero regardless.
- **"Correctness sweep" is not the fix queue.** That stage tracks `pin_sweep` kinds — 417 live
  findings — not the 52 fix-queue entries. Closing it is a different, larger job.
- **The stage marks are string literals** in `recon_progress.py`'s `stages` list. They are not
  derived from anything, so "until recon_progress reports 13/18" is satisfiable by editing prose.
  s102 did not touch them. Deriving the stage state is a genuine unit, and would make a goal of this
  shape checkable instead of assertable.

## 7. Suggested order

9. Re-verify per "Verify first". Stop if `agg_critical` is not 6.
10. Decide the session's ONE target and say so before starting. The honest next milestone is
    `CRITICAL 6 → 5`; every candidate is a multi-turn body write, so pick by divergence COUNT, not
    severity — a verdict flips only as a whole file.
11. Cheapest candidates by divergence count: `KSPlayerLayer_setUrlOptions_slot55` (3 left of 4),
    `KSPlayerLayer_readyToPlay_slot69` (4), `KSPlayerLayer_structural_placement_s76` (2 MED, no
    CRITICAL — flips the DIVERGENT count and the floor but not `agg_critical`).
12. If you take `setUrlOptions`, resume at `0x1019cb760` — everything before it is read and written
    up in the S102 finding addendum.
13. Gate every touched class before staging; commit each unit on `forward` through
    `scripts/commit_unit.sh`.

## Close out

14. Update `reconstruction/handoff_baseline.json` with a `captured_session103` block and re-pin
    `head`, `ahead_origin` and `faithful_floor`.
15. Run `python3 scripts/handoff_completeness_lint.py <this file>` before committing it.
16. Write the session-104 handoff; give the takeover prompt in chat, never in the file.
