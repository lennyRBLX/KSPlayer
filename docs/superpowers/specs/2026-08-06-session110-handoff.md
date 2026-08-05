# Session 110 handoff — KSPlayer / Forward-TF 1.3.17 reconstruction

**Status at write time: MEMBER_MISSING 76** (was 108 at s109 start). This document supersedes the
s109 handoff's §23–§24t appendix, which grew by accretion; everything durable from it is
consolidated here by topic. The s109 file stays in the repo as the raw trail.

> This document is ORIENTATION. It authorises no work. See
> `2026-08-06-session110-PROMPT.md` for the verify-then-stop entry point.

---

## 1. Verify first — derive these, do not quote them

```bash
python3 scripts/recon_gate.py --mode handoff
```
```bash
python3 scripts/pin_sweep.py --every
```

| what | expected |
|---|---|
| MEMBER_MISSING | 76 |
| ACCESS | 26 |
| NOT_IN_TRIE | 23 |
| AMBIGUOUS_OVERLOAD | 10 |
| TYPE_DIVERGENCE | 4 |
| gate | PASS 44 · ANOMALY 6 · FAIL 4 |
| build | 4/4 (`DEVELOPER_DIR=… scripts/validate_build.sh`) |
| KSPlayer | branch `forward`, tree clean, recent log showing the s110 docs commits (no hash pinned — writing these files moves HEAD) |
| FFmpegKit HEAD | `12f0899` on `forward-recon-shim` |

The 4 gate FAILs are **pre-existing** — each traces to a verdict file predating s109. They were
confirmed pre-existing at s109 start and the gate line has not moved since.

Two selfchecks carry disk-only fixes and must both print `SELFCHECK PASS`:
```bash
python3 scripts/recover_field_offsets.py --selfcheck && python3 scripts/field_offset_vector.py --selfcheck
```

---

## 2. Two environment facts that will bite you if you don't know them

**FFmpegKit was on a DETACHED HEAD.** s110 created branch `forward-recon-shim` at `9d7a0d1` so the
shim commit (`12f0899`) would not be left unreferenced. That repo also carries ~1167 unrelated dirty
files (BuildFFMPEG.swift, avutil_shim.h, the xcframeworks) which are deliberately NOT staged —
**never `git add -A` there.**

**`play/scripts/` is gitignored and stays that way** (user decision). Two pieces of s109 work live
there and nowhere else. This is not a blocker — use and fix them in place:
- `bind_oracle.py` — its row regex previously anchored the symbol at end-of-line and silently
  dropped every `(weak_import)` row. Fixed; recovers **377 rows**, 0 changed, 0 lost.
- `helper_fingerprint.py` — **new**, see §5.

---

## 3. What the FFmpegKit shim bought

`Sources/FFmpegKit/include/avformat_shim.h` now declares four internal libavformat prototypes,
verbatim from FFmpeg-n8.1.1's `url.h`:

    int64_t ffurl_seek2(void *urlcontext, int64_t pos, int whence);        // url.h:207
    int ffurl_closep(URLContext **h);                                      // url.h:234
    int ffurl_read2(void *urlcontext, uint8_t *buf, int size);             // url.h:171
    int ffurl_read_complete(URLContext *h, unsigned char *buf, int size);  // url.h:193

That is the file's own established pattern — `ff_isom_write_vpcc` sits there for the same reason,
and the file already declares `URLContext` and `ffurl_context_class`. **Note the `*2` naming:**
`url.h` defines `ffurl_seek`/`ffurl_read` as `static inline` wrappers that only forward, so the
unsuffixed names never survive as linkable symbols.

It unblocked six members: `URLContextDownload.fileSize/seek/close/read`,
`HLSCacheIOContext.fileSize/seek`.

---

## 4. The remaining 76, organised by BLOCKER CLASS

This is the useful cut. The rows are not uniformly "big"; they fail in four distinct ways.

