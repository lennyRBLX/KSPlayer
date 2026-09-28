//
//  FFmpegDecode.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/9.
//

import AVFoundation
import Foundation
import Libavcodec
import Libavformat

class FFmpegDecode: DecodeProtocol {
    private let options: KSOptions
    private var coreFrame: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
    private var codecContext: UnsafeMutablePointer<AVCodecContext>?
    private var bestEffortTimestamp: Int64 = 0
    private let frameChange: FrameChange
    private let filter: MEFilter
    private var hasDecodeSuccess: Bool = false
    private let isVideo: Bool
    private let assetTrack: FFmpegAssetTrack
    required init(assetTrack: FFmpegAssetTrack, options: KSOptions) {
        self.options = options
        self.assetTrack = assetTrack
        isVideo = assetTrack.mediaType == .video
        do {
            codecContext = try assetTrack.createContext(options: options)
        } catch {
            KSLog(error as CustomStringConvertible)
        }
        codecContext?.pointee.time_base = assetTrack.timebase.rational
        filter = MEFilter(timebase: assetTrack.timebase, isAudio: assetTrack.mediaType == .audio, nominalFrameRate: assetTrack.nominalFrameRate, options: options)
        if assetTrack.mediaType == .video {
            frameChange = VideoSwresample(fps: assetTrack.nominalFrameRate, dovi: assetTrack.dovi)
        } else {
            frameChange = AudioSwresample(audioDescriptor: assetTrack.audioDescriptor!)
        }
    }

