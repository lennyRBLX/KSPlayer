# Finishing the stand-up wave — a program handoff

This is **not** a session handoff. `2026-08-02-session93-handoff.md` is the next-session document and
still governs. This one scopes the run to wave COMPLETION and exists because the remaining work is
too large to sequence one session at a time, and because two decisions have to be made **before** the
remaining count means anything.

Written at the end of session 92. Every number below is a SNAPSHOT — re-derive before acting:

```bash
python3 scripts/contract_numbers.py --group state
```

## 0. The state this was written from

`recon_gate --mode handoff`: **PASS 46 / ANOMALY 0 / FAIL 3**, floor **299**, `agg_stood_up` **55**,
`git_head` fc37388, `ahead_origin` 301. The 3 FAILs are the permanent known debt (`agg_critical 15`,
`agg_high 55`, `agg_unresolved 1`).

Stand-up wave: **120 units / 23 classes / 42,189 instr** — 67 UNNAMED, 53 BINARY_ONLY,
**SOURCE_MATCH 0**. Audit wave: **6 units / 2 classes**, of which ~1 is genuinely open.

## 1. TWO DECISIONS COME FIRST. Do not start deriving bodies until both are made.

### 1a. The wave's SIZE is not yet known, because the bucket predicate is unsound

**17 of the 23 remaining classes have a source file.** Session 92 proved on `PixelBuffer` that a
class with source can have an **auditable** body sitting in the stand-up wave:
`method_source_presence` buckets on whether the METHOD can be NAMED, so a body the trie does not
name is bucketed UNNAMED/BINARY_ONLY even when the class's own source declares its counterpart and
two independent orderings select it.

This is not cosmetic. **A stand-up can never raise the faithful floor; an audit can.** Every
mis-bucketed unit is a body that looks like progress and moves the floor by zero.

**Do this first:** re-screen the 17 source-carrying classes for positional matches — protocol
requirement order and class vtable Method order against the source's declaration order, which is
the argument that worked on `PixelBuffer`. Output a list of units that move standup -> audit.

Classes worth screening in this order (source-carrying, smallest first so the technique is
validated cheaply): `KSOptions` (1 unit, **3 instr**), `SphereDisplayModel` (1/51),
`MetalSubtitleView` (1/63), `Remuxer` (1/94), `FFmpegDecode` (1/125), `DynamicInfo` (1/204),
`PlayerTransitionAnimator` (1/306), `PlayerToolBar` (1/780), `AudioSwresample` (2/795),
`LimitSeparatePreLoadIOContext` (3/1029), `LimitPreLoadIOContext` (3/1385), `HLSCacheIOContext`
(2/1391), `VideoSwresample` (5/1717), `KSSlider` (3/199), `PreLoadIOContext` (7/3391),
`Anime4K` (3/4780), `IOSVideoPlayerView` (32/9122).

**`IOSVideoPlayerView` is the known NEGATIVE control** and must come out of the screen as genuinely
BINARY_ONLY — `STANDUP_PROTOCOL` §1 records that its source declares `customizeUIComponents`,
`resetPlayer`, `onButtonPressed`, `updateUI`, `panGestureBegan` while its binary declares
`setupBottomControls`, `handleScreenshot`, `generateFFmpegMenu`, `getVideoMeta`,
`updateBatteryStatusImageView` — **zero overlap**. If a screen claims otherwise, the screen is wrong.

### 1b. "Wave complete" is currently unverifiable

`wave_worklist` prints its count as an **UPPER BOUND** and flags 3 standup + 6 audit units as
"already named in a per-body verdict field and may be DONE", because `_verdicted_addrs()` reads only
the top-level `binary_addr`. Until that resolves, the wave cannot be driven to a clean zero — it
will bottom out at a handful of units nobody can prove are finished.

**Build the adjudicated-exclusion file** that `wave_worklist` reads, with a selfcheck asserting every
entry still resolves to a real verdict FIELD. **Never a greedy free-text address scan** — that is the
s87 `bounds` defect and it would silently drop 5 LIVE units. The s88 adjudication
(`reconstruction/wave_coverage_adjudication_s88.json`) is the model and the first content.

## 2. The sequence, after those two

Ordered by "completes a class per unit of effort", which is what shrinks the wave's surface.

| # | batch | units | instr | why here |
|---|---|---|---|---|
| A | 11 single-unit classes + `KSSlider` ×3 | 14 | 2,446 | each completes a CLASS; 23 -> 11 classes |
| B | PreLoadIOContext family (4 classes) | 15 | 7,196 | one subsystem, shared shape, batch as one |
| C | Resample family (`VideoSwresample`+`AudioSwresample`) | 7 | 2,512 | one source file |
| D | `ThumbnailSession` + `MetalShaderExporter` | 6 | 6,253 | both NO SRC; budget like 10 bodies each |
| E | `Anime4K` | 3 | 4,780 | deep cluster, shader paths |
| F | `IOSVideoPlayerView` | 32 | 9,122 | all NAMED — trie gives full signatures |
| G | `SettingsView` | 43 | 9,880 | all UNNAMED — the hardest, do it LAST |
| H | audit tail: `VideoToolboxDecode` slot 29 | 1 | 572 | `deferred_to_P3` DV-crux; not a warm-up |

**Batch A is one or two sessions and is the highest-value start** — it takes the wave from 23 classes
to 11, which is the number a reader actually feels.

