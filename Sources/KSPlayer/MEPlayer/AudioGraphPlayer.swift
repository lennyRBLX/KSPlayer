//
//  AudioGraphPlayer.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/16.
//

import AudioToolbox
import AVFAudio
import CoreAudio

public final class AudioGraphPlayer: AudioOutput, AudioDynamicsProcessor {
    public private(set) var audioUnitForDynamicsProcessor: AudioUnit
    private let graph: AUGraph
    private var audioUnitForMixer: AudioUnit!
    // Head node of the graph. RE field +0x28: the AudioComponentDescription bytes at
    // 0x102ee93a0 resolve to type `aufc` (FormatConverter) / subtype `nutp` (NewTimePitch),
    // so this is genuinely a NewTimePitch unit and `playbackRate` via kNewTimePitchParam_Rate
    // is valid — but the binary situates it by node type (FormatConverter), so it is named
    // for its converter/head role rather than the rate function. There is no standalone
    // TimePitch node in the graph. (was mis-named audioUnitForTimePitch.)
    private var audioUnitForConverter: AudioUnit!
    private var audioUnitForOutput: AudioUnit!
    private var currentRenderReadOffset = UInt32(0)
    private var sourceNodeAudioFormat: AVAudioFormat?
    private var sampleSize = UInt32(MemoryLayout<Float>.size)
    private var outputLatency = TimeInterval(0)
    public weak var renderSource: OutputRenderSourceDelegate?

    /// System-level audio output latency.
    ///
    /// RE: stored field +0x50 (Forward addition) — written once in `init` via
    /// `str d8,[self+0x50]` from `[[AVAudioSession sharedInstance] outputLatency]`
    /// (0x1013f50dc). Cached at init time rather than re-read on every access.
    public private(set) var outputLatencySystem: TimeInterval = 0
    private var currentRender: AudioFrame? {
        didSet {
            if currentRender == nil {
                currentRenderReadOffset = 0
            }
        }
    }

    public func play() {
        AUGraphStart(graph)
    }

    public func pause() {
        AUGraphStop(graph)
    }

