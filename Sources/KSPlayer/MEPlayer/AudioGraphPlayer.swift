//
//  AudioGraphPlayer.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/16.
//
//  Forward re-parents this onto AudioBaseOutput (binary superclass @0x1044e84c8), which
//  owns the render engine — renderSource / currentRender / sourceNodeAudioFormat / the
//  render lock / the sample-copy loop (audioPlayerShouldInputData) and the audio clock
//  (audioPlayerDidRenderSample). What is left here is the 4-node AUGraph (timePitch ->
//  dynamicsProcessor -> mixer -> output). Binary: descriptor @0x1039ee8e4, conformances
//  = [AudioOutput, FrameOutput, AudioDynamicsProcessor], own vtable = {Init} (VTableSize=1)
//  + an override table (current-swiftc override-direct, so no vtable-numbering pin). Own
//  stored fields (dump_field_bindings, field-record order): audioUnitForDynamicsProcessor
//  @0x50, graph @0x58, audioUnitForMixer @0x60, audioUnitForTimePitch @0x68,
//  audioUnitForOutput @0x70, currentRenderReadOffset @0x78. Inherited storage is 0x10..0x4f.

import AudioToolbox
import AVFAudio
import CoreAudio

public class AudioGraphPlayer: AudioBaseOutput, AudioOutput, AudioDynamicsProcessor {
    public private(set) var audioUnitForDynamicsProcessor: AudioUnit
    private let graph: AUGraph
    private var audioUnitForMixer: AudioUnit!
    private var audioUnitForTimePitch: AudioUnit!
    private var audioUnitForOutput: AudioUnit!
    // Vestigial: the binary retains this own field (init zeroes it), but nothing in the
    // re-parented class reads or writes it — the render loop is now the inherited
    // AudioBaseOutput.audioPlayerShouldInputData, which uses its own currentRenderReadOffset.
    // Declared to match the binary's 6-field layout.
    private var currentRenderReadOffset = UInt32(0)
    #if os(macOS)
    private var volumeBeforeMute: Float = 0.0
    #endif

    public func play() {
        prepareRender()
        AUGraphStart(graph)
    }

    public func pause() {
        AUGraphStop(graph)
    }

    public var playbackRate: Float {
        get {
            var playbackRate = AudioUnitParameterValue(0.0)
            AudioUnitGetParameter(audioUnitForTimePitch, kNewTimePitchParam_Rate, kAudioUnitScope_Global, 0, &playbackRate)
            return playbackRate
        }
        set {
            AudioUnitSetParameter(audioUnitForTimePitch, kNewTimePitchParam_Rate, kAudioUnitScope_Global, 0, newValue, 0)
        }
    }

    public var volume: Float {
        get {
            var volume = AudioUnitParameterValue(0.0)
            #if os(macOS)
            let inID = kStereoMixerParam_Volume
            #else
            let inID = kMultiChannelMixerParam_Volume
            #endif
            AudioUnitGetParameter(audioUnitForMixer, inID, kAudioUnitScope_Input, 0, &volume)
            return volume
        }
        set {
            #if os(macOS)
            let inID = kStereoMixerParam_Volume
            #else
            let inID = kMultiChannelMixerParam_Volume
            #endif
            AudioUnitSetParameter(audioUnitForMixer, inID, kAudioUnitScope_Input, 0, newValue, 0)
        }
    }

    public var isMuted: Bool {
        get {
            var value = AudioUnitParameterValue(1.0)
            #if os(macOS)
            AudioUnitGetParameter(audioUnitForMixer, kStereoMixerParam_Volume, kAudioUnitScope_Input, 0, &value)
            #else
            AudioUnitGetParameter(audioUnitForMixer, kMultiChannelMixerParam_Enable, kAudioUnitScope_Input, 0, &value)
            #endif
            return value == 0
        }
        set {
            let value = newValue ? 0 : 1
            #if os(macOS)
            if value == 0 {
                volumeBeforeMute = volume
            }
            AudioUnitSetParameter(audioUnitForMixer, kStereoMixerParam_Volume, kAudioUnitScope_Input, 0, min(Float(value), volumeBeforeMute), 0)
            #else
            AudioUnitSetParameter(audioUnitForMixer, kMultiChannelMixerParam_Enable, kAudioUnitScope_Input, 0, AudioUnitParameterValue(value), 0)
            #endif
        }
    }

