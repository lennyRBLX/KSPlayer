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

// Static [String] object 0x1044eb5b0 (count 10, elements @0x1044eb5d0, SubtitleDecode.swift data region), read
// directly (no once-token) by AssImageParse.canParse 0x101a96b98 (loop `mov w23,#0xb` over 0x1044eb5d8, each
// element → StringProtocol._range(of:options: 0x401 = .regularExpression|.caseInsensitive)) and SubtitleDecode.text
// 0x101a6a568. Element literals read verbatim from the static object. Name unrecovered.
let assEffectTagPatterns = [ // INFERRED
    #"\\(?:move|pos|org|fad|fade|clip|iclip|t)\s*\("#,
    #"\\(?:frx|fry|frz|fr|fax|fay|pbo|blur|be|xbord|ybord|xshad|yshad)\s*[-+]?\d"#,
    #"\\(?:kf|ko|K|k)\s*\d"#,
    #"\\p\s*[1-9]"#,
    #"\\(?:alpha|[1-4]a)&H"#,
    #"\\(?:an|a)\s*\d+"#,
    #"\\(?:fn|fs|fscx|fscy|fsp)\s*[^\\{}]*"#,
    #"\\(?:bord|shad)\s*[-+]?\d"#,
    #"\\(?:[1-4]?c)&H"#,
    #"\\r[^\\{}]*"#,
]

