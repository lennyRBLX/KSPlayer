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
    /// Demuxer state machine — nested (descriptor parent = DemuxerIO, 0x1039f5588). 7 cases; the case ORDER is
    /// GOLD-CONFIRMED (field-record reflection: ready0/reading1/seeking2/paused3/endOfStream4/closed5/failed6),
    /// corroborated by slot0 `state == .endOfStream` compiling to `cmp state==4` (audited FAITHFUL).
    enum State {
        case ready, reading, seeking, paused, endOfStream, closed, failed
    }

    /// Demux command events processed by the actor's dispatcher (slot26). Nested in DemuxerIO
    /// (descriptor parent = DemuxerIO, 0x1039f55a4). 7 cases, ORDER field-record-confirmed:
    /// seek(0)/failed(1)/startReading(2)/pause(3)/resume(4)/endOfStream(5)/close(6). `seek`/`failed` carry payloads.
    /// RESTORED — Event is present in ProAVPlayer's `__swift5_types` (build_module_classmap; parent DemuxerIO),
    /// though an earlier M1 note dropped it. Payloads + LABELS are field-record/symref-CONFIRMED (not inferred):
    ///   • `seek` mangling `Sd2to_ySbYaYbKcSg10completiont` → labels `to`/`completion`, `Sd`=Double, `Sg`=Optional
    ///     closure identical to the `seekingCompletionHandler` field type.
    ///   • `failed` payload = an indirect symbolic ref → descriptor `0x10536d100` = Swift `Error`
    ///     (the known-answer control, proven prior sessions) ⇒ `any Error`.
    /// The 5 no-payload cases carry no associated values (field-record). ⚑ Only the closure `-> Void` return
    /// (mangling `y…`) is spelling-inferred.
    enum Event {
        case seek(to: Double, completion: (@Sendable (Bool) async throws -> Void)?)
        case failed(any Error)
        case startReading
        case pause
        case resume
        case endOfStream
        case close
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
    private var state: State = .ready                             // initial .ready confirmed (init sets state=.ready, FUN_101b6b184); case order gold-confirmed (field-record)
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

    /// slot27 vtable method — `FUN_101b7fed8` (7i, sync actor-isolated, method-kind).
    /// Weak delegate setter: stores the witness (delegate+8) then tail-calls `_swift_unknownObjectWeakAssign`
    /// for the object — i.e. `self.delegate = <existential>`. Kind=Method (NOT a synthesized Setter — delegate
    /// skips an accessor triple, later·49); dispatched via vtable only (3 DATA xrefs, no code caller).
    /// ⚑ NAME INFERRED — no #function (recover_swift_function_name @0x101b7fed8 = None; vtable-only dispatch
    ///   ⇒ no caller-recovery path). ⚑ param optionality inferred `DemuxerIODelegate?` (existential-ness
    ///   ABI-confirmed: prologue x0=object / x1=witness dynamic; only nil-vs-non-nil not binary-recoverable).
    func setDelegate(_ delegate: DemuxerIODelegate?) {
        self.delegate = delegate
    }

    /// slot26 vtable method — `FUN_101b7e9d0` (721i, sync actor-isolated) — the demuxer's Event dispatcher /
    /// state machine: an `Event` → state transition + delegate notify + async Task spawn.
    /// ⚑ NAME INFERRED — recover_swift_function_name = `rcl` labels=0 vs the 4-arg ABI ⇒ MISMATCH → UNRESOLVED
    ///   (P28); `process` inferred from role. ⚑ access-level not binary-recoverable (§1) — internal (vtable slot).
    /// Dispatch map DETERMINISTIC (`decode_int_switch.py`, golden-gated): tag w8 {2→control,1→failed,0→seek};
    /// control x23 {0→startReading,1→pause,2→resume,3→endOfStream,else→close} (state-stores →3/→1/→4/→5 confirmed);
    /// seek state-set = `DAT_1044f3418` {ready,reading,seeking,paused} (read). `switch event` (by case name) is
    /// faithful by construction — Event's gold declaration order emits exactly this dispatch.
    /// ⚑ DEFERRED (UNRESOLVED, honest-deferral P36): the `Task { }` closure bodies (async read/seek loops →
    ///   slot28 `FUN_101b7ff0c` / slot30 `FUN_101b813fc` + taskspawn `FUN_101b7f678`/`101b76bbc`); the `ioAction`
    ///   vtbl +0x120 call (devirt OutputStreamInfo/DemuxerIOAction method); KSLog forms (class-wide).
    func process(_ event: Event) {
        switch event {
        case .startReading:                                              // control x23==0
            guard state == .ready || state == .seeking else { return }   // state & 0xfd == 0
            ioTask?.cancel()
            if state == .ready { state = .reading }
            ioTask = Task { /* UNRESOLVED — async read loop (slot28 FUN_101b7ff0c) */ }
        case .pause:                                                     // x23==1 → state 3
            guard state == .reading else { return }
            state = .paused
        case .resume:                                                    // x23==2 → state 1
            guard state == .paused else { return }
            state = .reading
            ioWaiter?.resume(); ioWaiter = nil
            ioTask = Task { /* UNRESOLVED — async read loop */ }
        case .endOfStream:                                               // x23==3 → state 4
            guard state == .reading || state == .paused else { return }  // state | 2 == 3
            state = .endOfStream
            // ⚑ UNRESOLVED: ioAction vtbl +0x120 (devirt); not emitted
            delegate?.demuxerDidReachEnd()
        case .close:                                                     // x23 default → state 5
            guard state != .closed else { return }
            state = .closed
            ioWaiter?.resume(); ioWaiter = nil
            ioTask = Task { /* UNRESOLVED */ }
        case .failed(let error):                                         // tag==1
            // ⚑ KSLog error form UNRESOLVED (class-wide)
            delegate?.demuxerDidFail(error)
            if state != .closed { state = .failed }
        case .seek(let to, let completion):                             // tag==0
            // ⚑ seekTime is written PER-BRANCH (not hoisted): the binary stores it only in the branches
            //   that reach it (endOfStream L268 / failed L285 / active-set L295) and returns before any
            //   store on .closed (L282-283). Hoisting it above the switch was an (inert) DIVERGENCE — fixed.
            switch state {
            case .endOfStream:
                seekTime = to
                state = .seeking
                seekingCompletionHandler = completion
                process(.startReading)                                   // recursive [FUN_101b7e9d0(0,0,0,2)]
            case .failed:
                seekTime = to
                seekingCompletionHandler = completion
            case .ready, .reading, .seeking, .paused:                    // DAT_1044f3418 set
                seekTime = to
                if state == .seeking, seekingCompletionHandler != nil {
                    Task { /* UNRESOLVED — settle the superseded in-flight seek (FUN_101b76bbc) */ }
                }
                let wasPaused = (state == .paused)
                seekingCompletionHandler = completion
                state = .seeking
                if wasPaused { ioWaiter?.resume(); ioWaiter = nil }
            case .closed:
                break
            }
        }
    }

    // Remaining M2 (per A″): slot28 (FUN_101b7fef4) + slot30 (FUN_101b813e4) async method bodies + the
    // process(_:) Task closures (async read/seek loops) → deep-async sub-units; DemuxerIOAction reqs 2-3;
    // structural kind-seq (8-vs-10 accessor + method-order, class-M2 gate).
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
    /// req1 (witness+0x10, FUN_101b6abf8) — the demuxer reached end of stream (no args). Called by
    /// `process(.endOfStream)`. Impl = ConversionInfo witness (forwards to its own delegate). ⚑ NAME INFERRED.
    func demuxerDidReachEnd()
    /// req2 (witness+0x18, FUN_101b6ac44) — the demuxer failed. Called by `process(.failed(error))`.
    /// Impl = ConversionInfo witness (forwards param_1). ⚑ NAME INFERRED; param = `any Error` (getErrorValue).
    func demuxerDidFail(_ error: any Error)
    // 1 further requirement → M2.
}
