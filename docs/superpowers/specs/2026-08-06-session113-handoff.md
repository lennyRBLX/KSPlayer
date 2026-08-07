# Session 113 work

**The queue is no longer gated on naming.** s112 cleared the CALL axis twice and then screened every
remaining reachable row to a wall. The wall is the FIELD axis, there is no tool for it, and building
one is this session's job.

---

## Verify first

```bash
python3 scripts/recon_gate.py --mode handoff
```
```bash
python3 scripts/recon_progress.py
```
```bash
python3 scripts/pin_sweep.py --every
```

| what | expected |
|---|---|
| gate | `PASS 44   ANOMALY 6   FAIL 4` |
| FAITHFUL FLOOR | 333 / 1035 |
| MEMBER_MISSING | 67 |
| ACCESS | 26 |
| NOT_IN_TRIE | 23 |
| AMBIGUOUS_OVERLOAD | 10 |
| TYPE_DIVERGENCE | 4 |
| total disagreements | 130 |
| build | 4/4 |
| KSPlayer | branch `forward`, tree clean apart from 7 pre-existing untracked s98/s102/s104/s105 spec docs |
| FFmpegKit | `12f0899` on `forward-recon-shim`, 1167 tracked dirty files UNSTAGED. **Never `git add -A` there.** |

The 4 FAILs are pre-existing and were re-confirmed in s112: `sc_wave_worklist` (the OPEN
adjudication of `101a6ce44`, `wave_exclusions.json` entry 8, `adjudicated_session: 93`),
`agg_critical` 6, `agg_high` 24, `agg_unresolved` 1. No verdict file has an mtime at or after
2026-08-05; the newest is 2026-08-04 14:14.

Three selfchecks must print `SELFCHECK PASS`. All live only in `play/scripts/`, which is gitignored:

```bash
python3 scripts/rank_member_missing.py --selfcheck && python3 scripts/name_exhaustion_gate.py --selfcheck && python3 scripts/helper_fingerprint.py --selfcheck
```

`name_exhaustion_gate` must report **12** checks, not 9. s112 added three: the CSE'd-length
`#function` route, the arithmetic path itself, and a negative control. If it reports 9 the tool has
been rolled back and the fix below is gone.

1. Read `reconstruction/blocker_classification_s112.json` before any planning. It holds the
   `name_exhaustion_gate` verdict for all 116 distinct unnamed callees, the sweep method, the
   ARTIFACT caveat and the s112 gate-fix record. Do **not** re-derive it per address with the CLI —
   each process rebuilds the image-wide `bl`-target Counter. Run it in ONE process
   (`import name_exhaustion_gate; g.evaluate(va, quiet=True)`), which takes ~20 minutes.

---

## Why naming is not the bottleneck

The population is **48 ARTIFACT · 13 INLINE-INSTEAD · 46 EXHAUSTED · 9 ROUTE-OPEN**. The human
approved inventing names for the EXHAUSTED set in s112; s112 screened it and **41 are eligible**
(all inside KSPlayer `__text`; 5 are Task/actor-shaped and off-limits per s108: `0x1019a26a8`,
`0x1019c80fc`, `0x1019d2bb0`, `0x101a3e510`, `0x101a47ae0`).

That approval does not unblock the queue, because s112 closed two CALL-axis blockers and the rows
behind them still did not become writable:

- `AVSampleBufferDisplayLayer.enqueue(imageBuffer:formatDescription:)` @0x101a61f60 — name RECOVERED
  from the `#function` default argument in argument position. Landed, and it closed
  `MetalPlayView.enterForeground` (68 → 67).
- `CacheIOContext.fetchedSize`'s `didSet` @0x101b863f0 — name recovered the same way, from a
  register-built SMALL string. Landed. It cleared `readComplete`'s last unnamed callee and the row
  **still did not open**, because of the FIELD axis.