// SubtitleDecode @0x1039f0530 — Forward 1.3.17. 10 stored fields (reflection-authoritative), types §8.3/§8.6.
// The recon's VideoSwresample `scale` bitmap path is GONE — the binary uses the ASS-image pipeline
// (assImageRenderer/pendingASSImageSubtitles); +assetTrack/isASS/fontsDir/subtitleHeader. Bodies → P4 M2.
class SubtitleDecode: DecodeProtocol {
    var assImageRenderer: AssIncrementImageRenderer?
    private var codecContext: UnsafeMutablePointer<AVCodecContext>?
    private var subtitle: AVSubtitle = AVSubtitle()
    // ⚑[tool=field_surface ref=SubtitleDecode.assParse:idx4 result=let AssParse?] Record flags 0 (`let`).
    //   The init assigns it exactly once — the parsed AssParse, or nil — after the header probe.
    private let startTime: Double
    private let assParse: AssParse?
    private let assetTrack: FFmpegAssetTrack
    private let isASS: Bool
    private let fontsDir: String?
    private var subtitleHeader: String?
    // `start`/`duration` are Int64, not Double. The field record cannot settle it — its type
    // mangle is `SaySS8subtitle_<SYM:2@0x10536e600>5startAB8durationtG`, whose symbolic reference
    // resolves past __text (ends 0x103451708) and is not a bind site, so `dump_binary_field_types`
    // reports the row unmapped. The export trie decides it in ONE class-proven symbol — class,
    // field and type in the same mangling — and `xcrun swift-demangle` reads it as
    // `[(subtitle: Swift.String, start: Swift.Int64, duration: Swift.Int64)]`:
    //   $s8KSPlayer14SubtitleDecodeC24pendingASSImageSubtitles33_F85593AD49D6A91639A62D57F41DA4BDLLSaySS8subtitle_s5Int64V5startAH8durationtGvpfi
    // The `33_…LL` discriminator also confirms `private`. No call site changes: the field is
    // declared and never read (its bodies are still deferred), so this is a declaration-only fix.
    private var pendingASSImageSubtitles: [(subtitle: String, start: Int64, duration: Int64)] = [] // §8.6
    // init(assetTrack:options:) — Batch 4 Tier 3a. FUN_101a6914c (via __allocating_init thunk 0x101a69100). Base  ⚑[tool=resolve_fun_pins ref=FUN_101a6914c:0x101a6914c result=RESOLVES_UNIQUELY] = KSPlayer.SubtitleDecode.init(assetTrack: KSPlayer.FFmpegAssetTrack, options: KSPlayer.KSOptions?) -> KSPlayer.SubtitleDecode
    // cce7002 init is the adaptation reference, reworked for Forward's added fields (assetTrack/isASS/fontsDir/
    // subtitleHeader §8.3). isASS = codec_id in {SSA/ASS/EIA_608}
    // (DAT_1044eb330/334/338 read = 0x17004/0x17016/0x1700a). Only the non-optional stored field (assetTrack) needs
    // setting; the rest take their declared defaults (nil / AVSubtitle() / [] / 0 / false). Throwing: createContext
    // do/catch. FFmpeg fields accessed SYMBOLICALLY (this build is FFmpeg 7.1, non-stock ABI).
    // L7 lane 15: the !isASS Style-line rewrite (0x101aa17f4 = assDefaultStyleLine, KSOptions statics) and the
    //   flag-gated AssIncrementImageRenderer arm are now written from the Forward body (see inline notes).
    // ⚑ P55 REFINEMENT (session 32): `options` is `KSOptions?` (was non-optional — a Tier-3a faithfulness error).
    //   Forward's binary FUN_101a6914c guards `if options == nil { fontsDir = String?.none }` (disasm @0x101a692a8);  ⚑[tool=resolve_fun_pins ref=FUN_101a6914c:0x101a6914c result=RESOLVES_UNIQUELY] = KSPlayer.SubtitleDecode.init(assetTrack: KSPlayer.FFmpegAssetTrack, options: KSPlayer.KSOptions?) -> KSPlayer.SubtitleDecode
    //   the FFmpegSubtitle.init caller passes nil (`mov x1,#0x0` @0x101a9f5d8). Nullable options flows to createContext
    //   (already `KSOptions?`). Other caller MEPlayerItemTrack:304 passes non-nil (binds unchanged).
    required init(assetTrack: FFmpegAssetTrack, options: KSOptions?) {
        // 0x101a69244 CMTime.seconds → +0x28 (startTime) precedes 0x101a6924c str x24,[x25,#0x38] (assetTrack).
        startTime = assetTrack.startTime.seconds
        self.assetTrack = assetTrack
        fontsDir = options?.fontsDir?.path
        isASS = [AV_CODEC_ID_SSA, AV_CODEC_ID_ASS, AV_CODEC_ID_EIA_608].contains(assetTrack.codecpar.pointee.codec_id)
        // 0x101a69378 bl createContext (pkt_timebase store at +0x5c is FFmpegAssetTrack.createContext inlined);
        // success stores +0x18 (0x101a69504), error (cbz x21 @0x101a69380) logs and skips the store — no
        // separate time_base write in Forward.
        do {
            codecContext = try assetTrack.createContext(options: options)
        } catch {
            // 0x101a693a4 `cmp w8,#0x2; b.cs` + 0x101a6947c `mov w0,#0x2`: Forward logs at .error (LogLevel
            // case index 2), i.e. the KSLog(_ error:) overload inlined (error() as NSError @0x101a6943c).
            KSLog(error)
        }
        // 0x101a69520/28: codecContext nil or subtitle_header nil → assParse (+0x48) = nil, return.
        guard let pointer = codecContext?.pointee.subtitle_header else {
            assParse = nil
            return
        }
        var subtitleHeader = String(cString: pointer)
        // !isASS (tbz w22 @0x101a6953c): outlined split 0x101a699dc (Int.max, true; predicate == "\r\n" (0xa0d) ||
        // == "\n" (0xa)), map hasPrefix("Style: Default,") (0x10057cbc0) ? 0x101aa17f4 : String(sub), joined "\n".
        if !isASS {
            subtitleHeader = subtitleHeader.split { $0 == "\r\n" || $0 == "\n" }.map { $0.hasPrefix("Style: Default,") ? assDefaultStyleLine() : String($0) }.joined(separator: "\n")
        }
        self.subtitleHeader = subtitleHeader
        // Gates (DAT_104c63150 isASSUseImageRender && isASS) || (151 isSRTUseImageRender && !isASS) ||
        // (152 preferEffectSubtitle && isASS && 0x101a8e3b8(header)) → AssIncrementImageRenderer(fontsDir:header:)
        // 0x101a92d2c stored at +0x10 and into assetTrack+0x108 (subtitleRender, FUN_101a2119c), assParse nil;
        // else AssParse() + Scanner(string:) → canParse 0x101a97464.
        if (KSOptions.isASSUseImageRender && isASS) || (KSOptions.isSRTUseImageRender && !isASS) || (KSOptions.preferEffectSubtitle && isASS && assHasCustomStyle(subtitleHeader)) {
            let renderer = AssIncrementImageRenderer(fontsDir: fontsDir, header: subtitleHeader)
            assImageRenderer = renderer
            assetTrack.subtitleRender = renderer
            assParse = nil
        } else {
            let assParse = AssParse()
            self.assParse = assParse.canParse(scanner: Scanner(string: subtitleHeader)) ? assParse : nil
        }
    }

