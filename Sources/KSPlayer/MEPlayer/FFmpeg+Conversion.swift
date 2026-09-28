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
public final class CopyTranscodeContext: TranscodeProtocol {  // `final` not binary-pinned (no library evolution); 0 fields → no stored state
    public init() {}  // root class, 0 fields — devirt init has no readable body; minimal inferred init

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

//  Forward 1.3.17 reconstruction — P2 remux cluster (re-encode trio, STRUCTURE-ONLY).
//  Forward type (binary-confirmed name). TranscodeProtocol conformer for the AUDIO re-encode path.
//  Built by the re-encode driver FUN_101a1d014 (P3-owner) — OFF the remux→segments (M3) path and OFF
//  the P3 DV-decode path (P18 triage). Its witness bodies are the deep swr/fifo audio re-encode engine
//  → DEFERRED (cardinal: structure faithful now; the engine is reconstructed with its behavioral test in
//  the owner phase, NOT invented here). Descriptor 0x1039ef050 / accessor 0x101a1f284; vtable-empty
//  (real methods in the TranscodeProtocol witness table). 9 stored fields (reflection-authoritative).
public final class AudioTranscodeContext: TranscodeProtocol {  // `final` not binary-pinned (M2 verifies)
    // Field types: field-record concrete where resolvable; ⚑ = symref/§7-walled → name-inference-flagged.
    let decodeContext: UnsafeMutablePointer<AVCodecContext>      // field-record concrete
    let encodeContext: UnsafeMutablePointer<AVCodecContext>      // field-record concrete
    var decodedFrame:  UnsafeMutablePointer<AVFrame>? = nil      // field-record concrete (optional)
    // ⚑[tool=field_surface ref=AudioTranscodeContext.fifo,pts result=forward OpaquePointer (non-optional), Int64]
    var fifo:          OpaquePointer                             // AVAudioFifo*; Forward init 0x101a1c104 `str x0,[self,#0x28]` after a cbz→brk unwrap
    var pts:           Int64 = 0                                 // Forward init 0x101a1c070 `stp xzr,xzr,[self,#0x30]` (pts, swrContext)
    var swrContext:    OpaquePointer? = nil                      // ⚑ SwrContext* (opaque; codebase typealiases SwrContext=OpaquePointer)
    var channel:       AVChannelLayout = AVChannelLayout()       // field-record concrete
    var sampleFormat:  AVSampleFormat = AVSampleFormat(rawValue: -1)  // field-record concrete (AV_SAMPLE_FMT_NONE)
    var sampleRate:    Int32 = 0                                 // ⚑ symref-walled; FFmpeg sample_rate is `int`(32) + siblings are FFmpeg-typed → Int32. l2_field_gate's `Int?` is an UNSCOPED property-symbol (another class's sampleRate) — adjudicated noise.

    // init: vtable-empty class, devirt init (slot 0, no readable body) → minimal inferred init taking the
    // two non-optional codec contexts. Real signature unrecoverable → P3/owner refines. ⚑ inferred.
    public init(decodeContext: UnsafeMutablePointer<AVCodecContext>,
                encodeContext: UnsafeMutablePointer<AVCodecContext>) {
        self.decodeContext = decodeContext
        self.encodeContext = encodeContext
        // Forward init 0x101a1c0ec-0x101a1c104: av_audio_fifo_alloc(encode +0x15c sample_fmt,
        // +0x164 ch_layout.nb_channels, +0x178 frame_size)!. The rest of that init (decoder/encoder
        // construction via 0x101a07dc8 / 0x101a08a94, channel/format/rate copy, swr setup 0x101a1c198)
        // is its own unit.
        fifo = av_audio_fifo_alloc(encodeContext.pointee.sample_fmt, encodeContext.pointee.ch_layout.nb_channels, encodeContext.pointee.frame_size)!
    }

    // ── TranscodeProtocol conformance — re-encode WITNESS bodies STRUCTURE-ONLY (DEFERRED, not invented) ──
    // The real witness methods live in the TranscodeProtocol witness table; they are the deep swr/fifo audio
    // re-encode engine, off the M3/P3 path → reconstruct in the owner phase with a re-encode behavioral test.
    public func transcode(_ input: UnsafeMutablePointer<AVPacket>,
                          output: UnsafeMutablePointer<AVPacket>,
                          completion: (UnsafeMutablePointer<AVPacket>) -> Int32) -> Int32 {
        // UNRESOLVED → re-encode engine (witness slot1 @0x101a1c260, 460 instr: swr_convert + AVAudioFifo
        // buffering + encode). NOT reconstructed — structure-only scope.
        return 0  // ⚑ UNRESOLVED stub value — req1 body not reconstructed
    }
    public func drain(_ output: UnsafeMutablePointer<AVPacket>,
                      completion: (UnsafeMutablePointer<AVPacket>) -> Int32) -> Int32 {
        // UNRESOLVED → re-encode drain (witness slot2 @0x101a1c990, 99 instr). Structure-only.
        return 0  // ⚑ UNRESOLVED stub value — real body is the 0x101a1c990(flush: 1, …) drain, not reconstructed
    }
    public func close() {
        // UNRESOLVED → re-encode teardown (witness slot3 @0x101a1cb1c, 45 instr: swr_free/fifo_free/etc). Structure-only.
    }
}

//  Forward 1.3.17 reconstruction — P2 remux cluster (re-encode trio, STRUCTURE-ONLY).
//  Forward type (binary-confirmed name). TranscodeProtocol conformer for the SUBTITLE re-encode path.
//  Built by the re-encode driver FUN_101a1d014 (P3-owner) — OFF the remux→segments (M3) path. Witness
//  bodies (decode→AVSubtitle→encode) DEFERRED (cardinal: structure faithful now, engine reconstructed in
//  the owner phase — also the P4 subtitles owner). Descriptor 0x1039ef094 / accessor 0x101a1f2a4;
//  vtable-empty (witness-table methods). 3 stored fields (reflection-authoritative, all concrete).
public final class SubtitleTranscodeContext: TranscodeProtocol {  // `final` not binary-pinned (M2 verifies)
    let decodeContext: UnsafeMutablePointer<AVCodecContext>      // field-record concrete
    let encodeContext: UnsafeMutablePointer<AVCodecContext>      // field-record concrete
    var subtitle:      AVSubtitle = AVSubtitle()                 // field-record concrete (the decoded AVSubtitle)

