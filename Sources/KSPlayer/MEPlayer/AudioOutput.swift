//
//  AudioOutput.swift
//  KSPlayer
//
//  `AudioDataBuffer` is a NEW root class in Forward 1.3.17, absent from upstream and
//  from the reconstruction until session 47. It turns the pulled `AudioFrame` stream
//  into `CMSampleBuffer`s for an `AVSampleBufferAudioRenderer`-style consumer: its only
//  subclass, the public `AudioRendererPlayer`, calls `sampleBuffer(nanoseconds:)` from
//  its media-data-request block and enqueues the result.
//
//  Binary: descriptor @0x1039ee9f8, metadata @0x1044e8398, superclass=None (root,
//  superclass_conformance_gate), conformances=[] (GOT-aware binary_conformances),
//  vtable_size=16 (vtable_walk). Instance fields occupy +0x10..+0x33.
//
//  #file — the class's own KSLog bakes "KSPlayer/AudioOutput.swift" (@0x103d35580,
//  len 0x1a=26), so this file, not the sibling's AudioBaseOutput.swift, is the faithful
//  home. Forward kept `AudioBaseOutput` and `AudioDataBuffer` in ONE source file; the
//  reconstruction split `AudioBaseOutput` into its own file earlier, an orthogonal and
//  already-banked matter that this unit does not revisit.
//
//  vtable (vtable_walk): slots 0-2 renderSource get/set/_modify; 3-11 the accessor
//  triples of eof/currentRender/currentRenderReadOffset (null in the descriptor — not
//  overridden — but still allocated by the stored `var`s); slot 12 flush() (⚑ name
//  INFERRED); slot 13 sampleBuffer(nanoseconds:) (⚑ name INFERRED); slot 14
//  audioPlayerShouldInputData(ioData:) (name RECOVERED from #function); slot 15 the
//  implicit init() (null in the descriptor). Declaration order below IS the field-record
//  order (dump_field_bindings) and assigns those slots — do not reorder.
//

import AVFoundation
import CoreMedia
import CoreAudio

public class AudioDataBuffer {
    // Fields in __swift5_fieldmd (field-record) order; all four are `var`
    // (dump_field_bindings: flags 0x2), so each earns an accessor triple (slots 0-11).
    //
    // renderSource: weak+optional+existential (dump_field_type_mangles:
    // `<SYM:2@0x1039efde8>_pSgXw`; the field-record descriptor Name reads
    // "AudioOutputRenderSourceDelegate"). Typed as the ⚑ session-16b `OutputRenderSourceDelegate`
    // bridge (Model.swift:69 — refines Audio+VideoOutputRenderSourceDelegate), matching every sibling
    // renderer (AudioBaseOutput/AudioGraphPlayer/AudioUnitPlayer) and FrameOutput.renderSource. The
    // public subclass AudioRendererPlayer inherits THIS field and satisfies FrameOutput through it, so
    // the bridge spelling is load-bearing here. It is a P51 source-extra (the binary has no combined
    // protocol) that erases acceptably; the l2 gate leaves this existential field UNCHECKED either way.
    // (Session 47 corrected the original binary-literal spelling once the re-parent coupling surfaced —
    // AudioDataBuffer had been the sole outlier in an otherwise all-bridge subsystem.)
    public weak var renderSource: AudioOutputRenderSourceDelegate?
    // eof: field-record concrete type `Sb`. Receives the `.right(Bool)` payload of
    // `getAudioOutputRender() -> Either<AudioFrame, Bool>` on the no-frame path (the tag-1
    // branch does `and w8,w0,#0x1; strb w8,[self,#0x20]` in slots 13 and 14) — it is the
    // stream-ended flag, NOT an unconditional `eof = true`.
    var eof: Bool = false
    // currentRender: field-record mangle `<SYM:2@0x1039f006c>Sg`, byte-identical to
    // AudioBaseOutput.currentRender.
    //
    // ⚑ FORM (pinned): the observer is UNCONDITIONAL. The sibling AudioBaseOutput's
    // CONDITIONAL `didSet { if currentRender == nil { … } }` is POSITIVELY EXCLUDED —
    // control_test on AudioBaseOutput.flush @0x101a117b0 shows such a guard constant-folds
    // against the assigned value, so it would emit NO reset on a known-non-nil assignment,
    // yet slot 13 resets currentRenderReadOffset when it assigns a NEW frame. An
    // unconditional `didSet` explains all four assignment sites (slot 12 nil, slot 13
    // non-nil, slot 14 exhaustion nil, slot 14 adopt non-nil) with one construct. Reading B
    // (no observer; an explicit `currentRenderReadOffset = 0` written at each site) emits
    // identical machine code and is NOT excluded — this choice is FORM-only.
    @exclusivity(unchecked) var currentRender: AudioFrame? {
        didSet {
            currentRenderReadOffset = 0
        }
    }
    // currentRenderReadOffset: a 4-byte store at every site (undefined4) rules out a
    // 64-bit type; its field-record symref (0x103c2cf86) is the SAME linker-deduplicated
    // mangled string as AudioBaseOutput's same-named UInt32 field.
    @exclusivity(unchecked) private var currentRenderReadOffset: UInt32 = 0