    public var playbackRate: Float {
        // The head/converter node is a FormatConverter whose subtype is NewTimePitch
        // (`aufc`/`nutp`), so rate is driven through kNewTimePitchParam_Rate on that unit.
        get {
            var playbackRate = AudioUnitParameterValue(0.0)
            AudioUnitGetParameter(audioUnitForConverter, kNewTimePitchParam_Rate, kAudioUnitScope_Global, 0, &playbackRate)
            return playbackRate
        }
        set {
            AudioUnitSetParameter(audioUnitForConverter, kNewTimePitchParam_Rate, kAudioUnitScope_Global, 0, newValue, 0)
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
        // RE getter 0x1013f4bd8 / setter 0x1013f4c64 (round 11): both operate uniformly on
        // the mixer Enable param (inID=1=kMultiChannelMixerParam_Enable, inScope=1=Input,
        // inElement=0) of the mixer unit at self+0x20. `isMuted` is the logical inverse of
        // the Enable value: getter returns `value == 0`; setter writes the XOR-inverted bit
        // (isMuted == true ⇒ Enable = 0).
        get {
            var value = AudioUnitParameterValue(1.0)
            AudioUnitGetParameter(audioUnitForMixer, kMultiChannelMixerParam_Enable, kAudioUnitScope_Input, 0, &value)
            return value == 0
        }
        set {
            // Enable = inverse of isMuted: muted ⇒ 0, unmuted ⇒ 1.
            let enable = AudioUnitParameterValue(newValue ? 0 : 1)
            AudioUnitSetParameter(audioUnitForMixer, kMultiChannelMixerParam_Enable, kAudioUnitScope_Input, 0, enable, 0)
        }
    }

    /// RE: 0x1013f4e3c (AudioGraphPlayer.init, 1.3.15)
    ///
    /// Builds the AUGraph and full DSP chain: NewAUGraph → graph; 4× AUGraphAddNode
    /// (converter/mixer/dynamics/output, descs byte-verified against
    /// 0x102ee93a0/93b0/9320/93c0); AUGraphOpen; 3× AUGraphConnectNodeInput wiring
    /// converter→dynamics→mixer→output; 4× AUGraphNodeInfo extracting the four units;
    /// AudioUnitAddRenderNotify on the OUTPUT unit; EnableIO on the CONVERTER unit;
    /// then caches AVAudioSession.outputLatency into outputLatencySystem (self+0x50).
    public init() {
        var newGraph: AUGraph!
        NewAUGraph(&newGraph)
        graph = newGraph
        var descriptionForConverter = AudioComponentDescription()
        descriptionForConverter.componentType = kAudioUnitType_FormatConverter
        descriptionForConverter.componentSubType = kAudioUnitSubType_NewTimePitch
        descriptionForConverter.componentManufacturer = kAudioUnitManufacturer_Apple
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
        var nodeForConverter = AUNode()
        var nodeForDynamicsProcessor = AUNode()
        var nodeForMixer = AUNode()
        var nodeForOutput = AUNode()
        AUGraphAddNode(graph, &descriptionForConverter, &nodeForConverter)
        AUGraphAddNode(graph, &descriptionForMixer, &nodeForMixer)
        AUGraphAddNode(graph, &descriptionForDynamicsProcessor, &nodeForDynamicsProcessor)
        AUGraphAddNode(graph, &descriptionForOutput, &nodeForOutput)
        AUGraphOpen(graph)
        AUGraphConnectNodeInput(graph, nodeForConverter, 0, nodeForDynamicsProcessor, 0)
        AUGraphConnectNodeInput(graph, nodeForDynamicsProcessor, 0, nodeForMixer, 0)
        AUGraphConnectNodeInput(graph, nodeForMixer, 0, nodeForOutput, 0)
        AUGraphNodeInfo(graph, nodeForConverter, &descriptionForConverter, &audioUnitForConverter)
        var audioUnitForDynamicsProcessor: AudioUnit?
        AUGraphNodeInfo(graph, nodeForDynamicsProcessor, &descriptionForDynamicsProcessor, &audioUnitForDynamicsProcessor)
        self.audioUnitForDynamicsProcessor = audioUnitForDynamicsProcessor!
        AUGraphNodeInfo(graph, nodeForMixer, &descriptionForMixer, &audioUnitForMixer)
        AUGraphNodeInfo(graph, nodeForOutput, &descriptionForOutput, &audioUnitForOutput)
        // Render-notify is attached to the OUTPUT unit (self+0x30), not the converter.
        addRenderNotify(audioUnit: audioUnitForOutput)
        var value = UInt32(1)
        // EnableIO is set on the CONVERTER (head) unit (self+0x28).
        AudioUnitSetProperty(audioUnitForConverter,
                             kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Output, 0,
                             &value,
                             UInt32(MemoryLayout<UInt32>.size))
        // Cache system output latency once (stored field +0x50). AVAudioSession is
        // iOS/tvOS-only; macOS has no session-level outputLatency, so it stays 0 there.
        #if !os(macOS)
        outputLatencySystem = AVAudioSession.sharedInstance().outputLatency
        #endif
    }

    public func prepare(audioFormat: AVAudioFormat) {
        if sourceNodeAudioFormat == audioFormat {
            return
        }
        sourceNodeAudioFormat = audioFormat
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setPreferredOutputNumberOfChannels(Int(audioFormat.channelCount))
        KSLog("[audio] set preferredOutputNumberOfChannels: \(audioFormat.channelCount)")
        #endif
        sampleSize = audioFormat.sampleSize
        var audioStreamBasicDescription = audioFormat.formatDescription.audioStreamBasicDescription
        let audioStreamBasicDescriptionSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let channelLayout = audioFormat.channelLayout?.layout
        for unit in [audioUnitForConverter, audioUnitForDynamicsProcessor, audioUnitForMixer, audioUnitForOutput] {
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
            if unit == audioUnitForConverter {
                // SetRenderCallback (prop 0x17) is installed on the converter/head unit (self+0x28).
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

    public func flush() {
        currentRender = nil
        // Refresh the cached system latency (self+0x50), mirroring AudioEnginePlayer.flush.
        #if !os(macOS)
        outputLatencySystem = AVAudioSession.sharedInstance().outputLatency
        #endif
    }

    deinit {
        AUGraphStop(graph)
        AUGraphUninitialize(graph)
        AUGraphClose(graph)
        DisposeAUGraph(graph)
    }
}

extension AudioGraphPlayer {
    /// RE: 0x1013f5b68 (renderCallback) — the AURenderCallbackStruct entry installed on
    /// the converter unit; retains self, wraps ioData, and tail-calls the fill body.
    private func renderCallbackStruct() -> AURenderCallbackStruct {
        var inputCallbackStruct = AURenderCallbackStruct()
        inputCallbackStruct.inputProcRefCon = Unmanaged.passUnretained(self).toOpaque()
        inputCallbackStruct.inputProc = { refCon, _, _, _, inNumberFrames, ioData in
            guard let ioData else {
                return noErr
            }
            let `self` = Unmanaged<AudioGraphPlayer>.fromOpaque(refCon).takeUnretainedValue()
            self.audioPlayerShouldInputData(ioData: UnsafeMutableAudioBufferListPointer(ioData), numberOfFrames: inNumberFrames)
            return noErr
        }
        return inputCallbackStruct
    }

    /// RE: 0x1013f5c30 (renderNotifyCallback) — the AudioUnitRenderNotify proc attached
    /// to the output unit; on kAudioUnitRenderAction_PostRender it drives the clock tap.
    private func addRenderNotify(audioUnit: AudioUnit) {
        AudioUnitAddRenderNotify(audioUnit, { refCon, ioActionFlags, inTimeStamp, _, _, _ in
            let `self` = Unmanaged<AudioGraphPlayer>.fromOpaque(refCon).takeUnretainedValue()
            autoreleasepool {
                if ioActionFlags.pointee.contains(.unitRenderAction_PostRender) {
                    self.audioPlayerDidRenderSample(sampleTimestamp: inTimeStamp.pointee)
                }
            }
            return noErr
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    /// RE: 0x1013f5d44 (fillAudioBuffers) — per-channel planar memmove from
    /// currentRender.data[] (frame+0x40) at currentRenderReadOffset (self+0x38), pulling
    /// the next AudioFrame via renderSource (self+0x58 weak + self+0x60 witness) when the
    /// current one is exhausted; zero-fills the remainder of each buffer on underrun; on a
    /// format mismatch reprepares on the main thread.
    private func audioPlayerShouldInputData(ioData: UnsafeMutableAudioBufferListPointer, numberOfFrames: UInt32) {
        var ioDataWriteOffset = 0
        var numberOfSamples = numberOfFrames
        while numberOfSamples > 0 {
            if currentRender == nil {
                currentRender = renderSource?.getAudioOutputRender()
            }
            guard let currentRender else {
                break
            }
            let residueLinesize = currentRender.numberOfSamples - currentRenderReadOffset
            guard residueLinesize > 0 else {
                self.currentRender = nil
                continue
            }
            if sourceNodeAudioFormat != currentRender.audioFormat {
                runOnMainThread { [weak self] in
                    guard let self else {
                        return
                    }
                    self.prepare(audioFormat: currentRender.audioFormat)
                }
                return
            }
            let framesToCopy = min(numberOfSamples, residueLinesize)
            let bytesToCopy = Int(framesToCopy * sampleSize)
            let offset = Int(currentRenderReadOffset * sampleSize)
            for i in 0 ..< min(ioData.count, currentRender.data.count) {
                if let source = currentRender.data[i], let destination = ioData[i].mData {
                    (destination + ioDataWriteOffset).copyMemory(from: source + offset, byteCount: bytesToCopy)
                }
            }
            numberOfSamples -= framesToCopy
            ioDataWriteOffset += bytesToCopy
            currentRenderReadOffset += framesToCopy
        }
        let sizeCopied = (numberOfFrames - numberOfSamples) * sampleSize
        for i in 0 ..< ioData.count {
            let sizeLeft = Int(ioData[i].mDataByteSize - sizeCopied)
            if sizeLeft > 0 {
                memset(ioData[i].mData! + Int(sizeCopied), 0, sizeLeft)
            }
        }
    }

    /// RE: 0x1013f45e8 (renderScheduling, via renderNotifyCallback 0x1013f5c30) — derives
    /// the current presentation CMTime from the frame timebase, applies the output-latency
    /// correction, and feeds it to renderSource.setAudio(time:position:).
    private func audioPlayerDidRenderSample(sampleTimestamp _: AudioTimeStamp) {
        if let currentRender {
            let currentPreparePosition = currentRender.timestamp + currentRender.duration * Int64(currentRenderReadOffset) / Int64(currentRender.numberOfSamples)
            if currentPreparePosition > 0 {
                var time = currentRender.timebase.cmtime(for: currentPreparePosition)
                if outputLatency != 0 {
                    time = time - CMTime(seconds: outputLatency, preferredTimescale: time.timescale)
                }
                renderSource?.setAudio(time: time, position: currentRender.position)
            }
        }
    }
}
