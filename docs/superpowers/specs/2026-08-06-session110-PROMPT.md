# Session 110 — entry prompt (VERIFY AND STOP)

Paste this as the first message of the next session.

---

Read `MEMORY.md` and obey every rule. Then read the handoff at
`/Users/jweaver/Desktop/Work/swift/KSPlayer/docs/superpowers/specs/2026-08-06-session110-handoff.md`.
Work from `/Users/jweaver/Desktop/Work/swift/play`.

**This handoff is ORIENTATION ONLY and authorises no work.** Do its §1 "Verify first" steps, then
STOP and report. Confirm each value by deriving it — do not quote the table back at me — and say so
if any disagrees.

Expected: MEMBER_MISSING 76 · ACCESS 26 · NOT_IN_TRIE 23 · AMBIGUOUS_OVERLOAD 10 ·
TYPE_DIVERGENCE 4; gate PASS 44 / ANOMALY 6 / FAIL 4; build 4/4. KSPlayer must be on `forward`
with a CLEAN tree, its HEAD being the s110 handoff commit (`git log --oneline -1` should name
`docs(recon): s110 handoff`) — the exact hash is deliberately not pinned here, since committing
this file moves it.

Three verifications matter more than the counts:

1. Both `recover_field_offsets.py --selfcheck` and `field_offset_vector.py --selfcheck` must print
   `SELFCHECK PASS`. They carry disk-only fixes and `play/scripts/` is gitignored by design.
2. `helper_fingerprint.py --selfcheck` must print `SELFCHECK PASS`. It is the s109 tool the
   remaining work depends on, and it also lives only on disk.
3. FFmpegKit must be on branch `forward-recon-shim` at `12f0899`, and
   `git -C … status --porcelain` there must still show its ~1167 unrelated dirty files
   **unstaged**. That repo was on a detached HEAD; the branch exists so the shim commit is not
   orphaned. **Never `git add -A` in FFmpegKit.**

Then read §4 (the remaining 76 by blocker class), §5 (`helper_fingerprint.py`, including its
documented over-reporting limitation and the compiler-artifact check), and §6 (the techniques and
traps).

**Do NOT** dispatch an agent, read a member body, edit a source file, run a build beyond the §1
check, or touch either git index until I give you a directive. In particular do not start on the
`FFmpegSubtitle` standup (§4d) or the `AssImageParse` chain (§4c) — both are described precisely so
that starting them is a decision rather than a default. The `changePlaybackTime` chain and the
`SubtitleModel` `Task` closure remain off-limits from s108.

Report four things and wait:

- the five bucket counts, the gate line, and tree cleanliness for BOTH repos;
- whether all three selfchecks pass;
- whether the four gate FAILs are still confirmable as pre-existing (each should trace to a verdict
  file predating s109);
- one sentence proposing what to pick up first, and why — with the honest cost. §4 gives the
  blocker class for every row; I want the proposal to name the class, not just the row.

If anything in §1 disagrees with the expected values, stop after reporting it and do not investigate
further until I answer.
