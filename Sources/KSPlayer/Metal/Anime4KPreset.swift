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

    /// ⚑[tool=export_trie_oracle ref=KSPlayer.Anime4KPreset.displayName.getter:0x101a78e68 result=71-instr]
    /// A 13-arm jump-table switch. `public` because the property carries a `vpMV` descriptor
    /// (`$s8KSPlayer13Anime4KPresetO11displayNameSSvpMV`).
    ///
    /// The dispatch is `ldrb w11, [0x10356beed, caseIndex]` then `br` to
    /// `0x101a78e98 + w11*4`, so the table byte IS the arm. Twelve arms load a large string:
    /// `adrp`+`add` gives the literal's address, the tail stores it biased by −0x20 with the high
    /// bit set (`sub x8,x8,#0x20` / `orr x1,x8,#1<<63`), and x0 carries `0x0001000000000011` plus a
    /// per-tail adjustment — `+0` = 17 bytes, `+3` = 20, `+5` = 22, `|2` = 19.
    ///
    /// ⚑ `.disabled`'s table byte points at a BARE `ret` (0x101a78f60), not at an arm. That returns
    ///   the x0/x1 pair built at the TOP of the function, which is a SMALL string:
    ///   x0 = 0x0000ad97e9b385e5 is the UTF-8 run `e5 85 b3 e9 97 ad` = 关闭.
    ///   ⚑ Its discriminator is `0xA0|6`, NOT `0xE0|count`. `0xE0` marks a small string that is
    ///     all-ASCII; a non-ASCII small string uses `0xA0`. Reading 0xA6 as "not a small string"
    ///     is what hides a literal like this one.
    ///
    /// ⚑ The decode is self-checking: every one of the four distinct byte counts reproduces its
    ///   text exactly (模式 = 6B, " A " punctuation = 1B each, 快速 = 6B, 高画质 = 9B), giving
    ///   17/20/19/22 for the four tails with no slack, and the mode-letter/quality pattern is
    ///   regular across all 13 cases.
    public var displayName: String {
        switch self {
        case .disabled: "关闭"
        case .modeAFast: "模式 A (快速)"
        case .modeBFast: "模式 B (快速)"
        case .modeCFast: "模式 C (快速)"
        case .modeAHQ: "模式 A (高画质)"
        case .modeBHQ: "模式 B (高画质)"
        case .modeCHQ: "模式 C (高画质)"
        case .modeAAFast: "模式 A+A (快速)"
        case .modeBBFast: "模式 B+B (快速)"
        case .modeCAFast: "模式 C+A (快速)"
        case .modeAAHQ: "模式 A+A (高画质)"
        case .modeBBHQ: "模式 B+B (高画质)"
        case .modeCAHQ: "模式 C+A (高画质)"
        }
    }
}
