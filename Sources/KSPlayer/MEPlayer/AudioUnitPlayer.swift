//
//  AudioUnitPlayer.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/16.
//
//  Forward re-parents this onto AudioBaseOutput (binary superclass @0x1044e84c8),
//  which now owns the render engine — renderSource / currentRender / sourceNodeAudioFormat
//  / the render lock / the sample-copy loop (audioPlayerShouldInputData) and the audio
//  clock (audioPlayerDidRenderSample). What is left here is the raw output AudioUnit.
//
//  Binary: descriptor @0x1039eed40, super=AudioBaseOutput, conformances=[AudioOutput,
//  FrameOutput]. Own vtable is {Init} (VTableSize=1) + an override table — current-swiftc
//  emits `override` records directly, so there is no vtable-numbering pin. Own stored fields
//  (dump_field_bindings, field-record order): audioUnitForOutput@0x50, lastPrepareTime@0x58,
//  minDelayAfterPrepare@0x60, isPlaying@0x68, playbackRate@0x6c, isMuted@0x70. Inherited
//  storage is 0x10..0x4f. `volume` carries no field record — it is computed onto the unit.
//
//  let/var below are the __swift5_fieldmd IsVar flags (dump_field_bindings.py AudioUnitPlayer):
//  minDelayAfterPrepare is a `let`, so it earns no vtable triple and its 0.15 constant-folds
//  into play() (see below).

import AudioToolbox
import AVFAudio
import CoreAudio
import CoreMedia

public class AudioUnitPlayer: AudioBaseOutput, AudioOutput {
    private var audioUnitForOutput: AudioUnit!
    // Written by prepare(audioFormat:), read by play(): the timestamp the play()
    // debounce measures against (the "从多声道切换到2声道马上调用start会不生效" workaround —
    // a play() within minDelayAfterPrepare of the last prepare is deferred).
    var lastPrepareTime: Double = 0
    // ⚑ `let` (IsVar clear), init 0.15 (=0x3fc3333333333333). Because it is a `let`, every
    // read constant-folds — play() compares against an inline 0.15 and this field is loaded
    // nowhere in the binary. Access is underdetermined (a `let` carries no vtable entry at any
    // level); `private` matches its role.
    private let minDelayAfterPrepare = 0.15
    private var isPlaying = false
    public var playbackRate: Float = 1
    public var isMuted: Bool = false {
        didSet {
            // Mirror into the inherited flag the sample-copy loop reads (setter writes
            // self+0x70 then self+0x28). memsetZero was made `internal` on AudioBaseOutput
            // for this cross-file write.
            memsetZero = isMuted
        }
    }

    // volume is COMPUTED onto the output unit (no field record). id 14 / scope 1 / element 0
    // are pinned from the binary's AudioUnitGet/SetParameter arguments (kHALOutputParam_Volume
    // == 14, kAudioUnitScope_Input == 1).
    public var volume: Float {
        get {
            var value = AudioUnitParameterValue(0)
            AudioUnitGetParameter(audioUnitForOutput, kHALOutputParam_Volume, kAudioUnitScope_Input, 0, &value)
            return value
        }
        set {
            AudioUnitSetParameter(audioUnitForOutput, kHALOutputParam_Volume, kAudioUnitScope_Input, 0, newValue, 0)
        }
    }