### 4a. Unnamed private helper (the dominant class)
The row reads cleanly and then calls a private function no naming route resolves. **Profile it with
`helper_fingerprint.py` before concluding anything** (§5).

| row | addr | blocked on |
|---|---|---|
| `KSOptions.makeDecode` | 0x1019b604c | 0x1019b611c (362 instr) — profiled: it is the **decoder-selection switch**, constructing `FFmpegDecode` / `SubtitleDecode` / `VideoToolboxDecode`. Only the selection predicate (string compares over codec names) is left. |
| `KSComplexPlayerLayer.reCheckSubtitle` | 0x1019d1eb4 | 0x1019c7410 — **decoded**: dispatches PiP req1 with the literal `"delegate"`. req1 itself is still unnamed. |
| `KSComplexPlayerLayer.readyToPlay` | 0x1019d1cd0 | 0x1019d1d70 (81 instr) + `reCheckSubtitle` above |
| `AssImageParse.parse` | 0x101a8f5a8 | chain sized end to end — see §4c |
| `FFmpegSubtitleParse.parse` | 0x101a9eff4 | the `FFmpegSubtitle` standup — see §4d |

### 4b. Type divergence gates the body
| row | gate |
|---|---|
| `CacheIOContext.clearOtherCache` @0x101b8d948 | `tmpURL` is non-optional per its `vpWvd` (no `Sg`), but the source has `URL?`. Retyping builds with ONE error — not initialised at `super.init` — and the satisfying value is written by a virtual call at 0x101b8745c inside the init's UNRESOLVED region. **Body already transcribed into CacheIOContext.swift.** Do not spell it `URL!`. |

### 4c. Chain — every link sized, nothing undiscovered
`AssImageParse.parse` (73 instr, read) → `AssIncrementImageRenderer.init(content: String)` (103
instr; three stores located, `subtitles` identified by its `__swiftEmptyArrayStorage` value) →
**0x101a946bc (345 instr, unnamed)** which produces the `renderer` field.
Bonus already banked: this pinned the **TYPE_DIVERGENCE** row for
`AssIncrementImageRenderer.init` — the binary form is `init(content: Swift.String)`, source has
`init(renderer: AssImageRenderer)`. That divergence needs only the retype now.

