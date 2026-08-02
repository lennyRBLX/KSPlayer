# Session 97 — parallel orchestration

You are the ORCHESTRATOR. Seven agents derive; you alone adjudicate, edit source, build and commit.
This document is the dispatch plan. It is agent-facing in part, so every prohibition below carries
the pitfall it prevents and the action to take instead — a bare prohibition gets rationalised past.

## 0. Verify first

1. `ps -Ao pid,etime,command | grep -c "MacOS/claude --output-format stream-json"` — one live session
   prints **4**. A second unrelated pair means another session is writing `reconstruction/`; stop.
2. `python3 scripts/recon_gate.py --mode handoff` — expect PASS 48 / ANOMALY 0 / FAIL 3. The three
   FAILs (`agg_critical`, `agg_high`, `agg_unresolved`) are the standing debt and are the target.
3. `python3 scripts/recon_gate.py --mode handoff --timings` if you want to know what the gate costs
   before you run it seven more times. Never quote a timing from prose; the flag derives it.
4. Re-derive every quantity with `python3 scripts/contract_numbers.py --group state`. This document
   deliberately contains almost no counts — where you want one, the command is given instead.
5. Read MEMORY.md. Read `reconstruction/AGENT_PROTOCOL.md` before dispatching anything.

## 1. The parallelism law — read this before you dispatch

**Derivation parallelises. Landing does not.** Three separate mechanisms serialise you:

- **One build at a time** (MEMORY rule 17). Agents share one `.build`. *Pitfall:* two concurrent
  builds corrupt each other's incremental state and produce a green result for source that does not
  compile alone. *Instead:* agents never run `validate_build.sh`; only you do, one at a time.
- **`l2_field_gate` blocks on the CLASS, not your diff.** *Pitfall:* two finished units in the same
  file cannot both be staged; the second inherits the first's flags and looks broken. *Instead:*
  hold a commit lock per FILE (§3) and land one unit per file at a time.
- **One orchestrator adjudicates** (MEMORY rule 6). *Pitfall:* an agent that writes a verdict is
  grading its own work, and its conclusion is indistinguishable from evidence. *Instead:* agents
  return findings; you re-verify every load-bearing claim against the binary yourself with
  `llvm-objdump` before it enters a verdict (MEMORY rule 5).

### The commit-lock table — the lanes are NOT file-disjoint

This is the trap in the lane split. Four lanes want the same files. Before landing anything, check
this table and take the lock:

| file | lanes that want it |
|---|---|
| `Resample.swift` | **A** (AudioSwresample) · **B** (AudioDescriptor) · **D** (audioFormat callee) |
| `KSOptions.swift` | **A** (idx128) · **B** (isUseDisplayLayer) |
| `KSPlayerLayer.swift` | **B** (9 units) · **C** (3 missing) · **D** (change(state:), init, delegate) |
| `FFmpegDecode.swift` | **B** · **C** · **D** (VideoSwresample.s32) |
| `IOSVideoPlayerView.swift`, `PlayerView.swift`, `KSAVPlayer.swift`, `MEPlayerItem.swift` | **B** · **C** |
| `MediaPlayerProtocol.swift` | **C** · **D** |
| `VideoToolboxDecode.swift`, `PlayerTransitionAnimator.swift` | **A** only — genuinely free |

*Pitfall:* dispatching A and B together and discovering at commit time that both edited
`Resample.swift`, so one agent's derivation is stale. *Instead:* dispatch freely — derivation cannot
collide — but land in the order §5 gives, and re-verify any finding whose file changed under it.

## 2. What every agent is told

Every dispatch inherits `reconstruction/AGENT_PROTOCOL.md` verbatim. Restate these four in the brief
because they are the ones agents violate:

- **Create no file, edit no file, touch no git index, run no build, edit nothing under `scripts/`.**
  *Pitfall:* an agent's scratch file becomes an input to a later session and nobody knows who wrote
  it. *Instead:* the returned message is the entire output.
- **Return the CLAIM / EVIDENCE / TOOL triple, then `UNGROUNDED: <n>`.** *Pitfall:* prose findings
  cost the orchestrator a re-derivation each and hide which part was actually read. *Instead:*
  verbatim tool output, trimmed to the load-bearing lines, never paraphrased.
