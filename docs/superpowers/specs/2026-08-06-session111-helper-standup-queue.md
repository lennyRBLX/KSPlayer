# Session 111 — the private-helper standup queue, derived

Every number here is emitted by the script that produced this file, never transcribed by hand.
Regenerate with: `member_missing_triage.py --json T` -> `rank_member_missing.py --triage T`
-> `classify_compiler_helpers.py --addr` per distinct unnamed callee -> re-rank with `--helpers`.

## Shape

| quantity | value |
|---|---|
| MEMBER_MISSING rows | 68 |
| rows blocked on >=1 unnamed callee | 44 |
| DISTINCT unnamed callees behind them | 117 |
| ... classified HELPER | 29 helpers, 142 row-blockings |
| ... classified SOURCE | 72 helpers, 83 row-blockings |
| ... classified UNSURE | 16 helpers, 22 row-blockings |

`HELPER` = outlined value-witness / shared runtime helper with NO source counterpart. It must
never be named or written (s110 handoff §5). Those 29 are not work; they are noise the ranker
previously counted as blockers.

## The queue: SOURCE helpers by fan-in

Fan-in is how many BODIES call the helper; the rows column is DEDUPED, so the two can differ when
one row has several bodies (`0x1019c9cd4` reads 4 against 3 rows because `KSPlayerLayer.replace`
has two). Order by fan-in: the head of this list is worth several rows each, the tail is one.

⚠️ Standing one of these up does NOT always mean declaring a named private member. These helpers
are absent from the export trie, so their NAMES cannot be read, and MEMORY rule 1 forbids writing
a name that was not read. Two dispositions, and the choice is per helper:
  · **inline** — the compiler outlined a source-level expression. The faithful spelling is that
    expression at the call site, and no name is needed. A fan-in of 1 is weak evidence for this.
  · **named private member** — only when the name is independently recoverable (a `#function`
    literal whose loaded length matches, a `KSLog` file/line argument, an objc selector). See
    `[[recover-swift-function-name-false-anchors]]`: two of three confident hits on these were
    false. Where the name is not recoverable, the helper stays a `⚑` pin, not a guess.

| helper | fan-in | rows it gates |
|---|---|---|
| `0x1019c9cd4` | 4 | KSPlayerLayer.changePlaybackTime, KSPlayerLayer.replace, KSPlayerLayer.reset |
| `0x1019c7410` | 2 | KSComplexPlayerLayer.reCheckSubtitle, KSComplexPlayerLayer.stop |
| `0x1019c7454` | 2 | KSComplexPlayerLayer.pictureInPictureControllerDidStartPictureInPicture, KSComplexPlayerLayer.reCheckSubtitle |
| `0x1019c9a68` | 2 | KSPlayerLayer.replace |
| `0x1019d1d70` | 2 | KSComplexPlayerLayer.pipStart, KSComplexPlayerLayer.readyToPlay |
| `0x101b94bcc` | 2 | CacheIOContext.close, HLSCacheIOContext.parseM3U8 |
| `0x101ba3fd0` | 2 | LimitPreLoadIOContext.reuseEntry, LimitSeparatePreLoadIOContext.reuseEntry |
| `0x10245e7d8` | 2 | AssIncrementImageRenderer.add, AssIncrementImageRenderer.updateTextStyle |
| `0x10245f0e0` | 2 | AssIncrementImageRenderer.flush, AssIncrementImageRenderer.updateTextStyle |

Plus **63** SOURCE helpers with fan-in 1 (one row each):

```
  0x1019a26a8  0x1019ac164  0x1019ac5b4  0x1019ad650  0x1019afab0  0x1019b3c2c
  0x1019b611c  0x1019c1690  0x1019c1ca4  0x1019c2b50  0x1019c2c64  0x1019c2e88
  0x1019c835c  0x1019d24c0  0x1019d2bb0  0x1019d5978  0x1019d5d38  0x1019d8d28
  0x1019e1b6c  0x1019faf54  0x101a0133c  0x101a08744  0x101a1f188  0x101a1f1bc
  0x101a3e510  0x101a47ae0  0x101a4b20c  0x101a595d8  0x101a61f60  0x101a71b00
  0x101a7c2e4  0x101a7c40c  0x101a82044  0x101a8241c  0x101a824e8  0x101a8299c
  0x101a86ea4  0x101a9364c  0x101a960dc  0x101a9f27c  0x101aa0390  0x101abff3c
  0x101ac00c8  0x101ac0a90  0x101ac11ec  0x101b863f0  0x101b88480  0x101b8c114
  0x101b8d0f4  0x101b906c8  0x101b91728  0x101b94410  0x101b945b0  0x101b94910
  0x101b94b98  0x101b94c0c  0x101b94fd4  0x101b951c4  0x101b95200  0x101b9bfb8
  0x101bac9a8  0x101baedc8  0x101baf98c
```

## UNSURE — adjudicate before treating as either

| helper | fan-in | rows it gates |
|---|---|---|
| `0x101a460e8` | 3 | KSMEPlayer.reset, MEPlayerItem.resumeFromPreload, MEPlayerItem.send |
| `0x101b91580` | 3 | CacheIOContext.addEntry, CacheIOContext.close, CacheIOContext.seek |
| `0x10016cb68` | 2 | LimitPreLoadIOContext.reuseEntry, LimitSeparatePreLoadIOContext.reuseEntry |
| `0x101ab2540` | 2 | KSPlayerLayer.reset, KSPlayerLayer.select |
| `0x100036e98` | 1 | HLSCacheIOContext.read |
| `0x1019ac888` | 1 | KSOptions.removeHeader |
| `0x1019b1080` | 1 | CacheIOContext.seek |
| `0x1019b3b50` | 1 | KSOptions.removeHeader |
| `0x1019c4720` | 1 | KSOptions.removeHeader |
| `0x1019c80fc` | 1 | KSComplexPlayerLayer.pipStart |
| `0x1019d5bd8` | 1 | KSComplexPlayerLayer.finish |
| `0x101a31310` | 1 | DoviDisplayModel.set |
| `0x101a5960c` | 1 | MEPlayerItem.send |
| `0x101a767a8` | 1 | Anime4KPipeline.configure |
| `0x101ab2de4` | 1 | KSPlayerLayer.select |
| `0x1030c0994` | 1 | HLSCacheIOContext.read |
