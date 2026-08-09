import Foundation
import KSPlayer   // CacheEntryProtocol — the binary's `$s8KSPlayer18CacheEntryProtocolMp` is KSPlayer-module

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
// below).
//
// s98: CacheEntryProtocol is now DECLARED. Its requirement set is no longer unrecovered —
// the protocol descriptor is `$s8KSPlayer18CacheEntryProtocolMp` @0x1039edec8 (KSPlayer
// module) and it has exactly 2 instance Getters, read off BOTH conformers' validated witness
// tables. This type's own table is 0x1041e19e8: req0 @0x101b90b48 loads a 64-bit field through
// a runtime field-offset global and returns it (= the stored `position`, UInt64); req1
// @0x101b90b5c does the same for the 32-bit `size`. Both requirements are therefore satisfied
// by stored properties already declared below — this adds the conformance, not any member.
public final class CacheFileEntry: CacheEntryProtocol, CustomStringConvertible {
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
    // ⚑ s114: `let`, NOT an IUO `var`. Two independent binary signals, both re-read here:
    //   the field record's FLAGS word is 0 (= `let`; 0x2 would be IsVar), and the mangle
    //   `So12NSFileHandleC` carries no `Sg`. Decisively, the designated init @0x101b90114 emits NO
    //   implicit-nil default store for this field anywhere in its 226 instructions — an IUO `var`
    //   always gets one in the prologue — and writes it exactly once, on the success path, by a
    //   plain 8-byte `str x20,[x22,#0x10]` at 0x101b90488.
    //   ⚑[tool=fieldrec ref=CacheFileEntry.file:0x103cc062c result=flags0-let-no-Sg]
    let file: FileHandle
    // url: source/destination URL of the cache file.
    // ⚑ s114: `URL`, NOT `URL?` — the field record's tail is EMPTY (a `Sg` would make it Optional)
    //   and its symref is Foundation's `URL` nominal type descriptor. The init's parameter is
    //   non-optional for the same reason: it takes URL's own metadata and value witness, never
    //   `Optional<URL>`'s.
    //   ⚑[tool=bind_oracle ref=CacheFileEntry.url:0x104109b20 result=Foundation.URL-no-Sg]
    let url: URL
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
    /// @0x101b90114 (the initializing `…cfc`; the allocating thunk is 0x101b900c4), 226 instructions.
    /// The trie gives the whole signature, and all three of its differences from the previous
    /// spelling are read, not inferred:
    /// `init(url: Foundation.URL, position: Swift.UInt64) throws -> CacheFileEntry?` — FAILABLE,
    /// THROWING, and taking a NON-optional `url`.
    /// ⚑[tool=export_trie_oracle ref=CacheFileEntry.init(url:position:):0x101b90114 result=ACSg-throws]
    ///
    ///   · the three declaration defaults are the only ones materialised in the prologue —
    ///     `saveFile = false` (0x101b901c4), `size = 0` (0x101b901d4), `maxSize = nil` (0x101b901e4,
    ///     payload zeroed + tag byte 1). `file`, `url` and `position` get none, which is what makes
    ///     them non-defaulted `let`s.
    ///   · FAILABILITY is a NULL class reference, not an enum tag: `Optional<CacheFileEntry>` for a
    ///     class is a nullable pointer, so the nil path just sets x22 = 0 after
    ///     `swift_deallocPartialClassInstance` (0x101b90310). It returns nil WITHOUT throwing — the
    ///     swifterror register is restored from its entry spill.
    ///   · there are exactly TWO throw paths and this body calls NO `swift_willThrow` of its own —
    ///     both are propagations: from `URL.resourceValues(forKeys:)` and from
    ///     `FileHandle(forUpdating:)`, whose shim converts an `NSError`. So the thrown value is a
    ///     bridged Cocoa error, not a type declared in this module.
    ///
    /// ⚑ The old note said the init opens the file for READING. It does not: the selector is
    ///   `fileHandleForUpdatingURL:error:`, i.e. `FileHandle(forUpdating:)`, read-write.
    ///   ⚑[tool=decode_objc_selector ref=CacheFileEntry.init:0x10440b4a8 result=fileHandleForUpdatingURL:error:]
    ///
    /// ⚑ `size` comes from `URLResourceValues.fileSize` (an `Int?`) through a TRAPPING `UInt32(_:)`
    ///   narrowing — traps at 0x101b90494 on negative and 0x101b90498 on > UInt32.max. It is NOT a
    ///   FileManager attributes lookup and NOT a seek-to-end. The `forKeys:` argument is the
    ///   one-element literal `[.fileSizeKey]`, built as a stack-promoted array whose sole element is
    ///   the CoreFoundation global `NSURLFileSizeKey`.
    ///   ⚑[tool=bind_oracle ref=URLResourceValues.fileSize:0x104109830 result=fileSizeSiSgvg]
    ///
    /// ⚑ Spellings the binary does not decide: whether `maxSize` is written `size` or
    ///   `UInt32(fileSize)` (same register w20, one conversion), and whether `resourceValues(...)`
    ///   is bound to a local or chained into `.fileSize`.
    init?(url: URL, position: UInt64) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = values.fileSize {
            size = UInt32(fileSize)
            maxSize = size
        }
        self.position = position
        self.url = url
        saveFile = true
        file = try FileHandle(forUpdating: url)
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
    // ⚑ s106 RENAME `wouldOverflow(_:)` → `isOut(size:)`. The old name carried its own disclaimer,
    //   "name inferred (devirt)", and the inference was never needed: the trie names 0x101b90620
    //   `PreLoadIOContext.CacheFileEntry.isOut(size: Swift.UInt32) -> Swift.Bool` directly.
    //   BOTH parts come from the trie — the base name and the argument label (`_` → `size:`).
    //   Parameter type UInt32 and Bool return already matched, so this is a rename and not a
    //   signature change; that distinction was checked by comparing parameters, not assumed.
    //   No call sites: the tree-wide grep on the bare name returns only this declaration and its
    //   own comment.
    //   ⚑[tool=export_trie_oracle ref=CacheFileEntry.isOut(size:):0x101b90620 result=isOut-not-wouldOverflow]
    func isOut(size appending: UInt32) -> Bool {
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
        // ⚑ s114: the `guard let file` that stood here is GONE because `file` is a non-optional
        //   `let` (field-record flags 0, no `Sg`, and the init emits no implicit-nil default).
        //   A non-optional cannot be conditionally bound, and the binary has no nil test for it.
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
        // ⚑ s114: same as `write` above — `file` is a non-optional `let`, so there is no binding
        //   guard here and none in the binary.
        let target = offset - position // binary: traps if offset < position
        if try file.offset() != target {
            try file.seek(toOffset: target)
        }
        return try file.read(upToCount: Int(length)) // UNRESOLVED: exact return marshalling unseen
    }
}
