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
//      ⚠️ s97: FALSE for slot 3. The orphaned export trie names it outright —
//      `$s8KSPlayer16DirectoryWatcherC10isWatchingSbvg` = DirectoryWatcher.isWatching.getter :
//      Swift.Bool, one symbol at 0x101a04e10, not folded. The blanket "no symbols" claim came from
//      a tool that cannot see that trie; re-check the other slots against it before trusting them.
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

    // MARK: idx3 slot15 @0x101a04e10 — isWatching (4 instr) · name RECOVERED, not inferred (s97)
    // ⚑[tool=export_trie_oracle ref=KSPlayer.DirectoryWatcher.isWatching:0x101a04e10 result=name-recovered]

    /// `true` while a source is installed. Binary: `return *(self+0x70) != 0`.
    public var isWatching: Bool {
        return source != nil
    }

    // MARK: slot 7 @0x101a06150 — stop (24 instr) · name inferred

    /// Cancels the installed source and clears it. Binary: if `source != nil`
    /// → retain, `OS_dispatch_source.cancel()`, release; then `source = nil`.
    // ⚑ s105 RENAME: was `stop()`, self-declared "name inferred". The trie names
    // 0x101a06150 `cancel()` and carries exactly ONE symbol there, and no `stop` symbol
    // exists on this class. Body unchanged — only the name was invented.
    // ⚑[tool=export_trie_oracle ref=DirectoryWatcher.cancel:0x101a06150 result=name-recovered]
    func cancel() {
        source?.cancel()                          // guarded cancel on the live source
        source = nil                              // *(self+0x70) = 0; release old
    }

    // MARK: slot 5 @0x101a04e78 — watchModify(fileURL:completion:) (379 instr) · name RECOVERED (s109)

    /// Watches `fileURL`'s own path.
    ///
    /// ⚑ s109 RENAME + RE-SIGNATURE. This was `startWatching(url:handler:qos:)`, self-declared
    /// "name inferred" with labels "inferred (no symbol)". The trie names 0x101a04e78
    /// `KSPlayer.DirectoryWatcher.watchModify(fileURL: Foundation.URL, completion: @Sendable (Swift.Bool) -> ())`
    /// — so the name, both labels, the completion's `Bool` parameter, and the ARITY were all wrong.
    /// The old third parameter `qos: DispatchQoS` did not exist: the note above admitted it came
    /// from decompiler `param_3`, but the demangled signature takes two parameters and the
    /// `DispatchQoS` in the body is the argument to `DispatchQueue.global(qos:)`, not an input.
    func watchModify(fileURL: URL, completion: @escaping @Sendable (Bool) -> Void) {
        // Tear down any existing source first (identical to stop()'s body —
        // binary inlines it at the top: cancel live source, then *(self+0x70)=0).
        source?.cancel()
        source = nil

        // open(fileURL.path.utf8CString, O_EVTONLY)  — 0x8000 == O_EVTONLY.
        let fd = fileURL.path.withCString { open($0, O_EVTONLY) }
        guard fd >= 0, source == nil else { return }     // (-1 < fd) && *(self+0x70)==0

        // queue = DispatchQueue.global(qos: .default)  (binary: global(QoSClass.default))
        let queue = DispatchQueue.global(qos: .default)
        // makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write,.delete], queue: queue)
        // eventMask = [.write, .delete]  (binary: _get_delete + _get_write → SetAlgebra.init)
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete], queue: queue
        )

        // setEventHandler — the block @0x101a06254 is an 18-instruction partial-apply forwarder
        // (it recomputes the URL's size/alignment off the value witness to locate the captures)
        // onto the real body @0x101a05464. That body is READ: NSFileManager `defaultManager`,
        // `URL.path.getter`, `String._bridgeToObjectiveC`, then `fileExistsAtPath:` — and its BOOL
        // result is passed straight to the completion (`mov x0, <result>` then `blr` the callback).
        // ⚑ UNRESOLVED: after the completion call the body builds a weak-self box and a 40-byte
        //   context and creates a Task through the shared specialization 0x101a03fd4
        //   (async function pointer 0x1035697f0). That trailing task is not reconstructed.
        // ⚑[tool=bind_oracle ref=_OBJC_CLASS_$_NSFileManager:0x104410520 result=Foundation]
        source.setEventHandler {
            completion(FileManager.default.fileExists(atPath: fileURL.path))
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

    // MARK: slot 6 @0x101a0578c — watchNew(fileURL:completion:) (434 instr) · name RECOVERED (s109)

    /// Watches the CONTAINER of `url` (its parent directory) — used to detect a
    /// not-yet-existing file appearing. Distinct vtable slot → a SECOND method.
    /// Same spine as `watchModify(fileURL:completion:)` but it derives the path
    /// via `url.deletingLastPathComponent().path` (keeping `lastPathComponent`)
    /// and the eventMask is `[.write]` ONLY (the decompile calls `_get_write`
    /// but NOT `_get_delete`, unlike slot 5).
    /// ⚑ s109 RENAME + RE-SIGNATURE, same as slot 5. The trie names 0x101a0578c
    /// `KSPlayer.DirectoryWatcher.watchNew(fileURL: Foundation.URL, completion: @Sendable (Swift.Bool) -> ())`.
    /// Name, labels, completion type and arity were all inferred and all wrong; there is no
    /// `qos:` parameter.
    func watchNew(fileURL: URL, completion: @escaping @Sendable (Bool) -> Void) {
        // Tear down any existing source first (inlined cancel + clear).
        source?.cancel()
        source = nil

        // lastPathComponent is captured (binary: get_lastPathComponent → SVar32,
        // retained across the call); the watched path is the parent directory.
        let lastPathComponent = fileURL.lastPathComponent
        let parent = fileURL.deletingLastPathComponent()   // URL.deletingLastPathComponent()

        // open(parent.path.utf8CString, O_EVTONLY)
        let fd = parent.path.withCString { open($0, O_EVTONLY) }
        guard fd >= 0, source == nil else { return }       // fd<0 → cleanup+return; else needs *(self+0x70)==0

        let queue = DispatchQueue.global(qos: .default)
        // eventMask = [.write]  (binary slot 6: only _get_write — no _get_delete)
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write], queue: queue
        )

        // setEventHandler — block @0x101a06364 forwards to the real body @0x101a05e54, which IS
        // read and differs from slot 5's in exactly one way that matters. It rebuilds the watched
        // file's path with `URL.appendingPathComponent` from the captured `lastPathComponent`,
        // runs the same NSFileManager `defaultManager` / `fileExistsAtPath:` check, and then
        // `cbz w20` — on NOT-exists it skips the callback entirely; only the exists path reaches
        // `mov w0, #1` and the `blr`. So this one fires ONLY when the file appears, and always
        // with `true`, where slot 5 passes the check's result through.
        // ⚑[tool=bind_oracle ref=Foundation.URL.appendingPathComponent:0x104109a70 result=appendingPathComponent]
        source.setEventHandler {
            if FileManager.default.fileExists(atPath: parent.appendingPathComponent(lastPathComponent).path) {
                completion(true)
            }
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
