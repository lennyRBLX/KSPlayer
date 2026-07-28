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
    public weak var renderSource: OutputRenderSourceDelegate?
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
    var currentRender: AudioFrame? {
        didSet {
            currentRenderReadOffset = 0
        }
    }
    // currentRenderReadOffset: a 4-byte store at every site (undefined4) rules out a
    // 64-bit type; its field-record symref (0x103c2cf86) is the SAME linker-deduplicated
    // mangled string as AudioBaseOutput's same-named UInt32 field.
    var currentRenderReadOffset: UInt32 = 0

    // flush (slot 12 @0x101a11cb4, 8 instr — the name is CONFIRMED, no longer inferred. The
    // session-46 P43 check came back negative (no #function/#file literal, no witness-table
    // anchor, no naming caller) and the name was chosen by analogy to AudioBaseOutput.flush().
    // The analogy was right: the orphaned export trie maps 0x101a11cb4 directly to
    // `KSPlayer.AudioDataBuffer.flush() -> ()`.
    // ⚑[tool=export_trie_oracle ref=FUN_101a11cb4:0x101a11cb4 result=CONFIRMED AudioDataBuffer.flush()] Body: release
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
                eof = isEndOfFile
            }
        }
        guard let render = currentRender else {
            return nil
        }
        let audioFormat = render.audioFormat
        // frameCapacity ≈ 50 ms of audio: Int(sampleRate / 20). The Double→UInt32
        // conversion carries the binary's three overflow/range traps.
        let frameCapacity = AVAudioFrameCount(audioFormat.sampleRate / 20)
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
        let sampleSize = Int(audioFormat.sampleSize)
        let sampleSizeEntryCount: CMItemCount
        let sampleSizeArray: [Int]?
        if audioFormat.isInterleaved {
            sampleSizeEntryCount = 1
            sampleSizeArray = [sampleSize]
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
            ioData[0].mDataByteSize -= leftByteSize
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
    // udiv). It is `final` (a slot without a subclass override) yet not private: slot 13 calls it.
    final func audioPlayerShouldInputData(ioData: UnsafeMutableAudioBufferListPointer) -> UInt32 {
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
            guard currentRenderReadOffset < render.numberOfSamples else {
                // Frame drained: drop it (didSet resets the offset) and pull the next one.
                currentRender = nil
                continue
            }
            let residueLinesize = render.numberOfSamples - currentRenderReadOffset
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
