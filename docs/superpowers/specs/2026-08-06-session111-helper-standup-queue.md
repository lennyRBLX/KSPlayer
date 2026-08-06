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

## Four more RESOLVED: outlined value witnesses the classifier missed

s110 §5 already describes this shape — `__swift_instantiateConcreteTypeFromMangledName` followed by
a dispatch through a VWT slot (+0x0 initBufferWithCopyOfBuffer, +0x8 destroy, +0x10 initWithCopy,
+0x18 assignWithCopy, +0x20 initWithTake) is an outlined value-witness function with no source
counterpart. `classify_compiler_helpers.py` misses these because the instantiation is reached
through a HELPER (`0x10002d984`) rather than emitted inline, so the body looks like ordinary code.

`0x101baf98c` and `0x101b95200` are byte-identical in structure:

    x19 = dest, x20 = src
    x0 = <cache global>, x1 = <__TEXT,__const mangled-name pattern>
    bl 0x10002d984                       ; instantiate concrete type from mangled name
    x8 = metadata[-0x8]                  ; the VWT
    x8 = VWT[0x20]                       ; initializeWithTake
    blr x8  (dest, src, metadata) ; return dest

Screened all 41 shared members for it (VWT fetched via `metadata[-0x8]`, an instantiation helper in
the call set, <=40 instructions):

| helper | instr | witness |
|---|---|---|
| `0x101abff3c` | 20 | `initWithCopy` |
| `0x101b95200` | 20 | `initWithTake` |
| `0x101b9bfb8` | 18 | `destroy` |
| `0x101baf98c` | 20 | `initWithTake` |

Disposition: **never write**.

**Queue: 37 shared members + 14 UNSURE = 51 units.** 42 of the 117 callees are now HELPER.

## The 14 UNSURE, screened the same way

Applied both screens the SOURCE set already got — the call-site census and the tail-branch shape.
(The thunk screen had only ever run over the 72 SOURCE; the UNSURE set never saw it.)

