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

    // ── FFmpeg provenance (P32) — every av* symbol named in this class is ffmpeg_name_oracle result=CONFIRMED
    //   (instr/size fingerprint vs the linked lib); reconstructed bodies below cite these:
    //   ⚑[tool=ffmpeg_name_oracle ref=avcodec_decode_subtitle2:0x102a1a98c result=CONFIRMED]
    //   ⚑[tool=ffmpeg_name_oracle ref=avcodec_flush_buffers:0x10294d260 result=CONFIRMED]
    //   ⚑[tool=ffmpeg_name_oracle ref=avcodec_free_context:0x102d53ac8 result=CONFIRMED]
    //   ⚑[tool=ffmpeg_name_oracle ref=avsubtitle_free:0x10294d330 result=CONFIRMED]
    // decode() — base cce7002 = empty `{}`; no Forward body (DecodeProtocol no-op requirement). Faithful as-is.
    func decode() {}

    // decodeFrame — Batch 4 Tier 2a. Binary: FUN_101a69de8 (public: frame delivery) → FUN_101a69f54 (inner: decode +
    // timing + text() + empty fallback) → FUN_101a6a568 (text(subtitle:start:end:)). The public/inner split is compiler
    // outlining; the source is one method. Base cce7002 decodeFrame is the adaptation reference (P19/P61), reworked for
    // the SubtitlePart STRUCT (render:Either, start/end baked in) + the divergences flagged inline. Timing arms
    // disasm-verified (P42): FUN_101a69f54 @0x101a6a01c (ret<0), @0x101a6a038 (subtitle.pts branch), @0x101a6a0e0
    // (start adjust). Frame timestamp/duration: FUN_101a63adc (getPosition; the binary outlines it into the frame-init
    // helper — behaviorally identical whether in the loop here or SubtitleFrame.init).
    // ⚑ DEFERRED (Batch 5, TERMINAL — un-nameable primitives, consistent with AssImageParse.canParse={false}): the
    //   ASS-image detection+render arm of text() — the 4 detection helpers FUN_101a8e3b8/8f72c/90748/910ac, the
    //   10-regex complexity scan (DAT_1044eb5d0), the 3 KSOptions static gate flags (DAT_104c6315x), the
    //   assImageRenderer Task (FUN_101a03fd4) + pendingASSImageSubtitles buffering + lazy setup (FUN_101a6bc08).
    //   canParse={false} makes that path dead → deferring is zero-regression (spine-preserved-by-omission).
    func decodeFrame(from packet: Packet, completionHandler: @escaping (Result<MEFrame, Error>) -> Void) {
        guard let codecContext else {
            return
        }
        var gotsubtitle = Int32(0)
        // ⚑[tool=ffmpeg_name_oracle ref=avcodec_decode_subtitle2:0x102a1a98c result=CONFIRMED]
        let result = avcodec_decode_subtitle2(codecContext, &subtitle, &gotsubtitle, packet.corePacket)
        if result < 0 { // Forward addition (base ignored the return): FUN_101a69f54 @0x101a6a01c `tbnz w19,#0x1f`
            return
        }
        guard gotsubtitle != 0 else {
            return
        }
        // Forward addition: prefer the subtitle's own pts (µs timebase) over the packet timestamp (track timebase).
        // FUN_101a69f54 @0x101a6a038 (subtitle.pts == AV_NOPTS_VALUE), @0x101a6a090 (num=1, den=1_000_000).
        let timebase: Timebase
        let timestamp: Int64
        if subtitle.pts == Int64.min {
            timebase = assetTrack.timebase
            timestamp = packet.timestamp // binary recomputes from corePacket.pts/dts with a 0-fallback (FUN_101a69f54 @0x101a6a05c); differs from packet.timestamp only when BOTH pts&dts == AV_NOPTS_VALUE (degenerate)
        } else {
            timebase = Timebase(num: 1, den: 1_000_000)
            timestamp = subtitle.pts
        }
        var start = timebase.cmtime(for: timestamp).seconds + TimeInterval(subtitle.start_display_time) / 1000.0
        if start >= startTime.rounded(.down) { // FUN_101a69f54 @0x101a6a0e0: `frintm` floors startTime in the compare only; the subtraction uses full startTime
            start -= startTime
        }
        let end: Double
        if subtitle.end_display_time == UInt32.max {
            end = .infinity
        } else {
            var duration = TimeInterval(subtitle.end_display_time - subtitle.start_display_time) / 1000.0
            if duration == 0, packet.duration != 0 {
                duration = assetTrack.timebase.cmtime(for: packet.duration).seconds // ⚑ binary reads codecContext timebase @0x5c/0x60; assetTrack.timebase is the equivalent value
            }
            end = start + duration
        }
        var parts = text(subtitle: subtitle, start: start, end: end)
        if assImageRenderer == nil, parts.isEmpty {
            // base's empty placeholder part (base used attributedString: nil; the struct needs an empty text info).
            parts.append(SubtitlePart(start: start, end: end, render: .right(SubtitleTextInfo(text: NSAttributedString(), position: nil, displaySize: nil, styleRole: .primary, usesForcedPosition: false))))
        }
        // ⚑[tool=ffmpeg_name_oracle ref=avsubtitle_free:0x10294d330 result=CONFIRMED] — freed after text() extracts the
        // rect data into parts (Forward moves this before delivery; base freed it after the loop). FUN_101a69f54 @0x101a6a1ac.
        avsubtitle_free(&subtitle)
        for part in parts {
            let frame = SubtitleFrame(part: part, timebase: timebase)
            frame.timestamp = timebase.getPosition(from: part.start)
            if part.end.isFinite {
                frame.duration = max(timebase.getPosition(from: part.end) - frame.timestamp, 0)
            } else {
                frame.duration = Int64.max - max(frame.timestamp, 0)
            }
            completionHandler(.success(frame))
        }
    }

    // text(subtitle:start:end:) — FUN_101a6a568. Base cce7002 `text(subtitle:)` reworked: takes start/end (baked into
    // each part, since SubtitlePart is now a struct), assParse.parsePart returns [SubtitlePart] with a merge-vs-standalone
    // step, and the bitmap path builds SubtitleImageInfo/BitmapSource (not the removed VideoSwresample `scale`). This
    // reconstructs the text-rect and ASS-text (assParse) paths — faithful whenever the ASS-image feature is off (the
    // always-current state, since AssImageParse.canParse={false}). The ASS-image and SUBTITLE_BITMAP arms are DEFERRED
    // (see decodeFrame ⚑).
    private func text(subtitle: AVSubtitle, start: Double, end: Double) -> [SubtitlePart] {
        var parts = [SubtitlePart]()
        var images = [SubtitleImageInfo]()
        var attributedString: NSMutableAttributedString?
        for i in 0 ..< Int(subtitle.num_rects) {
            guard let rect = subtitle.rects[i]?.pointee else {
                continue
            }
            if let text = rect.text {
                if attributedString == nil {
                    attributedString = NSMutableAttributedString()
                }
                attributedString?.append(NSAttributedString(string: String(cString: text)))
            } else if let ass = rect.ass, let assParse {
                // ⚑ DEFERRED here (Batch 5): the ASS-image detection (\fs strip + 4 un-nameable helpers + 10-regex +
                //   KSOptions gate) that, when enabled, routes to assImageRenderer/pendingASSImageSubtitles. With the
                //   feature off the rect always falls through to assParse.parsePart. FUN_101a6a568 detection @0x101a6a6c0+.
                let scanner = Scanner(string: String(cString: ass))
                let assParts = assParse.parsePart(scanner: scanner)
                if let part = assParts.first {
                    if case let .right(textInfo) = part.render, !isASS {
                        if attributedString == nil {
                            attributedString = NSMutableAttributedString()
                        }
                        // Inline-merged ASS text renders PLAIN: the binary takes textInfo.text.string and rebuilds a
                        // bare NSAttributedString (FUN_101a6a568 cache 885 `objc_stub::string` → 895 initWithString:),
                        // stripping attributes. Styled/positioned parts go standalone (the else branch).
                        attributedString?.append(NSAttributedString(string: textInfo.text.string))
                    } else {
                        parts.append(SubtitlePart(start: start, end: end, render: part.render))
                    }
                }
            } else if rect.type == SUBTITLE_BITMAP, let bitmap = rect.data.0, let palette = rect.data.1 {
                // Tier 2b: SUBTITLE_BITMAP -> SubtitleImageInfo(.left). Net-new Forward code (replaces the removed
                // VideoSwresample scale.transfer path). Two Foundation.Data copies — the bitmap (linesize[0]*h) and the
                // palette (fixed AVPALETTE_SIZE = 256*4 = 1024) — plus a CGRect -> BitmapSource.palette. displaySize =
                // the codec reference resolution. FUN_101a6a568 cache 259-362; the 0x78 stride confirms .palette=Data.
                images.append(SubtitleImageInfo(
                    rect: CGRect(x: Int(rect.x), y: Int(rect.y), width: Int(rect.w), height: Int(rect.h)),
                    source: .palette(
                        bitmap: Data(bytes: bitmap, count: Int(rect.linesize.0) * Int(rect.h)),
                        palette: Data(bytes: palette, count: 1024),
                        width: Int(rect.w),
                        height: Int(rect.h),
                        stride: Int(rect.linesize.0)
                    ),
                    displaySize: CGSize(width: Double(codecContext?.pointee.width ?? 0), height: Double(codecContext?.pointee.height ?? 0)),
                    styleRole: .primary
                ))
            }
        }
        if let attributedString {
            parts.append(SubtitlePart(start: start, end: end, render: .right(SubtitleTextInfo(text: attributedString, position: nil, displaySize: nil, styleRole: .primary, usesForcedPosition: false))))
        }
        // Merge the bitmap-subtitle images (built above) as .left parts, stamped with the packet start/end — the text
        // accumulator part is emitted first, then the images. FUN_101a6a568 cache 992-1104 (stride 0x78 -> 0x88, .left).
        for image in images {
            parts.append(SubtitlePart(start: start, end: end, render: .left(image)))
        }
        return parts
    }

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
