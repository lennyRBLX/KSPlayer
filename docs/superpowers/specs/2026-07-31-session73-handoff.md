# Session 73 work

## Verify first

1. Run `python3 scripts/recon_gate.py --mode handoff` — expect **PASS 28 / ANOMALY 0 / FAIL 3**, verified against the updated baseline. The 3 FAILs are known debt, not regressions: `agg_critical 7`, `agg_high 16`, `agg_unresolved 1`. Floor **277**, tree clean.
   **The head/ahead pins are deliberately NOT written here.** They live in `reconstruction/handoff_baseline.json`, which the gate checks for you, and MEMORY rule 55 already says to derive state from the gate rather than from a handoff's prose. Writing them into the prose cannot work: the commit that adds a handoff cannot contain its own hash, so the number is stale the moment it is written. That is exactly what happened to the s72 handoff — it said head `8ed1153` / ahead 254 while the truth was `7587432` / 255, off by the handoff's own commit — and s72 lost time reconciling it. If the gate reports `git_head`/`git_ahead_origin` as PASS, the pins are right; if it reports ANOMALY, adjudicate that output.
2. Run `python3 scripts/recon_progress.py`. Expect floor 277/1035, stages 10/18. **Do not quote its "blocked on unresolved symbols 283" line — that number is HARDCODED at `recon_progress.py:105` and is not derived.**
3. **The two-repo split.** Swift sources and the `forward` branch live in `/Users/jweaver/Desktop/Work/swift/KSPlayer`. The cwd `/Users/jweaver/Desktop/Work/swift/play` holds `scripts/` and `reconstruction/`, **and both are gitignored there** (`.gitignore:129` and `:95`) — verdicts and tool fixes are durable on disk but are never committed, and `play` will keep reporting a clean tree no matter how much you change. **Handoffs live in the KSPlayer repo**, not in `play/docs`, which stops at session 71; the s72 takeover prompt cited a `play`-relative path and the file was not there.
4. Read `reconstruction/handoff_baseline.json` block `captured_session72`.
5. **`agg_unresolved 1` is correct and must not be "fixed" by relabelling.** `VideoSwresample_DVbodies_deferral_p3a` reconstructs no body and names three unwritten vtable bodies that exist in the binary. UNRESOLVED is the honest label.

## Do not redo (landed + verified in s72)

6. **One commit on `forward`: `a2c8fed`** — `FormatContext.init` drops the phantom `duration:` parameter, plus its two call sites (`FFmpegSubtitle.swift:44`, `MEPlayerItem.swift:200`). Build 4/4; FormatContext gates l2_field REAL_FLAG 0 / type_kind PASS / superclass PASS; commit gate BLOCK 0 WARN 0.
7. **Package L is DONE.** `adjudicate_verdict.py`'s decompile-cache guard is now scoped to body verdicts, mirroring `verdict_provenance_gate.py:78` (`"binary_addr" in v`). Its selfcheck is **9/9** with two added goldens. All five previously-unadjudicable verdicts are settled; the "unrecognized verdict state" warnings are gone.
8. **`adjudicate_verdict.py --selfcheck` is NOT wired into `recon_gate`.** It was 7/7 before s72 and is 9/9 now, but nothing runs it in the gate. Wiring it is a real strengthening and would take the gate's check count from 31 to 32 — do it deliberately and update the expected PASS count in the same change.

## Premises this session REFUTED — each was verified against the binary by the orchestrator

9. **MEMORY rule 7 was WRONG and has been amended.** It said "write a field whose mangle has no trailing `Sg` as `T!`, never `T?`". A compiled control (`swiftc -O -wmo`, arm64-apple-ios17.0) shows `T!` and `T?` emit the **identical** field-record typeref: `let opt: Q?` and `let iuo: Q!` both point to 0x4334; `String?` and `String!` both point to 0x4342; the non-optional forms differ. IUO is **not recoverable from reflection at all**. The rule now reads: no trailing `Sg` ⇒ plain `T`, never `T?` and never `T!`. Any verdict that spells a field `T!` on field-record evidence is citing something the evidence cannot show.
10. **Two committed FAITHFUL verdicts were false and are re-adjudicated DIVERGENT.** Root cause, and it is systemic: **Ghidra's default `__swiftcall` prototype prepends a phantom `double param_1`**, visible verbatim in the prefetch caches. Treat any reconstructed signature whose parameter list begins with an unexplained `Double` as suspect until re-read against the trie.
    - `FormatContext_inner_init_101a350bc` carried a 6th parameter `duration: Double` that does not exist; the trie gives exactly five labels, the prologue at `0x101a350e8-fc` consumes only x20+x0..x4 and never reads d0, and the body assigned `duration` from a local. **The correct signature was already in the same file, four times, in its own `⚑[tool=resolve_fun_pins …]` markers, while the declaration above them contradicted it.**
    - `openFormatContext_101a392a0` is wrong three ways and is **not yet fixed in source**: no `time:` parameter; x0 is an indirectly-passed `Either<URL, AbstractAVIOContext>`, not `URL?`; and it returns **three** values — `mov x0,x26 ; mov x1,x24 ; mov x2,x27` at `0x101a39f28` before its sole `ret` at `0x101a39f58`, all three consumed at `0x101a9f3e4-f8`.
