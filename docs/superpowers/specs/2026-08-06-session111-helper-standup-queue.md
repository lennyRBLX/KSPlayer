# Session 111 — the private-helper standup queue, derived

Every number here is emitted by the script that produced this file, never transcribed by hand.
Regenerate with: `member_missing_triage.py --json T` -> `rank_member_missing.py --triage T`
-> `classify_compiler_helpers.py --addr` per distinct unnamed callee -> re-rank with `--helpers`.

## Shape

| quantity | value |
|---|---|
| MEMBER_MISSING rows | 68 |
| rows blocked on >=1 unnamed callee | 44 |
| DISTINCT unnamed callees behind them | 117 |
| ... classified HELPER | 29 helpers, 142 row-blockings |
| ... classified SOURCE | 72 helpers, 83 row-blockings |
| ... classified UNSURE | 16 helpers, 22 row-blockings |

`HELPER` = outlined value-witness / shared runtime helper with NO source counterpart. It must
never be named or written (s110 handoff §5). Those 29 are not work; they are noise the ranker
previously counted as blockers.

## The queue: SOURCE helpers by fan-in

Fan-in is how many BODIES call the helper; the rows column is DEDUPED, so the two can differ when
one row has several bodies (`0x1019c9cd4` reads 4 against 3 rows because `KSPlayerLayer.replace`
has two). Order by fan-in: the head of this list is worth several rows each, the tail is one.

⚠️ Standing one of these up does NOT always mean declaring a named private member. These helpers
are absent from the export trie, so their NAMES cannot be read, and MEMORY rule 1 forbids writing
a name that was not read. Two dispositions, and the choice is per helper:
  · **inline** — the compiler outlined a source-level expression. The faithful spelling is that
    expression at the call site, and no name is needed. A fan-in of 1 is weak evidence for this.
  · **named private member** — only when the name is independently recoverable (a `#function`
    literal whose loaded length matches, a `KSLog` file/line argument, an objc selector). See
    `[[recover-swift-function-name-false-anchors]]`: two of three confident hits on these were
    false. Where the name is not recoverable, the helper stays a `⚑` pin, not a guess.

| helper | fan-in | rows it gates |
|---|---|---|
| `0x1019c9cd4` | 4 | KSPlayerLayer.changePlaybackTime, KSPlayerLayer.replace, KSPlayerLayer.reset |
| `0x1019c7410` | 2 | KSComplexPlayerLayer.reCheckSubtitle, KSComplexPlayerLayer.stop |
| `0x1019c7454` | 2 | KSComplexPlayerLayer.pictureInPictureControllerDidStartPictureInPicture, KSComplexPlayerLayer.reCheckSubtitle |
| `0x1019c9a68` | 2 | KSPlayerLayer.replace |
| `0x1019d1d70` | 2 | KSComplexPlayerLayer.pipStart, KSComplexPlayerLayer.readyToPlay |
| `0x101b94bcc` | 2 | CacheIOContext.close, HLSCacheIOContext.parseM3U8 |
| `0x101ba3fd0` | 2 | LimitPreLoadIOContext.reuseEntry, LimitSeparatePreLoadIOContext.reuseEntry |
| `0x10245e7d8` | 2 | AssIncrementImageRenderer.add, AssIncrementImageRenderer.updateTextStyle |
| `0x10245f0e0` | 2 | AssIncrementImageRenderer.flush, AssIncrementImageRenderer.updateTextStyle |

Plus **63** SOURCE helpers with fan-in 1 (one row each):

