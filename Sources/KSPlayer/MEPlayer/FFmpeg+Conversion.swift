//
//  OutputStreamInfo.swift
//  KSPlayer
//
//  Forward 1.3.17 reconstruction — NEW Forward-only class (0 source hits).
//  STRUCTURE-ONLY scope (user-gated): the type's 12 stored fields + an inferred minimal init are
//  reconstructed faithfully from the binary __swift5_fieldmd field-records. The 3 substantive methods
//  (vtable slots 13/14/15) are DEVIRTUALIZED ~170-line per-stream remux ops with unrecoverable
//  names/signatures → documented UNRESOLVED below, reconstructed in PHASE 2 (Remuxer).
//
//  The per-output-stream config the Phase-2 Remuxer writes packets through.
//
import Libavutil
import AVFoundation   // AVMediaType — the p8 slot's type, read from the binary (see the init below)
import FFmpegKit
import Libavcodec
import Libavformat
import Libswresample

// ── FFmpegAssetTrack members Forward emits inside this file (#fileID contiguity) ─────────────
// Order: Forward __text order — transcode(packet:) 0x101a1ae90, stop() 0x101a1be30.
extension FFmpegAssetTrack {
    /// ⚑[tool=llvm-objdump ref=FFmpegAssetTrack.transcode(packet:):0x101a1ae90 result=64-instr]
    /// `swift_allocObject(size: 0x48, align: 7)` for a `Packet`, whose default initializer runs
    /// inline — the numeric fields and `isFlush` are zeroed and `corePacket` is filled from
    /// av_packet_alloc. Then av_packet_ref copies the incoming packet into it, `self` is stored
    /// into `assetTrack` at 0x40 (old value released, new retained, then the `didSet` observer
    /// at 0x101a637d0 runs), and finally `subtitle` (0x100) dispatches metadata offset 0x1a0 ⇒
    /// slot 26, impl 0x101a5bab4 — which takes x0 and branches on the state byte at 0x28 being
    /// 2 (.flush), i.e. `putPacket(packet:)`.
    /// ⚑[tool=ffmpeg_name_oracle ref=av_packet_alloc:0x102d61878 result=CONFIRMED]
    /// ⚑[tool=ffmpeg_name_oracle ref=av_packet_ref:0x102d622ec result=CONFIRMED]
    /// ⚑[tool=vtable_walk ref=SyncPlayerItemTrack:slot26@0x101a5bab4 result=putPacket(packet:)]
    func transcode(packet: UnsafeMutablePointer<AVPacket>) {
        let newPacket = Packet()
        av_packet_ref(newPacket.corePacket, packet)
        newPacket.assetTrack = self
        subtitle?.putPacket(packet: newPacket)
    }

    /// ⚑[tool=llvm-objdump ref=FFmpegAssetTrack.stop():0x101a1be30 result=17-instr]
    /// Same shape as `flush`, dispatching metadata offset 0x1c0 ⇒ slot 30, impl 0x101a5bc34.
    /// That impl is arity-0 (it never reads x0), returns early when the state byte at 0x28 is
    /// 0 (.idle), sets it to 3 (.closed) and drains the render queue — `shutdown()`.
    /// ⚑[tool=vtable_walk ref=SyncPlayerItemTrack:slot30@0x101a5bc34 result=shutdown()]
    /// REJECTED anchor: reconstruction/build_match_release.json proposes `putPacket` for
    /// 0x101a5bc34 at similarity 0.5342 with 3603 matches over threshold — a fingerprint that
    /// cannot discriminate is never identity, and putPacket takes an argument this body never
    /// reads.
    @used func stop() {
        subtitle?.shutdown()
    }
}

//  Forward 1.3.17 reconstruction — P2 remux cluster (Wave 1).
//  Forward type (binary-confirmed name). Protocol descriptor @0x1039eefa0 declares exactly
//  3 instance methods, no defaults (binary fact — __swift5_proto). The witness slots are
//  GROUNDED from the Copy/BSF witness bodies (CopyTC_req1 @0x101a1bee0, BSFTC_req1 @0x101a1bf28,
//  BSFTC_req3 @0x101a1bfe4); the protocol method *names* are not in the binary → inferred + FLAGGED.
//  Conformers: CopyTranscodeContext, BSFTranscodeContext (this wave) + Audio/Video/Subtitle (later).
public protocol TranscodeProtocol {
    // ── req1 / witness slot 1 — the per-stream packet op (GROUNDED) ──────────────────────────────
    // Body shape (from Copy/BSF witnesses): take an INPUT packet + an OUTPUT packet (caller buffer)
    // + a COMPLETION closure that receives the output; on success set output.pts = -1 (AV_NOPTS) then
    // call completion(output)  (decompile: `param_2[9] = -1` then `(*param_3)(param_2)`).
    // I/O type GROUNDED: `UnsafeMutablePointer<AVPacket>?` (= OutputStreamInfo.outPacket; av_bsf_send_packet
    // takes `AVPacket*`). ⚑ method name `transcode` INFERRED (not in binary). ⚑ closure convention
    // (escaping/label) inferred from the call `(*param_3)(param_2)` = completion(output).
    // ⚑ SIGNATURE RE-READ (Copy 0x101a1bee0 / BSF 0x101a1bf28 / caller OSI.transcode @0x101a1ae68):
    //   · returns Int32 — BSF's failure paths return the live av_bsf_* result (`mov x20,x0 … mov x0,x20` around
    //     av_packet_unref), and the success path returns the completion's x0 unchanged (tail `blr`), which
    //     OSI.transcode (`-> Int32`) returns as its own result;
    //   · completion returns Int32 (OSI's closure 0x101a1af90 ends `mov x0,x22`), non-escaping (stack context);
    //   · `output` is NON-optional: `str #-1,[output,#0x48]` has no nil check in either conformer.
    func transcode(_ input: UnsafeMutablePointer<AVPacket>,
                   output: UnsafeMutablePointer<AVPacket>,
                   completion: (UnsafeMutablePointer<AVPacket>) -> Int32) -> Int32