**Batch F before G, deliberately.** `IOSVideoPlayerView`'s 32 units are BINARY_ONLY, meaning the
export trie gives each a full demangled signature — arity, parameter types and return type come free.
`SettingsView`'s 43 are NOT_IN_TRIE with no name at all. Doing the named class first builds the
IOSVideoPlayerView-shaped idioms you will need for the unnamed one.

**Before briefing any `SettingsView` unit**, run `recover_swift_function_name.py` on it yourself and
apply the labels>=2 discriminator. Reject on `labels=0` — the `zpl` false anchor has now fired five
times, most recently on `0x103566c60`, the `Swift.TaskPriority?` mangle that every `Task { }` site
references.

## 3. The throughput problem, stated honestly

Observed: session 91 landed 6 bodies (518 instr); session 92 landed 3 (424 instr) alongside a tool
build. Call it **~500 instr/session** at the current working style. **42,189 instr at that rate is
not a handful of sessions — it is a long program.**

The rate is not limited by deriving bodies. It is limited by **orchestrator verification**, which
cannot be delegated (MEMORY rule 5) and which scales with how much an agent returns. Two consequences:

1. **Run several agents per session, one body each.** The s92 `PixelBuffer` agent handled a
   324-instruction body across 62 tool calls in ~16 minutes and returned `UNGROUNDED: 0`, and it
   independently reproduced the idx-vs-slot trap on a class the orchestrator had not touched. That is
   the shape that scales. One agent per session does not.
2. **Tooling that cuts verification cost raises throughput more than tooling that cuts derivation
   cost.** `body_fingerprint`'s un-named globals block is the s92 example: it turned "scan the
   disassembly for `adrp`/`ldr` pairs the block does not list" into reading one block. Prefer that
   kind of fix over anything else in the queue.

If the wave must close faster than that, the honest options are to narrow what STOOD_UP requires per
body, or to accept agent-derived verdicts with sampled rather than exhaustive verification. **Both
weaken the corpus and neither should be adopted silently** — they are the user's call, not a
session's.

## 4. Tool blockers that gate specific batches

| blocker | gates | note |
|---|---|---|
| vtable idx-vs-slot + `PlayerView` collision | every batch | `slot = VTableOffset + idx`; both vtable tools resolve a bare NAME to the first classmap row. Take the descriptor from `conformance_walker` or `fieldrec.desc_for_class`. Fix once, benefits all. |
| adjudicated-exclusion file | wave completion | §1b |
| `decode_witness_table --wt` crash | F, G | dies on a cross-module conformer; route around by reading witness words directly |
| classmap lacks structs/enums | C, D, E | `fieldrec.py <descriptor_addr>` works; `--class` fails on every enum |
| `name_type_at_addr` misdecode | any protocol descriptor | read the Name rel32 at `descriptor+0x08` by hand |
| `prefetch_decompiles` has no golden | all | it is on every verdict's provenance path and is unguarded |

## 5. What DONE means, and how it is verified

The wave is complete when **all** of these hold, in this order:

1. `python3 scripts/wave_worklist.py --wave standup` returns **0 units** — with the exclusion file in
   place, so the number is exact and not an upper bound.
2. `python3 scripts/wave_worklist.py --wave audit` returns **0 units** on the same basis.
3. `verdict_provenance_gate.py --class <C>` is OK for every class touched.
4. `recon_gate --mode handoff` is PASS with `agg_stood_up` matching the baseline and
   `agg_faithful` **>= 299**. The floor will have moved only by whatever §1a re-bucketed into the
   audit wave and then audited — **expect it to move very little, and that is correct.**
5. `reconstruction/handoff_baseline.json` refreshed and the gate re-run AFTER.

**A wave of zero units is not a reconstruction of the class.** These bodies are STOOD_UP: shape
recovered, no source counterpart, audited against nothing. Closing the wave ends the *inventory*
problem, not the faithfulness problem.

## 6. Explicitly OUT of scope for this program

- **New-class stand-ups: 109 units across 11 types** (`class_presence_gate`). A separate bucket,
  not in the 120. `KSComplexPlayerLayer` alone has 44 symbols in the binary and zero in the
  reconstruction. Do not fold it in without saying so.
- 13 refuted let/var bindings across 10 classes; 280 FUN_ pins (84 nameable).
- Source edits. The pre-commit `l2_field_gate` blocks on the CLASS, so two "independent" edits in one
  file serialise anyway. Land derivations as specs during the wave; apply one unit, one commit.
- `GENERATED_ACCESSOR` (322 slots) — collapses into declarations, never body work.

## 7. Standing rules that bite hardest on this program

- Cite **both** idx and slot in every verdict.
- Give every agent the vpWvd technique, its limit, and the s92 addition: **ownership must be proven
  from the anchor site**, never from adjacency or from the section alone.
- When an agent reports a tool gap, verify its stated **CAUSE** against the binary, not just the
  symptom — s91's agent got the defect right and the cause wrong.
- A reasoned identification is a finding, **not a licence** (`STANDUP_PROTOCOL` §3). It does not make
  a unit auditable and does not license a comparison verdict. `PixelBuffer` idx35 is the worked
  example: a fully derived divergence, deliberately banked rather than emitted.
- Never type a count into an agent contract — `⚑[derive=<id>]`, gate-checked by
  `sc_contract_numbers`.
