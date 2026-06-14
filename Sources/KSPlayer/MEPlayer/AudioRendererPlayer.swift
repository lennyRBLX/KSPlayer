//
//  AudioRendererPlayer.swift
//  KSPlayer
//
//  Created by kintan on 2022/12/2.
//

import AVFoundation
import Foundation

public class AudioRendererPlayer: AudioOutput {
    /// Stored playback rate. Forward binary places this at field offset `+0x18`
    /// (Float, init `1.0f`). Read by the render callback and by `flushAndReset`
    /// when re-arming `setRate:time:` after a flush.
    public var playbackRate: Float = 1 {
        didSet {
            if !isPaused {
                // AudioRendererPlayer's own setRate vtable slot at Forward
                // `0x1013f74ac` is unclamped — `[*(self+0x60) setRate:]`
                // forwarded straight from the float register. The clamped
                // setter at `0x1013f1138` belongs to AudioEnginePlayer
                // (sets `timePitch.rate`), not this class.
                // `AVSampleBufferRenderSynchronizer` enforces its own range.
                renderSynchronizer.rate = playbackRate
            }
        }
    }

    public var volume: Float {
        get {
            renderer.volume
        }
        set {
            renderer.volume = newValue
        }
    }

    public var isMuted: Bool {
        get {
            renderer.isMuted
        }
        set {
            renderer.isMuted = newValue
        }
    }

    // MARK: - Forward additions (RE/66 + Ghidra v1.3.15 field audit)

    /// Output latency for A/V sync calibration. Forward field at `+0x10` (Double, init 0).
    public var outputLatency: Double = 0.0

    /// Reset-pending flag at Forward field `+0x50` (Bool, init `1`).
    ///
    /// Initialized true at construction so the very first render callback must
    /// pull a frame to clear it. Set true again by `flush()`, `flush(seekTime:)`,
    /// `flushAndReset()`, and `stopAndCleanup()`. Cleared by the request loop
    /// when a sample buffer is successfully enqueued (matches the binary
    /// render callback at `0x1013f7280` clearing `*(self+0x50) = 0` after a
    /// frame pull).
    private var needsReset: Bool = true

    /// `seekCMtime: CMTime?` — Forward inline storage at `+0x70..+0x88`.
    ///
    /// Binary layout (verified via disassembly of `AudioRendererPlayer_init`
    /// and the render callback at `0x1013f7280`):
    /// - `+0x70` (Int64): `CMTime.value`
    /// - `+0x78` (Int32+UInt32 packed): `CMTime.timescale | (flags << 32)`
    /// - `+0x80` (Int64): `CMTime.epoch`
    /// - `+0x88` (1 byte): Swift `Optional<CMTime>` discriminator
    ///   (`1` = `.none`, `0` = `.some`).
    ///
    /// The render callback writes the next frame's presentation CMTime into
    /// `+0x70..+0x87` and clears the tag at `+0x88` to mark `.some`. Init
    /// sets the tag to `1` (`.none`). Earlier RE notes that postulated a
    /// separate `flushTime` Bool at `+0x88` were conflating the same
    /// 25-byte Optional storage.
    private var seekCMtime: CMTime?

    public weak var renderSource: OutputRenderSourceDelegate?

    /// Periodic time observer at Forward field `+0x30`. Strong (not weak) — the
    /// binary uses `swift_beginAccess` on this offset, not weak load/store.
    private var periodicTimeObserver: Any?

    /// Audio renderer at Forward field `+0x58`.
    private let renderer = AVSampleBufferAudioRenderer()

    /// Render synchronizer at Forward field `+0x60`. Always allocated at
    /// construction (the binary unconditionally stores an
    /// `AVSampleBufferRenderSynchronizer` here), so the backing storage is
    /// non-optional. The protocol-facing `synchronizer` witness below republishes
    /// it as `AVSampleBufferRenderSynchronizer?`.
    private let renderSynchronizer = AVSampleBufferRenderSynchronizer()

