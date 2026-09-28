//
//  AudioRendererPlayer.swift
//  KSPlayer
//
//  Created by kintan on 2022/12/2.
//
//  Forward 1.3.17 EVOLVED this class into a subclass of `AudioDataBuffer`: it no longer owns
//  renderSource/eof/currentRender/currentRenderReadOffset (all inherited) and drives an
//  AVSampleBufferAudioRenderer from CMSampleBuffers produced by the inherited
//  `sampleBuffer(nanoseconds:)`. Descriptor @0x1039eebf0, super=AudioDataBuffer
//  (superclass_conformance_gate), conformances=[AudioOutput, FrameOutput] (AudioOutput refines
//  FrameOutput). 9 own fields (field-record order below), a 32-slot own vtable + an override table.
//
//  Field declaration order below IS the __swift5_fieldmd order (dump_field_bindings) and, for the
//  four accessor-bearing members, the vtable accessor-triple order: outputLatency (slots 0-2),
//  playbackRate (3-5), volume (6-8), isMuted (9-11); the private stored state gets storage but no
//  vtable triple. Do not reorder.
//

import AVFoundation
import Foundation

public class AudioRendererPlayer: AudioDataBuffer, AudioOutput {
    // outputLatency @+0x38 (field 1) — subtracted from the reported audio time (play() + the
    // periodic-observer callback both guard `if outputLatency != 0`). init = 0. Non-private: it
    // carries the vtable accessor triple at slots 0-2.
    public var outputLatency: TimeInterval = 0
    // playbackRate @+0x40 (field 2). vtable setter @0x101a1320c.
    public var playbackRate: Float = 1 {
        didSet {
            if !isPaused {
                synchronizer.rate = playbackRate
                if playbackRate == 1, !renderer.hasSufficientMediaDataForReliablePlaybackStart {
                    renderer.flush()
                }
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

    var isPaused: Bool {
        synchronizer.rate == 0
    }

    // periodicTimeObserver @+0x48 (field 3, Any? — 32-byte existential 0x48..0x67).
    private var periodicTimeObserver: Any?
    // flushTime @+0x68 (field 4) — the FLUSH-PENDING flag. flush()/stop()/request()-on-eof set it;
    // play() consumes it: only when set does play() flush the renderer and re-seed the render loop
    // (a plain pause->play resume with flushTime == false just restores the rate). init = false.
    private var flushTime = false
    private let renderer = AVSampleBufferAudioRenderer()          // @+0x70 (field 5)
    private let synchronizer = AVSampleBufferRenderSynchronizer() // @+0x78 (field 6)
    // requestQueue @+0x80 (field 7) — renamed from the pre-re-parent `serializationQueue`. The
    // binary label literal @0x103d341b0 (len 0x24).
    private let requestQueue = DispatchQueue(label: "KSPlayer-AudioRendererPlayer-request")
    // startTime @+0x88 (field 8, CMTime) — the first render's presentation time (ns scale); the
    // observer adds the synchronizer's elapsed time to it. flush-work resets it to .zero. init = .zero.
    private var startTime = CMTime.zero
    // timestamp @+0xa0 (field 9, Int64) — the running-MAX nanosecond media clock handed to the
    // inherited sampleBuffer(nanoseconds:). init = -1; play() resets it to -1.
    private var timestamp: Int64 = -1

    public required override init() {
        super.init()
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
        try? AVAudioSession.sharedInstance().setPreferredSampleRate(audioFormat.sampleRate)
        KSLog("[audio] set preferredOutputNumberOfChannels=\(audioFormat.channelCount) outputNumberOfChannels=\(AVAudioSession.sharedInstance().outputNumberOfChannels)")
        #endif
        if let periodicTimeObserver {
            synchronizer.removeTimeObserver(periodicTimeObserver)
            self.periodicTimeObserver = nil
        }
        periodicTimeObserver = synchronizer.addPeriodicTimeObserver(forInterval: CMTime(value: 100, timescale: Int32(audioFormat.sampleRate)), queue: .main) { [weak self] time in
            guard let self else {
                return
            }
            var audioTime = time + self.startTime
            if self.outputLatency != 0 {
                audioTime = audioTime - CMTime(seconds: self.outputLatency, preferredTimescale: 1_000_000_000)
            }
            self.renderSource?.setAudio(time: audioTime, position: -1)
        }
        flushTime = true
        if timestamp != -1 {
            requestQueue.sync {
                currentRender = nil
                renderer.stopRequestingMediaData()
            }
        }
    }

    public func play() {
        eof = false
        if flushTime {
            flushTime = false
            timestamp = -1
            renderer.flush()
            synchronizer.setRate(playbackRate, time: .zero)
            renderer.requestMediaDataWhenReady(on: requestQueue) { [weak self] in
                guard let self else {
                    return
                }
                self.request()
            }
            currentRender = if case let .left(render)? = renderSource?.getAudioOutputRender() {
                render
            } else {
                nil
            }
            if let render = currentRender {
                startTime = render.cmtime.convertScale(1_000_000_000, method: .default)
                var audioTime = startTime
                if outputLatency != 0 {
                    audioTime = audioTime - CMTime(seconds: outputLatency, preferredTimescale: audioTime.timescale)
                }
                renderSource?.setAudio(time: audioTime, position: -1)
            }
        } else {
            synchronizer.rate = playbackRate
        }
    }

    public func pause() {
        synchronizer.rate = 0
    }

    // Overrides the inherited AudioDataBuffer.flush() (override_table; body @0x101a14360). Sets the
    // flush-pending flag, then on the requestQueue tears down the in-flight render + renderer state.
    override public func flush() {
        flushTime = true
#sourceLocation(file: "KSPlayer/AudioRendererPlayer.swift", line: 123)
        requestQueue.sync {
            currentRender = nil
            renderer.stopRequestingMediaData()
            synchronizer.rate = 0
            startTime = .zero
        }
#sourceLocation()
    }

    // stop() @0x101a144d0 — flush-work + observer teardown. NOT yet a FrameOutput requirement in source
    // (binary FrameOutput {pause,flush,play,stop}; source {renderSource,pause,flush,play}) — follow-on unit.
    // ⚑ s105 RENAME: was `stop()`, an inferred name. The trie names 0x101a144d0 `invalidate()` (ONE
    // symbol, not an ICF fold; there is no `stop` symbol on this class at all). Only the name was
    // invented; the body below is read end to end from 0x101a144d0.
    public func invalidate() {
        flush()
        // The flush work is flush() INLINED, not a copy: invalidate's register allocation and its
        // early `swift_release(self)` @0x101a145b4 (right after the escape check, before the
        // observer teardown) reproduce only with the call; a duplicated body releases self at the
        // function end. The inlined closure's `swift_isEscapingClosureAtFileLocation` @0x101a145a8
        // carries line 0x7b = 123 (col 0x1b) — flush's sync closure, remapped above; the filename
        // length operand (0x53) is the build machine's absolute path and is not source-controlled.
        if let periodicTimeObserver {
            synchronizer.removeTimeObserver(periodicTimeObserver)
            self.periodicTimeObserver = nil
        }
    }

    /// Vtable F30: a dead slot of shape M, so Forward keeps no body, callers or strings. Name INFERRED;
    /// the declaration only holds the slot so that request() (F31) lines up.
    func unreadSlot30() {}

    // request() @0x101a1468c (vtable F31) — the requestMediaDataWhenReady callback. Rewired onto the inherited
    // AudioDataBuffer.sampleBuffer(nanoseconds:) (@0x101a11cd4) instead of the old flat
    // toCMSampleBuffer() loop. One enqueue per call (AVFoundation re-invokes the block); it throttles
    // with a bounded sleep when the enqueued buffer runs far enough ahead of the synchronizer.
    func request() {
        guard !isPaused else {
            return
        }
        let currentNanoseconds = synchronizer.currentTime().convertScale(1_000_000_000, method: .default).value
        let nanoseconds = max(timestamp, currentNanoseconds)
        timestamp = nanoseconds
        guard let sampleBuffer = sampleBuffer(nanoseconds: nanoseconds) else {
            if eof {
                flushTime = true
                renderer.stopRequestingMediaData()
            }
            return
        }
        if let formatDescription = sampleBuffer.formatDescription {
            let channelCount = formatDescription.channelCount
            let sampleRate = formatDescription.sampleRate
            timestamp += CMTime(value: Int64(sampleBuffer.numSamples), timescale: Int32(sampleRate)).convertScale(1_000_000_000, method: .default).value
            renderer.audioTimePitchAlgorithm = channelCount > 2 ? .spectral : .timeDomain
            #if !os(macOS)
            if AVAudioSession.sharedInstance().preferredOutputNumberOfChannels != Int(channelCount) {
                try? AVAudioSession.sharedInstance().setPreferredOutputNumberOfChannels(Int(channelCount))
            }
            if AVAudioSession.sharedInstance().preferredSampleRate != sampleRate {
                try? AVAudioSession.sharedInstance().setPreferredSampleRate(sampleRate)
            }
            #endif
        }
        renderer.enqueue(sampleBuffer)
        if renderer.isReadyForMoreMediaData {
            let currentTime = synchronizer.currentTime()
            let ahead = (sampleBuffer.presentationTimeStamp - currentTime).seconds
            if Double(playbackRate) * 2.2 <= ahead {
                Thread.sleep(forTimeInterval: min(ahead / 10, 0.4))
            }
        }
    }
}
