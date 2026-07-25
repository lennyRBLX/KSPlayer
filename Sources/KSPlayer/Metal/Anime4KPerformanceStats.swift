//
//  Anime4KPerformanceStats.swift
//  KSPlayer
//
//  Forward 1.3.17 reconstruction. `Anime4KPerformanceStats` is an immutable per-frame performance
//  snapshot for the Anime4K upscaling subsystem. It is OFF the critical path (not held by
//  Anime4KPipeline); its one subsystem reference is `Anime4KPreset`.
//
//  DECODED from the binary — access level is the only inference:
//    • kind=struct + 6 stored properties + their order + types + let/var = the struct field descriptor
//      (nominal descriptor 0x1039f0d34; Kind=0/Struct). Every FieldRecord flags=0x0 (IsVar bit clear)
//      → all `let`. Types from the class-scoped __swift5_fieldmd MangledTypeName
//      (fetch_fieldrecord_types): Double×3, Bool×2, Anime4KPreset.
//    • no conformances = superclass_conformance_gate confs=[] (GOT-aware, dyld-bind).
//    • access level ⚑ INFERRED `public` (type; fields left internal) ⚑[tool=nm
//      ref=Anime4KPerformanceStats result=local-symbols-stripped] (sibling convention: MPVShader).
//
public struct Anime4KPerformanceStats {
    let lastFrameTime: Double
    let averageFrameTime: Double
    let estimatedFPS: Double
    let isDropping: Bool
    let supported: Bool
    let preset: Anime4KPreset
}
