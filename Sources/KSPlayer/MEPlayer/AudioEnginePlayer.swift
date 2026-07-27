//
//  AudioEnginePlayer.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/11.
//

import AVFoundation
import CoreAudio

public protocol AudioOutput: FrameOutput {
    var playbackRate: Float { get set }
    var volume: Float { get set }
    var isMuted: Bool { get set }
    init()
    func prepare(audioFormat: AVAudioFormat)
}

public protocol AudioDynamicsProcessor {
    var audioUnitForDynamicsProcessor: AudioUnit { get }
}

public extension AudioDynamicsProcessor {
    var attackTime: Float {
        get {
            var value = AudioUnitParameterValue(1.0)
            AudioUnitGetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, &value)
            return value
        }
        set {
            AudioUnitSetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, AudioUnitParameterValue(newValue), 0)
        }
    }

    var releaseTime: Float {
        get {
            var value = AudioUnitParameterValue(1.0)
            AudioUnitGetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, &value)
            return value
        }
        set {
            AudioUnitSetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, AudioUnitParameterValue(newValue), 0)
        }
    }

    var threshold: Float {
        get {
            var value = AudioUnitParameterValue(1.0)
            AudioUnitGetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, &value)
            return value
        }
        set {
            AudioUnitSetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, AudioUnitParameterValue(newValue), 0)
        }
    }

    var expansionRatio: Float {
        get {
            var value = AudioUnitParameterValue(1.0)
            AudioUnitGetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, &value)
            return value
        }
        set {
            AudioUnitSetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, AudioUnitParameterValue(newValue), 0)
        }
    }

    var overallGain: Float {
        get {
            var value = AudioUnitParameterValue(1.0)
            AudioUnitGetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, &value)
            return value
        }
        set {
            AudioUnitSetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, AudioUnitParameterValue(newValue), 0)
        }
    }
}

public final class AudioEngineDynamicsPlayer: AudioEnginePlayer, AudioDynamicsProcessor {
    private let dynamicsProcessor = AVAudioUnitEffect(audioComponentDescription:
        AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                  componentSubType: kAudioUnitSubType_DynamicsProcessor,
                                  componentManufacturer: kAudioUnitManufacturer_Apple,
                                  componentFlags: 0,
                                  componentFlagsMask: 0))
    public var audioUnitForDynamicsProcessor: AudioUnit {
        dynamicsProcessor.audioUnit
    }

    override func audioNodes() -> [AVAudioNode] {
        var nodes: [AVAudioNode] = [dynamicsProcessor]
        nodes.append(contentsOf: super.audioNodes())
        return nodes
    }

    public required init() {
        super.init()
        engine.attach(dynamicsProcessor)
    }
}

// Forward re-parents this class onto AudioBaseOutput, which now owns the manual
// AVAudioSourceNode render engine (renderSource / currentRender / the render lock /
// the sample-copy loop). What is left here is the AVAudioEngine graph itself.
//
// Binary: metadata @0x1044e7be0, descriptor @0x1039ee768, superclass @meta+0x08 =
// 0x1044e84c8 = AudioBaseOutput, conformances = [AudioOutput, FrameOutput],
// instanceSize 0x7c. Own stored fields occupy 0x50..0x7b — the metadata field-offset
// vector @0x1044e7d80 reads exactly [0x50,0x58,0x60,0x68,0x70,0x78], and volume@0x78
// runs to instanceSize 0x7c, i.e. 4 bytes (Float). Inherited storage is 0x10..0x4f.
//
// let/var bindings below are NOT stylistic — they are the __swift5_fieldmd FieldRecord
// IsVar flags (scripts/dump_field_bindings.py AudioEnginePlayer). `let` matters twice
// over: a `let` stored property gets no vtable accessor triple (which is what makes the
// slot accounting add up), and the optimiser constant-folds reads of it — see
// minDelayAfterPrepare in play().
//
// Own vtable @meta+0x1d0, 23 entries. Slots 0-5 and 21 hold the shared deleted-method
// stub @0x10345cc70 (the optimiser eliminated those accessors; they have no body).
public class AudioEnginePlayer: AudioBaseOutput, AudioOutput {
    public let engine = AVAudioEngine()

//    private let reverb = AVAudioUnitReverb()
//    private let nbandEQ = AVAudioUnitEQ()
//    private let distortion = AVAudioUnitDistortion()
//    private let delay = AVAudioUnitDelay()

