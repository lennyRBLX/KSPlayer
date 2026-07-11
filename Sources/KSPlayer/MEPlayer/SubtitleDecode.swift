//
//  SubtitleDecode.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/11.
//

import CoreGraphics
import Foundation
import Libavformat
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// SubtitleDecode @0x1039f0530 — Forward 1.3.17. 10 stored fields (reflection-authoritative), types §8.3/§8.6.
// The recon's VideoSwresample `scale` bitmap path is GONE — the binary uses the ASS-image pipeline
// (assImageRenderer/pendingASSImageSubtitles); +assetTrack/isASS/fontsDir/subtitleHeader. Bodies → P4 M2.
class SubtitleDecode: DecodeProtocol {
    private var assImageRenderer: AssIncrementImageRenderer?
    private var codecContext: UnsafeMutablePointer<AVCodecContext>?
    private var subtitle: AVSubtitle = AVSubtitle()
    private var startTime: Double = 0
    private var assParse: AssParse?
    private var assetTrack: FFmpegAssetTrack
    private var isASS: Bool = false
    private var fontsDir: String?
    private var subtitleHeader: String?
    private var pendingASSImageSubtitles: [(subtitle: String, start: Double, duration: Double)] = [] // §8.6
    // ⚑ init shape inferred → M2 witness-verify (real init builds the codec ctx + ASS parse from assetTrack)
    required init(assetTrack: FFmpegAssetTrack, options _: KSOptions) {
        self.assetTrack = assetTrack
    }

    // ⚑ UNRESOLVED → P4 M2 (Batch 4, Tier 2): the ASS-image decode pipeline (decodeFrame → SubtitlePart
    //   via render:Either). Binary: FUN_101a69de8 (public decodeFrame) → FUN_101a69f54 (inner decode,
    //   avcodec_decode_subtitle2 @0x102a1a98c) → FUN_101a6a568 (AVSubtitle→text/ASS). Reconstruct in Tier 2.
    // ── FFmpeg provenance (P32) — every av* symbol named in this class is ffmpeg_name_oracle result=CONFIRMED
    //   (instr/size fingerprint vs the linked lib); reconstructed bodies below cite these:
    //   ⚑[tool=ffmpeg_name_oracle ref=avcodec_decode_subtitle2:0x102a1a98c result=CONFIRMED]
    //   ⚑[tool=ffmpeg_name_oracle ref=avcodec_flush_buffers:0x10294d260 result=CONFIRMED]
    //   ⚑[tool=ffmpeg_name_oracle ref=avcodec_free_context:0x102d53ac8 result=CONFIRMED]
    //   ⚑[tool=ffmpeg_name_oracle ref=avsubtitle_free:0x10294d330 result=CONFIRMED]
    // decode() — base cce7002 = empty `{}`; no Forward body (DecodeProtocol no-op requirement). Faithful as-is.
    func decode() {}
    func decodeFrame(from _: Packet, completionHandler _: @escaping (Result<MEFrame, Error>) -> Void) {}

    // FUN_101a6a3ac — doFlushCodec() (Forward ADDITION; base cce7002 = empty `{}`). Flush the subtitle
    // decoder's buffers. ⚑ FFmpeg CONFIRMED (ffmpeg_name_oracle): avcodec_flush_buffers @0x10294d260
    // (self+0x18 `codecContext`). ⚑ UNRESOLVED → Batch 5 (spine-preserved-by-omission, cardinal rule):
    //   the binary ALSO spawns a `Task { }` (FUN_101a03fd4) capturing self+0x10 `assImageRenderer` to
    //   async-reset the incremental ASS renderer — but that renderer method does NOT yet exist
    //   (AssIncrementImageRenderer is a Batch-5 skeleton with only `search` stubbed). Reconstruct the Task
    //   body together with the renderer in Batch 5; NOT fabricated here.
    func doFlushCodec() {
        if let codecContext {
            avcodec_flush_buffers(codecContext)
        }
    }

    // FUN_101a6a4ec — shutdown() (base-adapted, P19/P61: base cce7002 body MINUS the removed
    // VideoSwresample `scale.shutdown()` — Forward dropped the `scale` field, §8.3). Frees the decoded
    // subtitle then the codec context. ⚑ FFmpeg CONFIRMED (ffmpeg_name_oracle): avsubtitle_free
    // @0x10294d330 (self+0x20 `subtitle`), avcodec_free_context @0x102d53ac8 (self+0x18 `codecContext`).
    func shutdown() {
        avsubtitle_free(&subtitle)
        if codecContext != nil {
            avcodec_free_context(&self.codecContext)
        }
    }
}
