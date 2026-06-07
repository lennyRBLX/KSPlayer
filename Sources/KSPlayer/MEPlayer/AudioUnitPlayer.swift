//
//  AudioUnitPlayer.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/16.
//

import AudioToolbox
import AVFAudio
import CoreAudio
import QuartzCore

/// Raw `AudioUnit` API implementation. Lowest latency, no processing chain.
/// Uses RemoteIO on iOS/tvOS and HALOutput on macOS.
///
/// RE: 0x1013f89e4 (AudioUnitPlayer.init, 1.3.15) — full disasm 0x1013f89e4–0x1013f8b58.
/// Field layout (init-verified offsets): outputUnit @+0x10, rateUnit @+0x20 (varispeed),
/// volumeUnit @+0x28 (MultiChannelMixer), minDelayAfterPrepare @+0x48 (0.15),
/// playbackRate @+0x54 (1.0f), isMuted @+0x58, outputLatencySystem @+0x68.
public final class AudioUnitPlayer: AudioOutput {
    /// Output RemoteIO/HALOutput AudioUnit. (self+0x10) Created in `init`.
    /// RE: 0x1013f8aec (AudioComponentInstanceNew → self+0x10, EnableIO on input element).
    private var audioUnitForOutput: AudioUnit!

    /// Varispeed AudioUnit handle backing `playbackRate`. (self+0x20)
    /// Rate is applied at the unit level via `AudioUnitGet/SetParameter(inID: 0, inScope: 1)`.
    /// `init` zeroes this; the unit is created lazily in `setupProcessingUnits()`.
    /// RE: rate getter 0x1013f49d0 / setter 0x1013f4a50 (both `ldr x0,[self+0x20]`, scope 1).
    private var rateUnit: AudioUnit?

    /// MultiChannelMixer AudioUnit handle backing `volume`. (self+0x28)
    /// Volume is applied at the unit level via `kMultiChannelMixerParam_Volume`
    /// (`AudioUnitGet/SetParameter(inID: 0, inScope: 0)`).
    /// `init` zeroes this; the unit is created lazily in `setupProcessingUnits()`.
    /// RE: volume getter 0x1013f47c8 / setter 0x1013f4848 (scope 0, param 14 = volume).
    private var volumeUnit: AudioUnit?

    private var currentRenderReadOffset = UInt32(0)
    private var sourceNodeAudioFormat: AVAudioFormat?
    private var sampleSize = UInt32(MemoryLayout<Float>.size)
    public weak var renderSource: OutputRenderSourceDelegate?
    private var currentRender: AudioFrame? {
        didSet {
            if currentRender == nil {
                currentRenderReadOffset = 0
            }
        }
    }

    /// Timestamp of last `prepare()` call for debounce protection.
    /// RE: 0x1013f89e4 (AudioUnitPlayer field, 1.3.15) — debounce pair with `minDelayAfterPrepare`.
    private var lastPrepareTime: TimeInterval = 0

    /// Minimum delay between `prepare()` calls (seconds). (self+0x48, Double)
    /// RE: 0x1013f8a38 (AudioUnitPlayer.init, 1.3.15) — init writes 0.15 (0x3fc3333333333333).
    private let minDelayAfterPrepare: TimeInterval = 0.15

    /// System-level audio output latency, snapshotted once from
    /// `AVAudioSession.outputLatency` at construction. (self+0x68, Double)
    ///
    /// RE: 0x1013f8ab8 (AudioUnitPlayer.init, 1.3.15) — `str d8,[self+0x68]`; SEL 0x103c52e98
    /// resolves to the string "outputLatency". This is a STORED init snapshot, not a live
    /// re-query (the per-flush refreshed value is the separate `outputLatency` field below).
    public private(set) var outputLatencySystem: Double = 0

    private var isPlaying = false
    public func play() {
        if !isPlaying {
            isPlaying = true
            AudioOutputUnitStart(audioUnitForOutput)
        }
    }

    public func pause() {
        if isPlaying {
            isPlaying = false
            AudioOutputUnitStop(audioUnitForOutput)
        }
    }