    // slots 0-2 (setter @0x101a0dc20 — getter/_modify were eliminated). Not private:
    // a private stored property gets no vtable entry, and this one has a triple.
    // The setter stores the node then mirrors the current volume into it.
    var sourceNode: AVAudioSourceNode? {
        didSet {
            sourceNode?.volume = volume
        }
    }

    private let timePitch = AVAudioUnitTimePitch()

    // slots 3-5, all eliminated. Written by prepare(audioFormat:) and read by play();
    // it is the timestamp the play() debounce measures against.
    var lastPrepareTime: Double = 0

    // ⚑ `let` (IsVar flag clear) initialised to 0.15 — init seeds both Doubles from one
    // 16-byte constant @0x103564560 (0.0, 0.15). Because it is a `let`, every read is
    // constant-folded, which is why play() compares against an inline 0.15 and this
    // field is loaded nowhere in the binary. Access level is underdetermined (a `let`
    // carries no vtable entry at any access level); `private` matches its role.
    private let minDelayAfterPrepare = 0.15

    // Declaration order below is load-bearing, not cosmetic: Swift assigns class vtable
    // slots in member declaration order, so playbackRate MUST precede volume to land on
    // slots 6-8 / 9-11 as the binary has them. Stored layout is unaffected either way —
    // playbackRate is computed and emits no field record, so volume stays the last
    // stored property at +0x78.

    // slots 6-8 @0x101a0dcb0 / 0x101a0dcb8 / 0x101a0dcd0 — unchanged from upstream
    // (the setter's fmaxnm/fminnm immediates are 0x3D000000 = 1/32 and 0x42000000 = 32).
    public var playbackRate: Float {
        get {
            timePitch.rate
        }
        set {
            timePitch.rate = min(32, max(1 / 32, newValue))
        }
    }

    // slots 9-11. Forward changed volume from a computed passthrough to STORED @0x78,
    // seeded to 1.0 by init and mirrored into the source node on write.
    public var volume: Float = 1 {
        didSet {
            sourceNode?.volume = volume
        }
    }

    // slots 12-14 @0x101a0de18 / 0x101a0de60 / 0x101a0deb0 — unchanged from upstream.
    public var isMuted: Bool {
        get {
            engine.mainMixerNode.outputVolume == 0.0
        }
        set {
            engine.mainMixerNode.outputVolume = newValue ? 0.0 : 1.0
        }
    }

