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
                synchronizer.rate = playbackRate
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

    /// Render synchronizer at Forward field `+0x60`.
    public let synchronizer = AVSampleBufferRenderSynchronizer()

    /// Request queue at Forward field `+0x68`. Label exactly matches the binary
    /// literal at `0x80000001033312d0` (36 bytes).
    private let requestQueue = DispatchQueue(label: "KSPlayer-AudioRendererPlayer-request")

    /// Cached audio format from the most recent `prepare(audioFormat:)` call.
    /// Used by `play()` to size the periodic observer interval — the Forward
    /// binary derives the CMTime value from the audio format's sample-rate path
    /// inside `AudioRendererPlayer_play` (`0x1013f6afc`).
    private var preparedAudioFormat: AVAudioFormat?

    var isPaused: Bool {
        synchronizer.rate == 0
    }

    public required init() {
        // Order matches Forward `AudioRendererPlayer_init` @ `0x1013f67e4`:
        //   alloc renderer (already done via property init)
        //   alloc synchronizer (already done via property init)
        //   build requestQueue (already done via property init)
        //   addRenderer
        //   setDelaysRateChangeUntilHasSufficientMediaData:NO
        //   setAllowedAudioSpatializationFormats:.monoStereoAndMultichannel (7)
        synchronizer.addRenderer(renderer)
        if #available(macOS 11.3, iOS 14.5, tvOS 14.5, *) {
            synchronizer.delaysRateChangeUntilHasSufficientMediaData = false
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
                time = synchronizer.currentTime()
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
        synchronizer.setRate(playbackRate, time: time)
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
            synchronizer.removeTimeObserver(periodicTimeObserver)
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
        periodicTimeObserver = synchronizer.addPeriodicTimeObserver(forInterval: observerInterval, queue: .main) { [weak self] time in
            guard let self else {
                return
            }
            self.renderSource?.setAudio(time: time, position: -1)
        }
    }

    public func pause() {
        synchronizer.rate = 0
        renderer.stopRequestingMediaData()
        if let periodicTimeObserver {
            synchronizer.removeTimeObserver(periodicTimeObserver)
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
        synchronizer.setRate(playbackRate, time: .zero)
    }

    /// Seek-aware flush: stores target time for synchronized resume.
    /// Populates `seekCMtime` (Forward `+0x70..+0x88` inline Optional<CMTime>).
    public func flush(seekTime: CMTime) {
        renderer.flush()
        needsReset = true
        synchronizer.setRate(playbackRate, time: .zero)
        seekCMtime = seekTime
    }

    /// `AudioRendererPlayer_stopAndCleanup` at Forward `0x1013f7570`:
    ///   stopRequestingMediaData, flush, needsReset = 1, removeTimeObserver, setRate:0
    public func stopAndCleanup() {
        renderer.stopRequestingMediaData()
        renderer.flush()
        needsReset = true
        if let periodicTimeObserver {
            synchronizer.removeTimeObserver(periodicTimeObserver)
            self.periodicTimeObserver = nil
        }
        synchronizer.rate = 0
    }

    private func request() {
        // Forward request loop runs while the renderer is ready, the
        // synchronizer is not paused, and we are not still waiting on a
        // seek target (`seekCMtime` is consumed by the next `play()` call).
        while renderer.isReadyForMoreMediaData, !isPaused, seekCMtime == nil {
            guard var render = renderSource?.getAudioOutputRender() else {
                break
            }
            var array = [render]
            let loopCount = Int32(render.audioFormat.sampleRate) / 20 / Int32(render.numberOfSamples) - 2
            if loopCount > 0 {
                for _ in 0 ..< loopCount {
                    if let render = renderSource?.getAudioOutputRender() {
                        array.append(render)
                    }
                }
            }
            if array.count > 1 {
                render = AudioFrame(array: array)
            }
            if let sampleBuffer = render.toCMSampleBuffer() {
                let channelCount = render.audioFormat.channelCount
                renderer.audioTimePitchAlgorithm = channelCount > 2 ? .spectral : .timeDomain
                renderer.enqueue(sampleBuffer)
                // Forward render callback clears `needsReset` once a frame is
                // successfully delivered (`*(self+0x50) = 0` after the weak
                // load + frame pull at `0x1013f7280`).
                needsReset = false
                #if !os(macOS)
                if AVAudioSession.sharedInstance().preferredOutputNumberOfChannels != channelCount {
                    try? AVAudioSession.sharedInstance().setPreferredOutputNumberOfChannels(Int(channelCount))
                }
                #endif
            }
        }
    }
}
