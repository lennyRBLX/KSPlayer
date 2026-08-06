# Session 112 — entry prompt

Paste the block below as the session's first message. It verifies, reports, and stops. Set the
`/goal` only AFTER the verification report comes back clean.

---

Read MEMORY.md and obey every rule. Then read the handoff at
`/Users/jweaver/Desktop/Work/swift/KSPlayer/docs/superpowers/specs/2026-08-06-session112-handoff.md`.
Work from `/Users/jweaver/Desktop/Work/swift/play`.

This handoff is ORIENTATION ONLY and authorises no work. Do its §1 "Verify first" steps, then STOP
and report. Confirm each value by deriving it — do not quote the table back at me — and say so if
any disagrees.

Expected: MEMBER_MISSING 68 · ACCESS 26 · NOT_IN_TRIE 23 · AMBIGUOUS_OVERLOAD 10 ·
TYPE_DIVERGENCE 4; build 4/4. KSPlayer on branch `forward` with a CLEAN tree, its recent log
showing the s111 commits. No hash is pinned — writing the handoff moved HEAD.

Four things matter more than the counts:

1. All three selfchecks must print SELFCHECK PASS — `rank_member_missing.py`,
   `name_exhaustion_gate.py`, `helper_fingerprint.py`. **All three live only in `play/scripts/`,
   which is gitignored.** If any file is absent, say so immediately and do not substitute your own
   judgement for it; §3 and §4 of the handoff describe what each does well enough to rebuild, and a
   rebuilt tool needs its goldens back before it is trusted.
2. FFmpegKit must be on `forward-recon-shim` at `12f0899`, with its ~1167 dirty files still
   UNSTAGED. Never `git add -A` there.
3. **Re-run `member_missing_triage.py` before using ANY address list.** Every list in the s111
   working doc predates later edits — s111 itself nearly rewrote a body that already existed
   because it trusted a stale triage.
4. Confirm the 4 pre-existing gate FAILs still trace to verdict files predating s109.

Then read §2 (why there is no single blocker class), §4 (the invented-name rule), §7 (the row to
start on) and §8 (corrections you must not undo).

Do NOT dispatch an agent, edit a source file, or touch either git index until I give you a
directive. The `changePlaybackTime` chain and the `SubtitleModel` Task closure remain off-limits
from s108.

Report and wait:

- the five bucket counts, the gate line, and tree cleanliness for BOTH repos;
- whether all three selfchecks pass, and whether all three tool files exist;
- whether the four gate FAILs are still confirmable as pre-existing;
- one sentence proposing what to pick up first, naming its BLOCKER CLASS (§2) — not just the row.

---

## The goal to set after a clean report

```
/goal Close MEMBER_MISSING rows one unit at a time until only the 2 swift_deletedMethodError rows remain, building 4/4 and committing each unit alone; invent a name only through name_exhaustion_gate.py returning EXHAUSTED, carrying the invented= marker with my approval.
```

### Why the goal is worded that way

**"until only the 2 … rows remain", not "until 0".** `IOSVideoPlayerView.toggleBottomSlimProgress`
and `updateTitle` have no code in the binary. A goal of 0 cannot be satisfied without writing two
bodies from nothing, and a stop-hook goal that cannot be satisfied fires forever — s111 burned
several turns on exactly that.

**"one unit at a time, building 4/4 and committing each unit alone"** is the discipline that makes
progress durable and reviewable. Landing 8 rows in s111 took 8 separate build-and-commit cycles.

**"invent a name only through the gate"** keeps the authorisation bounded. The gate has been wrong
in both directions; it is the thing standing between an evidence-based name and a fabricated one.

### Realistic scope

66 reachable rows, plus ~40 helper units behind them, at roughly 100–2600 instructions each. s111
closed 8 rows in a full session. **This is several sessions of work, not one.** Expect the goal to
carry across sessions, and re-derive state at the start of each — the counts in any handoff go
stale the moment work lands.