    // ⚑ UNRESOLVED — the METHOD-slot numbering below (binary own-vtable entries 15..22) is
    // a fact about the binary that this source does NOT reproduce, and the mechanism is not
    // recovered. The class descriptor @0x1039ee768 has flags 0xC0000050 = HasVTable AND
    // HasOverrideTable: a 23-entry own vtable carrying Init@15 and prepare@16, PLUS a
    // 2-entry override table against AudioBaseOutput's slots 27/28 whose impls are
    // FORWARDING THUNKS back into those own entries — 0x101a0f7ec is
    // `ldr x0,[x20,#0x248]; br x0` (0x248 == 0x1d0 + 15*8) and 0x101a0f7f4 is
    // `b 0x101a0e0a8`. Current swiftc compiles `required override init()` / `override func
    // prepare` to override records pointing DIRECTLY at the subclass methods and emits no
    // own entry, so this declaration set yields 20 own entries and shifts everything from
    // 15 on down by two. No spelling that produces "override AND introduces an own entry,
    // with a thunk in the base slot" has been identified; an older toolchain is the leading
    // hypothesis. NOT a behavioural divergence — every body below is verdicted faithful —
    // and NOT applicable to entries 0..14, which precede init and are reproduced exactly.
    //
    // RE-DERIVED session 58 — the pin STANDS, and one candidate explanation is now RULED OUT.
    //   • The negative claim above was re-tested directly: compiling `open class Sub: Base` with
    //     `public required override init()` + `open override func prepare()` yields a sil_vtable
    //     containing ONLY `[override]` records pointing straight at the subclass methods, and no
    //     own entries. Current-toolchain behaviour confirmed; the pin's premise is sound.
    //   • SubtitleModel's superficially identical shape is a DIFFERENT mechanism and must not be
    //     conflated with this one. There, slots 95/96 (and 99/105) are BOTH own-vtable slots and
    //     resolve to an ordinary overload PAIR — one declaration forwarding to another — which
    //     reproduces byte-exactly (`mov w2,#1 ; b <target>`, and a bare `b <target>` when the
    //     forward needs no argument change). See KSSubtitle.swift addSubtitle(info:).
    //     Here, by contrast, 0x101a0f7ec and 0x101a0f7f4 are NOT vtable slots at all — the own
    //     vtable ends at 0x1039ee854 and their descriptor xrefs are 0x1039ee860 / 0x1039ee86c,
    //     i.e. OVERRIDE-table entries (they are also referenced from 0x1041d6f88 / 0x1041d6f90).
    //     An overload pair therefore cannot explain this shape: an overload introduces a second
    //     OWN entry, never a thunk in a superclass's slot.
    //   • Reading 0x101a0f7ec as "invoke a stored closure at self+0x248" is WRONG and was
    //     considered and rejected: for an initializer x20 is the METATYPE, so 0x248 is exactly
    //     this class's own vtable word 15 (0x1d0 + 15*8), as the line above already states.
    // The mechanism remains unidentified; the older-toolchain hypothesis is untouched by the
    // above. Deliberately left as a pin rather than guessed at. Re-derive alongside
    // AudioBaseOutput's own 34-entry set, which shows a similar shortfall.
    //
    // init: entry 15 @0x101a0df64 is the allocating entry — swift_allocObject(size: 0x7c,
    // alignMask: 7), which independently corroborates the 6-field layout and the 0x50
    // subclass boundary — tail-calling the designated body @0x101a0df98. That body sets
    // the own fields, then runs the inlined super.init() (zeroes 0x10..0x4f and seeds
    // outputLatencySystem), then attaches timePitch and installs the render notify.
    // The upstream `outputLatency = ...` line is gone: AudioBaseOutput.init does it.
    public required override init() {
        super.init()
        engine.attach(timePitch)
        if let audioUnit = engine.outputNode.audioUnit {
            addRenderNotify(audioUnit: audioUnit)
        }
    }