11. **The s72 handoff's own explanation of the DemuxerIO accessor residual was wrong.** It said "the 2 `let`s emit none". There are no such two `let`s. Commit `b831bdc` made `currentTime` and `state` `public private(set) var`, removing 2×3 accessor slots: 37−6=31. A fresh ProAVPlayer dylib now gives `class_detail.DemuxerIO = {status: paired, vtable_src 31, vtable_bin 31}`.
12. **`VideoVTBFrame`'s 6 binding_gate MISMATCHes are NOT divergences.** `binding_refuted_s62.json` already categorises `VideoSwresample.dovi` — same field name, same optional-DOVI type, same subsystem — as an `IMPLICIT_NIL_OPTIONAL` over-call, and five of the six are optionals of that shape. Recorded in `reconstruction/binding_videovtbframe_s72.json`, including that `isKeyFrame` is a non-optional Bool NOT covered by that precedent. Zero of the 289 verdicts record a binding mismatch as a divergence; the mechanism is `binding_refuted_*.json`, not verdict divergences.

## Facts to use, not rediscover

13. **Importing a dylib into Ghidra displaces the current program and silently breaks three gate checks** (`preflight`, `sc_init_thunk`, `sc_str_literal`). Close the imported program when done and re-run `python3 scripts/preflight_program.py` until it prints `OK program=Forward-1.3.17`.
14. **`vtable_anchor_diff` needs three things aligned or it silently reports 0 classes**: `--src-prog <your dylib>`, `--module ProAVPlayer` (DemuxerIO is NOT in the KSPlayer module), and a `--src-classmap` built for *that* program with `build_module_classmap.py`. Its `[gate]` line only prints when the class actually PAIRED, and its `vt=` is the **source** vtable.
15. **The KSPlayer pre-commit hook takes over 5 minutes.** A foreground `git commit` will time out and look like a failure while the commit is still in flight. Run it in the background, wait for `WRAPPER_EXIT`, then confirm HEAD moved — and check for duplicates before retrying.
16. **`function_sizes.py` keys by SYMTAB name, so stripped addresses are absent from it.** For an extent on a stripped address, parse `llvm-objdump --macho --function-starts` and take the delta to the next start.
17. Ghidra REST is on port **8089**. `llvm-objdump --macho --bind`: the symbol is the **8th** whitespace token; grep that table case-insensitively (UPPERCASE hex). A `0x1034xxxxx` stub needs a **12-byte** disassembly window.

## Package N — the openFormatContext body (do this FIRST; it unblocks Package B's remainder)

18. Reconstruct `openFormatContext` @**`0x101a392a0`**, extent `0x101a392a0..0x101a3a0b8` (3608 B / 902 instr, orchestrator-measured). Recovered shape: `openFormatContext(io: Either<URL, AbstractAVIOContext>, interrupt: IOInterruptContext, options: KSOptions?, inFormat: String?) throws -> (UnsafeMutablePointer<AVFormatContext>, Int64, AbstractAVIOContext?)`. Parameter NAMES are not in the trie (free function) — only arity, the four parameter types and the three return types are grounded.
19. Determine where `fileSize` (x1, from `bl 0x1030fdb5c` fed a path C-string; 0 on the fallback at `0x101a399dc`) and `ioContext` (x2, from the AVIO arm; 0 at `0x101a398a8`) are produced, and what the 4th String slot is consumed for.
20. Then update the declaration at `FormatContext.swift:464` and its call sites `FFmpegSubtitle.swift:35` and `MEPlayerItem.swift:195`, and fix the `fileSize: 0` / `ioContext: nil` placeholders left at `FFmpegSubtitle.swift:44` and `MEPlayerItem.swift:200`. Re-adjudicate `openFormatContext_101a392a0`.

## Package B-remainder — the three FormatContext convenience inits (needs N)

