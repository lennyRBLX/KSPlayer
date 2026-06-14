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
    var synchronizer: AVSampleBufferRenderSynchronizer? { get }
    init()
    func prepare(audioFormat: AVAudioFormat)
}

public extension AudioOutput {
    var synchronizer: AVSampleBufferRenderSynchronizer? { nil }
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
    public let nbandEQ = AVAudioUnitEQ(numberOfBands: 10)
    private let dynamicsProcessor = AVAudioUnitEffect(audioComponentDescription:
        AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                  componentSubType: kAudioUnitSubType_DynamicsProcessor,
                                  componentManufacturer: kAudioUnitManufacturer_Apple,
                                  componentFlags: 0,
                                  componentFlagsMask: 0))
    public var audioUnitForDynamicsProcessor: AudioUnit {
        dynamicsProcessor.audioUnit
    }

    /// Forward v1.3.15 chain: sourceNode → timePitch → nbandEQ → dynamicsProcessor → mainMixerNode.
    /// Speed adjustment applies first, then EQ + dynamics shape the resampled output.
    override func audioNodes() -> [AVAudioNode] {
        [timePitch, nbandEQ, dynamicsProcessor, engine.mainMixerNode]
    }

    public required init() {
        super.init()
        engine.attach(nbandEQ)
        engine.attach(dynamicsProcessor)
    }

    /// Configure the N-band parametric EQ gains.
    /// Each element in `bands` sets the gain (in dB) for the corresponding EQ band.
    /// Indices beyond the EQ's band count are ignored.
    public func configureEqualizer(bands: [Float]) {
        for (i, gain) in bands.enumerated() where i < nbandEQ.numberOfBands {
            nbandEQ.bands[i].gain = gain
        }
    }
}

public class AudioEnginePlayer: AudioOutput {
    public let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var sourceNodeAudioFormat: AVAudioFormat?

    fileprivate let timePitch = AVAudioUnitTimePitch()
    private var currentRenderReadOffset = UInt32(0)

    /// Stored A/V-sync latency, subtracted from the render clock alongside
    /// `outputLatencySystem`. types.json names this field `_outputLatency`
    /// (self+0x48); upstream KSPlayer calls it `outputLatency`. Refreshed in
    /// `flush()`; on iOS/tvOS it tracks `AVAudioSession.outputLatency`.
    /// RE: 0x1013f1480 (+0x48), summed with +0x50 in the clock fn 0x1013f2e40.
    private var _outputLatency = TimeInterval(0)

    public weak var renderSource: OutputRenderSourceDelegate?

    /// Timestamp of last prepare() call for debounce protection.
    /// RE: Forward v1.3.15 AudioEnginePlayer debounce fields
    private var lastPrepareTime: CFTimeInterval = 0

    /// Minimum delay between prepare() calls (seconds).
    /// RE: 0x1013f1480 (+0x30) writes 0.15 (0x3fc3333333333333).
    private let minDelayAfterPrepare: CFTimeInterval = 0.15

    /// System-level audio output latency, cached.
    ///
    /// Stored field at self+0x50 (Forward). The binary writes it once in the
    /// designated init from `[[AVAudioSession sharedInstance] outputLatency]`
    /// (0x1013f15ac) and refreshes it only in `flush()` (0x1013f2ca4) — it does
    /// NOT re-read AVAudioSession live on every access. The clock fn 0x1013f2e40
    /// sums this with `_outputLatency` (+0x48) before subtracting from the A/V
    /// time. On macOS AVAudioSession is unavailable, so it stays 0.
    /// RE: 0x1013f1480 (+0x50).
    private var outputLatencySystem = TimeInterval(0)

    /// os_unfair_lock guarding `currentRender` / `currentRenderReadOffset`
    /// between the CoreAudio render thread (drain 0x1013f3d90) and the
    /// decode/pull + clock side (0x1013f2e40 / flush 0x1013f2ca4).
    /// RE: 0x1013f1480 (+0x68), locked under swift_beginAccess flags 0x21.
    private var renderLock = os_unfair_lock_s()