2. Read `KSOptions.swift` around the `displayEnum*` block and `CacheIOContext.swift` around
   `fetchedSize` before planning. Both carry s112's measured negatives, and one RETRACTION —
   `35d70fe` retracts a wrong claim from `c8e4fc1`. Do not re-derive the retracted inference.

---

## 3. The unit: a field-recovery tool for `metadata_init=1` classes

This is the gate on MEMBER_MISSING → 2. It is deterministic, it is reusable across many rows, and it
does not exist.

**The problem, stated exactly.** A class with `metadata_init=1` has no static field-offset vector.
Its stored-property accesses load the offset from a per-field global. Some of those globals are
exported and the trie names them outright; the rest are non-public, and on this image they sit in
`__DATA,__common`, which is **zero-fill** — the offset value is not in the file at all. So both
static routes are closed and `recover_field_offsets` correctly answers `NOT RECOVERED`.

**The route that is open.** The ACCESS SHAPE at each use site is readable and carries the type:

| shape | implies |
|---|---|
| `ldrb w` / `strb` | `Bool` or `UInt8` |
| `ldr w` / `str w` | 32-bit — `Int32`, `Float` |
| `ldr x` + `adds`/`b.vs` | **signed** 64-bit — `Int64` |
| `ldr x` + `adds`/`b.hs` | **unsigned** 64-bit — `UInt64` |
| `ldr d` | `Double` |
| load followed by `swift_retain` / `objc_retain` | a class reference |
| two-word load, second word used as a table | a class-constrained existential |

`fieldrec` gives the class's fields IN ORDER with their mangled types, so the tool can bind an
unresolved global to the set of type-compatible fields that are not already bound by an exported
global, and report UNIQUE or refuse as AMBIGUOUS.

**s112 BUILT THE FIRST CUT.** `scripts/recover_field_by_access.py` exists, `--selfcheck` reports 8
checks, and it is goldened on two KNOWN answers recovered from access shape alone with the trie
names withheld: `CacheIOContext.stopOnLimitReached` as a byte access (`ldrb` + `cmp #1`) and
`fetchedSize` as a SIGNED dword (`ldr x` + `adds` + `b.vs`). It also carries two honest negatives —
SPILLED (distinct from ABSENT) and a global the body never touches. It is documented in the durable
inventory. Three bugs were caught by its own goldens while building it and are worth not
reintroducing: taking only the FIRST materialisation of an offset (a body re-loads the same offset
into several registers, so the first cut reported SPILLED for two fields whose access is plainly
there); parsing `fieldrec`'s bytes-repr type as literal text; and hand-building the class mangle,
which fails under backreference compression (`CacheIOContext` in `PreLoadIOContext` is `05CacheC0`).

4. Extend it with SPILL TRACKING. That is the one thing standing between it and
   `CacheIOContext` @0x104c63938: in `readComplete` the offset is loaded and immediately
   `str x8, [sp, #0x20]` at 0x101b8a150, so the direct-use scan cannot see the access.

5. Add a second discriminator so it can decide, not just narrow. Run today, 0x104c63938 is
   **provably a byte-class field** — three independent bodies agree (`close` @0x101b8c83c,
   `fileSize` @0x101b8c178, `seek` @0x101b8a77c all read it with `ldrb`) — and the tool correctly
   REFUSES, because 7 candidates remain after excluding `stopOnLimitReached`: `isJudgeEOF`,
   `saveFile`, `isReadComplete`, `eof`, `_isClosed`, `isInterleaved`, `isFirstFileSize`. Candidate
   discriminators, cheapest first: which body WRITES it (`strb` of `#1` in `close` would settle
   `_isClosed`); whether the access is a 3-valued tag compare, which would settle the
   `Bool?` `isInterleaved`; and the `swift_beginAccess` flag, where 1 is a modify and 0 a read.

