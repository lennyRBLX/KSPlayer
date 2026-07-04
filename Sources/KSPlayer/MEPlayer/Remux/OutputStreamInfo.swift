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
import FFmpegKit
import Libavcodec
import Libavformat

public class OutputStreamInfo {       // NON-final (P21): parse_class_descriptor gives OSI a 16-slot method vtable (slots 0-15,
                                      // incl. slot13/14/15 dispatched by RemuxerIOAction via +0x118/+0x120/+0x128) — a `final class`
                                      // emits NO method vtable, so `final` was the structural bug (as LocalHLSServer/ProAVPlayer/ProPlayerItem).
                                      // ⚑ EXACT 16-slot layout = tracked structural debt (member-level finality/order — vtable_anchor_diff, not fabricated).
    // Types from the class's own __swift5_fieldmd field-records (authoritative). Reflection order.
    // Map KEYS are Int32 (faithfulness correction, 3 signals: subscript hashes 4 bytes; key = AVPacket
    // stream_index which is C `int`; field-record key = stdlib symref, libswiftCore-walled).
    public var assetTrackMap: [Int32: FFmpegAssetTrack] = [:]      // +0x10  key Int32 (stream_index) ⚑ value confirmed
    public var transcodeMap:  [Int32: any TranscodeProtocol] = [:] // +0x18
    public var timeBaseMap:   [Int32: AVRational] = [:]            // +0x20
    public var frameRate:     Int = 0                            // v4 concrete `Si`
    public var url:           String = ""                        // v4 concrete `SS`
    public var streamMapping: [Int32: Int32] = [:]                 // +0x40  ⚑ value width inferred (verify)
    public var lastDTSMap:    [Int32: Int64] = [:]                 // +0x48  key Int32; value Int64 (DTS)
    public var hasWriteTrailer: Bool = false                     // v4 concrete `Sb`
    public let formatCtx:     UnsafeMutablePointer<AVFormatContext>  // v4 concrete (non-optional → init param)
    public var outPacket:     UnsafeMutablePointer<AVPacket>? = nil  // v4 concrete (optional)
    public var formatName:    String = ""                        // v4 concrete `SS`
    public var removeADTS:    Bool = false                       // v4 concrete `Sb`

    // init: binary slot 12 is DEVIRTUALIZED (no body) → signature UNRESOLVED. Minimal inferred init:
    // formatCtx is non-optional (must be supplied); all other fields default. Real init signature
    // (params/order) is unrecoverable from the binary → P2 refines.
    // builder sets assetTrackMap/lastDTSMap=[:], others from params; signature devirt-unrecoverable → minimal init retained (P3 may refine).
    public init(formatCtx: UnsafeMutablePointer<AVFormatContext>) {  // inferred — devirt slot 12, no body
        self.formatCtx = formatCtx
    }

