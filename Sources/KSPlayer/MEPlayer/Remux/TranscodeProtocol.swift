//
//  TranscodeProtocol.swift
//  KSPlayer
//
//  Forward 1.3.17 reconstruction — P2 remux cluster (Wave 1).
//  Forward type (binary-confirmed name). Protocol descriptor @0x1039eefa0 declares exactly
//  3 instance methods, no defaults (binary fact — __swift5_proto). The witness slots are
//  GROUNDED from the Copy/BSF witness bodies (CopyTC_req1 @0x101a1bee0, BSFTC_req1 @0x101a1bf28,
//  BSFTC_req3 @0x101a1bfe4); the protocol method *names* are not in the binary → inferred + FLAGGED.
//  Conformers: CopyTranscodeContext, BSFTranscodeContext (this wave) + Audio/Video/Subtitle (later).
//
import FFmpegKit
import Libavcodec

public protocol TranscodeProtocol {
    // ── req1 / witness slot 1 — the per-stream packet op (GROUNDED) ──────────────────────────────
    // Body shape (from Copy/BSF witnesses): take an INPUT packet + an OUTPUT packet (caller buffer)
    // + a COMPLETION closure that receives the output; on success set output.pts = -1 (AV_NOPTS) then
    // call completion(output)  (decompile: `param_2[9] = -1` then `(*param_3)(param_2)`).
    // I/O type GROUNDED: `UnsafeMutablePointer<AVPacket>?` (= OutputStreamInfo.outPacket; av_bsf_send_packet
    // takes `AVPacket*`). ⚑ method name `transcode` INFERRED (not in binary). ⚑ closure convention
    // (escaping/label) inferred from the call `(*param_3)(param_2)` = completion(output).
    func transcode(_ input: UnsafeMutablePointer<AVPacket>?,
                   output: UnsafeMutablePointer<AVPacket>?,
                   completion: (UnsafeMutablePointer<AVPacket>?) -> Void)

    // ── req2 / witness slot 2 — ATC-distinctive (re-encode drain) ────────────────────────────────
    // DEFERRED: the re-encode (ATC) path, off the remux test. Binary requires 3 methods, so it is
    // declared; Copy/BSF satisfy it with a SHARED/trivial witness (implemented trivially below).
    // ⚑ name + signature INFERRED placeholder. // UNRESOLVED → re-encode (ATC) phase
    func drain(_ completion: (UnsafeMutablePointer<AVPacket>?) -> Void)

    // ── req3 / witness slot 3 — teardown/close (GROUNDED from BSFTC_req3) ────────────────────────
    // BSF witness body = `av_bsf_free(&self.bsfContext)`. Copy's witness is trivial (shared/no-op).
    // ⚑ method name `close` INFERRED (not in binary).
    func close()
}
