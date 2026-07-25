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
}
