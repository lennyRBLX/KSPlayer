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
/// ACCESS — `public` is BINARY-FORCED, not stylistic. Six `vpMV` property descriptors hang off this
/// type: currentTime / formatContext / state / isEndOfStream (user-declared) plus the SYNTHESIZED
/// `unownedExecutor` (the Actor conformance witness) and `State.hashValue`. A compiled control
/// (swiftc -O -wmo, same Xcode as validate_build.sh) settles what a vpMV proves: an INTERNAL actor
/// emits NONE — not for members spelled `public`, not for unownedExecutor — while a public actor
/// emits all of them. So vpMV proves the enclosing TYPE is externally visible, which no member
/// spelling can fake. This SUPERSEDES the older `vpMV proves a public property, nothing proves a
/// public type` reading.
/// ⚑ `public` vs `@usableFromInline internal` is NOT separable — the latter reproduces every symbol
///   measured. `public` chosen: `@usableFromInline` is only legal where some `@inlinable` needs it,
///   and ProAVPlayer has none.
public actor DemuxerIO {
    /// Demuxer state machine — nested (descriptor parent = DemuxerIO, 0x1039f5588). 7 cases; the case ORDER is
    /// GOLD-CONFIRMED (field-record reflection: ready0/reading1/seeking2/paused3/endOfStream4/closed5/failed6),
    /// corroborated by slot0 `state == .endOfStream` compiling to `cmp state==4` (audited FAITHFUL).
    /// `public` is forced twice over: `…5StateO9hashValueSivpMV` exists, and the control shows an
    /// internal enum's automatic-Hashable `hashValue` emits NO vpMV while a public one does; and a
    /// public `state` property cannot expose an internal type.
    public enum State {
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
    ///
    /// ── VALUE-WITNESS CORROBORATION — the declaration above is now re-derived a SECOND, independent way,
    ///    from Event's own metadata + value witnesses rather than from the field record. Metadata @0x1041e1770
    ///    (kind 0x201 = Enum, descriptor 0x1039f55a4 = this type) → its VWT @0x1041e16f8:
    ///      size 25, stride 32, alignMask 7 (align 8), flags 0x00230007, extraInhabitantCount 253.
    ///    • size 25 = 8 (`to: Double`) + 16 (the two-word `completion` closure) + 1 out-of-line tag byte @+0x18.
    ///      The tag is OUT-OF-LINE because `seek`'s first payload word is a `Double` (no spare bits) overlaid on
    ///      `failed`'s `Error` pointer, so the cases share no spare bits — and flags indeed clears HasSpareBits
    ///      (0x00080000). flags = HasEnumWitnesses | IsNonInline | IsNonPOD; IsNonBitwiseTakable (0x00100000) is
    ///      clear, matching `initializeWithTake` @0x101b81a74 being a raw 25-byte copy (`ldr q0,[x1]` +
    ///      `ldur q1,[x1,#9]`) — which is also where the 25 is directly observable.
    ///    • extraInhabitantCount 253 ⇒ the tag byte takes exactly 3 values {0,1,2} (256 − 3) = 2 payload cases
    ///      plus one shared "empty cases" tag. `getEnumTagSinglePayload` @0x100217dbc agrees: it treats that same
    ///      byte as occupied only when `< 3`.
    ///    • `getEnumTag` @0x101b81ad4 is the case-ORDER proof and it is exact:
    ///        `w8 = word0; w9 = tagByte; w8 += 2; return w9 > 1 ? w8 : w9`
    ///      ⇒ tag 0 → index 0 (`seek`), tag 1 → index 1 (`failed`), tag 2 → index `word0 + 2`, i.e. the five
    ///      no-payload cases occupy indices 2…6 in declaration order (startReading/pause/resume/endOfStream/
    ///      close). That reproduces the field-record order AND `process(_:)`'s control dispatch {0,1,2,3,else}
    ///      from a different section of the binary.
    ///
    /// ── COMPILER-EMITTED ARC helpers for this enum — PINNED, so they are never re-attempted as source bodies.
    ///    They carry no user source; the declaration below is what emits them.
    ///    ⚑[tool=decompile_function ref=outlined copy of DemuxerIO.Event:0x101b7f8d4 result=pinned]
    ///    ⚑[tool=decompile_function ref=outlined destroy of DemuxerIO.Event:0x101b81988 result=pinned]
    ///    Both take the value exploded into registers (x0/x1/x2 = payload words 0-2, w3 = the +0x18 tag byte —
    ///    the explosion is read off @0x101b819ac, which does `ldp x20,x21,[x1]` / `ldr x22,[x1,#0x10]` /
    ///    `ldrb w23,[x1,#0x18]` straight into x0…x3) and are instruction-for-instruction mirrors, identical
    ///    except for the two call targets. Both switch on the tag:
    ///      · tag 0 (`seek`)   → `if completionFn != 0 { swift_retain / swift_release(completionCtx) }`
    ///        (@0x1000cecec / @0x1000b6684). Two facts fall out: word0 (`to: Double`) is POD and is never
    ///        touched, and the closure context is managed with plain `swift_retain`/`swift_release` — a NATIVE
    ///        Swift box, not unknownObject/bridgeObject. So `completion` is a two-word Swift closure made
    ///        Optional by a null function pointer, exactly as declared.
    ///      · tag 1 (`failed`) → `swift_errorRetain` @0x10345cd00 / `swift_errorRelease` @0x10345ccf4 on word0 —
    ///        the payload is a boxed `any Error` sharing word0 with `seek`'s Double.
    ///      · tag 2            → `ret`. The five empty cases own nothing.
    ///    Reached from the VWT entries destroy @0x101b81974 (VWT+0x08 — loads the 25 bytes and tail-calls the
    ///    destroy helper), initializeWithCopy @0x101b819ac (VWT+0x10 — loads, calls the copy helper, stores the
    ///    25 bytes to the destination) and assignWithCopy @0x101b81a08 (VWT+0x18 — copy-new, store, then
    ///    destroy-old via @0x101b81988); plus exactly THREE inline call sites inside `process(_:)` @0x101b7e9d0,
    ///    one per `seekingCompletionHandler = completion` store in the `.seek` branch below (.endOfStream /
    ///    .failed / the active-state set). That 3-for-3 match is a further check on the branch: the binary's
    ///    retain-new / store / release-old triple is precisely the ARC bookkeeping those three assignments
    ///    require, and contributes no extra source statement.
    ///    ⚑ WORKLIST CORRECTION — the unit id `DemuxerIO_slot26_seekHandler_101b7f8d4` is a MISATTRIBUTION.
    ///      @0x101b7f8d4 is not a seek handler and not a vtable slot; its only non-code reference lies in
    ///      __LINKEDIT (@0x10506fd22), not in any vtable, and slot26 is `process(_:)` @0x101b7e9d0 (below).
    ///      `classify_compiler_helpers.py` also reads it as SOURCE (fan-in 3 ≤ 5) — a known limit, not a result:
    ///      that heuristic is calibrated to separate MODULE-SHARED runtime helpers, and a TYPE-LOCAL outlined
    ///      value witness legitimately has only a handful of callers. Fan-in cannot classify this family;
    ///      membership in the type's VWT (above) can, and should be the check used for the sibling helpers.
    public enum Event {
        case seek(to: Double, completion: (@Sendable (Bool) async throws -> Void)?)
        case failed(any Error)
        case startReading
        case pause
        case resume
        case endOfStream
        case close
    }

    /// slot0 vtable getter (get-only computed): `state == .endOfStream` (FUN_101b7e6b8 — reads state, cmp == 4).  ⚑[tool=resolve_fun_pins ref=FUN_101b7e6b8:0x101b7e6b8 result=RESOLVES_UNIQUELY] = ProAVPlayer.DemuxerIO.isEndOfStream.getter : Swift.Bool
    /// NAME + ACCESS are BINARY-PROVEN — this SUPERSEDES the earlier "NAME INFERRED / access not
    /// binary-recoverable" note. The export trie carries `…13isEndOfStreamSbvg` (= 0x101b7e6b8, the already
    /// audited slot-0 body), `…vgTq` (descriptor slot 0, confirming the slot position independently) and
    /// `…vpMV` — a property descriptor, which a compiled control shows is emitted only for an
    /// externally visible member of an externally visible TYPE. `isAtEndOfStream` has NO symbol of any
    /// kind in the subtree. No `vs`/`vM` symbol and no setter/modify descriptor ⇒ get-only, as reconstructed.
    public var isEndOfStream: Bool { state == .endOfStream }

    // 10 reflection fields (order = layout). Types: field-record-concrete / decode_composite-resolved.
    // formatContext: binary NON-optional (l2 IUO_STANDIN discharged this pass); set in init from FUN_101b6b184 param_1 (@0x70).
    public let formatContext: FormatContext
    // `public` = `…11currentTimeSdvpMV`. Setter NOT public: the class descriptor's slots 2 (Setter) and 3
    // (ModifyCoroutine) exist but are NOT IN TRIE, while the sibling getter at slot 1 IS named (`vgTq`).
    // Controls both ways: every private var's accessor descriptor in this class is likewise unnamed, and
    // SwiftSoup.Node.parentNode — a genuinely public settable var in this same image — keeps vs/vsTq/vM/vMTq.
    // ⚑ private(set) vs fileprivate(set) vs internal(set) is NOT binary-recoverable: with no setter symbol
    //   there is no discriminator. `private(set)` is the narrowest spelling, and every write is in-type.
    // CONTROL (s72): a `public private(set) var` on a public actor emits Getter impl NON-NULL with
    // Setter and Modify impls NULL in the class descriptor — exactly Forward's slots 1/2/3 here and
    // 10/11/12 for `state`; a fully public var emits all three, a private var emits none.
    public private(set) var currentTime: Double = 0
    // ⚑ Failure type UNRES (libswiftCore wall) → M2. decode_composite = Task<(), UNRES>? (optional confirmed).
    private var ioTask: Task<Void, Never>?
    // Failure type RESOLVED (supersedes "UNRES → M2"): `…8ioWaiter33_…LLScCyyts5NeverOGSgvpfi`
    // = CheckedContinuation<(), Swift.Never>?. Corroborated twice: the slot28 park is
    // `withCheckedContinuation` (non-throwing ⇒ Never), and `ioTask` above carries the IDENTICAL `s5NeverO`
    // token — so the old pairing of Task<Void,Never> with CheckedContinuation<Void,Error> was internally
    // inconsistent and one of the two had to be wrong. The trie says it was this one.
    private var ioWaiter: CheckedContinuation<Void, Never>?
    // `public` = `…5stateAC5StateOvpMV`; setter NOT public — descriptor slots 11 (Setter) and 12 (Modify)
    // are unnamed while the getter at slot 10 is named `vgTq`. ⚑ same private(set)-vs-internal(set) pin.
    public private(set) var state: State = .ready                           // initial .ready confirmed (init sets state=.ready, FUN_101b6b184); case order gold-confirmed (field-record)
    private var seekTime: Double = 0
    private var seekingCompletionHandler: (@Sendable (Bool) async throws -> Void)?
    // OPTIONALITY RESOLVED (supersedes the `UNRES → M2` pin). Field record index 9 is
    // `let <SYM:1@0x1039f55c0>_p` — flags 0x00000000 (`let`) and NO trailing `Sg`; 0x1039f55c0 is the
    // ProtocolDescriptor named `DemuxerIOAction`. The sibling `delegate` at index 11 is `_pSgXw`, so
    // this dump does emit `Sg` when it is there. A compiled control settles the remaining ambiguity:
    // BOTH `Q?` and `Q!` reflect as `_pSg`, so a bare `_p` can only come from a genuinely
    // non-optional declaration and `DemuxerIOAction!` would ADD a divergence rather than remove one.
    // Corroborated in code: readPacket @0x101b812d0-0x101b812f4 does add/ldr/bl on the existential
    // with NO `cbz` on the metadata word — a force-unwrap of an Optional existential must test it.
    // Session 62's `let` (no declaration default; trie has no symbol of any kind for this field) stands.
    private let ioAction: DemuxerIOAction
    // Type BINARY-PROVEN (supersedes the "likely Swift.Int" pin): `…10retryCount33_…LLs6UInt64Vvpfi`
    // = Swift.UInt64, class-scoped and discriminator-bearing. NOTE l2_field_gate reports Int here via an
    // UNSCOPED property-descriptor match — that PASS is a false positive; the class-scoped trie symbol wins.
    private var retryCount: UInt64 = 0
    private weak var delegate: DemuxerIODelegate?          // weak optional (mangle _pSgXw)

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

    /// slot26 vtable method — `FUN_101b7e9d0` (721i, sync actor-isolated) — the demuxer's Event dispatcher /  ⚑[tool=resolve_fun_pins ref=FUN_101b7e9d0:0x101b7e9d0 result=RESOLVES_UNIQUELY] = ProAVPlayer.DemuxerIO.send(ProAVPlayer.DemuxerIO.Event) -> ()
    /// state machine: an `Event` → state transition + delegate notify + async Task spawn.
    /// ⚑ NAME INFERRED — recover_swift_function_name = `rcl` labels=0 vs the 4-arg ABI ⇒ MISMATCH → UNRESOLVED
    ///   (P28); `process` inferred from role.
    /// ⚑ ACCESS DIVERGENCE, deliberately not applied here: a compiled control shows MethodDescriptor.Impl
    ///   is non-null iff the member is externally visible (an @inline(never), called, internal method
    ///   still gets a NULL Impl even though its body is emitted). Forward's slots 26-30 ALL carry
    ///   non-null Impls while slot 25 (Init) is NULL — so the five methods are public and the init is
    ///   not. Making them public cascades `Event` and both protocols; that is its own unit, so they
    ///   stay internal here and the divergence is recorded rather than hidden.
    /// Dispatch map DETERMINISTIC (`decode_int_switch.py`, golden-gated): tag w8 {2→control,1→failed,0→seek};
    /// control x23 {0→startReading,1→pause,2→resume,3→endOfStream,else→close} (state-stores →3/→1/→4/→5 confirmed);
    /// seek state-set = `DAT_1044f3418` {ready,reading,seeking,paused} (read). `switch event` (by case name) is
    /// faithful by construction — Event's gold declaration order emits exactly this dispatch.
    /// ⚑ DEFERRED (UNRESOLVED, honest-deferral P36): the `Task { }` closure bodies (async read/seek loops →
    ///   slot28 `FUN_101b7ff0c` / slot30 `FUN_101b813fc` + taskspawn `FUN_101b7f678`/`101b76bbc`); the `ioAction`
    ///   vtbl +0x120 call (devirt OutputStreamInfo/DemuxerIOAction method); KSLog forms (class-wide).
    // ⚑ s106 RENAME `process(_:)` → `send(_:)`. This file already recorded the address twice —
    //   line 90 counts call sites "inside `process(_:)` @0x101b7e9d0" and line 97 calls slot26
    //   `process(_:)` — while the trie demangles that same address
    //   `ProAVPlayer.DemuxerIO.send(ProAVPlayer.DemuxerIO.Event) -> ()`. Same single unlabelled
    //   Event parameter and Void return, so a rename and not a signature change. No call sites:
    //   the other `process(` hits in the tree are KSOptions' unrelated overloads.
    //   ⚑[tool=export_trie_oracle ref=DemuxerIO.send:0x101b7e9d0 result=send-not-process]
    public func send(_ event: Event) {
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
                send(.startReading)                                      // recursive [FUN_101b7e9d0(0,0,0,2)]  ⚑[tool=resolve_fun_pins ref=FUN_101b7e9d0:0x101b7e9d0 result=RESOLVES_UNIQUELY] = ProAVPlayer.DemuxerIO.send(ProAVPlayer.DemuxerIO.Event) -> ()
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

    /// slot27 vtable method — `FUN_101b7fed8` (7i, sync actor-isolated, method-kind).  ⚑[tool=resolve_fun_pins ref=FUN_101b7fed8:0x101b7fed8 result=RESOLVES_UNIQUELY] = ProAVPlayer.DemuxerIO.update(delegate: ProAVPlayer.DemuxerIODelegate?) -> ()
    /// Weak delegate setter: stores the witness (delegate+8) then tail-calls `_swift_unknownObjectWeakAssign`
    /// for the object — i.e. `self.delegate = <existential>`. Kind=Method (NOT a synthesized Setter — delegate
    /// skips an accessor triple, later·49); dispatched via vtable only (3 DATA xrefs, no code caller).
    /// ⚑ s106 RENAME `setDelegate(_:)` → `update(delegate:)`. The name was never inferred-and-unknown:
    ///   the pin two lines above already resolved this address to
    ///   `ProAVPlayer.DemuxerIO.update(delegate: ProAVPlayer.DemuxerIODelegate?)`, and the declaration
    ///   below it used a different one. The old "NAME INFERRED — no #function" note was true about
    ///   `recover_swift_function_name` and irrelevant: the export trie names this address directly, and
    ///   a trie name is read, not inferred.
    ///   BOTH parts differ and both are taken from the trie: the base name (`setDelegate` → `update`)
    ///   and the argument label (`_` → `delegate:`). The parameter type, arity and Void return already
    ///   matched, so this is a rename and not a signature change.
    ///   ⚑[tool=export_trie_oracle ref=DemuxerIO.update(delegate:):0x101b7fed8 result=update-not-setDelegate]
    ///   Body unchanged and independently corroborated: field 10 `delegate` carries the mangle tail
    ///   `_pSgXw` — existential, optional, WEAK — and the tail call is
    ///   ⚑[tool=bind_oracle ref=__got:0x1041130c0 result=_swift_unknownObjectWeakAssign], which is the
    ///   weak store this line compiles to.
    ///   ⚑ param optionality still inferred (existential-ness is ABI-confirmed; nil-vs-non-nil is not).
    public func update(delegate: DemuxerIODelegate?) {
        self.delegate = delegate
    }

    /// slot28 vtable async method — `FUN_101b7fef4` (async sync-entry: stores self into the async frame
    /// [@0x248] then `_swift_task_switch` to the continuation `FUN_101b7ff0c`; async-func-ptr vtable record,
    /// P41). The read-drive body the demuxer's `ioTask = Task { }` runs (spawned by `process`).
    /// ⚑ NAME INFERRED — `recover_swift_function_name` @0x101b7fef4/0x101b7ff0c = None (async, no #function);
    ///   `readLoop` inferred from role (the ioTask read/seek/park driver).
    /// State-dispatched — `decode_int_switch.py --addr 0x101b7ff0c --reg w8 --start 0x101b7ff58` (golden-gated):
    ///   `{1 .reading → 0x101b80150, 2 .seeking → 0x101b800b8, 3 .paused → 0x101b7ff74, else → return}`.
    ///   Per-state actions decompile-grounded (continuation glossary):
    ///     • `.reading` → `do { try readPacket() (slot29); retryCount = 0 } catch {…}` — retryCount=0 is
    ///       success-ONLY (swifterror cbz @0x101b80160 → 0x101b8051c); the throw path (0x101b80164) is deep-async
    ///     • `.seeking` → settle `seekingCompletionHandler` (async completion continuation)
    ///     • `.paused`  → park via `withCheckedContinuation` storing `ioWaiter` (pre-park formatContext check)
    /// ⚑ UNRESOLVED (honest-deferral P36 — genuinely unrecoverable async internals): the continuation
    ///   linearization — resumption partials `FUN_101b80e88/80f54/809e0/80c38/80a28/80c80` + 2 unrecovered
    ///   jumptables ("Too many branches") + 32 pruned unreachable blocks + the `.paused` pre-park
    ///   formatContext dynamic-cast/witness; the exact while/await interleaving across suspension points is
    ///   not faithfully recoverable. The loop is the Task/continuation re-entry, NOT a `while` in this body.
    public func readLoop() async {
        switch state {
        case .reading:
            do {
                try readPacket()    // slot29 FUN_101b812b0
                retryCount = 0      // success-ONLY — swifterror cbz @0x101b80160 → success block 0x101b8051c (str xzr → retryCount); NOT on the throw path
            } catch {
                // ⚑ UNRESOLVED — throw path (0x101b80164): error-retain + dynamicCast + deep-async handling/retry
            }
        case .seeking:
            break               // ⚑ UNRESOLVED — settle seekingCompletionHandler (FUN_101b80e88/80f54)
        case .paused:
            break               // ⚑ UNRESOLVED — park: withCheckedContinuation → ioWaiter (formatContext pre-check FUN_101b809e0/80c38)
        default:
            break
        }
    }

    /// slot29 vtable method — `FUN_101b812b0` (77i, sync actor-isolated, `throws(Int32)`).  ⚑[tool=resolve_fun_pins ref=FUN_101b812b0:0x101b812b0 result=NOT_IN_TRIE]
    /// Drives one demux read through the action, records currentTime, notifies the delegate; on a
    /// read error throws the FFmpeg status as a typed `Int32`.
    /// ⚑ NAME INFERRED — no #function literal (`recover_swift_function_name` @0x101b812b0 = None); the
    ///   demuxer's per-call read-drive wrapper (identifier inferred from role + call target `performRead`).
    /// ioAction is read UNCONDITIONALLY (`add x0,x20,x8` / `ldr x1,[x0,#0x18]` / `bl 0x10002abb8`, no
    ///   `cbz` on the metadata word) — which is what a NON-optional field compiles to. The old
    ///   `ioAction!` force-unwrap modelled that absence; with the field record's bare `_p` spelling it
    ///   out as non-optional, the model is no longer needed and the pin is DISCHARGED.
    /// ⚑ PUNNED throw — on error, `ReadResult.value` (Double) carries the Int32 av_read_frame status in its  ⚑[tool=ffmpeg_name_oracle ref=av_read_frame:0x1030e6e78 result=CONFIRMED]
    ///   low 32 bits (performRead packs `Double(bitPattern: UInt64(UInt32(bitPattern: status)))`); the binary
    ///   reads value's low 4 bytes as the Int32 (auVar5._0_4_ → `_swift_allocError`/`_swift_willThrowTypedImpl`
    ///   on the Swift.Int32 metadata). currentTime write = `_swift_beginAccess`(self+0x78); delegate notify
    ///   = weak-load + witness `(*(wt+8))(value)`.
    public func readPacket() throws(Int32) {
        let r = ioAction.performRead(formatCtx: formatContext.formatCtx)
        if r.isError {
            throw Int32(bitPattern: UInt32(truncatingIfNeeded: r.value.bitPattern))
        } else if !r.isEnd {
            currentTime = r.value
            delegate?.didUpdateCurrentTime(r.value)
        }
    }

    /// slot30 vtable async method — `FUN_101b813e4` (async sync-entry: stores self [@0x10] then
    /// `_swift_task_switch` to `FUN_101b813fc`; async-func-ptr vtable record, P41). Cancels + drains the
    /// in-flight read task, tears down, and notifies the delegate.
    /// ⚑ NAME INFERRED — `recover_swift_function_name` = None; `cancelReading` from role (cancel-drain-close).
    /// Spine decompile-grounded (`FUN_101b813fc`): `if let t = ioTask { t.cancel(); await t.value }`
    ///   (ioTask @0x80) → `ioTask = nil` → teardown → `delegate?.<req3>()` (weak-load, witness wt+0x20 = the
    ///   4th DemuxerIODelegate requirement, no-arg ABI-confirmed).
    /// ⚑ UNRESOLVED (honest-deferral P36): the `await t.value` resumption (continuation `FUN_101b814f8`) +
    ///   the tail jumptable ("Too many branches") + the teardown callees (release ioAction `FUN_10002abb8`;
    ///   `FUN_101b82c04` module-new / `FUN_101a3302c` base).  ⚑[tool=resolve_fun_pins ref=FUN_101a3302c:0x101a3302c result=RESOLVES_UNIQUELY] = KSPlayer.FormatContext.close() -> ()
    public func cancelReading() async {
        if let task = ioTask {
            task.cancel()
            _ = await task.value
        }
        ioTask = nil
        // ⚑ UNRESOLVED — teardown: release ioAction (FUN_10002abb8) + FUN_101b82c04 / FUN_101a3302c cleanup  ⚑[tool=resolve_fun_pins ref=FUN_101a3302c:0x101a3302c result=RESOLVES_UNIQUELY] = KSPlayer.FormatContext.close() -> ()
        delegate?.demuxerDidClose()
    }

    // Remaining M2 (per A″): the process(_:) `Task { }` closures are SEPARATE deep-async impls, NOT thin
    //   `await self.readLoop()` wrappers — decoded the async-func records: read &DAT_1035719d0→FUN_101b7df4c /
    //   &DAT_1035719d8→FUN_101b85db4; seek-settle &DAT_103571690/16a0→FUN_101b7dfc4 (none call slot28/30 in-head).
    //   Faithful wiring ⇒ reconstruct those closures = their own deep-async unit (deferred, P36).
    // Also deferred: the readLoop .seeking/.paused + .reading-catch + cancelReading await-value continuation
    //   internals (deep-async); DemuxerIOAction reqs 2-3.
    // ── DECLARATION ORDER — the five methods are now in BINARY SLOT ORDER (s72). Swift lays a class's
    //   own vtable slots out in declaration order (compiled control: five methods alternating
    //   sync/async reproduce their IsAsync bits in declaration order, and Init takes its declaration
    //   position too). Forward's slots 25-30 read {Init, sync, sync, ASYNC, sync, ASYNC} from the
    //   MethodDescriptor flag bytes at 0x1039f5558 (0x01/0x10/0x10/0x50/0x10/0x50); the old order
    //   emitted {Init, sync, sync, sync, ASYNC, ASYNC} and was refuted at slots 28/29 WITHOUT using a
    //   single name. Identity: slot 26 = 0x101b7e9d0 = trie `DemuxerIO.send(Event)` (= process);
    //   slot 27 = 0x101b7fed8 = trie `DemuxerIO.update(delegate:)` (= setDelegate); slots 28/30 are the
    //   two async methods (async-function-pointer records 0x103571840 -> 0x101b7fef4 ctx 736 and
    //   0x103571848 -> 0x101b813e4 ctx 48); slot 29 is readPacket by elimination. Slot 30 is
    //   cancelReading because its body loads ioTask (self+0x80) and `cbz`s on it; slot 28 is readLoop
    //   because its body beginAccess-es the state byte and dispatches 3 ways.
    //   This SUPERSEDES the earlier refusal to reorder. Both of its premises are gone: source and
    //   binary now emit 31 slots with an IDENTICAL kind sequence (no +6 offset), and the old
    //   `src 10 vs bin 8 accessor-triples … library-evolution artifact` diagnosis was wrong — `let`
    //   stored properties get NO class-vtable accessor slot, so 8 vars give 8 triples and the two
    //   `let`s (formatContext, ioAction) give none.
}

/// Typed-throw support for `DemuxerIO.readPacket() throws(Int32)`. Binary-implied — the slot29 throw path
/// boxes an `Int32` as an `Error` (`_swift_allocError`/`_swift_willThrowTypedImpl` on the Swift.Int32
/// metadata), which requires `Int32: Error` in the module. ⚑ Placement inferred (Forward-new, ProAVPlayer).
extension Int32: Error {}

/// Action sink the demuxer drives. 3 requirements (protocol desc 0x1039f55c0); **2/3 impls located +
/// field-access-confirmed** (performRead + cancel), the 3rd deep-async-deferred (below).
/// ⚑ ALL 3 witnesses are `_swift_deletedMethodError` (wt 0x1041e1788) → every call is devirtualized to a
///   direct `RemuxerIOAction` method. DemuxerIO stores `ioAction` as THIS protocol type (`ioAction:
///   DemuxerIOAction?`), so any method it invokes on `ioAction` IS a requirement. Consequence: the witness
///   table is never dispatched ⇒ the requirement ORDER is binary-UNOBSERVABLE — the declaration order here
///   is a FREE choice, NOT binary-pinned (contrast the offset-pinned `ConversionInfoDelegate`).
/// ⚑ `#file` does NOT attribute a method to a class here: DemuxerIO + RemuxerIOAction SHARE the source file
///   `RemuxerIO.swift`, so methods are attributed by SELF-FIELD ACCESS, not #file.
protocol DemuxerIOAction {
    /// Demux-read requirement — impl = `RemuxerIOAction.performRead(formatCtx:)` (binary FUN_101b823b8).
    /// NON-throwing (0 throw machinery in the impl; the actor-side `DemuxerIO.slot29` is the `throws(Int32)`
    /// wrapper). Returns a 3-field status struct (see `RemuxerIOAction.ReadResult`).
    /// ⚑ `formatCtx` param type INFERRED = `UnsafeMutablePointer<AVFormatContext>`: the impl passes x0 straight
    ///   to `av_read_frame` (FUN_1030e6e78), which dereferences it as a raw C `AVFormatContext*` (fields
    ///   +0x10/+0x3d/+0x08…), NOT as the Swift `FormatContext` wrapper. Caller-side confirmation (what
    ///   `DemuxerIO.slot29` forwards) is walled → M2.
    func performRead(formatCtx: UnsafeMutablePointer<AVFormatContext>) -> RemuxerIOAction.ReadResult

    /// Teardown/cancel requirement — impl = `RemuxerIOAction` method binary `FUN_101b82c04`
    /// (self=RemuxerIOAction, FIELD-ACCESS-confirmed: reads `outputStreamInfo`@0x20 + the literal
    /// `RemuxerIOAction.packet` offset — NOT #file, which is the shared `RemuxerIO.swift`). Driven by
    /// `DemuxerIO.cancelReading` on `ioAction`. No args, `Void`, non-throwing (P44: epilogue plain `ret`;
    /// removeItem's error is `do/catch`-swallowed). Body = close `outputStreamInfo` (devirt vtable
    /// +0x120/+0x128) + `av_packet_unref` + `FileManager.default.removeItem(at: dir)` — OSI-devirt-coupled,
    /// so the impl is a grounded doc-stub (→ RemuxerIOAction M2). ⚑ NAME `cancel()` INFERRED
    /// (`recover_swift_function_name` = None; no #function).
    func cancel()

    // ⚑ 3rd requirement — DEFERRED WITH EVIDENCE (P43, searched not assumed): walked DemuxerIO's reachable
    //   async graph (process/readLoop/cancelReading + `_swift_task_switch` continuations, depth 7 / 11 funcs)
    //   — NO 3rd `ioAction` call found. Either a rarely-/un-invoked protocol req or beyond the core-loop
    //   graph → the DemuxerIO deep-async wiring unit. Count stays honest at 2/3 declared (req COUNT=3 is
    //   descriptor-confirmed; the missing impl is not fabricated).
}

/// Demuxer delegate — weak-referenced ⇒ `AnyObject`. 4 requirements (protocol desc 0x1039f540c).
public protocol DemuxerIODelegate: AnyObject {
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
    /// req3 (witness table +0x20, no-arg) — the demuxer cancelled/closed its in-flight read task. Called by
    /// the cancel-drain async method (slot30 `FUN_101b813fc`: weak-load `delegate` → witness `wt+0x20`).
    /// Impl = ConversionInfo witness (forwards to its own delegate). ⚑ NAME INFERRED
    /// (`recover_swift_function_name` = None); no-arg ABI-confirmed (the witness call site passes no args).
    func demuxerDidClose()
}
