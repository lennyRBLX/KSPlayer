//
//  LocalHLSServer.swift
//  ProAVPlayer
//
//  P3b M1 (structure) — Forward-new local HLS HTTP server. Field types resolved deterministically
//  (field-record + decode_composite + the init decompile); method bodies + the real init → M2.
//  Binary: desc=0x1039f5198, vtable=20 slots, 12 impl bodies (FUN_101b70274 init thunk → FUN_101b705ec).
//

import Foundation
import Network

/// Serves the locally-converted HLS (master M3U8 + segments) over HTTP so AVFoundation can play it.
/// Forward-new (ProAVPlayer module); self-contained (Network + Foundation only).
final class LocalHLSServer {
    // 7 reflection fields (order = layout). Types: field-record-concrete or decode_composite-resolved.
    private var port: UInt16                          // init(port:) param — binary init takes __uint16
    // ⚑ binary NON-optional (field-record mangle 02ed584d has no `Sg`; init stores it directly) — `!` (IUO)
    //   is the M1 placeholder-init stand-in; the real NWListener(using:on:) construction → M2.
    private var listener: NWListener!                 // Network framework
    // ⚑ UNRES inner → M2: decode_composite = [String:(UNRES)->()]. Keep-alive block per connection key;
    //   the closure's argument type is width-inferred from the connection handler in M2. Compile form drops the arg.
    private var keepAliveBlockMap: [String: () -> Void] = [:]
    private var rootDirectory: URL                    // served root (decompile: URL; init-set)
    private var queue: DispatchQueue                  // So:OS_dispatch_queue (init-created, the `::queue` field)
    private var statusMessages: [Int: String] = [:]   // field-record concrete [Int:String]
    // ⚑ UNRES inner → M2: decode_composite = [UNRES:UNRES]. Per-key retry delay; key+value width-inferred in M2.
    private var retryDelayMap: [String: Int] = [:]

    /// ⚑ M1 placeholder init — the real body (FUN_101b705ec) sets the Network/Dispatch scaffolding → M2.
    /// Binary signature is `init(port: UInt16)`. rootDirectory/queue values below are init-body details → M2.
    init(port: UInt16) {
        self.port = port
        self.listener = nil
        self.rootDirectory = FileManager.default.temporaryDirectory      // ⚑ init-set value → M2
        self.queue = DispatchQueue(label: "ProAVPlayer.LocalHLSServer")  // ⚑ init label → M2
    }

    // 20-slot vtable / 12 impl bodies (start / stop / accept-connection / serve-file / keep-alive / status)
    // → M2 (per-method pre-flight + body-audit). Structure-only here (P15).
}