    /// Playback rate. Backing default 1.0f stored at self+0x54; get/set are applied at the
    /// unit level through the varispeed `rateUnit` (self+0x20, scope 1, param id 0).
    ///
    /// RE: getter 0x1013f49d0 / setter 0x1013f4a50 (1.3.15) — both `AudioUnitGet/SetParameter`
    /// on the rate unit with `inScope = kAudioUnitScope_Input` (1). The stored 1.0f default is
    /// init-written at self+0x54 (0x1013f8a48).
    public var playbackRate: Float {
        get {
            guard let rateUnit else { return storedPlaybackRate }
            var value = AudioUnitParameterValue(storedPlaybackRate)
            AudioUnitGetParameter(rateUnit, 0, kAudioUnitScope_Input, 0, &value)
            return Float(value)
        }
        set {
            storedPlaybackRate = newValue
            guard let rateUnit else { return }
            AudioUnitSetParameter(rateUnit, 0, kAudioUnitScope_Input, 0, AudioUnitParameterValue(newValue), 0)
        }
    }

    /// Stored playback-rate default (self+0x54, init 1.0f). Serves as the backing value before
    /// the varispeed unit exists, and as the cached scalar the unit get/set round-trips.
    private var storedPlaybackRate: Float = 1

    /// Volume. Applied at the unit level through the MultiChannelMixer `volumeUnit`
    /// (self+0x28, scope 0, `kMultiChannelMixerParam_Volume`).
    ///
    /// RE: getter 0x1013f47c8 / setter 0x1013f4848 (1.3.15) — `AudioUnitGet/SetParameter` on the
    /// mixer unit with `inID` (0) and `inScope = kAudioUnitScope_Global` (0). The binary passes
    /// scope literal 0 (Global), NOT Output (2): disasm shows
    /// `_AudioUnitGet/SetParameter(unit=self+0x28, inID=0, inScope=0, inElement=0, …)`.
    public var volume: Float {
        get {
            guard let volumeUnit else { return storedVolume }
            var value = AudioUnitParameterValue(storedVolume)
            AudioUnitGetParameter(volumeUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Global, 0, &value)
            return Float(value)
        }
        set {
            storedVolume = newValue
            guard let volumeUnit else { return }
            AudioUnitSetParameter(volumeUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Global, 0, AudioUnitParameterValue(newValue), 0)
        }
    }

    /// Stored volume backing value, used before the mixer unit exists.
    private var storedVolume: Float = 1

    /// Mute state (self+0x58). Implemented by writing zeros in the render callback when set,
    /// matching the binary (no dedicated mute unit).
    /// RE: 0x1013f89e4 (AudioUnitPlayer.init, 1.3.15) — Bool zeroed at self+0x58.
    public var isMuted: Bool = false

    /// Per-flush refreshed output latency (iOS/tvOS), distinct from the init snapshot
    /// `outputLatencySystem`. Refreshed in `init` and `flush()`.
    private var outputLatency = TimeInterval(0)

    /// RE: 0x1013f89e4 (AudioUnitPlayer.init, 1.3.15) — full disasm.
    /// Sets the default-field block (minDelayAfterPrepare = 0.15, playbackRate = 1.0f,
    /// isMuted = false, outputLatencySystem snapshot) and creates ONLY the output unit.
    /// The rate (self+0x20) and mixer (self+0x28) units are NOT created here — a separate
    /// setup path (`setupProcessingUnits()`) builds them.
    public init() {
        // Snapshot the system output latency once (Forward field self+0x68).
        // RE: 0x1013f8ab8 — [[AVAudioSession sharedInstance] outputLatency].
        #if !os(macOS)
        // RemoteIO platforms (iOS/tvOS) expose AVAudioSession; macOS HAL has no session.
        outputLatencySystem = AVAudioSession.sharedInstance().outputLatency
        outputLatency = AVAudioSession.sharedInstance().outputLatency
        #else
        outputLatencySystem = 0
        #endif

        var descriptionForOutput = AudioComponentDescription()
        descriptionForOutput.componentType = kAudioUnitType_Output
        descriptionForOutput.componentManufacturer = kAudioUnitManufacturer_Apple
        #if os(macOS)
        // HALOutput is the system output unit on macOS (no RemoteIO).
        descriptionForOutput.componentSubType = kAudioUnitSubType_HALOutput
        #else
        // RemoteIO is the low-latency hardware I/O unit on iOS/tvOS.
        descriptionForOutput.componentSubType = kAudioUnitSubType_RemoteIO
        #endif
        let nodeForOutput = AudioComponentFindNext(nil, &descriptionForOutput)
        AudioComponentInstanceNew(nodeForOutput!, &audioUnitForOutput)
        var value = UInt32(1)
        // RE: 0x1013f8aec — AudioUnitSetProperty(unit, 0x7d3 = kAudioOutputUnitProperty_EnableIO,
        // scope 2 = kAudioUnitScope_Input, element 0, &1, 4). EnableIO is set on the INPUT element.
        AudioUnitSetProperty(audioUnitForOutput,
                             kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Input, 0,
                             &value,
                             UInt32(MemoryLayout<UInt32>.size))
    }

