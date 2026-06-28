//
//  BSFTranscodeContext.swift
//  KSPlayer
//
//  Forward 1.3.17 reconstruction — P2 remux cluster (Wave 1).
//  TranscodeProtocol conformer. Binary: 1 stored field `bsfContext` (+0x10), root class. The
//  bitstream-filter path: send the input packet through the BSF, receive the filtered packet into
//  the caller's output buffer, stamp AV_NOPTS, fire completion; teardown frees the BSF.
//  Bodies GROUNDED from BSFTC_req1 @0x101a1bf28 and BSFTC_req3 @0x101a1bfe4.
//  av_bsf_* are oracle-CONFIRMED names → used directly. The packet-unref helper (FUN_102d61970) is
//  name-UNRESOLVED → spine only.
//
import FFmpegKit
import Libavcodec

public final class BSFTranscodeContext: TranscodeProtocol {  // `final` not binary-pinned (no library evolution)
    // Field +0x10 (binary __swift5_fieldmd). FFmpeg C type. Accessed under _swift_beginAccess in req1/req3.
    public var bsfContext: UnsafeMutablePointer<AVBSFContext>?

    // init devirtualized (no readable body). Minimal inferred init — the bsfContext is supplied by the
    // Remuxer once the filter is allocated/initialised; exact init signature unrecoverable → inferred.
    public init(bsfContext: UnsafeMutablePointer<AVBSFContext>? = nil) {  // inferred — devirt init, no body
        self.bsfContext = bsfContext
    }

    // req1 / witness slot 1 — BSF packet op. GROUNDED (BSFTC_req1 @0x101a1bf28):
    //   av_bsf_send_packet(bsfContext, input);
    //   if (0 <= ret) { av_bsf_receive_packet(bsfContext, output);
    //                   if (recv < 0) FUN_102d61970(output);          // cleanup/unref
    //                   else { output[9] = -1; (*param_3)(output); } } // pts=AV_NOPTS, completion
    public func transcode(_ input: UnsafeMutablePointer<AVPacket>?,
                          output: UnsafeMutablePointer<AVPacket>?,
                          completion: (UnsafeMutablePointer<AVPacket>?) -> Void) {
        let sendResult = av_bsf_send_packet(bsfContext, input)  // oracle-CONFIRMED name
        if sendResult >= 0 {                                    // `if (-1 < (int)...)` = ret >= 0
            // av_bsf_receive_packet(ctx, pkt) — C arity is 2 (ctx, output buffer); the decompile's
            // 1-arg render is a decompiler artifact, the receive target is the output packet (param_2).
            let receiveResult = av_bsf_receive_packet(bsfContext, output)  // oracle-CONFIRMED name
            if receiveResult < 0 {
                // FUN_102d61970(output) — packet-unref/cleanup helper, name UNRESOLVED (oracle could
                // not name it) → reconstruct the SPINE only; do NOT invent an av_packet_* name.
                unrefPacket(output)  // UNRESOLVED name (FUN_102d61970) — packet-unref/cleanup helper
            } else {
                output?.pointee.pos = -1  // `param_2[9] = -1` → output.pos = -1 (+0x48 = AVPacket.pos,
                                          // "byte position unknown"). NOT pts (+0x08); AV_NOPTS=INT64_MIN,
                                          // not -1 (deterministic: packet.h offsets).
                completion(output)        // `(*param_3)(param_2)` = completion(output)
            }
        }
    }

    // req2 / witness slot 2 — re-encode (ATC) drain. BSF satisfies the shared/trivial witness.
    // UNRESOLVED → re-encode (ATC) phase. ⚑ trivial body inferred (no distinct BSF witness).
    public func drain(_ completion: (UnsafeMutablePointer<AVPacket>?) -> Void) {}

    // req3 / witness slot 3 — teardown. GROUNDED (BSFTC_req3 @0x101a1bfe4):
    //   av_bsf_free(&self.bsfContext)   (the _swift_beginAccess/_swift_endAccess pair = inout access)
    public func close() {
        av_bsf_free(&bsfContext)  // oracle-CONFIRMED name; takes AVBSFContext** → &self.bsfContext
    }

    // FUN_102d61970 — packet-unref/cleanup helper, name UNRESOLVED (av_packet_unref / av_packet_free?
    // — NOT invented). Spine placeholder so the GROUNDED control flow is preserved; resolve the callee
    // + exact semantics in a follow-up.  // UNRESOLVED callee name @0x102d61970
    private func unrefPacket(_ packet: UnsafeMutablePointer<AVPacket>?) {
        // UNRESOLVED — devirtualized helper FUN_102d61970(packet); follow-callees later.
    }
}
