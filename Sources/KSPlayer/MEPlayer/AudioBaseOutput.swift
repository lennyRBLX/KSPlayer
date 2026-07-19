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
//  DEFERRED — the render engine (next commit):
//    // ⚑ UNRESOLVED base method — slot 28 @0x10000e52c (empty coalesced stub; name unrecoverable)
//    // ⚑ UNRESOLVED base method — slot 29 @0x101a116c0 (render-pull: fetch currentRender from renderSource under renderLock)
//    // ⚑ UNRESOLVED base method — slot 33 @0x101a1184c (audioPlayerDidRenderSample: CMTime timing → renderSource.setAudio)
//    // ⚑ UNRESOLVED private method — audioPlayerShouldInputData (sample-copy; non-vtable, via the AVAudioSourceNode render block)
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
}