    // ⚠️ D1 CLOSED — the parameter is `UnsafeMutablePointer<AVPacket>`. Read over the whole extent
    // 0x101a2220c-0x101a22ca0 (677 instr, one exported symbol, no ICF fold): the parameter lives
    // in x24 and NEVER reaches an ARC helper (`mov x0, x24` does not occur anywhere), `[x24]` —
    // the isa word — is never read, and the ONLY offset dereferenced out of it is 0x28, read
    // three times and each time masked as a bit-field:
    //   101a222b8  ldr  w8,[x24,#0x28]  /  101a222c4  and  w1, w8, #0x1     AV_PKT_FLAG_KEY
    //   101a224b0  ldr  w8,[x24,#0x28]  /  101a224b4  tst  w8, #0x1         AV_PKT_FLAG_KEY
    //   101a22910  ldrb w8,[x24,#0x28]  /  101a22914  tbnz w8, #0x2         AV_PKT_FLAG_DISCARD
    // `Packet.size` also sits at 0x28, so the offset alone does NOT decide it — the flag masks
    // and the total absence of ARC traffic are what do. `Packet.assetTrack` is at 0x40 and is
    // never read out of the parameter at all.
    // ⚑[tool=field_offset_vector ref=FFmpegDecode:0x1039ef150 result=isVideo-0x61-assetTrack-0x68]
    // NOTE: `recover_field_offsets --module KSPlayer --class FFmpegDecode` recovers ZERO offsets
    // for this class — `field_offset_vector.py` is the tool that answers here (metadata
    // 0x1044e9418, FieldOffsetVectorOffset=10 words, InstanceSize 0x70).
    func decodeFrame(from packet: UnsafeMutablePointer<AVPacket>, completionHandler: @escaping (Result<MEFrame, Error>) -> Void) {
        // DEFERRED → DV-render/HDR-pixelBuffer phase (COUPLED unit): Forward moved this inline side-data loop (L71-142)
        // into VideoSwresample.s32 (0x101a67274; sole caller = this method @decompile-L182). s32 writes VideoSwresample's
        // DV/HDR fields that change s28 CONSUMES → frame, so loop-removal + s32 + change + transfer reconstruct as ONE unit
        // (landing s32 + removing this loop without change REGRESSES the edrMetaData path — change s28 grep-confirmed reads
        // +0x60/+0xc20../+0xc50/+0xc60). Gated on the protocol-witness verifier. Cached: FFmpegDecode_slot13/slot18.
        // The parameter is handed to the send call UNCHANGED — no field is loaded out of it first.
        // Four call sites, three passing it straight through and one draining with NULL:
        //   101a22254  mov x1, x24 / bl 0x102a1a424      (arg0 = self.codecContext @0x20)
        //   101a22614  mov x1, x24 / bl 0x102a1a424      (after codecContext re-create)
        //   101a22840  mov x1, #0x0 / bl 0x102a1a424     (the DRAIN call)
        //   101a228cc  mov x1, x24 / bl 0x102a1a424
        // ⚑[tool=ffmpeg_name_oracle ref=avcodec_send_packet:0x102a1a424 result=REFUTED]
        // ⚠️ THE ORACLE REFUTES THIS ONE, AND THE MARKER SAYS SO RATHER THAN ROUNDING UP. The sole
        // divergence from the reference build is a struct-offset immediate at instruction 11
        // (`ldr w8,[x21,#0x154]` against the stock `#0xa4`) — the known non-stock AVCodecContext
        // ABI — while all ten sibling candidates in the same fingerprint class diverge at index 0
        // or 3, and `--resolve` finds no instruction-for-instruction survivor at all. So the
        // identity rests on the ABI argument plus the company it keeps, NOT on the oracle.
        // Its three neighbours in this body ARE confirmed instruction-for-instruction:
        // ⚑[tool=ffmpeg_name_oracle ref=avcodec_receive_frame:0x10294dba0 result=CONFIRMED]
        // ⚑[tool=ffmpeg_name_oracle ref=avcodec_flush_buffers:0x10294d260 result=CONFIRMED]
        // ⚑[tool=ffmpeg_name_oracle ref=avcodec_free_context:0x102d53ac8 result=CONFIRMED]
        guard let codecContext = self.codecContext else {
            return
        }
        let sendResult = avcodec_send_packet(codecContext, packet)
        if sendResult != 0 {
            guard isVideo,
                  options.hardwareDecode,
                  codecContext.pointee.hw_device_ctx != nil,
                  options.recreateContext(
                      hasDecodeSuccess: hasDecodeSuccess,
                      isKeyFrame: packet.pointee.flags & AV_PKT_FLAG_KEY != 0
                  )
            else {
                return
            }
            avcodec_free_context(&self.codecContext)
            if sendResult != AVError.unknown.code, sendResult != AVError.tryAgain.code {
                options.hardwareDecode = false
            }
            KSLog(level: .error, "[video] videoToolbox ffmpeg decode failedCode=\(sendResult), hasDecodeSuccess=\(hasDecodeSuccess), isKeyFrame=\(packet.pointee.flags & AV_PKT_FLAG_KEY != 0). change to hardwareDecode=\(options.hardwareDecode)")
            do {
                let replacement = try assetTrack.createContext(options: options)
                replacement.pointee.time_base = assetTrack.stream?.pointee.time_base ?? assetTrack.timebase.rational
                self.codecContext = replacement
                _ = avcodec_send_packet(self.codecContext, packet)
            } catch {
                completionHandler(.failure(error))
                return
            }
        }
        var deliveredFrame = false
        // 需要avcodec_send_packet之后，properties的值才会变成FF_CODEC_PROPERTY_CLOSED_CAPTIONS
        // ⚠️ D2 CLOSED, and it is forced by D1 — with a raw pointer there is no `packet.assetTrack`
        // to ask. The binary asks SELF, and it asks a precomputed Bool rather than re-deriving the
        // mediaType: `ldrb w28,[x19,#0x61]` / `cmp w28,#0x1` / `b.ne` at 0x101a2261c, and again at
        // 0x101a22264 gating the send-failure path. Offset 0x61 is `isVideo` (field 7) and 0x68 is
        // `assetTrack` (field 8); this class sets both in `init` (:21-25), which is where the
        // `assetTrack.mediaType == .video` test actually lives in Forward.
        if isVideo {
            addClosedCaptionsTrack(assetTrack: assetTrack)
        }
        while true {
            let result = avcodec_receive_frame(self.codecContext, coreFrame)
            if result == 0, let inputFrame = coreFrame {
                if isVideo,
                   (inputFrame.pointee.repeat_pict == 1 || inputFrame.pointee.flags & AV_FRAME_FLAG_INTERLACED != 0),
                   assetTrack.fieldOrder.rawValue <= FFmpegFieldOrder.progressive.rawValue {
                    assetTrack.fieldOrder = inputFrame.pointee.flags & AV_FRAME_FLAG_TOP_FIELD_FIRST != 0 ? .tt : .bb
                    if options.context != "ReadCacheIOContext" {
                        options.deinterlace(assetTrack: assetTrack)
                        if !options.hardwareDecode,
                           self.codecContext?.pointee.hw_device_ctx != nil {
                            self.codecContext = try? assetTrack.createContext(options: options)
                            self.codecContext?.pointee.time_base = assetTrack.stream?.pointee.time_base ?? assetTrack.timebase.rational
                            _ = avcodec_send_packet(self.codecContext, packet)
                            continue
                        }
                    }
                }
                if !isVideo {
                    if assetTrack.codecpar.pointee.frame_size == 0,
                       inputFrame.pointee.sample_rate != 0,
                       inputFrame.pointee.nb_samples != 0 {
                        assetTrack.nominalFrameRate = Float(inputFrame.pointee.sample_rate) /
                            Float(inputFrame.pointee.nb_samples)
                    }
                    if inputFrame.pointee.ch_layout.nb_channels > 24 {
                        continue
                    }
                }
                hasDecodeSuccess = true
                deliveredFrame = true
                if packet.pointee.flags & AV_PKT_FLAG_DISCARD != 0 {
                    continue
                }
                if let videoSwresample = frameChange as? VideoSwresample {
                    videoSwresample.processSideData(frame: inputFrame.pointee, assetTrack: assetTrack, options: options, packet: packet)
                }
                filter.filter(options: options, inputFrame: inputFrame, isVideo) { avframe in
                    do {
                        var frame = try frameChange.change(avframe: avframe)
                        if let videoFrame = frame as? VideoVTBFrame {
                            if let pixelBuffer = videoFrame.pixelBuffer as? PixelBuffer {
                                pixelBuffer.formatDescription = assetTrack.formatDescription
                            }
                        }
                        frame.timebase = filter.timebase
                        //                frame.timebase = Timebase(avframe.pointee.time_base)
                        // CARRIED THROUGH D1, NOT RE-DERIVED. These two are inside the
                        // `filter.filter` closure, which is a SEPARATE binary function with its own
                        // address — the x24 scan that proves this method reads only AVPacket.flags
                        // covers 0x101a2220c-0x101a22ca0 and says nothing about the closure. The
                        // rewrite is the identity the source itself already asserts in
                        // `Packet.assetTrack.didSet` (Model.swift): `position = packet.pos` and
                        // `size = packet.size` off the same core pointer. The closure's own extent
                        // has NOT been read, so these two lines are unverified at their new
                        // spelling and are the first thing to check when that unit is opened.
                        // ⚑[tool=function_extents ref=FFmpegDecode.decodeFrame:0x101a2220c result=closure-extent-not-in-this-range]
                        // `frame.size = packet.pointee.size` dropped: Forward's `size` is a get-only requirement
                        // (ObjectQueueItem, 5 getters; MEFrame adds no size setter), so no MEFrame-typed store can exist.
                        frame.position = packet.pointee.pos
                        frame.duration = avframe.pointee.duration
                        if frame.duration == 0, avframe.pointee.sample_rate != 0, frame.timebase.num != 0 {
                            frame.duration = Int64(avframe.pointee.nb_samples) * Int64(frame.timebase.den) / (Int64(avframe.pointee.sample_rate) * Int64(frame.timebase.num))
                        }
                        var timestamp = avframe.pointee.best_effort_timestamp
                        if timestamp < 0 {
                            timestamp = avframe.pointee.pts
                        }
                        if timestamp < 0 {
                            timestamp = avframe.pointee.pkt_dts
                        }
                        if timestamp < 0 {
                            timestamp = bestEffortTimestamp
                        }
                        frame.timestamp = timestamp
                        bestEffortTimestamp = timestamp &+ frame.duration
                        completionHandler(.success(frame))
                    } catch {
                        completionHandler(.failure(error))
                    }
                }
            } else {
                if result == AVError.eof.code {
                    avcodec_flush_buffers(self.codecContext)
                    break
                } else if result == AVError.tryAgain.code {
                    if assetTrack.isImage,
                       !hasDecodeSuccess,
                       avcodec_send_packet(self.codecContext, nil) == 0 {
                        continue
                    }
                    return
                } else {
                    if deliveredFrame {
                        return
                    }
                    let error = KSPlayerError(errorCode: isVideo ? .codecVideoReceiveFrame : .codecAudioReceiveFrame, avErrorCode: result)
                    KSLog(error)
                    if isVideo, options.hardwareDecode {
                        avcodec_free_context(&self.codecContext)
                        options.hardwareDecode = false
                        self.codecContext = try? assetTrack.createContext(options: options)
                        self.codecContext?.pointee.time_base = assetTrack.stream?.pointee.time_base ?? assetTrack.timebase.rational
                        return
                    }
                    completionHandler(.failure(error))
                    return
                }
            }
        }
    }