    // init @0x101a10918 (alloc entry 0x101a108e4). `required override init()`: overrides
    // AudioBaseOutput.init() and satisfies AudioOutput's init requirement. super.init() seeds
    // the base storage (incl. outputLatencySystem from AVAudioSession on iOS/tvOS), which is
    // why the upstream `outputLatency = AVAudioSession...` line is gone from here.
    //
    // The alloc entry is swift_allocObject(size: 0x7c, alignMask: 7) then `bl 0x101a10918`
    // and `mov x0,x20 ; ret` — 13 instructions, identical in shape to AudioEnginePlayer's.
    // 0x7c over the 0x50 base leaves 0x2c, which is exactly the six own fields listed in the
    // file header. ARITY 0 is proven, not assumed: across those 13 instructions the entry
    // reads only x20 (the metatype), and w1/w2 are written with the size and align mask
    // rather than read. No argument register is read anywhere, which refutes a DEFAULTED
    // parameter as well as a declared one — a default-argument generator runs at the CALL
    // site, so its value would still have to arrive in an argument register here.
    //
    // super.init() runs where it is written below, AFTER the graph is fully built: the
    // inlined base storage zeroing sits at the END of the body, past all four
    // AUGraphNodeInfo calls. It must at least follow the two assignments to `graph` (+0x58)
    // and `audioUnitForDynamicsProcessor` (+0x50): neither carries a default, so Swift phase
    // 1 is not complete until both are stored, and the binary stores both before it.
    //
    // Each AudioComponentDescription is a compile-time constant the optimiser folded whole:
    // 16 bytes (componentType, componentSubType, componentManufacturer, componentFlags = 0)
    // copied from .rodata, with componentFlagsMask stored as a separate inline zero. Read as
    // FourCCs, byte-verified:
    //   descriptionForTimePitch          @0x103564570  'aufc' 'nutp' 'appl' 0
    //   descriptionForDynamicsProcessor  @0x1035644f0  'aufx' 'dcmp' 'appl' 0
    //   descriptionForMixer              @0x103564580  'aumx' 'mcmx' 'appl' 0
    //   descriptionForOutput             @0x103564590  'auou' 'rioc' 'appl' 0
    // 'mcmx' and 'rioc' are the MultiChannelMixer / RemoteIO subtypes, i.e. the `#else`
    // (non-macOS) arms below are the ones this build compiled; the macOS arms are
    // unverifiable from it, not contradicted.
    public required override init() {
        var newGraph: AUGraph!
        NewAUGraph(&newGraph)
        graph = newGraph
        var descriptionForTimePitch = AudioComponentDescription()
        descriptionForTimePitch.componentType = kAudioUnitType_FormatConverter
        descriptionForTimePitch.componentSubType = kAudioUnitSubType_NewTimePitch
        descriptionForTimePitch.componentManufacturer = kAudioUnitManufacturer_Apple
        var descriptionForDynamicsProcessor = AudioComponentDescription()
        descriptionForDynamicsProcessor.componentType = kAudioUnitType_Effect
        descriptionForDynamicsProcessor.componentManufacturer = kAudioUnitManufacturer_Apple
        descriptionForDynamicsProcessor.componentSubType = kAudioUnitSubType_DynamicsProcessor
        var descriptionForMixer = AudioComponentDescription()
        descriptionForMixer.componentType = kAudioUnitType_Mixer
        descriptionForMixer.componentManufacturer = kAudioUnitManufacturer_Apple
        #if os(macOS)
        descriptionForMixer.componentSubType = kAudioUnitSubType_StereoMixer
        #else
        descriptionForMixer.componentSubType = kAudioUnitSubType_MultiChannelMixer
        #endif
        var descriptionForOutput = AudioComponentDescription()
        descriptionForOutput.componentType = kAudioUnitType_Output
        descriptionForOutput.componentManufacturer = kAudioUnitManufacturer_Apple
        #if os(macOS)
        descriptionForOutput.componentSubType = kAudioUnitSubType_DefaultOutput
        #else
        descriptionForOutput.componentSubType = kAudioUnitSubType_RemoteIO
        #endif
        var nodeForTimePitch = AUNode()
        var nodeForDynamicsProcessor = AUNode()
        var nodeForMixer = AUNode()
        var nodeForOutput = AUNode()
        AUGraphAddNode(graph, &descriptionForTimePitch, &nodeForTimePitch)
        AUGraphAddNode(graph, &descriptionForMixer, &nodeForMixer)
        AUGraphAddNode(graph, &descriptionForDynamicsProcessor, &nodeForDynamicsProcessor)
        AUGraphAddNode(graph, &descriptionForOutput, &nodeForOutput)
        AUGraphOpen(graph)
        AUGraphConnectNodeInput(graph, nodeForTimePitch, 0, nodeForDynamicsProcessor, 0)
        AUGraphConnectNodeInput(graph, nodeForDynamicsProcessor, 0, nodeForMixer, 0)
        AUGraphConnectNodeInput(graph, nodeForMixer, 0, nodeForOutput, 0)
        AUGraphNodeInfo(graph, nodeForTimePitch, &descriptionForTimePitch, &audioUnitForTimePitch)
        var audioUnitForDynamicsProcessor: AudioUnit?
        AUGraphNodeInfo(graph, nodeForDynamicsProcessor, &descriptionForDynamicsProcessor, &audioUnitForDynamicsProcessor)
        self.audioUnitForDynamicsProcessor = audioUnitForDynamicsProcessor!
        AUGraphNodeInfo(graph, nodeForMixer, &descriptionForMixer, &audioUnitForMixer)
        AUGraphNodeInfo(graph, nodeForOutput, &descriptionForOutput, &audioUnitForOutput)
        super.init()
        addRenderNotify(audioUnit: audioUnitForOutput)
        var value = UInt32(1)
        AudioUnitSetProperty(audioUnitForTimePitch,
                             kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Output, 0,
                             &value,
                             UInt32(MemoryLayout<UInt32>.size))
    }