    /// Stored playback volume (self+0x78, Forward). Default 1.0. The setter
    /// writes this field AND forwards to `sourceNode.volume`; the stored value
    /// is re-applied when the source node is (re)built in `prepare()`, so a
    /// volume set before the node exists is not lost.
    /// RE: 0x1013f1480 (+0x78) init 1.0; setter 0x1013f11f0; getter 0x1013f11c0.
    private var _volume: Float = 1

    private var currentRender: AudioFrame? {
        didSet {
            if currentRender == nil {
                currentRenderReadOffset = 0
            }
        }
    }

    /// Playback rate. Backed by `timePitch.rate` (Forward field `+0x38`).
    ///
    /// The setter matches Forward `AudioEnginePlayer_setPlaybackRate_clamped`
    /// at `0x1013f1138` (Ghidra mislabels this as
    /// `AudioRendererPlayer_setRate_clamped`; vtable evidence in
    /// `0x103d0b9e0` and `0x103d0bc70` confirms AudioEnginePlayer ownership).
    /// Scalar lower clamp at `1/32 = 0.03125`, NEON `fminnm` upper clamp at
    /// `32.0`, then `[timePitch setRate:]`.
    public var playbackRate: Float {
        get {
            timePitch.rate
        }
        set {
            timePitch.rate = min(32, max(1 / 32, newValue))
        }
    }

    /// Stored volume with source-node passthrough.
    ///
    /// Getter returns the stored field (0x1013f11c0); setter stores it and
    /// forwards to the source node (0x1013f11f0:
    /// `beginAccess(self+0x78, write); *(self+0x78) = arg;
    /// objc_msgSend(*(self+0x18 = sourceNode), setVolume:)`). The stored value
    /// is reapplied in `prepare()` when the source node is rebuilt.
    public var volume: Float {
        get {
            _volume
        }
        set {
            _volume = newValue
            sourceNode?.volume = newValue
        }
    }

    public var isMuted: Bool {
        get {
            engine.mainMixerNode.outputVolume == 0.0
        }
        set {
            engine.mainMixerNode.outputVolume = newValue ? 0.0 : 1.0
        }
    }

    public required init() {
        engine.attach(timePitch)
        if let audioUnit = engine.outputNode.audioUnit {
            addRenderNotify(audioUnit: audioUnit)
        }
        // Designated init caches the system latency once (0x1013f15ac); it is
        // only refreshed in flush(). AVAudioSession is iOS/tvOS-only.
        #if !os(macOS)
        outputLatencySystem = AVAudioSession.sharedInstance().outputLatency
        #endif
    }

    public func prepare(audioFormat: AVAudioFormat) {
        let now = CACurrentMediaTime()
        guard now - lastPrepareTime >= minDelayAfterPrepare else { return }
        lastPrepareTime = now
        if sourceNodeAudioFormat == audioFormat {
            return
        }
        sourceNodeAudioFormat = audioFormat
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setPreferredOutputNumberOfChannels(Int(audioFormat.channelCount))
        KSLog("[audio] set preferredOutputNumberOfChannels: \(audioFormat.channelCount)")
        #endif
        KSLog("[audio] outputFormat AudioFormat: \(audioFormat)")
        if let channelLayout = audioFormat.channelLayout {
            KSLog("[audio] outputFormat channelLayout \(channelLayout.channelDescriptions)")
        }
        let isRunning = engine.isRunning
        engine.stop()
        engine.reset()
        sourceNode = AVAudioSourceNode(format: audioFormat) { [weak self] _, timestamp, frameCount, audioBufferList in
            if timestamp.pointee.mSampleTime == 0 {
                return noErr
            }
            self?.audioPlayerShouldInputData(ioData: UnsafeMutableAudioBufferListPointer(audioBufferList), numberOfFrames: frameCount)
            return noErr
        }
        guard let sourceNode else {
            return
        }
        KSLog("[audio] new sourceNode inputFormat: \(sourceNode.inputFormat(forBus: 0))")
        // Reapply the stored volume to the freshly built node (self+0x78).
        sourceNode.volume = _volume
        engine.attach(sourceNode)
        var nodes: [AVAudioNode] = [sourceNode]
        nodes.append(contentsOf: audioNodes())
        if audioFormat.channelCount > 2 {
            nodes.append(engine.outputNode)
        }
        // 一定要传入format，这样多音轨音响才不会有问题。
        engine.connect(nodes: nodes, format: audioFormat)
        engine.prepare()
        if isRunning {
            try? engine.start()
            // 从多声道切换到2声道马上调用start会不生效。需要异步主线程才可以
            DispatchQueue.main.async { [weak self] in
                self?.play()
            }
        }
    }

