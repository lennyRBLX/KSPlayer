//
//  Anime4KPreset.swift
//  KSPlayer
//
//  Forward 1.3.17 reconstruction. `Anime4KPreset` selects the Anime4K real-time-upscaling mode
//  (Mode A/B/C and their combined variants, each in a Fast and an HQ tier, plus `disabled`). It is
//  a LEAF of the Anime4K subsystem: `Anime4KPipeline.preset` and `Anime4KPerformanceStats.preset`
//  hold it, and it references no other subsystem type.
//
//  FULLY DECODED — nothing inferred except the access level:
//    • kind + the 13 payload-less cases + their order = the enum field descriptor @0x103cbd714
//      (nominal descriptor 0x1039f0d50; Kind=2/Enum, NumFields=13, every FieldRecord payload-empty).
//    • no raw type and no protocol conformances = superclass_conformance_gate confs=[] (GOT-aware,
//      authoritative) — a `: Int`/`: String` enum would carry a RawRepresentable conformance, and
//      CaseIterable/Equatable/Hashable would each appear as a conformance too.
//    • access level ⚑ INFERRED `public` ⚑[tool=nm ref=Anime4KPreset result=local-symbols-stripped]
//      (linkage is unavailable; matches the sibling Anime4KFrameDump — a host-facing upscaling
//      selector).
//
//  Binary source org: the subsystem's Swift lives in `KSPlayer/Anime4K.swift` +
//  `KSPlayer/Anime4KPipeline.swift`; per-type file attribution for the value types is not preserved
//  in the binary (a code-free enum emits no `#file`), so this gets its own file (binary-indifferent
//  placement; Anime4KFrameDump.swift precedent).
//

public enum Anime4KPreset {
    case disabled
    case modeAFast
    case modeBFast
    case modeCFast
    case modeAHQ
    case modeBHQ
    case modeCHQ
    case modeAAFast
    case modeBBFast
    case modeCAFast
    case modeAAHQ
    case modeBBHQ
    case modeCAHQ
}