21. Read `reconstruction/pkgB_formatcontext_evidence_s72.json` first — the full derivation is there, split into `orchestrator_verifiable` and `agent_claims_NOT_independently_verified`.
22. The three units, all extents orchestrator-measured: `__allocating_init(io:options:inFormat:interruptBlock:) throws` @**`0x101a34e54`** (127 instr); `init(url:options:inFormat:)` @**`0x101a3a0b8`** (140 instr, thunk `0x101a33e78`); `init(string:options:inFormat:)` @**`0x101a3a2e8`** (235 instr, thunk `0x101a32e14`).
23. Note the derivation's own honest limit: #2 and #3 contain the `io:` pipeline **inlined**, so a delegating spelling and a duplicated body are indistinguishable in emitted code. Do not present the delegating form as binary-proven.

## Package M — DONE in session 73 (do not redo)

24. **Two commits landed: `f419d26` + `76e65f6`, and `DemuxerIO_structural_M2` is now FAITHFUL.** `f419d26` applied rulings 1, 2 and 4 plus `public actor` / `public State`; `76e65f6` made the five vtable methods `public`. The floor moved 276 -> 277. Evidence: `reconstruction/pkgM_demuxerio_evidence_s72.json` and `reconstruction/access_oracle_s73.json`.
25. **A NEW DETERMINISTIC TOOL exists: `scripts/vtable_impl_oracle.py`** (selfcheck 17/17, golden anchored on DemuxerIO). It reads `{Flags, Impl}` per vtable method descriptor and establishes the **access oracle the project previously held impossible**: `MethodDescriptor.Impl` is NON-NULL **iff the member is externally visible AND the enclosing type is too**. This SUPERSEDES "nothing proves a *type* public". Use it on any class whose access you need to settle.
26. **The elimination confound is ruled out, so do not re-litigate it.** An `@inline(never)` *internal* method whose body is provably emitted (0x4264) and provably called (the public `drive` does `bl 0x4264` at 0x41e0) *still* has a NULL Impl. NULL means "not externally visible", never "body eliminated". And an *internal* actor with **every** member spelled `public` emits ALL NULL — no member spelling can fake the enclosing type's visibility.
27. **The oracle CANNOT separate `public` from `@usableFromInline`, and neither can the export trie.** Both emit a non-null Impl, both get an EXTERNAL (`S`) `Tq` descriptor where internal ones are local (`s`), and **both are listed by the trie** — a control `@usableFromInline` method appears in `dyld_info -exports` exactly as a public one does. So a trie asymmetry is NOT evidence for `@usableFromInline`; under rule 4 an absence is UNNAMED, not absent. The tiebreak used here: `@usableFromInline` exists to serve `@inlinable`, and ProAVPlayer contains none (all 6 in the reconstruction are in `KSPlayer/AVPlayer/KSOptions.swift`), nor does `Sources/` contain any `@usableFromInline`.
28. **The cascade was proven compiler-entailed, not chosen.** Applied per rule 45 as widen -> build -> narrow-probe -> build. Reverting `Event` and `DemuxerIODelegate` to internal yields EXACTLY two errors — `:195` (`process`) and `:259` (`setDelegate`), "method cannot be declared public because its parameter uses an internal type" — while `readLoop`, `readPacket` and `cancelReading` raise nothing. `DemuxerIOAction` stays internal because it is reached only through a `private let`.
29. **The one residual risk, stated plainly:** the controls are built with Xcode 26.4 and Forward was not. The mitigation is an in-image corroboration the controls could not fake — of DemuxerIO's 25 accessor records exactly three have non-null Impls (one standalone Getter, two Getters whose Setter+Modify are NULL), which is exactly `public var isEndOfStream` plus the two `public private(set) var`s. It remains a cross-toolchain inference. Calibrating it against a KSPlayer-module class already known public would close it.

## Packages C, J1–J3 — unchanged from s72, still open

