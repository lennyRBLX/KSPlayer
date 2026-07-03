//
//  ConversionInfo.swift
//  ProAVPlayer
//
//  P3b M1 (structure) — Forward-new coordinator for the convert-to-HLS pipeline: owns the
//  demuxer/remuxer/server/watcher and tracks playback timing. Field types resolved deterministically
//  (field-record mangle token-walk + l2_field_gate); method bodies + the real init → M2.
//  Binary: desc=0x1039f4fdc, vtable=1 (vtable-empty; methods devirtualized → M2 / witness-anchoring).
//

import Foundation
import KSPlayer

/// Coordinates the convert-to-HLS pipeline (demuxer ↔ remuxer ↔ local server ↔ directory watcher) and
/// surfaces playback timing/duration. Forward-new (ProAVPlayer module).
final class ConversionInfo: DemuxerIODelegate, RemuxerIOActionDelegate {   // binary conformances (conf@0x1035711a8/0x103571198); reqs → M2
    // 11 reflection fields (order = layout). Types: field-record mangle token-walk (Sg/Xw/_p suffix
    // authoritative for optionality); refs are non-optional (single symref, no Sg) → IUO M1 stand-ins.
    private var assetTracks: [FFmpegAssetTrack] = []
    private var duration: Double = 0
    private var subtitles: [MediaPlayerTrack] = []        // existential array (mangle Say…_pG; non-optional)
    // weak optional existential (mangle _pSgXw) → ConversionInfoDelegate (AnyObject). 3 reqs → M2.
    private weak var delegate: ConversionInfoDelegate? = nil
    private var demuxerTime: Double = 0
    private var currentPlaybackTime: Double = 0
    private var maxBufferDuration: Double = 0
    // ⚑ binary NON-optional refs (single symref, no Sg); IUO M1 stand-ins — real construction → M2.
    private var remuxerIOAction: RemuxerIOAction! = nil
    private var demuxerIO: DemuxerIO! = nil
    private var server: LocalHLSServer! = nil
    private var directoryWatcher: DirectoryWatcher! = nil  // KSPlayer (now public, fe13053)

    /// `DemuxerIODelegate` req0 witness — binary `FUN_101b6a40c` (`void f(double)`): stores the demuxer time
    /// (self@0x38, a `>=1.0`s-change throttle) then spawns a throttled progress `Task` (FUN_101b76920). The
    /// body couples to ConversionInfo's field layout (@0x38/0x40/0x48/0x50) + the Task machinery, both
    /// structure-only here → reconstruct with ConversionInfo's M2. ⚑ UNRESOLVED → ConversionInfo M2.
    /// Declared now so `DemuxerIO.readPacket()` (slot29) can call the req; witness slot is binary-present.
    func didUpdateCurrentTime(_ value: Double) {
        // UNRESOLVED — FUN_101b6a40c body; reconstruct with ConversionInfo M2 (field offsets + Task spawn).
    }
    func demuxerDidReachEnd() {
        // UNRESOLVED — FUN_101b6abf8 (forwards to ConversionInfo's own delegate, wt+0x10); ConversionInfo M2.
    }
    func demuxerDidFail(_ error: any Error) {
        // UNRESOLVED — FUN_101b6ac44 (forwards the error to ConversionInfo's own delegate, wt+0x18); ConversionInfo M2.
    }

    // vtable-empty (devirtualized) → M2 via witness-table-anchoring (the e651ff8 technique) + the real
    // init. Structure-only here (P15).
}

/// Coordinator delegate — weak-referenced ⇒ `AnyObject`. 3 requirements (protocol desc 0x1039f4fa0) → M2.
protocol ConversionInfoDelegate: AnyObject {
    // 3 requirements → M2 (resolve from the conformer / witness table).
}
