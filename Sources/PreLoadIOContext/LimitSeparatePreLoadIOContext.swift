import Foundation
import KSPlayer   // AbstractAVIOContext (superclass chain via CacheIOContext)
import FFmpegKit  // FFmpeg C types reachable through the CacheIOContext chain

// LimitSeparatePreLoadIOContext — CacheIOContext (1C.7) extended with a separate
// "load-more" download path and a size-limited / time-indexed preload engine.
//
// Reconstructed A+ structure-faithful from the Forward 1.3.17 binary:
//   fields  — the 8 own stored properties are orchestrator-RESOLVED (reflection
//             field-record + l2_field_gate + the cached designated init); NAMES +
//             ORDER + COUNT + TYPES transcribed verbatim from the brief's table.
//             The ⚑ ones are best-effort (unmapped stdlib int / pointer / in-module
//             class) and flagged `// ⚑`. All CacheIOContext fields are inherited.
//   inits   — designated s22 @101ba4650 (cached, READABLE): sets all 8 own fields
//             directly (loadMoreBuffer=nil, fakeUrlPos=0, moreUrlPos=0, _timeIndex=[],
//             _timeIndexLock=NSLock(), moreDownload=param-copied, maxFileSize=param_7,
//             maxReadedFileSize=param_8) then delegates to CacheIOContext's designated
//             init FUN_101b86d38. Arity/param-order inferred (no mangled init symbol);
//             the field stores + super-delegation are explicit in the decompile.
//           — s21 init is devirtualized (`new-unresolved`, no readable body) →
//             UNRESOLVED→P8 (IO-completion), NOT reconstructed.
//   methods — s27 @101ba4bd0 (cached, 109 instr; name devirt→inferred): a locked,
//             sorted insert-or-update into _timeIndex keyed by position. Faithful
//             spine; the Swift-synthesized stdlib Array internals (COW / insert /
//             grow) are noted as UNRESOLVED rather than transcribed by FUN-address.
//           — the deep separate-download / limit IO engine (s29/s30/s31) is stripped
//             FFmpeg → UNRESOLVED→P8 (IO-completion), NOT reconstructed. s28 (1-instr stdlib stub) is
//             skipped.
//
// CacheIOContext / URLContextDownload / TimeIndexEntry are in-module (already
//   committed; no import). PreLoadIOContext builds green via
//   `swift build --target PreLoadIOContext`.
public class LimitSeparatePreLoadIOContext: CacheIOContext {
    // --- stored fields (binary __swift5_fieldmd order; 8 own properties) ---

    // 0  maxFileSize: byte cap for this context. Designated init param-fed (param_7,
    //    8-byte store at +maxFileSize).
    var maxFileSize: UInt64 = 0
    // 1  maxReadedFileSize: cap on bytes read. Designated init param-fed (param_8,
    //    8-byte store at +maxReadedFileSize).
    var maxReadedFileSize: UInt64 = 0
    // 2  loadMoreBuffer: scratch buffer for the separate "load-more" download path.
    //    Designated init zeroes it (nil). ⚑ (element/optionality inferred; pointer width).
    var loadMoreBuffer: UnsafeMutablePointer<UInt8>? // ⚑
    // 3  fakeUrlPos: synthetic url position used by the separate-download bookkeeping.
    //    Designated init zeroes it. ⚑ (gate-UNCHECKED; UInt64 by the position-field pattern).
    var fakeUrlPos: UInt64 = 0 // ⚑
    // 4  moreDownload: the secondary URLContextDownload feeding the load-more path.
    //    Designated init copies a value into it (FUN_1001263e0 value-copy from param_2).
    //    ⚑ (name + shape inferred; copied, not retained-as-new).
    var moreDownload: URLContextDownload? // ⚑
    // 5  moreUrlPos: current position within the secondary download. Designated init
    //    zeroes it. ⚑ (gate-UNCHECKED; UInt64 by the position-field pattern).
    var moreUrlPos: UInt64 = 0 // ⚑
    // 6  _timeIndex: sorted-by-position index of (position,time) entries. Designated
    //    init defaults it to [] (PTR___swiftEmptyArrayStorage). field-record.
    var _timeIndex: [TimeIndexEntry] = []
    // 7  _timeIndexLock: serializes _timeIndex mutation. Designated init allocs
    //    NSLock() (objc_allocWithZone + init on __NSLock).
    var _timeIndexLock: NSLock = NSLock()

    // --- inits ---

