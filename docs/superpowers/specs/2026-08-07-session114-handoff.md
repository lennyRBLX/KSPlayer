# Session 114 work

## Verify first — every number here was DERIVED at the end of s113, not copied forward

```bash
python3 scripts/recon_gate.py --mode handoff
```
```bash
python3 scripts/pin_sweep.py --every
```

| what | expected |
|---|---|
| gate | `PASS 48   ANOMALY 2   FAIL 4` |
| FAITHFUL FLOOR | **356 / 1035** |
| MEMBER_MISSING | **60** |
| ACCESS · NOT_IN_TRIE · AMBIGUOUS_OVERLOAD · TYPE_DIVERGENCE | 26 · 23 · 10 · 4 |
| total disagreements | 123 |
| build | 4/4 |
| KSPlayer | `forward` @ `62e18ce`, tree clean apart from the pre-existing untracked spec docs |
| FFmpegKit | `12f0899` on `forward-recon-shim`, 1167 tracked dirty UNSTAGED, 0 staged. **Never `git add -A` there.** |

⚠️ **The s113 handoff's table said the floor was 333. It was 356 the whole time.**
`recon_progress.py:358` ECHOES `faithful_floor` out of `handoff_baseline.json`; it does not compute
it. The baseline had not been touched since `captured_session102`, so every handoff since then
repeated a stale number. The live count over 550 verdict files is 356 FAITHFUL / 175 STOOD_UP / 18
DIVERGENT / 1 UNRESOLVED, 16 of the FAITHFUL riding the no-recheck fallback. Both scalars are
corrected in the baseline now, which is why ANOMALY fell 6 → 2.

**The 4 FAILs are pre-existing and unchanged**: `sc_wave_worklist` (the OPEN adjudication of
`101a6ce44`, `wave_exclusions.json` entry 8, `adjudicated_session: 93`), `agg_critical` 6,
`agg_high` 24, `agg_unresolved` 1.

**The 2 ANOMALYs were left deliberately.** `wave_audit_size` and `wave_standup_size` both measure 0
against baselines of 4 and 49. Zeroing them is a one-line edit and I did not make it: the resolver
requires each unit adjudicated into `wave_exclusions.json`, s113 did not do that, and a baseline
moved without the adjudication hides drift instead of recording it. **That adjudication is a real,
small, well-specified unit and is a good place to start.**

Four selfchecks must print `SELFCHECK PASS`. All live only in `play/scripts/`, which is gitignored:

```bash
python3 scripts/rank_member_missing.py --selfcheck && python3 scripts/name_exhaustion_gate.py --selfcheck && python3 scripts/helper_fingerprint.py --selfcheck && python3 scripts/recover_field_by_access.py --selfcheck
```

Counts changed in s113: `recover_field_by_access` **35** checks (was 13), `name_exhaustion_gate`
**22** (was 14). Fewer means a fix was rolled back — stop and report before doing anything else.

---

## What s113 landed

Four commits, each alone on `forward`, build 4/4 at every one. **MEMBER_MISSING 66 → 63.**

| commit | unit |
|---|---|
| `ec9f17f` | `KSComplexPlayerLayer.change(state:)` @0x1019d1890 |
| `3901d2c` | `KSAVPlayer.readyToPlay()` @0x1019a402c |
| `be3d87b` | `CacheIOContext.copyPreloadCache(md5:from:to:)` @0x101b8e85c |
| `62e18ce` | no member — the derivation that `ReadCacheIOContext` 0x1044f6918 is `eof` |
| `91cc415` | `KSOptions.displayEnumVR` + `displayEnumVRBox` — TWO rows |
| `a096c0f` | `CacheIOContext.clearOtherCache` — plus `tmpURL` retyped to the non-optional `let` |
| `fb879df` | no member — the `0x104c63938` tie cut from SEVEN candidates to two |

### 🚨 THREE FALSE EXHAUSTED WERE FOUND INSIDE THE A4 PRE-APPROVED BATCH

