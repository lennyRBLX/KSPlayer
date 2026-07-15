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
    //    `flag`:Int = p8 (write→0); `transcodeCodecIDs` = p9 (a codec-id list: count@+0x10, elems@+0x20).
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
                formatContextOptions: [String: Any],
                formatName: String,
                flag: Int = 0,                         // ⚑ p8 name INFERRED
                transcodeCodecIDs: [AVCodecID] = []) throws {   // ⚑ p9 name/type INFERRED
        // ── C1: resolve muxer name → avformat_alloc_output_context2 → throw on failure ──────────────
        // ⚑ DEFERRED general-path (L196-381, dead for write() which passes "hls"): empty formatName →
        //   derive the muxer name from filename.pathExtension via a runtime format-registry match; the
        //   loop internals are not deterministically recoverable (P36/P43 — no static-switch fit).
        let resolvedFormatName = formatName
        var contextPointer: UnsafeMutablePointer<AVFormatContext>?
        // ⚑[tool=ffmpeg_name_oracle ref=0x103193858 result=CONFIRMED] avformat_alloc_output_context2 (79/316)
        let allocResult = avformat_alloc_output_context2(&contextPointer, nil, resolvedFormatName, filename)
        guard let outputContext = contextPointer else {          // L398 guards on ctx == nil
            _ = allocResult   // ⚑ binary embeds this AVERROR in the KSPlayerError box (code@0); the exact
                              //   code-field mechanics (enum-vs-Int) = KSPlayerError-owner/P8 (throwing bodies throw KSPlayerError)
            throw KSPlayerError(code: .formatOutputCreate, message: KSPlayerErrorCode.formatOutputCreate.description)
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
        guard avio_open(&outputContext.pointee.pb, filename, AVIO_FLAG_WRITE) >= 0 else {   // L1246/1249
            throw KSPlayerError(description: "avio_open fail")   // code=.unknown; ⚑ binary embeds the AVERROR (P8)
        }
        // ⚑ DEFERRED — build `options` (AVDictionary) from formatContextOptions (FUN_101a322c0, L1262:
        //   [String:Any] → per-entry AVDictionary inserts, e.g. hls_segment_filename/hls_segment_type). Reconstruct
        //   as the options-dict unit; spine passes an empty dict (muxer defaults).
        var options: OpaquePointer?
        // ⚑[tool=ffmpeg_name_oracle ref=0x1031941d8 result=CONFIRMED] avformat_write_header (143/572)
        let headerResult = avformat_write_header(outputContext, &options)
        av_dict_free(&options)   // ⚑[tool=ffmpeg_name_oracle ref=0x10323b034 result=CONFIRMED] av_dict_free (27/108)
        guard headerResult >= 0 else {                          // L1266 / L1356
            throw KSPlayerError(code: .formatWriteHeader, message: KSPlayerErrorCode.formatWriteHeader.description)
        }

        // ── C4: assemble the 12 stored fields + return (implicit) — L1311-1380 ───────────────────────
        //   removeADTS = isHLS && options["hls_segment_type"]=="fmp4"  (fMP4 segments need raw AAC; L1267-1310)
        let segmentType = formatContextOptions["hls_segment_type"] as? String
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
        _ = flag              // ⚑ p8: mode selector read in the dead extension-switch + the loop's param_8 branches (write→0)
        _ = forceTranscode    // ⚑ p4: gates frameRate accumulation + a streamMapping-value branch (write→false)
        _ = transcodeCodecIDs // ⚑ p9: the transcode codec allowlist — consumed by the deferred transcode arms
    }

    // ── Phase-1 test scaffold (⚑ NOT binary-present) — retained so Phase2RemuxTest can exercise slots
    //    13/14/15 in isolation without the full factory. The binary's SOLE construction is the designated
    //    init above (FUN_101a1d014). Not used in any reconstructed path. ──────────────────────────────
    init(formatCtx: UnsafeMutablePointer<AVFormatContext>) {   // ⚑ test scaffold, not in binary
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
    public func finishWriting() {                           // public (was internal): RemuxerIOAction (ProAVPlayer) calls it cross-module via the OSI vtable +0x120 — binary-arbitrated cross-module access (P34/§1; `open`/override NOT proven → `public` under-included)
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
    public func close() {                                   // public (was internal): RemuxerIOAction calls it cross-module via the OSI vtable +0x128 (P34/§1; `open` not proven → `public` under-included)
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
