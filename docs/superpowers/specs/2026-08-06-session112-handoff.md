# Session 112 handoff — closing the remaining MEMBER_MISSING

**Status at write time: MEMBER_MISSING 68** (76 at s111 start; s111 landed 8). This document is
ORIENTATION. Its companion `2026-08-06-session112-PROMPT.md` is the entry point.

s111's own working doc — `2026-08-06-session111-helper-standup-queue.md` — is the raw trail and
carries every address list. **Every address list in it predates later edits. Re-derive before use.**

---

## 1. Verify first — derive these, do not quote them

```bash
python3 scripts/recon_gate.py --mode handoff
```
```bash
python3 scripts/pin_sweep.py --every
```

| what | expected |
|---|---|
| MEMBER_MISSING | 68 |
| ACCESS | 26 |
| NOT_IN_TRIE | 23 |
| AMBIGUOUS_OVERLOAD | 10 |
| TYPE_DIVERGENCE | 4 |
| build | 4/4 |
| KSPlayer | branch `forward`, tree clean, recent log showing the s111 commits (no hash pinned — writing these files moves HEAD) |
| FFmpegKit | `12f0899` on `forward-recon-shim`, ~1167 tracked dirty files UNSTAGED. **Never `git add -A` there.** |

Three selfchecks must print `SELFCHECK PASS`. All live only in `play/scripts/`, which is
gitignored — **if any is missing it must be rebuilt from this document before it is trusted**:

```bash
python3 scripts/rank_member_missing.py --selfcheck && python3 scripts/name_exhaustion_gate.py --selfcheck && python3 scripts/helper_fingerprint.py --selfcheck
```

If any count disagrees, STOP and report before investigating.

---

## 2. The one thing that will mislead you most

**There is no single blocker class.** s111 spent most of its length assuming the queue was gated on
unnamed private helpers. It is gated on THREE independent things, and only the first is what the
invented-name authorisation addresses:

| blocker | measured by | example |
|---|---|---|
| unnamed in-module callee | `rank_member_missing.py` | most of the 44 blocked rows |
| **undeclared FIELD** | nothing — check by hand | `MetalPlayView` needed 4 fields for 3 rows |
| **TYPE divergence** | nothing — check by hand | `CacheIOContext.clearOtherCache` |

`CacheIOContext.clearOtherCache` is the cautionary one: its body is already transcribed in source,
the ranker calls it READY, and it cannot be written. `tmpURL` is declared `URL?` where the binary's
`vpWvd` has no `Sg`. Declaring the body needs a `guard let` (a branch the binary lacks) or a `!`
(a trap it lacks). **Before starting any "ready" row, resolve its offset globals with
`recover_field_offsets.py --class C --global G` and check every name against the source.**

---

## 3. Tools built in s111 (all gitignored — rebuild if absent)

**`scripts/rank_member_missing.py`** — ranks the queue by what actually blocks each row. Four
verdicts per body: `DELETED`, `ASYNC`, and callees split UNNAMED / QUEUED / HELPER / NAMED.
Read the ROW-level "every body ready" list at the bottom, not the per-body table — a pin_sweep row
closes only when every body under it is declared (`Coordinator.isRecord` has four).

    python3 scripts/member_missing_triage.py --json T
    python3 scripts/rank_member_missing.py --triage T --helpers H --json R

**`scripts/name_exhaustion_gate.py`** — the precondition for an invented name. Four verdicts:

| verdict | meaning |
|---|---|
| `ARTIFACT` | no source counterpart. Never name, never write. |
| `INLINE-INSTEAD` | one call site image-wide — inline the expression, do not name it |
| `ROUTE-OPEN` | a name is recoverable; rule 1 governs |
| `EXHAUSTED` | all routes closed AND it is a shared source member — an invented name is permitted |

---

## 4. The invented-name rule (human-authorised in s111)

Names may be invented from PURPOSE, **only** behind the gate:

1. `name_exhaustion_gate.py --addr A` must return `EXHAUSTED`.
2. The marker grammar is deliberately different from a derived fact:
   `⚑[invented=<name> addr=<0xADDR> exhaustion=name_exhaustion_gate approved=<who>]`
   **`invented=` is never `tool=`.** One grep then separates every fabricated identifier in the
   tree from every derived one, permanently.