s112 found one (`0x1019c835c`, Swift's `firstIndex(of:)`). s113 found **TWO more**, so the
eligible batch is **45 → 42** once the third below is counted: `0x1019ac164`,
`0x1019ac5b4` and `0x1019c1ca4`.

The first is five instructions — `adrp/add x2` to the ObjC classref `_OBJC_CLASS_$_AVPlayerItemAccessLogEvent`,
`adrp/add x3` to a `__DATA` global, then `b 0x1000e97c8` — and **seven** sibling thunks in the same
run tail-call that one shared body, each binding a different classref (the next one over binds a
register-built `"CTRunRef"`). None of the seven is in the trie. It is one arm of a compiler outline,
and naming it would have fabricated an identifier for glue.

It was reached by working the handoff's own 13-row worklist: `DynamicInfo.update` is field-clean and
its only blocker is this address, which made it look like the cheapest remaining row in the tree.

The gate now carries the discriminator as clause (c2): a body of ≤8 instructions that only loads
constants and tail-calls a shared target, where ≥3 sibling bodies tail-call that same target, is
ARTIFACT. It makes MORE things artifacts, which suppresses invention — the safe direction — and it
cannot swallow a real member because `route_trie` runs first (a trie-named one-instruction thunk
like `KSComplexPlayerLayer.removeRemoteControllEvent` @0x1019d27a4 is ROUTE-OPEN before it is
reached). Both are goldened; selfcheck 16 → 22.

The rule-10 re-sweep over all 116 addresses in one process CHANGED exactly two, both
EXHAUSTED → ARTIFACT: `0x1019ac164` (7 siblings on 0x1000e97c8) and `0x1019ac5b4` (3 siblings on
0x1000853e8, binding a `__TEXT` pointer and a register-built `"Anime4K"` string). Nothing else
moved. `reconstruction/blocker_classification_s112.json` now carries a `gate_fix_s113` block and
its tally is ARTIFACT 52 / EXHAUSTED 42 / INLINE-INSTEAD 13 / ROUTE-OPEN 9 after the
second re-sweep, which changed exactly one more address and nothing else.

### 🚨 …AND A THIRD, of a different kind: stdlib CONTAINER internals

`0x1019c1ca4` blocks `KSOptions.firstTimeLog`, which the worklist lists as field-clean with this as
its **only** blocker — so it read as one of the most available rows left. It is 67 instructions with
10 call sites, no literals and no `#file`, so every naming route legitimately closes. It also calls
**`KEY_TYPE_OF_DICTIONARY_VIOLATES_HASHABLE_REQUIREMENTS`** against `$sSSN`: it is a
`Dictionary<String, _>` lookup specialization. Naming it would name the standard library, exactly as
`firstIndex(of:)` would have in s112.

Gate clause (b2) now treats a call to a stdlib container diagnostic as ARTIFACT. Goldened.

⚠️ **The lesson for A4 generally: the EXHAUSTED batch is not pre-cleared, it is pre-APPROVED.**
THREE of its 45 addresses have now failed inspection in this session alone — two outlined-glue
family members and one Dictionary specialization — on top of s112's `firstIndex(of:)`. That is four
across two sessions, and every one of them was found only by reading the body. Run the shape check
on every address before writing a name, as A4 says: it is not a formality, it is the step that has
caught something four times out of four attempts to use the batch.

### 🚨 THE A4 WORKLIST IS MOSTLY NOT AVAILABLE — its blockers are glue, not names

This is the conclusion the three false EXHAUSTED above build to, and it is the most decision-relevant
thing in this handoff. s112's "the worklist your approval actually covers" lists 13 rows and says
eight of them are field-clean, so **"the ONLY remaining gate is naming — which is what the approval
covers."** s113 tested that claim by running the hardened gate over every blocker on the field-clean
rows and then READING each one. They are all still EXHAUSTED, and they are all adapters:

| row | blocker | what it actually is |
|---|---|---|
| `KSOptions.firstTimeLog` | `0x1019c1ca4` | `Dictionary<String,_>` specialization — now ARTIFACT |
| `DynamicInfo.update` | `0x1019ac164` | 1 of 7 outlined-glue thunks — now ARTIFACT |
| `KSOptions.removeHeader` | `0x1019ac888` (3 instr) | binds `_swift_bridgeObjectRelease` as an ARGUMENT, then `b 0x1019b02b0` — itself NOT_IN_TRIE, 69 instr |
| `HLSCacheIOContext.parseM3U8` | `0x101b945b0` (9 instr) | binds a data global, a `__TEXT` const, `Foundation.URL`'s metadata accessor and `_swift_bridgeObjectRelease`, then `b 0x100084f38` — NOT_IN_TRIE, 97 instr, and BELOW 0x101000000 |
| `PlayerView.buildMenusForButtons` | `0x1019afab0` (11 instr) | loads `[x20]`, binds two constants, calls `0x1019b0834` (NOT_IN_TRIE, 80 instr), stores the result back |

Swift source cannot pass `_swift_bridgeObjectRelease` as a value — it has no Swift spelling. A body
whose whole job is to bind a runtime entry point plus a metadata accessor and tail-call a shared
unnamed implementation is a generic-specialization adapter. **Naming it would not make the row
writable anyway**: its target is unnamed too, so the chain just moves one hop.

⚠️ **NEXT TOOL UNIT, specified:** encode this as gate clause (b3) — a body that loads a `__got` slot
binding a `_swift_*` runtime entry point into an ARGUMENT register (x0-x7) **without** ever `blr`-ing
it, and then tail-calls, is an adapter. Golden it positive on `0x1019ac888` and negative on
`CacheIOContext.copyPreloadCache` @0x101b8e85c, which CALLS `swift_bridgeObjectRelease` normally and
is a real member. s113 verified the shape by reading all five bodies but did NOT add the clause,
because rule 10 requires a full 116-address re-sweep before trusting it and two were already spent.

### Rows checked and MEASURED this session, so they are not re-hoped

`KSOptions.makeDecode(packet:)` @0x1019b604c looks like a 52-instruction row and is not one. Its
body is `autoreleasepool { … }`: the pool push/pop bracket a single call to `0x1019b611c`, which is
**362 instructions and INLINE-INSTEAD (1 call site)**, so it must be written INTO the source rather
than named — true cost **414**. Its FIELD axis is clean (every global is trie-named:
`KSOptions.hardwareDecode`, `asynchronousDecompression`, `decodeType`, plus the `DecodeProtocol`
witness tables for `FFmpegDecode` / `VideoToolboxDecode` / `SubtitleDecode`, which is what makes the
return a three-way choice). But its CALL axis is not: the inlined body has **seven** unnamed
KSPlayer-band callees — `0x101a6f3bc`, `0x101a6ed88` (twice), `0x10199b78c`, `0x101a0ce98`,
`0x101a0be50`, `0x101a0c470`. That is why the ranker excludes it.

`KSPlayerLayer.reset()` @0x1019ccbc0 is blocked on `0x101ab2540` (507 instr, EXHAUSTED) and uses
`swift_getKeyPath` twice plus `Published._enclosingInstance`, so it is a property-wrapper-aware body.

`HLSCacheIOContext.read` @0x101b97480 is blocked on `parseM3U8`, which is itself a queued row, and
calls two FFmpeg addresses in the library band that must be spelled by name.

**The genuinely unblocked large rows** — nothing to name, nothing to adjudicate, just reading — are
`KSComplexPlayerLayer.registerRemoteControllEvent` (648 + twelve `[weak self]` handler closures
measured at 67/67/92/80/67/61/95/101/133/133/105/257 = **1,258** more instructions, field axis
touches ZERO stored properties) and `MetalSubtitleView.draw` (242 + a 16,112-byte closure). Those
are the two to spend a session on.

### One approved-batch address that DOES pass the shape check

Not everything in the A4 batch is glue, and the counter-example is worth having: **`0x101ac0a90`**
(63 instr) sends `drawableSize`, `currentTraitCollection`, `displayScale` and `setNeedsDisplay`,
touches four instance fields and calls a KSPlayer body. It is method-shaped, and its FIELD axis is
already clean — MetalSubtitleView.swift names all four globals it uses (`subtitleImages` 0x1044ef5c0,
`pendingTexts` 0x1044ef5c8, `parts` 0x1044ef5d8, `playRatio` 0x1044ef5e0). It has THREE call sites:
`mtkView(_:drawableSizeWillChange:)` @0x101ac0d48 plus two unnamed bodies (0x101ac0810, 0x101ac0d58).

✅ **s112's cost estimate for `MetalSubtitleView.mtkView` is CONFIRMED, not overstated.** s113
initially misread it as an overstatement. It is not: `mtkView` is 4 instructions that forward
`(width, height, false)` to `0x101ac0a90`, and `0x101ac0a90` calls **`0x101abc398`, which is 809
instructions and INLINE-INSTEAD at a single call site** — so it must be written INTO the body rather
than named. 4 + 63 + 809 = **~876 instructions**, which is exactly the "~870-instruction
INLINE-INSTEAD chain" s112 recorded. Closing the row also requires an invented name for
`0x101ac0a90`, which the shape check clears.

### ⚠️ The single most transferable thing s113 learned

**A row three sessions recorded as blocked had an unprobed escape.** `displayEnumVR` /
`displayEnumVRBox` were written off by s106, s109 and s112, each of which measured a DIFFERENT
spelling and recorded the negative honestly — `nonisolated(unsafe) var`, `nonisolated(unsafe) let`,
`nonisolated` inits, and deleting `@MainActor` from `SphereDisplayModel`. None of them tried
`@MainActor` **on the static itself**. It builds 4/4 and touches nothing else in the tree.

Read the recorded negatives as *the set of spellings already eliminated*, not as *this is
impossible*. The note was excellent and still incomplete.

`change(state:)` is the superclass's 115-instruction `change` INLINED plus one
`MPNowPlayingInfoCenter.default().nowPlayingInfo = nil`. There is **no `bl 0x1019cc0ac`**, so
`super.change(state:)` is recorded in the source as a READING, not an observation — the argument
for it is that the alternative puts four statements in the subclass's file that nothing in the
binary distinguishes from the superclass's own.

---

## 1. THREE TOOL DEFECTS. Two fixed, one root cause still live.

All three were found by running a **known answer** through the tool, not by reading the code. That
is the technique to repeat.

### 1a. `recover_field_by_access` printed a FALSE UNIQUE. **FIXED.**

This is the one that matters, because A1 lets a session write a UNIQUE straight into the source
with no human. Three compounding defects:

- **Zero-register writes were invisible** — the access regex demanded a numbered register, so
  `str xzr` / `strb wzr` never matched. `isPictureInPictureStoped`, a binding s112 itself
  recorded, read ABSENT.
- **Address-forming `add` was invisible** — the trie-named `KSPlayerLayer.delegate` read ABSENT in
  a body that plainly does `add x21, x20, x8`. An `add` proves presence and carries NO width, so
  it must never narrow by type, and it must be a FALLBACK rather than a first-match return.
- **Width was matched against TYPE CLASS.** An 8-byte access is compatible with `dword` AND `ref`
  AND `double`; matching only `type_class == DWORD` discarded every reference-typed field. Worse,
  `exported_fields` matched module+field **without checking the owning class**, so
  `KSPlayerLayer.shouldSeekTo` was excluded on the strength of a vpWvd belonging to **KSAVPlayer**.
  Together they printed `UNIQUE -> bufferingStartTime` for a global that is a real 2-way tie.

Ownership now comes from the DEMANGLED vpWvd and cross-agrees with `recover_field_offsets`'
independent accessor route — that agreement is goldened. Rule-10 re-sweep contradicted no s112
binding; the tool now refuses more often, never less.

### 1b. A MUTABILITY axis was added, and it closes ties the handoffs called unbreakable. **NEW.**

A field-record FLAGS word of 0 is a `let`; 0x2 carries IsVar. Swift forbids assigning a `let`
stored property outside an initialiser. So when a site **stores** through an offset global and the
storing body is a METHOD, every `let` candidate is eliminated.

- **`ReadCacheIOContext` 0x1044f6918 is `eof`.** `fileSize()` @0x101bad320 does
  `strb w9,[x21,x8]` at 0x101bad50c, the trie names that address as a method, `onlyCache` is
  flags=0 and `eof` is flags=2. The s113 handoff said this tie must STAY OPEN because both
  SEMANTIC readings were defensible — and semantics never had to enter it.
- **`CacheIOContext` 0x104c63938 fell 7 → 6**, eliminating `saveFile`, which s62 had already
  established is a `let`.

⚠️ Gate it on BOTH conditions. An unnamed body cannot be proven to be a method, so `is_initializer`
answers True for it and no narrowing happens. `0x1044f6940`'s only store is inside the initialiser
0x101baf0cc, so the axis correctly does NOT fire and it stays a 2-way candidate — **do not close it
by elimination from `eof`.**

### 1c. `name_exhaustion_gate` verdicted ARTIFACT for a trie-NAMED member. ORDERING fixed, ROOT CAUSE NOT.

It printed `VERDICT: ARTIFACT` / *"This address has NO source counterpart. Never name it, never
write it"* for `0x101b95e68` — which the trie names as
`PreLoadIOContext.CacheOnlyIOContext.read(buffer:size:)`, a live MEMBER_MISSING row.
`is_compiler_artifact` short-circuited before ROUTES, and `export trie` is ROUTES[0]. `route_trie`
now runs first. The selfcheck missed it because it pinned only "never EXHAUSTED"; there are now two
checks, one per verdict.

**The root defect is still live and is the next tool unit.**
`classify_compiler_helpers.is_vwt_base` reads a CLASS METADATA vtable as a value-witness table:
its size/stride test at base+0x40 / base+0x48 is satisfied by the first two entries of the class's
FIELD-OFFSET VECTOR (0x18 and 0x28 for CacheOnlyIOContext, metadata 0x1044f4180, FOV 0x1044f4238).
It propagates through the W2 signal — `0x101b9089c` verdicts ARTIFACT purely because "value witness
0x101b95e68 calls it".

✅ **Blast radius on recorded data is ZERO, and that is measured, not assumed:** all 116 addresses
in `blocker_classification_s112.json` are absent from the trie (they are *unnamed callees* by
construction), so ARTIFACT ∩ trie-named = 0 and no recorded verdict can flip. The defect only bites
when the gate is run on a ROW address.

---

## 2. Premises that were REFUTED. Do not re-derive them.

s113 ran five gathering agents, one MEMBER_MISSING row each. They refuted three things this
programme had been carrying:

1. **`CacheOnlyIOContext` is NOT `metadata_init=1`.** It has a static field-offset vector — 8
   fields, InstanceSize 0x70, `entryListProvider` 0x18 / `endProvider` 0x28 / `eofProvider` 0x38 /
   `logicalPos` 0x48 / `sourceContext` 0x50 / `allowNetworkFallback` 0x58 / `requestedBytes` 0x60 /
   `maxNetworkBytes` 0x68. `CacheFileEntry`, `CacheIOContext` and `PreLoadIOContext` are.
2. **This module's initialisers do NOT all write through constant offsets.** `0x101baf0cc` writes
   five `ReadCacheIOContext` fields through offset GLOBALS; only `download` at +0x18 is reached at a
   constant offset. **So the A2 constant-offset-correspondence route yields no both-ways field on
   that class** — it was tried and it is exhausted, not merely unattempted.
3. **Neither `ReadCacheIOContext` byte field is a `Bool?`.** Both records are plain `Sb` with no
   `Sg`, and nothing anywhere compares either against 2. The handoff's "look for a 3-valued tag
   compare" route is CLOSED for this class.

---

## 3. Work order

| # | unit | why |
|---|---|---|
| 1 | Adjudicate the two drained waves into `wave_exclusions.json` | small, fully specified, clears ANOMALY 2 → 0 |
| 2 | `classify_compiler_helpers.is_vwt_base` | §1c root cause; a false VWT poisons every callee through W2. **The discriminator is found — see below** |
| 3 | `ReadCacheIOContext` 0x1044f6910 | 5 → 3 after the mutability axis: `end`, `urlPos`, `entryCache`. Closing it opens `fileSize`, `read` AND `seek`, three rows at once |
| 4 | `CacheIOContext` 0x104c63938 | **now TWO: `eof` or `_isClosed`** — see `fb879df`. Both Bool, both var, both default false; width, mutability and the default axis are all spent, and the file-private cross-file test came back negative (all nine accesses are in CacheIOContext.swift). Neither has an accessor. |

### Unit 2's discriminator is already found — it needs the POSITIVE anchor, not the idea

`is_vwt_base` accepts any base whose first 8 words point into `__text` and whose +0x40/+0x48
satisfy `0 < size <= stride`. The **ValueWitnessFlags word at +0x50** rejects the false ones and
s113 measured it on the exact failing case:

| base | size | stride | flags | alignment mask | verdict |
|---|---|---|---|---|---|
| `0x1044f41f8` (inside CacheOnlyIOContext's metadata) | 0x18 | 0x28 | `0x00000038` | **56** | must REJECT — 56 is not `2ⁿ−1` |

A real value-witness table always carries a valid alignment mask in the low 8 bits of +0x50, so
requiring `((align + 1) & align) == 0` is sound and only ever rejects non-VWTs. Those two "pointers"
at +0x40/+0x48 are just the first two entries of that class's FIELD-OFFSET VECTOR.

⚠️ **Do NOT land it on that alone.** Tightening this predicate makes FEWER things classify as
compiler helpers, which is the direction that lets a real artifact through, so it needs a POSITIVE
golden — a known-good VWT that still passes — and s113 could not anchor one: reading a class's VWT
pointer at `metadata − 8` returns `KeyError: 'data'` from the Ghidra reader for both classes tried,
and the `is_value_witness` search from the selfcheck's own anchor `0x101baf98c` finds no VWT base at
all. Get a real VWT in hand FIRST, then tighten, then rule-10 re-sweep. The payoff is
`0x101b9089c`, whose ARTIFACT is false and which gates the fully-derived `CacheOnlyIOContext.read`.

⚠️ **`rank_member_missing --ready` is the readiness oracle. Do NOT sort the triage by raw
instruction count and pick the top row.** s113 did exactly that and burned a cycle on
`LimitCountPreLoadIOContext.preloadCount` — 18 instructions, body read end to end, both field
globals resolved (0x1044f4ac0 = `moreCount`, 0x1044f4ac8 = `maxMoreCount`, by the mutability axis;
both `UInt16`, __got 0x104112ad8 binds `_$ss6UInt16VMn`). It does not compile, because
`preloadCount` is not declared anywhere on the superclass chain: the override table puts its base
method on `PreLoadIOContext`, and `LimitPreLoadIOContext.preloadCount` @0x101ba1cdc is itself a
591-instruction MEMBER_MISSING row. The ranker already knew — its own selfcheck uses this exact row
as its "a callee that is itself a queued row is a DEPENDENCY" anchor. **The 18-instruction body is
ready to paste the moment the 591-instruction base lands**, and that derivation is banked in this
paragraph so it is not redone.

⚠️ **Pick from the UNIT cost, never a row's `instr` column.** Two live examples from s113:
`registerRemoteControllEvent` is ranked 648 instructions and is really 648 **plus twelve
`[weak self]` handler closure bodies**, every one NOT_IN_TRIE (0x1019d3690, 0x1019d37ec,
0x1019d38f8, 0x1019d3a68, 0x1019d3ba8, 0x1019d3cb4, 0x1019d3da8, 0x1019d3f24, 0x1019d40b8,
0x1019d42cc, 0x1019d44e0, 0x1019d4684) — it is not one unit. `MetalSubtitleView.draw` is ranked 242
and carries a 16,112-byte inline closure.

**Rows to leave alone, with the reason:**
- `AssIncrementImageRenderer.flush` — 71 instructions, the cheapest ready row, and its only helper
  is `0x10245f0e0`, libass. Both matching routes are already refuted; it is a known dead end.
- `CacheIOContext.clearOtherCache` — body transcribed verbatim in the source comment, blocked ONLY
  on `tmpURL`'s optionality, whose own blocker is the value built at 0x101b8745c in the designated
  init. The field record's tail is EMPTY (no `Sg`), so the binary says plain `URL`.
- `KSMEPlayer.sourceDidOpenedSync` — derived end to end by an agent, blocked on an AMBIGUOUS-29
  `MEPlayerItem` field global (0x1044ea218).

---

## 4. A divergence found in passing that is its own unit

`runOnMainThread` is declared in `Utility.swift` as `block: @escaping @Sendable () -> Void`. The
trie names the whole signature at 0x101a03e88 as
**`runOnMainThread(block: @Swift.MainActor @Sendable () -> ())`** — mangle `yyYbScMYcc`, carrying
`Yb` AND `ScMYc`. The declaration drops the `@MainActor`, which is also why its `Thread.isMainThread`
arm is a bare `block()` where every inlined copy in the binary calls `MainActor.assumeIsolated`.

The correction was measured, not guessed: **of 30+ call sites it breaks exactly ONE**,
`AudioBaseOutput.swift:179`, where a non-Sendable `AudioBaseOutput` would then have to cross into a
`@MainActor` closure. Making that compile needs `AudioBaseOutput` declared Sendable — and Sendable
is a MARKER protocol that emits no conformance descriptor anywhere in this image (0 across the whole
module), so the binary can neither confirm nor deny it. Writing it would be inventing a type, so
s113 reverted the change and PINNED the dependent statement instead
(`KSAVPlayer.readyToPlay`'s main-actor hop, which is otherwise fully derived and ready to
transcribe the moment this lands).

---

## Close out

- Update `handoff_baseline.json` with a `captured_session114` block.
- Write the session 115 handoff.
