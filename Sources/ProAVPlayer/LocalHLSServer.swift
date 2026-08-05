//
//  LocalHLSServer.swift
//  ProAVPlayer
//
//  P3b M2 (bodies) — Forward-new local HLS HTTP server. init + startListen SPINE reconstructed
//  (FUN_101b705ec init, FUN_101b7138c=slot10 startListen); deeper serve/connection bodies → later commits.  ⚑[tool=resolve_fun_pins ref=FUN_101b705ec:0x101b705ec result=RESOLVES_UNIQUELY] = ProAVPlayer.LocalHLSServer.init(rootDirectory: Foundation.URL, port: Swift.UInt16) throws -> ProAVPlayer.LocalHLSServer
//  Binary: desc=0x1039f5198, vtable=20; accessors slots0/3/4/5 compiler-synthesized (no source).
//
//  M1→M2 CORRECTIONS (binary-confirmed): init was `init(port:)` — real is `init(rootDirectory:port:) throws`
//  (URL param copied into rootDirectory; NWListener init throws). listener was IUO nil — real is a
//  constructed non-optional NWListener. statusMessages/queue-label recovered from static data.
//

import CFNetwork
import Foundation
import KSPlayer
import Network

/// Serves the locally-converted HLS (master M3U8 + segments) over HTTP so AVFoundation can play it.
/// Forward-new (ProAVPlayer module); self-contained (Network + Foundation only).
/// P21 (vtable_anchor_diff, later·45): NON-final — the binary vtable (desc 0x1039f5198, 20 slots) carries
/// method + property-accessor slots, which Swift emits ONLY for a non-final class (a `final class` with no
/// superclass emits no method vtable slots; the SRC `final` gave vt=1). ⚑ EXACT-LAYOUT = tracked structural
/// debt (unrecoverable, NOT fabricated): the BIN's 20 < a plain non-final SRC's 34, so Forward marks ~5 stored
/// props + 2 methods `final` (a final member ⇒ no vtable slot; `private` does NOT trim — empirical), AND has a
/// COMPUTED property at slots 16-18 (a property-triple after 9 method slots — stored props follow field order,
/// so it can only be a late computed var; null-impl ⇒ unnameable/untyped, MISSING here). Which members are
/// `final` + prop_c's identity/type are not deterministically recoverable.
class LocalHLSServer {
    // 7 reflection fields (order = layout). Mutability kept `var` (M1 under-claim; l2 mutability partial).
    public let port: UInt16                          // init param; self+0x10 (__uint16)
    public var listener: NWListener                  // ⚑ was NWListener! IUO → non-optional (init-constructed, self+0x18)
    // ⚑ [String: (URL) -> Void] — value CORRECTED from M1's ()->Void: slot13 invokes the block with the
    // request's file URL (blr, x0 = fileURL; context in x20). Keep-alive block per directory-path key (self+0x20).
    public var keepAliveBlockMap: [String: (URL) -> Void] = [:]
    private let rootDirectory: URL                    // ⚑ init param (URL value-witness copy) — was temporaryDirectory (M1 bug)
    private let queue: DispatchQueue = DispatchQueue(label: "com.localhlsserver.queue")  // label @0x103d3df80
    // HTTP status table — 6 pairs recovered from the static dict literal (keys read as Int; values
    // 400/403/404 inline-confirmed, 405/500/503 length-matched to the standard messages).
    private let statusMessages: [Int: String] = [
        400: "Bad Request", 403: "Forbidden", 404: "Not Found",
        405: "Method Not Allowed", 500: "Internal Server Error", 503: "Service Unavailable",
    ]
    // ⚑ [URL: UInt64] — the KEY was CORRECTED from the M1 [String: Int] guess: slot19
    // (sendRetryResponse) hashes it via URL:Hashable (FUN_101b835bc → Hashable._rawHashValue on a URL).
    // Session 79 corrects the VALUE, which that pass never checked: the binary says UInt64, not Int.
    // ⚑[tool=export_trie_oracle ref=LocalHLSServer.retryDelayMap:$s11ProAVPlayer14LocalHLSServerC13retryDelayMap33_15C2A0C98D82F34B7E875A9CFB544E90LLSDy10Foundation3URLVs6UInt64VGvpfi result=CONFIRMED]
    //   demangles to `[Foundation.URL : Swift.UInt64]` — `s6UInt64V`, not `Si`.
    // NOT a spelling difference (MEMORY rule 51), three ways. (a) The same class mangles
    // `statusMessages` as `SDySiSSG` = [Swift.Int : Swift.String], so Int vs UInt64 is a distinction
    // this mangler makes inside this one class. (b) and (c) the BODY agrees, in sendRetryResponse
    // (0x101b740d4–0x101b74760, 419 instr by LC_FUNCTION_STARTS), where x26 IS the loaded value —
    // `ldr x26,[x8,x0,lsl #3]` @0x101b74288 is the subscript, `mov w26,#0x1` @0x101b742a8 the `?? 1`:
    //   (b) `cmp x26,#0x5` / `b.lo` @0x101b74294-98 is the `delay <= 4` test taken UNSIGNED; a
    //       `Swift.Int` emits the signed `b.lt`.
    //   (c) `ucvtf d0, x26` @0x101b744f0 converts it for `.now() + Double(delay)` — the UNSIGNED
    //       convert, where a `Swift.Int` emits `scvtf`.
    // Per-URL backoff delay.
    private var retryDelayMap: [URL: UInt64] = [:]

