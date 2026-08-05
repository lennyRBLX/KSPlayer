# Session 108 takeover prompt

Paste the block below as the first message of the new session.

---

Read MEMORY.md and obey every rule. Then read the handoff at
`/Users/jweaver/Desktop/Work/swift/KSPlayer/docs/superpowers/specs/2026-08-05-session108-handoff.md`.
Work from `/Users/jweaver/Desktop/Work/swift/play`.

This handoff is ORIENTATION ONLY and authorizes no work. Do its §1 "Verify first" steps 1–5, then
STOP.

Expect: MEMBER_MISSING 108 · ACCESS 26 · NOT_IN_TRIE 24 · AMBIGUOUS_OVERLOAD 10 ·
TYPE_DIVERGENCE 4; gate PASS 44 / ANOMALY 6 / FAIL 4; build 4/4; HEAD `4168fb7` on `forward` with a
clean tree. Confirm each of these rather than quoting it, and say so if any disagrees.

Two verifications matter more than the counts:

* `recover_field_offsets.py --selfcheck` and `field_offset_vector.py --selfcheck` must BOTH print
  SELFCHECK PASS. Those files carry three fixes that exist only on this disk, because
  `play/scripts/` is gitignored. If either fails, say so immediately — the handoff's §4 describes
  what was in them and roughly +156 named offset globals depend on it.
* `recover_field_offsets.py --class KSPlayerLayer` should list **7** offset globals including
  `0x104c634f0 → player`. Before the fix it listed zero. That single line is the cheapest proof the
  substitution fix survived.

Then read §3 (four earlier conclusions that were WRONG — two of them would have made a future
session skip real rows), §5 (three measured negatives; do not re-search them), and §6 (where the
remaining 108 actually sit, and the one long chain that is fully mapped).

Do NOT dispatch an agent, read a member body, edit a source file, run a build beyond the §1 check,
or touch the git index until I give you a directive. In particular do not resume the
`changePlaybackTime` chain, and do not start on the `SubtitleModel` `Task` closure — both are
described in §6 precisely so that resuming them is a decision rather than a default.

Report four things and wait:

* the five bucket counts, the gate line, and whether the working tree is clean;
* whether both selfchecks pass and whether `KSPlayerLayer` shows 7 offset globals;
* which of the four gate FAILs you can confirm are pre-existing rather than from the last drive;
* one sentence on what you would pick up first and why — **as a proposal, not an action.**

If anything in §1 disagrees with the expected values, stop after reporting it and do not
investigate further until I answer.
