//
//  VideoInfo.swift
//  KSPlayer
//
//  Binary-faithful reconstruction (Forward 1.3.17). NEW Forward-only type.
//  Remux-foundation; consumed by the Phase-2 Remuxer + Phase-3 DV path.
//  Reconstructed from binary: init `0x101a33eb8`, coverImage getter `0x101a372f8`.
//

import CoreGraphics

// Binary: vtable 4 (num_immediate 9 − num_fields 5 = 4).
// Slots: 0 getter `0x101a372f8` (coverImage), 1 setter (devirt/synthesized),
//        2 _modify (devirt/synthesized), 3 init `0x101a33eb8`.
// Allocator is `_swift_allocObject` (class, not a subclass).
public final class VideoInfo {
    // Stored fields in reflection (offset) order, each 8B. Types transcribed from
    // the class's own __swift5_fieldmd field-records (authoritative), NOT inferred
    // from the decompile's undefined8 widths.
    public let duration: Double            // +0x10  (init param 1)
    public let fileSize: Int64             // +0x18  (init param 2) — external/unmapped stdlib symref; definitively NOT Int (Int would mangle `Si`); 8B non-optional
    public let metadata: [String: String]  // +0x20  (init param 3)
    public let assetTracks: [FFmpegAssetTrack] // +0x28 (init param 4)
    public var coverImage: CGImage?        // +0x30  (init stores 0/nil); slots 1/2 are compiler-synthesized accessors

    // init `0x101a33eb8`: +0x10=p1, +0x18=p2, +0x20=p3, +0x28=p4, +0x30=0.
    public init(duration: Double, fileSize: Int64, metadata: [String: String], assetTracks: [FFmpegAssetTrack]) {
        self.duration = duration
        self.fileSize = fileSize
        self.metadata = metadata
        self.assetTracks = assetTracks
        // coverImage defaults nil (binary init stores 0 at +0x30)
    }
}