    // prepare (binary own-vtable entry 16) @0x101a0e0a8 OVERRIDES AudioBaseOutput's slot-28 hook: the
    // inherited slot @meta+0x170 holds 0x101a0f7f4, a one-instruction `b 0x101a0e0a8`.
    // That is also how the render engine re-enters this method on a format change.
    //
    // Forward's deltas vs upstream: reset() precedes stop(); the preferred sample rate
    // is set as well as the channel count; sampleSize is gone (AudioBaseOutput drives
    // the copy from the buffer's own mDataByteSize); sourceNodeAudioFormat is assigned
    // at the END rather than up front; lastPrepareTime is stamped; and the trailing
    // restart no longer calls engine.start() itself — it defers to play(), which owns
    // the debounce that upstream open-coded here as a DispatchQueue.main.async hop.
    override public func prepare(audioFormat: AVAudioFormat) {
        if sourceNodeAudioFormat == audioFormat {
            return
        }
        let isRunning = engine.isRunning
        engine.reset()
        engine.stop()
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setPreferredOutputNumberOfChannels(Int(audioFormat.channelCount))
        try? AVAudioSession.sharedInstance().setPreferredSampleRate(audioFormat.sampleRate)
        KSLog("[audio] set preferredOutputNumberOfChannels=\(audioFormat.channelCount) outputNumberOfChannels=\(AVAudioSession.sharedInstance().outputNumberOfChannels)")
        #endif
        KSLog("[audio] outputFormat AudioFormat=\(audioFormat)")
        // Bind through `.layout` deliberately. `channelDescriptions` is overloaded:
        // AVAudioChannelLayout's returns a String ("tag: …, channelDescriptions: …") and
        // would emit a layoutTag call, while UnsafePointer<AudioChannelLayout>'s returns
        // [AudioChannelDescription]. The binary builds the 20-byte-element array and calls
        // no layoutTag, so it is the pointer overload. Chaining `?.layout` also reproduces
        // the binary's two nil tests ahead of the log-level gate: an objc_msgSend cannot be
        // hoisted above a branch, so `.layout` executing first is evidence it is a source
        // access dominating the KSLog rather than something inside its autoclosure.
        if let layout = audioFormat.channelLayout?.layout {
            KSLog("[audio] outputFormat channelLayout \(layout.channelDescriptions)")
        }
        sourceNode = AVAudioSourceNode(format: audioFormat) { [weak self] _, timestamp, _, audioBufferList in
            if timestamp.pointee.mSampleTime == 0 {
                return noErr
            }
            self?.audioPlayerShouldInputData(ioData: UnsafeMutableAudioBufferListPointer(audioBufferList))
            return noErr
        }
        guard let sourceNode else {
            return
        }
        KSLog("[audio] new sourceNode inputFormat=\(sourceNode.inputFormat(forBus: 0))")
        engine.attach(sourceNode)
        var nodes: [AVAudioNode] = [sourceNode]
        nodes.append(contentsOf: audioNodes())
        if audioFormat.channelCount > 2 {
            nodes.append(engine.outputNode)
        }
        // 一定要传入format，这样多音轨音响才不会有问题。
        engine.connect(nodes: nodes, format: audioFormat)
        engine.prepare()
        sourceNodeAudioFormat = audioFormat
        lastPrepareTime = CFAbsoluteTimeGetCurrent()
        if isRunning {
            // The capture is WEAK in the binary: prepare allocates a 0x18 box and calls
            // swift_weakInit, and the hopped-to body @0x101a0ef6c does a weakLoadStrong
            // before calling play(). `nonisolated(unsafe)` is this repo's established
            // launder for the Swift-6 "sending 'self'" diagnostic on a MainActor hop
            // (the ThumbnailController.peeksTask / searchSubtitle idiom).
            nonisolated(unsafe) weak var weakSelf = self
            Task { @MainActor in
                weakSelf?.play()
            }
        }
    }

    // @0x101a0efe0 (binary own-vtable entry 17) — unchanged from upstream. prepare reaches it via a
    // vtable call at metadata+600; the own-vtable base is metadata+0x1d0, and
    // (600 - 0x1d0) / 8 == 17.
    func audioNodes() -> [AVAudioNode] {
        [timePitch, engine.mainMixerNode]
    }

