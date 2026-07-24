//
//  MPVShader.swift
//  KSPlayer
//
//  Forward 1.3.17 reconstruction. `MPVShader` is one parsed mpv-format GLSL user shader (the
//  `//!HOOK` / `//!BIND` / `//!SAVE` / `//!WIDTH` / … directive set). `Anime4K.shaders` and
//  `Anime4K.enabledShaders` are `[MPVShader]`; it is a LEAF of the Anime4K subsystem — all 10
//  fields are stdlib types and it references no other subsystem type.
//
//  FULLY DECODED — nothing inferred except the access level:
//    • kind=struct + 10 stored fields + order + types = the struct field descriptor @0x103cbd7f4
//      (nominal desc 0x1039f0de0; Kind=0/Struct, NumFields=10; every FieldRecord concrete —
//      mangles SS / SSSg / SaySSG / SiSg / SS_SftSg / SdSg).
//    • all 10 fields `var` — FieldRecordFlags IsVar (0x2) set on every record (dump_field_bindings).
//    • no protocol conformances — superclass_conformance_gate confs=[] (GOT-aware): not Codable
//      (the .hook text is parsed field-by-field, not decoded through Codable).
//    • access level ⚑ INFERRED public ⚑[tool=nm ref=MPVShader result=local-symbols-stripped]
//      (linkage unavailable in the stripped, statically-linked image; subsystem-sibling
//      convention). Fields left internal `var` — no per-field access signal survives.
//
//  Binary source org: the subsystem's Swift lives in `KSPlayer/Anime4K.swift` +
//  `KSPlayer/Anime4KPipeline.swift`; per-type file attribution for the value types is not preserved
//  in the binary, so this gets its own file (binary-indifferent placement; Anime4KFrameDump /
//  Anime4KPreset precedent).
//

public struct MPVShader {
    var name: String
    var hook: String?
    var binds: [String]
    var save: String?
    var components: Int?
    var width: (String, Float)?
    var height: (String, Float)?
    var when: String?
    var sigma: Double?
    var code: [String]
}
