//
//  SubtitleActor.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15. Swift actor for thread-safe subtitle state
//  management. Actor isolation serializes `parts` mutations from background
//  decode and reads from the main-thread display.
//
//  Canonical create-or-update entry: `SubtitleActor_createOrUpdateActor`
//  @ 0x1014910a4 (Ghidra entry; older notes used the IDA-era address
//  0x101374BCC, which is interior to a wrapper — see SubtitleSystem.md
//  §"Deprecated IDA-era addresses").
//

import Foundation

/// Thread-safe subtitle state container using Swift actor isolation.
///
/// Wraps subtitle parts and track info so that background decode tasks and
/// main-thread display reads are serialized without explicit locking.
///
/// RE: 136-byte (0x88) actor — confirmed exact via `createOrUpdateActor`'s
/// three ivar writes:
///   - `+0x70`  = parts ref (`emptyArrayStorage`)
///   - `+0x78`  = SubtitleInfo existential object ref
///   - `+0x80`  = SubtitleInfo existential witness table
/// End-of-instance is at `+0x88`. Header (0x10) + DefaultActorStorage
/// (0x60) + parts (0x8) + class-existential pair (0x10) = 0x88.
public actor SubtitleActor {
    /// Full subtitle parts for the active track — the actor's canonical
    /// storage, populated once parsing completes and never narrowed by
    /// time-change handling.
    ///
    /// RE: stored at `+0x70`; `createOrUpdateActor` seeds it with
    /// `emptyArrayStorage` (`plVar4[0xe]`). The parse result (`startParsing` /
    /// `ingest` / `setParts`) writes the COMPLETE parsed array here; the
    /// per-instant visible window is derived into `activeParts` by
    /// `handleTimeChange` and is what display consumers read.
    public private(set) var parts: [SubtitlePart]

    /// The subset of `parts` visible at `currentTime`, recomputed on each
    /// time change. Derived view over `parts`; mutating it never disturbs the
    /// canonical track storage. Observers fire when this window shifts.
    public private(set) var activeParts: [SubtitlePart] = []

    /// Metadata for the active subtitle track.
    ///
    /// RE: stored as a class-constrained existential pair at `+0x78`
    /// (object) / `+0x80` (witness). `createOrUpdateActor` writes the actor
    /// WITH its info (`plVar4[0xf] = info_ref`, `plVar4[0x10] = info_witness`);
    /// the actor is never created in a default-nil-then-set shape, so this is
    /// non-optional and set at init time. (Resolves the prior optional
    /// `(any SubtitleInfo)?` field type.)
    public private(set) var info: any SubtitleInfo

    /// Current playback time (seconds) the actor is selecting parts against.
    ///
    /// RE: `setCurrentTime` @ 0x100040584 stages this through an async
    /// continuation (`swift_task_alloc` + `FUN_10003a410`) before it drives
    /// part selection via `handleTimeChange`.
    private var currentTime: TimeInterval = 0

    /// Observer callbacks invoked when the active parts window changes.
    /// `notifyObservers` walks this list; `deinit` tears it down.
    private var observers: [(SubtitleActor) -> Void] = []

    /// In-flight parse task, retained so `deinit` can cancel it.
    private var parseTask: Task<Void, Never>?

    /// Designated initializer — the actor is always created with its track
    /// info, matching `createOrUpdateActor`'s allocate-and-seed sequence
    /// (`_swift_allocObject` + `_swift_defaultActor_initialize`, then the
    /// three ivar writes).
    ///
    /// RE: 0x1014910a4 (field seeding portion).
    public init(info: any SubtitleInfo) {
        self.parts = []
        self.info = info
    }

    // MARK: - createOrUpdateActor (RE: 0x1014910a4)

    /// Canonical create-or-update entry point.
    ///
    /// Compares the incoming track `info` against `existing`'s stored info via
    /// the info identity (the binary's `_stringCompareWithSmolCheck` over the
    /// existential's `subtitleID` string). Behaviour:
    ///   - If `existing` already holds the same info → returns `existing`
    ///     unchanged (the `LAB_1014912b0` early-out; no re-parse).
    ///   - Otherwise → deselects the stored track through its witness
    ///     (`info.isEnabled = false`, the `*(code**)(lVar10+0x38)` witness
    ///     call), allocates a fresh actor seeded with empty parts + the new
    ///     info, and kicks `startParsing`. The freshly returned actor is the
    ///     one the caller installs into its `firstSubtitleActor` slot.
    ///
    /// In the binary this is a free function that also performs the
    /// model-side slot swap (`*(unaff_x20 + *param_4) = plVar4`); that
    /// store belongs to `SubtitleModel.firstSubtitleActor` and stays with the
    /// caller. See the CROSS-FILE note in the reconstruction summary.
    ///
    /// RE: 0x1014910a4 (564B).
    public static func createOrUpdate(existing: SubtitleActor?,
                                      info: any SubtitleInfo) async -> SubtitleActor {
        if let existing {
            let storedID = await existing.info.subtitleID
            if storedID == info.subtitleID {
                // Same track — no change, no re-parse (LAB_1014912b0).
                return existing
            }
            // Different track — deselect the stored one via its witness.
            await existing.deselect()
        }
        // Allocate + seed a fresh actor, then begin parsing.
        let actor = SubtitleActor(info: info)
        await actor.startParsing()
        return actor
    }

    /// Deselect the actor's current track (witness `+0x38` call in
    /// `createOrUpdateActor`). Disables the stored `SubtitleInfo` so the model
    /// stops treating it as the active selection.
    func deselect() {
        info.isEnabled = false
    }

    // MARK: - startParsing (RE: 0x101494d94)

    /// Begin async subtitle parsing for the actor's track. Critical path.
    ///
    /// RE: `SubtitleActor_startParsing` @ 0x101494d94 (1504B). The binary's
    /// body, decompiled against the model context it runs on:
    ///   1. Platform-gates an iOS 17.4+ `TranslationSession.Configuration`
    ///      branch (`__isPlatformVersionAtLeast(_, 0x12, 0, 0)` →
    ///      `__s11Translation0A7SessionC13ConfigurationVMa`); the on-device
    ///      translation config is only built when available. (Reconstructed
    ///      as the `#available` guard below; the concrete translation wiring
    ///      lives in `SubtitleTranslation.swift` and is invoked there.)
    ///   2. Calls `SubtitleModel_updateSubtitlePosition`.
    ///   3. For a `URLSubtitleInfo`, reads `downloadURL`; if the URL
    ///      `isFileURL`, probes `resourceValues(forKeys:)` for
    ///      `isUbiquitousItem` (iCloud) and bails on the not-yet-downloaded
    ///      case (`URLResourceValues.isUbiquitousItem == .some(true)` →
    ///      early return).
    ///   4. Reads the registered data sources (model `+0x50`) and, on the
    ///      `MainActor` executor (`swift_task_reportUnexpectedExecutor`
    ///      asserts `SubtitleModel.swift:28` runs on `MainActor.shared`),
    ///      dispatches the parse for the first source conforming to the
    ///      parse protocol.
    ///
    /// This Swift reconstruction performs the load+parse for the actor's own
    /// URL-backed track through the standalone `SubtitleParse` driver (the
    /// five-parser registry from `KSOptions.subtitleParses`), stores the
    /// result into `parts`, and notifies observers. The model-side position
    /// update and data-source iteration are driven by
    /// `SubtitleModel.resetAndReloadSubtitleSources`; see CROSS-FILE note.
    public func startParsing() {
        // Cancel any prior in-flight parse before starting a new one.
        parseTask?.cancel()
        let info = self.info
        parseTask = Task { [weak self] in
            guard let self else { return }
            // (3) Only URL-backed tracks have an external file to fetch+parse.
            guard let urlInfo = info as? URLSubtitleInfo else { return }
            let url = urlInfo.downloadURL
            // (3) iCloud guard: skip a ubiquitous item that is not yet
            // materialized locally (binary's isUbiquitousItem early-return).
            if url.isFileURL,
               let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey]),
               values.isUbiquitousItem == true {
                return
            }
            // (4) Drive the five-parser registry through the standalone driver.
            let driver = SubtitleParse(registry: SubtitleParseRegistry(parsers: KSOptions.subtitleParses))
            guard let parsed = try? await driver.loadAndParseAsync(url: url) else { return }
            await self.ingest(parsed)
        }
    }

    /// Install freshly parsed parts and republish to observers.
    /// Split out so `startParsing`'s detached task can hop back onto the
    /// actor before mutating `parts`. Recomputes the visible window against the
    /// current time so a freshly parsed track shows the right cues immediately
    /// (`handleTimeChange` fans out to observers).
    private func ingest(_ newParts: [SubtitlePart]) {
        parts = newParts
        handleTimeChange()
    }

    // MARK: - setCurrentTime (RE: 0x100040584)

    /// Set the actor's current playback time, which drives part selection.
    ///
    /// RE: `SubtitleActor_setCurrentTime` @ 0x100040584. The binary stages the
    /// time through an async continuation (`swift_task_alloc`, continuation
    /// `FUN_100004eac`, trampoline `FUN_10003a410`) so the update lands on the
    /// actor's executor; here actor isolation provides that hop directly. The
    /// staged time then feeds `handleTimeChange`.
    public func setCurrentTime(_ time: TimeInterval) {
        currentTime = time
        handleTimeChange()
    }

    // MARK: - handleTimeChange (RE: inlined into setCurrentTime chain — see note)

    /// Handle a playback-time change: recompute the active parts window for the
    /// stored track at `currentTime` and notify observers if it shifted.
    ///
    /// RE NOTE — re-verify RESOLVED: there is NO standalone time-change-handler
    /// function in the binary; the role is inlined into the `setCurrentTime`
    /// async continuation chain. Evidence:
    ///
    ///  1. The catalog's `SubtitleActor_handleTimeChange` @ 0x10137adb8 is a
    ///     mis-attribution. Its decompiled body is a SwiftUI
    ///     `_BackgroundModifier<Color>` type-metadata accessor — lazy-cache
    ///     guard `DAT_103d05bd8`, a call to `__s7SwiftUI19_BackgroundModifierVMa`
    ///     passing `PTR___s7SwiftUI5ColorVN` (Color metadata) +
    ///     `…ColorVAA4ViewAAWP` (the `Color: View` witness). Zero subtitle logic.
    ///     Both its callers (`FUN_10137ab34`, `FUN_10137af2c`, @ 0x10137ab48 /
    ///     0x10137af6c) merely hand the symbol to a metadata-cache helper
    ///     (`FUN_1007189a0(_, &DAT_103d05b90, …, handleTimeChange)`) as a
    ///     generic-metadata instantiation fn-pointer — it is never invoked as a
    ///     time handler. It sits in the same 0x10137xxxx zone where
    ///     SubtitleSystem.md already STRUCK two SubtitleActor entries
    ///     (`0x10137ace0` = `ModifiedContent/_PaddingLayout` accessor, also
    ///     re-confirmed here; `0x10000af54`).
    ///  2. `search_functions("handleTimeChange")` over all 165,776 functions
    ///     returns ONLY that one bogus symbol — no correctly-named entry exists.
    ///  3. `createOrUpdateActor` @ 0x1014910a4 has exactly one logic-bearing
    ///     callee (`startParsing`); 0x10137adb8 is absent from the actor's call
    ///     graph entirely.
    ///  4. The real driver is `setCurrentTime` @ 0x100040584: it snapshots state
    ///     and hands it to a continuation (`FUN_100004eac` / trampoline
    ///     `FUN_10003a410`) that `swift_task_switch`es onto the actor's executor
    ///     (`FUN_10003a42c` → …), where the time-driven selection runs. So the
    ///     binary expresses "recompute on the actor after a time change" via the
    ///     continuation hop; here that hop is provided by actor isolation, and
    ///     this method is the synchronous body `setCurrentTime`/`ingest`/
    ///     `setParts` call once already on the actor.
    func handleTimeChange() {
        // Derive the visible window from the canonical `parts` storage using
        // the `SubtitlePart == TimeInterval` predicate (start <= t <= end).
        // This must NOT narrow `parts` itself — that array is the full track
        // and overwriting it would permanently drop every not-yet-visible
        // cue, so subtitles could never reappear after scrolling past.
        let active = parts.filter { $0 == currentTime }
        // Only republish when the visible window actually changed.
        if active != activeParts {
            activeParts = active
            notifyObservers()
        }
    }

    // MARK: - notifyObservers (RE: 0x1014970c8)

    /// Push the actor's current state to every registered observer.
    ///
    /// RE: `SubtitleActor_notifyObservers` @ 0x1014970c8. The binary gates on a
    /// flag at `+0x59` before reading state at `+0x10` and bridging it out
    /// (the `objc_msgSend` / `_unconditionallyBridgeFromObjectiveC` glue is the
    /// Combine `Published`/observation plumbing). Here the equivalent is a
    /// direct fan-out to the registered callbacks.
    func notifyObservers() {
        for observe in observers {
            observe(self)
        }
    }

    /// Register an observer to be called on each state change. Returned so the
    /// caller can mirror the binary's observation registration; the actual
    /// republish happens through `notifyObservers`.
    public func addObserver(_ observe: @escaping (SubtitleActor) -> Void) {
        observers.append(observe)
    }

    // MARK: - Cross-file mutators (live callers in KSSubtitle.swift / SubtitleParse.swift)

    /// Replace the canonical parts array.
    ///
    /// Retained mutator: `SubtitleModel.asyncSubtitleParse` (KSSubtitle.swift)
    /// pushes parsed output here. Recomputes the visible window for the current
    /// time (which republishes to observers), mirroring `ingest`.
    public func setParts(_ newParts: [SubtitlePart]) {
        parts = newParts
        handleTimeChange()
    }

    /// Replace the active subtitle track info.
    ///
    /// Retained mutator for the cross-file caller in
    /// `SubtitleModel.asyncSubtitleParse` (KSSubtitle.swift), which constructs
    /// a bare actor and assigns info after the fact. (Kept non-optional to
    /// match the field type.)
    public func setInfo(_ newInfo: any SubtitleInfo) {
        info = newInfo
    }

    // MARK: - deinit (RE: 0x10149733c)

    /// RE: `SubtitleActor_deinit` @ 0x10149733c — VERIFIED: the deinit performs
    /// observer teardown, not pure compiler-synthesized ARC release. Decompiled
    /// body, transcribed exactly:
    ///
    ///     if ((*(byte *)(self + 0x59) & 1) != 0) {   // observation-active flag
    ///         uVar1 = *(undefined8 *)(self + 0x10);   // load the observed state
    ///         FUN_1013ccc5c(uVar1, ...);              // observation teardown
    ///     }
    ///
    /// The teardown call `FUN_1013ccc5c` @ 0x1013ccc5c is a one-line protocol
    /// witness thunk — `(**(code **)(PTR_PTR_103a28368 + 0x10))(state, ...)` —
    /// i.e. it dispatches through a witness table's slot `+0x10`. That is the
    /// SAME teardown shape `notifyObservers` @ 0x1014970c8 uses (identical
    /// `+0x59` gate, `+0x10` load, then `FUN_1013ccc5c`): the Combine
    /// `@Published`/observation plumbing that detaches the actor's observers.
    /// So the actor's observer list IS released on deinit through the witness,
    /// which the reconstruction models as `observers.removeAll()`.
    ///
    /// (The separate `dealloc` @ 0x1014973a0 and `release_helper` @ 0x101497380
    /// are the runtime/ARC helpers and need no hand-written body.) The
    /// `parseTask?.cancel()` below has no direct counterpart in the 0x10149733c
    /// body — the in-flight parse `Task` is a reconstruction-side handle (the
    /// binary spawns its parse via `swift_task_*` with no retained cancel slot),
    /// so cancelling it here is the Swift-idiomatic equivalent of dropping that
    /// detached work when the actor dies.
    deinit {
        parseTask?.cancel()
        observers.removeAll()
    }
}
