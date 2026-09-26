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
//    non-vtable audioPlayerShouldInputData @0x101a12b28 — the sample-copy engine — DONE.
//  The base class is now complete. REMAINING: the re-parent of AudioEnginePlayer
//  (declare `: AudioBaseOutput`, move the machinery fields off it, rewrite prepare/init to
//  override the base hook and drive this engine, delete sampleSize and the flat render
//  methods, then its 11 own accessors). Those changes are load-bearing, so they land as
//  their own unit rather than being folded in here.
//

import AVFoundation

@_silgen_name("swift_release")
private func releaseDisplacedFrame(_ object: UnsafeMutableRawPointer?)

#if !os(macOS)
@inline(never)
private func audioSessionOutputLatencyForFlush() -> Double {
    AVAudioSession.sharedInstance().outputLatency
}
#endif

public class AudioBaseOutput {
    // Fields in __swift5_fieldmd (field-record) order — dump_binary_field_types.
    public weak var renderSource: AudioOutputRenderSourceDelegate?
    // internal, not private: AudioEnginePlayer.prepare(audioFormat:) both reads this
    // (the early-out compare) and writes it, and it lives in another file.
    @exclusivity(unchecked) var sourceNodeAudioFormat: AVAudioFormat?
    // internal, not private: AudioUnitPlayer.isMuted's didSet mirrors the mute
    // state into this flag from another file (its setter writes self+0x28
    // directly — no accessor call — which requires at least `internal` access).
    // The sample-copy loop reads it to swap the memmove for a bzero. Same reason
    // as sourceNodeAudioFormat above.
    var memsetZero: Bool = false
    @exclusivity(unchecked) private var outputLatencySystem: Double = 0
    @exclusivity(unchecked) private var _outputLatency: Double = 0
    private var renderLock: os_unfair_lock_s = os_unfair_lock_s()
    @exclusivity(unchecked) private var currentRenderReadOffset: UInt32 = 0
    @exclusivity(unchecked) private var currentRender: AudioFrame?

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
    @inline(__always) public init() {
        #if !os(macOS)
        outputLatencySystem = AVAudioSession.sharedInstance().outputLatency
        #endif
    }

    // flush (slot 30 @0x101a117b0): clear the frame and read offset under
    // renderLock, then release the displaced frame after reading system latency.
    public func flush() {
        let previousRender = withUnsafeMutablePointer(to: &renderLock) { lock in
            // Forward stores these fields directly while the lock access is live.
            let fields = UnsafeMutableRawPointer(lock)
            let readOffset = fields.advanced(by: 4).assumingMemoryBound(to: UInt32.self)
            let frame = fields.advanced(by: 8).assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
            os_unfair_lock_lock(lock)
            let previous = frame.move()
            frame.initialize(to: nil)
            readOffset.pointee = 0
            os_unfair_lock_unlock(lock)
            return previous
        }
        #if !os(macOS)
        let latency = audioSessionOutputLatencyForFlush()
        releaseDisplacedFrame(previousRender)
        // The stored Double is at self+0x30 in the checked class layout.
        Unmanaged.passUnretained(self).toOpaque().advanced(by: 0x30)
            .assumingMemoryBound(to: Double.self).pointee = latency
        #else
        releaseDisplacedFrame(previousRender)
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
            // .left only — this class has no `eof` field, so .right's Bool is dropped.
            // Binary @0x101a12c70: `csel x8,xzr,x23,eq` (tag==1 ? nil : payload) then an
            // unconditional store. See Model.swift's note on the Either return.
            if case let .left(frame)? = renderSource?.getAudioOutputRender() {
                currentRender = frame
            } else {
                currentRender = nil
            }
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
        let currentPreparePosition = currentRender.timestamp + currentRender.duration * Int64(currentRenderReadOffset) / Int64(currentRender.dataSize)
        os_unfair_lock_unlock(&renderLock)
        if currentPreparePosition > 0 {
            var time = currentRender.timebase.cmtime(for: currentPreparePosition)
            if outputLatency != 0 {
                time = time - CMTime(seconds: outputLatency, preferredTimescale: time.timescale)
            }
            renderSource.setAudio(time: time, position: currentRender.position)
        }
        withExtendedLifetime(renderSource) {}
    }

    // audioPlayerShouldInputData (@0x101a12b28) — the sample-copy engine, reached
    // from AudioEnginePlayer.prepare's AVAudioSourceNode render block (block-invoke
    // @0x101a10114 → thunk @0x101a0f6f0 → closure @0x101a0ed08). It carries no
    // vtable slot, so it is final; private is ruled out because the subclass's
    // prepare closure calls it from another file.
    // Forward reworks upstream here: sampleSize is gone — both the work amount and
    // the write offset come from the buffer's own mDataByteSize — the pull/copy
    // runs under renderLock, and memsetZero swaps the memmove for a bzero (silence).
    // The trailing zero-fill is guarded: it runs only on the two underrun exits,
    // never on the normal drain path.
    final func audioPlayerShouldInputData(ioData: UnsafeMutableAudioBufferListPointer) {
        guard ioData.count > 0 else {
            return
        }
        var residueBytes = ioData[0].mDataByteSize
        while residueBytes != 0 {
            os_unfair_lock_lock(&renderLock)
            if currentRender == nil {
                // .left only (see prepareRender): .right's Bool has no home on this class.
                if case let .left(frame)? = renderSource?.getAudioOutputRender() {
                    currentRender = frame
                } else {
                    currentRender = nil
                }
                currentRenderReadOffset = 0
            }
            guard let render = currentRender else {
                os_unfair_lock_unlock(&renderLock)
                break
            }
            // Compare before subtracting: the binary guards on the comparison and
            // emits no borrow trap here, so the subtraction cannot underflow.
            guard currentRenderReadOffset < render.numberOfSamples else {
                currentRender = nil
                currentRenderReadOffset = 0
                os_unfair_lock_unlock(&renderLock)
                continue
            }
            let residueLinesize = render.numberOfSamples - currentRenderReadOffset
            // Optional != non-optional: a nil sourceNodeAudioFormat is unequal by
            // construction, so an unconfigured engine takes the re-prepare edge.
            if sourceNodeAudioFormat != render.audioFormat {
                nonisolated(unsafe) let audioFormat = render.audioFormat
                os_unfair_lock_unlock(&renderLock)
                nonisolated(unsafe) weak var weakSelf = self
                runOnMainThread {
                    weakSelf?.prepare(audioFormat: audioFormat)
                }
                break
            }
            let bytesToCopy = min(residueBytes, residueLinesize)
            for i in 0 ..< min(ioData.count, render.data.count) {
                if let source = render.data[i], let destination = ioData[i].mData {
                    let writeOffset = Int(ioData[i].mDataByteSize - residueBytes)
                    if memsetZero {
                        bzero(destination + writeOffset, Int(bytesToCopy))
                    } else {
                        memmove(destination + writeOffset, source + Int(currentRenderReadOffset), Int(bytesToCopy))
                    }
                }
            }
            currentRenderReadOffset += bytesToCopy
            os_unfair_lock_unlock(&renderLock)
            residueBytes -= bytesToCopy
        }
        // Reached only on the two underrun exits; after a complete copy
        // residueBytes is 0 and the binary returns without touching the buffers.
        if residueBytes > 0 {
            for i in 0 ..< ioData.count {
                let buffer = ioData[i]
                bzero(buffer.mData! + Int(buffer.mDataByteSize - residueBytes), Int(residueBytes))
            }
        }
    }
}
