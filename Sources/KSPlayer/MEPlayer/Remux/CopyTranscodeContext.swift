//
//  CopyTranscodeContext.swift
//  KSPlayer
//
//  Forward 1.3.17 reconstruction — P2 remux cluster (Wave 1).
//  TranscodeProtocol conformer. Binary: 0 stored fields, root class. The stream-copy (no-transcode)
//  path: copy the input packet into the caller's output buffer, stamp AV_NOPTS, fire completion.
//  Body GROUNDED from CopyTC_req1 @0x101a1bee0. req2/req3 = trivial shared witness.
//
import FFmpegKit
import Libavcodec

public final class CopyTranscodeContext: TranscodeProtocol {  // `final` not binary-pinned (no library evolution); 0 fields → no stored state
    public init() {}  // root class, 0 fields — devirt init has no readable body; minimal inferred init

    // req1 / witness slot 1 — stream-copy packet op. GROUNDED (CopyTC_req1 @0x101a1bee0):
    //   FUN_102d622ec(output, input);  param_2[9] = -1;  (*param_3)(param_2);
    public func transcode(_ input: UnsafeMutablePointer<AVPacket>?,
                          output: UnsafeMutablePointer<AVPacket>?,
                          completion: (UnsafeMutablePointer<AVPacket>?) -> Void) {
        // Copy input → output (caller buffer). FUN_102d622ec = packet-copy helper, name UNRESOLVED
        // (oracle could not name it) → reconstruct the SPINE only; do NOT invent an av_packet_* name.
        copyPacket(into: output, from: input)  // UNRESOLVED name (FUN_102d622ec) — packet-copy helper
        output?.pointee.pos = -1               // `param_2[9] = -1` → output.pos = -1 (+0x48 = AVPacket.pos,
                                               // "byte position unknown"). NOT pts: pts is +0x08, and
                                               // AV_NOPTS_VALUE is INT64_MIN, not -1 (deterministic: packet.h).
        completion(output)                     // `(*param_3)(param_2)` = completion(output)
    }

    // req2 / witness slot 2 — re-encode (ATC) drain. Copy satisfies the shared/trivial witness.
    // UNRESOLVED → re-encode (ATC) phase. ⚑ trivial body inferred (no distinct Copy witness).
    public func drain(_ completion: (UnsafeMutablePointer<AVPacket>?) -> Void) {}

    // req3 / witness slot 3 — teardown. Copy's witness is trivial/shared (no bsfContext to free).
    public func close() {}

    // FUN_102d622ec — packet-copy helper, name UNRESOLVED (av_packet_ref / av_packet_copy / custom?
    // — NOT invented). Spine placeholder so the GROUNDED call sequence is preserved; resolve the
    // callee + exact semantics in a follow-up.  // UNRESOLVED callee name @0x102d622ec
    private func copyPacket(into output: UnsafeMutablePointer<AVPacket>?,
                            from input: UnsafeMutablePointer<AVPacket>?) {
        // UNRESOLVED — devirtualized helper FUN_102d622ec(output, input); follow-callees later.
    }
}