    // ── FFmpeg provenance (P32) — every av* symbol named in this class is ffmpeg_name_oracle result=CONFIRMED
    //   (instr/size fingerprint vs the linked lib); reconstructed bodies below cite these:
    //   ⚑[tool=ffmpeg_name_oracle ref=avcodec_decode_subtitle2:0x102a1a98c result=CONFIRMED]
    //   ⚑[tool=ffmpeg_name_oracle ref=avcodec_flush_buffers:0x10294d260 result=CONFIRMED]
    //   ⚑[tool=ffmpeg_name_oracle ref=avcodec_free_context:0x102d53ac8 result=CONFIRMED]
    //   ⚑[tool=ffmpeg_name_oracle ref=avsubtitle_free:0x10294d330 result=CONFIRMED]
    // decode() — base cce7002 = empty `{}`; no Forward body (DecodeProtocol no-op requirement). Faithful as-is.
    func decode() {}

    // decodeFrame(from:completionHandler:) — FUN_101a69de8, the DecodeProtocol witness. Calls the synchronous  ⚑[tool=resolve_fun_pins ref=FUN_101a69de8:0x101a69de8 result=RESOLVES_UNIQUELY] = KSPlayer.SubtitleDecode.decodeFrame(from: Swift.UnsafeMutablePointer<__C.AVPacket>, completionHandler: (Swift.Result<KSPlayer.MEFrame, Swift.Error>) -> ()) -> ()
    // decodeFrame(from:) above on packet.corePacket, then delivers each part as a SubtitleFrame. FUN_101a69de8  ⚑[tool=resolve_fun_pins ref=FUN_101a69de8:0x101a69de8 result=RESOLVES_UNIQUELY] = KSPlayer.SubtitleDecode.decodeFrame(from: Swift.UnsafeMutablePointer<__C.AVPacket>, completionHandler: (Swift.Result<KSPlayer.MEFrame, Swift.Error>) -> ()) -> ()
    // @0x101a69e24 captures the tuple's .timebase (x2) and passes it to the frame-init getPosition helper (FUN_101a63adc,
    // outlined into the frame build); the tuple's .timestamp (x1) is unused here (frame timing derives from part.start).
    // The parameter is the raw pointer, and this body forwards it UNCHANGED — it loads no field
    // out of it. Between entry and the call only x1 and x2 move; x0 and x20 are untouched:
    //   101a69e08  mov x19, x2      101a69e0c  mov x21, x1
    //   101a69e10  bl  0x101a69f54  101a69e14  cbz x0, 0x101a69f10   (the nil-tuple early return)
    // So the `packet.corePacket` unwrap this body used to do belongs to the CALLER now, and the
    // two-overload split is the binary's own: 0x101a69de8 (91 instr) ends exactly where
    // 0x101a69f54 (278 instr) begins.
    func decodeFrame(from packet: UnsafeMutablePointer<AVPacket>, completionHandler: @escaping (Result<MEFrame, Error>) -> Void) {
        guard let (parts, _, timebase) = decodeFrame(from: packet) else {
            return
        }
        for part in parts {
            // timestamp/duration are set inside SubtitleFrame.init @0x101a63adc.
            let frame = SubtitleFrame(part: part, timebase: timebase)
            completionHandler(.success(frame))
        }
    }

