import Foundation

// CacheFileEntry — standalone cache-entry type (NO superclass). Shared dependency
// for the Wave-2 cache contexts (CacheIOContext / ReadCacheIOContext reference it).
//
// Reconstructed A+ structure-faithful from the Forward 1.3.17 binary:
//   fields  — __swift5_fieldmd reflection (NAMES + ORDER + COUNT authoritative).
//   inits   — s10 (101b900c4): inner FUN_101b90114 has explicit param→field stores  ⚑[tool=resolve_fun_pins ref=FUN_101b90114:0x101b90114 result=RESOLVES_UNIQUELY] = PreLoadIOContext.CacheFileEntry.init(url: Foundation.URL, position: Swift.UInt64) throws -> PreLoadIOContext.CacheFileEntry?
//             (url=param_1, position=param_2; saveFile=true) → GROUNDED framing,
//             with the Foundation file-open/size-read detail UNRESOLVED→P8 (IO-completion).
//             s9 (101b881f8): the DESIGNATED init, inner FUN_101b8fb0c — its  ⚑[tool=resolve_fun_pins ref=FUN_101b8fb0c:0x101b8fb0c result=RESOLVES_UNIQUELY] = PreLoadIOContext.CacheFileEntry.init(dir: Foundation.URL, position: Swift.UInt64, maxSize: Swift.UInt32?) throws -> PreLoadIOContext.CacheFileEntry
//             param_1 (url-derivation base) type is not deterministically
//             resolvable → left UNRESOLVED, no fabricated signature. — P2.
//   methods — s12/s13/s14 (101b90620 / 101b906c8 / 101b9089c): CacheFileEntry's
//             own logic; symbols devirtualized → method NAMES inferred from the
//             readable body shape (marked `name inferred`). Faithful spine; the
//             intricate FileHandle/Data-helper details are flagged UNRESOLVED.
// superclass_conformance_gate reports the binary's own conformance list for this type as
// ['CacheEntryProtocol', 'CustomStringConvertible'] (reverse-walk from the class
// descriptor through each conformance descriptor's TypeRef). CustomStringConvertible is
// declared here because its single requirement is now satisfied (see `description`
// below). CacheEntryProtocol is still MISSING from this list — a pre-existing gate FLAG,
// byte-identical at HEAD; its requirement set has not been recovered, so declaring it
// would be a fabrication. Left for the owner phase.
public final class CacheFileEntry: CustomStringConvertible {
    // --- stored fields (binary __swift5_fieldmd order) ---
    // file: backing FileHandle. s13/s14 fetch it at field offset 0x10 and drive
    //   NSFileHandle::_offset / seekToOffset:error: / _write / _read on it.
    // ⚑[tool=binding_gate ref=CacheFileEntry:__swift5_fieldmd result=pinned — binary says `let`, source cannot be]
    //   Session 61 binding sweep: these fields' FieldRecord flags word is 0x00000000
    //   (= `let`), but the Swift compiler REFUSES that spelling here. Left as `var`.
    //   • file — `var x: T?` gets an implicit nil; `let x: T?` would need an explicit `= nil`, asserting it is PERMANENTLY nil
    //   Real divergence, not fixable by a keyword flip. Detail + the full 33:
    //   reconstruction/binding_refuted_s61.json
    //   RESOLVED in session 62: `position` is now `let` — the init assigns it from its
    //   `position` PARAMETER, so the `= 0` default was never observable. `file` still stands.
    var file: FileHandle! // ⚑ IUO: field-record mangle `So12NSFileHandleC` carries NO `Sg` ⇒ non-optional
    //   (nil until init opens it; `guard let file` binds it). The prior `?` was an inferred guess; the
    //   binary is authoritative. FileHandle erases to NSFileHandle (Foundation.apinotes SwiftName).
    // url: source/destination URL of the cache file.
    let url: URL? // type inferred — ⚑ (Foundation; unmapped in field-records)
    // position: base byte offset of this entry within the underlying stream.
    //   s13/s14 compute `offset - position`; accessed as `*(ulong *)` with an
    //   UNSIGNED compare (`offset < position`) → 64-bit unsigned. Brief's `Int64`
    //   ⚑ guess corrected to UInt64 per the decompile width/signedness.
    public let position: UInt64  // type inferred — ⚑ (brief said Int64; decompile shows ulong/unsigned → UInt64)
    // saveFile: whether the entry persists to disk. v4 concrete (gate PASS).
    //   (Not read by s12/s13/s14 in the cached set; consulted elsewhere.)
    private var saveFile: Bool = false
    // size: bytes currently held by this entry. s13 increments it by the write
    //   length; s12 compares it against maxSize + a 32MiB ceiling. Accessed as
    //   `*(uint *)` with a CARRY4 (unsigned 32-bit overflow) trap → UInt32. Brief's
    //   `Int64` ⚑ guess corrected to UInt32 per the decompile width/signedness.
    public var size: UInt32 = 0 // type inferred — ⚑ (brief said Int64; decompile shows uint/CARRY4 → UInt32)
    // maxSize: capacity ceiling for this entry. s12 compares size+delta against it
    //   as `*(uint *)` and reads its +4 tag byte (`(char)puVar1[1]`) → 5-byte
    //   optional. l2_field_gate binary property descriptor independently resolves
    //   `UInt32?`. Brief's `Int64` ⚑ guess corrected to UInt32? (2 binary signals).
    public var maxSize: UInt32? // type inferred — ⚑ (brief said Int64; l2 gate + decompile → UInt32?)