3. The gate is a PRECONDITION, not an approval. `approved=` carries explicit human sign-off.
4. Derive the name from the ROUTE-C caller-set evidence in the s111 doc, plus what the body does.

⚠️ The gate has been wrong in BOTH directions on its first two uses, which is why it has goldens:
it returned `EXHAUSTED` for Swift stdlib bridging code, and `ROUTE-OPEN` for the noise string `zpl`.
Do not weaken it; extend it and add an anchor.

---

## 5. The helper queue, as s111 left it

117 distinct unnamed callees behind the blocked rows:

| class | count | disposition |
|---|---|---|
| HELPER / ARTIFACT | 43+9 | never name, never write |
| single-call-site | 18 | INLINE into the caller — not units |
| tail-branch thunks | 6 | not units |
| **EXHAUSTED** | **40** | invented name permitted, with evidence |
| ROUTE-OPEN | 1 | `0x101a9f27c` = `FFmpegSubtitle.init(url:)` (unique literal `can not judge stream`) |

Three are library code, not Swift: `0x1030c0994` (FFmpeg), `0x10245e7d8` / `0x10245f0e0` (libass —
their literals are libass event-parser messages). They gate `HLSCacheIOContext.read` and all three
`AssIncrementImageRenderer` rows; their unit is an FFmpeg/libass NAMING one, not a standup.

---

## 6. The floor is 2, not 0

`IOSVideoPlayerView.toggleBottomSlimProgress` and `updateTitle` fold onto `0x10198eb18`, the
`swift_deletedMethodError` stub. Their names are in the trie; **their code is not in the binary.**
Clearing those two means writing bodies with no source of truth. Everything else is reachable.

---

## 7. Start here — `MetalPlayView.enterForeground` @0x101a60ad0

Fully decoded in s111, every constant read. All four fields it needs are declared.

    isBackground = false
    if !renderUseDispatchSourceTimer {
        backgroundTimer.schedule(deadline: .distantFuture, repeating: .never, leeway: .nanoseconds(0))
    }
    guard metalView.isHidden else { return }
    guard let pixelBuffer else { return }
    guard let imageBuffer = pixelBuffer.<witness +0xc8> else { return }
    if let formatDescription {
        (displayView.layer as! AVSampleBufferDisplayLayer).<0x101a61f60>(imageBuffer, formatDescription)
    }

Constants, all read: `__got 0x104113320` = `.never`; `0x104113310` = `.nanoseconds` with a zeroed
payload; globals `0x1044ea8e0` = `formatDescription`, `0x1044ea8a8` = `displayView`; classref
`0x104410d18` = **`AVSampleBufferDisplayLayer`** (NOT `CAMetalLayer` — an earlier s111 note said
otherwise and was corrected).

**One blocker: the spelling of `0x101a61f60`.** It takes an `AVSampleBufferDisplayLayer` receiver in
swiftself and two arguments, the second demonstrably `formatDescription`. Its `#function` literal
reads `enqueue(imageBuffer:formatDescription:)` and matches the call shape exactly, but FAILS the
corrected two-part rule (the body never materialises a 39-character string), so the gate routes it
to the invented-name path. Source's three-label `enqueue(...:time:)` at MetalPlayView.swift:544 is
on `AVSampleBufferDisplayView` — different type, different arity, not that member.

Closing this row also requires reading that method's 439-instruction body. It is its own unit.

---

## 8. Corrections s111 made that you must not undo

- **The s110 `#function` trust rule is REFUTED.** "Early materialisation whose loaded length
  matches" fires on `0x1019c7454` -> `pictureInPictureViewController`, which is a **KVC key** passed
  to a witness, not the function's name. Its sibling `0x1019c7410` does the same with `delegate`.
  The corrected rule needs BOTH the length match AND a `#file` companion — and even both together
  passed noise, so check what the string is USED for.
- **`0x101a61f60` is NOT an outlined KSLog**, despite touching `logLevel`/`logger` with a `#file`.
  That signature cannot separate "is an outlined KSLog" from "contains one".
- **`method_source_presence._chained_ptr` returns image-base+0 for a NULL field**, so a genuine
  negative prints as `entsize=0xfeedfacf`. Cosmetic, but it makes a true negative look like a gap.

---

## 9. Waiting on the human

Nothing is blocked on a decision. The invented-name authorisation is granted and gated; the floor
of 2 is stated; every other row is a binary read.