    /// `AudioOutput.synchronizer` protocol witness.
    ///
    /// The protocol requirement is `var synchronizer: AVSampleBufferRenderSynchronizer? { get }`
    /// (optional, because non-Atmos backends — AudioEnginePlayer/AudioGraphPlayer/
    /// AudioUnitPlayer — have no synchronizer and fall through to the extension
    /// default that returns nil). A non-optional stored `let` of type
    /// `AVSampleBufferRenderSynchronizer` does NOT satisfy an optional `T?` get
    /// requirement in Swift, so without this explicit witness the compiler would
    /// silently bind `AudioOutput.synchronizer` to the nil-returning extension
    /// default — making `KSMEPlayer.renderSynchronizer` (and the subtitle time
    /// observer in KSPlayerLayer that depends on it) return nil on the Atmos /
    /// spatial AudioRendererPlayer path. Exposing the real instance through this
    /// optional computed property repairs the witness binding while keeping all
    /// internal uses non-optional.
    public var synchronizer: AVSampleBufferRenderSynchronizer? { renderSynchronizer }

    /// Request queue at Forward field `+0x68`. Label exactly matches the binary
    /// literal at `0x80000001033312d0` (36 bytes).
    ///
    /// RE: 0x1013f768c (push-loop dispatch). The Forward push loop is registered
    /// through `requestMediaDataWhenReadyOnQueue:` on this queue and reached via
    /// a 2-tier trampoline: tier-0 `FUN_1013f7134` (bare tail-call) → tier-1
    /// `FUN_1013f70e0`, which `swift_beginAccess(owner+0x10)` +
    /// `swift_weakLoadStrong` the AudioRendererPlayer and tail-calls the body
    /// only if non-nil. The `[weak self]` block installed by `play()` via
    /// `requestMediaDataWhenReady(on:)` is the idiomatic equivalent of that
    /// tier-1 weak load.
    private let requestQueue = DispatchQueue(label: "KSPlayer-AudioRendererPlayer-request")

    /// Cached audio format from the most recent `prepare(audioFormat:)` call.
    /// Used by `play()` to size the periodic observer interval — the Forward
    /// binary derives the CMTime value from the audio format's sample-rate path
    /// inside `AudioRendererPlayer_play` (`0x1013f6afc`).
    private var preparedAudioFormat: AVAudioFormat?

    var isPaused: Bool {
        renderSynchronizer.rate == 0
    }

