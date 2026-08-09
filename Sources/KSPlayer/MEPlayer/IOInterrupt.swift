//
//  IOInterrupt.swift
//  KSPlayer
//
//  Binary-faithful reconstruction (Forward 1.3.17). Leaf IO-cancellation
//  primitives consumed later by AbstractAVIOContext / PreLoadIOContext.
//
//  Provenance:
//    - Fields are FAITHFUL — transcribed verbatim from the binary's
//      __swift5_fieldmd reflection metadata (names + types are the binary's own).
//    - IOInterruptContext.init reconstructed from FUN_101a391bc (designated init
//      body; vtable slot 0 = __allocating_init thunk @0x101a33658).
//    - The 3 private classes are vtable-devirtualized (null slot in descriptor):
//      no standalone init function exists; their construction is inlined into
//      IOInterruptContext.init / IOInterruptRegistry.register. They are declared
//      with the faithful fields + a minimal memberwise init, marked UNRESOLVED-slot.
//

import Foundation

/// Holds an interrupt callback used to abort blocking IO. Public surface
/// (mangled `_TtC8KSPlayer18IOInterruptContext`).
public final class IOInterruptContext {
    // FAITHFUL fields (binary reflection, alloc 0x30):
    public var flag: Bool                          // @ +0x10
    let block: (@Sendable () -> Bool)?      // 2-word closure @ +0x18 (fn) / +0x20 (ctx)
    // Field name/type are FAITHFUL. The ACCESS LEVEL is not binary-readable for any of the
    // three helper classes below — they are vtable-devirtualized (null descriptor slots), so
    // nothing in the image records `private` vs `internal`. It was previously `fileprivate`
    // purely to satisfy the compiler; it is now `internal`, for the same non-semantic reason in
    // the other direction: `openFormatContext` installs `interrupt.token.opaque` into
    // `AVFormatContext.interrupt_callback` and must be able to read it.
    let token: IOInterruptToken // @ +0x28

    /// ⚑[tool=disassemble ref=IOInterruptContext.interrupt.getter:0x101a34c08 result=24-instr]
    /// A short-circuit OR, read directly off the branch structure:
    ///   `ldrb w8,[x20,#0x10]` / `tbz w8,#0` — if `flag` is set, `mov w0,#1` and return;
    ///   `ldr x8,[x20,#0x18]` / `cbz x8` — if the closure's function word is null, `mov w0,#0`;
    ///   otherwise `ldr x20,[x20,#0x20]` for its context and `blr x8`, returning its result.
    /// The three offsets are the ones this class already annotates above — flag @+0x10 and the
    /// two-word closure @+0x18/+0x20 — so no offset had to be recovered for this member.
    /// The null test on the function word IS the `?.`; there is no force-unwrap, and the `mov
    /// w0,#0` arm is the `?? false`.
    /// Access read from its vpMV.
    public var interrupt: Bool {
        flag || (block?() ?? false)
    }

    /// Designated init — reconstructed from FUN_101a391bc (vtable slot 0).
    /// Allocating thunk @0x101a33658 calls this then balances ARC on the closure.
    init(_ block: (@Sendable () -> Bool)?) {
        self.flag = false                              // *(self+0x10) = 0
        let reg = IOInterruptRegistry.shared           // _swift_once → DAT_1044e9ac0
        reg.lock.lock()                                // objc_stub::lock(reg+0x10)
        let id = reg.nextID                            // id = *(reg+0x18)
        reg.nextID = id &+ 1                           // reg.nextID = id &+ 1 (wrapping)
        reg.lock.unlock()                              // objc_stub::unlock(reg+0x10)
        // token built inline @FUN_101a391bc: tok.id = id; tok.opaque = id (raw ptr).
        // body guards `if (id != 0)` before the opaque store → bitPattern!/non-nil is faithful.
        let token = IOInterruptToken(id: id, opaque: UnsafeMutableRawPointer(bitPattern: id)!)
        self.block = block                             // *(self+0x18)=fn, *(self+0x20)=ctx
        self.token = token                             // *(self+0x28) = tok
        reg.register(self, token: token)               // FUN_101a34a20 → contexts[id] = weak(self)
    }
}

/// Process-wide registry mapping interrupt ids to weak context references.
/// The binary discriminator `P33_AAD283AF…` says the ORIGINAL was file-private; this is declared
/// `internal` because the `@convention(c)` interrupt callback that FFmpeg calls must reach
/// `shared`, `lock` and `contexts`. Access level is not binary-readable here (see the note on
/// `IOInterruptContext.token`), so this is a spelling change, not a fidelity claim.
final class IOInterruptRegistry {
    // FAITHFUL fields (binary reflection, alloc ~0x28):
    let lock: NSLock                                   // @ +0x10
    var nextID: Int                                    // @ +0x18
    var contexts: [Int: WeakIOInterruptContext]        // @ +0x20

    /// Lazy singleton — `_swift_once(&DAT_1044e9ab8, FUN_101a349c4)`; instance
    /// stored at DAT_1044e9ac0. The binary's `_swift_once` is exactly the
    /// run-once-then-share-one-global pattern; mutable state inside is guarded by
    /// `self.lock` (as in the binary), so `nonisolated(unsafe)` is the faithful
    /// annotation here — not a new lock or actor.
    nonisolated(unsafe) static let shared = IOInterruptRegistry()

    // once-init FUN_101a349c4 (orchestrator-resolved from binary): RESOLVED.
    //   *(self+0x10)=NSLock()  *(self+0x18)=1  *(self+0x20)=_swiftEmptyDictionarySingleton
    // nextID starts at 1 (not 0): the binary uses id 0 as a trap sentinel — the
    // counter is 1-based so the first issued token id is 1.
    init() {
        self.lock = NSLock()
        self.nextID = 1
        self.contexts = [:]
    }

    /// Reconstructed from FUN_101a34a20: lock, build a weak holder for `context`,
    /// insert it under `token.id`, unlock.
    func register(_ context: IOInterruptContext, token: IOInterruptToken) {
        lock.lock()                                    // objc_stub::lock(reg+0x10)
        let id = token.id                              // id = *(token+0x10)
        let wc = WeakIOInterruptContext(context: context) // alloc + _swift_weakInit/Assign
        contexts[id] = wc                              // Dictionary subscript-set (FUN_1019c2264)
        lock.unlock()                                  // objc_stub::unlock
    }
}

/// Opaque interrupt-token handle.
/// `opaque` holds the id reinterpreted as a raw pointer (`*(tok+0x18) = id`).
/// `internal` rather than `private` for the reason given on `IOInterruptContext.token`.
final class IOInterruptToken {
    // FAITHFUL fields (binary reflection, alloc 0x20):
    let id: Int                                        // @ +0x10
    let opaque: UnsafeMutableRawPointer                // @ +0x18

    // memberwise — construction inlined @FUN_101a391bc; vtable slot devirtualized (UNRESOLVED in binary)
    init(id: Int, opaque: UnsafeMutableRawPointer) {
        self.id = id
        self.opaque = opaque
    }
}

/// Weak wrapper so the registry does not retain contexts.
/// `internal` rather than `private` for the reason given on `IOInterruptContext.token`.
final class WeakIOInterruptContext {
    // FAITHFUL field (binary reflection, alloc 0x18):
    weak var context: IOInterruptContext?              // @ +0x10

    // memberwise — construction inlined @FUN_101a34a20; vtable slot devirtualized (UNRESOLVED in binary)
    init(context: IOInterruptContext) {
        self.context = context
    }
}