    // ── req2 / witness slot 2 — ATC-distinctive (re-encode drain) ────────────────────────────────
    // DEFERRED: the re-encode (ATC) path, off the remux test. Binary requires 3 methods, so it is
    // declared; Copy/BSF satisfy it with a SHARED/trivial witness (implemented trivially below).
    // ⚑ name + signature INFERRED placeholder. // UNRESOLVED → re-encode (ATC) phase
    // ⚑ req2 ARITY RE-READ: Audio's witness 0x101a1cc00 forwards (x0 packet, x1/x2 closure) + returns w0;
    //   OSI.writeTrailer calls it as (outPacket, closure 0x101a1f1dc). Copy/BSF/Video/Subtitle all share the
    //   ICF-folded `mov w0,#0; ret` (0x10002dab0) = `return 0`.
    func drain(_ output: UnsafeMutablePointer<AVPacket>,
               completion: (UnsafeMutablePointer<AVPacket>) -> Int32) -> Int32

    // ── req3 / witness slot 3 — teardown/close (GROUNDED from BSFTC_req3) ────────────────────────
    // BSF witness body = `av_bsf_free(&self.bsfContext)`. Copy's witness is trivial (shared/no-op).
    // ⚑ method name `close` INFERRED (not in binary).
    func close()
}

//  Forward 1.3.17 reconstruction — P2 remux cluster (Wave 1).
//  TranscodeProtocol conformer. Binary: 0 stored fields, root class. The stream-copy (no-transcode)
//  path: copy the input packet into the caller's output buffer, stamp AV_NOPTS, fire completion.
//  Body GROUNDED from CopyTC_req1 @0x101a1bee0. req2/req3 = trivial shared witness.
public final class CopyTranscodeContext: TranscodeProtocol, Sendable {  // `final` not binary-pinned (no library evolution); 0 fields → no stored state
    public init() {}  // root class, 0 fields — devirt init has no readable body; minimal inferred init
    // Forward's copy branch of OutputStreamInfo.transcode(packet:block:) does not allocate: it calls this
    // class's metadata accessor (0x101a1f188) and then swift_initStaticObject(metadata, 0x1044e8be8)
    // (@0x101a1addc-0x101a1adec). That is a statically initialized global object, which is what a
    // `static let` of this 0-field class becomes. No symbol names the global (it is not in the export
    // trie and Ghidra has no label at 0x1044e8be8), so the name is INFERRED. `Sendable` is a marker
    // conformance with no record; Swift 6 needs it for the static let.
    static let shared = CopyTranscodeContext()  // INFERRED

    // req1 — stream-copy packet op @0x101a1bee0 (the witness itself; self unused):
    //   av_packet_ref(output, input) (0x102d622ec — body read: ref/alloc buf + copy props; result DISCARDED —
    //   the next instruction is the store), output.pos (+0x48) = -1, return completion(output).
    public func transcode(_ input: UnsafeMutablePointer<AVPacket>,
                          output: UnsafeMutablePointer<AVPacket>,
                          completion: (UnsafeMutablePointer<AVPacket>) -> Int32) -> Int32 {
        _ = av_packet_ref(output, input)
        output.pointee.pos = -1
        return completion(output)
    }

    // req2 — the shared ICF-folded witness 0x10002dab0 (`mov w0,#0; ret`).
    public func drain(_ output: UnsafeMutablePointer<AVPacket>,
                      completion: (UnsafeMutablePointer<AVPacket>) -> Int32) -> Int32 {
        0
    }

    // req3 — Copy's witness is the empty `ret` fold 0x10000e52c.
    public func close() {}
}

//  Forward 1.3.17 reconstruction — P2 remux cluster (Wave 1).
//  TranscodeProtocol conformer. Binary: 1 stored field `bsfContext` (+0x10), root class. The
//  bitstream-filter path: send the input packet through the BSF, receive the filtered packet into
//  the caller's output buffer, stamp AV_NOPTS, fire completion; teardown frees the BSF.
//  Bodies GROUNDED from BSFTC_req1 @0x101a1bf28 and BSFTC_req3 @0x101a1bfe4.
//  av_bsf_* are oracle-CONFIRMED names → used directly. The packet-unref helper (FUN_102d61970) is
//  name-UNRESOLVED → spine only.
public final class BSFTranscodeContext: TranscodeProtocol {  // `final` not binary-pinned (no library evolution)
    // Field +0x10 (binary __swift5_fieldmd). FFmpeg C type. Accessed under _swift_beginAccess in req1/req3.
    public var bsfContext: UnsafeMutablePointer<AVBSFContext>?

    // init devirtualized (no readable body). Minimal inferred init — the bsfContext is supplied by the
    // Remuxer once the filter is allocated/initialised; exact init signature unrecoverable → inferred.
    public init(bsfContext: UnsafeMutablePointer<AVBSFContext>? = nil) {  // inferred — devirt init, no body
        self.bsfContext = bsfContext
    }

    // req1 — BSF packet op @0x101a1bf28 (witness thunk 0x101a1bfc4 loads self from [x20]). Read in full:
    //   beginAccess(read, self+0x10); av_bsf_send_packet(bsfContext, input) (0x10295b31c) → `tbnz w0,#31` return it;
    //   av_bsf_receive_packet(bsfContext, output) (0x10295b40c) → on <0: av_packet_unref(output) (0x102d61970 —
    //   body read: frees side data + buf, resets fields, pos=-1, pts/dts=AV_NOPTS) and return the receive result;
    //   else output.pos (+0x48) = -1, return completion(output).
    public func transcode(_ input: UnsafeMutablePointer<AVPacket>,
                          output: UnsafeMutablePointer<AVPacket>,
                          completion: (UnsafeMutablePointer<AVPacket>) -> Int32) -> Int32 {
        var ret = av_bsf_send_packet(bsfContext, input)
        if ret < 0 {
            return ret
        }
        ret = av_bsf_receive_packet(bsfContext, output)
        if ret < 0 {
            av_packet_unref(output)
            return ret
        }
        output.pointee.pos = -1
        return completion(output)
    }