All 14 are SHARED — none is single-call-site — so none folds into a caller. Two resolve anyway:

  · `0x1019ac888` — 3 instructions, **49 call sites**: `adrp/ldr` a `__got` value into x4, then
    `b 0x1019b02b0`. A tail-branch argument-setup thunk. **Never write.**
  · `0x1030c0994` — 93 instructions, **42 call sites**, and it sits at `0x1030c…`, inside the
    FFMPEG/library region of `__text`, not KSPlayer's. It is not a private member of anything and
    cannot be "stood up": it is an FFmpeg symbol, and its unit is a NAMING one.
    `ffmpeg_name_oracle` returns **6 candidates** and does not narrow, so it needs the s110 §6
    treatment (this build's own headers + a log literal + call shape), not a declaration.
    It gates `HLSCacheIOContext.read`.

That leaves **12 UNSURE** needing genuine adjudication, all in KSPlayer's own range and all shared:
`0x1019b1080` `0x1019b3b50` `0x1019c4720` `0x1019c80fc` `0x1019d5bd8` `0x101a31310` `0x101a460e8`
`0x101a5960c` `0x101a767a8` `0x101ab2540` `0x101ab2de4` `0x101b91580`.

**Queue: 37 shared members + 12 UNSURE = 49 units**, plus one FFmpeg naming unit.

## Name recovery across all 49: exactly ZERO usable names — and an s110 verdict REFUTED

Ran `recover_swift_function_name` over all 49 remaining units. 11 returned a candidate; 10 are
three-character garbage (`zpl` x4, `Hql`, `ppl`, `Bel`, `jcl`, `nkl`) picked out of body bytes.
The eleventh is the one s110 §6 recorded as the rule's GENUINE example:

    0x1019c7454  confidence=high  #function: pictureInPictureViewController

**It is a false anchor, and the s110 trust rule cannot see it.** The rule is "an early in-body
materialisation whose loaded length matches". That holds here: `mov x0,#0x1e` = 30 with the
`movk #0xd000` large-string discriminator, and the literal read from 0x103d349e0 is genuinely
`pictureInPictureViewController`, exactly 30 characters. The rule fires, and it is WRONG.

What it misses is what the string is FOR. The body passes it to a protocol witness at `[x1+0x30]`
and `swift_dynamicCast`s the result (`0x10345cc7c`, flags `w4=6`). That is a **lookup by string
key**, not a logging default argument. Its sibling `0x1019c7410` — s110 already decoded it as
"dispatches PiP req1 with the literal `delegate`" — has the IDENTICAL shape: it builds the small
string `delegate` (`64 65 6c 65 67 61 74 65`, `0xE0|8`) and dispatches a witness at `[x2+0x10]`.
The same rule applied there would "recover" the name `delegate`.

**The discriminator the rule is missing: a real `#function` default argument never travels alone.**
It arrives with `#file` (and a line). The outlined KSLog body `0x101a4b20c` carries
`#file: KSPlayer/MEPlayerItem.swift`; `0x1019c7454` reports `#file: None`. A length-matching string
with no `#file` companion is DATA the function uses, not the function's own name.

So: **0 of 49 units have a recoverable name.** The `#function` route is exhausted for this queue.
The 37 shared members are real private members whose names are not in the trie and not in a
`#function` literal; what remains for them is the objc-selector route, or a `⚑` pin. That is a
conclusion about the queue, not a failure to look.

## All three naming routes, measured to exhaustion

| route | result over the 49 |
|---|---|
| `#function` literal | **0 usable.** 11 candidates: 10 three-char garbage, 1 refuted false anchor (above) |
| objc selector | **0 usable.** 39 units send no selector at all; 5 send exactly one but across 13-41 calls, so the selector is one call inside a larger body, never the 2-instruction tail-call shape that named `KSPictureInPictureController.start` |
| `#file` origin | names the FILE, never the member — MEMORY is explicit that this is evidence of origin only |

The `#file` route came closest and still fails. `0x1019a26a8` (7 sites, 107 instr) and `0x101a3e510`
(8 sites, 128 instr) both report `#file: KSPlayer/Utility.swift`, both send `isMainThread`, and both
allocate a closure context, `swift_weakInit` a captured self, and materialise `ScM`/`ScP` (MainActor
/ TaskPriority) metadata. That is unmistakably a main-thread dispatch helper declared in
Utility.swift — and `Utility.swift:368` declares `public func runOnMainThread(block:)`.

**It still cannot be named.** `runOnMainThread` has ZERO entries in the export trie, so nothing
connects the address to the spelling except the shape, and shape is not a name. Both also call
`0x101a04674` and `0x101a03fd4`, the Task-closure helpers the s108 SubtitleModel work is off-limits
on.

### So every remaining unit's DISPOSITION is now decided, and it is `⚑` pin

That is a real outcome, not a shortfall: MEMORY rule 2 exists precisely for a value that cannot be
read, and this document's own disposition rule says a helper whose name is not independently
recoverable stays a pin rather than a guess. What CANNOT be done is declare 37 named private
members — every name would be invented, and rule 1 forbids exactly that.

**Final state: 49 units, all with a determined disposition of PIN.** Standing them up as named
members requires evidence that does not exist in this binary.

## Two further routes closed, with the negatives PROVEN rather than assumed

**objc method-list IMP — 0 of 49, and it is a real negative.** The vtable check structurally
misses `@objc` members (they get an objc IMP and no vtable slot), so this was the population that
could still have been named by its selector. Scanned all 220 classes: 25 decode a method list
(166 methods), 111 have no metadata accessor, 84 have none. **No unit is an IMP.**

⚠️ The count initially looked untrustworthy: 80 classes reported `entsize=0xfeedfacf count=16777228`,
which is the **Mach-O 64 magic and CPU_TYPE_ARM64** — i.e. a pointer resolving to the image header.
That is not a pointer-form method list the decoder refuses; the raw field is simply zero
(`RAW[ro+0x20] = 0x0` for `AbstractAVIOContext`, `Anime4KPipeline`), and
`method_source_presence._chained_ptr` returns image-base+0 instead of None. A genuine NULL prints
as garbage. `MetalSubtitleView`'s real list reads `0x103474da8` and decodes fine, which is the
control. **The defect is cosmetic for this question but it makes a true negative look like a
coverage gap** — worth fixing before someone reads it the other way.

**`#line` extraction — applies to 2 of 49 and yields nothing.** Only `0x1019a26a8` and
`0x101a3e510` carry a `#file` at all (both `KSPlayer/Utility.swift`). Their small immediates are
`[2, 22]`; 2 is the `LogLevel` case index this tree already documents, and a real `#line` shows up
as a large immediate (`READING_THE_BINARY` records `w6 = 0x398 = 920`). Neither call carries a line.

### Routes now closed against this binary

| route | result |
|---|---|
| export trie | absent by construction — these are the unnamed set |
| `#function` literal | 0 of 49; the one high-confidence hit refuted as a KVC key |
| objc selector (sent) | 0; no unit has the tail-call-to-selector shape |
| objc IMP (defined) | **0 — proven negative, all 220 classes scanned** |
| vtable / method-descriptor elimination | 1 candidate, unnameable (nothing left to eliminate against) |
| `#file` + `#line` | 2 of 49 have a file, 0 have a line |

What remains are inference routes against the upstream source tree (address ordering between named
neighbours; unique string literals grepped upstream). Both name from UPSTREAM, and Forward is a
fork that demonstrably renames — `IOSVideoPlayerView`'s UI layer shares not one method name with
it. Under rule 1 a hit there is a hypothesis carried as a `⚑` pin, never a declaration.

## Route C — caller-set evidence (27 of 50 have >=2 NAMED callers)

Decoded every BL to each unit and named the enclosing function from the trie. This does not name a
helper, but it constrains it far harder than any single string, because the caller SET is a
signature. Recorded as pin evidence:

| unit | named callers | what the set says |
|---|---|---|
| `0x101b91580` | 11 | `CacheIOContext` .init/.read/.seek/.close/.addEntry/.addNewEntry/.firstEntryContain/.firstEntryAfter/.firstEntryEqual/.firstEntryIndexContain/.cachedTimeRanges — i.e. essentially EVERY method of the class. A shared internal utility of `CacheIOContext`, not a feature helper. |
| `0x101a3e510` | 5 | `KSMEPlayer` .reset/.seek/.play/.pause/.stop — and it sends `isMainThread` and materialises `ScM`/`ScP`. A main-thread dispatch helper. |
| `0x1019a26a8` | 3 | `KSAVPlayer` .seek/.update(loadState:)/.replaceCurrentItem — same `isMainThread` + MainActor shape. The KSAVPlayer counterpart of the above. |
| `0x1019b3b50` | 5 | `KSOptions` .init/.appendHeader/.appendAVPlayerHeader/.removeHeader/.setCookie — a shared HTTP-header-dictionary helper. |
| `0x1019c9a68` | 3 | `KSPlayerLayer` .set(url:options:)/.replace(item:url:)/.replace(playerItem:) — shared item-swap setup. |
| `0x101a86ea4` | 3 | `PlaneDisplayModel`/`DoviDisplayModel`/`SphereDisplayModel` .set(frame:encoder:), and its only selector is `setFragmentBuffer:offset:atIndex:` — a shared Metal encode step. |
| `0x101b94fd4` | 3 | `CacheIOContext.cleanupOldCaches` + both `CacheFileEntry.init` overloads — a shared cache-file path helper. |
| `0x101ab2540` | 4 | `KSPlayerLayer` .reset/.stop/.select(subtitleInfo:) + `SubtitleModel.rebindSelectionIfNeeded` — subtitle-selection teardown. |

Every row above is a `⚑` pin with evidence, NOT a name. The caller set says what the helper is FOR;
it does not say what Forward called it, and rule 1 governs the difference.

## Route D — string literals grepped against the tree (16 of 50 carry one)

Two results, one of them a reclassification:

**`0x10245e7d8` and `0x10245f0e0` are libass, not Swift.** They carry `Event at %lld, +%lld: %s`
and `Event format header missing` — libass event-parser messages. Both sit in a large unexported
gap (nearest Swift symbols are `DanmakuKit` at 0x101c18244 and `SwiftyBeaver` at 0x1033952b0,
megabytes away), which is what statically-linked C looks like in this image. They gate
`AssIncrementImageRenderer.add / flush / updateTextStyle`. They are **not standable Swift members**;
like `0x1030c0994` their unit is an FFmpeg/libass NAMING one.

**`0x101a9f27c` confirmed as `FFmpegSubtitle.init(url:)`.** Its literal `can not judge stream`
appears in exactly ONE file in the tree — `FFmpegSubtitle.swift:68`, `throw KSPlayerError(description:
"can not judge stream")`. This corroborates s110 §4d independently, and note the file ALREADY
exists with the init sketched and the throw site addressed at :66 — so §4d's "the type must be
stood up" is stale.

The other 14 string-carrying units reference only `#file` constants or generic text
(`Fatal error`) with zero or non-unique tree hits.

**Queue after C and D: 3 units are library-code naming problems (`0x1030c0994`, `0x10245e7d8`,
`0x10245f0e0`), 1 is confirmed (`0x101a9f27c`), and the remaining ~46 carry caller-set evidence as
pins.**

## The invented-name gate (human decision, s111)

All naming routes are closed for this population, so the human authorised names invented from
PURPOSE — **as a one-off, behind a gate**. `scripts/name_exhaustion_gate.py` is that gate
(selfcheck PASS, 5 anchors). Because `play/scripts/` is gitignored, the RULE is recorded here and
in memory; the tool is not durable and must be rebuilt if lost.

### The rule

1. No invented name without `name_exhaustion_gate.py --addr <A>` returning **`EXHAUSTED`**. It runs
   all seven routes and reports each OPEN/CLOSED. Any OPEN route ⇒ the name is recoverable and
   rule 1 still governs.
2. **`INLINE-INSTEAD` is a refusal.** One call site image-wide ⇒ no independent identity ⇒ inline
   the expression, do not name it. This keeps the fabricated surface as small as the binary allows.
3. The marker grammar is deliberately different:
   `⚑[invented=<name> addr=<0xADDR> exhaustion=name_exhaustion_gate approved=<who>]`
   `invented=` is never `tool=`, so one grep separates every fabricated identifier from every
   derived fact, permanently.
4. The gate is a PRECONDITION, not an approval. It answers "is this unrecoverable"; it neither
   chooses nor blesses the name. `approved=` carries explicit human sign-off.
5. A wrong NAME costs more than a wrong body: a body is caught by the next audit against the
   binary; a name propagates into call sites and verdicts, where it reads as evidence.

### What the gate's own goldens pin

| anchor | asserts |
|---|---|
| `0x1019cc5f8` (`KSPlayerLayer.play`) | a trie-named address is `ROUTE-OPEN`, never `EXHAUSTED` |
| `0x1019c7454` | the s111 KVC-key false anchor does NOT reopen the `#function` route — length matches, `#file` absent |
| `0x101b8c114` | a one-call-site helper is `INLINE-INSTEAD`, not a naming problem |
| `0x101b91580` | a genuinely exhausted shared helper (20 sites, 11 named callers) reaches `EXHAUSTED` |
| `0x101a9f27c` | the unique-literal route OPENS where it demonstrably worked (`can not judge stream`) |

The second and fifth are the load-bearing ones: they encode the two s111 corrections directly into
the gate, so the refuted rule cannot quietly return.
