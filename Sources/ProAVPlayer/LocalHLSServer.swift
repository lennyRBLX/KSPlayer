//
//  LocalHLSServer.swift
//  ProAVPlayer
//
//  P3b M2 (bodies) — Forward-new local HLS HTTP server. init + startListen SPINE reconstructed
//  (FUN_101b705ec init, FUN_101b7138c=slot10 startListen); deeper serve/connection bodies → later commits.
//  Binary: desc=0x1039f5198, vtable=20; accessors slots0/3/4/5 compiler-synthesized (no source).
//
//  M1→M2 CORRECTIONS (binary-confirmed): init was `init(port:)` — real is `init(rootDirectory:port:) throws`
//  (URL param copied into rootDirectory; NWListener init throws). listener was IUO nil — real is a
//  constructed non-optional NWListener. statusMessages/queue-label recovered from static data.
//

import Foundation
import Network

/// Serves the locally-converted HLS (master M3U8 + segments) over HTTP so AVFoundation can play it.
/// Forward-new (ProAVPlayer module); self-contained (Network + Foundation only).
final class LocalHLSServer {
    // 7 reflection fields (order = layout). Mutability kept `var` (M1 under-claim; l2 mutability partial).
    private var port: UInt16                          // init param; self+0x10 (__uint16)
    private var listener: NWListener                  // ⚑ was NWListener! IUO → non-optional (init-constructed, self+0x18)
    // ⚑ UNRES inner → later body: [String:(UNRES)->()]. Keep-alive block per connection key (self+0x20).
    private var keepAliveBlockMap: [String: () -> Void] = [:]
    private var rootDirectory: URL                    // ⚑ init param (URL value-witness copy) — was temporaryDirectory (M1 bug)
    private var queue: DispatchQueue = DispatchQueue(label: "com.localhlsserver.queue")  // label @0x103d3df80
    // HTTP status table — 6 pairs recovered from the static dict literal (keys read as Int; values
    // 400/403/404 inline-confirmed, 405/500/503 length-matched to the standard messages).
    private var statusMessages: [Int: String] = [
        400: "Bad Request", 403: "Forbidden", 404: "Not Found",
        405: "Method Not Allowed", 500: "Internal Server Error", 503: "Service Unavailable",
    ]
    // ⚑ UNRES inner → later body: [UNRES:UNRES]. Per-key retry delay (self, retryDelayMap field).
    private var retryDelayMap: [String: Int] = [:]

    /// Binary: FUN_101b705ec (init thunk FUN_101b70274 allocs + tail-calls this with the URL + port).
    /// ⚑ param labels inferred (stripped). URL param + `throws` are binary facts (URL value-witness copy
    /// into rootDirectory; NWListener(using:on:) throws → `_swift_willThrow`/`deallocPartialClassInstance`).
    init(rootDirectory: URL, port: UInt16) throws {
        self.rootDirectory = rootDirectory
        self.port = port
        let params = NWParameters.tcp                            // Network::NWParameters::get_tcp
        params.allowLocalEndpointReuse = true                   // set_allowLocalEndpointReuse(true)
        self.listener = try NWListener(using: params,
                                       on: NWEndpoint.Port(rawValue: port)!)  // ⚑ Port(rawValue:) force-unwrap
        startListen()
    }

    /// Binary: FUN_101b7138c (vtable slot10). ⚑ name from the trailing debug-log string "startListen()".
    /// SPINE reconstructed (wire both handlers + start on the queue); the handler closure BODIES
    /// (connection accept/serve + listener-state handling) are UNRESOLVED → next LocalHLSServer commit.
    private func startListen() {
        listener.newConnectionHandler = { connection in
            _ = connection   // UNRESOLVED → next commit: accept + serve HLS. ⚑ binary captures [weak self]
        }                    //   (deferred: strict-concurrency rejects weak-self in this @Sendable handler
        listener.stateUpdateHandler = { state in            //   for a non-Sendable class; no binary Sendable conf)
            _ = state        // UNRESOLVED → next commit: listener state handling. ⚑ binary captures [weak self]
        }
        listener.start(queue: queue)
        // ⚑ trailing debug log ("startListen()") omitted — KSLog form UNRESOLVED.
    }

    /// Binary: FUN_101b70b64 (vtable slot7) → outlined body FUN_101b753e8.
    /// ⚑ name UNRESOLVED — the ABI proves this method takes no params (disasm: x0..x7 unread on
    /// entry, self in x20), which rules out the only nearby name-string "probeListener(block:)"
    /// (@0x103d3e750, takes a `block:`) as this method's name; that string names the sibling
    /// keepAliveBlock installer, not this method (and get_xrefs_to that string = none). No clean
    /// #function anchor exists → the name below is a flagged SEMANTIC placeholder describing
    /// behaviour, not a recovered symbol.
    /// SPINE: probe the listener; when ready, open a keep-alive NWConnection to self
    /// (127.0.0.1:port) and start it. Deferred → next commit (strict-concurrency block; no binary
    /// Sendable conf): the [weak self] stateUpdateHandler closure (FUN_101b76230 → FUN_101b70bb0
    /// retry/recreate-listener) + the "listener not ready" debug log.
    private func openKeepAliveConnection() {   // ⚑ semantic placeholder name (UNRESOLVED)
        if listener.state == .ready {
            let connection = NWConnection(
                to: .hostPort(host: "127.0.0.1",
                              port: NWEndpoint.Port(rawValue: port)!),  // ⚑ force-unwrap (binary ==1 trap)
                using: .tcp)
            connection.stateUpdateHandler = { state in
                _ = state   // UNRESOLVED → next commit: [weak self] retry (FUN_101b76230 → FUN_101b70bb0)
            }
            connection.start(queue: queue)
        } else {
            // UNRESOLVED → next commit: KSLog("listener not ready … keepAliveBlock url=…")
            //   + retry/recreate listener (FUN_101b70bb0, [weak self] guard → self.listener = NWListener(…))
        }
    }

    /// Binary: FUN_101b70d3c (vtable slot8). ⚑ name from the debug-log string "stop()".
    /// Cancels the listener and clears the retry / keep-alive maps.
    func stop() {
        listener.cancel()
        retryDelayMap = [:]
        keepAliveBlockMap = [:]
        // ⚑ trailing debug log ("stop HLS Server" / "stop()") omitted — KSLog form UNRESOLVED.
    }

    // Remaining vtable methods (slots 9/13/15/19 — serve-URL [FUN_101b70ed4]/serve-file/status) →
    // later LocalHLSServer commits (per-method pre-flight + body-audit).
}