    // flush (slot 12 @0x101a11cb4, 8 instr — the name is CONFIRMED, no longer inferred. The
    // session-46 P43 check came back negative (no #function/#file literal, no witness-table
    // anchor, no naming caller) and the name was chosen by analogy to AudioBaseOutput.flush().
    // The analogy was right: the orphaned export trie maps 0x101a11cb4 directly to
    // `KSPlayer.AudioDataBuffer.flush() -> ()`.
    // ⚑[tool=export_trie_oracle ref=FUN_101a11cb4:0x101a11cb4 result=CONFIRMED AudioDataBuffer.flush()] Body: release  ⚑[tool=resolve_fun_pins ref=FUN_101a11cb4:0x101a11cb4 result=RESOLVES_UNIQUELY] = KSPlayer.AudioDataBuffer.flush() -> ()
    // and clear currentRender; the unconditional didSet resets currentRenderReadOffset.
    // AudioDataBuffer has no lock field, so there is no os_unfair_lock here.
    public func flush() {
        currentRender = nil
    }

    // sampleBuffer(nanoseconds:) (slot 13 @0x101a11cd4, 398 instr, ⚑ name still INFERRED —
    // and unlike slot 12 this one does NOT resolve: 0x101a11cd4 is absent from the export trie.
    // That makes it a VERIFIED negative rather than an unverified one; named for its behaviour
    // and its `nanoseconds` argument.
    // ⚑[tool=export_trie_oracle ref=FUN_101a11cd4:0x101a11cd4 result=absent — VERIFIED negative, name remains inferred]
    //
    // ⚑ SIGNATURE CORRECTION (session 47): the session-46 decode recorded
    // `(CMTime) -> CMSampleBuffer?`. Disassembly disproves the parameter: the prologue saves
    // only x0 (`mov x21,x0`) — a CMTime by value occupies three registers — and x0 is used
    // as the `value:` of a freshly built `CMTime(value:, timescale: 1_000_000_000)`. The
    // caller @0x101a1468c passes `renderer.currentTime.convertScale(1e9, …).value` (an Int64
    // nanosecond timestamp) after a `renderer.rate != 0` guard. So the parameter is Int64
    // nanoseconds, not a CMTime. The return (x0, `cbz` at the caller) is `CMSampleBuffer?`.
    public func sampleBuffer(nanoseconds: Int64) -> CMSampleBuffer? {
        // The whole body is gated on renderSource (weak→strong load at the top, released at
        // the end); without the delegate there is nothing to pull.
        guard let renderSource else {
            return nil
        }
        if currentRender == nil {
            switch renderSource.getAudioOutputRender() {
            case let .left(frame):
                currentRender = frame // didSet resets currentRenderReadOffset
            case let .right(isEndOfFile):
                // Forward returns straight away here (no currentRender reload).
                eof = isEndOfFile
                return nil
            }
        }
        guard let render = currentRender else {
            return nil
        }
        // frameCapacity ≈ 50 ms of audio: ceil(sampleRate / 20) (frintp). The Double→UInt32
        // conversion carries the binary's three overflow/range traps. Forward reads
        // render.audioFormat twice (unretained for sampleRate, then the retained local).
        let frameCapacity = AVAudioFrameCount((render.audioFormat.sampleRate / 20).rounded(.up))
        let audioFormat = render.audioFormat
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCapacity) else {
            return nil
        }
        pcmBuffer.frameLength = pcmBuffer.frameCapacity
        let ioData = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)
        // Fill the buffer; the leftover (unfilled) byte count divided by the per-frame byte
        // size (AVAudioFormat.sampleSize @0x101a63468) gives the frames still missing, so the
        // frames actually written = frameCapacity − leftByteSize / sampleSize.
        let leftByteSize = audioPlayerShouldInputData(ioData: ioData)
        let sampleCount = CMItemCount(frameCapacity - leftByteSize / audioFormat.sampleSize)
        // Per-sample duration and a nanosecond PTS; DTS invalid.
        let presentationTimeStamp = CMTime(value: nanoseconds, timescale: 1_000_000_000)
        let duration = CMTime(value: 1, timescale: Int32(audioFormat.sampleRate))
        let timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: presentationTimeStamp, decodeTimeStamp: .invalid)
        // Interleaved audio needs one sample-size entry; planar needs none (matches
        // AudioFrame.toCMSampleBuffer, Model.swift).
        let sampleSizeEntryCount: CMItemCount
        let sampleSizeArray: [Int]?
        if audioFormat.isInterleaved {
            sampleSizeEntryCount = 1
            sampleSizeArray = [Int(audioFormat.sampleSize)]
        } else {
            sampleSizeEntryCount = 0
            sampleSizeArray = nil
        }
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            formatDescription: audioFormat.formatDescription,
            sampleCount: sampleCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: [timing],
            sampleSizeEntryCount: sampleSizeEntryCount,
            sampleSizeArray: sampleSizeArray,
            sampleBufferOut: &sampleBuffer
        )
        guard let sampleBuffer else {
            return nil
        }
        // Trim the buffer list down to the bytes actually written before attaching it.
        if leftByteSize != 0 {
            ioData.unsafeMutablePointer.pointee.mBuffers.mDataByteSize -= leftByteSize
        }
        try? sampleBuffer.setDataBuffer(fromAudioBufferList: ioData.unsafePointer)
        return sampleBuffer
    }

    // audioPlayerShouldInputData(ioData:) (slot 14 @0x101a1230c, 283 instr) — name RECOVERED
    // (recover_swift_function_name: #function @0x103d355a0 len 0x23, length_verified). The
    // sample-copy loop, a leaner cousin of AudioBaseOutput's same-named engine: AudioDataBuffer
    // has no renderLock, no memsetZero, and no sourceNodeAudioFormat re-prepare. Differences it
    // DOES carry: it consumes `.right`'s Bool into `eof`, logs the underrun, and RETURNS the
    // leftover byte count (UInt32 — the caller slot 13 divides it by sampleSize with a 32-bit
    // udiv). Not `final`: Forward gives it vtable slot 14 (before init F15); not private: slot 13 calls it.
    func audioPlayerShouldInputData(ioData: UnsafeMutableAudioBufferListPointer) -> UInt32 {
        guard ioData.count > 0 else {
            return 0
        }
        guard let renderSource else {
            return 0
        }
        var residueBytes = ioData[0].mDataByteSize
        while residueBytes != 0 {
            if currentRender == nil {
                switch renderSource.getAudioOutputRender() {
                case let .left(frame):
                    currentRender = frame // didSet resets currentRenderReadOffset
                case let .right(isEndOfFile):
                    eof = isEndOfFile
                }
            }
            guard let render = currentRender else {
                // Underrun: the pull produced no frame. Log the shortfall at the default
                // level (.warning; the inlined gate is `warning.caseIndex(3) <= logLevel`,
                // which the binary folds to `2 < logLevel` — see KSLog, KSOptions.swift:745),
                // then zero-fill the tail of each output buffer and return the shortfall.
                KSLog("[audio] leftByteSize=\(residueBytes)")
                for i in 0 ..< ioData.count {
                    bzero(ioData[i].mData! + Int(ioData[i].mDataByteSize - residueBytes), Int(residueBytes))
                }
                return residueBytes
            }
            // Forward reads dataSize (+0x10, no access check) and subtracts with the overflow
            // trap first (`subs; b.cc brk`), then drops a drained frame on zero (`cbz`).
            let residueLinesize = render.dataSize - currentRenderReadOffset
            guard residueLinesize > 0 else {
                // Frame drained: drop it (didSet resets the offset) and pull the next one.
                currentRender = nil
                continue
            }
            let bytesToCopy = min(residueBytes, residueLinesize)
            for i in 0 ..< min(ioData.count, render.data.count) {
                if let source = render.data[i], let destination = ioData[i].mData {
                    let writeOffset = Int(ioData[i].mDataByteSize - residueBytes)
                    memmove(destination + writeOffset, source + Int(currentRenderReadOffset), Int(bytesToCopy))
                }
            }
            currentRenderReadOffset += bytesToCopy
            residueBytes -= bytesToCopy
        }
        return residueBytes
    }
}