    // req2 — the shared ICF-folded witness 0x10002dab0 (`mov w0,#0; ret`).
    public func drain(_ output: UnsafeMutablePointer<AVPacket>,
                      completion: (UnsafeMutablePointer<AVPacket>) -> Int32) -> Int32 {
        0
    }

    // req3 / witness slot 3 — teardown. GROUNDED (BSFTC_req3 @0x101a1bfe4):
    //   av_bsf_free(&self.bsfContext)   (the _swift_beginAccess/_swift_endAccess pair = inout access)
    public func close() {
        av_bsf_free(&bsfContext)  // oracle-CONFIRMED name; takes AVBSFContext** → &self.bsfContext
    }

}

//  Forward 1.3.17 reconstruction — P2 remux cluster (re-encode trio).
//  Forward type (binary-confirmed name). TranscodeProtocol conformer for the AUDIO re-encode path.
//  Built by FFmpegUtility.write()'s audio arm (0x101a1d014 family). Descriptor 0x1039ef050 / accessor
//  0x101a1f284; vtable-empty (real methods in the TranscodeProtocol witness table). 9 stored fields
//  (reflection-authoritative). Witness bodies reconstructed in L7 lane 16 (I6) from 0x101a1c02c..0x101a1cc2c.
public final class AudioTranscodeContext: TranscodeProtocol {  // `final` not binary-pinned (M2 verifies)
    // Field types: field-record concrete where resolvable; ⚑ = symref/§7-walled → name-inference-flagged.
    let decodeContext: UnsafeMutablePointer<AVCodecContext>      // field-record concrete
    let encodeContext: UnsafeMutablePointer<AVCodecContext>      // field-record concrete
    // ⚑ L7 lane 16: Forward init 0x101a1c068-0x101a1c06c — av_frame_alloc() (0x103240100) is the FIRST
    //   store (`str x0,[self,#0x20]`), before either context exists → a field default, not an init statement.
    var decodedFrame:  UnsafeMutablePointer<AVFrame>? = av_frame_alloc()  // field-record concrete (optional)
    // ⚑[tool=field_surface ref=AudioTranscodeContext.fifo,pts result=forward OpaquePointer (non-optional), Int64]
    var fifo:          OpaquePointer                             // AVAudioFifo*; Forward init 0x101a1c104 `str x0,[self,#0x28]` after a cbz→brk unwrap
    var pts:           Int64 = 0                                 // Forward init 0x101a1c070 `stp xzr,xzr,[self,#0x30]` (pts, swrContext)
    var swrContext:    OpaquePointer? = nil                      // ⚑ SwrContext* (opaque; codebase typealiases SwrContext=OpaquePointer)
    // ⚑ L7 lane 16: channel/sampleFormat/sampleRate have NO default store in Forward's init (0x101a1c02c):
    //   their only writes are the decode-context copies at 0x101a1c108-0x101a1c12c → no initial values here.
    var channel:       AVChannelLayout                           // field-record concrete
    var sampleFormat:  AVSampleFormat                            // field-record concrete
    var sampleRate:    Int32                                     // ⚑ symref-walled; FFmpeg sample_rate is `int`(32) + siblings are FFmpeg-typed → Int32. l2_field_gate's `Int?` is an UNSCOPED property-symbol (another class's sampleRate) — adjudicated noise.

    // ⚑ L7-17: Forward init 0x101a1c02c is `(codecpar x0, codecID x1) throws`: decodeContext =
    //   try codecpar.createContext(options: nil) (0x101a07dc8, x0=nil, x20=codecpar) → +0x10, then
    //   encodeContext = try createEncoderContext(codecID:) (0x101a08a94, x20 still codecpar) → +0x18.
    //   A throw from either lands in swift_deallocPartialClassInstance(self, meta, 0x60, 7) (0x101a1c0a8).
    public init(codecpar: UnsafeMutablePointer<AVCodecParameters>, codecID: AVCodecID) throws { // INFERRED labels
        decodeContext = try codecpar.pointee.createContext(options: nil)
        encodeContext = try codecpar.pointee.createEncoderContext(codecID: codecID)
        // Forward init 0x101a1c0ec-0x101a1c104: av_audio_fifo_alloc(encode +0x15c sample_fmt,
        // +0x164 ch_layout.nb_channels, +0x178 frame_size)!.
        fifo = av_audio_fifo_alloc(encodeContext.pointee.sample_fmt, encodeContext.pointee.ch_layout.nb_channels, encodeContext.pointee.frame_size)!
        // ⚑ L7 lane 16: 0x101a1c108-0x101a1c12c — `ldp x8,x9,[self,#0x10]` reloads both contexts FROM SELF
        //   (hence `self.`), then copies decode ch_layout (+0x160, 24 B) → +0x40, sample_fmt (+0x15c) → +0x58,
        //   sample_rate (+0x158) → +0x5c.
        channel = self.decodeContext.pointee.ch_layout
        sampleFormat = self.decodeContext.pointee.sample_fmt
        sampleRate = self.decodeContext.pointee.sample_rate
        // ⚑ L7 lane 16: 0x101a1c130-0x101a1c17c — ALL six operands are loaded before the single
        //   av_channel_layout_compare (0x103237220) call, then fmt (w24/w25) and rate (w20/w23) are compared
        //   in that order → a 3-tuple `!=` (a short-circuit `||` would load fmt/rate after the opaque C call,
        //   as transcode 0x101a1c2ec does). The lhs rate is w20 — the value just stored to +0x5c, not reloaded
        //   (the lhs fmt IS reloaded from decode+0x15c after the +0x58 store) → lhs rate = self.sampleRate.
        //   Any difference → setupSwrContext() (0x101a1c184).
        if (self.decodeContext.pointee.ch_layout, self.decodeContext.pointee.sample_fmt, sampleRate)
            != (self.encodeContext.pointee.ch_layout, self.encodeContext.pointee.sample_fmt, self.encodeContext.pointee.sample_rate) {
            setupSwrContext()
        }
    }