    // init: vtable-empty, devirt init (no readable body) → minimal inferred. ⚑ inferred.
    public init(decodeContext: UnsafeMutablePointer<AVCodecContext>,
                encodeContext: UnsafeMutablePointer<AVCodecContext>) {
        self.decodeContext = decodeContext
        self.encodeContext = encodeContext
    }

    // ── TranscodeProtocol conformance — re-encode WITNESS bodies STRUCTURE-ONLY (DEFERRED, not invented) ──
    public func transcode(_ input: UnsafeMutablePointer<AVPacket>,
                          output: UnsafeMutablePointer<AVPacket>,
                          completion: (UnsafeMutablePointer<AVPacket>) -> Int32) -> Int32 {
        // UNRESOLVED → subtitle re-encode (witness slot1 @0x101a1cc50, 82 instr: decode_subtitle→encode). Structure-only.
        return 0  // ⚑ UNRESOLVED stub value — req1 body not reconstructed
    }
    public func drain(_ output: UnsafeMutablePointer<AVPacket>,
                      completion: (UnsafeMutablePointer<AVPacket>) -> Int32) -> Int32 {
        // UNRESOLVED → re-encode drain (req2 — shared/trivial witness). Structure-only.
        return 0  // req2 = shared ICF fold 0x10002dab0 (`mov w0,#0; ret`)
    }
    public func close() {
        // UNRESOLVED → re-encode teardown (witness slot3 @0x101a1cdc8, 19 instr). Structure-only.
    }
}

//  Forward 1.3.17 reconstruction — P2 remux cluster (re-encode trio, STRUCTURE-ONLY).
//  Forward type (binary-confirmed name). TranscodeProtocol conformer for the VIDEO re-encode path.
//  Built by the re-encode driver FUN_101a1d014 (P3-owner) — OFF the remux→segments (M3) path. Witness
//  bodies (decode→encode re-encode) DEFERRED (cardinal: structure faithful now, engine reconstructed in
//  the owner phase). Descriptor 0x1039ef0d8 / accessor 0x101a1f2c4; vtable-empty (witness-table methods).
//  3 stored fields (reflection-authoritative, all field-record concrete).
public final class VideoTranscodeContext: TranscodeProtocol {  // `final` not binary-pinned (M2 verifies)
    let decodeContext: UnsafeMutablePointer<AVCodecContext>      // field-record concrete
    let encodeContext: UnsafeMutablePointer<AVCodecContext>      // field-record concrete
    var decodedFrame:  UnsafeMutablePointer<AVFrame>? = nil      // field-record concrete (optional)

    // init: vtable-empty, devirt init (no readable body) → minimal inferred. ⚑ inferred.
    public init(decodeContext: UnsafeMutablePointer<AVCodecContext>,
                encodeContext: UnsafeMutablePointer<AVCodecContext>) {
        self.decodeContext = decodeContext
        self.encodeContext = encodeContext
    }

    // ── TranscodeProtocol conformance — re-encode WITNESS bodies STRUCTURE-ONLY (DEFERRED, not invented) ──
    public func transcode(_ input: UnsafeMutablePointer<AVPacket>,
                          output: UnsafeMutablePointer<AVPacket>,
                          completion: (UnsafeMutablePointer<AVPacket>) -> Int32) -> Int32 {
        // UNRESOLVED → video re-encode (witness slot1 @0x101a1ce14, 59 instr: decode→encode). Structure-only.
        return 0  // ⚑ UNRESOLVED stub value — req1 body not reconstructed
    }
    public func drain(_ output: UnsafeMutablePointer<AVPacket>,
                      completion: (UnsafeMutablePointer<AVPacket>) -> Int32) -> Int32 {
        // UNRESOLVED → re-encode drain (req2 — shared/trivial witness, no distinct VTC slot). Structure-only.
        return 0  // req2 = shared ICF fold 0x10002dab0 (`mov w0,#0; ret`)
    }
    public func close() {
        // UNRESOLVED → re-encode teardown (witness slot3 @0x101a1cf30, 19 instr). Structure-only.
    }
}

public class OutputStreamInfo {       // NON-final (P21): parse_class_descriptor gives OSI a 16-slot method vtable (slots 0-15,
                                      // incl. slot13/14/15 dispatched by RemuxerIOAction via +0x118/+0x120/+0x128) — a `final class`
                                      // emits NO method vtable, so `final` was the structural bug (as LocalHLSServer/ProAVPlayer/ProPlayerItem).
                                      // ⚑ EXACT 16-slot layout = tracked structural debt (member-level finality/order — vtable_anchor_diff, not fabricated).
    // Types from the class's own __swift5_fieldmd field-records (authoritative). Reflection order.
    // Map KEYS are Int32 (faithfulness correction, 3 signals: subscript hashes 4 bytes; key = AVPacket
    // stream_index which is C `int`; field-record key = stdlib symref, libswiftCore-walled).
    public var assetTrackMap: [Int32: FFmpegAssetTrack] = [:]      // +0x10  key Int32 (stream_index) ⚑ value confirmed
    public private(set) var transcodeMap:  [Int32: any TranscodeProtocol] = [:] // +0x18  vtable: getter impl, setter/modify null
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
    private let outPacket:     UnsafeMutablePointer<AVPacket>?  // field flags 0 (`let`); both inits assign it once
    public let formatName:    String  // v4 concrete `SS`
    public let removeADTS:    Bool  // v4 concrete `Sb`