public protocol AudioOutput: FrameOutput {
    var renderSource: AudioOutputRenderSourceDelegate? { get set }
    var playbackRate: Float { get set }
    var volume: Float { get set }
    var isMuted: Bool { get set }
    init()
    func prepare(audioFormat: AVAudioFormat)
}

// ⚑ s105: a body the binary places in an EXTENSION of AudioOutput —
// `(extension in KSPlayer):KSPlayer.AudioOutput.resetTime() -> ()` @0x101a11b10. Three
// instructions, and all three are the dispatch:
//     ldr x1, [x1, #0x8]     ; x1 is Self's AudioOutput witness table; +0x8 is its INHERITED
//                            ; FrameOutput table (a refined protocol's WT holds the base's there)
//     ldr x2, [x1, #0x18]    ; FrameOutput requirement index 2
//     br  x2                 ; tail-call it — the whole body is that one call
// Requirement 2 was NAMED, not counted off the source's declaration order: decoding
// AudioGraphPlayer's FrameOutput witness table (0x1041d70b0, via conformance descriptor
// 0x10356a0f0) gives req0 play() @0x101a10284, req1 pause() @0x101a1029c, req2 a thunk to
// AudioBaseOutput.flush() @0x101a117b0, req3 invalidate() @0x101a11138. So this calls flush().
// ⚑[tool=decode_witness_table ref=AudioGraphPlayer:FrameOutput:0x1041d70b0 result=req2=flush]
//
// ⚠️ SEPARATE FINDING, not acted on here: that decode also shows FrameOutput has FOUR
// requirements in the order play / pause / flush / invalidate, where the protocol above declares
// three as pause / flush / play. Requirement order IS the witness-table layout, so that is a real
// divergence — but reordering a protocol's requirements ripples to every conformer's table and
// needs its own unit.
public extension AudioOutput {
    func resetTime() {
        flush()
    }
}

