# Session 119 work

## Verify first

1. Run `python3 scripts/recon_gate.py --mode handoff`. Expect **PASS 88 · ANOMALY 0 · FAIL 3**,
   floor **367/1035**. The three FAILs are `agg_critical 4`, `agg_high 14`, `agg_unresolved 1`.
2. Run `python3 scripts/recon_progress.py`. Expect stages 13/18 and floor 367/1035. Ignore its
   prose line reading "6 DIVERGENT" — it is a stale literal; the derived count is **7**.
3. Read `docs/superpowers/RECONSTRUCTION_FAITHFULNESS_MANUAL.md`, `reconstruction/AGENT_PROTOCOL.md`
   and `reconstruction/DISPATCH_CONTRACT_s64.md` before dispatching anything.
4. Read the three s118 derivation files — they are the session's product and every unit below
   depends on them:
   `reconstruction/derivations/s118_URLContextDownload_init_101b90c58.md`,
   `reconstruction/derivations/s118_download_construction_sites.md`,
   `reconstruction/derivations/s118_KSMEPlayer_infos_101a18f68.md`.

## What FAIL 0 actually costs — read before planning

5. Accept that FAIL 0 is not a one-session target, and do not plan as if it were. The three FAIL
   counters are corpus-wide, and a verdict flips per FILE, so reaching zero means closing **six of
   the seven** DIVERGENT files plus the one UNRESOLVED verdict.
6. Read `reconstruction/verdicts/VideoSwresample_DVbodies_deferral_p3a.json` before proposing to
   close `agg_unresolved`. Its own adjudication says the three DV bodies are gated on a
   protocol-witness verifier that does not exist, and that `FFmpegDecode` is inseparable from it.
   That is a tooling stage, not a body. `FFmpegDecode_decodeFrame_slot13_s85` (1 CRITICAL + 4 HIGH)
   cannot close before it.

## Unit A — `readyToPlay`'s Task. Start here: it is the only FAIL-moving unit that is unblocked.

Closing `KSPlayerLayer_readyToPlay_slot69_s84` removes **1 CRITICAL + 1 HIGH**.

