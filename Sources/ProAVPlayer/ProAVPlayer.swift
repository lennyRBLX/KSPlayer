//
//  ProAVPlayer.swift
//  ProAVPlayer
//
//  P3b M1 (structure) — Forward-new KSAVPlayer subclass that plays the locally-converted HLS via
//  AVFoundation. Field types resolved deterministically (field-record mangle + a known-answer control
//  for the Task Failure). Method bodies → M2.
//  Binary: desc=0x1039f52c4, superclass=KSAVPlayer (needs `open`), vtable=16, 1 impl body @slot15
//  (the AVPlayer-wrapper method per the module enumeration); rest devirt/inherited → M2.
//

import AVFoundation
import KSPlayer

/// The ProAVPlayer module's player: a KSAVPlayer subclass that plays the locally-served HLS conversion.
/// Forward-new (ProAVPlayer module).
/// P21 (vtable_anchor_diff, later·45): NON-final — the binary gives ProAVPlayer its OWN 16-slot vtable
/// (overrides + new methods on KSAVPlayer), which a `final` subclass would not emit (the SRC `final` gave
/// no own vtable). ⚑ EXACT-LAYOUT = tracked structural debt: matching the 16 own slots needs member-level
/// `final`/override reconstruction not yet done (same class as the LocalHLSServer residual).
class ProAVPlayer: KSAVPlayer, ConversionInfoDelegate {   // + ConversionInfoDelegate (binary conf@0x1035715a0); reqs → M2
    // 4 reflection fields (order = layout). Optionality from the mangle Sg.
    // task's Failure = Error PROVEN (known-answer control: KSAVPlayer.error `Error?` symref → the
    // same protocol descriptor 0x10536d100); Success = AVPlayerItem (So-mangle). Access level is not
    // binary-determined — `private` under-includes (P17); widen at M2 if a usage requires it.
    private var m3u8Info: ConversionInfo? = nil
    private var task: Task<AVPlayerItem, Error>? = nil
    private var hasEndOfStream: Bool = false