//  Forward extracted the manual AVAudioSourceNode render engine out of the flat
//  upstream `AudioEnginePlayer` into this root base class; `AudioEnginePlayer`
//  becomes a thin subclass (engine/sourceNode/timePitch/lastPrepareTime/
//  minDelayAfterPrepare/volume) that inherits this storage. Binary: metadata
//  @0x1044e84c8, descriptor @0x1039eeaac, superclass=None (root), conformances=[]
//  (GOT-aware binary_conformances), vtable_size=34, instance fields @0x10..0x4f
//  (subclass storage begins at +0x50).
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

    // outputLatency (computed, slots 3-5): the public latency = the system
    // baseline (outputLatencySystem, seeded in init) + the app-set delta
    // (_outputLatency); the setter writes only the delta.
    public var outputLatency: TimeInterval {
        get { _outputLatency + outputLatencySystem }
        set { _outputLatency = newValue }
    }
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

    // init @0x101a127c8 (slot 27): zero/nil all storage, then seed
    // outputLatencySystem from the system output latency (iOS/tvOS only —
    // AVAudioSession is unavailable on macOS).
    // Internal, not public: AudioEnginePlayer/AudioGraphPlayer/AudioUnitPlayer each give their
    // `public required override init()` an OWN vtable entry, and their override-table entry for
    // this slot is a vtable thunk into it. swiftc emits exactly that shape when the override is
    // more visible than the base (isEffectiveLinkageMoreVisibleThan); a public base gets a plain
    // override record and no own entry.
    // ⚑[tool=override_table ref=AudioEnginePlayer:0x1039ee768 result=base-method-desc-0x1039eebb8=slot27]
    @inline(__always) init() {
        #if !os(macOS)
        outputLatencySystem = AVAudioSession.sharedInstance().outputLatency
        #endif
    }

    // prepare(audioFormat:) (slot 28 @0x10000e52c — the coalesced empty-body
    // stub): the overridable base hook. AudioEnginePlayer overrides it with the
    // real engine/sourceNode setup; the sample-copy engine re-invokes it through
    // this slot when the incoming frame's format stops matching
    // sourceNodeAudioFormat. Slot identity is arithmetic, not inferred: the
    // engine's main-thread re-prepare calls metadata+0x170, and the vtable base
    // is metadata+0x90 (slot k at +0x90+k*8), so 0x170 == slot 28. Internal for the reason init()
    // is: AudioEnginePlayer's public override owns entry 16 and thunks this slot.
    // ⚑[tool=override_table ref=AudioEnginePlayer:0x1039ee768 result=base-method-desc-0x1039eebc0=slot28]
    func prepare(audioFormat _: AVAudioFormat) {}

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
        // Forward inlines the session read (sharedInstance → outputLatency → release) here.
        let latency = AVAudioSession.sharedInstance().outputLatency
        releaseDisplacedFrame(previousRender)
        // The stored Double is at self+0x30 in the checked class layout.
        Unmanaged.passUnretained(self).toOpaque().advanced(by: 0x30)
            .assumingMemoryBound(to: Double.self).pointee = latency
        #else
        releaseDisplacedFrame(previousRender)
        #endif
    }

    /// Vtable F31: a dead slot of shape M, so Forward keeps no body, callers or strings. Name INFERRED;
    /// the declaration only holds the slot.
    func unreadSlot31() {}

    /// Vtable F32: a dead slot of shape M, so Forward keeps no body, callers or strings. Name INFERRED;
    /// the declaration only holds the slot.
    func unreadSlot32() {}

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