    /// Lazily creates the varispeed (`rateUnit`, self+0x20) and MultiChannelMixer
    /// (`volumeUnit`, self+0x28) processing units and pushes the cached `playbackRate`/`volume`
    /// onto them. `init` deliberately leaves both nil (it only creates the output unit); the
    /// binary defers their creation to a separate setup path (residual in the doc), which we
    /// anchor at the first `prepare(audioFormat:)`.
    ///
    /// Kept as a distinct step from the output-unit creation in `init` per the API-surface
    /// preservation rule: rate and volume are driven through two SEPARATE unit handles, not
    /// folded into the output unit.
    private func setupProcessingUnits() {
        if rateUnit == nil {
            var varispeedDescription = AudioComponentDescription()
            varispeedDescription.componentType = kAudioUnitType_FormatConverter
            varispeedDescription.componentSubType = kAudioUnitSubType_Varispeed
            varispeedDescription.componentManufacturer = kAudioUnitManufacturer_Apple
            if let component = AudioComponentFindNext(nil, &varispeedDescription) {
                var unit: AudioUnit?
                AudioComponentInstanceNew(component, &unit)
                rateUnit = unit
                if let rateUnit {
                    // Push the cached rate (self+0x54) onto the freshly created unit.
                    AudioUnitSetParameter(rateUnit, 0, kAudioUnitScope_Input, 0, AudioUnitParameterValue(storedPlaybackRate), 0)
                }
            }
        }
        if volumeUnit == nil {
            var mixerDescription = AudioComponentDescription()
            mixerDescription.componentType = kAudioUnitType_Mixer
            mixerDescription.componentSubType = kAudioUnitSubType_MultiChannelMixer
            mixerDescription.componentManufacturer = kAudioUnitManufacturer_Apple
            if let component = AudioComponentFindNext(nil, &mixerDescription) {
                var unit: AudioUnit?
                AudioComponentInstanceNew(component, &unit)
                volumeUnit = unit
                if let volumeUnit {
                    // Push the cached volume (self+0x54-adjacent stored value) onto the mixer.
                    // Scope 0 (Global) to match the binary's volume setter at 0x1013f4848.
                    AudioUnitSetParameter(volumeUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Global, 0, AudioUnitParameterValue(storedVolume), 0)
                }
            }
        }
    }