    // --- inits ---
    // s10 @101b900c4 → inner FUN_101b90114 (2 args; explicit field stores url=param_1, position=param_2).  ⚑[tool=resolve_fun_pins ref=FUN_101b90114:0x101b90114 result=RESOLVES_UNIQUELY] = PreLoadIOContext.CacheFileEntry.init(url: Foundation.URL, position: Swift.UInt64) throws -> PreLoadIOContext.CacheFileEntry?
    // Arity inferred (no mangled init symbol exists); param→field stores are explicit in the inner init.
    // Body opens the EXISTING cache file + reads its NSURLFileSizeKey size → faithful spine; the
    // NSFileManager/URLResourceValues marshalling detail is UNRESOLVED.
    init(url: URL?, position: UInt64) {
        self.url = url
        self.position = position
        self.saveFile = true                  // binary sets saveFile=true on this path
        // UNRESOLVED: open existing file (NSFileManager.fileExists) + read NSURLFileSizeKey → size/maxSize,
        //   then open FileHandle → file. Foundation spine in FUN_101b90114; detail deferred. — P2  ⚑[tool=resolve_fun_pins ref=FUN_101b90114:0x101b90114 result=RESOLVES_UNIQUELY] = PreLoadIOContext.CacheFileEntry.init(url: Foundation.URL, position: Swift.UInt64) throws -> PreLoadIOContext.CacheFileEntry?
    }

    // UNRESOLVED: s9 @101b881f8 → inner FUN_101b8fb0c — the DESIGNATED init (3 args: param_1 = a  ⚑[tool=resolve_fun_pins ref=FUN_101b8fb0c:0x101b8fb0c result=RESOLVES_UNIQUELY] = PreLoadIOContext.CacheFileEntry.init(dir: Foundation.URL, position: Swift.UInt64, maxSize: Swift.UInt32?) throws -> PreLoadIOContext.CacheFileEntry
    //   url-derivation base [1-word, CustomStringConvertible; TYPE NOT deterministically resolvable],
    //   position: UInt64 = param_2, maxSize: UInt32? = param_3 packed). Derives url via
    //   appendingPathComponent + creates a new FileHandle (deep Foundation IO). param_1 type unpinnable
    //   without guessing → do NOT declare. Real designated init deferred. — P2

    // --- description (vtable slot 11, between the two inits at 9/10 and the three
    //     methods at 12/13/14 — so it is declared here, after the inits) ---