7. Re-read `readyToPlay` in `Sources/KSPlayer/AVPlayer/KSPlayerLayer.swift` by NAME (it is at :622,
   not the verdict's `source_lines` 457-495) and confirm that divergences 2, 3 and 4 are already
   discharged in committed source before writing anything. D2 (`updateNowPlayingInfo()` has no
   counterpart) is recorded as removed at :701 with an exhaustive 29-callee argument; D3's PiP block
   is removed at :691; D4 is source-position drift only. `stale_divergence_screen.py` reports D2
   ALL_PRESENT — that is the known comment-grep trap, because the word appears inside the comment
   recording the removal. Do not trust it here; read the body.
8. Declare `infos()` on `KSMEPlayer` in `Sources/KSPlayer/MEPlayer/KSMEPlayer.swift`. Entry
   `0x101a18f68` is a 6-instruction async entry; the body is the single funclet
   `0x101a18f80-0x101a19144` (113 instr), two funclets total. It calls `tracks(mediaType:)` at
   `0x101a3ccd0` with the argument loaded from `_AVMediaTypeSubtitle`, then filters, boxing each
   survivor with witness table `0x1041d7668` (`FFmpegAssetTrack : SubtitleInfo`). It reads no field
   of `self`, holds no literal, and never throws.
9. The filter is SETTLED — do not re-derive it. Read
   `reconstruction/derivations/s118_infos_cast_lowering_probe.md`, which closes it by swiftc probe
   at UNGROUNDED 0. `x21` is the element's instance word (stride 16 from base+0x20, a class-bound
   existential), the guard is `object_getClass(elem) == FFmpegAssetTrack metadata AND elem != nil`,
   and the body is:

       public func infos() async throws -> [any SubtitleInfo] {
           tracks(mediaType: .subtitle).compactMap { $0 as? FFmpegAssetTrack }
       }

   `filter { $0 is T }.map` is refuted (two `object_getClass`, 153 instr vs Forward's 113) and
   `for` + `if let` is refuted (it emits `swift_unknownObjectRetain_n`; Forward emits the plain
   `swift_unknownObjectRetain` via `__got 0x1041130b0`). The declaration is `async throws` even
   though the body never throws — the trie carries the `K`.
9a. **`FFmpegAssetTrack` must be made `final` FIRST, and that is a prerequisite, not a nicety.** The
   probe shows the exact-metadata compare appears ONLY with a `final` cast target; a non-final
   target — public OR internal-under-WMO — lowers to `swift_dynamicCastClass` and the body stops
   matching. Source declares `public class FFmpegAssetTrack: MediaPlayerTrack` at
   `FFmpegAssetTrack.swift:24`; the binary corroborates finality independently through the class's
   vtable, which carries one `Init` slot and NO method slots
   (`python3 scripts/vtable_walk.py FFmpegAssetTrack` → `VTableSize=1`, `override_table=False`).
   Nothing in the tree subclasses it, so the keyword is safe. This is a NEW divergence that no
   existing verdict records — land it as its own change with its own verdict, and note it touches
   `FFmpegDecode`'s neighbourhood, which carries its own DIVERGENT verdict.
10. Add the conformance `extension KSMEPlayer: ConstantSubtitleDataSource {}`. The binary carries it
    at witness table `0x1041d76d8`; source carries neither the conformance nor `infos()`. The
    protocol is at `Sources/KSPlayer/Subtitle/SubtitleDataSource.swift:152` — the pin in
    `KSPlayerLayer.swift:658` says `:167`, which is the closing brace. `ConstantSubtitleDataSource`
    has NumRequirements 2 (BaseProtocol + 1 Method) and no default `infos()`, so the conformance
    cannot be satisfied by an extension alone. Its only two conformers image-wide are claimed to be
    `KSAVPlayer` (`0x1041d4168`) and `KSMEPlayer` (`0x1041d76d8`) — **that pair and the
    NumRequirements 2 are AGENT-DERIVED and were not re-verified by the s118 orchestrator; confirm
    both before relying on them.** What WAS orchestrator-verified is the base protocol:
    `python3 scripts/conformance_walker.py --protocols 'P:0x1039f1a68'` returns `SubtitleDataSource`
    with NumRequirements 0 and 8 conformers, and gives `KSMEPlayer : SubtitleDataSource` witness
    table `0x1041d76f0` — exactly the pointer the agent reports in slot `+0x8` of `0x1041d76d8`,
    which corroborates the table's identity from the other direction.
11. Retype `subtitleDataSource` from `(any SubtitleDataSource)?` to `(any ConstantSubtitleDataSource)?`
    at exactly three sites: `MediaPlayerProtocol.swift:300`, `KSAVPlayer.swift:770` and
    `KSMEPlayer.swift:448`. The pin in `KSPlayerLayer.swift:668` says KSMEPlayer's is at `:408` —
    that has drifted; locate it by NAME. Both binary getters are getter-only and return
    `ConstantSubtitleDataSource?` — no `vs` and no `vM` symbol exists for either — so
    `MediaPlayerProtocol.swift:300`'s existing `{ get }` is already correct and must stay
    getter-only.
12. Write the Task statement as statement 5 of `readyToPlay`, using the four funclets already
    recorded at `KSPlayerLayer.swift:619-621` and re-confirmed this session: `0x1019cdf98` entry,
    `0x1019ce034` post-await, `0x1019ce114` post-hop success, `0x1015f4544` post-hop error, reached
    through the forwarder `0x1019d5b58`. The await site is `ldr x8, [x19, #0x10]` + `br x2` —
    witness offset `+0x10`, which is `infos()`.
13. Gate every touched class, build 4/4, commit through `bash scripts/commit_unit.sh`, then flip the
    verdict with `python3 scripts/adjudicate_verdict.py`. **The flip is a separate act from the fix
    and is the only one that moves a counter.** Adjudicate all four divergences, not just D1.

## Unit B — `download` optionality. Fully derived, but four bodies deep. Do not start it casually.

Closing `PreLoadIOContext_download_existential_s78` moves the floor and `DIVERGENT 7→6`, but it is
MED-only and moves **no FAIL counter**. Sequence it after Unit A.

14. Treat the optionality itself as SETTLED and do not re-derive it. Read from the Mach-O field
    records with `python3 scripts/fieldrec.py --class <C> --module PreLoadIOContext`:
    `CacheIOContext.download` tail `_p`, `LimitSeparatePreLoadIOContext.moreDownload` tail `_p`,
    and — the control that proves the emitter writes `Sg` when it means it —
    `ReadCacheIOContext.download` tail `_pSg`. The optionality is therefore NOT uniform: the
    ReadCacheIOContext field is genuinely Optional and its `download?.close()` at
    `ReadCacheIOContext.swift:182` must NOT be touched.
15. Declare `URL.sortQueryString` before anything else in this unit. It is
    `(extension in PreLoadIOContext):Foundation.URL.sortQueryString.getter : Swift.String` at
    `0x101b86a2c` (651 B, URLComponents queryItems/url), and it is ABSENT from source — it appears
    only inside ⚑ marker comments. Both construction sites pass `url.sortQueryString.md5()` as
    `md5:`, so nothing in this unit compiles without it. `String.md5()` already exists at
    `Utility.swift:102`.
16. Declare `KSPlayerError.init(errorCode:avErrorCode:)`. `0x1019e1f94` is a ONE-instruction
    forwarder `b 0x1019e429c`; the real body is at `0x1019e429c`. Source's `KSPlayerError` declares
    only `init(code:description:)` at `PlayerDefines.swift:380`, so the throw inside
    `URLContextDownload.init` cannot be spelled without this init.
17. Do NOT let the `KSPlayerErrorCode` mismatch block step 16. The binary enum has 19 cases and
    source has 22 — verified with `python3 scripts/fieldrec.py 0x1039edbb8`: binary index 0 is
    `formatCreate`, index 1 `formatOpenInput`, index 2 `avioOpen`; source's leading `unknown` is
    absent from the binary and `avioOpen`/`noStream` are absent from source. That is a real and
    separate divergence, but the throw in `URLContextDownload.init` is tag 1 = `formatOpenInput`,
    a name source ALREADY has, so it is spellable today. A prior agent recorded this as a blocker;
    its own evidence refutes it.
18. Declare `URLContextDownload.init(url:flags:options:interrupt:isReadComplete:) throws`
    (`0x101b90c58`, extent `0x101b90c58-0x101b91078`, 264 instr, not ICF-folded) from
    `s118_URLContextDownload_init_101b90c58.md`. ABI is x20=self, x0=&url indirect owned,
    w1=flags, x2=options, x3+x4=interrupt spilled to fp-0x70, x5=isReadComplete. `super.init` is
    INLINED as one 8-byte store at self+0x10, not called. Its sole AVDictionary key is
    `"multiple_requests"`, compared `== "1"` to set `keepAlive`; there is no `av_dict_set`.
19. Fix `URLContextDownload`'s own field declarations in the same change — the field records refute
    three of them. `url` is `URL`, NOT `URL?` (record 3's typeref tail is `b''`, no `Sg`), and
    `keepAlive`/`isReadComplete` are not the `= false` constants source declares: the binary assigns
    a computed value to self+0x20 and the parameter to self+0x21.
20. Add `ffurl_open_whitelist` to FFmpegKit's `Sources/FFmpegKit/include/avformat_shim.h`. This is
    NOT the cross-repo blocker a prior session recorded: `_ffurl_open_whitelist` is `T` in
    `FFmpegKit/.Script/FFmpeg/ios/thin/arm64/lib/libavformat.a`, FFmpegKit is a PATH dependency
    (`.package(path: "../FFmpegKit")` at `Package.swift:89`) so the edit takes effect immediately,
    and four identical prototypes already ship there at FFmpegKit `12f0899`. Do NOT route this
    through the in-repo `Sources/FFURLShim` module: nothing imports it, and its own
    `typedef struct URLContext` would collide with the one `URLContextDownload.swift` already gets
    from `import FFmpegKit`.
20a. **Before committing anything in FFmpegKit, look at its tree.** As of s118 close it carries
    roughly 100 KB of uncommitted changes that belong to NOBODY in this reconstruction — modified
    `Plugins/BuildFFmpeg/BuildFFMPEG.swift`, `Plugins/BuildFFmpeg/main.swift`,
    `Sources/FFmpegKit/include/avutil_shim.h`, rebuilt `Libavcodec.xcframework` binaries, and a
    large set of DELETED `ios-arm64_x86_64-maccatalyst` framework headers. KSPlayer's tracked tree
    is clean; FFmpegKit's is not. Stage only `Sources/FFmpegKit/include/avformat_shim.h` by path.
    Never `git commit -a` there, and do not "clean up" the deletions — they are not yours.
21. Rewrite `CacheIOContext`'s convenience init at `CacheIOContext.swift:386`. The trie gives arity
    5 and it THROWS: `init(url: URL, formatContextOptions: [String: Any], interrupt: AVIOInterruptCB,
    saveFile: Bool, isReadComplete: Bool) throws` — there is no `bufferSize:` parameter. It builds
    ONE `URLContextDownload` with flags 1 and `isReadComplete` hardcoded FALSE, then delegates with
    `md5: url.sortQueryString.md5()` and bufferSize `0x40000` (256 KiB), not the 32 KiB default.
    This also discharges the arity pin recorded at `CacheIOContext.swift:385`.
22. Rewrite `LimitSeparatePreLoadIOContext`'s convenience init at `:379`. Its signature already
    matches the trie. It constructs TWICE — `0x101ba4420` over the pre-mutation options into
    `download`, `0x101ba4508` over the post-`rw_timeout` options into `moreDownload` — both with
    flags 1 and isReadComplete false. Replace the self-declared placeholder `let cacheKey = ""` at
    `:393`, which is NOT the binary's value, with `url.sortQueryString.md5()`.
23. Flip the five init parameters and two stored properties from `(any DownloadProtocol)?` to
    `any DownloadProtocol`: `CacheIOContext.swift:53` and `:347`, `LimitCacheIOContext.swift:30`,
    `LimitPreLoadIOContext.swift:145`, `LimitCountPreLoadIOContext.swift:53`,
    `LimitSeparatePreLoadIOContext.swift:98` and `:226`. All five designated inits also THROW in the
    binary (`…tKcfc`), so each delegation and each `URLContextDownload(...)` needs `try` and each
    convenience init needs `throws`.
24. Record, do not fix, two things this unit uncovers but does not own: the init's `#fileID` decodes
    to `PreLoadIOContext/CacheIOContext.swift` line 1043 while the class is declared in
    `URLContextDownload.swift` (a file-placement divergence), and `ReadCacheIOContext`'s init label
    is `onlyCache:`, not the `onlyRead:` a prior note used, and it does NOT throw.
25. After landing, expect `CacheIOContext.fileSize()` to become declarable — it was read end to end
    in s117 and is pinned at `CacheIOContext.swift:428-455` with `download`'s optionality named as
    its ONLY blocker. Treat it as a follow-on unit with its own verdict, not as part of Unit B.

## Unit C — `KSVideoPlayerView_openURL`. Screen it before believing its CRITICAL.

This file carries **2 CRITICAL + 4 HIGH**, six of the eighteen FAIL-counted divergences — the
largest single reduction available.

26. Re-read its CRITICAL, which names three blockers. Two are ALREADY satisfied in committed source
    and were verified this session: `KSVideoPlayerModel` is a real class at
    `Sources/KSPlayer/SwiftUI/KSVideoPlayerModel.swift:23`, and
    `KSPlayerLayer.select(subtitleInfo:isSecondary:)` is `public` at `KSPlayerLayer.swift:819`.
27. Scope the one surviving blocker: retyping `@StateObject private var playerCoordinator` at
    `Sources/KSPlayer/SwiftUI/KSVideoPlayerView.swift:18` from `KSVideoPlayer.Coordinator` to
    `KSVideoPlayerModel`. Binary evidence covers the `openURL` body only — ground each other use
    site before applying wholesale, and do not let a single agent apply all 44 at once.

## Close out

28. Update `reconstruction/handoff_baseline.json` with a `captured_session119` block after the last
    commit, using keys `head` and `ahead_origin` (NOT `git_head` / `git_ahead_origin`). Re-run
    `python3 scripts/recon_gate.py --mode handoff` and confirm ANOMALY 0.
29. Run `python3 scripts/handoff_completeness_lint.py <this handoff>` before committing the next
    one: every tool a handoff names must exist in `scripts/` AND carry a usage entry in
    `docs/superpowers/RECONSTRUCTION_FAITHFULNESS_MANUAL.md`.
30. Write the session 120 handoff and give the takeover prompt in chat, never in the file.