    // init @0x101a15270 (alloc entry 0x101a1523c). `required override init()`: overrides
    // AudioBaseOutput.init() and satisfies AudioOutput's init requirement. super.init() seeds
    // the base storage (incl. outputLatencySystem from AVAudioSession on iOS/tvOS), which is
    // why the upstream `outputLatency = AVAudioSession...` line is gone from here.
    //
    // The alloc entry is swift_allocObject(size: 0x71, alignMask: 7) then `bl 0x101a15270`
    // and `mov x0,x20 ; ret` — 13 instructions, identical in shape to the other two audio
    // players. 0x71 over the shared 0x50 base leaves 0x21, which is exactly the six own
    // fields in the header's layout (8+8+8+1, pad, 4+1 ⇒ 0x50…0x70 inclusive). ARITY 0 is
    // proven, not assumed: across those 13 instructions the entry reads only x20 (the
    // metatype), and w1/w2 are written with the size and align mask rather than read. No
    // argument register is read anywhere, which refutes a DEFAULTED parameter as well as a
    // declared one — a default-argument generator runs at the CALL site, so its value would
    // still have to arrive in an argument register here.
    //
    // super.init() runs FIRST, exactly as written: the body seeds the six own fields from
    // their declared defaults, then falls straight into the inlined base storage zeroing,
    // and only then builds the description. That ordering is legal precisely because every
    // own field has a default, so phase 1 is complete before the super call.
    //
    // descriptionForOutput is a folded compile-time constant: 16 bytes @0x103564590 —
    // 'auou' 'rioc' 'appl' 0 (type, subType, manufacturer, flags), byte-verified — with
    // componentFlagsMask stored as a separate inline zero. 'rioc' is RemoteIO, i.e. the
    // `#else` arm below is the one this build compiled; the macOS `kAudioUnitSubType_
    // HALOutput` arm is unverifiable from this binary, not contradicted.
    public required override init() {
        super.init()
        var descriptionForOutput = AudioComponentDescription()
        descriptionForOutput.componentType = kAudioUnitType_Output
        descriptionForOutput.componentManufacturer = kAudioUnitManufacturer_Apple
        #if os(macOS)
        descriptionForOutput.componentSubType = kAudioUnitSubType_HALOutput
        #else
        descriptionForOutput.componentSubType = kAudioUnitSubType_RemoteIO
        #endif
        let nodeForOutput = AudioComponentFindNext(nil, &descriptionForOutput)
        AudioComponentInstanceNew(nodeForOutput!, &audioUnitForOutput)
        var value = UInt32(1)
        AudioUnitSetProperty(audioUnitForOutput,
                             kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Output, 0,
                             &value,
                             UInt32(MemoryLayout<UInt32>.size))
    }