    // vtable slot 14 — method descriptor @0x1039ef1f4 (descriptor 0x1039ef150 + 0xa4): flags 0x10
    // (kind Method, instance, not dynamic, not async) with a NULL impl (rel ptr 0 at 0x1039ef1f8).
    // It sits between decodeFrame (slot 13, 0x101a2220c) and doFlushCodec (slot 15, 0x101a23330).
    // No `Tq` method-descriptor symbol in the export trie (decodeFrame/doFlushCodec/shutdown/decode
    // all have one) ⇒ non-public; the null impl ⇒ never referenced, so WMO dropped the body — the
    // same null-impl pattern as the 12 private stored-property accessors in slots 0-11.
    // ⚑ NAME, SIGNATURE AND BODY ARE NOT RECOVERABLE (nothing references it; the descriptor carries
    //   no type). This declaration only occupies the slot so doFlushCodec/shutdown/decode/
    //   addClosedCaptionsTrack land on slots 15/16/17/18 as in Forward. Name INVENTED.
    private func vtableSlot14() {}

    func doFlushCodec() {
        bestEffortTimestamp = Int64(0)
        // seek之后要清空下，不然解码可能还会有缓存，导致返回的数据是之前seek的。
        if codecContext != nil {
            avcodec_flush_buffers(codecContext)
        }
    }