    // ── The REAL designated init (= FUN_101a1d014, the SOLE OSI construction site; ~1382-line devirt
    //    decompile: reconstruction/decompiles/OSI_factory_101a1d014.txt). Reconstructed C1-C4. ────────
    //  GROUNDED: the avformat_alloc_output_context2 prologue + KSPlayerError throw (C1); the
    //    avio_open / avformat_write_header epilogue + throws (C3); the 12-field assembly + return, incl.
    //    av_packet_alloc / formatName-from-oformat / removeADTS (C4). All FFmpeg calls oracle-CONFIRMED
    //    (reconstruction/osi_factory_ffmpeg_map.json).
    //  SPINE + honest-deferred (user-gated scope): the per-track loop reconstructs the COPY path + the
    //    maps (timeBaseMap/streamMapping) + frameRate + avformat_new_stream; the codec-specific TRANSCODE
    //    ARMS (AAC-ADTS-BSF / subtitle WEBVTT=0x17012·MOV_TEXT=0x17005 / HEVC=0xad extradata — constants
    //    compile-oracle-decoded) build a per-codec ctx via devirt ctor helpers (recover_swift_function_name
    //    = None) → reconstructed as named per-arm units (P36/P43). FFmpegAssetTrack field reads are
    //    offset-grounded, field-name-INFERRED (the shared +0x40 / 18-vs-37 layout debt, P34/§1).
    //  ⚑ signature (P28, devirt-inferred names): formatContext/filename/formatContextOptions/formatName
    //    GROUNDED; `forceTranscode` = p4 (tested `& 1`, write→false; CORRECTS the pinned "String?");
    //    `mediaType`:AVMediaType? = p8 — DERIVED, no longer inferred, and it CORRECTS the pinned
    //    `flag`:Int. The slot is nil-tested (`ldur x8,[x29-0x140]` / `cbz x8` @0x101a1d4b4) inside the
    //    per-track loop, then bridged and STRING-COMPARED against the loop element's +0x78 field:
    //    both sides go through `String._unconditionallyBridgeFromObjectiveC` and the results are
    //    compared pairwise (`cmp x0,x2` / `ccmp x20,x1,#0,eq` @0x101a1d4e4). An Int slot cannot be
    //    nil-tested nor bridged. The caller confirms the type: MEPlayerItem.startRecord's trie
    //    signature is `(url: Foundation.URL, mediaType: __C.AVMediaType?)` and it moves that very
    //    parameter into x7 (`mov x7,x21` @0x101a484d8) with x21 <- x1 at entry.
    //    ⚑[tool=bind_oracle ref=String._unconditionallyBridgeFromObjectiveC:0x10410a250 result=CONFIRMED]
    //    ⚑[tool=export_trie_oracle ref=MEPlayerItem.startRecord(url:mediaType:):0x101a483d4 result=AVMediaType-optional]
    //    `transcodeCodecIDs` = p9 (a codec-id list: count@+0x10, elems@+0x20).
    //  FFmpeg provenance — every symbol below is ffmpeg_name_oracle result=CONFIRMED (instr/size fp vs the
    //  symbolicated FFmpegKit static libs; reconstruction/osi_factory_ffmpeg_map.json):
    //   ⚑[tool=ffmpeg_name_oracle ref=avformat_alloc_output_context2:0x103193858 result=CONFIRMED]
    //   ⚑[tool=ffmpeg_name_oracle ref=avformat_new_stream:0x1031b8714 result=CONFIRMED]
    //   ⚑[tool=ffmpeg_name_oracle ref=avcodec_parameters_copy:0x1029f5584 result=CONFIRMED]
    //   ⚑[tool=ffmpeg_name_oracle ref=avcodec_parameters_from_context:0x1029f5738 result=CONFIRMED]
    //   ⚑[tool=ffmpeg_name_oracle ref=avformat_write_header:0x1031941d8 result=CONFIRMED]
    //   ⚑[tool=ffmpeg_name_oracle ref=av_dict_free:0x10323b034 result=CONFIRMED]
    //   ⚑[tool=ffmpeg_name_oracle ref=av_packet_alloc:0x102d61878 result=CONFIRMED]
    //   (avio_open @0x1030c0914 CONFIRMED too — not FFMPEG_RE-scanned)
    public init(formatContext: FormatContext,
                filename: String,
                forceTranscode: Bool = false,          // ⚑ p4 name INFERRED
                // ⚑ p5/p6-p7 OPTIONALITY DERIVED s102 — both are nil-tested by the binary, so neither
                // can be the non-optional type this init used to declare:
                //   p5  `cbz x24` @0x101a1d0f8 — an empty Dictionary is a non-null singleton, so a
                //       non-optional Dictionary can never be zero. The nil arm builds the substitute
                //       from `__swiftEmptyArrayStorage` (__got 0x104112d00) via 0x1019c3148, which is
                //       how an empty DICTIONARY LITERAL `[:]` is constructed, and both arms converge
                //       on one stack slot — i.e. the callee itself applies `?? [:]`.
                //   p6+p7 `cbz x25` @0x101a1d11c and `cbz x20` @0x101a1e154 — `""` is
                //       (0, 0xE000000000000000), never (0,0), so a non-optional String cannot be zero.
                // Slot identity is NOT in doubt — which is what rules out "the parameter ORDER is
                // wrong" as the competing explanation. The p5 value is converted by 0x101a322c0 and
                // passed as the AVDictionary** of  ⚑[tool=ffmpeg_name_oracle ref=avformat_write_header:0x1031941d8 result=CONFIRMED]
                // (`bl 0x1031941d8` @0x101a1e4a4), then released by  ⚑[tool=ffmpeg_name_oracle ref=av_dict_free:0x10323b034 result=CONFIRMED]
                // (@0x101a1e4b0). So p5 IS the format-context options and only its optionality was wrong.
                // ⚑[tool=bind_oracle ref=__swiftEmptyArrayStorage:0x104112d00 result=CONFIRMED]
                formatContextOptions: [String: Any]?,
                formatName: String?,
                // ⚑ p8 DERIVED (was `flag: Int`, inferred). MODULE-QUALIFIED: FFmpeg's C `AVMediaType`
                // enum collides with AVFoundation's here, the same collision MEPlayerItem.swift:271 names.
                mediaType: AVFoundation.AVMediaType? = nil,
                // ⚑ p9 OPTIONALITY DERIVED s102. The stack argument (`ldr x12,[x29,#0x10]`
                // @0x101a1d354) is NIL-TESTED at 0x101a1dcd4 — on the reloaded slot, not on x12 — then
                // its count is read at +0x10 and zero-tested (0x101a1dcd8-0x101a1dcdc), and only then
                // is the element base (x12+0x20, computed speculatively @0x101a1d3f0) walked. The
                // ELEMENT TYPE is corroborated, not merely inherited: the loop reads 32-bit elements
                // (`ldr w11,[x10],#0x4` @0x101a1dcf0) and compares each against `[x22,#0x4]`, i.e. a
                // linear search for a matching codec id. So the list type was right and only the
                // optionality was wrong; startRecord passes `str xzr,[sp]` @0x101a484b8, i.e. nil.
                transcodeCodecIDs: [AVCodecID]? = nil) throws {
        // ── C1: resolve muxer name → avformat_alloc_output_context2 → throw on failure ──────────────
        // ⚑ DEFERRED general-path (L196-381, dead for write() which passes "hls"): NIL formatName →
        //   derive the muxer name from filename.pathExtension via a runtime format-registry match; the
        //   loop internals are not deterministically recoverable (P36/P43 — no static-switch fit).
        //   CORRECTED s102: the guard is `formatName == nil`, not `formatName.isEmpty`. The binary
        //   tests the String's DISCRIMINATOR word (`cbz x25` @0x101a1d11c) and the nil arm runs the
        //   filename-derived path with x28/x2 (the filename String) @0x101a1d150-0x101a1d174; the
        //   non-nil arm instead converts formatName to a buffer pointer (result +0x20, the
        //   _StringObject.nativeBias) @0x101a1d13c and skips that path entirely.
        let resolvedFormatName = formatName
        var contextPointer: UnsafeMutablePointer<AVFormatContext>?
        // ⚑[tool=ffmpeg_name_oracle ref=0x103193858 result=CONFIRMED] avformat_alloc_output_context2 (79/316)
        let allocResult = avformat_alloc_output_context2(&contextPointer, nil, resolvedFormatName, filename)
        guard let outputContext = contextPointer else {          // L398 guards on ctx == nil
            // ⚑[tool=ffmpeg_name_oracle ref=avformat_alloc_output_context2:0x103193858 result=CONFIRMED]
            // ⚑[tool=ffmpeg_name_oracle ref=avformat_write_header:0x1031941d8 result=CONFIRMED]
            // ⚑ RESOLVED. The `_ = allocResult` discard and the enum-vs-Int question are both gone:
            //   `code` is `Int32`, and the binary's code operand here IS the live
            //   avformat_alloc_output_context2 return, i.e. `allocResult`. message is the 35-byte
            //   literal at 0x103d34ed0 = `formatOutputCreate`'s raw value.
            throw KSPlayerError(code: allocResult, description: KSPlayerErrorCode.formatOutputCreate.rawValue)
        }
        // ⚑ binary also sets an AVFormatContext numeric field (+0x80 = 0x200000 / 2 MiB tuning, L410) —
        //   which field UNRESOLVED → omitted (non-load-bearing for stream/map setup).

        // ── C2: per-track loop → output streams + maps (SPINE; transcode arms deferred) ─────────────
        var timeBaseMap:   [Int32: AVRational]            = [:]
        var streamMapping: [Int32: Int32]                 = [:]
        let transcodeMap:  [Int32: any TranscodeProtocol] = [:]   // ⚑ populated by the deferred transcode arms
        var accumulatedFrameRate = 0
        var outputStreamIndex: Int32 = 0
        let isHLS = (resolvedFormatName == "hls")                 // local_20c
        for track in formatContext.assetTracks {                  // formatContext+0x40
            let trackID = track.trackID                           // +0x10 (map key)
            timeBaseMap[trackID] = track.timebase.rational        // ⚑ +0xc0 field-inferred (layout debt); Timebase.rational
            accumulatedFrameRate += Int(track.nominalFrameRate)   // ⚑ +0x58 field-inferred; exact per-branch gating spine-approx
            streamMapping[trackID] = outputStreamIndex            // ⚑ value = output-stream counter (per-branch selection spine-approx)
            // ⚑[tool=ffmpeg_name_oracle ref=0x1031b8714 result=CONFIRMED] avformat_new_stream (105/420)
            guard let outputStream = avformat_new_stream(outputContext, nil) else { continue }
            // Codec dispatch — SPINE reconstructs the COPY arm (default; oracle-CONFIRMED). The transcode
            //   arms (gated on transcodeCodecIDs + track.mediaType + codec_id) build a per-codec transcode
            //   context via the devirt ctor helpers then avcodec_parameters_from_context [ref=0x1029f5738
            //   CONFIRMED] + transcodeMap[trackID]=ctx — DEFERRED to the OSI-transcode-arm unit (P36/P43).
            // ⚑[tool=ffmpeg_name_oracle ref=avcodec_parameters_copy:0x1029f5584 result=CONFIRMED] (copy 109/436)
            //   track.codecpar retyped value→pointer (+0xb8) — passed directly (was withUnsafePointer over the value)
            _ = avcodec_parameters_copy(outputStream.pointee.codecpar, track.codecpar)   // ⚑ FFmpegAssetTrack.codecpar (+0xb8)
            if outputStream.pointee.codecpar.pointee.sample_rate == 0 {     // L754
                outputStream.pointee.codecpar.pointee.sample_rate = 48000
            }
            outputStreamIndex += 1
        }

        // ── C3: avio_open → avformat_write_header → av_dict_free ─────────────────────────────────────
        // ⚑[tool=ffmpeg_name_oracle ref=0x1030c0914 result=CONFIRMED] avio_open (32/128)
        // ⚑ THE MESSAGE HERE WAS A SELF-DECLARED STRING AND IT IS NOT ONE — the 16 bytes the binary
        //   loads equal arm 2 of the rawValue table exactly, so it is `KSPlayerErrorCode.avioOpen`,
        //   a case the reconstruction did not have until this change. `code` is the live avio_open
        //   return, which now has to be bound to be thrown.
        let avioResult = avio_open(&outputContext.pointee.pb, filename, AVIO_FLAG_WRITE)
        guard avioResult >= 0 else {   // L1246/1249
            throw KSPlayerError(code: avioResult, description: KSPlayerErrorCode.avioOpen.rawValue)
        }
        // ⚑ DEFERRED — build `options` (AVDictionary) from formatContextOptions (FUN_101a322c0, L1262:
        //   [String:Any] → per-entry AVDictionary inserts, e.g. hls_segment_filename/hls_segment_type). Reconstruct
        //   as the options-dict unit; spine passes an empty dict (muxer defaults).
        var options: OpaquePointer?
        // ⚑[tool=ffmpeg_name_oracle ref=0x1031941d8 result=CONFIRMED] avformat_write_header (143/572)
        let headerResult = avformat_write_header(outputContext, &options)
        av_dict_free(&options)   // ⚑[tool=ffmpeg_name_oracle ref=0x10323b034 result=CONFIRMED] av_dict_free (27/108)
        guard headerResult >= 0 else {                          // L1266 / L1356
            // ⚑ code is the live avformat_write_header return, `headerResult`; message is the
            //   26-byte literal at 0x103d34eb0 = `formatWriteHeader`'s raw value.
            throw KSPlayerError(code: headerResult, description: KSPlayerErrorCode.formatWriteHeader.rawValue)
        }

        // ── C4: assemble the 12 stored fields + return (implicit) — L1311-1380 ───────────────────────
        //   removeADTS = isHLS && options["hls_segment_type"]=="fmp4"  (fMP4 segments need raw AAC; L1267-1310)
        // `?? [:]` is the callee's OWN substitution, read at 0x101a1d0f8-0x101a1d114 (see the init's
        // p5 note): both the nil and non-nil arms converge on one slot, so every later use sees a
        // dictionary whether or not the caller passed one.
        let segmentType = (formatContextOptions ?? [:])["hls_segment_type"] as? String
        self.formatCtx       = outputContext                                       // +0x58
        self.url             = filename                                            // +0x30/+0x38
        self.timeBaseMap     = timeBaseMap                                         // +0x20
        self.streamMapping   = streamMapping                                       // +0x40
        self.transcodeMap    = transcodeMap                                        // +0x18 (local_130)
        self.frameRate       = accumulatedFrameRate                                // +0x28 (local_178)
        self.assetTrackMap   = [:]                                                 // +0x10 (binary: empty singleton)
        self.lastDTSMap      = [:]                                                 // +0x48 (empty singleton)
        self.hasWriteTrailer = false                                              // +0x50
        // ⚑[tool=ffmpeg_name_oracle ref=0x102d61878 result=CONFIRMED] av_packet_alloc
        self.outPacket       = av_packet_alloc()                                   // +0x60 (L1325)
        self.formatName      = String(cString: outputContext.pointee.oformat.pointee.name)  // +0x68 (L1343; binary preconditions oformat/name non-nil)
        self.removeADTS      = isHLS && (segmentType == "fmp4")                    // +0x78 (bVar10)
        // ⚑ p8: READ as a per-track media-type FILTER — non-nil gates a bridged string compare of
        //   this argument against the loop element's +0x78 field (@0x101a1d4b4-0x101a1d4ec). What the
        //   equal / not-equal arms then DO is NOT read, so no filtering is expressed here.
        //   ⚑[tool=bind_oracle ref=String._unconditionallyBridgeFromObjectiveC:0x10410a250 result=CONFIRMED]
        _ = mediaType
        _ = forceTranscode    // ⚑ p4: gates frameRate accumulation + a streamMapping-value branch (write→false)
        _ = transcodeCodecIDs // ⚑ p9: the transcode codec allowlist — consumed by the deferred transcode arms
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
                  let bsfContext = makeADTSBitstreamFilter("aac_adtstoasc", stream.pointee.codecpar)
        {
            context = BSFTranscodeContext(bsfContext: bsfContext)
            transcodeMap[index] = context
        } else {
            context = CopyTranscodeContext()
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

    // ── slot 13 @0x101a1ab5c — per-stream: GET-OR-CREATE the transcode context, then RUN it ────────
    // 🚨 THE CLAIM "not in binary" IS FALSE, AND THE WHOLE SIGNATURE IS WRONG. The export trie names
    // 0x101a1ab5c outright:
    //   KSPlayer.OutputStreamInfo.transcode(packet: Swift.UnsafeMutablePointer<__C.AVPacket>,
    //                                       block: ((Swift.UnsafeMutablePointer<__C.AVPacket>) -> ())?)
    //     -> Swift.Int32
    // Four differences from the declaration below, not one:
    //   · base name    — `buildTranscodeContext` is INVENTED; it is `transcode`.
    //   · first label  — `packet:`, not unlabelled `_`.
    //   · second param — `block:`, not `completion:`, AND THE OPTIONALITY IS INVERTED: the binary has
    //                    an OPTIONAL closure taking a NON-optional pointer; the source has a
    //                    non-optional closure taking an OPTIONAL pointer.
    //   · return type  — `Int32`, not `Void`.
    // ⚠️ NOT CORRECTED HERE ON PURPOSE. Making `block` optional changes what is forwarded to
    // `TranscodeProtocol.transcode(_:output:completion:)`, and the `Int32` return needs a value on
    // each of the body's return paths — both require reading the 205-instruction body
    // (0x101a1ab5c-0x101a1ae90), which is its own unit. Applying half the signature would leave a
    // declaration that looks verified and is not. The FALSE "not in binary" claim is what is fixed.
    // ⚑[tool=export_trie_oracle ref=OutputStreamInfo.transcode:0x101a1ab5c result=transcode(packet:block:)-Int32]
    // Called by Remuxer.write
    // as s13(packet, completion). NOT just a builder: it ensures a per-stream Copy/BSF context exists
    // (dispatch AAC/ADTS → BSF, else Copy) AND invokes `ctx.transcode(packet, output: outPacket, completion:)`
    // — the terminal witness call (L161) is the function's PRIMARY effect [body-audit re-walk fix].
    // param_1 = AVPacket* (data@+0x18, size@+0x20, stream_index@+0x24 — header-verified).
    //
    // Decompile outer shape (FUN_101a1ab5c) — the outer branch keys on assetTrackMap[idx] (OSI+0x10),  ⚑[tool=resolve_fun_pins ref=FUN_101a1ab5c:0x101a1ab5c result=RESOLVES_UNIQUELY] = KSPlayer.OutputStreamInfo.transcode(packet: Swift.UnsafeMutablePointer<__C.AVPacket>, block: ((Swift.UnsafeMutablePointer<__C.AVPacket>) -> ())?) -> Swift.Int32
    // NOT transcodeMap [orchestrator re-walk fix]:
    //   if (assetTrackMap.count==0 || assetTrackMap[idx] miss)  → BUILD the context (this faithful path)
    //   else (assetTrackMap[idx] present)                       → FUN_101a1ae90 = steady-state per-packet  ⚑[tool=resolve_fun_pins ref=FUN_101a1ae90:0x101a1ae90 result=RESOLVES_UNIQUELY] = KSPlayer.FFmpegAssetTrack.transcode(packet: Swift.UnsafeMutablePointer<__C.AVPacket>) -> ()
    //                                                             copy/enqueue (UNRESOLVED, flagged below).
    // BUILD is further guarded by outPacket(+0x60) live + streamMapping[idx] + timeBaseMap[idx] + a live
    // output AVStream (formatCtx->streams[mapped]); then decide Copy vs BSF and store transcodeMap[idx].
    // (Which branch dominates at runtime is binary-UNVERIFIED — assetTrackMap's populator was not located.)
    // ⚑ NAME AND SIGNATURE ARE WRONG — see the trie signature recorded above this comment block.
    final func buildTranscodeContext(_ packet: UnsafeMutablePointer<AVPacket>,           // ⚑ INVENTED name; real name is `transcode`
                               completion: (UnsafeMutablePointer<AVPacket>?) -> Void) {  // forwarded to ctx.transcode (binary: callback FUN_101a660d0 + closure box, adapted by the compiler reabstraction thunk FUN_101a1f1a8 — not source-level)
        let idx = packet.pointee.stream_index                                     // *(uint*)(packet+0x24)

        // Outer branch keys on assetTrackMap[idx] (self+0x10) — track ABSENT → BUILD; PRESENT → steady-state.
        guard assetTrackMap[idx] == nil else {                                    // self+0x10 (FUN_1019c10ec)
            // ── STEADY-STATE per-packet path (assetTrackMap[idx] EXISTS) = FUN_101a1ae90 (64 instr) ──  ⚑[tool=resolve_fun_pins ref=FUN_101a1ae90:0x101a1ae90 result=RESOLVES_UNIQUELY] = KSPlayer.FFmpegAssetTrack.transcode(packet: Swift.UnsafeMutablePointer<__C.AVPacket>) -> ()
            // ⚑ UNRESOLVED → own follow-up unit: alloc queued-packet (FUN_101a65be4) + packet-copy  ⚑[tool=resolve_fun_pins ref=FUN_101a65be4:0x101a65be4 result=RESOLVES_UNIQUELY] = type metadata accessor for KSPlayer.Packet
            //   (FUN_102d622ec, sidecar-flagged UNRESOLVED) + enqueue @+0x100. The packet-copy core + the
            //   queue type are unresolved → NOT invented (cardinal). The body-audit + M3 packet-harness are
            //   the arbiters; the M3 test drives the BUILD path below to arbitrate the dispatch.
            //   Cached decompile: reconstruction/decompiles/OutputStreamInfo_s13else_101a1ae90.txt
            return  // UNRESOLVED — steady-state enqueue (FUN_101a1ae90), reconstruct as its own unit  ⚑[tool=resolve_fun_pins ref=FUN_101a1ae90:0x101a1ae90 result=RESOLVES_UNIQUELY] = KSPlayer.FFmpegAssetTrack.transcode(packet: Swift.UnsafeMutablePointer<__C.AVPacket>) -> ()
        }

        // ── BUILD path (assetTrackMap[idx] absent): set up the per-stream transcode context ──
        // Build-guards faithful to the nested binary conditions: a live outPacket, the input→output stream
        // mapping, a timebase entry, and a live output AVStream before constructing a context.
        guard outPacket != nil,                                                   // self+0x60 (binary's first build-guard)
              !streamMapping.isEmpty, let mapped = streamMapping[idx],            // self+0x40 (FUN_1019c10ec)
              !timeBaseMap.isEmpty, timeBaseMap[idx] != nil,                      // self+0x20 (timebase must exist)
              let outStream = formatCtx.pointee.streams[Int(mapped)]              // formatCtx->streams[mapped] (self+0x58 → +0x30 → *8)
        else { return }
        // Get-or-create the per-stream context (binary INNER branch @L94 on transcodeMap[idx]):
        //   present → reuse the existing context (FUN_1001263e0 COW, L146-150);
        //   absent  → build by the dispatch below (BSF stored; Copy is a transient static singleton).
        let ctx: any TranscodeProtocol
        if let existing = transcodeMap[idx] {                                     // self+0x18 present → reuse
            ctx = existing
        } else {
            let codecpar = outStream.pointee.codecpar                             // *(outStream+0x10) — AVCodecParameters*
            // DISPATCH (grounded + deterministic): AAC + ADTS-syncword + removeADTS → aac_adts BSF; else Copy.
            let useBSF = removeADTS                                               // self+0x78 == 1
                && codecpar?.pointee.codec_id == AV_CODEC_ID_AAC                  // codec_id == 0x15002 (header-verified)
                && packet.pointee.size > 2                                        // packet+0x20
                && packet.pointee.data[0] == 0xFF                                 // packet.data[0] == -1
                && (packet.pointee.data[1] & 0xF0) == 0xF0                        // (byte)data[1] > 0xEF
            // BSF only when useBSF AND the filter builds. On BSF-alloc FAILURE the binary FALLS THROUGH to
            // Copy (L115 `if (lVar13 != 0)` has no else/no return) → degrade to unfiltered Copy, do NOT drop
            // the packet [re-audit fix]. The `else` covers both non-AAC/non-ADTS and BSF-alloc-failed.
            // BOTH inputs are caller-supplied and the wrapper is built HERE, not inside the helper:
            //   x0/x1 = the filter NAME (13-char small string, decoded below), x20 = codecpar (loaded from
            //   outStream.pointee.codecpar immediately before the call, then cbz-checked — which is the
            //   `let codecpar` binding above). The BSFTranscodeContext is a 24-byte swift_allocObject at the
            //   CALL SITE whose single field receives the helper's raw return.
            if useBSF, let codecpar, let bsfContext = makeADTSBitstreamFilter("aac_adtstoasc", codecpar) {
                let bsf = BSFTranscodeContext(bsfContext: bsfContext)             // built at the call site, not in the helper
                transcodeMap[idx] = bsf                                           // STORE per-stream BSF (FUN_1019b3c2c, L131)
                ctx = bsf
            } else {
                // Copy: binary uses a static singleton (initStaticObject, L138) and does NOT store it in
                // transcodeMap. ⚑ modeled as a fresh stateless instance (CopyTranscodeContext = 0 fields →
                // observationally equivalent); a `static let shared` would be byte-faithful (refinement).
                ctx = CopyTranscodeContext()                                      // FUN_101a1f188
            }
        }

        // PRIMARY EFFECT (binary terminal witness call @L161 `(*ctx.witness[1])(packet, outPacket, …)`):
        // run the context on the packet, FORWARDING the completion (the compiler reabstraction thunk
        // FUN_101a1f1a8 is not source-level → the completion is passed through, not constructed here).
        // ⚑ ADAPTER ONLY (TranscodeProtocol.transcode now `-> Int32` with an Int32 completion): this function's own
        //   signature/closure (trie: transcode(packet:block:) -> Int32; closure 0x101a1af90 returns the write
        //   result) is its own unit — the `return 0` below is NOT binary-read.
        _ = ctx.transcode(packet, output: outPacket!, completion: { completion($0); return 0 })
    }

    // BSF allocation (FUN_101a08744, 0x101a08744..0x101a08a94, 212 instr). export_trie_oracle = NOT IN TRIE,
    // so the base name AND the labels stay inferred (⚑ P28) — but the ARITY, the value types and the return
    // type are now BINARY-READ, not inferred.
    // ⚑ SIGNATURE CORRECTION. The retired pin claimed "makeADTS true binary sig is 4-param, not no-arg".
    //   That is wrong in both directions: the body reads exactly THREE live-in registers = TWO values.
    //     x0/x1 = a Swift String — String.utf8CString.getter feeds av_bsf_get_by_name, and the SAME x0/x1
    //             are re-appended into the not-found message, which only makes sense for a String parameter.
    //     x20   = UnsafeMutablePointer<AVCodecParameters>, live-in and never written on the success path,
    //             consumed as the `src` of avcodec_parameters_copy. x20 is NOT self: the sole caller keeps
    //             its own self in x21 and deliberately loads codecpar into x20 four instructions earlier.
    // ⚑ THE HARD-CODED FILTER NAME WAS WRONG AND UNRUNNABLE. Source said "aac_adts", which is not an FFmpeg
    //   bitstream filter at all, so this body could only ever return nil. The name is a PARAMETER, and the
    //   caller passes a 13-char small string: x0 = 0x737464615f636161 -> "aac_adts", x1 = 0xed00006373616f74
    //   -> "toasc" with discriminator 0xED = 0xE0|13 -> count 13 => "aac_adtstoasc", which is the real filter
    //   (libavcodec/bsf/aac_adtstoasc.c). The old comment's constant 0x737364615f636161 decodes to "aac_adss"
    //   — a mistyped read of only the first of the two registers.
    // ⚑ RETURN is the raw pointer; there is NO swift_allocObject on the success path. The 24-byte
    //   BSFTranscodeContext is built by the CALLER (see the call site above).
    // ⚑ the declaration form that lands the pointer in x20 rather than x2 (an UnsafeMutablePointer extension's
    //   `self` vs a nested function's capture) is NOT binary-recoverable — modelled as an ordinary second
    //   parameter; the register assignment is the only unmatched detail.
    //   ⚑[tool=ffmpeg_name_oracle ref=av_bsf_get_by_name:0x102957ca0 result=UNKNOWN] — this was recorded
    //     "(oracle-CONFIRMED)"; --resolve now returns UNKNOWN, so the name is retained on call-shape grounds
    //     only. Stale provenance, corrected rather than carried forward.
    //   ⚑[tool=ffmpeg_name_oracle ref=av_bsf_alloc:0x10295b0d4 result=CONFIRMED]
    //   ⚑[tool=ffmpeg_name_oracle ref=avcodec_parameters_copy:0x1029f5584 result=CONFIRMED]
    //   ⚑[tool=ffmpeg_name_oracle ref=av_bsf_init:0x10295b198 result=CONFIRMED]
    //   ⚑[tool=ffmpeg_name_oracle ref=av_bsf_free:0x10295b040 result=CONFIRMED]
    private final func makeADTSBitstreamFilter(_ name: String,                          // ⚑ label inferred (P28)
                                         _ codecpar: UnsafeMutablePointer<AVCodecParameters>) // ⚑ label inferred (P28)
        -> UnsafeMutablePointer<AVBSFContext>?
    {
        guard let filter = av_bsf_get_by_name(name) else {                        // name is the PARAMETER, not a literal
            print("bsf \(name) not found")                                        // "bsf " (count 4) + name + " not found" (count 10)
            return nil
        }
        var ctx: UnsafeMutablePointer<AVBSFContext>?
        let allocResult = av_bsf_alloc(filter, &ctx)
        guard allocResult >= 0 else {
            // NO av_bsf_free here — the binary does not free on the alloc-failure path (ctx is still nil).
            print("Failed to allocate bitstream filter context: \(allocResult)")  // literal count 45, Int32 interpolation
            return nil
        }
        // The long-deferred "UNRESOLVED par-setup" is now READ: src is the `codecpar` parameter, and this
        // branch has its own failure arm + message that the previous reconstruction lacked entirely.
        let copyResult = avcodec_parameters_copy(ctx?.pointee.par_in, codecpar)   // par_in read by NAME from bsf.h
        guard copyResult >= 0 else {
            av_bsf_free(&ctx)
            print("Failed to copy codec parameters: \(copyResult)")               // literal count 33
            return nil
        }
        let initResult = av_bsf_init(ctx)
        guard initResult >= 0 else {
            av_bsf_free(&ctx)
            print("Failed to initialize bitstream filter: \(initResult)")         // literal count 39
            return nil
        }
        return ctx                                                                // raw pointer; wrapper built by the caller
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
        lastDTSMap = [:]                                    // self+0x48 cleared [0x101a1ba0c]
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
        for (_, track) in assetTrackMap {                   // self+0x10
            // Inlined FFmpegAssetTrack.stop(): track+0x100 (`subtitle`) → vtable +0x1c0 (shutdown()).
            track.stop()
        }
        var outPacket = outPacket                           // Forward stop() @0x101a1bb5c frees a stack copy, no writeback
        av_packet_free(&outPacket)                          // FUN_102d618b8 — ffmpeg_name_oracle CONFIRMED (46/184 exact) [0x101a1be1c]
        // FUN_101a39028 = static FFmpegUtility.close(formatCtx:) (#function "close(formatCtx:)", trie
        // $s8KSPlayer13FFmpegUtilityO5close9formatCtxySpySo15AVFormatContextVGSg_tFZ).
        FFmpegUtility.close(formatCtx: formatCtx)
    }

    // ── Phase-1 test scaffold (⚑ NOT binary-present) — retained so Phase2RemuxTest can exercise slots
    //    (L7 pilot c: declared LAST so its build-only vtable slot 16 follows Forward's F14 writeTrailer /
    //    F15 stop instead of displacing them; Forward has no such slot — ledgered as a test scaffold.)
    //    13/14/15 in isolation without the full factory. The binary's SOLE construction is the designated
    //    init above (FUN_101a1d014). Not used in any reconstructed path. ──────────────────────────────
    //    ⚑ It must assign EVERY `let` field, which is why it takes the three the test varies
    //    as parameters instead of letting the test mutate them afterwards. Six of this
    //    class's fields have FieldRecord flags 0x00000000 (= `let`) in the binary; a
    //    designated init that left any of them to a default would not compile, which is
    //    itself independent confirmation that no such second init exists in the original —
    //    this one is ours. The literals below are scaffold values, NOT binary-grounded.
    init(formatCtx: UnsafeMutablePointer<AVFormatContext>,   // ⚑ test scaffold, not in binary
         outPacket: UnsafeMutablePointer<AVPacket>,
         streamMapping: [Int32: Int32] = [:],
         timeBaseMap: [Int32: AVRational] = [:],
         removeADTS: Bool = false) {
        self.formatCtx = formatCtx
        self.streamMapping = streamMapping
        self.timeBaseMap = timeBaseMap
        self.removeADTS = removeADTS
        self.url = ""            // ⚑ scaffold-only value
        self.frameRate = 0       // ⚑ scaffold-only value
        self.formatName = ""     // ⚑ scaffold-only value
        self.outPacket = outPacket
    }
}