    /// `FUN_101b7c164`. Name RECOVERED (`recover_swift_function_name` high, 1 label; #file ProAVPlayer.swift;
    /// `param_1 & 1` ⇒ `needSeek: Bool`, P28-clean). ProAVPlayer's own vtable slot15. On `needSeek`: snapshot
    /// `player.currentTime` → `seekToTime` + advance the remuxer live-window `startPlayTime` by the last seekable
    /// range; then, on the main thread, rebuild the `ProPlayerItem` from the current asset and install it.
    /// Disasm-confirmed: needSeek block is `tbz w21,#0`-guarded (@0x101b7c260); `self.player` = KSAVPlayer's
    /// public accessor (FUN_1019a1730); the item-swap runs via `runOnMainThread` (FUN_101a03e88).  ⚑[tool=resolve_fun_pins ref=FUN_1019a1730:0x1019a1730 result=RESOLVES_UNIQUELY] = KSPlayer.KSAVPlayer.player.getter : __C.AVQueuePlayer  ⚑[tool=resolve_fun_pins ref=FUN_101a03e88:0x101a03e88 result=RESOLVES_UNIQUELY] = KSPlayer.runOnMainThread(block: @Swift.MainActor @Sendable () -> ()) -> ()
    func replaceCurrentItem(needSeek: Bool) {
        KSLog("", file: "ProAVPlayer/ProAVPlayer.swift", function: "replaceCurrentItem(needSeek:)", line: 303)
        if needSeek {                                                        // [tbz w21,#0 @0x101b7c260]
            seekToTime = player.currentTime()                               // self.player.currentTime() → seekToTime (CMTime?)
            if let firstRange = player.currentItem?.seekableTimeRanges.first?.timeRangeValue,   // element 0: ldr x8,[x20,#0x20]
               let m3u8Info {                                               // self.m3u8Info != nil
                // `.start` (vs .end/.duration) — DISASM-CONFIRMED: CMTimeRangeValue writes the range @sp+0x60,
                // get_seconds loads x0,x1=[sp+0x60]/x2=[sp+0x70] = the CMTime @offset 0 (.start; .duration = sp+0x78)
                m3u8Info.remuxerIOAction.startPlayTime =
                    (m3u8Info.remuxerIOAction.startPlayTime ?? 0) + firstRange.start.seconds  // *(remux+0x10); tag=0 (.some)
            }
        }
        runOnMainThread { [weak self] in                                    // FUN_101a03e88 = Utility.runOnMainThread; weak-self capture (0x1041e1198)  ⚑[tool=resolve_fun_pins ref=FUN_101a03e88:0x101a03e88 result=RESOLVES_UNIQUELY] = KSPlayer.runOnMainThread(block: @Swift.MainActor @Sendable () -> ()) -> ()
            guard let self,
                  let asset = player.currentItem?.asset as? AVURLAsset else { return }  // currentItem.asset as? AVURLAsset
            let item: ProPlayerItem
            if hasEndOfStream {                                             // self.hasEndOfStream
                item = ProPlayerItem(url: asset.url)                       // initWithURL: (inherited AVPlayerItem init)
                hasEndOfStream = false
            } else {
                item = ProPlayerItem(asset: asset)                        // initWithAsset:
            }
            item.m3u8Info = m3u8Info                                       // ProPlayerItem.m3u8Info = self.m3u8Info
            if let m3u8Info {                                             // [cbz x20 @0x101b7c640 — guard the ConversionInfo]
                // FUN_101b69fc4 = ConversionInfo.updateCurrentPlaybackTime (receiver x20=m3u8Info; arg d8 =
                // demuxerTime - (startPlayTime ?? 0) computed here @0x101b7c644-660). NOT a ProAVPlayer method.
                m3u8Info.updateCurrentPlaybackTime(m3u8Info.demuxerTime - (m3u8Info.remuxerIOAction.startPlayTime ?? 0))
            }
            player.automaticallyWaitsToMinimizeStalling = false
            (self as KSAVPlayer).replaceCurrentItem(playerItem: item)     // KSAVPlayer.replaceCurrentItem(playerItem:) — FUN_1019a563c (P34: private→internal). Upcast resolves the base-name shadow from the needSeek: overload (super-in-closure unsupported); ProAVPlayer doesn't override it ⇒ same dispatch as the binary.  ⚑[tool=resolve_fun_pins ref=FUN_1019a563c:0x1019a563c result=RESOLVES_UNIQUELY] = KSPlayer.KSAVPlayer.replaceCurrentItem(playerItem: __C.AVPlayerItem?) -> ()
        }
    }

    /// req0 witness `FUN_101b7cc78` = `FUN_101b7c164(0)` — refresh the current item without seeking.  ⚑[tool=resolve_fun_pins ref=FUN_101b7cc78:0x101b7cc78 result=RESOLVES_UNIQUELY] = ProAVPlayer.ProAVPlayer.reconstructComplete() -> ()
    func reconstructComplete() {
        replaceCurrentItem(needSeek: false)
    }
    private var seekToTime: CMTime? = nil

    // Adds no designated init + all 4 stored props defaulted ⇒ inherits KSAVPlayer's designated
    // `init(io:options:)` (Forward emits ProAVPlayer.init(io:options:) fC+fc, no init(url:)) and with it
    // the convenience `required init(url:options:)`. vtable=16; slot15 (replaceCurrentItem) reconstructed below.

    // MARK: createPlayerItem override @0x101b77704 (task body @0x101b77768…)