    /// Binary: FUN_101b705ec (init thunk FUN_101b70274 allocs + tail-calls this with the URL + port).  ⚑[tool=resolve_fun_pins ref=FUN_101b705ec:0x101b705ec result=RESOLVES_UNIQUELY] = ProAVPlayer.LocalHLSServer.init(rootDirectory: Foundation.URL, port: Swift.UInt16) throws -> ProAVPlayer.LocalHLSServer  ⚑[tool=resolve_fun_pins ref=FUN_101b70274:0x101b70274 result=RESOLVES_UNIQUELY] = ProAVPlayer.LocalHLSServer.__allocating_init(rootDirectory: Foundation.URL, port: Swift.UInt16) throws -> ProAVPlayer.LocalHLSServer
    /// vtable slot 6 @0x101b70274 is the compiler-emitted ALLOCATING entry point for this init and has no
    /// source of its own — whole body (20 instr, disasm): save x0/x1 → `ldr w1,[x20,#0x30]` /
    /// `ldrh w2,[x20,#0x34]` (instanceSize / alignMask off the metadata in x20) → `bl 0x10345caf0`
    /// (swift_allocObject) → restore x0 (URL), x1 (port) → `bl 0x101b705ec` → ret. It also round-trips the
    /// swifterror register (`mov x19,x21` on entry, `mov x21,x19` before the call), which is a SECOND,
    /// independent binary witness for `throws` here (the third is the error path's
    /// `_swift_willThrow` + `_swift_deallocPartialClassInstance` @0x101b70b0c).
    ///
    /// ⚑[tool=recover_swift_function_name.py ref=LocalHLSServer.init(rootDirectory:port:):0x101b705ec result=CONFIRMED]
    /// PARAM LABELS ARE RECOVERED, NOT INFERRED — this supersedes the earlier "labels inferred (stripped)"
    /// pin. The throw path materializes this init's own `#function` literal @0x103d3e3e0, count 25, whose
    /// bytes read exactly `init(rootDirectory:port:)`; the paired `#file` @0x103d3e3b0, count 32, reads
    /// `ProAVPlayer/LocalHLSServer.swift`, and the call passes line 0x2f = 47. 2 labels == the 2 argument
    /// registers the thunk reads → P28-clean.
    /// ARITY 2 is pinned by the ABI: the thunk reads only x0/x1 and leaves x2..x7 untouched, which also
    /// refutes a third DEFAULTED parameter — a default-argument generator runs at the CALL site and its
    /// value would still arrive in x2.
    ///
    /// ⚑ NO STATIC INSTANCE SIZE EXISTS FOR THIS CLASS — a binary fact, not a tool gap, and the reason
    /// `init_thunk_probe.py` reports `size=-` here while it reads a constant for every sibling. The thunk
    /// loads size/align from the metadata at runtime (`ldr w1,[x20,#0x30]`/`ldrh w2,[x20,#0x34]`) instead
    /// of the usual constant `mov w1,#<size>`, because `rootDirectory: URL` is a RESILIENT Foundation
    /// struct whose size is unknown at compile time: its metadata accessor @0x103452464 is
    /// `URL default typeMetadataAccessor`, and the argument arrives INDIRECTLY as a pointer that is copied
    /// in through the value witness `initializeWithCopy` (VWT+0x10) rather than by a plain store.
    /// Three further witnesses agree, so no number could be written here without fabricating it:
    ///   (a) only the fields BEFORE `rootDirectory` store at constant offsets — port self+0x10 (`strh`,
    ///       decompiled as `__uint16`), listener self+0x18, keepAliveBlockMap self+0x20 — while every
    ///       field from `rootDirectory` on indexes through a runtime FIELD-OFFSET global, and all four of
    ///       those globals read as ZERO in the file (they are filled in by swift_initClassMetadata at
    ///       load): 0x1044f2a78 queue · 0x1044f2a80 statusMessages · 0x1044f2b40 retryDelayMap ·
    ///       0x1044f2b48 rootDirectory. (Ghidra names all four `_TtC11ProAVPlayer14LocalHLSServer::<field>`,
    ///       which is an independent confirmation of that mapping.)
    ///   (b) the metadata comes from a SINGLETON accessor (FUN_101b75858) over a cache @0x1044f2b90 that  ⚑[tool=resolve_fun_pins ref=FUN_101b75858:0x101b75858 result=RESOLVES_UNIQUELY] = type metadata accessor for ProAVPlayer.LocalHLSServer
    ///       is likewise null in the file, keyed on descriptor 0x1039f5198.
    ///   (c) the error path re-reads +0x30/+0x34 off the LIVE metadata to size the partial dealloc.
    /// Field ORDER is still pinned (declaration order above); only the byte offsets of the last four
    /// fields are runtime-determined, and the instance size is not a constant in any build.
    ///
    /// ⚑ ORDER-ONLY (semantically inert, weak evidence): the binary stores `port` before `rootDirectory`.
    /// The four defaulted stored properties are emitted ahead of both, in declaration order, which shows
    /// this function did not have its initializing stores reordered — so the two explicit assignments are
    /// written in the observed order. Both are `let`, assigned once, with no interdependency; nothing but
    /// the store order distinguishes the alternatives.
    /// ⚠️ That is a PRESENTATION choice, not a recovery: under -O the optimiser may freely reorder two
    /// independent stores to distinct `let` fields, so the emitted order is NOT evidence of the order the
    /// source wrote them in. (This is exactly where user statements differ from DEFAULT materialization,
    /// which the compiler emits in declaration order in a fixed prologue — that IS probative, and is what
    /// the session-62 `packet` / `_timeIndexLock` findings rest on. Do not carry the inference across.)
    /// ⚑ a log-level-gated KSLog on the throw path (`1 < logLevel`, error bridged via
    /// `Foundation.__convertErrorToNSError`) is omitted — KSLog form UNRESOLVED, as elsewhere in the class.
    init(rootDirectory: URL, port: UInt16) throws {
        self.port = port
        self.rootDirectory = rootDirectory
        let params = NWParameters.tcp                            // Network::NWParameters::get_tcp
        params.allowLocalEndpointReuse = true                   // set_allowLocalEndpointReuse(true)
        self.listener = try NWListener(using: params,
                                       on: NWEndpoint.Port(rawValue: port)!)  // ⚑ Port(rawValue:) force-unwrap
        startListen()
    }