    func audioNodes() -> [AVAudioNode] {
        [timePitch, engine.mainMixerNode]
    }

    public func play() {
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                KSLog(error)
            }
        }
    }

    public func pause() {
        if engine.isRunning {
            engine.pause()
        }
    }

    /// FrameOutput.flush(). Under `renderLock` (self+0x68): drop the current
    /// frame and reset the read offset; then (outside the lock) refresh the
    /// cached system latency. RE: 0x1013f2ca4.
    public func flush() {
        os_unfair_lock_lock(&renderLock)
        currentRender = nil
        os_unfair_lock_unlock(&renderLock)
        #if !os(macOS)
        // 这个要在主线程执行，如果在音频的线程，那就会有中断杂音
        outputLatencySystem = AVAudioSession.sharedInstance().outputLatency
        #endif
    }

    private func addRenderNotify(audioUnit: AudioUnit) {
        AudioUnitAddRenderNotify(audioUnit, { refCon, ioActionFlags, inTimeStamp, _, _, _ in
            let `self` = Unmanaged<AudioEnginePlayer>.fromOpaque(refCon).takeUnretainedValue()
            autoreleasepool {
                if ioActionFlags.pointee.contains(.unitRenderAction_PostRender) {
                    self.audioPlayerDidRenderSample(sampleTimestamp: inTimeStamp.pointee)
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

    /// Render-thread drain. Runs entirely under `renderLock` (self+0x68) to
    /// guard `currentRender` / `currentRenderReadOffset` against the clock fn
    /// and flush. The copy stride (bytesPerFrame) is derived locally from the
    /// frame's format — the binary has no cached `sampleSize` field here; that
    /// instance slot was repurposed for the stored `volume` (+0x78).
    /// RE: 0x1013f3d90 (drain, three branches: UNDERRUN / FORMAT-MISMATCH / COPY).
    private func audioPlayerShouldInputData(ioData: UnsafeMutableAudioBufferListPointer, numberOfFrames: UInt32) {
        os_unfair_lock_lock(&renderLock)
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
                os_unfair_lock_unlock(&renderLock)
                runOnMainThread { [weak self] in
                    guard let self else {
                        return
                    }
                    self.prepare(audioFormat: currentRender.audioFormat)
                }
                return
            }
            let sampleSize = currentRender.audioFormat.sampleSize
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
        // Zero any tail the source frames did not fill (per-channel silence).
        for i in 0 ..< ioData.count {
            let sizeLeft = Int(ioData[i].mDataByteSize) - ioDataWriteOffset
            if sizeLeft > 0 {
                memset(ioData[i].mData! + ioDataWriteOffset, 0, sizeLeft)
            }
        }
        os_unfair_lock_unlock(&renderLock)
    }

    /// A/V-sync clock feed, driven by the output node's render-notify tap.
    /// Reads `currentRender` under `renderLock`, computes the presentation
    /// CMTime, then subtracts the total output latency — the binary sums BOTH
    /// the stored A/V-sync latency (`_outputLatency`, +0x48) and the cached
    /// system latency (`outputLatencySystem`, +0x50) unconditionally (no
    /// `!= 0` guard), unlike upstream KSPlayer which subtracts only one.
    /// RE: 0x1013f2e40.
    private func audioPlayerDidRenderSample(sampleTimestamp _: AudioTimeStamp) {
        os_unfair_lock_lock(&renderLock)
        defer { os_unfair_lock_unlock(&renderLock) }
        if let currentRender {
            let currentPreparePosition = currentRender.timestamp + currentRender.duration * Int64(currentRenderReadOffset) / Int64(currentRender.numberOfSamples)
            if currentPreparePosition > 0 {
                var time = currentRender.timebase.cmtime(for: currentPreparePosition)
                let totalLatency = _outputLatency + outputLatencySystem
                time = time - CMTime(seconds: totalLatency, preferredTimescale: time.timescale)
                renderSource?.setAudio(time: time, position: currentRender.position)
            }
        }
    }
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