    /// Spawns a `[weak self]` MainActor Task. Its body converts `io.left` to local HLS through
    /// `ConversionToM3U8.shared.record` (@0x101b6c0bc), installs the ConversionInfo, and returns a
    /// `ProPlayerItem`. The Task is stored in `task` (reset() cancels through it) and awaited.
    /// Error literals verbatim: "ProAVPlayer deinit" (self gone) / "ProAVPlayer not url" (io is .right).
    override func createPlayerItem() async throws -> AVPlayerItem {
        let task = Task { @MainActor [weak self] () throws -> AVPlayerItem in
            guard let self else { throw KSPlayerError(code: 0, description: "ProAVPlayer deinit") }
            guard case let .left(url) = io else { throw KSPlayerError(code: 0, description: "ProAVPlayer not url") }
            options.context = "ProAVPlayer"
            let (localURL, m3u8Info) = try await ConversionToM3U8.shared.record(url: url, options: options)
            m3u8Info.delegate = self                                          // W4
            self.m3u8Info = m3u8Info
            fileSize = m3u8Info.remuxerIOAction.formatContext.fileSize        // W1
            chapters = m3u8Info.remuxerIOAction.formatContext.chapters()      // W2 (Forward: FUN_101a362d0 = FormatContext.chapters())
            subtitleTracks.append(contentsOf: m3u8Info.subtitles)             // W3
            let item = ProPlayerItem(url: localURL)
            item.m3u8Info = m3u8Info
            return item
        }
        self.task = task
        return try await task.value
    }
    override func readyToPlay() { fatalError("L7: ProAVPlayer.readyToPlay — Forward body unread") }
    override func nominalFrameRate(track: MediaPlayerTrack) -> Float { fatalError("L7: ProAVPlayer.nominalFrameRate — Forward body unread") }
    override var ioContext: AbstractAVIOContext? { fatalError("L7: ProAVPlayer.ioContext — Forward body unread") }
    override func play() { fatalError("L7: ProAVPlayer.play — Forward body unread") }
    override func process(error: Error) { fatalError("L7: ProAVPlayer.process — Forward body unread") }
    override func update(loadState: MediaLoadState, oldValue: MediaLoadState) { fatalError("L7: ProAVPlayer.update — Forward body unread") }
    override func changePlaybackTime(time: Double) { fatalError("L7: ProAVPlayer.changePlaybackTime — Forward body unread") }
    override func seek(time: Double, completion: @escaping @MainActor @Sendable (Bool) -> Void) { fatalError("L7: ProAVPlayer.seek — Forward body unread") }

    /// Forward `ProAVPlayer.reset` @ `0x101b7c6e4`; body and cleanup refs: `5cf964654b0ad471a415f6404bd514a97c30a397dffc0b7d65ddc40fa73cae6e`, `b43bbafa67d940027f9762caf377baafec4e7b0423910732f64792d97fa30fe2`.
    override func reset() {
        task?.cancel()
        if let m3u8Info {
            self.m3u8Info = nil
            Task { @MainActor in
                m3u8Info.server.keepAliveBlockMap.removeValue(forKey: m3u8Info.remuxerIOAction.dir.path)
                await m3u8Info.demuxerIO.send(.close)
            }
        }
        options.context = ""
        super.reset()
    }

    // MARK: slot15 @0x101b7c164 — replaceCurrentItem(needSeek:) (M2)

    // ── ConversionInfoDelegate conformance (binary conf@0x1035715a0, wt 0x1041e1340 → req0 101b7cc78 /
    //    req1 101b7cc80 / req2 101b7d3b4). ProAVPlayer receives the coordinator's lifecycle callbacks.
    //    Names inferred from ConversionInfo's forwards; behaviors reconstructed from the witness bodies.

