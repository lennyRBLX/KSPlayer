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
import FFmpegKit   // AVFormatContext for the performRead(formatCtx:) req (matches RemuxerIOAction's import)

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

    /// slot29 vtable method — `FUN_101b812b0` (77i, sync actor-isolated, `throws(Int32)`).
    /// Drives one demux read through the action, records currentTime, notifies the delegate; on a
    /// read error throws the FFmpeg status as a typed `Int32`.
    /// ⚑ NAME INFERRED — no #function literal (`recover_swift_function_name` @0x101b812b0 = None); the
    ///   demuxer's per-call read-drive wrapper (identifier inferred from role + call target `performRead`).
    /// ⚑ `ioAction!` force-unwrap — the binary copies+calls `ioAction` with NO null-check (field optionality
    ///   UNRES, l2 mangle-truncated); modeled as a force-unwrap of the `DemuxerIOAction?` field.
    /// ⚑ PUNNED throw — on error, `ReadResult.value` (Double) carries the Int32 av_read_frame status in its
    ///   low 32 bits (performRead packs `Double(bitPattern: UInt64(UInt32(bitPattern: status)))`); the binary
    ///   reads value's low 4 bytes as the Int32 (auVar5._0_4_ → `_swift_allocError`/`_swift_willThrowTypedImpl`
    ///   on the Swift.Int32 metadata). currentTime write = `_swift_beginAccess`(self+0x78); delegate notify
    ///   = weak-load + witness `(*(wt+8))(value)`.
    func readPacket() throws(Int32) {
        let r = ioAction!.performRead(formatCtx: formatContext.formatCtx)
        if r.isError {
            throw Int32(bitPattern: UInt32(truncatingIfNeeded: r.value.bitPattern))
        } else if !r.isEnd {
            currentTime = r.value
            delegate?.didUpdateCurrentTime(r.value)
        }
    }

    // Remaining M2 (per A″): slot26 (async state-machine) / slot27 (delegate setter) methods;
    // slot28/30 out-of-text; the DemuxerIOAction reqs 2-3; structural kind-seq (8-vs-10 accessor residual).
}

/// Typed-throw support for `DemuxerIO.readPacket() throws(Int32)`. Binary-implied — the slot29 throw path
/// boxes an `Int32` as an `Error` (`_swift_allocError`/`_swift_willThrowTypedImpl` on the Swift.Int32
/// metadata), which requires `Int32: Error` in the module. ⚑ Placement inferred (Forward-new, ProAVPlayer).
extension Int32: Error {}

/// Action sink the demuxer drives. 3 requirements (protocol desc 0x1039f55c0) — signatures → M2.
protocol DemuxerIOAction {
    /// Demux-read requirement — impl = `RemuxerIOAction.performRead(formatCtx:)` (binary FUN_101b823b8).
    /// NON-throwing (0 throw machinery in the impl; the actor-side `DemuxerIO.slot29` is the `throws(Int32)`
    /// wrapper). Returns a 3-field status struct (see `RemuxerIOAction.ReadResult`).
    /// ⚑ `formatCtx` param type INFERRED = `UnsafeMutablePointer<AVFormatContext>`: the impl passes x0 straight
    ///   to `av_read_frame` (FUN_1030e6e78), which dereferences it as a raw C `AVFormatContext*` (fields
    ///   +0x10/+0x3d/+0x08…), NOT as the Swift `FormatContext` wrapper. Caller-side confirmation (what
    ///   `DemuxerIO.slot29` forwards) is walled → M2. The other 2 reqs remain → M2.
    func performRead(formatCtx: UnsafeMutablePointer<AVFormatContext>) -> RemuxerIOAction.ReadResult
    // 2 further requirements → M2 (resolve from the conformer / witness table).
}

/// Demuxer delegate — weak-referenced ⇒ `AnyObject`. 4 requirements (protocol desc 0x1039f540c).
protocol DemuxerIODelegate: AnyObject {
    /// req0 (witness table +8) — notified with the current demux time (seconds) after a non-EOF read,
    /// from `DemuxerIO.readPacket()` (slot29). Impl = ConversionInfo witness `FUN_101b6a40c`
    /// (`void f(double)` — single `Double`, `Void` return, synchronous; ABI-confirmed, P28).
    /// ⚑ NAME INFERRED (`recover_swift_function_name` = None on all 4 req witnesses); param type/arity ABI-confirmed.
    func didUpdateCurrentTime(_ value: Double)
    // 3 further requirements → M2.
}
