//
//  Anime4KPreset.swift
//  KSPlayer
//
//  Forward 1.3.17 reconstruction. `Anime4KPreset` selects the Anime4K real-time-upscaling mode
//  (Mode A/B/C and their combined variants, each in a Fast and an HQ tier, plus `disabled`). It is
//  a LEAF of the Anime4K subsystem: `Anime4KPipeline.preset` and `Anime4KPerformanceStats.preset`
//  hold it, and it references no other subsystem type.
//
//  DECODED from the binary — the only inferences are the access level and the raw-value source
//  spelling (both flagged):
//    • kind + the 13 cases + their order = the enum field descriptor @0x103cbd714 (nominal descriptor
//      0x1039f0d50; Kind=2/Enum, NumFields=13, every FieldRecord payload-empty).
//    • RAW TYPE = String. The RawRepresentable conformance descriptor @0x10356c090 is
//      HasResilientWitnesses; its ResilientWitnessesHeader @cd+16 has 3 witnesses, and the RawValue
//      associated-type witness's impl resolves to the mangled name "SS" (@0x103c2d634) = Swift.String.
//      Corroborated by the rawValue getter @0x101a7bfc8 (returns a 16-byte String) and
//      init?(rawValue:) @0x101a7c6fc (takes a String ptr+count).
//    • RAW VALUES = the String defaults (each equals its case name): the getter's small-string
//      constants spell exactly the 13 case names (disabled … modeCAHQ). Whether the source wrote them
//      explicitly is not distinguishable in the binary from the default; the default (no `= "…"`) is
//      the parsimonious faithful form.
//    • CONFORMANCES {RawRepresentable, Equatable, Hashable, CaseIterable} — all 4 dyld-bind proven
//      (superclass_conformance_gate, GOT-aware). RawRepresentable/Equatable/Hashable are IMPLICIT from
//      `: String`; only CaseIterable is written.
//    • access level ⚑ INFERRED `public` ⚑[tool=nm ref=Anime4KPreset result=local-symbols-stripped]
//      (linkage is unavailable; matches the sibling Anime4KFrameDump — a host-facing upscaling
//      selector).
//
//  Binary source org: the subsystem's Swift lives in `KSPlayer/Anime4K.swift` +
//  `KSPlayer/Anime4KPipeline.swift`; per-type file attribution for the value types is not preserved
//  in the binary (a code-free enum emits no `#file`), so this gets its own file (binary-indifferent
//  placement; Anime4KFrameDump.swift precedent).
//

public enum Anime4KPreset: String, CaseIterable {
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
