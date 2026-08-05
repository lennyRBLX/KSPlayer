# Session 111 handoff — KSPlayer / Forward-TF 1.3.17 reconstruction

**MEMBER_MISSING 76 → 70.** Six rows landed. The durable result is not the six rows; it is that the
remaining queue has been re-measured and is smaller than s110 believed, and that the real
bottleneck has moved from *reading bodies* to *recovering field offsets*.

> ORIENTATION. Derive every number below before acting on it (`recon_gate.py --mode handoff`,
> `pin_sweep.py --every`). MEMORY rule 15.

---

## 1. What landed

| commit | row | instr |
|---|---|---|
| `4f89d10` | `KSComplexPlayerLayer.play` | 77 |
| `9302da6` | `KSComplexPlayerLayer.removeRemoteControllEvent` | 181 (via 1-instr thunk) |
| `63eb29f` | `KSOptions.wantedSubtitle` | 175 |
| `7ceff55` | `LimitPreLoadIOContext.canAccessNetwork` | 113 |
| `fffa417` | `KSAVPlayer.canQuickSeek` | 116 |
| `32e302f` | `LimitPreLoadIOContext.switchToPlaybackMode` | 177 |

Each read from its address, built 4/4 alone before staging, clean commit gate.
ACCESS 26 / NOT_IN_TRIE 23 / AMBIGUOUS_OVERLOAD 10 / TYPE_DIVERGENCE 4 never moved.

---

## 2. NEW TOOL — `scripts/rank_member_missing.py` (disk only; `play/scripts/` is gitignored)

Implements the s110 §6 ranking, which had existed only as prose. `--selfcheck` PASSes on 11
anchors established before the tool. Usage:

```bash
python3 scripts/member_missing_triage.py --json /tmp/t.json
python3 scripts/rank_member_missing.py --triage /tmp/t.json --helpers /tmp/helper_verdicts.txt
```

Read the **ROW-level** "every body ready" list at the bottom, not the per-body table — a pin_sweep
row closes only when every body under it is declared (`Coordinator.isRecord` has four).

### 2a. ALWAYS pass `--helpers`, and read the EVIDENCE line

Without it the tool counts compiler artifacts as blockers. Build the cache by running
`classify_compiler_helpers.py --addr` over every distinct unnamed callee and keeping `HELPER`.
Measured over the 119 distinct unnamed callees this session: **30 HELPER / 72 SOURCE / 17 UNSURE**.
Excluding only the HELPERs moved fully-ready rows **4 → 17** and blocked rows **67 → 46**. The three
highest-fan-in helpers alone appeared in 23, 22 and 21 rows.

**Verdicts are not equally strong.**
- *Structural* (`W1`/`W2` value-witness membership, or `C2` a stdlib diagnostic string such as
  `Down-casted Array element`) — trustworthy. `canAccessNetwork` landed on one.
- *Fan-in only* (`fan-in N >= 20`) — WEAK. `0x101a04674` verdicts HELPER on fan-in 27 with no
  structural signal, and it is reached from `KSAVPlayer.readyToPlay` and
  `KSComplexPlayerLayer.change` beside `swift_allocObject` / `ScMMa` / `ScPMa` — i.e. a
  `Task { @MainActor }` closure standup, **off-limits since s108**. Treat fan-in-only as UNSURE.

The 17 UNSURE helpers are unadjudicated. Each one resolved either frees rows or correctly reblocks
them.

### 2b. It measures CALL blockers only — there is a second axis

`MetalPlayView.enterBackground` @0x101a6095c ranks READY and is not: it touches `isPaused`,
`isBackground`, `backgroundTimer` and `renderUseDispatchSourceTimer`, all in the binary field
records and all absent from Sources. Before starting a "ready" row, resolve its offset globals and
check the names against source.

---

## 3. THE BOTTLENECK — offset recovery on `metadata_init=1` classes

This is the highest-leverage next unit, and it is a TOOL unit, not a body unit.

`recover_field_offsets.py` walks NAMED accessors. Classes with none return nothing:
`recover_field_offsets --class ReadCacheIOContext` → **0 offsets from 0 named accessors**.
`field_offset_vector.py` refuses the same classes because `metadata_init=1`.

**And the static image genuinely has no answer.** Verified this session by reading the raw values:
every offset global for ReadCacheIOContext (`0x1044f6910`–`0x1044f6940`) reads **`0x0`** — they are
filled at runtime. So the answer must come from ANCHOR SITES across bodies, which is what the new
tool would have to do.

This blocks `ReadCacheIOContext.fileSize`, `MetalPlayView.enterBackground`, and most of the
PreLoadIOContext chain.

---

## 4. `ReadCacheIOContext.fileSize` @0x101bad320 — derived to the wall

218 instr. Control flow fully mapped; STOPPED on two unnameable fields.

  · `self+0x18` is an optional existential; copied out via 0x10002e588, `cbz [sp+0xa8]` is the nil
    test. Non-nil → witness `[x22+0x38]` → Int64 result in x19.
  · `cmp x19,#0 / b.le` splits: `> 0` → `csel` a `max` into global **0x1044f6910** and `strb #1`
    into global **0x1044f6918**, then return x19.
  · `<= 0` → witness `[x23+0x30]` with `x0 = -1`, `w1 = 2`; negative result → second KSLog.
  · nil path (0x101bad51c) destroys, loads **0x1044f6910** and returns it under a `tbnz #0x3f`.

