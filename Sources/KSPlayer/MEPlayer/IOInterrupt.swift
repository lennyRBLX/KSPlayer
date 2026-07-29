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
    // `fileprivate` required by Swift: this public class exposes a property whose
    // type (IOInterruptToken) is private. Field name/type are FAITHFUL; only the
    // access modifier is added to satisfy the compiler (no semantic change).
    fileprivate let token: IOInterruptToken // @ +0x28

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
/// Private (binary discriminator `P33_AAD283AF…`).
private final class IOInterruptRegistry {
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

/// Opaque interrupt-token handle. Private.
/// `opaque` holds the id reinterpreted as a raw pointer (`*(tok+0x18) = id`).
private final class IOInterruptToken {
    // FAITHFUL fields (binary reflection, alloc 0x20):
    let id: Int                                        // @ +0x10
    let opaque: UnsafeMutableRawPointer                // @ +0x18

    // memberwise — construction inlined @FUN_101a391bc; vtable slot devirtualized (UNRESOLVED in binary)
    init(id: Int, opaque: UnsafeMutableRawPointer) {
        self.id = id
        self.opaque = opaque
    }
}

/// Weak wrapper so the registry does not retain contexts. Private.
private final class WeakIOInterruptContext {
    // FAITHFUL field (binary reflection, alloc 0x18):
    weak var context: IOInterruptContext?              // @ +0x10

    // memberwise — construction inlined @FUN_101a34a20; vtable slot devirtualized (UNRESOLVED in binary)
    init(context: IOInterruptContext) {
        self.context = context
    }
}
