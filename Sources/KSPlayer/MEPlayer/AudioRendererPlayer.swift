//
//  AudioRendererPlayer.swift
//  KSPlayer
//
//  Created by kintan on 2022/12/2.
//

import AVFoundation
import Foundation

public class AudioRendererPlayer: AudioOutput {
    public var playbackRate: Float = 1 {
        didSet {
            if !isPaused {
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

    // MARK: - Forward additions (RE/66)

    /// Output latency for A/V sync calibration
    public var outputLatency: Double = 0.0
    /// Flush state flag — prevents enqueueing during flush
    private var flushTime: Bool = false
    /// Seek target timestamp for synchronized seeking
    private var seekCMtime: CMTime?

    public weak var renderSource: OutputRenderSourceDelegate?
    private var periodicTimeObserver: Any?
    private let renderer = AVSampleBufferAudioRenderer()
    public let synchronizer = AVSampleBufferRenderSynchronizer()
    private let requestQueue = DispatchQueue(label: "ks.player.serialization.queue")
    var isPaused: Bool {
        synchronizer.rate == 0
    }

    public required init() {
        synchronizer.addRenderer(renderer)
        if #available(macOS 11.3, iOS 14.5, tvOS 14.5, *) {
            synchronizer.delaysRateChangeUntilHasSufficientMediaData = false
        }
        if #available(tvOS 15.0, iOS 15.0, macOS 12.0, *) {
            renderer.allowedAudioSpatializationFormats = .monoStereoAndMultichannel
        }
    }

    public func prepare(audioFormat: AVAudioFormat) {
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setPreferredOutputNumberOfChannels(Int(audioFormat.channelCount))
        KSLog("[audio] set preferredOutputNumberOfChannels: \(audioFormat.channelCount)")
        #endif
    }

    public func play() {
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
        flushTime = false
        synchronizer.setRate(playbackRate, time: time)
        renderSource?.setAudio(time: time, position: -1)
        renderer.requestMediaDataWhenReady(on: requestQueue) { [weak self] in
            guard let self else {
                return
            }
            self.request()
        }
        periodicTimeObserver = synchronizer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.01), queue: .main) { [weak self] time in
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

    public func flush() {
        flushTime = true
        renderer.flush()
        synchronizer.setRate(0, time: .zero)
        seekCMtime = nil
    }

    /// Seek-aware flush: stores target time for synchronized resume.
    public func flush(seekTime: CMTime) {
        flushTime = true
        renderer.flush()
        synchronizer.setRate(0, time: .zero)
        seekCMtime = seekTime
    }

    private func request() {
        while renderer.isReadyForMoreMediaData, !isPaused, !flushTime {
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
                #if !os(macOS)
                if AVAudioSession.sharedInstance().preferredOutputNumberOfChannels != channelCount {
                    try? AVAudioSession.sharedInstance().setPreferredOutputNumberOfChannels(Int(channelCount))
                }
                #endif
            }
        }
    }
}
