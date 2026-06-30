//
//  DoviSerializer.swift
//  KSPlayer
//
//  P3a Phase B prereq — the KS-side DV-metadata serializer (stub; body → DV-render).
//

import DOVIRPUShim

/// Flattens the FFmpeg-decoded `AVDOVIMetadata` into the 3008-byte `KSDOVIMetadata` GPU buffer.
///
/// Binary: `FUN_101b31c6c` (455 instr, sret return, free/global function — decompile-confirmed;
/// shared by 3 decode callers). The float-flattening body (mapping / color / DM-spline blocks →
/// the 3008-byte float layout) is DEFERRED → DV-render, where the `KSDOVIMetadata` field-layout is
/// reconstructed. This stub returns a zeroed buffer (matching the binary's leading
/// `bzero(out, 0xBC0)`) so the decode-loop callers build and are body-auditable.
func convertAVDOVIToKSDOVIMetadata(_ metadata: UnsafePointer<AVDOVIMetadata>) -> KSDOVIMetadata {
    // UNRESOLVED → DV-render: the float-flattening of mapping/color/DM into the 3008-byte layout.
    return KSDOVIMetadata()
}
