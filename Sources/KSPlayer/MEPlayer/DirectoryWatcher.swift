//
//  DirectoryWatcher.swift
//  KSPlayer
//
//  Binary-faithful reconstruction (Forward 1.3.17, KSPlayer module).
//  Fires on HLS-segment directory changes; consumed later by HLSCacheIOContext.
//
//  Provenance / scope (honest 5-of-9 vtable coverage):
//    - `DirectoryWatcher` is a Swift `actor` — slot-4 init calls
//      `_swift_defaultActor_initialize()` (the executor-init the compiler
//      synthesizes for `actor`); we declare `actor` and do NOT emit that call
//      or the `$defaultActor` ivar ourselves.
//    - ONE real stored field: `source` @ +0x70 (binary __swift5_fieldmd, after
//      filtering the synthesized actor-executor ivar). Type taken from the
//      makeFileSystemObjectSource call in slots 5/6 (the binary wins; its
//      property descriptor is stripped → l2_field_gate marks it UNCHECKED).
//    - Slots 0–2 are `source`'s getter/setter/read accessors — SYNTHESIZED by
//      declaring the stored `var source`; nothing is written for them.
//    - Slots 3 (isWatching), 4 (init), 7 (stop) are small + fully reconstructed.
//    - Slots 5 & 6 are substantive (379 / 434 instr): the observable SPINE
//      (open → makeFileSystemObjectSource(eventMask:) → setEventHandler /
//      setCancelHandler → activate → store source) is reconstructed faithfully;
//      the event/cancel-handler CLOSURE INTERNALS are not cleanly recoverable
//      from the decompile and are left `// UNRESOLVED` with compiling stubs
//      (fabricating 379 instr of closure logic is the cardinal failure).
//    - All method NAMES are INFERRED — every slot is devirtualized (no symbols).
//    - Slot 8 is UNRESOLVED (null descriptor address) — declared as nothing.

import Dispatch
import Foundation

// UNRESOLVED slot 8 @descriptor 0x1039ee53c — devirtualized; follow-callees later.

