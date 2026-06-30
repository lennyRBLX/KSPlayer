//
//  DemuxerIO.swift
//  ProAVPlayer
//
//  P3b M1 (structure) — Forward-new demuxer IO for the convert-to-HLS pipeline.
//  Field types: field-record + decode_composite (deterministic); method bodies + the real init → M2.
//  Binary: desc=0x1039f5450, vtable=31 slots, 6 impl bodies (3 getter + 3 method); 25 devirt → M2.
//

import Foundation
import KSPlayer

/// Drives demuxing of the source for the HLS conversion (reads the FormatContext, runs seek/state).
/// Forward-new (ProAVPlayer module). Binary-confirmed `actor` (init calls
/// `_swift_defaultActor_initialize` + a `$defaultActor` field record present; actors are implicitly final).
actor DemuxerIO {
    /// Demuxer state machine — nested (descriptor parent = DemuxerIO). 7 cases (field-record reflection).
    enum State {
        case ready, reading, seeking, paused, endOfStream, closed, failed
    }

    // 10 reflection fields (order = layout). Types: field-record-concrete / decode_composite-resolved.
    private var formatContext: FormatContext! = nil               // ⚑ binary non-optional; IUO M1 stand-in (init-constructed) → M2
    private var currentTime: Double = 0
    // ⚑ Failure type UNRES (libswiftCore wall) → M2. decode_composite = Task<(), UNRES>? (optional confirmed).
    private var ioTask: Task<Void, Never>? = nil
    // ⚑ Failure type UNRES → M2. decode_composite = CheckedContinuation<(), UNRES>? (optional confirmed).
    private var ioWaiter: CheckedContinuation<Void, Error>? = nil
    private var state: State = .ready                             // ⚑ initial case inferred (first case) → M2 confirms
    private var seekTime: Double = 0
    private var seekingCompletionHandler: (@Sendable (Bool) async throws -> Void)? = nil
    // ⚑ optionality UNRES (decode_composite=None, mangle truncated) → M2. symref → DemuxerIOAction.
    private var ioAction: DemuxerIOAction? = nil
    private var retryCount: Int = 0                              // ⚑ type symref-unresolved (likely Swift.Int, non-opt) → M2
    private weak var delegate: DemuxerIODelegate? = nil          // weak optional (mangle _pSgXw)

    // 31-slot vtable / 6 impl bodies + the real init → M2 (per-method pre-flight + body-audit).
}

/// Action sink the demuxer drives. 3 requirements (protocol desc 0x1039f55c0) — signatures → M2.
protocol DemuxerIOAction {
    // 3 requirements → M2 (resolve from the conformer / witness table).
}

/// Demuxer delegate — weak-referenced ⇒ `AnyObject`. 4 requirements (protocol desc 0x1039f540c) → M2.
protocol DemuxerIODelegate: AnyObject {
    // 4 requirements → M2.
}