```
  0x1019a26a8  0x1019ac164  0x1019ac5b4  0x1019ad650  0x1019afab0  0x1019b3c2c
  0x1019b611c  0x1019c1690  0x1019c1ca4  0x1019c2b50  0x1019c2c64  0x1019c2e88
  0x1019c835c  0x1019d24c0  0x1019d2bb0  0x1019d5978  0x1019d5d38  0x1019d8d28
  0x1019e1b6c  0x1019faf54  0x101a0133c  0x101a08744  0x101a1f188  0x101a1f1bc
  0x101a3e510  0x101a47ae0  0x101a4b20c  0x101a595d8  0x101a61f60  0x101a71b00
  0x101a7c2e4  0x101a7c40c  0x101a82044  0x101a8241c  0x101a824e8  0x101a8299c
  0x101a86ea4  0x101a9364c  0x101a960dc  0x101a9f27c  0x101aa0390  0x101abff3c
  0x101ac00c8  0x101ac0a90  0x101ac11ec  0x101b863f0  0x101b88480  0x101b8c114
  0x101b8d0f4  0x101b906c8  0x101b91728  0x101b94410  0x101b945b0  0x101b94910
  0x101b94b98  0x101b94c0c  0x101b94fd4  0x101b951c4  0x101b95200  0x101b9bfb8
  0x101bac9a8  0x101baedc8  0x101baf98c
```

## UNSURE — adjudicate before treating as either

| helper | fan-in | rows it gates |
|---|---|---|
| `0x101a460e8` | 3 | KSMEPlayer.reset, MEPlayerItem.resumeFromPreload, MEPlayerItem.send |
| `0x101b91580` | 3 | CacheIOContext.addEntry, CacheIOContext.close, CacheIOContext.seek |
| `0x10016cb68` | 2 | LimitPreLoadIOContext.reuseEntry, LimitSeparatePreLoadIOContext.reuseEntry |
| `0x101ab2540` | 2 | KSPlayerLayer.reset, KSPlayerLayer.select |
| `0x100036e98` | 1 | HLSCacheIOContext.read |
| `0x1019ac888` | 1 | KSOptions.removeHeader |
| `0x1019b1080` | 1 | CacheIOContext.seek |
| `0x1019b3b50` | 1 | KSOptions.removeHeader |
| `0x1019c4720` | 1 | KSOptions.removeHeader |
| `0x1019c80fc` | 1 | KSComplexPlayerLayer.pipStart |
| `0x1019d5bd8` | 1 | KSComplexPlayerLayer.finish |
| `0x101a31310` | 1 | DoviDisplayModel.set |
| `0x101a5960c` | 1 | MEPlayerItem.send |
| `0x101a767a8` | 1 | Anime4KPipeline.configure |
| `0x101ab2de4` | 1 | KSPlayerLayer.select |
| `0x1030c0994` | 1 | HLSCacheIOContext.read |

## The SOURCE 72, split again by SHAPE (added after the first screen)

A tail-branch thunk — no `bl`, no `ret`, ends in an unconditional `b` — has no independent source
identity. It IS the call site's own expression, outlined, so it is inlined rather than stood up.

| shape | count | instr sizes |
|---|---|---|
| tail-branch thunk (inline; nothing to declare) | 6 | 5, 5, 5, 8, 9, 17 |
| real body (needs a disposition) | 66 | min 8, median 75, max 2659, **total 9983** |

⚠️ Correction worth keeping: the thunk shape was inferred from the five SMALLEST entries, four of
which are thunks — `0x1019ac5b4` materialises the small string "Anime4K" (0x6e41/0x6d69/0x3465/
0x4b with the 0xE0|7 ASCII discriminator) and tail-branches. Generalising from that sample said
"many of the 72 are thunks". The deterministic screen says **six**. Sample-then-generalise is
exactly the failure mode `[[recorded-blocker-only-as-good-as-its-error]]` describes; the screen is
cheap, so run it rather than infer it.

So the real queue is **66 real helper bodies + 16 UNSURE = 82 units**, ~9983 instructions of reading.

## Two units RESOLVED: `0x101a1f188` / `0x101a1f1bc` are type metadata accessors

`classify_compiler_helpers.py` called both SOURCE. They are not. Each is 8 instructions —
`adrp/add` a class object, `bl _objc_opt_self`, `mov x1, #0x0`, `ret` — and the classes are named
from their nominal type descriptors at metadata+0x40: **`CopyTranscodeContext`** (0x1044e8da8) and
**`BSFTranscodeContext`** (0x1044e8e40). Both are root Swift classes; their word-1 chained-fixup
bind resolves to `_OBJC_CLASS_$__TtCs12_SwiftObject`.

