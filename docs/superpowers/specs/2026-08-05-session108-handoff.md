# Session 108 handoff — close-out of the s107 MEMBER_MISSING drive

**ORIENTATION ONLY. This document authorizes no work.**

The long accumulated log for this drive is
`2026-08-04-session107-handoff.md` (sections §2a–§2ai). That file is the reference; this one is the
readable close-out. Where they disagree, the older file's §-sections carry the addresses and are
authoritative on detail — but note that **six of its sections were CORRECTED during the drive** and
one is marked superseded. Read §2n's superseded banner and §2o's correction banner before quoting
either.

---

## 1. Verify first (do these, then stop)

Run from `/Users/jweaver/Desktop/Work/swift/play`. Confirm each rather than quoting it, and say so
if any disagrees:

1. `python3 scripts/pin_sweep.py --every` → **MEMBER_MISSING 108**, ACCESS 26, NOT_IN_TRIE 24,
   AMBIGUOUS_OVERLOAD 10, TYPE_DIVERGENCE 4.
2. `python3 scripts/recon_gate.py --mode handoff` → **PASS 44 · ANOMALY 6 · FAIL 4**.
3. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/validate_build.sh` →
   **4/4**.
4. `git -C ../KSPlayer log --oneline -1` → **4168fb7** on branch **forward**; working tree clean
   (no non-`??` entries).
5. `python3 scripts/recover_field_offsets.py --selfcheck` and
   `python3 scripts/field_offset_vector.py --selfcheck` → both **SELFCHECK PASS**. These two carry
   this drive's tool fixes; if either fails, the fixes are gone (see §4).

The four gate FAILs are **pre-existing and not from this drive**: `agg_critical 6`, `agg_high 24`,
`agg_unresolved 1`, and `sc_wave_worklist` (`0x101a6ce44` = `VideoToolboxDecode.decodeFrame`, OPEN
since s93).

---

## 2. What moved

MEMBER_MISSING **159 → 108** across 145 commits on `forward`. Members landed, by owning type:

* `MediaPlayerProtocol` extension — `audioFormat`, `videoFormat`, `dynamicRange`, `subtitlesTracks`
* `CacheIOContext` — `cacheExists`, `firstEntryAfter/Contain/IndexContain/Equal`
* `CacheOnlyIOContext` — `entryList`, `fileSize()`, `seek(offset:whence:)`
* `MetalPlayView` — `rotation`, `drawable`, both PiP methods · `UIView` — `addSub`, PiP defaults
* `KSPlayerLayer` — `reachEndOfStream`, `makeUIView`, `pipStop`, two `KSComplexPlayerLayer` PiP delegates
* `IOSVideoPlayerView` — `pause()`, `play()`, `tapGestureAction`, `doubleTapGestureAction`
* `Anime4KPreset.displayName` · `Anime4KPipeline.isUpscaleSupported` + 2 private helpers
* `KSPlayerError` — `localizedDescription`, `errorDescription` · `SubtitlePart` — `text`, `isEmpty`
* `KSMEPlayer` — `sourceDidEOF`, `sourceDidClear`, `ioContext` · `KSAVPlayer.updatePlaybackBuffer`
* `DoviDisplayModel` stood up; `KSOptions.displayEnumDovi` declared
* `FFThumbnail` reshaped (3 stored fields, `image` computed, 2 inits)
* `MEPlayerDelegate` 5→7 requirements; `MediaPlayerDelegate` 5→7 (of 8)

---

## 3. Corrections made to earlier findings — read these before trusting the old file

Four recorded conclusions were **wrong** and would have caused bad work:

* **§2n** ruled two `shouldContinueRead` subclass rows "FALSE POSITIVES, skip them". Both classes
  carry genuine **override-table entries**. They are real rows. §2n is marked superseded by §2ad.
* **§2o**'s inheritance-artifact screen flagged `IOSVideoPlayerView.tapGestureAction` as an
  artifact. It is a real override; the screen cannot tell inheritance from an **ICF fold of two
  identical bodies**. Net artifacts in the queue: **zero**.
* **§2l** recorded both `sourceDidEOF` and `sourceDidClear` as calling `reachEndOfStream`. They
  differ by one instruction — `[x21,#0x30]` vs `[x21,#0x40]` — and the second is `playerDidClear`.
* **My own** `export_trie_oracle --owner` argument was not a test. `OWNER_MATCH` only says a symbol
  with that class's name exists at the address, which is true for inherited and overridden alike.
  **The override table is the test** (§2ad).

---

## 4. The three tool fixes — DISK-ONLY, verify they still exist

`play/scripts/` and `play/docs/` are both gitignored. These live on one machine:

1. **`field_offset_vector.py`** — was silently refusing **73 of 1064** classes. It built the literal
   `$s<len><Module><len><Class>CN`, but substitution compresses any class reusing a module word
   (`CacheIOContext` → `05CacheC0C`). Fallback added: prefilter on the MODULE token (never
   substituted), settle the class half with the toolchain demangler. 48 of the 73 now yield real
   static offsets.
2. **`recover_field_offsets.py` — the big one.** `globals_from_trie` had the same literal-token bug.
   `KSPlayerLayer` in module `KSPlayer` is spelled `0A5Layer`, so it reported "0 offset-globals" for
   a class the trie names fine. Fixed like-for-like: **1419 → 1575 named globals, +156 across 43
   classes, 0 lost.**
3. **`name_global_by_value(cls, glob, module)`** — new route in the same file. A `vpWvd` global
   *holds* the field's byte offset; on a `metadata_init=0` class that word is in the image, so the
   global is named with no accessor and no symbol. Reproduced six hand-derivations exactly.

**Substitution was the single most expensive recurring defect of this drive** — four separate
misses (`CacheIOContext` in a search, `KSPictureInPictureProtocol`'s `WP`, `KSPlayerError`'s 60+
symbols, and the two tools). **Never prefilter on a literal class token.**

---

## 5. Measured negatives — do not re-search these

* A `metadata_init=1` class's offset globals are **never written in `__text`**. The metadata
  completion function (descriptor + 44 + 8) calls `swift_initClassMetadata` with
  `x4 = metadata + 0x50`, filling the metadata's own vector; the runtime patches the globals. No
  symbol, no static value, no store site. (§2ai)
* `ffurl_seek`/`ffurl_read`/`ffurl_read_complete` cannot satisfy the commit gate even if the
  FFmpegKit shim is fixed — `ffmpeg_name_oracle --candidate` answers `UNKNOWN_SYM` because they are
  FFmpeg **internal** symbols, absent from the indexed libs. Four rows need both fixes. (§2s)
* Two rows have no recoverable body at all (`swift_deletedMethodError`). (§2t)

---

## 6. Where the remaining 108 sit

Shape, measured: **27** rows on classes the value-read route serves; **~74** on `metadata_init=1`
classes needing per-class field derivation; **7** unmapped.

**The one long chain, fully mapped:**

`SubtitleModel.subtitle(currentTime:playRatio:screenSize:)` → `KSPlayerLayer.changePlaybackTime` →
`MediaPlayerDelegate` req3 → `KSAVPlayer.changePlaybackTime`.

Both `changePlaybackTime` bodies are **read end to end and written out verbatim** in the old file.
The six `SubtitleModel` globals that blocked everything are **named** (§ "STEP 0 IS DONE"). The
`subtitle` body is structurally read. What remains is its trailing `Task` closure, which is *not*
reachable by following a call: the 128-byte context holds only captures, no function pointer, and
the callee dispatches through the context's type. That is its own async-runtime unit.

**Also known-blocked, with reasons recorded:** `KSComplexPlayerLayer` (13 rows) behind
`KSPictureInPictureProtocol`, which declares **10** requirements to source's 5;
`KSOptions.displayEnumVR`/`VRBox` behind a `@MainActor` over-annotation question;
`KSOptions.subtitleDynamicRange`/`translationTarget`/`defaultFont`/`recordDir` are `.modify`
coroutines on resilient types whose initializer expressions are not recoverable from call shape.

---

## 7. Two process notes worth keeping

* **Rank by transitive cost, not body size.** Size-only ranking picked three misleading targets in a
  row: `FFThumbnail.jpegData` (11 instr → whole-struct reshape), `urlPos` (24 → async thunk),
  `Coordinator.isRecord` (32 → a 412-instruction `didSet`). Add the sizes of `bl` targets that are
  in the Swift band **and unnamed in the trie**. It still cannot see across a coroutine split.
* **Compiling is a reading tool.** Twice, "declare the member" was really "fix the type it talks
  to" — `FFThumbnail`, and `SubtitleModel.subtitle`'s arity. The trie alone did not surface either.
