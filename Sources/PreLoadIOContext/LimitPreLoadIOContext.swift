import Foundation
import KSPlayer   // AbstractAVIOContext (superclass chain via PreLoadIOContext → CacheIOContext)
import FFmpegKit  // AVIOInterruptCB (inherited interrupt chain — FFmpeg C struct)

// LimitPreLoadIOContext — a PreLoadIOContext (1C.7) extended with size-limited
// preloading: file-size / readed-size caps, a moov-protection window, an exact-or-
// approximate playback byte position, a periodic time-sync threshold, cache-delete
// bookkeeping, and a (~40-byte) cached byte distribution. Reconstructed A-structure-
// faithful from the Forward 1.3.17 binary:
//
//   fields  — the 14 stored properties are orchestrator-RESOLVED (decode_composite +
//             width + init constants); NAMES + ORDER + COUNT + TYPES + DEFAULTS are
//             transcribed verbatim from the brief, NOT re-derived from the decompiles.
//             The ⚑ ones are best-effort (composite/width-inferred) → l2_field_gate
//             UNCHECKs them (expected 0 FLAG). CachedDistribution is an EMPTY
//             placeholder (its ~40-byte layout is UNRESOLVED → P8 (IO-completion)).
//   init    — the designated init (s37 @101b9d748, READABLE) sets LimitPreLoad's 14
//             own fields (all but the two caps carry the field defaults below) and
//             delegates to CacheIOContext's designated init (inherited through
//             PreLoadIOContext, which has no own init). The decompile ALSO inlines
//             PreLoadIOContext's own field defaults (loadMoreBuffer/_timeIndex/etc.) —
//             that is the COMPILER flattening the init chain; those belong to
//             PreLoadIOContext's declared defaults and are NOT re-set here.
//   methods — only the one cached small method s21 (@101b9d4dc) is reconstructed
//             (faithful spine + `// UNRESOLVED` for the unnamed-FUN parts). Its name is
//             devirt→inferred (no mangled method symbol). Everything else — the deep
//             limit/cache-distribution IO engine and the null devirt slots — is
//             UNRESOLVED→later phase, marked NOT fabricated (see the tail markers).
//
// PreLoadIOContext / CacheIOContext / TimeIndexEntry are in-module (already committed;
// no import). AVIOInterruptCB resolves via `import FFmpegKit` (the inherited interrupt
// field). Builds via `swift build --target PreLoadIOContext`.

// UNRESOLVED placeholder — ~40-byte composite (init zeroes 4 words + a UInt16=0x100);
// real layout → P2. Fabricating its fields is forbidden by the brief — empty only.
struct CachedDistribution {}

public class LimitPreLoadIOContext: PreLoadIOContext {
    // --- stored fields (binary __swift5_fieldmd order; defaults are the binary's
    //     flattened init constants from s37. Swift synthesizes accessors — do NOT
    //     hand-write get/set) ---

    // 0  canPreload: whether preloading is permitted. init true (binary: byte = 1).
    var canPreload: Bool = true
    // 1  maxFileSize: cap on total file size to preload. init = init param.
    var maxFileSize: UInt64
    // 2  maxReadedFileSize: cap on bytes read while preloading. init = init param.
    var maxReadedFileSize: UInt64
    // 3  moovProtectionSize: protected head window (moov atom). init 10_485_760
    //    (binary const 0xa00000).
    var moovProtectionSize: UInt64 = 10_485_760
    // 4  playbackBytePosition: current playback byte position (exact-or-approx). ⚑
    //    UInt64? (9-byte: payload + tag) — l2_field_gate binary type (brief table had
    //    Int64?; per the brief's FLAG rule the integer is set to the gate's binary
    //    type). init nil per brief (binary s37/s21 store payload 0 + tag byte 1).
    var playbackBytePosition: UInt64? = nil // ⚑ (composite Optional; gate-typed UInt64?)
    // 5  playbackBytePositionIsExact: whether playbackBytePosition is exact. init false
    //    (binary: byte = 0).
    var playbackBytePositionIsExact: Bool = false
    // 6  _lastSyncedTime: last time a sync occurred. init -1.0 (binary const
    //    0xbff0000000000000).
    var _lastSyncedTime: Double = -1.0
    // 7  syncThreshold: min interval between syncs. init 1.0 (binary const
    //    0x3ff0000000000000).
    var syncThreshold: Double = 1.0
    // 8  lastCheckCacheSize: cache size at last delete-check. ⚑ width-inferred UInt64;
    //    init 0.
    var lastCheckCacheSize: UInt64 = 0 // ⚑ (width-inferred; gate UNCHECKED)
    // 9  deleteCheckThreshold: cache growth before a delete-check. ⚑ width-inferred
    //    UInt64; init 4_194_304 (binary const 0x400000).
    var deleteCheckThreshold: UInt64 = 4_194_304 // ⚑ (width-inferred; gate UNCHECKED)
    // 10 cachedDistribution: cached byte-distribution composite. ⚑ EMPTY placeholder
    //    (~40-byte; init zeroes 4 words + a UInt16=0x100 — real layout P2).
    var cachedDistribution: CachedDistribution = CachedDistribution() // ⚑ placeholder (gate UNCHECKED)
    // 11 cachedDistributionLogicalPos: logical position the distribution covers. ⚑
    //    Int64; init -1 (binary const 0xffffffffffffffff).
    var cachedDistributionLogicalPos: Int64 = -1 // ⚑ (composite/width-inferred; gate UNCHECKED)
    // 12 cachedDistributionEntryCount: entries in the distribution. field-record Int;
    //    init -1 (binary const 0xffffffffffffffff).
    var cachedDistributionEntryCount: Int = -1
    // 13 lastKnownCachedSize: last observed cached size. ⚑ width-inferred UInt64;
    //    init 0.
    var lastKnownCachedSize: UInt64 = 0 // ⚑ (width-inferred; gate UNCHECKED)

