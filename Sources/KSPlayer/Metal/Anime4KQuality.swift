//
//  Anime4KQuality.swift
//  KSPlayer
//
//  Forward 1.3.17 reconstruction. `Anime4KQuality` is a payload-less quality-tier selector for the
//  Anime4K upscaling subsystem. It is OFF the critical path (not held by Anime4KPipeline) and a LEAF:
//  it references no other subsystem type.
//
//  DECODED from the binary — access level is the only inference:
//    • kind=enum + 5 payload-less cases + their order = the enum field descriptor (nominal descriptor
//      0x1039f0d18; every FieldRecord payload-empty, type=None).
//    • no raw type / no conformances = superclass_conformance_gate confs=[] (GOT-aware, dyld-bind).
//    • access level ⚑ INFERRED `public` ⚑[tool=nm ref=Anime4KQuality result=local-symbols-stripped]
//      (linkage unavailable; matches the siblings Anime4KPreset / Anime4KFrameDump).
//
public enum Anime4KQuality {
    case lowest
    case low
    case medium
    case high
    case highest

    // ── Forward's quality-tier policy ────────────────────────────────────────────────────────
    // Seven computed properties the binary declares on this enum and this source did not. Each
    // body was read at the address noted on it. `self` is the payload-less case index in w0 —
    // lowest 0 … highest 4, the order re-read from the enum's own field descriptor
    // (nominal descriptor 0x1039f0d18 -> field descriptor 0x103cbd670), not from the comment above.
    //
    // ORDER of the first four follows their ADDRESSES, which are contiguous
    // (0x101a7b4e8 / 4fc / 510 / 51c) — evidence of source order, not proof of it. The remaining
    // three sit elsewhere in __text and carry no positional evidence.
    //
    // Access ⚑ INFERRED `public` ⚑[tool=export_trie_oracle ref=Anime4KQuality.displayName.getter:0x101a7b51c result=exported]
    // — every getter is in the export trie and the type is public; linkage itself is unavailable.

    /// ⚑ getter 0x101a7b4e8 — `and x8, x0, #0xff` then `ldr x0, [x9, x8, lsl #3]` off the 5-entry
    /// table at 0x10356c240, read as 1080 · 1080 · 1440 · 1440 · 2160.
    public var maxResolutionHeight: Int {
        switch self {
        case .lowest, .low:
            return 1080
        case .medium, .high:
            return 1440
        case .highest:
            return 2160
        }
    }

    /// ⚑ getter 0x101a7b4fc — `tst w0, #0xfe` / `csel x0, x9, x8, eq` with w9=0x1e0, w8=0x168.
    /// The mask is true only for indices 0 and 1, so .lowest and .low take 480 and the rest 360.
    public var minResolutionHeight: Int {
        switch self {
        case .lowest, .low:
            return 480
        case .medium, .high, .highest:
            return 360
        }
    }

    /// ⚑ getter 0x101a7b510 — `tst w0, #0xfe` / `cset w0, eq`: true exactly when the case index
    /// clears every bit above bit 0, i.e. .lowest and .low.
    public var skipHighBitDepth: Bool {
        switch self {
        case .lowest, .low:
            return true
        case .medium, .high, .highest:
            return false
        }
    }

    /// ⚑ getter 0x101a7b51c — five inline Swift small strings selected by a `csel` chain keyed on
    /// index 3, then 2, then 0, then 1. Texts recovered with
    /// ⚑[tool=decode_string_literal ref=Anime4KQuality.displayName.getter:0x101a7b51c result=small-strings]
    /// — they are immediates, not pointer literals, so the pointer decoder reports none.
    public var displayName: String {
        switch self {
        case .lowest:
            return "最低"
        case .low:
            return "低"
        case .medium:
            return "中等"
        case .high:
            return "高"
        case .highest:
            return "最高"
        }
    }

    /// ⚑ getter 0x1019e1af0 — `tst w0, #0xff` / `cset w0, ne`: true for every case whose index is
    /// non-zero, i.e. false only for .lowest.
    public var autoDowngrade: Bool {
        switch self {
        case .lowest:
            return false
        case .low, .medium, .high, .highest:
            return true
        }
    }

    /// ⚑ getter 0x101a7c8f8 — a single `b 0x101a7b510`, i.e. it tail-branches into
    /// `skipHighBitDepth`'s body and therefore computes the identical predicate.
    public var onlyForLowResolution: Bool {
        switch self {
        case .lowest, .low:
            return true
        case .medium, .high, .highest:
            return false
        }
    }

    /// ⚑ getter 0x10002dab0 — `mov w0, #0x0` / `ret`, unconditional. The address is ICF-folded
    /// (it is the image's canonical `return false`), so the body carries no information unique to
    /// this property; what it does carry is that the value never depends on `self`.
    public var animeOnly: Bool {
        return false
    }
}