    // Designated init s22 @101ba4650 → inner FUN_101ba4650 (cached, READABLE). The
    // decompile sets all 8 own fields directly:
    //   loadMoreBuffer = nil (+loadMoreBuffer = 0), fakeUrlPos = 0, moreUrlPos = 0,
    //   _timeIndex = [] (PTR___swiftEmptyArrayStorage), _timeIndexLock = NSLock()
    //     (allocWithZone(__NSLock) + init), moreDownload = param_2 (value-copied via
    //     FUN_1001263e0), maxFileSize = param_7, maxReadedFileSize = param_8,
    // then delegates to CacheIOContext's designated init FUN_101b86d38 with the
    // download value (param_1, value-copied) + cacheKey/bufferSize/saveFile/
    // isReadComplete (param_3..param_6, param_9). Arity/param-order inferred (no
    // mangled init symbol); the field stores + the super-delegation are explicit in
    // the decompile and transcribed here. The `moreDownload` and `download` values are
    // copied (FUN_1001263e0) rather than freshly built — reflected as plain params.
    public init(download: URLContextDownload?, moreDownload: URLContextDownload?,
                cacheKey: String, bufferSize: Int32 = 32 * 1024, saveFile: Bool,
                isReadComplete: Bool, maxFileSize: UInt64, maxReadedFileSize: UInt64) {
        self.loadMoreBuffer = nil          // binary: *(self+loadMoreBuffer) = 0
        self.fakeUrlPos = 0                // binary: *(self+fakeUrlPos) = 0
        self.moreUrlPos = 0                // binary: *(self+moreUrlPos) = 0
        self._timeIndex = []               // binary: *(self+_timeIndex) = swiftEmptyArrayStorage
        self._timeIndexLock = NSLock()     // binary: allocWithZone(__NSLock) + init
        self.moreDownload = moreDownload   // binary: FUN_1001263e0 value-copy of param_2
        self.maxFileSize = maxFileSize     // binary: *(self+maxFileSize) = param_7
        self.maxReadedFileSize = maxReadedFileSize // binary: *(self+maxReadedFileSize) = param_8
        super.init(download: download, cacheKey: cacheKey, bufferSize: bufferSize,
                   saveFile: saveFile, isReadComplete: isReadComplete) // binary: FUN_101b86d38
    }

    // UNRESOLVED → P8 (IO-completion): s21 init — devirtualized (`new-unresolved`); the binary has no
    //   readable body for it (the designated reconstructed above is s22). No body to
    //   reconstruct → not fabricated. — P2

    // --- methods ---

    // s27 @101ba4bd0 — `func addTimeIndex(position:time:)` (name inferred, devirt;
    //   109 instr). FAITHFUL SPINE.
    //
    // The cached decompile locks _timeIndexLock, then performs a SORTED insert-or-update
    // into _timeIndex keyed by `position` (the ulong param_2, compared against each
    // entry's +0x20 / TimeIndexEntry.position over a 0x10-stride buffer):
    //   • scan for the first entry whose position >= the new position;
    //   • position already present (==)  → replace that entry in place;
    //   • a greater position found (>)   → insert the new entry before it
    //                                      (FUN_101babf50 = Array insert-at-index);
    //   • none found (loop falls off)    → append (reserve/grow + count+1),
    //                                      writing +0x20 = position, +0x28 = time;
    // then unlock. The mutations go through Swift's COW machinery
    // (_swift_isUniquelyReferenced + FUN_101b94710 array-grow + FUN_101bac23c) which
    // the compiler synthesizes from the Array operations below — those unnamed-FUN
    // internals are NOT transcribed by address (see the UNRESOLVED note). `time` is the
    // 8-byte value stored into the entry's time slot (+0x28); `position` is the UInt64
    // search key (+0x20).
    //
    // UNRESOLVED → P8 (IO-completion): the exact COW/grow sequencing (FUN_101b94710 array-grow,
    //   FUN_101bac23c, FUN_101babf50 insert, _swift_isUniquelyReferenced uniqueness
    //   checks) is Swift-synthesized stdlib Array machinery — reproduced here via the
    //   equivalent Array operations rather than transcribed by FUN-address; the
    //   lock / sorted-search / insert-update-append spine is the faithful structure. — P2
    func addTimeIndex(position: UInt64, time: Double) { // name inferred (devirt)
        _timeIndexLock.lock()                  // binary: objc_stub::lock(_timeIndexLock)
        defer { _timeIndexLock.unlock() }      // binary: objc_stub::unlock(self) on every exit
        // binary: scan for the first entry with position >= the new position.
        if let idx = _timeIndex.firstIndex(where: { $0.position >= position }) {
            if _timeIndex[idx].position == position {
                _timeIndex[idx] = TimeIndexEntry(position: position, time: time) // == → replace in place
            } else {
                _timeIndex.insert(TimeIndexEntry(position: position, time: time), at: idx) // > → insert before (FUN_101babf50)
            }
        } else {
            _timeIndex.append(TimeIndexEntry(position: position, time: time)) // none → append (grow + count+1)
        }
    }

    // s28 — 1-instruction stdlib stub → skipped (no reconstructable body).

    // UNRESOLVED → P8 (IO-completion) (deep separate-download / limit IO engine — NOT reconstructed;
    //   their symbols are devirt and their calls are stripped FFmpeg the P2 oracle
    //   names; declare nothing beyond these markers):
    //   • s29 @ (346 instr) — separate-download IO
    //   • s30 @ (433 instr) — limit IO engine
    //   • s31 @ (250 instr) — separate-download / limit IO
    //   stripped-FFmpeg saturated. — P2
}
