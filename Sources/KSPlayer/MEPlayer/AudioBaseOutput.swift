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
//  STAGE 1 (this commit) = the faithful field layout + the designated init only.
//  The other 10 vtable bodies are DEFERRED to Stage 2 (addresses pinned below):
//    // ⚑ UNRESOLVED base body — slot 0 getter @0x101a11ba0
//    // ⚑ UNRESOLVED base body — slot 1 setter @0x101a11bd8
//    // ⚑ UNRESOLVED base body — slot 2 read   @0x101a11600
//    // ⚑ UNRESOLVED base body — slot 3 getter @0x101a11684
//    // ⚑ UNRESOLVED base body — slot 4 setter @0x1016b6020
//    // ⚑ UNRESOLVED base body — slot 5 read   @0x101a11690
//    // ⚑ UNRESOLVED base method — slot 28 @0x10000e52c (coalesced abstract stub)
//    // ⚑ UNRESOLVED base method — slot 29 @0x101a116c0
//    // ⚑ UNRESOLVED base method — slot 30 @0x101a117b0
//    // ⚑ UNRESOLVED base method — slot 33 @0x101a1184c
//  The re-parent of AudioEnginePlayer + the field move + prepare/init/flush
//  rewrite are ALSO Stage 2 (the field changes — sampleSize removed, renderLock/
//  memsetZero/outputLatencySystem added — are load-bearing in those bodies).
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
    private var currentRender: AudioFrame?

    // init @0x101a127c8 (slot 27): zero/nil all storage, then seed
    // outputLatencySystem from the system output latency (iOS/tvOS only —
    // AVAudioSession is unavailable on macOS).
    public init() {
        #if !os(macOS)
        outputLatencySystem = AVAudioSession.sharedInstance().outputLatency
        #endif
    }
}
