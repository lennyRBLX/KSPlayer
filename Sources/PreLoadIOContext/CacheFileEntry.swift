import Foundation

// CacheFileEntry — standalone cache-entry type (NO superclass). Shared dependency
// for the Wave-2 cache contexts (CacheIOContext / ReadCacheIOContext reference it).
//
// Reconstructed A+ structure-faithful from the Forward 1.3.17 binary:
//   fields  — __swift5_fieldmd reflection (NAMES + ORDER + COUNT authoritative).
//   inits   — s9 (101b881f8) + s10 (101b900c4): both cached decompiles are the
//             outer *allocating* thunks (_swift_allocObject → inner init FUN);
//             the inner field-store bodies (FUN_101b8fb0c / FUN_101b90114) are
//             NOT in the cached decompile set → init bodies are faithful spine
//             + UNRESOLVED for the exact field-assignment sequence.
//   methods — s12/s13/s14 (101b90620 / 101b906c8 / 101b9089c): CacheFileEntry's
//             own logic; symbols devirtualized → method NAMES inferred from the
//             readable body shape (marked `name inferred`). Faithful spine; the
//             intricate FileHandle/Data-helper details are flagged UNRESOLVED.
final class CacheFileEntry {
    // --- stored fields (binary __swift5_fieldmd order) ---
    // file: backing FileHandle. s13/s14 fetch it at field offset 0x10 and drive
    //   NSFileHandle::_offset / seekToOffset:error: / _write / _read on it.
    var file: FileHandle? // type inferred — ⚑ (complex; confirmed FileHandle by s13/s14 NSFileHandle interop)
    // url: source/destination URL of the cache file.
    var url: URL? // type inferred — ⚑ (Foundation; unmapped in field-records)
    // position: base byte offset of this entry within the underlying stream.
    //   s13/s14 compute `offset - position`; accessed as `*(ulong *)` with an
    //   UNSIGNED compare (`offset < position`) → 64-bit unsigned. Brief's `Int64`
    //   ⚑ guess corrected to UInt64 per the decompile width/signedness.
    var position: UInt64 = 0 // type inferred — ⚑ (brief said Int64; decompile shows ulong/unsigned → UInt64)
    // saveFile: whether the entry persists to disk. v4 concrete (gate PASS).
    //   (Not read by s12/s13/s14 in the cached set; consulted elsewhere.)
    var saveFile: Bool = false
    // size: bytes currently held by this entry. s13 increments it by the write
    //   length; s12 compares it against maxSize + a 32MiB ceiling. Accessed as
    //   `*(uint *)` with a CARRY4 (unsigned 32-bit overflow) trap → UInt32. Brief's
    //   `Int64` ⚑ guess corrected to UInt32 per the decompile width/signedness.
    var size: UInt32 = 0 // type inferred — ⚑ (brief said Int64; decompile shows uint/CARRY4 → UInt32)
    // maxSize: capacity ceiling for this entry. s12 compares size+delta against it
    //   as `*(uint *)` and reads its +4 tag byte (`(char)puVar1[1]`) → 5-byte
    //   optional. l2_field_gate binary property descriptor independently resolves
    //   `UInt32?`. Brief's `Int64` ⚑ guess corrected to UInt32? (2 binary signals).
    var maxSize: UInt32? // type inferred — ⚑ (brief said Int64; l2 gate + decompile → UInt32?)

    // --- inits ---
    // s9 @101b881f8 — outer allocating thunk: _swift_allocObject then
    //   FUN_101b8fb0c(param_1, param_2, param_3 & 0xffffffffff). Three args; the
    //   third masked to 40 bits (a small int / flag). Likely the designated init.
    // UNRESOLVED: inner init FUN_101b8fb0c (field-store sequence) not in cached
    //   decompiles — exact param→field mapping unconfirmed; spine only.
    init(file: FileHandle?, url: URL?, position: UInt64, saveFile: Bool, size: UInt32, maxSize: UInt32?) {
        self.file = file
        self.url = url
        self.position = position
        self.saveFile = saveFile
        self.size = size
        self.maxSize = maxSize
    }

    // s10 @101b900c4 — outer allocating thunk: _swift_allocObject then
    //   FUN_101b90114(param_1, param_2). Two args; likely a convenience init.
    // UNRESOLVED: inner init FUN_101b90114 (field-store sequence) not in cached
    //   decompiles — exact param→field mapping unconfirmed; spine only.
    convenience init(url: URL?, maxSize: UInt32?) {
        self.init(file: nil, url: url, position: 0, saveFile: false, size: 0, maxSize: maxSize)
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