    @used func shutdown() {
        av_frame_free(&coreFrame)
        avcodec_free_context(&codecContext)
        frameChange.shutdown()
    }

    func decode() {
        bestEffortTimestamp = Int64(0)
        if codecContext != nil {
            avcodec_flush_buffers(codecContext)
        }
    }

    // slot 0x128 @0x101a23404 (private) — called from decodeFrame when isVideo; the CC checks live here.
    private func addClosedCaptionsTrack(assetTrack: FFmpegAssetTrack) {
        // ⚑ Forward retyped FFmpegAssetTrack.codecpar value→pointer, so the synthetic CC codecpar is
        //   heap-allocated (stable pointer the track stores) — the alloc folds into the compound `if`
        //   to match the binary (FUN_101a23404 L33-38: alloc-fail skips the block, not a return).
        //   ⚑[tool=ffmpeg_name_oracle ref=avcodec_parameters_alloc:0x1029f543c result=CONFIRMED]
        //   ⚑ ownership/free deferred to the FFmpegAssetTrack lifecycle audit (the alloc'd params are now owned by the track; the base value-copy had no free step).
        if let currentCodecContext = self.codecContext,
           Int32(currentCodecContext.pointee.properties) & FF_CODEC_PROPERTY_CLOSED_CAPTIONS != 0,
           assetTrack.closedCaptionsTrack == nil,
           let codecpar = avcodec_parameters_alloc() {
            codecpar.pointee.codec_type = AVMEDIA_TYPE_SUBTITLE
            codecpar.pointee.codec_id = AV_CODEC_ID_EIA_608
            if let subtitleAssetTrack = FFmpegAssetTrack(codecpar: codecpar, stream: nil) {
                subtitleAssetTrack.name = "Closed Captions"
                subtitleAssetTrack.startTime = assetTrack.startTime
                subtitleAssetTrack.timebase = assetTrack.timebase
                // ⚑[tool=export_trie_oracle ref=FUN_101a23404:0x101a23404 result=NOT_IN_TRIE — enclosing function
                //   unnamed (a real negative, not a lookup failure); identified by its own body, below]
                // Call @0x101a235a0 (thunk 0x101a3340c) inside that function: `w1 = 0x80` @0x101a23594 and
                // `w3 = 1` @0x101a2359c, both binary-read — so frameCapacity is 128 here, not the 255 source
                // carried. Site identified by its own body: `str d0,[x0]` @0x101a23480 writes the
                // codec_type/codec_id pair, swift_allocObject(351) @0x101a23498 is the FFmpegAssetTrack, and
                // the result is stored to +0x100 (`subtitle`) @0x101a235ac.
                let subtitle = SyncPlayerItemTrack<SubtitleFrame>(mediaType: .subtitle, frameCapacity: 128, options: options, expanding: true)
                subtitleAssetTrack.subtitle = subtitle
                assetTrack.closedCaptionsTrack = subtitleAssetTrack
                subtitle.decode()
            }
        }
    }
}