### 4d. Undeclared type must be stood up
`FFmpegSubtitle` — an **actor**, InstanceSize `0xa8` (matches the caller's `swift_allocObject(168, 15)`).
All eight fields typed: `formatContext: FormatContext`, `decode: SubtitleDecode`,
`subtitleStreamIndex: Int32`, `preTime`/`startTime`/`endTime: Double`, `parts: [SubtitlePart]`.
Both class-typed fields already exist in Sources, so it does not cascade.
Blocked on `init(url:) throws` @0x101a9f27c (409 instr): three fields are `let`, so a spine cannot
stand in. Stores located at 0x101a9f5b4 / 0x101a9f5e4 / 0x101a9f6c4; `FormatContext.init(formatCtx:
fileSize:interrupt:ioContext:fontsDir:)` @0x101a350bc recovered. Three helpers still unnamed
(0x1019aba90, 0x101a391bc, 0x101a392a0).

### 4e. Async — a distinct category
`KSAVPlayer.createPlayerItem` @0x1019a3ccc is `async throws`. Its 36 instructions are only the
async **prologue** (`orr x29, x29, #0x1000000000000000`, frame stores, tail branch into the
continuation). **Never size an async row from its entry point** — it is the thunk trap one level up.

### 4f. Permanently unrecoverable
`IOSVideoPlayerView.toggleBottomSlimProgress` and `updateTitle` both fold onto `0x10198eb18`, the
`swift_deletedMethodError` stub. Not blocked — gone.

### 4g. Blocked on non-binary-derived isolation
`KSOptions.displayEnumVR` / `displayEnumVRBox` — values fully read since s106. Both escape routes
were MEASURED in s109: dropping `@MainActor` from `SphereDisplayModel` builds 4/4 but changes
nothing (isolation comes from the `DisplayEnum` protocol); marking the inits `nonisolated` just
moves the error onto `KSOptions.sceneSize` and `super.init()`. Landing two read values would cost
three invented annotations. Left blocked deliberately.

---

## 5. `helper_fingerprint.py` — the s109 tool, and how to use it

Profiles an unnamed function **structurally**: type-metadata accessors it calls (the TYPES it
materialises), every `swift_allocObject(size, alignMask)` site (match against
`field_offset_vector`'s InstanceSize), named in-module calls that bound its role, and `__got`
references. `--selfcheck` anchors on a trie-NAMED function and requires the profile to be
consistent with that known signature (MEMORY rule 11).

**It emits evidence and never invents a name** — deliberately unlike `recover_swift_function_name`.

⚠️ **Documented limitation, in the code:** the `__got` section pairs every tracked `adrp` page with
every `ldr` offset, so it **over-reports**. Treat that section as candidates to confirm at the
instruction. The metadata-accessor and `allocObject` sections do not share the flaw.

**Check for a compiler artifact FIRST.** A helper whose whole body is
`__swift_instantiateConcreteTypeFromMangledName` followed by a dispatch through a VWT slot
(+0x0 initBufferWithCopyOfBuffer, +0x8 destroy, +0x10 initWithCopy, +0x18 assignWithCopy,
+0x20 initWithTake…) is an **outlined value-witness function with no source counterpart**. It must
never be named or written. s109 found four: 0x101aa0308 (destroy), 0x10002e588 (copy), 0x100012a78
and 0x10003751c (destroys). One disassembly removes such a helper from the queue; a naming hunt on
it can never succeed.

---

## 6. Techniques that paid, and traps that cost

**Identify a field by what is STORED into it, never by position.** Offset globals are NOT emitted in
field-record order — hit twice, in `MetalSubtitleView` and `KSComplexPlayerLayer`, and it silently
yields a plausible wrong map. Use: store WIDTH (`strb` ⇒ Bool), the empty-collection singleton
(`__swiftEmptyArrayStorage` 0x104112d00 / `__swiftEmptyDictionarySingleton` 0xd08 /
`__swiftEmptySetSingleton` 0xd10 — adjacent, and telling them apart is the whole trick), an
immediate (0x3ff0000000000000 ⇒ 1.0), or the type of the parameter it feeds.
See `[[offset-globals-not-in-field-record-order]]`.

**A recorded blocker is only as good as the error it quotes.** Three "settled" blockers fell in s109,
all failing the same way — one symptom generalised to a sibling without re-testing. Re-run the
compiler on *that* member and read the error it actually emits.
See `[[recorded-blocker-only-as-good-as-its-error]]`.

**An ICF fold spanning a base and its subclasses, over a `private` field, means the subclass rows are
`super.<member>()` forwards — not copies.** Swift denies a subclass access to a `private` superclass
member even in the same file, so the forward is the only spelling that both compiles and inlines to
the byte-identical body the fold implies. This is the `shouldContinueRead` row that a previous
session broke by widening `CacheIOContext._isClosed` to `internal` (ACCESS 26→27, reverted). The
privacy is PROVEN: the trie carries `_isClosed33_D69EFE1402863CA716A3171C7DB6DFB9LLSbvpfi`, and a
per-file discriminator is what `private` emits.

**An ICF fold says NOTHING about signatures.** `AbstractAVIOContext.read` and `write` share impl
0x100137314 because both bodies are `{ size }` — yet `read` takes `UnsafeMutablePointer` and `write`
takes `UnsafePointer`. Probe each member's mangling separately even when they demonstrably share a
body.

**Naming an FFmpeg symbol the oracle cannot narrow.** `ffmpeg_name_oracle` returns 59 band
candidates for 0x1030c07ac. The answer came from three independent places: this build's own `url.h`
(the `static inline` forwarder cannot be a call target), a log literal inside the binary
(`"more ffurl_seek2 "`), and the call shape (`AVSEEK_SIZE` = 0x10000, avio.h:468). For
`ffurl_close` vs `ffurl_closep`, the ACCESS FLAGS settle it: a `0x21` Modify|Tracking access passing
the field's ADDRESS is the two-star form. For `ffurl_read2` vs `ffurl_read_complete`, the
discriminator is the `retry_transfer_wrapper` `size_min` guard — an extra `cmp w2,#1 / b.lt` means
`size_min` is the runtime size.

**`recover_swift_function_name` trust rule — CORRECTED in s109.** The old rule gated on
`labels>=1`; that separates nothing. The real discriminator is an **early in-body materialisation
whose loaded length matches**. Evidence, all three `confidence=high, labels=0`:
`pictureInPictureViewController` @0x1019c7454 materialises at instr ~5 with `mov x0,#0x1e` = 30 =
its length ⇒ GENUINE; `cues_parsing_deferred` @0x101a392a0 ⇒ FALSE (an FFmpeg AVOption key);
`FFmpegAssetTrack` @0x1019aba90 ⇒ FALSE (a TYPE name). Two smells: a recovered name that is a TYPE
in the image, or has FFmpeg/AVOption shape. See `[[recover-swift-function-name-false-anchors]]`.

**Rank rows by in-module callee count, not instruction count.** Disassemble each body's extent and
count `bl` targets below the stub-island floor `0x103451708`; zero in-module callees means it reads
end to end. That ranking found the rows s109 landed. Two caveats: the triage's instruction count is
the THUNK's (five rows that looked 1–4 instructions were thunks into 107/181/227-instruction
bodies), and for async rows it is the PROLOGUE's (§4e).

---

## 7. What s109 landed (32 rows)

`HLSCacheIOContext.clearCache` · `KSOptions.defaultFont / recordDir / subtitleDynamicRange /
translationTarget` · `KSPlayerLayer.isPictureInPictureActive` · `KSAVPlayer.configPIP` ·
`KSMEPlayer.configPIP` · `KSComplexPlayerLayer.pause` · `LimitPreLoadIOContext.syncPlaybackPosition`
· `URLContextDownload.fileSize / seek / close / read` · `HLSCacheIOContext.fileSize / seek` ·
`ReadCacheIOContext.close` · `cacheList` ×2 · `shouldContinueRead` ×2 · plus the earlier batch
(`SubtitleDataSource.isSrt`, `TextPosition.alignment`, `SubtitlePart.change` ×3, `KSAVPlayer.reset /
process(error:) / cachedTimeRanges`, `Anime4KPreset.autoSelect`, `IOSVideoPlayerView.showPromptMessage
/ hidePrompt`, `DirectoryWatcher` renames, `KSMEPlayer.cachedTimeRanges`, `KSOptions.resolveIO`,
`LimitSeparatePreLoadIOContext.urlPos`).

Also landed: all eight `DownloadProtocol` requirements named (the "deferred residue" discharged),
PiP req2 `init?(playerLayer:)` and req3 `required init(contentSource:)` declared, and two source
corrections — `clearPlaybackPosition` wrote `= 0` where the binary writes `nil`, and
`AbstractAVIOContext.read`'s pointer type.

---

## 8. ⏳ Waiting on you

1. **~~FFmpegKit shim~~ — DONE.** Committed `12f0899` on branch `forward-recon-shim`. You may want
   to decide where that branch goes relative to your detached-HEAD work.
2. **`play/scripts/` stays gitignored — acknowledged.** Recorded in §2 as a fact, not a blocker.
3. **Nothing else is blocked on a decision.** The remaining 76 are all binary reads; §4 says which
   kind each one is.