The two-word return is a **`MetadataResponse` `{const Metadata *Value; MetadataState State}`**, and
`mov x1, #0` is `MetadataState::Complete` — not a nil second element. Proven at the CALLER rather
than argued from the shape: `OutputStreamInfo.transcode` @0x101a1addc calls it, keeps x0 as the
metatype (`mov x20, x0`) and OVERWRITES x1 on the very next instruction
(`adrp x1, 0x1044e8000 / add x1, x1, #0xbe8`). A discarded second word cannot be a return value.

So the disposition is **never write**: a type metadata accessor is compiler-generated and has no
source counterpart, exactly like the outlined value witnesses in s110 §5.

⚠️ This is a `classify_compiler_helpers.py` BLIND SPOT worth fixing at the tool: a body whose only
call is `_objc_opt_self` and which sets `x1 = 0` before returning is a metadata accessor, never
source. Screened all 66 real bodies for that exact shape — it finds **exactly these two**, so the
blind spot is narrow. (Screened rather than assumed, after the thunk over-generalisation above.)

Queue after this: **64 real bodies + 16 UNSURE = 80 units**. No ROW unblocked yet —
`OutputStreamInfo.transcode` still carries 7 other unnamed callees.

## A third unit RESOLVED: `0x101b94bcc` is a lazy witness-table cache accessor

16 instructions, and it gated TWO rows (`CacheIOContext.close`, `HLSCacheIOContext.parseM3U8`):

    ldr x0,[0x1044f3890] · cbz -> slow · ret            (cached)
    slow: x0 = got 0x104111550, x1 = got 0x104111500 · bl _swift_getWitnessTable · stlr x0,[cache]

`0x104111550` binds `_$sSSSysMc` and `0x104111500` binds `_$sSSN`, i.e. the conformance descriptor
and nominal type descriptor for **`String: StringProtocol`**. Compiler-generated; the cache-load /
`cbz` / `stlr` triple is the canonical lazy-conformance shape. Disposition: **never write**.

Screened all 63 remaining bodies for it (only call is `swift_getWitnessTable`, plus a `cbz`/`stlr`
cache): finds exactly this one.

## What the remaining 63 actually are

Profiled by call signature, so the next session does not re-derive it:

| family | count |
|---|---|
| pure leaf, no calls at all | 2 (`0x101b8c114` 25 instr, `0x1019e1b6c` 26 instr) |
| carries a `swift_once` (lazy global init) | 9 |
| has >=1 in-module call | 56 |

Size distribution (25-instruction buckets): 9 under 25 · 8 at 25-49 · 12 at 50-74 · 6 at 75-99 ·
10 at 100-124 · then a thin tail to 439, plus one outlier at 2659.

These are REAL bodies. Three compiler-artifact shapes have now been screened out exhaustively
(outlined value witness -> already HELPER; type metadata accessor -> 2; lazy witness cache -> 1),
and each screen was run over the whole set rather than inferred from a sample. **Queue: 63 real
bodies + 16 UNSURE = 79 units.** The two pure leaves are the cheapest genuine reads left.

## The structural correction: 18 of the 63 are NOT units at all

Decoded every `BL` in `__text` directly from the bytes (1,189,121 call sites; a BL is opcode
`0b100101` with a signed imm26, so the target is arithmetic, not a disassembly pass) and counted
call sites per helper.

| | count |
|---|---|
| called from exactly **ONE** site image-wide | **18** |
| called from more than one site | **45** |

A helper with a single call site and no trie name is **not a standable unit**. It has no
independent identity to declare — it is its caller's own code, outlined. It resolves only when
that caller is reconstructed, and declaring it separately would invent a private member the source
never had. This settles `0x101b8c114` (25 instr, the "cheapest pure leaf"): it is called once,
from `CacheIOContext.seek` @0x101b8abc0, so it is part of that body and cannot be stood up alone.
Its mechanics ARE readable — a pairwise scan over an 8-byte-element array returning false when two
adjacent elements share a strict sign — but that expression belongs inside `seek`.

**So the queue is 45 shared members + 16 UNSURE = 61 units, not 79.** The 18 fold into the 44
blocked rows rather than sitting beside them.

### The 45 real shared members, by call-site count

Call-site count is the right priority order here: a helper called from 16 sites is unambiguously a
real private member, and its name is the most load-bearing thing left to recover.

