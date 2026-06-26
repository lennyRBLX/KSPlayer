//
//  CacheEntry.swift
//  KSPlayer
//
//  Reconstructed binary-faithful from Forward 1.3.17 (KSPlayer module).
//

// In-memory cache record of the IO foundation. `final class` (the binary's
// inits call `_swift_allocObject`; `init(from:)` calls
// `_swift_deallocPartialClassInstance`). Conforms to `Codable` — slots 11
// (`encode(to:)`) and 12 (`init(from:)`) are Swift's AUTO-SYNTHESIZED Codable
// methods (verified: ordered integer CodingKeys 0–4 = declaration order, with
// `encodeIfPresent` for the single Optional). Properties are declared in key
// order 0–4 so that synthesis matches the binary's key order.
final class CacheEntry: Codable {
    // field types pinned from mangled property descriptors (authoritative — demangled):
    //   CacheEntry.logicalPos : Swift.UInt64  ·  .physicalPos : Swift.UInt64
    //   CacheEntry.size : Swift.UInt32  ·  .maxSize : Swift.UInt32?  ·  .eof : Swift.Bool
    var logicalPos: UInt64   // +0x10, 8B  (mangled: logicalPoss6UInt64Vv)
    var physicalPos: UInt64  // +0x18, 8B  (mangled: physicalPoss6UInt64Vv)
    var size: UInt32         // +0x20, 4B  (mangled: size...s6UInt32V; bounds-check compares UNSIGNED)
    var eof: Bool            // +0x24, 1B  (reflection `Sb`; init writes 0 = false)
    var maxSize: UInt32?     // +0x28 value / +0x2c discriminator (mangled: maxSizes6UInt32VSgv; encodeIfPresent)

    // Slot 9 memberwise init @0x1019e28dc: stores logicalPos(+0x10),
    // physicalPos(+0x18), size(+0x20) from params; eof(+0x24) defaults to
    // false (init writes 0); maxSize(+0x28/+0x2c) stored from the Optional
    // param. There is no `eof` parameter — the binary always initialises it false.
    init(logicalPos: UInt64, physicalPos: UInt64, size: UInt32, maxSize: UInt32?) {
        self.logicalPos = logicalPos
        self.physicalPos = physicalPos
        self.size = size
        self.eof = false
        self.maxSize = maxSize
    }

    // Slot 10 method @0x1019e29e4 (bounds/space check). NAME inferred — no symbol
    // in binary (devirtualized). Behaviour is faithful to the decompile:
    //   reads size(+0x20) and maxSize(+0x28/+0x2c); returns Bool.
    //   if size >= 0x1000001 (> 16MB)                       -> true
    //   else if maxSize != nil && maxSize < size + length   -> true   (size+length
    //        is a checked UInt32 add: the binary traps on CARRY4 overflow)
    //   else                                                -> false
    // name inferred — no symbol in binary
    func isExceeded(_ length: UInt32) -> Bool {
        if size > 0x100_0000 {
            return true
        }
        if let maxSize, maxSize < size + length {
            return true
        }
        return false
    }

    // Slots 11 (encode(to:)) + 12 (init(from:)) are SYNTHESIZED by `: Codable`.
    // Do NOT hand-write them — the binary uses standard Swift Codable synthesis.
}