    // ⚑ L7 lane 16: 0x101a1c198 — own (non-inlined) function, x20 = self, called from init (0x101a1c184)
    //   and transcode (0x101a1c310). Loads decode/encode fmt+rate first, then modify-access (0x21) on
    //   swrContext (+0x38) around swr_alloc_set_opts2 (0x103288ad4; out = encode, in = decode, log 0/nil).
    //   `cbnz w19` skips on a non-zero result; else swr_init (0x1034499dc, swrContext read unaccessed)
    //   and on `< 0` a second modify access around swr_free(&swrContext) (0x10344997c).
    private final func setupSwrContext() { // INFERRED
        let result = swr_alloc_set_opts2(&swrContext, &encodeContext.pointee.ch_layout, encodeContext.pointee.sample_fmt, encodeContext.pointee.sample_rate, &decodeContext.pointee.ch_layout, decodeContext.pointee.sample_fmt, decodeContext.pointee.sample_rate, 0, nil)
        if result == 0, swr_init(swrContext) < 0 {
            swr_free(&swrContext)
        }
    }

    // ⚑ L7 lane 16: 0x101a1c990 — own function (x0 frameSize, x1 output, x2/x3 completion, x20 self);
    //   called out-of-line by the drain witness 0x101a1cc00 with frameSize 1 and INLINED into transcode
    //   (0x101a1c6ac-0x101a1c7b8, frameSize = encode +0x178). ret starts 0 (0x101a1c9e4); loop while
    //   av_audio_fifo_size (0x10322e64c) >= frameSize; frameSize 1 re-reads the fifo size (0x101a1c9f8);
    //   av_frame_alloc nil → break (0x101a1ca14); fills nb_samples/format/ch_layout/sample_rate from the
    //   encoder; av_frame_get_buffer(frame, 0) (0x103240344) or av_audio_fifo_read (0x10322e654, the frame
    //   pointer itself = &frame.data) < 0 → av_frame_free + break (0x101a1cad0); nb_samples = read count,
    //   pts = self.pts, self.pts += count (`adds … b.vs` trap); avcodec_send_frame (0x102a64b44) result is
    //   held across av_frame_free(&frame) (0x1032401a0); only a >= 0 send drains avcodec_receive_packet
    //   (0x102a6506c) == 0 → output.pos = -1, ret = completion(output).
    private final func encodeFrames(frameSize: Int32, output: UnsafeMutablePointer<AVPacket>, completion: (UnsafeMutablePointer<AVPacket>) -> Int32) -> Int32 { // INFERRED
        var ret: Int32 = 0
        while av_audio_fifo_size(fifo) >= frameSize {
            let size = frameSize == 1 ? av_audio_fifo_size(fifo) : frameSize
            var frame = av_frame_alloc()
            guard let outFrame = frame else {
                break
            }
            outFrame.pointee.nb_samples = size
            outFrame.pointee.format = encodeContext.pointee.sample_fmt.rawValue
            outFrame.pointee.ch_layout = encodeContext.pointee.ch_layout
            outFrame.pointee.sample_rate = encodeContext.pointee.sample_rate
            if av_frame_get_buffer(outFrame, 0) < 0 {
                av_frame_free(&frame)
                break
            }
            // ⚑ L7 lane 16: x1 = the AVFrame pointer itself (data is at +0x0) — a pointer cast, not an array.
            let samples = av_audio_fifo_read(fifo, UnsafeMutableRawPointer(outFrame).assumingMemoryBound(to: UnsafeMutableRawPointer?.self), size)
            if samples < 0 {
                av_frame_free(&frame)
                break
            }
            outFrame.pointee.nb_samples = samples
            outFrame.pointee.pts = pts
            pts += Int64(samples)
            let result = avcodec_send_frame(encodeContext, outFrame)
            av_frame_free(&frame)
            if result >= 0 {
                while avcodec_receive_packet(encodeContext, output) == 0 {
                    output.pointee.pos = -1
                    ret = completion(output)
                }
            }
        }
        return ret
    }

