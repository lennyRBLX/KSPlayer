//
//  RemuxerIOAction.swift
//  ProAVPlayer
//
//  P3b M1 (structure) — Forward-new remux action (writes HLS segments + the master M3U8).
//  Field types: field-record + decode_composite (deterministic); bodies + the real init → M2.
//  Binary: desc=0x1039f561c, vtable=1 (vtable-empty; methods devirtualized → M2 / witness-anchoring).
//

import Foundation
import KSPlayer
import FFmpegKit

/// Demuxes the source and writes HLS segments + the master M3U8 that LocalHLSServer serves.
/// Forward-new (ProAVPlayer module).
final class RemuxerIOAction: DemuxerIOAction {   // binary conformance (conf@0x103571970, witness-validated); DemuxerIOAction reqs → M2
    // 10 reflection fields (order = layout). Types: field-record-concrete / decode_composite-resolved.
    private var startPlayTime: Double? = nil
    private var outputStreamInfo: OutputStreamInfo! = nil        // ⚑ binary non-optional; IUO M1 stand-in → M2
    private var formatContext: FormatContext! = nil             // ⚑ binary non-optional; IUO M1 stand-in → M2
    private var dir: URL! = nil                                 // ⚑ binary non-optional (symref); decompile: URL; IUO M1 stand-in → M2
    private var subtitles: [FFmpegAssetTrack] = []
    private weak var delegate: RemuxerIOActionDelegate? = nil   // weak optional (mangle _pSgXw)
    private var formatContextOptions: [String: Any] = [:]
    private var masterM3U8Context: String = ""
    private var packet: UnsafeMutablePointer<AVPacket>? = nil
    private var directoryWatcher: DirectoryWatcher! = nil       // ⚑ binary non-optional; KSPlayer (now public); IUO M1 stand-in → M2

    // vtable-empty (devirtualized) → M2 via witness-table-anchoring (the e651ff8 technique) + the real init.
}

/// Remux action delegate — weak-referenced ⇒ `AnyObject`. 1 requirement (protocol desc 0x1039f55f0) → M2.
protocol RemuxerIOActionDelegate: AnyObject {
    // 1 requirement → M2.
}