    /// Binary: FUN_101b7138c (vtable slot10). ⚑ name from the debug-log string "startListen()". Accepts
    /// each connection, drives it to `.ready`, receives the HTTP request, and dispatches it. The `[weak self]`
    /// captures in these `@Sendable` handlers are faithful to the binary (weakInit/weakLoadStrong); they
    /// compile because ProAVPlayer is built in Swift 5 language mode (Package.swift — Forward's own mode,
    /// since LocalHLSServer has no Sendable conformance). Per-state KSLog forms UNRESOLVED (as elsewhere).
    private func startListen() {
        listener.newConnectionHandler = { [weak self] connection in            // accept: FUN_101b71590
            guard let self else { return }
            connection.stateUpdateHandler = { [weak self] state in             // conn state: FUN_101b71644
                guard let self else { return }
                switch state {
                case .failed:
                    // ⚑ gated KSLog("startListen() … connection failed") omitted — KSLog form UNRESOLVED.
                    connection.cancel()
                case .ready:
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
                        [weak self] data, _, isComplete, error in              // receive: FUN_101b72150
                        guard let self else { return }
                        if error != nil {
                            // ⚑ gated KSLog("Connection failed: \(error)") omitted — KSLog form UNRESOLVED.
                            connection.cancel()
                            return
                        }
                        if let data {
                            self.processRequest(data: data, connection: connection)
                        }
                        if isComplete {   // peer closed the stream (EOF) → close the connection
                            connection.cancel()
                        }
                    }
                default:
                    break
                }
            }
            connection.start(queue: self.queue)
        }
        listener.stateUpdateHandler = { [weak self] state in                   // listener state: FUN_101b71958
            guard let self else { return }
            _ = state
            // ⚑ per-state gated KSLog (startListen() … .failed / .ready / .cancelled) omitted — KSLog form UNRESOLVED.
        }
        listener.start(queue: queue)
    }

    /// Binary: FUN_101b70b64 (vtable slot7) → outlined body FUN_101b753e8.  ⚑[tool=resolve_fun_pins ref=FUN_101b70b64:0x101b70b64 result=RESOLVES_UNIQUELY] = ProAVPlayer.LocalHLSServer.ping() -> ()
    /// ⚑ name UNRESOLVED — the ABI proves this method takes no params (disasm: x0..x7 unread on
    /// entry, self in x20), which rules out the only nearby name-string "probeListener(block:)"
    /// (@0x103d3e750, takes a `block:`) as this method's name; that string names the sibling
    /// keepAliveBlock installer, not this method (and get_xrefs_to that string = none). No clean
    /// #function anchor exists → the name below is a flagged SEMANTIC placeholder describing
    /// behaviour, not a recovered symbol.
    /// Probe the listener; when it's ready, open a keep-alive NWConnection to self (127.0.0.1:port)
    /// and start it, recreating the listener on any connection state change; when it isn't ready,
    /// recreate the listener immediately. `recreateListener` is the shared [weak self] rebuild closure
    /// (FUN_101b70bb0): it stands up a fresh NWListener bound to the same port (try? — the throw is
    /// swallowed), cancels the old one, and re-arms startListen() 0.01s later (FUN_101b70330).
    // ⚑ s106 RENAME `openKeepAliveConnection()` → `ping()`, and the name was never UNRESOLVED.
    //   The note above reasoned about the nearby string "probeListener(block:)", correctly ruled it
    //   out on ABI grounds, and concluded no name was recoverable — while the pin on the line
    //   directly above it already carried the answer:
    //     ⚑[tool=resolve_fun_pins ref=FUN_101b70b64:0x101b70b64 result=RESOLVES_UNIQUELY]
    //       = ProAVPlayer.LocalHLSServer.ping() -> ()
    //   A trie name is READ. The absence of a `#function` literal only means
    //   `recover_swift_function_name` has nothing to work with; it says nothing about the trie.
    //   Arity 0 and Void return already matched, so this is a rename, not a signature change, and
    //   there are no call sites.
    // ⚑ `private` DROPPED, also read: a private member carries a per-file discriminator in its
    //   mangled name, and this one demangles clean as `LocalHLSServer.ping() -> ()` with none. That
    //   rules out private. It does not prove public, so the declaration is left unmarked
    //   (internal) rather than promoted.
    //   ⚑[tool=export_trie_oracle ref=LocalHLSServer.ping:0x101b70b64 result=no-discriminator-not-private]
    func ping() {
        // Shared listener-rebuild — a [weak self] CLOSURE (binary FUN_101b70bb0 weak-loads self inside;
        // NOT a method — corrects the earlier "private recreateListener() method" plan). try? swallows the
        // NWListener throw (disasm: mov x21,#0; bl _init; cbz x21 @0x101b70cac → skip on error), then cancel
        // the old listener and re-arm startListen() after 0.01s (FUN_101b70330: NWListener.cancel + queue
        // .asyncAfter(.now()+0.01){startListen}; delay Double @0x103487958 = 0.01; strong-self block FUN_100004aec).
        let recreateListener: () -> Void = { [weak self] in
            guard let self else { return }
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            if let newListener = try? NWListener(using: params,
                                                 on: NWEndpoint.Port(rawValue: self.port)!) {  // Port! trap @0x101b70d3c
                let oldListener = self.listener
                self.listener = newListener
                oldListener.cancel()
                self.queue.asyncAfter(deadline: .now() + 0.01) { self.startListen() }
            }
        }
        if listener.state == .ready {
            let connection = NWConnection(
                to: .hostPort(host: "127.0.0.1",
                              port: NWEndpoint.Port(rawValue: port)!),  // ⚑ force-unwrap (binary ==1 trap)
                using: .tcp)
            // Keep-alive probe: any state change → recreate the listener. Binary forwards via a reabstraction
            // thunk (FUN_101b76230 = `mov x1,x20; b recreate`); recreate's (arg & 1)==0 guard is VESTIGIAL —
            // NWConnection.State is address-only (non-@frozen resilient) so the arg is a pointer (bit0=0) and
            // recreate never inspects the state (no getEnumTag/VWT; contrast the VWT-decoding sibling
            // FUN_101b71644). So: recreate on every callback, state ignored.
            connection.stateUpdateHandler = { _ in recreateListener() }
            connection.start(queue: queue)
        } else {
            // ⚑ KSLog("listener not ready …") omitted — KSLog form UNRESOLVED (as elsewhere in the class).
            recreateListener()   // force rebuild (binary: recreate called with flag 0 → (0&1)==0)
        }
    }

    /// Binary: FUN_101b70d3c (vtable slot8). ⚑ name from the debug-log string "stop()".  ⚑[tool=resolve_fun_pins ref=FUN_101b70d3c:0x101b70d3c result=RESOLVES_UNIQUELY] = ProAVPlayer.LocalHLSServer.stop() -> ()
    /// Cancels the listener and clears the retry / keep-alive maps.
    func stop() {
        listener.cancel()
        retryDelayMap = [:]
        keepAliveBlockMap = [:]
        // ⚑ trailing debug log ("stop HLS Server" / "stop()") omitted — KSLog form UNRESOLVED.
    }

    /// Binary: 0x101b70ed4 (vtable slot9), `throws`. ⚑ s105: the name is no longer inferred —
    /// the export trie names the address outright, one symbol, and the pin on this very line
    /// already recorded it. Renamed `url(for:local:)` -> `getURL(for:local:)`; the argument
    /// labels `for:` / `local:` were already right, so only the base name moves. No call
    /// sites in this module — the cross-class caller reaches it through the vtable.
    /// ⚑[tool=export_trie_oracle ref=LocalHLSServer.getURL:0x101b70ed4 result=name-recovered]  ⚑[tool=resolve_fun_pins ref=FUN_101b70ed4:0x101b70ed4 result=RESOLVES_UNIQUELY] = ProAVPlayer.LocalHLSServer.getURL(for: Foundation.URL, local: Swift.Bool) throws -> Foundation.URL
    /// Builds the local-server URL for a file in the HLS output directory:
    ///   http://<host>:<port>/<fileURL's path relative to rootDirectory>
    /// host = local ? "127.0.0.1" : (localIPAddress() ?? "127.0.0.1"). Throws Forward's
    /// `KSPlayerError` (descriptor 0x1039edbd4) on an invalid URL — the binary boxes {code = .unknown
    /// (0), message = "can not get url "} via `_swift_allocError`, matching `KSPlayerError(description:)`.
    /// ⚑ internal: a cross-class caller (FUN_101b69880) invokes it via the vtable; widen if needed.
    func getURL(for fileURL: URL, local: Bool) throws -> URL {
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

    /// Binary: FUN_1019f501c (slot9-private helper — new; not an existing KSPlayer URL ext). ⚑ names  ⚑[tool=resolve_fun_pins ref=FUN_1019f501c:0x1019f501c result=RESOLVES_UNIQUELY] = (extension in KSPlayer):Foundation.URL.relativePath(base: Foundation.URL) -> Swift.String
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

    /// Binary: FUN_101b740d4 (vtable slot19). Name RECOVERED (recover_swift_function_name.py: in-body
    /// `#function` "sendRetryResponse(connection:url:)" @0x103d3e400, count-34 length-verified; arity 2 =
    /// ABI). Reschedules a file-serve for `url` on `connection` with per-URL exponential backoff.
    /// ⚑ private: called only by slot13 (processRequest).
    private func sendRetryResponse(connection: NWConnection, url: URL) {
        let delay = retryDelayMap[url] ?? 1
        if delay <= 4 { retryDelayMap[url] = delay * 2 }   // exp backoff; >4 stops doubling (cap 8)
        // ⚑ gated KSLog omitted (the #file/#function source; KSLog form UNRESOLVED, as stop()/startListen()).
        queue.asyncAfter(deadline: .now() + Double(delay)) { [weak self] in
            // Serve `url` on `connection` once it's ready (FUN_101b75a84 -> FUN_101b74760). The block
            // captures [weak self] + connection + url + delay (`delay` = param_4, pinned via `ucvtf d0,x26`
            // + the retryDelayMap load in slot19; referenced only by the omitted gated KSLog). Compiles under .v5.
            guard let self, connection.state == .ready else {
                // ⚑ gated KSLog("…connection.state=\(connection.state) not ready…") omitted — KSLog form
                //   UNRESOLVED. self nil (cbz @0x101b74884) OR state != .ready (tbz @0x101b748ec) -> shared log.
                return
            }
            if let data = try? Data(contentsOf: url), !data.isEmpty {   // Data init 0x103452488 (x21 error-slot); !isEmpty @0x101b74a94
                self.sendFileResponse(connection: connection, data: data, contentType: self.contentType(for: url))  // 200 (FUN_101b75edc)
            } else {
                // ⚑ gated KSLog omitted — UNRESOLVED. Inline 503 (throw OR empty data). This completion
                //   CANCELS the connection (FUN_101b75064: cancel(param_2)) — contrast sendFileResponse keep-alive.
                //   Append order A -> contentType(url) -> B disasm-confirmed (grow/append @0x101b74efc-f54).
                var response = "HTTP/1.1 503 Service Unavailable\r\nContent-Type: "  // @0x103d3e470 count 48 (read_mem-verified)
                response.append(self.contentType(for: url))                         // FUN_101b73388(url)
                // ⚑ binary-faithful: literal B is 87 bytes (decompile count 0x57) ending "\r\n\r" — Forward's 503
                //   is MISSING the final "\n" of the header terminator; reproduced verbatim, NOT smoothed to \r\n\r\n.
                response.append("\r\nRetry-After: 1\r\nCache-Control: no-store\r\nConnection: keep-alive\r\nContent-Length: 0\r\n\r")
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    /// Binary: FUN_101b7248c (vtable slot13, 959i). Name RECOVERED (recover_swift_function_name.py:
    /// in-body `#function` "processRequest(data:connection:)" @0x103d3e6c0 count-32 length-verified;
    /// #file "ProAVPlayer/LocalHLSServer.swift"; 2 labels == ABI (disasm prologue: x0/x1=data, x2=connection,
    /// x20=self) → P28-clean). ⚑ private (get_xrefs_to 0x101b7248c = 1 code caller, FUN_101b72150 — inferred).
    ///
    /// The HTTP request dispatcher: parse the request → resolve the file within `rootDirectory` (path-traversal
    /// guarded) → serve it, ask the client to retry if it isn't ready, or reject it.
    ///
    /// SPINE (commit ①): the request-parse + dispatch decisions (400 malformed / 403 traversal / retry-when-
    /// absent-or-unreadable). The serve path + the .m3u8 freshness gate are a flagged DEFERRED region below →
    /// commit ② (serve FUN_101b75edc + content-type map FUN_101b73388 + the contentModificationDate staleness
    /// / keepAliveBlockMap invoke). Callees slot15/slot19 already FAITHFUL.
    private func processRequest(data: Data, connection: NWConnection) {
        // Parse the HTTP request bytes; a malformed request (no complete header / no request URL) → 400.
        guard let message = parseRequest(data),
              let requestURL = CFHTTPMessageCopyRequestURL(message)?.takeRetainedValue() as URL?
        else {
            sendErrorResponse(connection: connection, statusCode: 400, message: "Bad Request")
            return
        }
        // Map the request path (percent-decoded) into the served directory.
        let requestPath = requestURL.path.removingPercentEncoding ?? requestURL.path
        let fileURL = rootDirectory.appendingPathComponent(requestPath)
        // Path-traversal guard: the resolved file must stay under rootDirectory → else 403.
        // ⚑ prefix check on `.path` (binary: String.hasPrefix on the two URL paths).
        guard fileURL.path.hasPrefix(rootDirectory.path) else {
            sendErrorResponse(connection: connection, statusCode: 403, message: "Forbidden")
            return
        }
        // Not yet produced by the converter → tell the client to back off and retry.
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            sendRetryResponse(connection: connection, url: fileURL)
            return
        }
        // Read the file; an unreadable/empty file is also "not ready yet" → retry.
        // ⚑ empty-check is the faithful intent of the binary's Data-representation length test.
        guard let fileData = try? Data(contentsOf: fileURL), !fileData.isEmpty else {
            sendRetryResponse(connection: connection, url: fileURL)
            return
        }
        let mimeType = contentType(for: fileURL)
        // For an incomplete media playlist (.m3u8, not master.m3u8, not yet #EXT-X-ENDLIST-terminated):
        // reset the retry backoff (the file now exists), and when it is stale relative to its own
        // target-duration budget, nudge the directory's keep-alive block before serving. (Binary: the
        // .m3u8 branch of slot13; a compiler value-witness `initializeWithCopy` in this path is omitted
        // as non-source. Threshold comparison `threshold <= age` = fcmp d0,d8; b.ls.)
        if fileURL.pathExtension == "m3u8", fileURL.lastPathComponent != "master.m3u8" {
            retryDelayMap.removeValue(forKey: fileURL)            // FUN_101b7e1a0(op=1) = remove key
            if let content = String(data: fileData, encoding: .utf8),
               !content.hasSuffix("#EXT-X-ENDLIST\n") {
                if let modDate = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate {
                    let age = Date().timeIntervalSince1970 - modDate.timeIntervalSince1970
                    // Threshold = the playlist's #EXT-X-TARGETDURATION × 1.5 + 20s, else 26s.
                    let scanner = Scanner(string: content)
                    scanner.scanUpToString("#EXT-X-TARGETDURATION:")
                    let threshold = (scanner.scanString("#EXT-X-TARGETDURATION:") != nil
                                     ? scanner.scanDouble().map { $0 * 1.5 + 20.0 } : nil) ?? 26.0
                    if threshold <= age {
                        // ⚑ gated KSLog (level-gated; emits "…\(fileURL.lastPathComponent),diff=\(age)")
                        //   omitted — KSLog form UNRESOLVED (as elsewhere in the class).
                        keepAliveBlockMap[fileURL.deletingLastPathComponent().path]?(fileURL)
                    }
                }
            }
        }
        sendFileResponse(connection: connection, data: fileData, contentType: mimeType)
    }

    /// Binary: FUN_101b75aec (slot13 helper). ⚑ name inferred. Builds a CFHTTP request message from the
    /// received bytes (CFHTTPMessageCreateEmpty(isRequest: true) + append the Data via withUnsafeBytes),
    /// returning it once the header is complete. ⚑ the exact incomplete-header return path → own later unit.
    private func parseRequest(_ data: Data) -> CFHTTPMessage? {
        let message = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, true).takeRetainedValue()
        data.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                CFHTTPMessageAppendBytes(message, base.assumingMemoryBound(to: UInt8.self), data.count)
            }
        }
        return CFHTTPMessageIsHeaderComplete(message) ? message : nil
    }

    /// Binary: FUN_101b73388 (slot13 helper). ⚑ name inferred. Maps a file extension to the HTTP
    /// Content-Type used when serving it. Map extracted DETERMINISTICALLY by
    /// `scripts/decode_string_switch.py` (--selfcheck golden, P29) — NOT hand-read (an earlier manual
    /// read mis-partitioned the two catch-all strings; see later·40). `.m3u8`→the HLS playlist type;
    /// `key`→octet-stream; default→octet-stream. ⚑ m4a→audio/mp4 width-inferred (shared "…/mp4" tail).
    private func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "ts":                return "video/mp2t"
        case "mp4", "m4s", "m4v": return "video/mp4"
        case "m4a":               return "audio/mp4"
        case "aac":               return "audio/aac"
        case "vtt":               return "text/vtt"
        case "key":               return "application/octet-stream"
        case "m3u8":              return "application/vnd.apple.mpegurl"
        default:                  return "application/octet-stream"
        }
    }

    /// Binary: FUN_101b75edc (slot13 helper). ⚑ name inferred. Sends `data` as an HTTP/1.1 200 response
    /// on `connection` (Content-Type + `Cache-Control: no-store` + `Connection: keep-alive` +
    /// Content-Length, then the bytes as one payload). Keep-alive → the connection is NOT cancelled
    /// after the write (contrast sendErrorResponse). ⚑ completion (FUN_101b76190 → FUN_101b736e0): on a
    /// send error it KSLogs the error (bridged to NSError, log-level-gated — KSLog form UNRESOLVED); no cancel.
    private func sendFileResponse(connection: NWConnection, data: Data, contentType: String) {
        var response = "HTTP/1.1 200 OK\r\nContent-Type: "
        response.append(contentType)
        response.append("\r\nCache-Control: no-store\r\nConnection: keep-alive\r\nContent-Length: ")
        response.append("\(data.count)")
        response.append("\r\n\r\n")
        // ⚑ binary: response.data(using: .utf8) then Data.append(data) → one combined payload.
        var payload = Data(response.utf8)
        payload.append(data)
        connection.send(content: payload, completion: .contentProcessed { _ in })
    }

    // LocalHLSServer M2: all 8 vtable methods + every startListen/slot7/slot19 closure reconstructed.
    // Remaining M2 arbiter for this class = slot-ORDER faithfulness across all 20 slots → the P21
    // vtable_anchor_diff STRUCTURAL gate (build a ProAVPlayer classmap-builder → structural diff).
}
