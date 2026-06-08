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

/// Raw `AudioUnit` API implementation. Lowest latency, NO processing chain.
/// Uses RemoteIO on iOS/tvOS and HALOutput on macOS.
///
/// RE: 0x1013f89e4 (AudioUnitPlayer.init, 1.3.15) — full disasm 0x1013f89e4–0x1013f8b58.
/// init creates EXACTLY ONE AudioUnit (the output unit, self+0x10) via the single
/// `AudioComponentInstanceNew` call site at 0x1013f8aec. There is NO varispeed unit and
/// NO mixer unit — no `AudioComponentInstanceNew` for either exists anywhere in the class.
/// Init-verified field layout:
///   self+0x10 = output AudioUnit (RemoteIO/HALOutput)
///   self+0x18 = currentRenderReadOffset (UInt32)
///   self+0x20 = sourceNodeAudioFormat (AVAudioFormat) — set by prepare @0x1013f8b5c, NOT a unit
///   self+0x28 = weak renderSource (swift_unknownObjectWeakInit)
///   self+0x48 = minDelayAfterPrepare (Double, 0.15 = 0x3fc3333333333333)
///   self+0x50 = isPlaying (Bool) — prepare stops/re-arms the output unit off this flag
///   self+0x54 = playbackRate (Float, 1.0f = 0x3f800000)
///   self+0x58 = isMuted (Bool)
///   self+0x68 = outputLatencySystem (Double) — AVAudioSession.outputLatency snapshot
///
/// `playbackRate` and `volume` are AudioOutput protocol requirements. This player has no
/// processing units to route them through, so they are backed as STORED properties (matching
/// the binary: no `AudioUnitGet/SetParameter` for rate/volume is emitted against self+0x10).
/// `isMuted` is enforced in software by zeroing the render buffer in the input callback.
public final class AudioUnitPlayer: AudioOutput {
    /// Output RemoteIO/HALOutput AudioUnit. (self+0x10) Created in `init`.
    /// RE: 0x1013f8aec (AudioComponentInstanceNew → self+0x10, EnableIO on input element).
    private var audioUnitForOutput: AudioUnit!

    private var currentRenderReadOffset = UInt32(0)

    /// Last-negotiated source format. (self+0x20)
    /// RE: 0x1013f8b5c (prepare) — `str param_1,[self+0x20]` after the NSObject `==` early-out;
    /// init leaves it nil (zeroed at 0x1013f89e4). This is the stored format, NOT a varispeed unit.
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

    /// Playback rate (AudioOutput requirement). Stored property, init default 1.0f. (self+0x54)
    ///
    /// RE: 0x1013f8a48 (AudioUnitPlayer.init, 1.3.15) — `str` of 0x3f800000 (1.0f) into self+0x54.
    /// This player has no varispeed unit (init makes only the output unit at self+0x10), so the
    /// rate is held as a stored scalar; there is no `AudioUnitGet/SetParameter` for it anywhere
    /// in the class. (Rate-via-unit lives in the sibling AudioEnginePlayer / graph players.)
    public var playbackRate: Float = 1

    /// Volume (AudioOutput requirement). Stored property, default 1.0.
    ///
    /// RE: 0x1013f89e4 (AudioUnitPlayer.init, 1.3.15) — the init default block writes no volume
    /// unit and emits no mixer-param call. With no MultiChannelMixer in this player, volume is a
    /// plain stored scalar; the render path copies samples verbatim (mute aside). Mixer-backed
    /// volume is an AudioEnginePlayer/graph-player concern, not this raw-AudioUnit path.
    public var volume: Float = 1

    /// Mute state (self+0x58). Implemented by writing zeros in the render callback when set,
    /// matching the binary (no dedicated mute unit).
    /// RE: 0x1013f89e4 (AudioUnitPlayer.init, 1.3.15) — Bool zeroed at self+0x58.
    public var isMuted: Bool = false

    /// Per-flush refreshed output latency (iOS/tvOS), distinct from the init snapshot
    /// `outputLatencySystem`. Refreshed in `init` and `flush()`.
    private var outputLatency = TimeInterval(0)

    /// RE: 0x1013f89e4 (AudioUnitPlayer.init, 1.3.15) — full disasm 0x1013f89e4–0x1013f8b58.
    /// Sets the default-field block (minDelayAfterPrepare = 0.15 @+0x48, playbackRate = 1.0f
    /// @+0x54, isMuted = false @+0x58, outputLatencySystem snapshot @+0x68) and weak-inits
    /// renderSource @+0x28, then creates EXACTLY ONE AudioUnit — the output unit @+0x10 — via the
    /// single `AudioComponentInstanceNew` call site (0x1013f8aec), enabling IO on its input
    /// element. self+0x20 (the source format) is zeroed here and filled by `prepare`. There is no
    /// varispeed or mixer unit anywhere in the class.
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
        // RE: 0x1013f8b18 — AudioUnitSetProperty(unit, 0x7d3 = kAudioOutputUnitProperty_EnableIO,
        // scope 2 = kAudioUnitScope_Output, element 0, &1, 4). EnableIO is enabled on the OUTPUT
        // element of the output-only unit (scope register w2 = #0x2 at 0x1013f8b0c).
        AudioUnitSetProperty(audioUnitForOutput,
                             kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Output, 0,
                             &value,
                             UInt32(MemoryLayout<UInt32>.size))
    }

    /// Negotiates the output unit for a new source format and (re)initializes it.
    ///
    /// RE: 0x1013f8b5c (AudioUnitPlayer.prepare, 1.3.15). The binary, in order:
    ///   • early-outs when the stored format (self+0x20) is NSObject-`==` to the incoming one;
    ///   • stores the new format at self+0x20 (releasing the old);
    ///   • if isPlaying (self+0x50 == 1) calls `AudioOutputUnitStop` then clears the flag, and
    ///     `AudioUnitUninitialize`, before reconfiguring;
    ///   • `setPreferredOutputNumberOfChannels:` / `setPreferredSampleRate:` on the shared
    ///     `AVAudioSession` (RemoteIO platforms);
    ///   • `AudioUnitSetProperty` StreamFormat (8) / AudioChannelLayout (0x13) /
    ///     SetRenderCallback (0x17) on the OUTPUT unit (self+0x10), all scope Input (1);
    ///   • `AudioUnitAddRenderNotify` + `AudioUnitInitialize`.
    /// Crucially it touches ONLY self+0x10 — there is no varispeed/mixer unit to configure.
    public func prepare(audioFormat: AVAudioFormat) {
        let now = CACurrentMediaTime()
        guard now - lastPrepareTime >= minDelayAfterPrepare else { return }
        lastPrepareTime = now
        if sourceNodeAudioFormat == audioFormat {
            return
        }
        sourceNodeAudioFormat = audioFormat
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
    /// class DESTROY vtable slot (0x1013f936c) ahead of `__deallocating_deinit` (0x1013fa094).
    /// The Swift `deinit` + ARC release of the single output-unit handle is the idiomatic
    /// equivalent of that {destroy, dealloc-deinit} pair. There are no rate/mixer units to
    /// dispose — the binary's dealloc-deinit only `swift_release`s self+0x10/+0x18 and deallocs.
    /// RE: 0x1013f936c (DESTROY slot: AudioUnitUninitialize(self+0x10)) +
    ///     0x1013fa094 (__deallocating_deinit: swift_release self+0x10/+0x18, deallocObject).
    deinit {
        if let audioUnitForOutput {
            AudioUnitUninitialize(audioUnitForOutput)
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
