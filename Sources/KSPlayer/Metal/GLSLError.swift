//
//  GLSLError.swift
//  KSPlayer
//
//  Forward 1.3.17 reconstruction. `GLSLError` is the error type thrown by the MPV-format `.hook`
//  shader parser (`Anime4K.parseShaders` @0x101a7e52c). It is a SIBLING of, and distinct from,
//  `Anime4KError`: two different enums with different metadata. Session 54 had assumed the parser
//  threw `Anime4KError.fileNotFound` and deliberately stopped rather than write an unproven `throw`;
//  session 55 resolved the metadata and the assumption was wrong.
//
//  DECODED from the binary — access level + the case-binding identifier are the only inferences:
//    • TYPE IDENTITY anchored at the throw site: the parser does `adrp x0,0x1041d9000` +
//      `add x0,x0,#0xcc8` feeding `swift_allocError`'s x0 ⟹ metadata @0x1041d9cc8. That metadata's
//      kind word is 0x201 = MetadataKind.Enum (NOT an unresolvable value — this is what s54 read and
//      discarded), and its +8 nominal descriptor is 0x1039f0dfc, whose name is "GLSLError"
//      @0x10356c2c0. `Anime4K.init`'s own throw uses a DIFFERENT slot (@0x1041d96f8 → 0x1039f0a1c =
//      Anime4KError), which is how the two were conflated.
//    • kind=enum + 2 cases + order = the enum field descriptor @0x103cbd87c (Kind=3/MultiPayloadEnum,
//      NumFields=2, FieldRecordSize=12); each case carries a single UNLABELED `String` (FieldRecord
//      MangledTypeName "SS" @0x103c2d634, the same record Anime4KError's cases use). Parent context
//      0x1039eae44 — identical to Anime4KError's ⟹ a top-level type, not nested.
//    • conformances {Error, LocalizedError} — decode_witness_table --conformances 0x1039f0dfc
//      (GOT-indirect dyld-bind: @0x1041d9d08 = _$ss5ErrorMp, @0x1041d9cd8 =
//      _$s10Foundation14LocalizedErrorMp). Declaring `: LocalizedError` satisfies both (it refines
//      Error). The conformances are RESILIENT (flags 0x30000, witnessTable@cd+8 NULL) — the witnesses
//      live in the ResilientWitnessesHeader @cd+16.
//    • errorDescription is a CUSTOM witness @0x101a7df68 (slot 1 of the 5-entry LocalizedError
//      conformance @0x10356c2cc; slot 0 is the base-Error associated conformance, slots 2–4 are the
//      default nil witnesses @0x10003b478/47c/480). Error's 4 requirements @0x10356c314 are all
//      defaults @0x10003b3ec..f8. Same shape as Anime4KError's conformance pair.
//    • the body is a 2-arm switch returning "<prefix>" + payload via Swift.String.append (the `+`
//      operator), not interpolation. Both prefixes are byte-verified: tag 1 = "Shader error: "
//      (14 chars — small-string immediates 0x6853/0x6461/0x7265/0x6520 + 0x7272/0x726f/0x203a/0xee00,
//      discriminator 0xEE = 0xE0|14); tag 0 = "Failed to parse: " (17 chars @0x103d37ff0, matching the
//      `mov x9,#0x11` length immediate; P72 — the emitted pointer is chars−0x20).
//    • the tag→case-index mapping is PROVEN by those two prefixes ("Shader error" ↔ `shaderError` at
//      index 1, "Failed to parse" ↔ `parseFail` at index 0), not assumed. Codegen tests tag==1 first
//      and falls through to tag 0; the source is written in declaration order (equivalent codegen —
//      the Anime4KError precedent).
//    • `.shaderError` is declared in the field descriptor but has NO construction site in this binary:
//      the only `swift_allocError` against metadata @0x1041d9cc8 is the parser's `.parseFail`
//      (xrefs = that one throw plus the two witness/metadata accessors).
//    • access level ⚑ INFERRED `public` ⚑[tool=nm ref=GLSLError result=local-symbols-stripped];
//      the case-binding identifier is a source local (not binary-encoded) — ⚑ INFERRED `detail`.
//

import Foundation

public enum GLSLError: LocalizedError {
    case parseFail(String)
    case shaderError(String)

    public var errorDescription: String? {
        switch self {
        case .parseFail(let detail): return "Failed to parse: " + detail
        case .shaderError(let detail): return "Shader error: " + detail
        }
    }
}
