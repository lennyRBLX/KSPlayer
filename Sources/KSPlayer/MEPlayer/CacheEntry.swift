//
//  CacheEntry.swift
//  KSPlayer
//
//  Reconstructed binary-faithful from Forward 1.3.17 (KSPlayer module).
//

// In-memory cache record of the IO foundation. NOT final: vtable slots 9-12 (the binary's
// inits call `_swift_allocObject`; `init(from:)` calls
// `_swift_deallocPartialClassInstance`). Conforms to `Codable` — slots 11
// (`encode(to:)`) and 12 (`init(from:)`) are Swift's AUTO-SYNTHESIZED Codable
// methods (verified: ordered integer CodingKeys 0–4 = declaration order, with
// `encodeIfPresent` for the single Optional). Properties are declared in key
// order 0–4 so that synthesis matches the binary's key order.
// Forward-only protocol, `$s8KSPlayer18CacheEntryProtocolMp` @0x1039edec8 — module KSPlayer,
// NOT PreLoadIOContext (that spelling is a real trie negative). It is a LEAF: 2 requirements,
// both instance Getters, both stdlib scalars, and NumRequirementsInSignature 0 so it is not
// class-constrained. Two conformers, both with validated witness tables:
//   CacheEntry     wt 0x1041d5378  req0 0x1019e30a4 (position)  req1 0x1019e30b8 (size)
//   CacheFileEntry wt 0x1041e19e8  req0 0x101b90b48 (position)  req1 0x101b90b5c (size)
// Requirement ORDER and both widths are read off those witnesses: req0 returns x0 (64-bit),
// req1 returns w0 (32-bit); the trie independently names CacheEntry.position.getter : UInt64
// @0x1019e3094 and CacheEntry.size.getter : UInt32 @0x1019e2750.
//
// `public` because PreLoadIOContext.CacheFileEntry conforms to it across the module boundary
// and PreLoadIOContext exposes `[any CacheEntryProtocol]`. Public vs package is not decidable
// from the image — access level is not carried in the mangling and both export a descriptor —
// so this follows the in-tree precedent for Forward's other recovered protocols.
public protocol CacheEntryProtocol {
    var position: UInt64 { get }
    var size: UInt32 { get }
}

public class CacheEntry: CacheEntryProtocol, Codable {
    // field types pinned from mangled property descriptors (authoritative — demangled):
    //   CacheEntry.logicalPos : Swift.Int64   ·  .physicalPos : Swift.UInt64
    //   CacheEntry.size : Swift.UInt32  ·  .maxSize : Swift.UInt32?  ·  .eof : Swift.Bool
    //
    // logicalPos was UInt64 here and the comment asserting the mangling `logicalPoss6UInt64Vv`
    // was FALSE. Three independent reads say Int64:
    //   1. l2_field_gate raises a REAL_FLAG — source UInt64 vs binary Int64.
    //   2. The export trie HAS $s8KSPlayer10CacheEntryC10logicalPoss5Int64Vvg @0x100137008 and
    //      the `s6UInt64V` spelling is a real trie negative — no address exports that name.
    //   3. The CacheEntryProtocol `position` witness @0x1019e30a4 is
    //      `ldr x0,[x8,#0x10]` / `tbnz x0,#0x3f` / `ret` / `brk #0x1` — a sign-bit test that
    //      traps. That trap is Swift's UInt64(Int64) conversion guard and is only emitted when
    //      the source value is SIGNED; on a UInt64 field no test would exist at all.
    // The reflection field records corroborate the split: logicalPos resolves through the same
    // type __got slot as CacheIOContext.fetchedSize (gate-confirmed SIGNED), while physicalPos
    // resolves through the UInt64 slot that CacheFileEntry.position uses.
    public let logicalPos: Int64    // +0x10, 8B  (mangled: logicalPoss5Int64Vv)
    public let physicalPos: UInt64  // +0x18, 8B  (mangled: physicalPoss6UInt64Vv)
    public var size: UInt32         // +0x20, 4B  (mangled: size...s6UInt32V; bounds-check compares UNSIGNED)
    public var eof: Bool = false    // +0x24, 1B  (reflection `Sb`; initial value: 0x1019e2928 strb wzr precedes the param stores)
    public var maxSize: UInt32?     // +0x28 value / +0x2c discriminator (mangled: maxSizes6UInt32VSgv; encodeIfPresent)

