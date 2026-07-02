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
import KSPlayer
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

    /// Binary: FUN_101b70ed4 (vtable slot9), `throws`. ⚑ name/param-labels inferred (stripped).
    /// Builds the local-server URL for a file in the HLS output directory:
    ///   http://<host>:<port>/<fileURL's path relative to rootDirectory>
    /// host = local ? "127.0.0.1" : (localIPAddress() ?? "127.0.0.1"). Throws Forward's
    /// `KSPlayerError` (descriptor 0x1039edbd4) on an invalid URL — the binary boxes {code = .unknown
    /// (0), message = "can not get url "} via `_swift_allocError`, matching `KSPlayerError(description:)`.
    /// ⚑ internal: a cross-class caller (FUN_101b69880) invokes it via the vtable; widen if needed.
    func url(for fileURL: URL, local: Bool) throws -> URL {
        let host = local ? "127.0.0.1" : (localIPAddress() ?? "127.0.0.1")
        let path = relativePath(from: rootDirectory, to: fileURL)
        guard let url = URL(string: "http://\(host):\(port)/\(path)") else {
            throw KSPlayerError(description: "can not get url ")
        }
        return url
    }

    /// Binary: FUN_101b71134 (slot9-private helper). ⚑ name inferred. The device's Wi-Fi (en0/en1)
    /// IPv4 address, or nil: getifaddrs → first AF_INET interface named "en0"/"en1" →
    /// getnameinfo(NI_NUMERICHOST). (en0/en1 are the "en0"/"en1" small-string literals in the binary.)
    private func localIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name == "en1" else { continue }
            var addr = interface.ifa_addr.pointee
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(&addr, socklen_t(addr.sa_len),
                        &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            return String(cString: hostname)
        }
        return nil
    }

    /// Binary: FUN_1019f501c (slot9-private helper — new; not an existing KSPlayer URL ext). ⚑ names
    /// inferred. `to`'s path relative to `from`: when they share scheme + host, drop the common leading
    /// standardized path components and join the remainder with "/"; otherwise `to.path`.
    private func relativePath(from: URL, to: URL) -> String {
        guard from.scheme == to.scheme, from.host == to.host else {
            return to.path
        }
        let fromComponents = from.standardized.pathComponents
        let toComponents = to.standardized.pathComponents
        var i = 0
        while i < fromComponents.count, i < toComponents.count, fromComponents[i] == toComponents[i] {
            i += 1
        }
        return toComponents[i...].joined(separator: "/")
    }

    /// Binary: FUN_101b7395c (vtable slot15). Name RECOVERED (deterministic — `recover_swift_function_name.py`):
    /// slot15 materializes a KSLog `#function` String literal of count 49 + a `#file` of count 32.
    /// Applying Swift's `_StringObject.nativeBias` (0x20) to the stored `_object` pointers yields the exact
    /// bytes — "sendErrorResponse(connection:statusCode:message:)" (@0x103d3e680) and
    /// "ProAVPlayer/LocalHLSServer.swift" (@0x103d3e3b0), each length-verified against its disasm count.
    /// The #function's arity (3 labels) matches the ABI (x0=NWConnection, x1=Int, x2/x3=String) → P28-clean.
    /// (Contrast slot7: the tool finds no #function literal → UNRESOLVED; "probeListener(block:)" is a
    /// slot13 literal, not slot7's name.)
    /// Writes a minimal HTML error page as an HTTP/1.1 response on the connection.
    /// ⚑ private: called only by slot13 (the request dispatcher).
    private func sendErrorResponse(connection: NWConnection, statusCode: Int, message: String) {
        let statusText = statusMessages[statusCode] ?? "Error"
        // ⚑ log-level-gated KSLog debug (the #file/#function source) omitted — KSLog form UNRESOLVED
        //   (consistent with stop()/startListen()).
        let body = "<html><body><h1>\(statusCode) \(statusText)</h1><p>\(message)</p></body></html>"
        // ⚑ Content-Length uses String.count (binary calls Swift.String.count on `body`); equals the
        //   UTF-8 byte count for this ASCII HTML.
        let response = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
            + "Content-Type: text/html\r\nConnection: close\r\nContent-Length: \(body.count)\r\n\r\n"
            + body
        // send(content:contentContext:isComplete:completion:). DISASM @0x101b73df0–e08 (self=x20=connection):
        //   x0/x1 = content (Data?)  ·  x2 = .defaultMessage  ·  w3 = isComplete = 1 (TRUE; byte 23008052
        //   = MOVZ w3,#1)  ·  x4 = completion. `.defaultMessage` and `isComplete: true` are both the API
        // defaults, so omitting them is equivalent (writing them explicitly emits the same call). content
        // is Optional → no force-unwrap.  [NB: the decompile mis-casts these args; the disasm is authoritative.]
        // Completion (FUN_101b761e8 → FUN_101b73e58): on a send error it KSLogs the error (bridged to
        // NSError, log-level-gated — omitted, KSLog form UNRESOLVED), then ALWAYS cancels the
        // connection (Connection: close — close after the response is written).
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // Remaining vtable methods (slots 13/19 — request-dispatch/serve-file + deferred) → later
    // LocalHLSServer commits (per-method pre-flight + body-audit). Slot-ORDER faithfulness across all
    // slots deferred to the P21 vtable_anchor_diff structural gate at LocalHLSServer M2-complete.
}
