# Session 101 — takeover prompt (orientation only)

Paste the block below into a fresh session. It authorizes no work.

---

Read MEMORY.md and obey every rule. Then read the handoff at
`/Users/jweaver/Desktop/Work/swift/KSPlayer/docs/superpowers/specs/2026-08-05-session101-readiness-residue-handoff.md`,
and `reconstruction/STANDUP_PROTOCOL.md` and `reconstruction/DISPATCH_CONTRACT_s64.md`. Work from
`/Users/jweaver/Desktop/Work/swift/play`.

This handoff is ORIENTATION ONLY and authorizes no work. Do steps 1-6, then STOP at step 7.

1. Run `python3 scripts/recon_gate.py --mode handoff` — expect PASS 50 / ANOMALY 0 / FAIL 3. The
   three FAILs (`agg_critical` 7, `agg_high` 19, `agg_unresolved` 1) are session-98 fix-queue debt
   and are not a target unless I say so.
2. Run `python3 scripts/aggregate_verdicts.py` — the faithful floor is 332. Session 100 moved it
   four times (328 → 332). Confirm the number rather than quoting it.
3. Run `python3 scripts/recon_progress.py`, but do NOT plan from its WORK BUCKETS or KNOWN DEBT
   lines — handoff §4.1/§4.2 explain why both are frozen artifacts and what they misreport.
4. Re-derive the wave quantities with `python3 scripts/contract_numbers.py --group state`.
5. Re-derive the bucket state yourself, ADDRESS-KEYED, not through `classify_accessor_slots` —
   handoff §4.1 explains why a freshly generated bucket artifact is untrustworthy. Expect
   COMPUTED_ACCESSOR blocked 16 and, against the shape-verified bucket, INIT_THUNK blocked 0.
6. Read handoff §0 (state at close), §3 (the 16 blockers, all already READ — do not re-derive
   them), §3.5 (the BIND vs REBASE distinction and `bind_oracle.py`), and §6 (the judgement I have
   not made). Then read `reconstruction/S100_FINDING_published_accessor_blockers.md`.

7. Do NOT dispatch an agent, write a verdict, edit a source file, run a build, or touch the git
   index until I give you a directive.

Report three things and wait:

- the gate result and the floor;
- the bucket state you derived address-keyed, and whether it matches §0;
- anything in the handoff you disagree with, with the command output that establishes it.

Two things in the handoff are known to be soft, and I want your own read on them rather than
agreement: the claim in §3 that every remaining blocker has been read and none is glue (four
"the structural vein is exhausted" calls were wrong during session 100 before that claim was
backed by reading), and the decision recorded in §6.1 about the s42 keypath guard, which is mine
to make and which you should not pre-empt.