30. **Package C — file topology.** Enumerate the binary's KSPlayer `#fileID` literals (`llvm-objdump --macho --section=__TEXT,__cstring | grep -oE "KSPlayer/[A-Za-z0-9_]+\.swift"`), diff against the source tree, and rule on which reconstruction filenames are inventions. Three file-identity findings are already in hand, each read from a `#file` literal: `performSeek` names `KSPlayer/FFmpegUtility.swift`; `RemuxerIOAction.reconstruct` names `ProAVPlayer/RemuxerIO.swift`; `SubtitleModel.searchSubtitle` names `KSPlayer/SubtitleModel.swift` while the class lives in `KSSubtitle.swift`. Only after that ruling, relocate `performSeek` and re-adjudicate `FormatContext_performSeek_101a329d8`.
31. **J1** — migrate `KSPlayerLayerDelegate` from its 4 source requirements to the 12 the binary declares, updating every conformer; read `reconstruction/kscomplexplayerlayer_inventory_s66.json` first, and do this **before** any stand-up (MEMORY rule 53).
32. **J2** (needs J1) — move `readyToPlay`/`finish` into the class body, retype `state` to `@Published public private(set)`, extract `change(state:)`, add `KSPlayerLayer.addSubtitle(to:)`, stand up `KSComplexPlayerLayer : KSPlayerLayer`.
33. **J3** (needs J2) — replace `restoreUserInterfaceForPictureInPictureStop` with `player.pipController?.stop(restoreUserInterface: true)`, reduce `KSPictureInPictureController.start`/`.stop` to their one-statement bodies, flip the two slot verdicts.

## How to orchestrate

34. Hold the division of labour fixed: an agent **derives and proposes** (evidence package, proposed diff as TEXT, draft `verdict`), and the orchestrator alone re-verifies load-bearing claims against the binary with `llvm-objdump`, runs `validate_build.sh`, runs the class gates, stages, commits, and writes `recheck.final_verdict` via `adjudicate_verdict.py`.
35. **Forbid agents from writing anywhere under `/Users/jweaver/Desktop/Work/swift/KSPlayer`, and give each its own scratchpad subdirectory.** Both worked in s72 — three concurrent agents, KSPlayer tree clean throughout, no scratchpad collisions.
36. Write every agent prompt so its premises can be refuted: the address, its extent measured by YOU, the trie name, the claim to **test rather than confirm**, and that "absent from the trie" means unnamed, not absent. In s72 this produced the phantom-`double` discovery, the rule-7 refutation, and two stale line-number corrections.
37. **Re-verify agent claims yourself.** In s72 every load-bearing claim that was checked held up — but the checking is what turned "an agent says the verdict is wrong" into a committed fix. Also note an agent corrected the handoff's own line numbers (the `= nil` lines are at 117/123/128/139, not 109/111/114/122).

## Close out

38. Update `reconstruction/handoff_baseline.json` with a `captured_session73` block, and refresh `head`/`ahead_origin`/`faithful_floor`. **Re-run `recon_gate --mode handoff` AFTER updating the baseline** — the gate reads the baseline at start, so a pre-update run reports progress as ANOMALIES. Take `ahead_origin` from the gate's own resolver output (the `origin:` line), not from `git rev-list --count origin/main..HEAD`.
39. Record which packages landed, which were dispatched but not landed, and every premise the session refuted.
40. Write the session-74 handoff and its takeover prompt in this format, **in the KSPlayer repo** at `docs/superpowers/specs/`.

---

## Takeover prompt for session 73

Session 72 fixed the tool that had made five verdicts permanently unadjudicable, then spent most of its value on refutations: Ghidra's default `__swiftcall` prototype prepends a phantom `double param_1`, which had been reconstructed as a real parameter in two committed FAITHFUL verdicts (one of them contradicted by its own file's pin markers, four times over); and MEMORY rule 7 was refuted by a compiled control and amended.

**A later part of session 73 has already run.** It re-derived the `MethodDescriptor.Impl` access oracle from scratch with new controls, built `scripts/vtable_impl_oracle.py` around it, and landed `f419d26` + `76e65f6` — Package M's whole-file DemuxerIO change plus making its five vtable methods `public`. `DemuxerIO_structural_M2` is FAITHFUL and the floor is 277. **Steps 24–29 below are DONE; start at Package N.**

1. Read `MEMORY.md` and obey every rule. Note rule 7 changed in s72.
2. Read this handoff by path — it is in the **KSPlayer** repo: `/Users/jweaver/Desktop/Work/swift/KSPlayer/docs/superpowers/specs/2026-07-31-session73-handoff.md`.
3. Run `python3 scripts/recon_gate.py --mode handoff` from `/Users/jweaver/Desktop/Work/swift/play`.
4. Run `python3 scripts/recon_progress.py`.
5. Do Package N first — it unblocks Package B's remainder and is the largest single body still open.
6. Then Package M-apply, landing Rulings 1+2+4 as one commit and leaving Ruling 3 deferred until its oracle is calibrated against a known-public class in this image.
7. Verify each agent claim against the binary with `llvm-objdump` yourself before acting on it.
8. Run every gate on a touched class before you stage it; expect the pre-commit hook to take over 5 minutes.
9. Commit each landed unit on the `forward` branch after its gate passes, and confirm HEAD actually moved.
10. Stop at the first instruction you cannot ground and pin it.
