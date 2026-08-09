# Session 118 handoff — what makes this go fast

State at handoff: `26dd612` on `forward`, tree green 4/4, gate **PASS 88 · ANOMALY 0 · FAIL 3**,
stages 13/18, floor 367/1035, MEMBER_MISSING 46, DIVERGENT 6, fix queue 35.

Take state from `recon_gate.py --mode handoff` and `recon_progress.py`, never from this prose.

## Paste as the argument to `/goal`

> Close DIVERGENT files, one coupled unit at a time. SCREEN every unit's premises by name against
> current source BEFORE dispatching an agent. Agents write findings to
> `reconstruction/derivations/` and return a 15-line summary. Write and commit only as the single
> integrator. Stop when `python3 scripts/recon_gate.py --mode handoff` reports FAIL 0, or when the
> next unit cannot be finished and reverted safely in remaining context — whichever comes first.

The `--mode handoff` FAIL count is the honest terminal. Do not make 18/18 stages a stop condition:
two of the six open stages are gated on work nobody has scoped (`masked_twin.py` does not exist).

## The five things that decide your throughput

**1. Screen before you dispatch.** In s117 all eight fix-queue units carried a false premise, and
two named blockers that were *already satisfied in committed code* (`KSVideoPlayerModel` — a
committed 110-line file; `KSPlayerLayer.select(subtitleInfo:isSecondary:)` — public at `:766`).
A third claimed "our source has no member of that name" about a member at `:589` of its own file.
Checking a premise by name costs a minute; deriving it costs an agent. Run
`stale_divergence_screen.py`, then verify each surviving premise yourself.

**2. Only the verdict flip moves the floor.** Fixing source and adjudicating are two acts.
`PlayerView_setUrlOptions_slot18_s84` went FAITHFUL for **+5 floor with zero source edits** because
an earlier commit had fixed it and never re-adjudicated. Look for those first — they are free.

**3. A verdict flips per FILE.** Fixing three of nine divergences in a file moves nothing. Batch by
file, and pay one gate per file, not one per divergence.

**4. NOT_IN_TRIE means unnamed, not unreadable.** s117 found a body pinned as "unread" whose
address was a 32-instruction forwarder into a fully readable four-funclet closure. Never accept an
absent symbol as a reason a body cannot be derived.

**5. A cross-file `private` call is not automatically an access-level decision.** Look for an
accessor already declared in the owning file. `MEPlayerItem.seekable` existed as a `false` stub in
the same file as the `fileprivate` field it needed; filling it unblocked
`KSMEPlayer.sourceDidOpenedSync` with nothing widened and nothing invented. I twice reported this
shape as needing a user ruling. It did not.

## Tool behaviour you cannot derive

- `aggregate_verdicts` counts `recheck.final_verdict`, falling back to `verdict`. Counting the
  agent-written `verdict` field gives ~53 DIVERGENT where the real number is 6.
- `stale_divergence_screen` greps **comments**, so a divergence quoted inside a fix comment reads
  back ALL_PRESENT. It produced one false LIVE in s117.
- `recon_progress` displays `handoff_baseline.faithful_floor`, not the derived value. Its own drift
  warning tells you when to re-baseline. Baseline keys are `head` / `ahead_origin` — *not*
  `git_head` / `git_ahead_origin`.
- `recover_field_offsets` refuses every global of a `metadata_init=1` class. Fall back to
  `fieldrec` (which carries NAME and TYPE), then to a **sibling reader** — another accessor loading
  the same global. That is how `0x1044ea218` was named after `recover_field_by_access` refused it
  as AMBIGUOUS across 29 candidates.
- `override_table.py` emits chained-fixup-corrupted base VAs (`0x100000039f6380` for
  `0x1039f6380`). Read the low 32 bits.
- `decode_string_literal.py --addr <body>` dies on a field-offset global. Use `--at <addr> --count
  <n>`, and remember the emitted pointer is BIASED — the literal usually starts at +0x20.
- A golden fixture must never be a live body reconstruction can close, nor a count over a corpus
  prose can move. Two goldens rotted in s117 for exactly those reasons; both are re-anchored.

## The open work, in dependency order

**`download` optionality — gates two DIVERGENT files.** Binary mangles `DownloadProtocol_p` with no
`Sg` across every init; image-wide there are 655 `_pSg` symbols and zero `DownloadProtocol_pSg`, so
the absence is informative. Source says `(any DownloadProtocol)?` throughout. Blocked on three
coupled things, not one: `URLContextDownload.init` @`0x101b90c58` (unread), and the two
`download: nil` call sites — `CacheIOContext.swift:390`, whose convenience init is already pinned
DIVERGENT on arity, and `LimitSeparatePreLoadIOContext.swift:394`, which also passes a
self-declared placeholder `cacheKey = ""`. Closing it also lands `CacheIOContext.fileSize`, which
is fully derived and pinned at its site.

**`readyToPlay`'s Task.** Body fully derived; the only blocker is a TYPE_DIVERGENCE —
`KSAVPlayer.subtitleDataSource.getter` mangles `ConstantSubtitleDataSource?`, source says
`(any SubtitleDataSource)?`. Retyping needs `KSMEPlayer.infos()` @`0x101a18f68` derived, because
KSMEPlayer conforms to `ConstantSubtitleDataSource` only in the binary (WT `0x1041d76d8`).

**`FFmpegDecode` D3.** Coupling to the `VideoSwresample` UNRESOLVED deferral is CONFIRMED across
three legs; `FFmpegDecode.swift:225` is the only writer of `edrMetaData` in the tree. Not separable.

**`KSVideoPlayerView` retype.** 44 use sites, 40 lines, all needing optional-chained `.config`.
Binary evidence covers the `openURL` body only — ground the others before applying wholesale.

**`displayLayerDelegate` removal.** Five of seven sites are safe (zero image occurrences, control:
`flickerDetector` 3). The other two hold the PiP setup, and `pipController` is a real public field.
Re-home the body before deleting.