- **Every premise in the brief is refutable — check it.** *Pitfall:* an address or owner copied
  forward from a stale handoff produces a confident audit of the wrong body. *Instead:* if the
  address does not hold the named symbol, that is the most valuable finding you can return.
- **Never recurse into a callee.** *Pitfall:* one unit silently becomes five and the context is gone
  before the original body is finished. *Instead:* report the callee's address and trie name.

**The `slot` field in every worklist is the vtable IDX, not the slot.** slot = VTableOffset + idx.
Record both as `idx<N> slot<M>`. *Pitfall:* citing the worklist number as a slot names a different,
often bodiless accessor descriptor. *Instead:* run `vtable_impl_oracle.py "$BIN" <Class>` first.

## 3. Lane A — four agents, one per audit-wave unit

⚑[derive=wave.audit_units] units across ⚑[derive=wave.audit_classes] classes. These are **fresh
audits, not queue units** — each one that lands is floor +1, and nothing else in this plan touches
them except the two file collisions above. Dispatch all four at once.

| agent | class | idx | addr | instr | file |
|---|---|---|---|---|---|
| A1 | KSOptions | 128 | `0x10002db34` | 3 | KSOptions.swift |
| A2 | PlayerTransitionAnimator | 2 | `0x101b18b50` | 306 | PlayerTransitionAnimator.swift |
| A3 | AudioSwresample | 10 | `0x101a67c34` | 368 | Resample.swift |
| A4 | VideoToolboxDecode | 29 | `0x101a6ce44` | 572 | VideoToolboxDecode.swift |

**A1 is three instructions.** Do it first and by hand if you prefer; it is the cheapest floor point
in the project. Check the ICF fold before concluding anything: a 3-instruction body is very likely
shared, and a shared address is not an anchor mismatch.

**A4 is the DV crux and carries an explicit P3 deferral.** *Pitfall:* treating a standing deferral as
undone work and reconstructing it anyway. *Instead:* derive it, return the findings, and adjudicate
whether the deferral still holds before writing any source.

Brief for each: derive the body at `<addr>` against its source counterpart in `<file>`. Report the
extent from `function_extents.py`, the trie name and fold count, every call target with its resolved
name, and each source statement that has no counterpart or vice versa. Do not rate severity.

## 4. Lanes B, C, D — one agent each

### Lane B — the DIVERGENT queue

The live queue is `reconstruction/divergent_queue_s94.json`. Recompute what is open — never trust a
count in prose:

```bash
python3 scripts/stale_divergence_screen.py --misplaced
```

Then per unit read the verdict's `divergences`, re-derive each claim, fix source, rebuild, re-audit.
Order the agent's work by file so you can land whole files at a time. `KSPlayerLayer.swift` is the
largest concentration of floor and the most serialised — give the agent its units last, after lane D
has settled `change(state:)`, because several of them share that premise.

**Three units are coupled and must not be started as written:** `AudioDescriptor_updateAudioFormat`
(needs the 190-instruction callee `0x101a68c44` audited first — lane D owns it),
`FFmpegDecode_decodeFrame` (coupled to `VideoSwresample.s32`), and both
`KSPictureInPictureController` units (the binary class has zero stored properties; it is a
class-level reconciliation, not a per-slot edit). *Pitfall:* a two-HIGH unit that looks like a
one-line signature fix but whose consequent body nobody has read. *Instead:* audit the callee first
and land the pair as ONE unit.

**`source_lines` drifts and is unmaintained.** *Pitfall:* editing at the cited range lands in a
comment or mid-body. *Instead:* locate the method by NAME.

### Lane C — methods Forward has that our source does not

```bash
python3 scripts/file_placement_sweep.py --json    # the NOT_IN_SOURCE rows
```

Each row is a body the trie names, whose Forward FILE the sweep already tells you, absent from our
source entirely. This lane RECONSTRUCTS methods rather than repairing them. Start with
`FFmpegUtility+Thumbnail.swift` (the densest, and a Forward file we do not have at all — the sibling
`FFmpegUtility.swift` was created in s95, so the naming evidence is already settled) and
`MediaPlayerProtocol.swift` (protocol extension getters; small and independent).

*Pitfall:* inventing a signature for a method that has no source counterpart to check against.
*Instead:* the trie gives the full demangled signature; take labels and types from it, and pin
anything the binary does not show.

### Lane D — structural unblockers