    // s11 @0x101b9049c — `var description: String`. The NAME is not inferred: no mangled
    //   name survives (recover_swift_function_name → None), but
    //   superclass_conformance_gate independently proves this type conforms to
    //   CustomStringConvertible in the binary, and slot 11 is the only get-only String
    //   property in the vtable — so `description` is the witness, established rather than
    //   guessed. The BODY is byte-exact too: the
    //   three literals are recovered from the small-string immediates the decompile
    //   loads, so the format string is not a guess.
    //     "position=" str 0x6e6f697469736f70 = "position", bridgeObject 0xe9…003d = count 9, 9th byte '='
    //     ",size="    str 0x00003d657a69732c = ",size=",   bridgeObject 0xe6…0000 = count 6
    //     ",maxSize=" str 0x657a695378616d2c = ",maxSize", bridgeObject 0xe9…003d = count 9, 9th byte '='
    //   Interpolation kinds corroborate the field order independently: `position`
    //   (UInt64) and `size` (UInt32) each go through
    //   `CustomStringConvertible.description` — two `get_description` calls — while
    //   `maxSize` (UInt32?, an Optional and therefore NOT CustomStringConvertible)
    //   falls to the generic `appendInterpolation<T>` → `_print_unlocked` with the
    //   DefaultStringInterpolation metadata/TextOutputStream witness pair. The
    //   `grow(0x1e)` is the 30-byte literal reserve (9 + 6 + 9 = 24 plus slack).
    //   Both field reads are `swift_beginAccess` on the ivar-offset globals
    //   `CacheFileEntry::size` / `CacheFileEntry::maxSize`, i.e. this class's own
    //   `size` and `maxSize`, not a sibling's.
    // ⚑[tool=superclass_conformance_gate ref=CacheFileEntry.description.getter:0x101b9049c result=CustomStringConvertible witness]
    //   Interpolating `maxSize` (a UInt32?) directly is what the binary does — the generic
    //   `appendInterpolation<T>` → `_print_unlocked` path only exists because the value is
    //   an Optional. Swift emits an "interpolation produces a debug description for an
    //   optional value" WARNING for it; the warning is the faithful reading and is not
    //   silenced (a `String(describing:)` or `?? default` rewrite would change the
    //   emitted call and break the body diff).
    public var description: String {
        "position=\(position),size=\(size),maxSize=\(maxSize)"
    }

    // --- methods (CacheFileEntry's own; names devirtualized → inferred) ---

    // s12 @101b90620 — `func wouldOverflow(_:) -> Bool` (name inferred).
    //   undefined8 FUN(uint param_1): returns 0/1. Faithful (full) reconstruction:
    //   a capacity predicate. Reads size (uint); if size >= 0x2000001 (32MiB+1) →
    //   true. Else reads maxSize and tests its +4 optional-tag byte
    //   (`(char)puVar1[1] != '\x01'` == maxSize is non-nil); when non-nil, an
    //   overflow-checked `maxSize < size + appending` → true. Else false.
    //   NOTE: s12 does NOT read `saveFile`; the byte at maxSize+4 is the UInt32?
    //   optional tag, not saveFile.
    func wouldOverflow(_ appending: UInt32) -> Bool { // name inferred (devirt)
        if size >= 0x2000001 {
            return true
        }
        if let maxSize {
            // CARRY4(size, appending) → unsigned-overflow trap in the binary; the
            // sum is the faithful comparison target.
            if maxSize < size + appending {
                return true
            }
        }
        return false
    }

    // s13 @101b906c8 — `func write(offset:buffer:length:) throws` (name inferred).
    //   void FUN(ulong param_1, __int64 param_2, uint param_3): offset, buffer ptr,
    //   length. Faithful spine: derive the FileHandle seek target from
    //   `offset - position` (binary traps when offset < position), seek the file
    //   if it is not already there (seekToOffset:error: → throws via
    //   convertNSErrorToError), write the buffer bytes as Data, then size += length.
    // UNRESOLVED: the exact Data construction/deallocator dance and the unnamed
    //   helpers (FUN_100395fc0 build-Data, FUN_101b95a8c, FUN_10000627c) are not
    //   resolvable from the cached decompile — spine preserved, helper detail TODO.
    func write(offset: UInt64, buffer: UnsafePointer<UInt8>, length: Int32) throws { // name inferred (devirt)
        guard let file else { return }
        let target = offset - position // binary: traps if offset < position
        if try file.offset() != target {
            try file.seek(toOffset: target)
        }
        let data = Data(bytes: buffer, count: Int(length)) // UNRESOLVED: exact Data builder (FUN_100395fc0) unseen
        try file.write(contentsOf: data)
        size += UInt32(length) // binary: CARRY4 unsigned-overflow trap on size + length
    }

    // s14 @101b9089c — `func read(offset:length:) throws -> Data?` (name inferred).
    //   void FUN(ulong param_1, int param_2): offset, length. Faithful spine:
    //   same `offset - position` seek-target derivation + conditional
    //   seekToOffset:error: (throws), then NSFileHandle::_read of `length` bytes.
    // UNRESOLVED: the decompile shows the _read call but the returned-Data
    //   marshalling is obscured — return shape is a best-effort spine.
    func read(offset: UInt64, length: Int32) throws -> Data? { // name inferred (devirt)
        guard let file else { return nil }
        let target = offset - position // binary: traps if offset < position
        if try file.offset() != target {
            try file.seek(toOffset: target)
        }
        return try file.read(upToCount: Int(length)) // UNRESOLVED: exact return marshalling unseen
    }
}