/// Watches an HLS-segment directory (or a not-yet-existing file's container)
/// via a `DispatchSource` file-system-object source, firing a caller-supplied
/// handler on `.write` / `.delete` events.
///
/// `actor` (binary: init calls `_swift_defaultActor_initialize`). Mangled
/// `_TtC8KSPlayer16DirectoryWatcher`. Method names below are INFERRED — the
/// vtable is devirtualized so no symbol survives.
// P3b: `public` — the Forward-new ProAVPlayer module (a separate SPM target) references this type
// cross-module (RemuxerIOAction/ConversionInfo hold a `directoryWatcher: DirectoryWatcher` field;
// field-record symref → KSPlayer.DirectoryWatcher desc 0x1039ee53c). A separate target can only see a
// public type, so Forward made it public. Type-level public suffices (members stay internal until M2).
public actor DirectoryWatcher {
    // FAITHFUL field (binary __swift5_fieldmd @ +0x70). Built by
    // `DispatchSource.makeFileSystemObjectSource(...)` in slots 5/6, whose static
    // return type is `any DispatchSourceFileSystemObject` → declared as such.
    // (Accessors = vtable slots 0–2, synthesized by this stored `var`.)
    var source: DispatchSourceFileSystemObject?   // @ +0x70

    // MARK: slot 4 @0x101a04e20 — init() (14 instr)

    /// Parameter-less designated init. Body sets `source = nil` only; the
    /// `_swift_defaultActor_initialize()` the binary emits here is the
    /// compiler-synthesized actor executor setup — NOT written by hand.
    public init() {                              // public (was internal, P34): ConversionInfo (ProAVPlayer) constructs it cross-module
        source = nil                              // *(self+0x70) = 0
    }

    // MARK: slot 3 @0x101a04e10 — isWatching (4 instr) · name inferred

    /// `true` while a source is installed. Binary: `return *(self+0x70) != 0`.
    var isWatching: Bool {
        return source != nil
    }

    // MARK: slot 7 @0x101a06150 — stop (24 instr) · name inferred

    /// Cancels the installed source and clears it. Binary: if `source != nil`
    /// → retain, `OS_dispatch_source.cancel()`, release; then `source = nil`.
    func stop() {
        source?.cancel()                          // guarded cancel on the live source
        source = nil                              // *(self+0x70) = 0; release old
    }

    // MARK: slot 5 @0x101a04e78 — startWatching (self path) (379 instr) · name inferred

    /// Watches `url`'s own path. SPINE reconstructed faithfully; handler closure
    /// internals are UNRESOLVED (see below).
    ///
    /// Signature recovered from the decompile param types: `param_1` = `URL`,
    /// `param_2` = the event-handler callback (captured into the source's event
    /// closure), `param_3` = `DispatchQoS` (used for the source's global queue).
    /// Labels are inferred (no symbol).
    func startWatching(url: URL, handler: @escaping @Sendable () -> Void, qos: DispatchQoS) {
        // Tear down any existing source first (identical to stop()'s body —
        // binary inlines it at the top: cancel live source, then *(self+0x70)=0).
        source?.cancel()
        source = nil

        // open(url.path.utf8CString, O_EVTONLY)  — 0x8000 == O_EVTONLY.
        let fd = url.path.withCString { open($0, O_EVTONLY) }
        guard fd >= 0, source == nil else { return }     // (-1 < fd) && *(self+0x70)==0

        // queue = DispatchQueue.global(qos: .default)  (binary: global(QoSClass.default))
        let queue = DispatchQueue.global(qos: .default)
        // makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write,.delete], queue: queue)
        // eventMask = [.write, .delete]  (binary: _get_delete + _get_write → SetAlgebra.init)
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete], queue: queue
        )

        // setEventHandler { ... }  — binary builds a closure capturing weak self
        // (_swift_weakInit(..., self)), `url`, `handler` (param_2), `qos` (param_3)
        // and fd, then __Block_copy + _setEventHandler.
        // UNRESOLVED slot 5 event-handler body @0x101a06254/0x100004aec —
        // closure internals not faithfully recoverable; observable effect is the
        // captured `handler` being invoked on each fs event.
        source.setEventHandler {
            handler()   // stub: invoke the captured callback (faithful observable effect)
        }
        // setCancelHandler { ... }  — second closure (capturing handler/qos/fd),
        // __Block_copy + _setCancelHandler. Cancel handlers for an fs source
        // conventionally close(fd).
        // UNRESOLVED slot 5 cancel-handler body @0x101a063ec —
        // closure internals not faithfully recoverable.
        source.setCancelHandler {
            close(fd)   // stub: balance the opened descriptor on cancel
        }

        source.activate()                          // OS_dispatch_source.activate()
        self.source = source                       // *(self+0x70) = source; release old
    }

    // MARK: slot 6 @0x101a0578c — startWatching (parent dir) (434 instr) · name inferred

    /// Watches the CONTAINER of `url` (its parent directory) — used to detect a
    /// not-yet-existing file appearing. Distinct vtable slot → a SECOND method.
    /// Same spine as `startWatching(url:handler:qos:)` but it derives the path
    /// via `url.deletingLastPathComponent().path` (keeping `lastPathComponent`)
    /// and the eventMask is `[.write]` ONLY (the decompile calls `_get_write`
    /// but NOT `_get_delete`, unlike slot 5).
    func startWatchingParent(url: URL, handler: @escaping @Sendable () -> Void, qos: DispatchQoS) {
        // Tear down any existing source first (inlined cancel + clear).
        source?.cancel()
        source = nil

        // lastPathComponent is captured (binary: get_lastPathComponent → SVar32,
        // retained across the call); the watched path is the parent directory.
        _ = url.lastPathComponent
        let parent = url.deletingLastPathComponent()       // URL.deletingLastPathComponent()

        // open(parent.path.utf8CString, O_EVTONLY)
        let fd = parent.path.withCString { open($0, O_EVTONLY) }
        guard fd >= 0, source == nil else { return }       // fd<0 → cleanup+return; else needs *(self+0x70)==0

        let queue = DispatchQueue.global(qos: .default)
        // eventMask = [.write]  (binary slot 6: only _get_write — no _get_delete)
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write], queue: queue
        )

        // setEventHandler { ... } — closure captures weak self, parent URL,
        // lastPathComponent (SVar32), handler (param_2), qos (param_3), fd.
        // UNRESOLVED slot 6 event-handler body @0x101a06364/0x100004aec —
        // closure internals not faithfully recoverable; the captured
        // lastPathComponent is presumably matched against fs events before the
        // handler fires, but that logic is not cleanly recoverable.
        source.setEventHandler {
            handler()   // stub: invoke the captured callback (faithful observable effect)
        }
        // setCancelHandler { ... } — second closure (handler/qos/fd).
        // UNRESOLVED slot 6 cancel-handler body @0x101a063ec —
        // closure internals not faithfully recoverable.
        source.setCancelHandler {
            close(fd)   // stub: balance the opened descriptor on cancel
        }

        source.activate()                          // OS_dispatch_source.activate()
        self.source = source                       // *(self+0x70) = source; release old
    }
}