    // ── slot 13 @0x101a1ab5c — per-stream: GET-OR-CREATE the transcode context, then RUN it ────────
    // ⚑ method name `buildTranscodeContext` INFERRED (devirt; not in binary). Called by Remuxer.write
    // as s13(packet, completion). NOT just a builder: it ensures a per-stream Copy/BSF context exists
    // (dispatch AAC/ADTS → BSF, else Copy) AND invokes `ctx.transcode(packet, output: outPacket, completion:)`
    // — the terminal witness call (L161) is the function's PRIMARY effect [body-audit re-walk fix].
    // param_1 = AVPacket* (data@+0x18, size@+0x20, stream_index@+0x24 — header-verified).
    //
    // Decompile outer shape (FUN_101a1ab5c) — the outer branch keys on assetTrackMap[idx] (OSI+0x10),
    // NOT transcodeMap [orchestrator re-walk fix]:
    //   if (assetTrackMap.count==0 || assetTrackMap[idx] miss)  → BUILD the context (this faithful path)
    //   else (assetTrackMap[idx] present)                       → FUN_101a1ae90 = steady-state per-packet
    //                                                             copy/enqueue (UNRESOLVED, flagged below).
    // BUILD is further guarded by outPacket(+0x60) live + streamMapping[idx] + timeBaseMap[idx] + a live
    // output AVStream (formatCtx->streams[mapped]); then decide Copy vs BSF and store transcodeMap[idx].
    // (Which branch dominates at runtime is binary-UNVERIFIED — assetTrackMap's populator was not located.)
    func buildTranscodeContext(_ packet: UnsafeMutablePointer<AVPacket>,           // ⚑ name inferred (devirt slot13)
                               completion: (UnsafeMutablePointer<AVPacket>?) -> Void) {  // forwarded to ctx.transcode (binary: callback FUN_101a660d0 + closure box, adapted by the compiler reabstraction thunk FUN_101a1f1a8 — not source-level)
        let idx = packet.pointee.stream_index                                     // *(uint*)(packet+0x24)

        // Outer branch keys on assetTrackMap[idx] (self+0x10) — track ABSENT → BUILD; PRESENT → steady-state.
        guard assetTrackMap[idx] == nil else {                                    // self+0x10 (FUN_1019c10ec)
            // ── STEADY-STATE per-packet path (assetTrackMap[idx] EXISTS) = FUN_101a1ae90 (64 instr) ──
            // ⚑ UNRESOLVED → own follow-up unit: alloc queued-packet (FUN_101a65be4) + packet-copy
            //   (FUN_102d622ec, sidecar-flagged UNRESOLVED) + enqueue @+0x100. The packet-copy core + the
            //   queue type are unresolved → NOT invented (cardinal). The body-audit + M3 packet-harness are
            //   the arbiters; the M3 test drives the BUILD path below to arbitrate the dispatch.
            //   Cached decompile: reconstruction/decompiles/OutputStreamInfo_s13else_101a1ae90.txt
            return  // UNRESOLVED — steady-state enqueue (FUN_101a1ae90), reconstruct as its own unit
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
            if useBSF, let bsf = makeADTSBitstreamFilter() {                      // FUN_101a08744 (BSF accessor FUN_101a1f1bc)
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
        ctx.transcode(packet, output: outPacket, completion: completion)
    }

    // aac_adts BSF allocation (FUN_101a08744 — the 0x737364615f636161 = "aac_adts" branch). A Forward
    // helper that creates the bitstream filter. av_bsf_* names are ORACLE-CONFIRMED → used directly.
    // Confirmed sequence: av_bsf_get_by_name("aac_adts") → av_bsf_alloc(filter,&ctx) → <UNRESOLVED
    // par-setup> → av_bsf_init(ctx) → BSFTranscodeContext(bsfContext: ctx); on non-zero return,
    // av_bsf_free(&ctx) + the error is logged. ⚑ name `makeADTSBitstreamFilter` INFERRED.
    private func makeADTSBitstreamFilter() -> BSFTranscodeContext? {
        guard let filter = av_bsf_get_by_name("aac_adts") else {                  // FUN_102957ca0 (oracle-CONFIRMED)
            print("bsf aac_adts not found")  // [audit fix] binary logs on the filter-null path (was silent). ⚑ message text audit-decoded ("bsf <name> not found")
            return nil
        }
        var ctx: UnsafeMutablePointer<AVBSFContext>?
        guard av_bsf_alloc(filter, &ctx) >= 0 else {                              // FUN_10295b0d4 (oracle-CONFIRMED)
            // [audit fix] NO av_bsf_free here — the binary does NOT free on the alloc-failure path (alloc-fail
            //   leaves ctx nil; only the par-setup-fail and init-fail branches call av_bsf_free).
            print("av_bsf_alloc failed for aac_adts")                            // Swift._print (⚑ message text approximate)
            return nil
        }
        // UNRESOLVED → P3 (remux driver): FUN_1029f5584 = avcodec_parameters_copy (oracle CONFIRMED, exact
        //   cross-binary size 436==436). The call is avcodec_parameters_copy(ctx.pointee.par_in, <src codecpar>);
        //   src = caller-supplied (makeADTS true binary sig is 4-param, not no-arg — src is threaded from the
        //   OSI slot13/14/15 op FUN_101a1ab5c, itself deferred). Reconstruct with the OSI remux ops in P3 — do
        //   NOT fabricate the src here. Spine preserved by omission. See reports/task-P2-task4-deferred-io-bodies.md §1.
        guard av_bsf_init(ctx) >= 0 else {                                        // FUN_10295b198 (oracle-CONFIRMED)
            av_bsf_free(&ctx)                                                     // FUN_10295b040 (oracle-CONFIRMED) — error path
            print("av_bsf_init failed for aac_adts")                             // Swift._print on the error path
            return nil
        }
        return BSFTranscodeContext(bsfContext: ctx)                              // Wave-1 type (1 field)
    }

    // ── slot14 @0x101a1b8d4 (162 instr) — drain-all + write the container trailer, run-once. Void (P44:
    //    plain-ret epilogue). ⚑ method NAME `finishWriting()` INFERRED (devirt; recover_swift_function_name
    //    = None). Called by RemuxerIOAction.cancel (OSI vtable +0x120). The FFmpeg call is
    //    ffmpeg_name_oracle-CONFIRMED (not eyeballed). Cache: decompiles/OutputStreamInfo#14.txt.
    func finishWriting() {
        guard !hasWriteTrailer else { return }              // self+0x50 (& 1) — run-once guard [0x101a1b904]
        hasWriteTrailer = true                              // self+0x50 = 1
        for (_, ctx) in transcodeMap {                      // self+0x18 iteration (Swift Dictionary bucket-walk)
            // ⚑ the drain is GATED per-entry on stream-mapping state (outPacket present + assetTrackMap[idx] +
            //   streamMapping[idx], @0x101a1b9f8-a2c) — the exact gate + the completion body (FUN_101a1f1dc,
            //   per-packet write-out) are DEFERRED to P3 (behaviorally testable with the remux driver). The
            //   drain CALL (witness +0x10) is faithful; its guard is modeled as unconditional here — ⚑ flagged.
            ctx.drain { _ in
                // ⚑ UNRESOLVED — completion body FUN_101a1f1dc; reconstruct with the P3 remux driver.
            }
        }
        av_write_trailer(formatCtx)                         // FUN_103194e1c — ffmpeg_name_oracle CONFIRMED (117/468 exact) [0x101a1b9f0]
        lastDTSMap = [:]                                    // self+0x48 cleared [0x101a1ba0c]
    }

    // ── slot15 @0x101a1bb5c (181 instr) — close-all: close every transcode ctx + asset track, free the
    //    out-packet and the format context. Void (P44). ⚑ method NAME `close()` INFERRED (devirt). Called by
    //    RemuxerIOAction.cancel (+0x128) + reconstruct. Cache: decompiles/OutputStreamInfo#15.txt.
    func close() {
        for (_, ctx) in transcodeMap {                      // self+0x18
            ctx.close()                                     // TranscodeProtocol.close (witness +0x18) [0x101a1bce8]
        }
        for (_, track) in assetTrackMap {                   // self+0x10 (stride 0x200)
            // ⚑ UNRESOLVED — per-track teardown: the track value's `obj@+0x100 . vtable+0x1c0()`
            //   (FFmpegAssetTrack-internal codec/context close) — DEFERRED to P3 (FFmpegAssetTrack layout).
            _ = track
        }
        av_packet_free(&outPacket)                          // FUN_102d618b8 — ffmpeg_name_oracle CONFIRMED (46/184 exact) [0x101a1be1c]
        // ⚑ formatCtx cleanup — FUN_101a39028: a KSPlayer Swift wrapper (0x101a3 range, NOT FFmpeg —
        //   ffmpeg_name_oracle REFUTED avformat_free_context: fwd 101/404 ≠ lib 131/524) around FFmpeg
        //   FUN_1030e632c = av_formatCloseInput (ffmpeg_name_oracle CONFIRMED avformat_close_input, 38/152 exact).
        //   The Swift wrapper's own NAME is devirt-unrecoverable (recover = None) → NOT emitted as a fabricated
        //   call; DEFERRED to P3 (the wrapper likely does `avformat_close_input(&formatCtx)`). [0x101a1be28]
    }
}