**Literals decoded:** `0x103d3fe40` (41) is the `#fileID` `PreLoadIOContext/ReadCacheIOContext.swift`
— NOT a message. `0x103d3fed0` is `[ReadCacheIOContext] ffurl_seek2 `, the failure-path message.

**BLOCKER:** `0x1044f6910` / `0x1044f6918` carry no `vpWvd`, the resolver refuses both, and the
class has three `UInt64` fields (`end`, `logicalPos`, `urlPos`) with no discriminator between them.
Do NOT guess — see `[[offset-globals-not-in-field-record-order]]`. `close()` @0x101bad688 uses
globals `0x1044f6928` / `0x1044f6930` for `entryCache` / `download`, confirming an 8-byte stride but
NOT a mapping.

---

## 4a. `MetalPlayView.enterBackground` — now unblocked; the init WAS locatable

`locate_class_init --class MetalPlayView` answers "0 construction sites found", which reads like a
dead end and is not. The inits are in the trie by ADDRESS — go through `address_multimap` and
filter for `cfC`/`cfc`:

    0x101a5ed78  MetalPlayView.__allocating_init(options:)
    0x101a5eda8  MetalPlayView.init(options:)          <- designated, 436 instr

Inside it, at **0x101a5f144**:

    0x101a5f138  ldrb w8, [x28, x19]      ; a Bool read out of `options` (x28)
    0x101a5f140  ldr  x9, [0x1044ea928]   ; = renderUseDispatchSourceTimer's offset global
    0x101a5f144  strb w8, [x25, x9]       ; self.renderUseDispatchSourceTimer = that Bool

So the last blocking field IS assigned from `options`. ⚠️ REMAINING STEP: resolve x19's own global
(the `adrp` feeding 0x101a5f120) to name the KSOptions field. `KSOptions.renderUseDispatchSourceTimer`
exists at KSOptions.swift:210 with a matching type, but that is a same-name inference — CONFIRM the
global before writing it.

The other three fields are fully read and need no init:
  · `isPaused: Bool = true`   — vpfi 0x10002c740 `mov w0,#1`; the init re-emits it at 0x101a5eea4
  · `isBackground: Bool = false` — vpfi 0x10002dab0 `mov w0,#0`; re-emitted at 0x101a5ef34
  · `backgroundTimer` — vpfi 0x10199ae4c, 90 instr: `DispatchSource.makeTimerSource` with
    `DispatchQueue.main` and a `TimerFlags` built from an EMPTY sequence. Whether the source spells
    `flags: []` explicitly or relies on the default is NOT decidable from the inlined call.
    Field-record type is `So24OS_dispatch_source_timer_p`, i.e. `DispatchSourceTimer`, a `let`.

Binary field ORDER (l2_field_gate surface), from `fieldrec --class MetalPlayView`:
`isPaused, formatDescription, fps, rotation, pixelBuffer, options, renderSource, drawable,
metalView, dovi, isBackground, displayView, displayLink, backgroundTimer,
renderUseDispatchSourceTimer, flickerDetector, forcedFrameRetryScheduled` — note source currently
opens with `isDovi` where the binary has `isPaused`, a PRE-EXISTING divergence not to be conflated
with this standup.

`enterBackground` @0x101a6095c itself is fully read: sets `isBackground = true`, returns early if
`renderUseDispatchSourceTimer` or `isPaused`, else
`backgroundTimer.schedule(deadline: .now(), repeating: 1/Double(fps), leeway: <injected tag>)`.

---

## 5. Rows still genuinely ready (structural helpers only)

`CacheIOContext.copyPreloadCache` 413 · `LimitPreLoadIOContext.preloadCount` 591 ·
`CacheOnlyIOContext.read` 622 · `CircularBuffer.seek` 647.

Nothing under 200 instructions remains. `CircularBuffer.seek` is the UNSPECIALIZED generic body —
every value operation goes through value witnesses, and all its field touches are constant offsets
matching the documented source order, so it does NOT hit the §3 bottleneck.

---

## 6. Techniques that paid this session

**An ICF-shared sibling is the best oracle you have.** `KSComplexPlayerLayer.play` was read against
the `pause()` s109 landed: same `pipController` witness `0xf8`, same req4 `0x28`, and
`setPlaybackState:` 1 vs 2. The pairing made both readings evidence rather than one lookup.

**Count the call, don't assume the hoist.** `removeRemoteControllEvent` re-sends
`MPRemoteCommandCenter.shared()` twelve times; a `let center = …` emits one. Same rule caught
`wantedSubtitle` recomputing `Locale.current` inside its loop, and `canQuickSeek` building its
`CMTime` inside the closure.

**A nil/nil branch that reaches the MATCH exit proves an OPTIONAL comparison.** That is what fixed
`wantedSubtitle`'s spelling as `.flatMap` rather than `if let`.

**Descriptor absence decides placement.** `canQuickSeek` has exactly one trie symbol and no
`method descriptor` ⇒ no vtable slot ⇒ extension member, not class body.

**A default argument can be the whole explanation.** `switchToPlaybackMode`'s `cmp w8,#3` gate is
`KSLog`'s own `level.rawValue <= KSOptions.logLevel.rawValue` folded to a tag compare, and index 3
is `.warning` — which is `KSLog`'s DEFAULT, so the source passes no level argument at all.

**Interpolations may read the STORED property, not the parameter.** `switchToPlaybackMode` logs
`self.maxFileSize` after the conditional store, via a fresh `beginAccess` through the field's own
offset global. Spelling it `\(maxFileSize)` compiles and is wrong.
