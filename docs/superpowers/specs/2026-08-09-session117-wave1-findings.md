# Session 117 — fix-queue wave 1 findings

Seven derive-only agents on the eight fix-queue units. Every load-bearing claim below was
re-derived by the orchestrator against the binary before being written here.

## Landed

| commit | what |
|---|---|
| `8dcd2f0` | `PlayerView.set(url:options:)` + the `required` its metatype call needs |
| `2af6f9e` | `Sources/FFURLShim` — ships `libavformat/url.h`, `URLContext` nameable in Swift |
| `0ad38a0` | corrects `2af6f9e`'s own claim about which bodies that unblocks |

`PlayerView_setUrlOptions_slot18_s84` adjudicated **FAITHFUL**. Floor 362 → 367, fix queue 40 → 35.

## The recurring failure mode this wave: verdicts outlive the source

Three of eight units carried premises that a later commit had already satisfied and nobody
re-adjudicated. This is not an occasional slip — it is the dominant cost in the fix queue.

1. **PlayerView** — three of five divergences described source rewritten by `8dcd2f0`.
2. **LimitSeparatePreLoadIOContext** — MED `s104_2` asserts "our source has no member of that
   name"; `canContinuePreload(at:)` is declared and implemented at
   `LimitSeparatePreLoadIOContext.swift:589`. The comment at :719-722 inside `more()`
   contradicts :589 of its own file.
3. **KSVideoPlayerView.openURL** — the CRITICAL entry blocks on three absent things. **Two are
   present.** `KSVideoPlayerModel` was stood up in `7942514` and is a committed 110-line file at
   `Sources/KSPlayer/SwiftUI/KSVideoPlayerModel.swift`; `KSPlayerLayer.select(subtitleInfo:isSecondary:)`
   is declared `public` at `KSPlayerLayer.swift:766` with the matching existential-optional signature.

Screen before spending an agent. Note also that `stale_divergence_screen.py` greps **comments** —
a divergence quoted inside a fix comment reads back as ALL_PRESENT. That produced one false LIVE
on `PlayerView`'s `srtControl` entry.

## New hard blocker, same class as the url.h one

`LimitSeparatePreLoadIOContext.more()` @0x101ba5398 calls `CacheIOContext.updateSpeedSample`,
a **fileprivate** member (private discriminator `_D69EFE1402863CA716A3171C7DB6DFB9`), from a body
whose own `#fileID` decodes to `PreLoadIOContext/LimitSeparatePreLoadIOContext.swift`. Swift cannot
express a cross-file call to a fileprivate member. This needs a user decision on access level, the
way url.h needed one on the FFmpeg distribution — it is not derivable away.

That body is additionally blocked on `addEntry` and `findDiscontinuousPos`, which appear in Sources
only inside comments. It calls **no** FFmpeg function: 433 instructions, 48 `bl` sites, 21 distinct
targets, none in the FFmpeg band.

## Confirmed live divergence: `download` optionality

Binary mangles `download` as `DownloadProtocol_p` with **no** trailing `Sg` across every
PreLoadIOContext init. The absence is informative, not an encoding limit: image-wide there are 655
`_pSg` optional-existential symbols and **zero** `DownloadProtocol_pSg`. Field records agree and
discriminate — `CacheIOContext.download` is `_p`, `ReadCacheIOContext.download` is `_pSg`, through
the same protocol descriptor `__got 0x1041079c8`. Source declares `(any DownloadProtocol)?`
throughout. Not a spelling or alias difference: `DownloadProtocol` is declared once, at
`PlayerDefines.swift:773`, with no typealias anywhere.

**Coupled, so it lands as one unit or not at all.** Making `download` non-optional breaks the two
`download: nil` call sites, both self-declared placeholders in convenience inits, one of which
(`CacheIOContext.swift:385`) is already pinned DIVERGENT for an unrelated arity divergence.

## `KSVideoPlayerView.openURL` — scoped, deliberately not applied

Anchor holds: 0x101ac99ac, OWNER_MATCH, 1 symbol, 1152 B / 288 instr. Source lines 305-315 in the
record are stale; `openURL` is now at :346.

Applied already: divergence _1's declaration half (`openURL(_ url: URL, options: KSOptions?)`, call
site passes `options: nil`), _3 (`runOnMainThread` absent), _4 (`isAudio || isMovie` absent).

Open and blocked on ONE thing — retyping `playerCoordinator` from `KSVideoPlayer.Coordinator` to
`KSVideoPlayerModel` at `KSVideoPlayerView.swift:18`: divergences _2, _5, _6 and _1's store half.
The binary's subtitle arm reads `KSVideoPlayerModel.config` (offset global 0x104c63810) then
`Coordinator.playerLayer` (0x104c63538), nil-tests, and calls 0x1019ceb00 with the
`URLSubtitleInfo : SubtitleInfo` witness table 0x1041da4f8 and `isSecondary=false`.

**Cost, derived:** 44 use sites on 40 lines — 34 member accesses, 10 whole-value passes. All eight
distinct members reached (`isMaskShow` 9, `playerLayer` 8, `skip` 6, `subtitleModel` 5, `state` 2,
`timemodel` 2, `mask` 1, `playbackRate` 1) are absent from `KSVideoPlayerModel`'s eight field
records, so every one needs `.config` interposed — and `config` is `Coordinator?`, so optional-chained.

**Why it was NOT applied here.** The binary evidence covers the `openURL` body only. Interposing
`.config` at all 44 sites on the strength of one body's derivation would be a half-grounded
signature change applied wholesale. The declaration retype and the `openURL` sites are groundable
now; the other sites each need their own body read. Scope it that way.

Also independent of the retype: divergence _7 is a pure reorder of `KSVideoPlayerView`'s own stored
properties — the `StateObject` payload is read at self+0x00/+0x08/+0x10, so it must be declared
first, ahead of `subtitleDataSource` and `title`.

One member of `KSVideoPlayerModel` is still missing from source: `init(playerLayer:)` @0x101acacbc,
452 B / 113 instr. It has no `…fc` counterpart in the trie, which is the signature of a
`convenience init`. Zero members of this class are trie negatives, and it carries no ObjC method
list, so nothing here needs the exhaustion gate.

## Verdict hygiene

`reconstruction/verdicts/KSVideoPlayerView_openURL_101ac99ac.json` still has `recheck: null` and
`source_lines: null` while three of its seven divergences are applied. All three
`LimitSeparate…_s104_*` entries cite a `decompile_txt` that does not exist on disk.