    // --- init (designated; s37 @101b9d748, READABLE) ---
    //
    // s37 sets all 14 own fields then delegates to CacheIOContext's designated init.
    // The constant fields carry the declared defaults above, so the init body sets only
    // the two caps from params and delegates to super; the super call is
    // CacheIOContext's designated init (PreLoadIOContext has no own init → inherited).
    // Arity/order of the leading params is inferred (no init mangled symbol); the field
    // stores (maxFileSize/maxReadedFileSize) and the super-delegation are explicit and
    // grounded in the decompile (param_6 → maxFileSize, param_7 → maxReadedFileSize;
    // FUN_101b86d38 = CacheIOContext's designated init).
    init(download: URLContextDownload?, cacheKey: String, bufferSize: Int32 = 32 * 1024,
         saveFile: Bool, isReadComplete: Bool, maxFileSize: UInt64, maxReadedFileSize: UInt64) {
        self.maxFileSize = maxFileSize            // binary s37: self.maxFileSize = param_6
        self.maxReadedFileSize = maxReadedFileSize // binary s37: self.maxReadedFileSize = param_7
        // binary s37: the remaining 12 own fields are set to the constants carried as the
        //   declared defaults above; PreLoadIOContext's inlined field inits in the
        //   decompile (loadMoreBuffer/_timeIndex/_playbackSnapshot/etc.) are the compiler
        //   flattening the chain and belong to PreLoadIOContext — NOT re-set here.
        // binary s37: delegates to CacheIOContext's designated init (FUN_101b86d38),
        //   inherited through PreLoadIOContext.
        super.init(download: download, cacheKey: cacheKey, bufferSize: bufferSize,
                   saveFile: saveFile, isReadComplete: isReadComplete)
    }

    // --- methods (only the one cached small method; name devirt→inferred) ---

    // s21 @101b9d4dc — `func resetPlaybackPosition()` (name inferred, devirt; 40 instr).
    //   FAITHFUL SPINE. The decompile resets the playback-position state: under a write
    //   access to playbackBytePosition it stores payload 0 + tag byte 1, sets
    //   playbackBytePositionIsExact = false, and _lastSyncedTime = -1.0; then, under
    //   PreLoadIOContext's inherited _playbackSnapshotLock, it nils _playbackSnapshot
    //   (stores 0,0 + tag byte 1). The _playbackSnapshot/_playbackSnapshotLock writes
    //   touch INHERITED PreLoadIOContext fields (out of this class's field scope — owned
    //   by 1C.7) → that tail is preserved as an UNRESOLVED note, not re-derived here.
    func resetPlaybackPosition() { // name inferred (devirt)
        // binary s21: _swift_beginAccess(&playbackBytePosition); store payload 0 + tag 1.
        //   Brief default is nil; the binary writes .some(0). Match the binary store here:
        playbackBytePosition = 0
        playbackBytePositionIsExact = false      // binary: byte = 0
        _lastSyncedTime = -1.0                    // binary const 0xbff0000000000000
        // UNRESOLVED → P8 (IO-completion) (s21 tail @101b9d4dc): the binary then locks PreLoadIOContext's
        //   inherited _playbackSnapshotLock (objc_stub::lock(self._playbackSnapshotLock)),
        //   nils _playbackSnapshot (*p=0; p[1]=0; tag byte=1), and unlocks. Those are
        //   INHERITED PreLoadIOContext fields owned by 1C.7 (not in this class's
        //   reconstruction scope) → preserved as a faithful note, NOT re-set here.
    }

    // UNRESOLVED → later phase (do NOT reconstruct — no readable body and/or their calls
    //   are stripped FFmpeg the P2 oracle names — fabrication risk):
    //   DEEP ENGINE (limit / cache-distribution IO → P2):
    //     • s39 (177 instr) @ —   — limit/cache-distribution IO engine
    //     • s44 (199 instr) @ —   — limit/cache-distribution IO engine
    //     • s43 (1009 instr) @ —  — limit/cache-distribution IO engine (deepest)
    //   DEVIRT (null, no body): slots 40, 41, 42.
    //   cache-distribution layout (CachedDistribution) is P2; limit/cache IO is P2.
    //   — NOT fabricated.
}