    /// req1 witness `FUN_101b7cc80` — mark end-of-stream; if the un-drained lead  ⚑[tool=resolve_fun_pins ref=FUN_101b7cc80:0x101b7cc80 result=RESOLVES_UNIQUELY] = ProAVPlayer.ProAVPlayer.endOfStream() -> ()
    /// (`currentItem.duration - remuxerIOAction.startPlayTime`) exceeds `maxBufferDuration`, schedule the
    /// end-of-stream item work on the main actor.
    func endOfStream() {
        hasEndOfStream = true                                            // [*(self+hasEndOfStream)=1]
        guard let currentItem = player.currentItem else { return }       // [player=FUN_1019a1730; currentItem==0 -> return]  ⚑[tool=resolve_fun_pins ref=FUN_1019a1730:0x1019a1730 result=RESOLVES_UNIQUELY] = KSPlayer.KSAVPlayer.player.getter : __C.AVQueuePlayer
        if let m3u8Info {                                                // self.m3u8Info != nil
            if m3u8Info.maxBufferDuration < currentItem.duration.seconds - (m3u8Info.remuxerIOAction.startPlayTime ?? 0) {  // [+0x48 < duration.seconds - startPlayTime]
                Task { @MainActor in                                    // [true: MainActor Task; alloc 0x38 @0x1041e1328]
                    // body 7d66c → 7cedc → 7cf80 → 7d01c
                    try await Task.sleep(nanoseconds: 100_000_000)
                    let player = self.player
                    let currentTime = currentItem.currentTime()
                    _ = await player.seek(to: currentTime - CMTime(seconds: m3u8Info.remuxerIOAction.startPlayTime ?? 0, preferredTimescale: currentTime.timescale), toleranceBefore: .zero, toleranceAfter: .zero)
                }
            } else {                                                    // [false path — audit-caught: NOT omitted]
                runOnMainThread { [weak self] in                        // [false: runOnMainThread; weak-self ctx @0x1041e1198 + currentItem @0x1041e1300] body 7d628 → 7d2c0
                    guard let self else { return }
                    self.seekToTime = self.isReadyToPlay ? currentItem.currentTime() : CMTime.zero
                    self.player.replaceCurrentItem(with: nil)
                    self.player.replaceCurrentItem(with: currentItem)
                }
            }
        }
    }

    /// req2 witness `FUN_101b7d3b4` = a thunk to `KSAVPlayer.prepareToPlay()` (FUN_1019a9e20) — on conversion  ⚑[tool=resolve_fun_pins ref=FUN_101b7d3b4:0x101b7d3b4 result=RESOLVES_UNIQUELY] = ProAVPlayer.ProAVPlayer.failed(error: Swift.Error) -> ()  ⚑[tool=resolve_fun_pins ref=FUN_1019a9e20:0x1019a9e20 result=RESOLVES_UNIQUELY] = KSPlayer.KSAVPlayer.prepareToPlay() -> ()
    /// failure, re-prepare the player. `error` is received by the protocol req but unused (the witness thunk
    /// drops it; `prepareToPlay()` takes no args).
    @used final func failed(error: any Error) {
        prepareToPlay()
    }
}

//  P3b M1 (structure) — Forward-new AVPlayerItem subclass carrying the conversion info for the
//  locally-served HLS. Field type resolved deterministically (field-record mangle); superclass from
//  the descriptor mangle (So…AVPlayerItemC). Method bodies → M2.
//  Binary: desc=0x1039f5278, superclass=AVPlayerItem, vtable=3 (vtable-empty; slots devirtualized → M2).
/// The AVPlayerItem ProAVPlayer plays — carries the `ConversionInfo` describing the local HLS conversion.
/// Forward-new (ProAVPlayer module).
/// P21 (vtable_anchor_diff, later·45): NON-final — the binary gives ProPlayerItem its OWN 3-slot vtable
/// (overrides/new members on AVPlayerItem), which a `final` subclass would not emit (the SRC `final` gave
/// no own vtable). ⚑ EXACT-LAYOUT = tracked structural debt: matching the 3 own slots needs member-level
/// reconstruction not yet done (same class as the LocalHLSServer residual).
class ProPlayerItem: AVPlayerItem {
    // 1 reflection field. Optional (mangle Sg) — defaults nil ⇒ AVPlayerItem designated inits inherited
    // (no new designated init + the one new stored prop is defaulted). The real init → M2.
    var m3u8Info: ConversionInfo? = nil

    // vtable-empty (3 devirtualized slots — AVPlayerItem overrides/additions) → M2 via witness-table-
    // anchoring (the e651ff8 technique). Structure-only here (P15).
}

// ⚑[tool=member_add ref=KSOptions.localHLSServerPort:0x101b76e90 result=missing; mangled KSOptionsC11ProAVPlayerE — ProAVPlayer's extension, fwd_file ProAVPlayer.swift]
// Moved from KSPlayer's `public extension KSOptions`; defaults are the binary-read values of 44a57762.
extension KSOptions {
    nonisolated(unsafe) static var localHLSServerPort: UInt16 = 8887
    nonisolated(unsafe) static var maxM3U8FileSize: Int64 = 1_073_741_824
    nonisolated(unsafe) static var minM3U8BufferDuration: Int64 = 60
}