    // req1 — ⚑ L7 lane 16: 0x101a1c260 (witness thunk 0x101a1cbe0 `ldr x20,[x20]`).
    //   avcodec_send_packet (0x102a1a424) < 0 → return it. Short-circuit layout / fmt / rate compare against
    //   the cached fields (0x101a1c2dc-0x101a1c308) → setupSwrContext() then re-cache (0x101a1c314-0x101a1c330).
    //   Read accesses on decodedFrame/swrContext are hoisted out of the receive loop (0x101a1c334/0x101a1c348).
    //   Nil decodedFrame → re-test receive (0x101a1c378: `continue`). Swr path (0x101a1c398-0x101a1c6a0):
    //   linesize via av_samples_get_buffer_size(&linesize, enc nb_channels, nb_samples, enc fmt, 1)
    //   (0x10325c4c0, result unused); a range map of per-channel UInt8 allocations (reserve 0x1019afcf0 +
    //   swift_slowAlloc(linesize, -1)); swr_get_out_samples (0x10328a524); the 8-way data tuple map
    //   (0x1019afcc4 reserve 8 + 8 unrolled appends); swr_convert (0x103289134) with both array bases;
    //   an UnsafeMutablePointer<UnsafeMutableRawPointer?> of outData.count (`lsr #60` check + slowAlloc) filled
    //   element-wise (vectorized copy, alias check 0x101a1c624); av_audio_fifo_write (0x10322e548); then the
    //   optional per-channel deallocs (0x101a1c7c4), the data dealloc (0x101a1c694). Non-swr path
    //   (0x101a1c460): fifo_write(fifo, <frame ptr>, nb_samples). Then av_frame_unref (0x1032401d4) and
    //   the inlined encodeFrames(frameSize: encode +0x178).
    public func transcode(_ input: UnsafeMutablePointer<AVPacket>,
                          output: UnsafeMutablePointer<AVPacket>,
                          completion: (UnsafeMutablePointer<AVPacket>) -> Int32) -> Int32 {
        var ret = avcodec_send_packet(decodeContext, input)
        if ret < 0 {
            return ret
        }
        if decodeContext.pointee.ch_layout != channel || decodeContext.pointee.sample_fmt != sampleFormat || decodeContext.pointee.sample_rate != sampleRate {
            setupSwrContext()
            channel = decodeContext.pointee.ch_layout
            sampleFormat = decodeContext.pointee.sample_fmt
            sampleRate = decodeContext.pointee.sample_rate
        }
        while avcodec_receive_frame(decodeContext, decodedFrame) == 0 {
            guard let decodedFrame else {
                continue
            }
            if let swrContext {
                var linesize = Int32(0)
                let nbSamples = decodedFrame.pointee.nb_samples
                _ = av_samples_get_buffer_size(&linesize, encodeContext.pointee.ch_layout.nb_channels, nbSamples, encodeContext.pointee.sample_fmt, 1)
                let outData: [UnsafeMutablePointer<UInt8>?] = (0 ..< Int(encodeContext.pointee.ch_layout.nb_channels)).map { _ in
                    UnsafeMutablePointer<UInt8>.allocate(capacity: Int(linesize))
                }
                let outSamples = swr_get_out_samples(swrContext, nbSamples)
                let frameBuffer = Array(tuple: decodedFrame.pointee.data).map { UnsafePointer<UInt8>($0) }
                let samples = swr_convert(swrContext, outData, outSamples, frameBuffer, nbSamples)
                let data = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: outData.count)
                for i in 0 ..< outData.count {
                    data[i] = UnsafeMutableRawPointer(outData[i])
                }
                _ = av_audio_fifo_write(fifo, data, samples)
                outData.forEach { $0?.deallocate() }
                data.deallocate()
            } else {
                // ⚑ L7 lane 16: 0x101a1c460 — x1 = the AVFrame pointer itself (&frame.data), a pointer cast.
                _ = av_audio_fifo_write(fifo, UnsafeMutableRawPointer(decodedFrame).assumingMemoryBound(to: UnsafeMutableRawPointer?.self), decodedFrame.pointee.nb_samples)
            }
            av_frame_unref(decodedFrame)
            ret = encodeFrames(frameSize: encodeContext.pointee.frame_size, output: output, completion: completion)
        }
        return ret
    }

    // req2 — ⚑ L7 lane 16: witness 0x101a1cc00 = `ldr x20,[x20]; mov w0,#1; bl 0x101a1c990` (drain the fifo
    //   in whatever-is-left chunks).
    public func drain(_ output: UnsafeMutablePointer<AVPacket>,
                      completion: (UnsafeMutablePointer<AVPacket>) -> Int32) -> Int32 {
        encodeFrames(frameSize: 1, output: output, completion: completion)
    }

    // req3 — ⚑ L7 lane 16: 0x101a1cb1c. av_frame_free(&decodedFrame) under a modify access (0x21);
    //   each context copied to a stack slot → avcodec_free_context (0x102d53ac8) (a `let` field cannot be
    //   passed inout, so a local var copy); swr_free(&swrContext) under a modify access; av_audio_fifo_free
    //   (0x10322e2f8).
    public func close() {
        av_frame_free(&decodedFrame)
        var decodeContext: UnsafeMutablePointer<AVCodecContext>? = self.decodeContext
        avcodec_free_context(&decodeContext)
        var encodeContext: UnsafeMutablePointer<AVCodecContext>? = self.encodeContext
        avcodec_free_context(&encodeContext)
        swr_free(&swrContext)
        av_audio_fifo_free(fifo)
    }
}

//  Forward 1.3.17 reconstruction — P2 remux cluster (re-encode trio).
//  Forward type (binary-confirmed name). TranscodeProtocol conformer for the SUBTITLE re-encode path.
//  Descriptor 0x1039ef094 / accessor 0x101a1f2a4; vtable-empty (witness-table methods). 3 stored fields
//  (reflection-authoritative, all concrete). Witness bodies: L7 lane 16 (I6).
public final class SubtitleTranscodeContext: TranscodeProtocol {  // `final` not binary-pinned (M2 verifies)
    let decodeContext: UnsafeMutablePointer<AVCodecContext>      // field-record concrete
    let encodeContext: UnsafeMutablePointer<AVCodecContext>      // field-record concrete
    var subtitle:      AVSubtitle = AVSubtitle()                 // field-record concrete (the decoded AVSubtitle)

    // ⚑ L7 lane 17: no standalone init in Forward — inlined into write 0x101a1d014 (alloc 0x40 via
    //   accessor 0x101a1f2a4, subtitle +0x20..0x3c zeroed; createContext(options: nil) 0x101a07dc8 → +0x10,
    //   throw → 0x101a1eb98; encoder builder 0x101a08a94 → +0x18, throw → 0x101a1eba0).
    public init(codecpar: UnsafeMutablePointer<AVCodecParameters>, codecID: AVCodecID) throws { // INFERRED labels
        decodeContext = try codecpar.pointee.createContext(options: nil)
        encodeContext = try codecpar.pointee.createEncoderContext(codecID: codecID)
    }

