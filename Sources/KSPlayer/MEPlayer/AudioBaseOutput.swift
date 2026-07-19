//
//  AudioBaseOutput.swift
//  KSPlayer
//
//  Forward extracted the manual AVAudioSourceNode render engine out of the flat
//  upstream `AudioEnginePlayer` into this root base class; `AudioEnginePlayer`
//  becomes a thin subclass (engine/sourceNode/timePitch/lastPrepareTime/
//  minDelayAfterPrepare/volume) that inherits this storage. Binary: metadata
//  @0x1044e84c8, descriptor @0x1039eeaac, superclass=None (root), conformances=[]
//  (GOT-aware binary_conformances), vtable_size=34, instance fields @0x10..0x4f
//  (subclass storage begins at +0x50).
//
//  Reconstruction status (bottom-up):
//    slots 0-2  renderSource get/set/_modify — compiler-synthesized by the `weak var` decl.
//    slots 3-5  outputLatency computed property — DONE.
//    slot 27    init() — DONE (Stage 1).
//    slot 30    flush() — DONE.
//    slot 28    prepare(audioFormat:) overridable hook — DONE.
//    slot 29    prepareRender() (⚑ inferred name) — DONE.
//    slot 33    audioPlayerDidRenderSample() — DONE.
//  DEFERRED — the sample-copy engine (next commit):
//    // ⚑ UNRESOLVED private method — audioPlayerShouldInputData, the sample-copy @0x101a12b28 (non-vtable; reached from
//    //    prepare's AVAudioSourceNode render block → thunk @0x101a0f6f0 → closure @0x101a0ed08). Under renderLock it pulls
//    //    frames, honours memsetZero (bzero silence path in place of the memmove copy), re-prepares on a format change via
//    //    slot 28, and zero-fills the tail.
//  THEN the re-parent of AudioEnginePlayer (field move + prepare/init rewrite + delete sampleSize/the flat render methods —
//  those changes are load-bearing and would break the build if done before the engine lands).
//

import AVFoundation

public class AudioBaseOutput {
    // Fields in __swift5_fieldmd (field-record) order — dump_binary_field_types.
    public weak var renderSource: OutputRenderSourceDelegate?
    private var sourceNodeAudioFormat: AVAudioFormat?
    private var memsetZero: Bool = false
    private var outputLatencySystem: Double = 0
    private var _outputLatency: Double = 0
    private var renderLock: os_unfair_lock_s = os_unfair_lock_s()
    private var currentRenderReadOffset: UInt32 = 0
    private var currentRender: AudioFrame? {
        didSet {
            if currentRender == nil {
                currentRenderReadOffset = 0
            }
        }
    }

    // outputLatency (computed, slots 3-5): the public latency = the system
    // baseline (outputLatencySystem, seeded in init) + the app-set delta
    // (_outputLatency); the setter writes only the delta.
    public var outputLatency: TimeInterval {
        get { _outputLatency + outputLatencySystem }
        set { _outputLatency = newValue }
    }

    // init @0x101a127c8 (slot 27): zero/nil all storage, then seed
    // outputLatencySystem from the system output latency (iOS/tvOS only —
    // AVAudioSession is unavailable on macOS).
    public init() {
        #if !os(macOS)
        outputLatencySystem = AVAudioSession.sharedInstance().outputLatency
        #endif
    }

    // flush (slot 30 @0x101a117b0): drop the in-flight frame under renderLock
    // (the didSet resets currentRenderReadOffset), then re-read the system
    // output latency (iOS/tvOS only).
    public func flush() {
        os_unfair_lock_lock(&renderLock)
        currentRender = nil
        os_unfair_lock_unlock(&renderLock)
        #if !os(macOS)
        outputLatencySystem = AVAudioSession.sharedInstance().outputLatency
        #endif
    }

    // prepare(audioFormat:) (slot 28 @0x10000e52c — the coalesced empty-body
    // stub): the overridable base hook. AudioEnginePlayer overrides it with the
    // real engine/sourceNode setup; the sample-copy engine re-invokes it through
    // this slot when the incoming frame's format stops matching
    // sourceNodeAudioFormat. Slot identity is arithmetic, not inferred: the
    // engine's main-thread re-prepare calls metadata+0x170, and the vtable base
    // is metadata+0x90 (slot k at +0x90+k*8), so 0x170 == slot 28.
    public func prepare(audioFormat _: AVAudioFormat) {}

    // ⚑ name INFERRED — #function is unrecoverable (stripped, no literal), and
    // the method is absent from the source and from the FrameOutput/AudioOutput
    // requirement sets, so no tool maps this address to a symbol. Named for its
    // behaviour. slot 29 @0x101a116c0; AudioEnginePlayer.play() calls it before
    // engine.start() to prime the render state.
    public func prepareRender() {
        os_unfair_lock_lock(&renderLock)
        if currentRender == nil {
            currentRender = renderSource?.getAudioOutputRender()
            currentRenderReadOffset = 0
        }
        os_unfair_lock_unlock(&renderLock)
        audioPlayerDidRenderSample()
    }

    // audioPlayerDidRenderSample (slot 33 @0x101a1184c): report the audio clock
    // to renderSource. Forward drops upstream's unused sampleTimestamp parameter,
    // takes renderLock while reading the frame state, and releases it before the
    // CMTime work and the delegate call.
    public func audioPlayerDidRenderSample() {
        os_unfair_lock_lock(&renderLock)
        guard let currentRender, let renderSource else {
            os_unfair_lock_unlock(&renderLock)
            return
        }
        let currentPreparePosition = currentRender.timestamp + currentRender.duration * Int64(currentRenderReadOffset) / Int64(currentRender.numberOfSamples)
        os_unfair_lock_unlock(&renderLock)
        if currentPreparePosition > 0 {
            var time = currentRender.timebase.cmtime(for: currentPreparePosition)
            if outputLatency != 0 {
                time = time - CMTime(seconds: outputLatency, preferredTimescale: time.timescale)
            }
            renderSource.setAudio(time: time, position: currentRender.position)
        }
    }
}
