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

    /// slot0 vtable getter (get-only computed): `state == .endOfStream` (FUN_101b7e6b8 — reads state, cmp == 4).
    /// ⚑ NAME INFERRED — the getter carries no #function literal (`recover_swift_function_name` = None); declared
    /// first to occupy vtable slot0 (declaration order inferred from the slot position). Access level not
    /// binary-recoverable (manual §1 — under-include; `var` = internal).
    var isAtEndOfStream: Bool { state == .endOfStream }

    // 10 reflection fields (order = layout). Types: field-record-concrete / decode_composite-resolved.
    // formatContext: binary NON-optional (l2 IUO_STANDIN discharged this pass); set in init from FUN_101b6b184 param_1 (@0x70).
    private var formatContext: FormatContext
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

    /// Designated init — `FUN_101b6b184` (actor ⇒ the compiler emits `_swift_defaultActor_initialize`).
    /// formatContext ← param_1 (@0x70); ioAction ← param_2 boxed as a `DemuxerIOAction` existential
    /// (5-word copy via FUN_100018cdc; witness `0x1041e1788` = RemuxerIOAction's DemuxerIOAction conformance);
    /// delegate ← param_3/param_4 (weak existential {obj, witness}). state = .ready; the rest take their
    /// stored-property defaults (currentTime/seekTime/retryCount = 0; ioTask/ioWaiter/seekingCompletionHandler = nil).
    /// ioAction param = CONCRETE `RemuxerIOAction` — DISASM-CONFIRMED (P28): the init ABI is x0..x4 =
    /// formatContext / ioAction / delegate-obj / delegate-witness / self, with NO generic type-metadata or
    /// witness-table param (a `some DemuxerIOAction` would pass both in registers, as delegate's witness is in x3);
    /// the witness `0x1041e1788` + RemuxerIOAction metadata are hardcoded inside the init. `some DemuxerIOAction` disproven.
    init(formatContext: FormatContext, ioAction: RemuxerIOAction, delegate: DemuxerIODelegate?) {
        self.formatContext = formatContext
        self.ioAction = ioAction
        self.delegate = delegate
    }

    // Remaining M2 (per A″): slot26 (async state-machine) / slot27 (delegate setter) / slot29 (throws(Int32)) methods;
    // slot28/30 out-of-text; `extension Int32: Error`; the DemuxerIOAction req signature; structural kind-seq (8-vs-10 accessor residual).
}

/// Action sink the demuxer drives. 3 requirements (protocol desc 0x1039f55c0) — signatures → M2.
protocol DemuxerIOAction {
    // 3 requirements → M2 (resolve from the conformer / witness table).
}

/// Demuxer delegate — weak-referenced ⇒ `AnyObject`. 4 requirements (protocol desc 0x1039f540c) → M2.
protocol DemuxerIODelegate: AnyObject {
    // 4 requirements → M2.
}
