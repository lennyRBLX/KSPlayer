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

## `FFmpegDecode.decodeFrame` — 0x101a2220c, 677 instr

D1 and D2 are **already closed in source**: `FFmpegDecode.swift:55` declares
`from packet: UnsafeMutablePointer<AVPacket>`, mangling identically to the trie; the CC guard at
:88 tests `self.isVideo` (field offset 0x61) and reaches `self.assetTrack` (0x68).

The CRITICAL's own sentence "every later use is a DIRECT AVPacket field read" is **refuted**: of
11 x24 uses only 3 are dereferences, and all three read `AVPacket.flags` — masked with
`AV_PKT_FLAG_KEY` and `AV_PKT_FLAG_DISCARD`. Offsets were proven by compiling `_Static_assert`s
against this build's own ios-arm64 install tree rather than assumed, which is the method to copy.
The same technique refutes a "non-stock AVCodecContext" reading elsewhere in D8: 0x154 is `slices`
and 0xa4 is `field_order` in this tree.

D4 is **mis-scoped, not live**: the source's four-level fallback now lives inside the
`filter.filter` closure at :246-257, outside this extent.

**D3's coupling is CONFIRMED across all three legs and must not be fixed alone.** 0x101a67274 is
the relocated side-data loop (reads `nb_side_data` 0x110 and `side_data` 0x108, dispatches on the
same nine `AVFrameSideDataType` values) and is VideoSwresample vtable slot 32; it writes the
VideoSwresample instance at +0xc20…+0xc68; slot 28 (0x101a660dc) reads those back and stores them
into `VideoVTBFrame+0x50`, which `field_offset_vector` names `edrMetaData`. Independently checked:
`FFmpegDecode.swift:225` is the **only** writer of `edrMetaData` in the whole tree —
`Resample.swift:101` and `Model.swift:528` are declarations. Deleting the inline loop before
landing `change()` regresses the field.

## `Coordinator.player(layer:currentTime:totalTime:)` — 0x1019db8e8, 261 instr

Lines premise refuted: 283-302 → the method is at 297-315.

Two divergences collapse on inspection. **D3's blocker is refuted** — `bufferTime` is already
declared at `KSVideoPlayer.swift:384`, so nothing must be added first — and **D3's field-order
claim is refuted too**: the binary's record order is `_currentTime, _totalTime, _bufferTime,
fileSize`, which matches source exactly. **D7 is refuted**: the keypath identities are readable,
not merely inferable — each pattern's computed-component ID at +0x1c resolves to the property's
method descriptor, naming all three outright. Root and value alone cannot discriminate them, which
is presumably why they were called unreadable.

Still live and now better grounded: D1, D2, D4, D5, D6, D8, D9. One real field divergence —
`subtitleModel` is declared in the source Coordinator and is **absent from the Coordinator's 15
binary field records**, with the records otherwise in source order across the gap.

New control-flow fact stated in none of the nine: a `playableTime` outside Int range aborts the
whole method before any timemodel write, sharing the epilogue with the currentTime/totalTime check.

## `KSPlayerLayer.readyToPlay(player:)` — 0x1019cda08, 356 instr

**The address appears in none of its four fix-queue JSONs**; it had to be recovered from the
decompile header. Lines premise refuted: 457-495 → the method is at 615-670.

**The CRITICAL is largely already applied.** Four of its five "binary-only" prologue statements are
present at :616-619 in the binary's own order — `addSubtitle(to: player.view)`, `bufferedCount = 0`,
`player.playbackRate = options.startPlayRate`, and the `compactMap` into `options.audioRecognizes`.
The fifth — the MainActor `Task` around `subtitleDataSource` / `selectedSubtitleInfo` — is still
unwritten, and its guard order is the **reverse** of the CRITICAL's wording: `subtitleDataSource`
is fetched first and branches away when nil, then `selectedSubtitleInfo` branches away when
non-nil. The Task's async body 0x1019d5b58 is a trie negative.

**The HIGH is stale.** `updateNowPlayingInfo()` is no longer called from this method; the extent
never touches the `MPNowPlayingInfoCenter` classref page. The private method survives at :996.

Two field names remain unrecoverable and must not be guessed: globals 0x1044e6188 (the
`bufferedCount` store) and 0x104c63520 / 0x1044e6190 (the `isAutoPlay` / `shouldSeekTo` guards).
The offset resolver answers `NOT RECOVERED` for all three.

## Tool defect found, deferred because the wave was live

`decode_string_literal.py --addr <body>` dies with
`RuntimeError: read at 0x104c634b0 failed` — it tries to decode a field-offset global as a string
and aborts before printing any non-SMALL literal. Rule 7 froze the tool layer while agents were
running; fix it before the next wave.

## Verdict hygiene

`reconstruction/verdicts/KSVideoPlayerView_openURL_101ac99ac.json` still has `recheck: null` and
`source_lines: null` while three of its seven divergences are applied. All three
`LimitSeparate…_s104_*` entries cite a `decompile_txt` that does not exist on disk.