6. Run the extended tool over EVERY reconstructed class before trusting one result (MEMORY rule 10).
   The s112 sweep over `CacheIOContext`, `MetalSubtitleView`, `MetalPlayView` and
   `ReadCacheIOContext` returned sane maps; `MetalSubtitleView`'s independently matches the map
   proven in `f1483d3`, which is a useful ongoing control.

---

## 7. The rows it unblocks, and what else each needs

7. `CacheIOContext.readComplete(buffer:size:isReadComplete:)` @0x101b8a0f8, 412 instructions. CALL
   axis already clear. Needs `0x104c63938` named, plus the dispatch offsets `0x1e0` and `0x398` read.
8. `ReadCacheIOContext.fileSize` @0x101bad320, 218 instructions. Three globals unresolved —
   `0x1044f6910`, `0x1044f6918`, `0x1044f6928` — and all three are absent from the trie, so the
   `vpWvd` route is closed too.
9. `MetalSubtitleView.draw` @0x101ac0e24, 242 instructions plus the INLINE-INSTEAD `0x101ac11ec`
   (101 instructions) that must be inlined into it. Its three list fields are now named (`f1483d3`);
   `0x1044ef5b0` and `0x1044ed178` are still unresolved, and `0x101a83a6c` is an unnamed function
   reference taken as a global.

---

## 10. Rows to leave alone, with the reason

Do not spend the session re-discovering these.

10. `CacheIOContext.clearOtherCache` @0x101b8d948 — the TYPE trap. Body transcribed, ranker says
    READY, cannot be written: `tmpURL` is `URL?` in source where the binary's `vpWvd` has no `Sg`.
11. `KSAVPlayer.readyToPlay` @0x1019a402c and `KSComplexPlayerLayer.change` @0x1019d1890 — both read
    "ready" only because `0x101a04674` verdicts ARTIFACT on a fan-in-only signal. It is a Task-closure
    standup, off-limits per s108.
12. `AssIncrementImageRenderer.*` — cleared only by `0x10245f0e0`, which is libass. ARTIFACT is right
    for "may I invent a Swift name" and WRONG as "no source counterpart": this is C you must call by
    name. Screen every ARTIFACT on the address range (`>= 0x102000000` is library code) before
    feeding it to `rank_member_missing --helpers`.
13. `KSAVPlayer.changePlaybackTime` and the SubtitleModel Task closure — off-limits from s108.
14. `KSOptions.displayEnumVR` / `displayEnumVRBox` — 23 instructions each and still blocked. s112
    measured the full escape: removing `@MainActor` from `DisplayEnum` and both conformers leaves
    EXACTLY five unresolved references — `MotionSensor.shared` ×2, `KSOptions.sceneSize` ×3 — and
    nothing else. The MotionSensor calls are REAL (`SphereDisplayModel.init` @0x101a8bf3c carries the
    `enableSensor` gate `0x1044e5150` and the full CoreMotion sequence), so the unit is small and
    fully enumerated but not free. `let` instead of `var` does NOT help; that was measured.

---

## Tool notes s112 paid for

15. `field_offset_vector.py` needs `--module PreLoadIOContext` for that module's classes. Without it
    it looks up a `KSPlayer`-prefixed symbol, fails, and reports "no exported metadata symbol in the
    trie" — which reads as a finding about the class and is really a wrong-module lookup.
16. `decode_string_literal.py --addr <fn>` crashes on a body whose globals include a `__DATA` address
    (it tries to read `KSOptions.logger` as a string). Use `--at <addr> --count <n>` per literal.
17. `name_exhaustion_gate` has a second, still-unfixed `#function` gap: it reads pointer-form literals
    only and misses a SMALL string built in registers. That is how `0x101b863f0` reported "no
    #function candidate" while its `#function` was plainly `fetchedSize` (x4 = `fetchedS`, x5 = `ize`
    under discriminator `0xEB`). Fixing this is a smaller job than step 4 and worth doing first.

---

## Close out

18. Update `handoff_baseline.json` with a `captured_session113` block.
19. Write the session 114 handoff.