    // prepare(audioFormat:) @0x101a10bf4 — OVERRIDES AudioBaseOutput's slot-28 hook. Forward's
    // deltas over the flat body: the preferred sample rate is set as well as the channel count;
    // the KSLog gains the outputNumberOfChannels value; sampleSize is gone (AudioBaseOutput
    // drives the copy from the buffer's own mDataByteSize). The channel layout still comes from
    // channelLayout?.layout (unlike AudioUnitPlayer, which switched to
    // CMAudioFormatDescriptionGetChannelLayout).
    override public func prepare(audioFormat: AVAudioFormat) {
        if sourceNodeAudioFormat == audioFormat {
            return
        }
        sourceNodeAudioFormat = audioFormat
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setPreferredOutputNumberOfChannels(Int(audioFormat.channelCount))
        try? AVAudioSession.sharedInstance().setPreferredSampleRate(audioFormat.sampleRate)
        KSLog("[audio] set preferredOutputNumberOfChannels=\(audioFormat.channelCount) outputNumberOfChannels=\(AVAudioSession.sharedInstance().outputNumberOfChannels)")
        #endif
        var audioStreamBasicDescription = audioFormat.formatDescription.audioStreamBasicDescription
        let audioStreamBasicDescriptionSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let channelLayout = audioFormat.channelLayout?.layout
        for unit in [audioUnitForTimePitch, audioUnitForDynamicsProcessor, audioUnitForMixer, audioUnitForOutput] {
            guard let unit else { continue }
            AudioUnitSetProperty(unit,
                                 kAudioUnitProperty_StreamFormat,
                                 kAudioUnitScope_Input, 0,
                                 &audioStreamBasicDescription,
                                 audioStreamBasicDescriptionSize)
            AudioUnitSetProperty(unit,
                                 kAudioUnitProperty_AudioChannelLayout,
                                 kAudioUnitScope_Input, 0,
                                 channelLayout,
                                 UInt32(MemoryLayout<AudioChannelLayout>.size))
            if unit != audioUnitForOutput {
                AudioUnitSetProperty(unit,
                                     kAudioUnitProperty_StreamFormat,
                                     kAudioUnitScope_Output, 0,
                                     &audioStreamBasicDescription,
                                     audioStreamBasicDescriptionSize)
                AudioUnitSetProperty(unit,
                                     kAudioUnitProperty_AudioChannelLayout,
                                     kAudioUnitScope_Output, 0,
                                     channelLayout,
                                     UInt32(MemoryLayout<AudioChannelLayout>.size))
            }
            if unit == audioUnitForTimePitch {
                var inputCallbackStruct = renderCallbackStruct()
                AudioUnitSetProperty(unit,
                                     kAudioUnitProperty_SetRenderCallback,
                                     kAudioUnitScope_Input, 0,
                                     &inputCallbackStruct,
                                     UInt32(MemoryLayout<AURenderCallbackStruct>.size))
            }
        }
        AUGraphInitialize(graph)
    }