    // text(subtitle:start:end:) — FUN_101a6a568. Base cce7002 `text(subtitle:)` reworked: takes start/end (baked into
    // each part, since SubtitlePart is now a struct), assParse.parsePart returns [SubtitlePart] with a merge-vs-standalone
    // step, and the bitmap path builds SubtitleImageInfo/BitmapSource (not the removed VideoSwresample `scale`). This
    // reconstructs the text-rect and ASS-text (assParse) paths — faithful whenever the ASS-image feature is off (the
    // always-current state, since AssImageParse.canParse={false}). The ASS-image and SUBTITLE_BITMAP arms are DEFERRED
    // (see decodeFrame ⚑).
    private func text(subtitle: AVSubtitle, start: Double, end: Double, displaySize: CGSize) -> [SubtitlePart] {
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
            } else if let ass = rect.ass {
                // an ASS rect without assParse is skipped, not tried as a bitmap (@0x101a6a568).
                guard let assParse else {
                    continue
                }
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
                        parts.append(SubtitlePart(start, end, render: part.render))
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
                    displaySize: displaySize, // the d2/d3 parameter, not a codecContext re-read
                    styleRole: .primary
                ))
            }
        }
        if let attributedString {
            parts.append(SubtitlePart(start, end, render: .right(SubtitleTextInfo(text: attributedString, position: nil, displaySize: nil, styleRole: .primary, usesForcedPosition: false))))
        }
        // Merge the bitmap-subtitle images (built above) as .left parts, stamped with the packet start/end — the text
        // accumulator part is emitted first, then the images. FUN_101a6a568 cache 992-1104 (stride 0x78 -> 0x88, .left).
        for image in images {
            parts.append(SubtitlePart(start, end, render: .left(image)))
        }
        return parts
    }

    // FUN_101a6a3ac — doFlushCodec() (Forward ADDITION; base cce7002 = empty `{}`). Flush the subtitle  ⚑[tool=resolve_fun_pins ref=FUN_101a6a3ac:0x101a6a3ac result=RESOLVES_UNIQUELY] = KSPlayer.SubtitleDecode.doFlushCodec() -> ()
    // decoder's buffers. ⚑ FFmpeg CONFIRMED (ffmpeg_name_oracle): avcodec_flush_buffers @0x10294d260
    // (self+0x18 `codecContext`). ⚑ UNRESOLVED → Batch 5 (spine-preserved-by-omission, cardinal rule):
    //   the binary ALSO spawns a `Task { }` (FUN_101a03fd4) capturing self+0x10 `assImageRenderer` to
    //   async-reset the incremental ASS renderer — but that renderer method does NOT yet exist
    //   (AssIncrementImageRenderer is a Batch-5 skeleton with only `search` stubbed). Reconstruct the Task
    //   body together with the renderer in Batch 5; NOT fabricated here.
    @used func doFlushCodec() {
        if let codecContext {
            avcodec_flush_buffers(codecContext)
        }
        if let assImageRenderer {
            Task {
                await assImageRenderer.flush()
            }
        }
    }

    // FUN_101a6a4ec — shutdown() (base-adapted, P19/P61: base cce7002 body MINUS the removed  ⚑[tool=resolve_fun_pins ref=FUN_101a6a4ec:0x101a6a4ec result=RESOLVES_UNIQUELY] = KSPlayer.SubtitleDecode.shutdown() -> ()
    // VideoSwresample `scale.shutdown()` — Forward dropped the `scale` field, §8.3). Frees the decoded
    // subtitle then the codec context. ⚑ FFmpeg CONFIRMED (ffmpeg_name_oracle): avsubtitle_free
    // @0x10294d330 (self+0x20 `subtitle`), avcodec_free_context @0x102d53ac8 (self+0x18 `codecContext`).
    @used func shutdown() {
        avsubtitle_free(&subtitle)
        if codecContext != nil {
            avcodec_free_context(&self.codecContext)
        }
    }

    // decodeFrame(from:) — FUN_101a69f54, `SubtitleDecode.decodeFrame(from:) -> ([SubtitlePart], Int64, Timebase)?`.
    // Forward SPLIT the base's single completion-handler decodeFrame into this SYNCHRONOUS decode core + a
    // completion-handler wrapper (decodeFrame(from:completionHandler:) below = FUN_101a69de8, which calls this). The  ⚑[tool=resolve_fun_pins ref=FUN_101a69de8:0x101a69de8 result=RESOLVES_UNIQUELY] = KSPlayer.SubtitleDecode.decodeFrame(from: Swift.UnsafeMutablePointer<__C.AVPacket>, completionHandler: (Swift.Result<KSPlayer.MEFrame, Swift.Error>) -> ()) -> ()
    // split lets the subtitle-sidecar path (FFmpegSubtitle.init) and search(with:) accumulate [SubtitlePart] directly.
    // THREE callers (get_function_xrefs 0x101a69f54): FUN_101a69de8 (completion — uses .parts + .timebase, captured  ⚑[tool=resolve_fun_pins ref=FUN_101a69de8:0x101a69de8 result=RESOLVES_UNIQUELY] = KSPlayer.SubtitleDecode.decodeFrame(from: Swift.UnsafeMutablePointer<__C.AVPacket>, completionHandler: (Swift.Result<KSPlayer.MEFrame, Swift.Error>) -> ()) -> ()
    // @0x101a69e24 x2), FUN_101a9f27c=FFmpegSubtitle.init (uses .parts), FUN_101a9fa34=search(with:) async (deferred stub).
    // Takes the RAW AVPacket* (FFmpegSubtitle.init passes its allocated packet pointer directly; pts@+0x08 / dts@+0x10 /
    // duration@+0x40 read here) — NOT a Packet wrapper. Base cce7002 decodeFrame is the adaptation reference (P19/P61),
    // reworked for the SubtitlePart STRUCT (render:Either, start/end baked in). Returns nil (x0=0) on the guard-fail
    // paths (no codecContext / decode<0 / no subtitle); timestamp/timebase are x1/x2 of the tuple return. Timing arms
    // disasm-verified (P42): FUN_101a69f54 @0x101a6a01c (ret<0), @0x101a6a038 (subtitle.pts branch), @0x101a6a0e0 (start floor).
    // ⚑ DEFERRED (Batch 5, TERMINAL — un-nameable primitives, consistent with AssImageParse.canParse={false}): the
    //   ASS-image detection+render arm of text() — the 4 detection helpers FUN_101a8e3b8/8f72c/90748/910ac, the
    //   10-regex complexity scan (DAT_1044eb5d0), the 3 KSOptions static gate flags (DAT_104c6315x), the
    //   assImageRenderer Task (FUN_101a03fd4) + pendingASSImageSubtitles buffering + lazy setup (FUN_101a6bc08).
    //   canParse={false} makes that path dead → deferring is zero-regression (spine-preserved-by-omission).
    func decodeFrame(from packet: UnsafeMutablePointer<AVPacket>) -> ([SubtitlePart], timestamp: Int64, timebase: Timebase)? {
        guard let codecContext else {
            return nil
        }
        var gotsubtitle = Int32(0)
        let result = avcodec_decode_subtitle2(codecContext, &subtitle, &gotsubtitle, packet) // ⚑[tool=ffmpeg_name_oracle ref=avcodec_decode_subtitle2:0x102a1a98c result=CONFIRMED]
        if result < 0 { // Forward addition (base ignored the return): FUN_101a69f54 @0x101a6a01c `tbnz w19,#0x1f`
            return nil
        }
        guard gotsubtitle != 0 else {
            return nil
        }
        // Forward addition: prefer the subtitle's own pts (µs timebase) over the packet timestamp (track timebase).
        // FUN_101a69f54 @0x101a6a038 (subtitle.pts == AV_NOPTS_VALUE), @0x101a6a090 (num=1, den=1_000_000).
        let timebase: Timebase
        let timestamp: Int64
        if subtitle.pts == Int64.min {
            timebase = assetTrack.timebase
            // FUN_101a69f54 @0x101a6a05c: timestamp = pts (if set) else dts (if set) else 0, read from the raw AVPacket
            // (self+0x38..). This is the faithful form of the prior `packet.timestamp` approximation.
            if packet.pointee.pts != Int64.min {
                timestamp = packet.pointee.pts
            } else if packet.pointee.dts != Int64.min {
                timestamp = packet.pointee.dts
            } else {
                timestamp = 0
            }
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
            if duration == 0, packet.pointee.duration != 0 {
                // The duration fallback reads codecContext.time_base (num@+0x5c / den@+0x60 per the non-stock FFmpeg
                // ABI), reconstructed symbolically: @0x101a6a124 `ldrsw` num · @0x101a6a138 `ldr` den · CMTime(value:
                // duration*num, timescale: den). (Previously assetTrack.timebase — a stream-vs-codec value equivalence
                // both audit rounds flagged; now byte-faithful by construction — the trivial Timebase init inlines away.)
                duration = Timebase(codecContext.pointee.time_base).cmtime(for: packet.pointee.duration).seconds
            }
            end = start + duration
        }
        // displaySize = codecContext width/height (+0x70/+0x74 @0x101a6a154, `scvtf` d2/d3) passed into text() @0x101a6a178.
        var parts = text(subtitle: subtitle, start: start, end: end, displaySize: CGSize(width: Int(codecContext.pointee.width), height: Int(codecContext.pointee.height)))
        if assImageRenderer == nil, parts.isEmpty {
            // Placeholder for an empty subtitle cue: a part covering [start, end] whose text is the normalization
            // pipeline applied to an empty string. The binary (@0x101a6a204-0x101a6a2e4) runs the same normalization it
            // uses for real text: get_whitespaces(@0x103451bac) → StringProtocol.trimmingCharacters(@0x103458908) →
            // replacingOccurrences(@0x103458914, of="\r"/with="") → String._bridgeToObjectiveC → NSAttributedString
            // initWithString:(@0x103463620), stored at the text-info +0x30. The receiver is a PROVEN literal "":
            // @0x101a6a204 materializes it with immediate stores (`stp xzr,x8`, x8=0xe000000000000000 = the empty
            // small-string), NOT a field load; the trim receiver is x20=&"" while x0=x22 holds the .whitespaces
            // CharacterSet (get_whitespaces' x8-indirect result), so trimming "" is a no-op and the cue renders empty.
            // (Supersedes the s33 <s>-unresolved deferral: x22 was misread as the receiver — it is the CharacterSet.)
            parts.append(SubtitlePart(start, end, render: .right(SubtitleTextInfo(text: NSAttributedString(string: "".trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\r", with: "")), position: nil, displaySize: nil, styleRole: .primary, usesForcedPosition: false))))
        }
        // ⚑[tool=ffmpeg_name_oracle ref=avsubtitle_free:0x10294d330 result=CONFIRMED] — freed after text() extracts the
        // rect data into parts (Forward moves this before delivery; base freed it after the loop). FUN_101a69f54 @0x101a6a1ac.
        avsubtitle_free(&subtitle)
        return (parts, timestamp, timebase)
    }
}