    // play @0x101a0f050 (binary own-vtable entry 18) — FrameOutput requirement 0, per the conformance's
    // witness table @0x1041d6fa0. This is Forward's replacement for upstream's
    // "从多声道切换到2声道马上调用start会不生效" workaround: rather than restarting inside
    // prepare, a play() that lands within minDelayAfterPrepare of the last prepare is
    // delayed by the remainder of that window. The comparison compiles to a fused
    // fcmp/fccmp/b.mi against an inline 0.15 because minDelayAfterPrepare is a `let`.
    public func play() {
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

    // Name RECOVERED, not inferred: the `KSLog(error)` in the catch below bakes in its
    // `function: String = #function` default argument as a Swift small string, and the
    // immediate pair in this body — 0x292879616c506f64 with discriminator 0xe8 (count 8)
    // — decodes byte-for-byte to "doPlay()". #function is evaluated at the source call
    // site, so it names the function lexically containing that KSLog: this one.
    // This entry (binary own-vtable 19) appears in NEITHER witness table (AudioOutput's 19 requirements,
    // FrameOutput's 4), so it is an internal helper, not a protocol member; play() is its
    // only caller, by both edges — the immediate tail-call `b 0x101a0f438` and the
    // deferred @MainActor closure @0x101a0f350.
    func doPlay() {
        if !engine.isRunning {
            prepareRender()
            do {
                try engine.start()
            } catch {
                KSLog(error)
            }
        }
    }

    // @0x101a0f648 (binary own-vtable entry 20) — FrameOutput requirement 1, unchanged from upstream.
    public func pause() {
        if engine.isRunning {
            engine.pause()
        }
    }

    // @0x101a0f6f8 (binary own-vtable entry 22) — FrameOutput requirement 3. New in Forward; upstream had no
    // stop(). flush() is NOT overridden here: the inherited slot 30 @meta+0x180 still
    // holds AudioBaseOutput.flush @0x101a117b0.
    public func stop() {
        engine.reset()
        engine.stop()
    }

    // ⚑ UNRESOLVED — binary own-vtable entry 21 (between pause and stop) holds the deleted-method
    // stub @0x10345cc70. The method was eliminated, so no body, name or signature exists
    // anywhere in the binary to recover. Recorded, deliberately not invented.

    // private, so it carries no vtable slot and the optimiser inlined it straight into
    // init (the AudioUnitAddRenderNotify call sits at 0x101a0e084, installing the C
    // callback @0x101a0f680). Forward drops upstream's sampleTimestamp argument: the
    // base's audioPlayerDidRenderSample() never used it.
    private func addRenderNotify(audioUnit: AudioUnit) {
        AudioUnitAddRenderNotify(audioUnit, { refCon, ioActionFlags, _, _, _, _ in
            let `self` = Unmanaged<AudioEnginePlayer>.fromOpaque(refCon).takeUnretainedValue()
            autoreleasepool {
                if ioActionFlags.pointee.contains(.unitRenderAction_PostRender) {
                    self.audioPlayerDidRenderSample()
                }
            }
            return noErr
        }, Unmanaged.passUnretained(self).toOpaque())
    }

//    private func addRenderCallback(audioUnit: AudioUnit, streamDescription: UnsafePointer<AudioStreamBasicDescription>) {
//        _ = AudioUnitSetProperty(audioUnit,
//                                 kAudioUnitProperty_StreamFormat,
//                                 kAudioUnitScope_Input,
//                                 0,
//                                 streamDescription,
//                                 UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
//        var inputCallbackStruct = AURenderCallbackStruct()
//        inputCallbackStruct.inputProcRefCon = Unmanaged.passUnretained(self).toOpaque()
//        inputCallbackStruct.inputProc = { refCon, _, _, _, inNumberFrames, ioData in
//            guard let ioData else {
//                return noErr
//            }
//            let `self` = Unmanaged<AudioEnginePlayer>.fromOpaque(refCon).takeUnretainedValue()
//            self.audioPlayerShouldInputData(ioData: UnsafeMutableAudioBufferListPointer(ioData), numberOfFrames: inNumberFrames)
//            return noErr
//        }
//        _ = AudioUnitSetProperty(audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &inputCallbackStruct, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
//    }

    // The flat render machinery that used to live here — audioPlayerShouldInputData
    // (the sample copy) and audioPlayerDidRenderSample (the audio clock) — moved to
    // AudioBaseOutput along with the state it reads. sampleSize went with it and has no
    // Forward counterpart: the copy is driven by the buffer's own mDataByteSize.
}

extension AVAudioEngine {
    func connect(nodes: [AVAudioNode], format: AVAudioFormat?) {
        if nodes.count < 2 {
            return
        }
        for i in 0 ..< nodes.count - 1 {
            connect(nodes[i], to: nodes[i + 1], format: format)
        }
    }
}