Each releases several units elsewhere, so this lane runs FIRST among B/C/D:

1. `change(state:)` idx58 `0x1019cc0ac` — no source counterpart; the `state` willSet is inlined at
   every write. Shared premise under several KSPlayerLayer units. **Highest leverage in the project.**
2. `MediaPlayerDelegate` has 8 requirements in the binary (descriptor `0x1039ed850`) against 5
   declared. Witness table `0x1041d49b8`.
3. KSPlayerLayer's designated init is `init(url:options:delegate:)` — three parameters, not four —
   at `0x1019ca41c`.
4. The PlayList protocol (blocks `FormatContext_inner_init`).
5. `KSPictureInPictureProtocol`, 10 requirements, descriptor `0x1039ecde0` — blocks `pipController`
   in two classes and both PiP queue units.
6. `AudioDescriptor.audioFormat` `0x101a68c44`, 190 instructions — blocks the Resample queue unit.
7. `VideoSwresample.s32` `0x101a67274` — blocks removing FFmpegDecode's relocated side-data loop.

## 5. Your landing loop, per unit

Agents may be mid-flight throughout; only this loop touches the tree.

1. Re-verify every load-bearing claim against the binary yourself. An agent conclusion is not
   evidence; raw tool output is.
2. Take the file's commit lock (§1). Edit source.
3. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/validate_build.sh all` → 4/4.
   The pre-commit hook now builds too (Gate 0), but it builds the working TREE, not the staged
   content — so staging a subset still needs your judgment.
4. `python3 scripts/verdict_provenance_gate.py --class <C>` for every class touched.
5. `git add` the unit's files, then `python3 scripts/recon_gate.py --mode commit`.
6. `bash scripts/commit_unit.sh -F <msgfile>` — never a bare `git commit`. *Pitfall:* git exits 0
   when the pre-commit hook blocks, so a bare commit cannot tell you whether it landed. *Instead:*
   the wrapper compares HEAD and fails if it did not move. `--no-verify` reaches git only through
   `commit_unit.sh --deferral <file>`, and a support-class block never justifies it.
7. `python3 scripts/adjudicate_verdict.py --id <id> --final FAITHFUL --overturned --evidence "$(cat <file>)"`.
   Pass evidence via `$(cat …)`. *Pitfall:* `command_shape_hook` matches the whole command line and
   cannot tell a citation from an invocation, so evidence prose naming a tool is blocked. *Instead:*
   write it to a file first. The same applies to any commit message that names a tool.

## 6. Lane E — inline, and ONLY after every agent has returned

`prefetch_decompiles.py` has **no golden** — no `test_prefetch_decompiles.py`, no `--selfcheck` —
and it sits on the provenance path of every verdict in the corpus.

**It must be last, and this is not a preference.** MEMORY rule 7: never edit a tool while an agent
depends on it. *Pitfall:* every lane's provenance runs through this tool; changing it mid-flight
invalidates derivations already returned and you cannot tell which. *Instead:* confirm all seven
agents have returned, then build the golden inline, then re-run
`python3 scripts/recon_gate.py --mode handoff`.

Anchor the golden on a known answer, and on the PROPERTY rather than a count — a cache-entry census
passes while the cache is shaped wrong. Give it a negative control.

## 7. Close out

- Update `reconstruction/handoff_baseline.json` with a `captured_session97` block; refresh
  `faithful_floor`, `stood_up_floor`, `wave_standup_size`, `wave_audit_size`, `head`, `ahead_origin`
  (`git rev-list --count origin/forward..forward`). Re-run `recon_gate --mode handoff` after.
- Record every premise an agent refuted. That is the highest-value output of a parallel session.
- `python3 scripts/handoff_completeness_lint.py <handoff>` before committing the next handoff.
- The ⚑[derive=wave.standup_units]-unit stand-up wave is excluded from all of the above: by design
  it cannot move the floor.

**One honest caveat on the goal.** `agg_faithful` counts audit-backed FAITHFUL verdicts — an
independent read of a verbatim decompile against the source. That is not byte-identity, which has
been proven exactly once in this project (`addSubtitle` slot 95, via `build_vs_binary`). If the bar
you actually want is disassembly-identical, run `build_vs_binary` over the existing floor first and
find out how many survive the stronger test, before scaling parallel work measured against the
weaker one.
