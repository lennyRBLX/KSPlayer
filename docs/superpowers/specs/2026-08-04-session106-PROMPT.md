Read MEMORY.md and obey every rule. Then read the handoff at
/Users/jweaver/Desktop/Work/swift/KSPlayer/docs/superpowers/specs/2026-08-04-session106-handoff.md,
and reconstruction/STANDUP_PROTOCOL.md and reconstruction/DISPATCH_CONTRACT_s64.md.
Work from /Users/jweaver/Desktop/Work/swift/play.

GOAL, unchanged from s105: drive MEMBER_MISSING to 0.

Do the handoff's "Verify first" steps 1-6 and report before touching anything. Expect
MEMBER_MISSING 223, and the same three modified-uncommitted files s105 was handed and never
touched. Confirm each rather than quoting it, and say so if any disagrees. Do NOT refresh
handoff_baseline.json.

⛔ DO NOT OPEN THIS THE WAY s105 DID. That session triaged the whole queue and then picked the
cheapest individual row anywhere in the corpus, over and over. The cheap seam is gone — the median
body was 16 instructions at s105 open and is 30 now — and row-at-a-time pays the per-class setup
cost once per ROW instead of once per CLASS. Two things come first instead:

1. §1 — the `isConvertNALSize` decision. It is MINE, and it gates 44 rows (20% of the queue)
   across KSAVPlayer 17 / MediaPlayerProtocol 15 / FFmpegAssetTrack 9 / MediaPlayerTrack 3,
   because those types live in the three staged files. Bring me the decision with the evidence;
   do not decide it yourself and do not edit those files until it lands.

2. §2 — then work ONE CLASS end to end and land it as one commit. Resolve that class's field
   offsets, witness tables and callees once, then read every body in it. FFmpegAssetTrack is the
   cheapest real class (9 rows, 262 instructions) the moment §1 lands.

Read §4 before you judge any comment in the source. Twelve members in this corpus were sitting
under names nobody had read, every one behind a confident comment citing a correct address — and
the enumeration that finds them is in §4 and costs one grep per row.

Read §5's six traps. Two of them are about distrusting a clean result: three s105 tool outputs were
confidently wrong and none was caught by a gate.

§6 lists what is genuinely undecidable. Do not spend time re-deriving those.

Standing constraints: never declare a member whose return value you have not read; never write
`= false` for a field with no vpfi; decode a witness slot rather than counting it; and a stored
property goes at its field-record index, not appended.

Report the gate result, the re-derived MEMBER_MISSING split, and anything in the handoff you
disagree with, with the command output that establishes it. Then wait for my §1 decision.