    public required init() {
        // Order matches Forward `AudioRendererPlayer_init` @ `0x1013f67e4`:
        //   alloc renderer (already done via property init)
        //   alloc synchronizer (already done via property init)
        //   build requestQueue (already done via property init)
        //   addRenderer
        //   setDelaysRateChangeUntilHasSufficientMediaData:NO
        //   setAllowedAudioSpatializationFormats:.monoStereoAndMultichannel (7)
        renderSynchronizer.addRenderer(renderer)
        if #available(macOS 11.3, iOS 14.5, tvOS 14.5, *) {
            renderSynchronizer.delaysRateChangeUntilHasSufficientMediaData = false
        }
        if #available(tvOS 15.0, iOS 15.0, macOS 12.0, *) {
            renderer.allowedAudioSpatializationFormats = .monoStereoAndMultichannel
        }
    }

    public func prepare(audioFormat: AVAudioFormat) {
        preparedAudioFormat = audioFormat
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setPreferredOutputNumberOfChannels(Int(audioFormat.channelCount))
        KSLog("[audio] set preferredOutputNumberOfChannels: \(audioFormat.channelCount)")
        #endif
    }

    public func play() {
        // Forward `AudioRendererPlayer_play` (`0x1013f6afc`) also sets the
        // preferred sample rate on the shared `AVAudioSession`. The previous
        // observer (if any) is detached before re-installing a new one.
        #if !os(macOS)
        if let preparedAudioFormat {
            try? AVAudioSession.sharedInstance().setPreferredSampleRate(preparedAudioFormat.sampleRate)
        }
        #endif

        let time: CMTime
        if let seekTarget = seekCMtime {
            time = seekTarget
            seekCMtime = nil
        } else if #available(macOS 11.3, iOS 14.5, tvOS 14.5, *) {
            if renderer.hasSufficientMediaDataForReliablePlaybackStart {
                time = renderSynchronizer.currentTime()
            } else {
                if let currentRender = renderSource?.getAudioOutputRender() {
                    time = currentRender.cmtime
                } else {
                    time = .zero
                }
            }
        } else {
            if let currentRender = renderSource?.getAudioOutputRender() {
                time = currentRender.cmtime
            } else {
                time = .zero
            }
        }
        renderSynchronizer.setRate(playbackRate, time: time)
        renderSource?.setAudio(time: time, position: -1)
        renderer.requestMediaDataWhenReady(on: requestQueue) { [weak self] in
            guard let self else {
                return
            }
            self.request()
        }

        // Detach existing observer first (matches `removeTimeObserver:` in the
        // Forward play body before re-installing).
        if let periodicTimeObserver {
            renderSynchronizer.removeTimeObserver(periodicTimeObserver)
            self.periodicTimeObserver = nil
        }

        // Forward `AudioRendererPlayer_play` (`0x1013f6afc`) builds the CMTime
        // as `CMTime(value: 100, timescale: Int32(audioFormat.sampleRate))`
        // (disassembly at `0x1013f6f50..0x1013f6f58`):
        //
        //     fcvtzs w1, d0   ; timescale = (Int32)sampleRate
        //     mov    w0, #0x64 ; value = 100
        //     bl     CMTime.init(value:timescale:)
        //
        // Interval = 100 / sampleRate seconds (≈ 2.08 ms at 48 kHz).
        let sampleRateInt32: Int32 = {
            if let sampleRate = preparedAudioFormat?.sampleRate, sampleRate.isFinite, sampleRate > 0 {
                return Int32(sampleRate)
            }
            return 48000
        }()
        let observerInterval = CMTime(value: 100, timescale: sampleRateInt32)
        periodicTimeObserver = renderSynchronizer.addPeriodicTimeObserver(forInterval: observerInterval, queue: .main) { [weak self] time in
            guard let self else {
                return
            }
            self.renderSource?.setAudio(time: time, position: -1)
        }
    }

    public func pause() {
        renderSynchronizer.rate = 0
        renderer.stopRequestingMediaData()
        if let periodicTimeObserver {
            renderSynchronizer.removeTimeObserver(periodicTimeObserver)
            self.periodicTimeObserver = nil
        }
    }

    /// Vtable-slot-6 flush at Forward `0x1013f74c0`:
    ///   `[renderer flush]; *(self+0x50) = 1`
    public func flush() {
        renderer.flush()
        needsReset = true
        seekCMtime = nil
    }

    /// `AudioRendererPlayer_flushAndReset` at Forward `0x1013f74e8`:
    ///   `[renderer flush]; needsReset = 1; [synchronizer setRate:self.playbackRate time:kCMTimeZero]`
    ///
    /// Note: the rate argument is the stored `playbackRate` field (Forward
    /// `+0x18`), not literal `0.0`. The CMTime argument is `kCMTimeZero`.
    public func flushAndReset() {
        renderer.flush()
        needsReset = true
        renderSynchronizer.setRate(playbackRate, time: .zero)
    }

    /// Seek-aware flush: stores target time for synchronized resume.
    /// Populates `seekCMtime` (Forward `+0x70..+0x88` inline Optional<CMTime>).
    public func flush(seekTime: CMTime) {
        renderer.flush()
        needsReset = true
        renderSynchronizer.setRate(playbackRate, time: .zero)
        seekCMtime = seekTime
    }

    /// `AudioRendererPlayer_stopAndCleanup` at Forward `0x1013f7570`:
    ///   stopRequestingMediaData, flush, needsReset = 1, removeTimeObserver, setRate:0
    public func stopAndCleanup() {
        renderer.stopRequestingMediaData()
        renderer.flush()
        needsReset = true
        if let periodicTimeObserver {
            renderSynchronizer.removeTimeObserver(periodicTimeObserver)
            self.periodicTimeObserver = nil
        }
        renderSynchronizer.rate = 0
    }

    /// RE: 0x1013f768c (AudioRendererPlayer push-loop body, 1.3.15)
    ///
    /// The producer half of the CMSampleBuffer PUSH path — the single code
    /// caller of `AudioFrame.mergeFramesFromArray` and
    /// `AudioFrame.createCMSampleBuffer`. Dispatched via
    /// `requestMediaDataWhenReadyOnQueue:` through a 2-tier weak-load
    /// trampoline (Forward `FUN_1013f7134` → `FUN_1013f70e0`), modelled here by
    /// the `[weak self]` block installed in `play()`.
    ///
    /// Disassembly-verified control flow (`0x1013f768c–0x1013f7d6f`):
    ///   1. Rate guard: bail if `synchronizer.rate == 0` (no work when paused).
    ///   2. renderSource weak-load + frame-witness guard (the `guard let`
    ///      pulls below).
    ///   3. Batch count: `(sampleRate / perBufferSampleCount) * 0.125 *
    ///      max(1.0, playbackRate)` — a 0.125 s (≈125 ms) window scaled by rate.
    ///      Single-frame fast-path when count < 2.
    ///   4. Merge ≥2 frames; build CMSampleBuffer.
    ///   5. Time-pitch algorithm: spectral iff channelCount > 2 else timeDomain.
    ///   6. AVAudioSession negotiation of BOTH preferredOutputNumberOfChannels
    ///      AND preferredSampleRate against the merged frame.
    ///   7. Enqueue; backpressure gate on `isReadyForMoreMediaData`.
    ///   8. Producer self-throttle: keep ≲ `2.2 × playbackRate` seconds buffered.
    private func request() {
        // Step 1 — rate guard. Equivalent to the binary's `s0 = [synchronizer
        // rate]; if rate == 0 return`. Combined with the backpressure tail (the
        // loop re-enters only while the renderer wants more data) this models
        // the binary's single-pass body that the dispatch source re-invokes.
        while renderer.isReadyForMoreMediaData, !isPaused {
            // Step 2 — weak renderSource + frame-witness pull. nil → stop.
            guard var render = renderSource?.getAudioOutputRender() else {
                break
            }
            var array = [render]

            // Step 3 — batch count. Forward `0x1013f7784–0x1013f781c`:
            //   d8 = format.sampleRate
            //   d9 = renderSource+0x48 (per-buffer sample count, UInt32)
            //   fVar = max(1.0, playbackRate)   (self+0x18, `fcsel ...,ls`)
            //   count = (sampleRate / sampleCount) * 0.125 * fVar
            // The `0.125` multiplier is `0x3fc0000000000000` at disasm
            // `0x1013f780c` (= 1/8 ⇒ a 125 ms media window). `frameDurConst`
            // in earlier RE notes was a decompiler alias for `format.sampleRate`
            // (the `q0` const stored at array+0x10 is the array's frame-duration
            // metadata, NOT the dividend — disasm `fdiv d1,d8,d1` uses d8 =
            // sampleRate). count < 2 ⇒ single-frame fast-path (skip collect).
            let rateScale = Double(max(1.0, playbackRate))
            let perBufferSampleCount = Double(render.numberOfSamples)
            let rawCount: Double = perBufferSampleCount > 0
                ? (render.audioFormat.sampleRate / perBufferSampleCount) * 0.125 * rateScale
                : 0
            let batchCount = Int32(rawCount)
            if batchCount > 1 {
                // Step 4 (collect) — the binary pre-grows to max(req, 2·count)
                // via COW; appending to a Swift Array reproduces the COW growth.
                for _ in 1 ..< batchCount {
                    if let next = renderSource?.getAudioOutputRender() {
                        array.append(next)
                    }
                }
            }
            if array.count > 1 {
                // Step 4 (merge) — Forward `AudioFrame_mergeFramesFromArray`
                // 0x101449c04 via the alloc thunk.
                render = AudioFrame(array: array)
            }

            // Step 4 (CMSampleBuffer) — Forward `AudioFrame_createCMSampleBuffer`
            // 0x10144726c (Atmos passthrough — preserves the E-AC-3 JOC /
            // TrueHD+Atmos bitstream). nil → fall through to the backpressure
            // tail without enqueuing.
            if let sampleBuffer = render.toCMSampleBuffer() {
                let channelCount = render.audioFormat.channelCount

                // Step 5 — time-pitch algorithm. Forward `0x1013f7a2c`
                // (`cmp w0,#0x2 / csel ...,hi`): spectral iff channelCount > 2.
                renderer.audioTimePitchAlgorithm = channelCount > 2 ? .spectral : .timeDomain

                // Step 6 — AVAudioSession negotiation of BOTH channels AND
                // sample rate against the merged frame. macOS has no
                // AVAudioSession, so this is iOS/tvOS/visionOS-only.
                #if !os(macOS)
                let session = AVAudioSession.sharedInstance()
                // Channel half (Forward selref 0x103c52f10 / setter 0x103c531e8,
                // disasm 0x1013f7ad0 — previously undocumented).
                if session.preferredOutputNumberOfChannels != Int(channelCount) {
                    try? session.setPreferredOutputNumberOfChannels(Int(channelCount))
                }
                // Sample-rate half (Forward selref 0x103c52f18 / setter
                // 0x103c531f0, disasm 0x1013f7b90).
                if session.preferredSampleRate != render.audioFormat.sampleRate {
                    try? session.setPreferredSampleRate(render.audioFormat.sampleRate)
                }
                #endif

                // Step 7 — enqueue. Forward `[renderer enqueueSampleBuffer:]`
                // selref 0x103c52a98.
                renderer.enqueue(sampleBuffer)

                // Mirror the render callback clearing `needsReset` once a frame
                // is delivered (`*(self+0x50) = 0`).
                needsReset = false
            }

            // Step 7 (backpressure gate) — Forward `[renderer
            // isReadyForMoreMediaData]` selref 0x103c52d58. false ⇒ stop
            // producing for now; the dispatch source re-invokes us when ready.
            if !renderer.isReadyForMoreMediaData {
                break
            }

            // Step 8 — producer self-throttle (Forward `0x1013f7c44–0x1013f7d20`).
            // leadDelta = batchSeconds − referenceSeconds, where:
            //   batchSeconds   = CMTimeGetSeconds(render.cmtime) — the just-
            //                    enqueued frame's presentation time (disasm
            //                    builds CMTime(value: timestamp·num,
            //                    timescale: den) = render.cmtime, then
            //                    `fsub d8,d8,d0`).
            //   referenceSeconds = the cached seek time (`+0x70..+0x80`) when
            //                    the Optional tag (`+0x88 & 1`) marks `.some`,
            //                    else `synchronizer.currentTime()`.
            // If `playbackRate * 2.2 <= leadDelta` (gate const 2.2 =
            // DAT_102ee95b8), sleep `min(leadDelta / 10.0, 0.4)` (cap 0.4 =
            // DAT_102e8d1f0, /10.0 = 0x4024000000000000) via
            // `Thread.sleep(forTimeInterval:)`. The synchronizer is read-ONLY
            // here (rate / currentTime); there is NO `setRate:time:` in this
            // body. Keeps the renderer ≲ 2.2×-playback-seconds buffered instead
            // of busy-spinning until `isReadyForMoreMediaData` flips false.
            let batchSeconds = render.cmtime.seconds
            let referenceSeconds: Double
            if let seekTarget = seekCMtime {
                referenceSeconds = seekTarget.seconds
            } else {
                referenceSeconds = renderSynchronizer.currentTime().seconds
            }
            let leadDelta = batchSeconds - referenceSeconds
            if Double(playbackRate) * 2.2 <= leadDelta {
                let sleepInterval = min(leadDelta / 10.0, 0.4)
                if sleepInterval > 0 {
                    Thread.sleep(forTimeInterval: sleepInterval)
                }
            }
        }
    }

    /// RE: 0x1013f7280 (AudioRendererPlayer render callback, core vtable slot [2], 1.3.15)
    ///
    /// Distinct binary function from the push-loop body (`request()`,
    /// `0x1013f768c`) — preserved as a separate call per the API Surface rule.
    /// The synchronizer machinery drives this slot to (a) confirm sufficient
    /// media / reset state, (b) pull the next frame via the renderSource witness
    /// `+0x8`, (c) re-arm `synchronizer.setRate:time:` from the cached
    /// `seekCMtime` (`+0x70..+0x88`), and (d) feed the audio clock back via the
    /// renderSource witness `+0x10` = `setAudio(time:position:-1)`.
    ///
    /// The producer-write half (caching the pulled frame's presentation CMTime
    /// into `seekCMtime` and clearing the Optional tag to `.some` — the disasm
    /// tail `stp x19,x22,[x20,#0x70]; str x21,[x20,#0x80]; strb wzr,[x20,#0x88]`)
    /// is what `request()`'s step-8 throttle later reads back as
    /// `referenceSeconds`.
    func renderCallback() {
        // (a) Reset / sufficient-media gate. needsReset is initialized true at
        // construction so the first callback must pull a frame to clear it.
        if #available(macOS 11.3, iOS 14.5, tvOS 14.5, *) {
            if !needsReset, renderer.hasSufficientMediaDataForReliablePlaybackStart {
                // Already primed and the renderer is satisfied — nothing to do.
                return
            }
        }
        // (b) Pull the next frame via the renderSource witness (+0x8).
        guard let render = renderSource?.getAudioOutputRender() else {
            return
        }
        let frameTime = render.cmtime
        // (c) Re-arm the synchronizer at the cached seek target if present,
        // otherwise at the pulled frame's presentation time.
        let startTime = seekCMtime ?? frameTime
        renderSynchronizer.setRate(playbackRate, time: startTime)
        // Producer-write: cache the frame's presentation CMTime as `.some`
        // (binary writes the triple into +0x70..+0x87 and clears the +0x88 tag).
        seekCMtime = frameTime
        needsReset = false
        // (d) Feed the audio clock back to the render source (witness +0x10).
        renderSource?.setAudio(time: frameTime, position: -1)
    }
}