    // req1 — ⚑ L7 lane 16: 0x101a1cc50 (witness thunk 0x101a1cda8). gotSubtitle = 0 on the stack;
    //   avcodec_decode_subtitle2 (0x102a1a98c) under a MODIFY access (0x21) on subtitle (+0x20);
    //   `< 0` or gotSubtitle == 0 → return ret. av_new_packet(output, 0x100000) (0x102d61a08, result
    //   unused); data (+0x18) / size (+0x20) loaded BEFORE the READ access (0x20) for
    //   avcodec_encode_subtitle (0x102a64918); `< 0` → return; av_shrink_packet(output, ret) (0x102d61ab8),
    //   size = ret, then pts/dts/duration copied from input (+0x8/+0x10/+0x40) — pos is NOT stamped.
    public func transcode(_ input: UnsafeMutablePointer<AVPacket>,
                          output: UnsafeMutablePointer<AVPacket>,
                          completion: (UnsafeMutablePointer<AVPacket>) -> Int32) -> Int32 {
        var gotSubtitle: Int32 = 0
        var ret = avcodec_decode_subtitle2(decodeContext, &subtitle, &gotSubtitle, input)
        guard ret >= 0, gotSubtitle != 0 else {
            return ret
        }
        _ = av_new_packet(output, 1024 * 1024)
        ret = avcodec_encode_subtitle(encodeContext, output.pointee.data, output.pointee.size, &subtitle)
        guard ret >= 0 else {
            return ret
        }
        av_shrink_packet(output, ret)
        output.pointee.size = ret
        output.pointee.pts = input.pointee.pts
        output.pointee.dts = input.pointee.dts
        output.pointee.duration = input.pointee.duration
        return completion(output)
    }
    public func drain(_ output: UnsafeMutablePointer<AVPacket>,
                      completion: (UnsafeMutablePointer<AVPacket>) -> Int32) -> Int32 {
        return 0  // req2 = shared ICF fold 0x10002dab0 (`mov w0,#0; ret`)
    }
    // req3 — ⚑ L7 lane 16: witness 0x101a1cdc8 tail-calls the merged body 0x101a1cf7c with x2 = avsubtitle_free
    //   (0x10294d330): modify access (0x21) on +0x20 → free(&field); then both contexts via stack copies →
    //   avcodec_free_context (0x102d53ac8). VideoTranscodeContext.close() is the same body with av_frame_free.
    public func close() {
        avsubtitle_free(&subtitle)
        var decodeContext: UnsafeMutablePointer<AVCodecContext>? = self.decodeContext
        avcodec_free_context(&decodeContext)
        var encodeContext: UnsafeMutablePointer<AVCodecContext>? = self.encodeContext
        avcodec_free_context(&encodeContext)
    }
}

//  Forward 1.3.17 reconstruction — P2 remux cluster (re-encode trio).
//  Forward type (binary-confirmed name). TranscodeProtocol conformer for the VIDEO re-encode path.
//  Descriptor 0x1039ef0d8 / accessor 0x101a1f2c4; vtable-empty (witness-table methods).
//  3 stored fields (reflection-authoritative, all field-record concrete). Witness bodies: L7 lane 16 (I6).
public final class VideoTranscodeContext: TranscodeProtocol {  // `final` not binary-pinned (M2 verifies)
    let decodeContext: UnsafeMutablePointer<AVCodecContext>      // field-record concrete
    let encodeContext: UnsafeMutablePointer<AVCodecContext>      // field-record concrete
    var decodedFrame:  UnsafeMutablePointer<AVFrame>? = nil      // field-record concrete (optional)

    // ⚑ L7 lane 17: no standalone init in Forward — inlined into write 0x101a1d014 (alloc 0x40 via
    //   accessor 0x101a1f2a4, subtitle +0x20..0x3c zeroed; createContext(options: nil) 0x101a07dc8 → +0x10,
    //   throw → 0x101a1eb98; encoder builder 0x101a08a94 → +0x18, throw → 0x101a1eba0).
    public init(codecpar: UnsafeMutablePointer<AVCodecParameters>, codecID: AVCodecID) throws { // INFERRED labels
        decodeContext = try codecpar.pointee.createContext(options: nil)
        encodeContext = try codecpar.pointee.createEncoderContext(codecID: codecID)
    }

    // req1 — ⚑ L7 lane 16: 0x101a1ce14 (witness thunk 0x101a1cf10). avcodec_send_packet (0x102a1a424)
    //   < 0 → return it; read access (flags 0) on decodedFrame hoisted (0x101a1ce5c); while
    //   avcodec_receive_frame (0x10294dba0) == 0: avcodec_send_frame (0x102a64b44) with the optional frame
    //   (no nil test), av_frame_unref (0x1032401d4) BEFORE the result test, then a >= 0 send drains
    //   avcodec_receive_packet (0x102a6506c) == 0 → output.pos = -1, ret = completion(output).
    public func transcode(_ input: UnsafeMutablePointer<AVPacket>,
                          output: UnsafeMutablePointer<AVPacket>,
                          completion: (UnsafeMutablePointer<AVPacket>) -> Int32) -> Int32 {
        var ret = avcodec_send_packet(decodeContext, input)
        if ret < 0 {
            return ret
        }
        while avcodec_receive_frame(decodeContext, decodedFrame) == 0 {
            let result = avcodec_send_frame(encodeContext, decodedFrame)
            av_frame_unref(decodedFrame)
            if result >= 0 {
                while avcodec_receive_packet(encodeContext, output) == 0 {
                    output.pointee.pos = -1
                    ret = completion(output)
                }
            }
        }
        return ret
    }
    public func drain(_ output: UnsafeMutablePointer<AVPacket>,
                      completion: (UnsafeMutablePointer<AVPacket>) -> Int32) -> Int32 {
        return 0  // req2 = shared ICF fold 0x10002dab0 (`mov w0,#0; ret`)
    }
    // req3 — ⚑ L7 lane 16: witness 0x101a1cf30 tail-calls the merged body 0x101a1cf7c with x2 = av_frame_free
    //   (0x1032401a0) — same shape as SubtitleTranscodeContext.close().
    public func close() {
        av_frame_free(&decodedFrame)
        var decodeContext: UnsafeMutablePointer<AVCodecContext>? = self.decodeContext
        avcodec_free_context(&decodeContext)
        var encodeContext: UnsafeMutablePointer<AVCodecContext>? = self.encodeContext
        avcodec_free_context(&encodeContext)
    }
}