| call sites | instr | helper |
|---|---|---|
| 16 | 126 | `0x101a4b20c` |
| 15 | 297 | `0x1019c9cd4` |
| 10 | 11 | `0x1019afab0` |
| 10 | 67 | `0x1019c1ca4` |
| 10 | 20 | `0x101baf98c` |
| 8 | 128 | `0x101a3e510` |
| 7 | 107 | `0x1019a26a8` |
| 7 | 76 | `0x1019ad650` |
| 7 | 20 | `0x101b95200` |
| 7 | 35 | `0x101ba3fd0` |
| 5 | 84 | `0x1019c9a68` |
| 5 | 32 | `0x1019d5978` |

(full list in `callsites.json`; the tail is 2-3 sites each)

## Four more units RESOLVED: outlined `KSLog` bodies

Screened all 45 shared members for the pair `static KSOptions.logLevel` + `static KSOptions.logger`.
Four touch both, and each also builds a String, calls `_print_unlocked`, and ends at `swift_once`:

| helper | call sites | instr | baked `#file` |
|---|---|---|---|
| `0x1019c9cd4` | 15 | 297 | `KSPlayer/KSPlayerLayer.swift` |
| `0x101a4b20c` | 16 | 126 | `KSPlayer/MEPlayerItem.swift` |
| `0x101a61f60` |  4 | 439 | `KSPlayer/MetalPlayView.swift` |
| `0x101b863f0` |  3 | 102 | `PreLoadIOContext/CacheIOContext.swift` |

`KSLog` is `@inlinable`, so every call site inlines it and the compiler then outlines the shared
emission tail back out — ONE helper per file, carrying that file's `#file` constant. `#function`
is NOT baked (it varies per call site), which is why three of the four recover `#function: None`.
Disposition: **never write**. The source spells `KSLog(...)` at each of the 38 call sites.

`0x1019c9cd4` was the head of the fan-in table and gates `KSPlayerLayer.changePlaybackTime`,
`replace` and `reset` — three rows, and it is not a member at all.

⚠️ `0x101a61f60` recovers `#function: enqueue(imageBuffer:formatDescription:)` at confidence=high.
It is a FALSE ANCHOR by the s110 rule and was checked rather than trusted: there is no early
in-body materialisation whose loaded length matches (the first 14 instructions are prologue and a
`__got` load, no `mov x0,#0x26`), and the literal is the `#function` default-arg constant of a
KSLog call inside. Note in passing, NOT resolved here: the literal carries TWO labels while
`MetalPlayView.swift:544` declares `enqueue(imageBuffer:formatDescription:time:)` with THREE. That
is a possible signature divergence and belongs to its own unit.

**Queue: 41 shared members + 16 UNSURE = 57 units.**

## The address-range corroboration, and two more UNSURE resolved

Split all 117 distinct callees at `0x101000000` — KSPlayer's own code sits above it; the low
`__text` region is where this image emits shared compiler/runtime-support functions (the three
outlined value witnesses s110 §5 named are all there).

| region | count | verdicts |
|---|---|---|
| below `0x101000000` | 22 | HELPER 20, UNSURE 2, **SOURCE 0** |
| at/above | 95 | SOURCE 70, UNSURE 14, HELPER 11 |

Zero disagreement in the low region — the classifier and the range agree completely, which is what
makes the range usable as corroboration rather than as a guess. The two UNSURE there were then read
rather than assumed:

  · `0x10016cb68` — ONE instruction, `b 0x1000b6684`, a thunk into another low-region helper.
  · `0x100036e98` — 42 instructions opening `cbz x1` / `cmp x1, #0xf` / `b.hs`, the 15-byte
    small-string threshold. Stdlib-shaped, no source counterpart.

Both HELPER. Disposition: **never write**.

## Running total

| | |
|---|---|
| distinct unnamed callees | 117 |
| HELPER (never write) | **38** |
| SOURCE | 65 — of which 6 thunks and 18 single-call-site, neither a unit |
| UNSURE | 14 |
| **real standable units left** | **41 shared members + 14 UNSURE = 55** |

Rows blocked on an unnamed helper: **45 -> 43**. Bodies READY: **17 -> 19**.