    // Slot 9 memberwise init @0x1019e28dc: stores logicalPos(+0x10),
    // physicalPos(+0x18), size(+0x20) from params; eof(+0x24) defaults to
    // false (init writes 0); maxSize(+0x28/+0x2c) stored from the Optional
    // param. There is no `eof` parameter — the binary always initialises it false.
    @used init(logicalPos: Int64, physicalPos: UInt64, size: UInt32, maxSize: UInt32?) {
        self.logicalPos = logicalPos
        self.physicalPos = physicalPos
        self.size = size
        // eof: declaration default. maxSize: assigned after full init (0x1019e294c swift_beginAccess, flags 1).
        self.maxSize = maxSize
    }

    // Slot 10 method @0x1019e29e4 (bounds/space check).
    // ⚑ s105 RENAME+LABEL: this was `isExceeded(_ length:)` and the comment below claimed
    // "no symbol in binary (devirtualized)". That is refuted — the export trie names the address
    // `KSPlayer.CacheEntry.isOut(size: Swift.UInt32) -> Swift.Bool`, one symbol, not a fold. So
    // both the method name AND the argument label were invented; the label is `size:`, not `_`.
    // Written `size length:` so the external label matches the binary while the body keeps its
    // own name — `size` alone would shadow the stored property this method reads.
    // ⚑[tool=export_trie_oracle ref=CacheEntry.isOut:0x1019e29e4 result=name-recovered]
    // The BODY was already right and is unchanged. Behaviour is faithful to the decompile:
    //   reads size(+0x20) and maxSize(+0x28/+0x2c); returns Bool.
    //   if size >= 0x1000001 (> 16MB)                       -> true
    //   else if maxSize != nil && maxSize < size + length   -> true   (size+length
    //        is a checked UInt32 add: the binary traps on CARRY4 overflow)
    //   else                                                -> false
    func isOut(size length: UInt32) -> Bool {
        if size > 0x100_0000 {
            return true
        }
        if let maxSize, maxSize < size + length {
            return true
        }
        return false
    }

    // CacheEntryProtocol req0. COMPUTED, not stored: `position` appears nowhere in this class's
    // 5 field records. The witness @0x1019e30a4 is four instructions —
    //   ldr x0,[x8,#0x10]  ·  tbnz x0,#0x3f,+8  ·  ret  ·  brk #0x1
    // — i.e. load logicalPos (the first stored field, at the +0x10 header boundary) and trap if
    // it is negative. That is exactly `UInt64(logicalPos)`: the trapping, non-clamping
    // conversion. `UInt64(bitPattern:)` or `UInt64(clamping:)` would emit no test at all.
    // The class's own declared getter @0x1019e3094 is the same four instructions off x20.
    public var position: UInt64 {
        UInt64(logicalPos)
    }

    // CacheEntryProtocol req1 is satisfied by the stored `size` above: the witness
    // @0x1019e30b8 takes a read access on self+0x20 and returns `ldr w0,[x19,#0x20]` — a plain
    // 32-bit stored-property read, no computation. +0x20 is where `size` sits given
    // logicalPos@+0x10 (8B) and physicalPos@+0x18 (8B).

    // Slots 11 (encode(to:)) + 12 (init(from:)) are SYNTHESIZED by `: Codable`.
    // Do NOT hand-write them — the binary uses standard Swift Codable synthesis.
    // `Codable` IS exactly `Decodable & Encodable`, so the binary listing those two separately
    // is a spelling equivalence, not a missing conformance.
}