public class OutputStreamInfo: @unchecked Sendable { // NON-final (P21): parse_class_descriptor gives OSI a 16-slot method vtable (slots 0-15,
                                      // incl. slot13/14/15 dispatched by RemuxerIOAction via +0x118/+0x120/+0x128) — a `final class`
                                      // emits NO method vtable, so `final` was the structural bug (as LocalHLSServer/ProAVPlayer/ProPlayerItem).
                                      // ⚑ EXACT 16-slot layout = tracked structural debt (member-level finality/order — vtable_anchor_diff, not fabricated).
    // Types from the class's own __swift5_fieldmd field-records (authoritative). Reflection order.
    // Map KEYS are Int32 (faithfulness correction, 3 signals: subscript hashes 4 bytes; key = AVPacket
    // stream_index which is C `int`; field-record key = stdlib symref, libswiftCore-walled).
    public var assetTrackMap: [Int32: FFmpegAssetTrack] = [:]      // +0x10  key Int32 (stream_index) ⚑ value confirmed
    // ⚑ L7 lane 14: no default — Forward's vpfi set is assetTrackMap/lastDTSMap/hasWriteTrailer/outPacket only.
    public private(set) var transcodeMap:  [Int32: any TranscodeProtocol] // +0x18  vtable: getter impl, setter/modify null
    // ⚑[tool=binding_gate ref=OutputStreamInfo:__swift5_fieldmd result=pinned — binary says `let`, source cannot be]
    //   Session 61 binding sweep: these fields' FieldRecord flags word is 0x00000000
    //   (= `let`), but the Swift compiler REFUSES that spelling here. Left as `var`.
    //   • outPacket — passed as an inout argument
    //   Real divergence, not fixable by a keyword flip. Detail + the full 33:
    //   reconstruction/binding_refuted_s61.json
    //   RESOLVED in session 62: formatName, frameRate, removeADTS, streamMapping, timeBaseMap
    //   and url are now `let`. The designated init assigns all six from init-locals computed
    //   over its parameters, so their defaults were never observable. What had blocked them
    //   was OUR OWN Phase-1 test scaffold init (below), which left them to those defaults —
    //   a second designated init doing that cannot compile against a `let`, so the binary's
    //   bindings independently confirm the scaffold is not in the original. It now takes the
    //   three values the test varies as parameters instead. `outPacket` still stands.
    public let timeBaseMap:   [Int32: AVRational]  // +0x20
    public let frameRate:     Int  // v4 concrete `Si`
    public let url:           String  // v4 concrete `SS`
    public let streamMapping: [Int32: Int32]  // +0x40  ⚑ value width inferred (verify)
    private var lastDTSMap:    [Int32: Int64] = [:]                 // +0x48  key Int32; value Int64 (DTS)
    private var hasWriteTrailer: Bool = false                     // v4 concrete `Sb`
    public let formatCtx:     UnsafeMutablePointer<AVFormatContext>  // v4 concrete (non-optional → init param)
    // ⚑ L7 lane 14: pfi `variable initialization expression of OutputStreamInfo.(outPacket in _3E45B09B…)`
    //   (0x10199acb8; discriminator = MD5("KSPlayer"+"FFmpeg+Conversion.swift")) → default av_packet_alloc().
    private let outPacket:     UnsafeMutablePointer<AVPacket>? = av_packet_alloc()  // field flags 0 (`let`)
    public let formatName:    String  // v4 concrete `SS`
    public let removeADTS:    Bool  // v4 concrete `Sb`

    // ⚑ L7 lane 14 (#69/#14): internal fields-only init. Forward's trie has no OutputStreamInfo init
    //   symbol; FFmpegUtility.write's FSO body 0x101a1d014 does all the work and allocates the instance
    //   last (swift_allocObject 0x79 @0x101a1e828), then stores: the three defaulted fields (+0x10, +0x48,
    //   +0x50), outPacket's default av_packet_alloc (+0x60), url (+0x30/+0x38), timeBaseMap (+0x20),
    //   formatCtx (+0x58), formatName = String(cString: oformat.name) with both unwraps trapping
    //   (brk 0x101a1ee7c / 0x101a1ee80) (+0x68), streamMapping (+0x40), transcodeMap (+0x18),
    //   frameRate (+0x28), removeADTS (+0x78).
    init(url: String,
         formatCtx: UnsafeMutablePointer<AVFormatContext>,
         timeBaseMap: [Int32: AVRational],
         streamMapping: [Int32: Int32],
         transcodeMap: [Int32: any TranscodeProtocol],
         frameRate: Int,
         removeADTS: Bool) {
        self.url = url
        self.timeBaseMap = timeBaseMap
        self.formatCtx = formatCtx
        formatName = String(cString: formatCtx.pointee.oformat.pointee.name)
        self.streamMapping = streamMapping
        self.transcodeMap = transcodeMap
        self.frameRate = frameRate
        self.removeADTS = removeADTS
    }

    public func transcode(packet: UnsafeMutablePointer<AVPacket>, block: ((UnsafeMutablePointer<AVPacket>) -> Void)?) -> Int32 {
        let index = packet.pointee.stream_index
        if let assetTrack = assetTrackMap[index] {
            assetTrack.transcode(packet: packet)
            return 0
        }
        guard let outPacket, let mapped = streamMapping[index], let timebase = timeBaseMap[index],
              let stream = formatCtx.pointee.streams[Int(mapped)]
        else {
            return 0
        }
        let context: any TranscodeProtocol
        if let existing = transcodeMap[index] {
            context = existing
        } else if removeADTS, stream.pointee.codecpar.pointee.codec_id == AV_CODEC_ID_AAC, packet.pointee.size > 2,
                  packet.pointee.data[0] == 0xFF, packet.pointee.data[1] & 0xF0 == 0xF0,
                  let bsfContext = stream.pointee.codecpar.pointee.makeADTSBitstreamFilter("aac_adtstoasc")
        {
            context = BSFTranscodeContext(bsfContext: bsfContext)
            transcodeMap[index] = context
        } else {
            context = CopyTranscodeContext.shared
        }
        return context.transcode(packet, output: outPacket) { packet in
            block?(packet)
            packet.pointee.stream_index = mapped
            av_packet_rescale_ts(packet, timebase, stream.pointee.time_base)
            let duration = packet.pointee.duration
            let dts = packet.pointee.dts
            var diff: Int64?
            if dts > 0, let lastDTS = self.lastDTSMap[mapped], lastDTS > 0 {
                let value = lastDTS - dts
                diff = value
                if value >= 0, value <= duration {
                    if dts == packet.pointee.pts {
                        packet.pointee.pts = lastDTS + 1
                    }
                    packet.pointee.dts = lastDTS + 1
                } else if self.formatName == "hls", abs(value) > duration * 100 {
                    KSLog("non monotonically increasing dts index=\(mapped),diff=\(value), dts=\(packet.pointee.dts),duration=\(packet.pointee.duration)")
                    av_packet_unref(packet)
                    return -1_919_247_215 // 0x8D9A9C91, read from the Forward closure 0x101a1af90
                }
            }
            if duration == 0 {
                packet.pointee.duration = 1
            } else if duration < 0 || duration > Int64(stream.pointee.time_base.den) {
                KSLog("outputIndex=\(mapped),dts=\(dts),duration=\(duration)")
            }
            self.lastDTSMap[mapped] = packet.pointee.dts
            let ret = av_interleaved_write_frame(self.formatCtx, packet)
            if ret < 0, let diff {
                KSLog("av_interleaved_write_frame result=\(ret),index=\(mapped),diff=\(diff), dts=\(dts),duration=\(duration)")
            }
            av_packet_unref(packet)
            return ret
        }
    }