    public func prepare(audioFormat: AVAudioFormat) {
        let now = CACurrentMediaTime()
        guard now - lastPrepareTime >= minDelayAfterPrepare else { return }
        lastPrepareTime = now
        if sourceNodeAudioFormat == audioFormat {
            return
        }
        sourceNodeAudioFormat = audioFormat
        // Create the rate/mixer units on first prepare (init leaves them nil).
        setupProcessingUnits()
        #if !os(macOS)
        // AVAudioSession channel negotiation only exists on RemoteIO platforms.
        try? AVAudioSession.sharedInstance().setPreferredOutputNumberOfChannels(Int(audioFormat.channelCount))
        KSLog("[audio] set preferredOutputNumberOfChannels: \(audioFormat.channelCount)")
        #endif
        sampleSize = audioFormat.sampleSize
        var audioStreamBasicDescription = audioFormat.formatDescription.audioStreamBasicDescription
        AudioUnitSetProperty(audioUnitForOutput,
                             kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Input, 0,
                             &audioStreamBasicDescription,
                             UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        let channelLayout = audioFormat.channelLayout?.layout
        AudioUnitSetProperty(audioUnitForOutput,
                             kAudioUnitProperty_AudioChannelLayout,
                             kAudioUnitScope_Input, 0,
                             channelLayout,
                             UInt32(MemoryLayout<AudioChannelLayout>.size))
        var inputCallbackStruct = renderCallbackStruct()
        AudioUnitSetProperty(audioUnitForOutput,
                             kAudioUnitProperty_SetRenderCallback,
                             kAudioUnitScope_Input, 0,
                             &inputCallbackStruct,
                             UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        addRenderNotify(audioUnit: audioUnitForOutput)
        AudioUnitInitialize(audioUnitForOutput)
    }

    public func flush() {
        currentRender = nil
        #if !os(macOS)
        outputLatency = AVAudioSession.sharedInstance().outputLatency
        #endif
    }

    /// Teardown. The load-bearing step is `AudioUnitUninitialize(outputUnit)` — the binary's
    /// class DESTROY vtable slot (0x1013f936c) before `__deallocating_deinit` (0x1013fa094).
    /// The Swift-level `deinit` + ARC release of the unit handles is the idiomatic equivalent of
    /// that {destroy, dealloc-deinit} pair. Also disposes the lazily-created rate/mixer units.
    /// RE: 0x1013f936c (DESTROY slot: AudioUnitUninitialize(self+0x10)) +
    ///     0x1013fa094 (__deallocating_deinit: swift_release self+0x10/+0x18, deallocObject).
    deinit {
        if let audioUnitForOutput {
            AudioUnitUninitialize(audioUnitForOutput)
        }
        if let rateUnit {
            AudioComponentInstanceDispose(rateUnit)
        }
        if let volumeUnit {
            AudioComponentInstanceDispose(volumeUnit)
        }
    }
}

extension AudioUnitPlayer {
    /// One-time active-renderer-class check used by renderer selection.
    ///
    /// RE: 0x1013a03b8 (AudioUnitPlayer.singletonInit, 1.3.15). Ensures
    /// `AudioEnginePlayer.singletonInit` has run (the sole writer of the active-class global
    /// `DAT_104458738`, via `swift_once(&DAT_103d060b0)`), then READS that global and compares
    /// it against AudioUnitPlayer's class metadata (`FUN_1013f9a4c` = `_objc_opt_self`),
    /// returning true iff the active `audioPlayerType` is AudioUnitPlayer.
    ///
    /// v5.3 G-R1-1: this does NOT write the global — it is a read-and-compare. The Swift
    /// equivalent of `DAT_104458738` is the static `KSOptions.audioPlayerType` existential.
    ///
    /// Note: the binary first runs `AudioEnginePlayer.singletonInit` (the sole writer of the
    /// active-class global) via `swift_once` to guarantee the global is seeded before the
    /// read. In Swift, `KSOptions.audioPlayerType` is a statically-initialized stored type, so
    /// the ordering guarantee is implicit and no prior one-time init is required here. If an
    /// explicit `AudioEnginePlayer.singletonInit()` is added to that cluster's file, call it
    /// first (see CROSS-FILE note in the reconstruction report).
    @discardableResult
    static func singletonInit() -> Bool {
        KSOptions.audioPlayerType == AudioUnitPlayer.self
    }

    private func renderCallbackStruct() -> AURenderCallbackStruct {
        var inputCallbackStruct = AURenderCallbackStruct()
        inputCallbackStruct.inputProcRefCon = Unmanaged.passUnretained(self).toOpaque()
        inputCallbackStruct.inputProc = { refCon, _, _, _, inNumberFrames, ioData in
            guard let ioData else {
                return noErr
            }
            let `self` = Unmanaged<AudioUnitPlayer>.fromOpaque(refCon).takeUnretainedValue()
            self.audioPlayerShouldInputData(ioData: UnsafeMutableAudioBufferListPointer(ioData), numberOfFrames: inNumberFrames)
            return noErr
        }
        return inputCallbackStruct
    }

    private func addRenderNotify(audioUnit: AudioUnit) {
        AudioUnitAddRenderNotify(audioUnit, { refCon, ioActionFlags, inTimeStamp, _, _, _ in
            let `self` = Unmanaged<AudioUnitPlayer>.fromOpaque(refCon).takeUnretainedValue()
            autoreleasepool {
                if ioActionFlags.pointee.contains(.unitRenderAction_PostRender) {
                    self.audioPlayerDidRenderSample(sampleTimestamp: inTimeStamp.pointee)
                }
            }
            return noErr
        }, Unmanaged.passUnretained(self).toOpaque())
    }

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
                    if isMuted {
                        memset(destination + ioDataWriteOffset, 0, bytesToCopy)
                    } else {
                        (destination + ioDataWriteOffset).copyMemory(from: source + offset, byteCount: bytesToCopy)
                    }
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