    // stop() @0x101a11138 (FrameOutput requirement 3). New in Forward — the flat class did this
    // in deinit; that deinit is gone (DisposeAUGraph has exactly one caller now, stop()).
    // flush() is NOT overridden: FrameOutput requirement 2 resolves to the inherited
    // AudioBaseOutput.flush @0x101a117b0.
    public func stop() {
        AUGraphStop(graph)
        AUGraphUninitialize(graph)
        AUGraphClose(graph)
        DisposeAUGraph(graph)
    }
}

extension AudioGraphPlayer {
    private func renderCallbackStruct() -> AURenderCallbackStruct {
        var inputCallbackStruct = AURenderCallbackStruct()
        inputCallbackStruct.inputProcRefCon = Unmanaged.passUnretained(self).toOpaque()
        // inputProc @0x101a114a0 — calls the INHERITED audioPlayerShouldInputData(ioData:); the
        // frame count comes from the buffer's own mDataByteSize, so inNumberFrames is unused.
        inputCallbackStruct.inputProc = { refCon, _, _, _, _, ioData in
            guard let ioData else {
                return noErr
            }
            let `self` = Unmanaged<AudioGraphPlayer>.fromOpaque(refCon).takeUnretainedValue()
            self.audioPlayerShouldInputData(ioData: UnsafeMutableAudioBufferListPointer(ioData))
            return noErr
        }
        return inputCallbackStruct
    }

    private func addRenderNotify(audioUnit: AudioUnit) {
        // renderNotify @0x101a11548 — calls the INHERITED audioPlayerDidRenderSample() on
        // PostRender; Forward drops the flat body's unused sampleTimestamp argument.
        AudioUnitAddRenderNotify(audioUnit, { refCon, ioActionFlags, _, _, _, _ in
            let `self` = Unmanaged<AudioGraphPlayer>.fromOpaque(refCon).takeUnretainedValue()
            autoreleasepool {
                if ioActionFlags.pointee.contains(.unitRenderAction_PostRender) {
                    self.audioPlayerDidRenderSample()
                }
            }
            return noErr
        }, Unmanaged.passUnretained(self).toOpaque())
    }
}