    // ── slot14 @0x101a1b8d4 (162 instr) — drain-all + write the container trailer, run-once. Void (P44:
    //    plain-ret epilogue). ⚑ method NAME `finishWriting()` INFERRED (devirt; recover_swift_function_name
    //    = None). Called by RemuxerIOAction.cancel (OSI vtable +0x120). The FFmpeg call is
    //    ffmpeg_name_oracle-CONFIRMED (not eyeballed). Cache: decompiles/OutputStreamInfo#14.txt.
    // ⚑ NAME RECOVERED s102, superseding the inferred `finishWriting()`. The export trie carries a
    //   single symbol at this body address — no ICF fold — and it demangles unambiguously:
    //   ⚑[tool=export_trie_oracle ref=$s8KSPlayer16OutputStreamInfoC12writeTraileryyF:0x101a1b8d4 result=writeTrailer]
    //   Corroborated by the caller: MEPlayerItem.startRecord tears the old remuxer down with
    //   `bl 0x101a1b8d4` on `remuxer.outputStreamInfo` (+0x18) @0x101a48430.
    public func writeTrailer() {                            // public (was internal): RemuxerIOAction (ProAVPlayer) calls it cross-module via the OSI vtable +0x120 — binary-arbitrated cross-module access (P34/§1; `open`/override NOT proven → `public` under-included)
        guard !hasWriteTrailer else { return }              // self+0x50 (& 1) — run-once guard [0x101a1b904]
        hasWriteTrailer = true                              // self+0x50 = 1
        for (index, ctx) in transcodeMap {                  // self+0x18 iteration (Swift Dictionary bucket-walk)
            // Gate @0x101a1ba08-0x101a1ba5c: outPacket, streamMapping[index], timeBaseMap[index], then
            // formatCtx.streams[mapped]; the closure (0x101a1f1dc) captures mapped, timebase, the output
            // stream's time_base VALUE (loaded @0x101a1ba70 before the call) and self.
            guard let outPacket, let mapped = streamMapping[index], let timebase = timeBaseMap[index],
                  let stream = formatCtx.pointee.streams[Int(mapped)]
            else {
                continue
            }
            let outTimebase = stream.pointee.time_base
            _ = ctx.drain(outPacket) { packet in
                packet.pointee.stream_index = mapped
                av_packet_rescale_ts(packet, timebase, outTimebase)
                return av_interleaved_write_frame(self.formatCtx, packet)
            }
        }
        av_write_trailer(formatCtx)                         // FUN_103194e1c — ffmpeg_name_oracle CONFIRMED (117/468 exact) [0x101a1b9f0]
        lastDTSMap.removeAll()                              // self+0x48 cleared INSIDE the modify access: beginAccess(+0x48) → store empty singleton → release old [0x101a1bb08]
    }

    // ── slot15 @0x101a1bb5c (181 instr) — close-all: close every transcode ctx + asset track, free the
    //    out-packet and the format context. Void (P44). ⚑ method NAME `close()` INFERRED (devirt). Called by
    //    RemuxerIOAction.cancel (+0x128) + reconstruct. Cache: decompiles/OutputStreamInfo#15.txt.
    // ⚑ NAME RECOVERED s102, superseding the inferred `close()`. Single trie symbol at this body
    //   address, no fold:
    //   ⚑[tool=export_trie_oracle ref=$s8KSPlayer16OutputStreamInfoC4stopyyF:0x101a1bb5c result=stop]
    //   Corroborated by the caller: startRecord calls `bl 0x101a1bb5c` on the same +0x18 receiver
    //   immediately after writeTrailer @0x101a48438. The inner `ctx.close()` below is a DIFFERENT
    //   method — TranscodeProtocol's witness +0x18 — and is deliberately not renamed.
    public func stop() {                                    // public (was internal): RemuxerIOAction calls it cross-module via the OSI vtable +0x128 (P34/§1; `open` not proven → `public` under-included)
        for (_, ctx) in transcodeMap {                      // self+0x18
            ctx.close()                                     // TranscodeProtocol.close (witness +0x18) [0x101a1bce8]
        }
        // self+0x10 — Forward: bridgeObjectRetain_n(dict, 2) (guaranteed collection + iterator copy), then
        // bridgeObjectRelease + outlined consume of the iterator (0x10002239c) = Sequence.forEach shape.
        // Inlined FFmpegAssetTrack.stop(): track+0x100 (`subtitle`) → vtable +0x1c0 (shutdown()).
        assetTrackMap.values.forEach { $0.stop() }
        var outPacket = outPacket                           // Forward stop() @0x101a1bb5c frees a stack copy, no writeback
        av_packet_free(&outPacket)                          // FUN_102d618b8 — ffmpeg_name_oracle CONFIRMED (46/184 exact) [0x101a1be1c]
        // FUN_101a39028 = static FFmpegUtility.close(formatCtx:) (#function "close(formatCtx:)", trie
        // $s8KSPlayer13FFmpegUtilityO5close9formatCtxySpySo15AVFormatContextVGSg_tFZ).
        FFmpegUtility.close(formatCtx: formatCtx)
    }
}