    // prepare(audioFormat:) @0x101a153cc — OVERRIDES AudioBaseOutput's slot-28 hook. Forward's
    // evolution over the flat body: a running unit is stopped and uninitialized before
    // reconfiguring; the preferred sample rate is set as well as the channel count; the channel
    // layout comes from CMAudioFormatDescriptionGetChannelLayout rather than
    // channelLayout?.layout; lastPrepareTime is stamped; and the trailing restart defers to
    // play() (which owns the debounce) via a @MainActor Task rather than calling start() here.
    override public func prepare(audioFormat: AVAudioFormat) {
        if sourceNodeAudioFormat == audioFormat {
            return
        }
        let isRunning = isPlaying
        if isPlaying {
            isPlaying = false
            AudioOutputUnitStop(audioUnitForOutput)
        }
        AudioUnitUninitialize(audioUnitForOutput)
        sourceNodeAudioFormat = audioFormat
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setPreferredOutputNumberOfChannels(Int(audioFormat.channelCount))
        try? AVAudioSession.sharedInstance().setPreferredSampleRate(audioFormat.sampleRate)
        KSLog("[audio] set preferredOutputNumberOfChannels=\(audioFormat.channelCount) outputNumberOfChannels=\(AVAudioSession.sharedInstance().outputNumberOfChannels)")
        #endif
        var audioStreamBasicDescription = audioFormat.formatDescription.audioStreamBasicDescription
        AudioUnitSetProperty(audioUnitForOutput,
                             kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Input, 0,
                             &audioStreamBasicDescription,
                             UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        var layoutSize = 0
        if let channelLayout = CMAudioFormatDescriptionGetChannelLayout(audioFormat.formatDescription, sizeOut: &layoutSize) {
            AudioUnitSetProperty(audioUnitForOutput,
                                 kAudioUnitProperty_AudioChannelLayout,
                                 kAudioUnitScope_Input, 0,
                                 channelLayout,
                                 UInt32(layoutSize))
        }
        var inputCallbackStruct = renderCallbackStruct()
        AudioUnitSetProperty(audioUnitForOutput,
                             kAudioUnitProperty_SetRenderCallback,
                             kAudioUnitScope_Input, 0,
                             &inputCallbackStruct,
                             UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        addRenderNotify(audioUnit: audioUnitForOutput)
        AudioUnitInitialize(audioUnitForOutput)
        lastPrepareTime = CFAbsoluteTimeGetCurrent()
        if isRunning {
            nonisolated(unsafe) weak var weakSelf = self
            Task { @MainActor in
                weakSelf?.play()
            }
        }
    }

    // play() @0x101a14c54 (FrameOutput requirement 0): a play() that lands within
    // minDelayAfterPrepare of the last prepare is deferred by the remainder of that window.
    // The comparison fuses to an inline 0.15 because minDelayAfterPrepare is a `let`.
    public func play() {
        if !isPlaying {
            let elapsed = CFAbsoluteTimeGetCurrent() - lastPrepareTime
            if lastPrepareTime > 0, elapsed < minDelayAfterPrepare {
                nonisolated(unsafe) weak var weakSelf = self
                DispatchQueue.main.asyncAfter(deadline: .now() + (minDelayAfterPrepare - elapsed)) { @MainActor in
                    weakSelf?.doPlay()
                }
            } else {
                doPlay()
            }
        }
    }

    // The actual start, shared by play()'s immediate path and the deferred @MainActor closure
    // (fully inlined at both sites, so it carries no distinct address). prepareRender() is the
    // inherited AudioBaseOutput hook @0x101a116c0.
    private func doPlay() {
        if !isPlaying {
            isPlaying = true
            prepareRender()
            AudioOutputUnitStart(audioUnitForOutput)
        }
    }

    // pause() @0x101a150dc (FrameOutput requirement 1).
    public func pause() {
        if isPlaying {
            isPlaying = false
            AudioOutputUnitStop(audioUnitForOutput)
        }
    }

    // stop() @0x101a15b28 (FrameOutput requirement 3). New in Forward — the flat class did this
    // in deinit; that deinit is gone (AudioUnitUninitialize has exactly two callers now, prepare
    // and stop). flush() is NOT overridden: FrameOutput requirement 2 resolves to the inherited
    // AudioBaseOutput.flush @0x101a117b0.
    public func stop() {
        AudioUnitUninitialize(audioUnitForOutput)
    }
}

extension AudioUnitPlayer {
    private func renderCallbackStruct() -> AURenderCallbackStruct {
        var inputCallbackStruct = AURenderCallbackStruct()
        inputCallbackStruct.inputProcRefCon = Unmanaged.passUnretained(self).toOpaque()
        // inputProc @0x101a15f18 — calls the INHERITED audioPlayerShouldInputData(ioData:); the
        // frame count comes from the buffer's own mDataByteSize, so inNumberFrames is unused.
        inputCallbackStruct.inputProc = { refCon, _, _, _, _, ioData in
            guard let ioData else {
                return noErr
            }
            let `self` = Unmanaged<AudioUnitPlayer>.fromOpaque(refCon).takeUnretainedValue()
            self.audioPlayerShouldInputData(ioData: UnsafeMutableAudioBufferListPointer(ioData))
            return noErr
        }
        return inputCallbackStruct
    }

    private func addRenderNotify(audioUnit: AudioUnit) {
        // renderNotify @0x101a15fc0 — calls the INHERITED audioPlayerDidRenderSample() on
        // PostRender; Forward drops the flat body's unused sampleTimestamp argument.
        AudioUnitAddRenderNotify(audioUnit, { refCon, ioActionFlags, _, _, _, _ in
            let `self` = Unmanaged<AudioUnitPlayer>.fromOpaque(refCon).takeUnretainedValue()
            autoreleasepool {
                if ioActionFlags.pointee.contains(.unitRenderAction_PostRender) {
                    self.audioPlayerDidRenderSample()
                }
            }
            return noErr
        }, Unmanaged.passUnretained(self).toOpaque())
    }
}
