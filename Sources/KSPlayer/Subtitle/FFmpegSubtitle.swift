//
//  FFmpegSubtitle.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — FFmpegSubtitle at 0x101362AE4
//  Swift actor providing thread-safe external subtitle file parsing via FFmpeg.
//  Opens a separate AVFormatContext for the subtitle file, finds the subtitle stream,
//  demuxes via av_read_frame, and decodes via avcodec_decode_subtitle2.
//

import CoreGraphics
import Foundation
import Libavcodec
import Libavformat
import Libavutil
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Actor-isolated FFmpeg subtitle file parser.
///
/// Opens a separate AVFormatContext for an external subtitle file (independent of
/// the main media context), finds the subtitle stream, and demuxes/decodes packets
/// into SubtitlePart arrays. Actor isolation serializes FFmpeg operations to prevent
/// data races on seek/track switch.
///
/// RE: 8-field actor (formatCtx, decode, subtitleStreamIndex, preTime, startTime,
/// endTime, parts) with DefaultActorStorage. Conforms to KSSubtitleProtocol.
public actor FFmpegSubtitle: KSSubtitleProtocol {
    private var formatCtx: UnsafeMutablePointer<AVFormatContext>?
    private var codecCtx: UnsafeMutablePointer<AVCodecContext>?
    private var subtitle = AVSubtitle()
    private var subtitleStreamIndex: Int32 = -1
    private var preTime: Double = 0
    private var startTime: Double = 0
    private var endTime: Double = 0
    private var parts: [SubtitlePart] = []
    private let assParse = AssParse()

    public init() {}

    // MARK: - KSSubtitleProtocol

    /// Search for subtitle parts matching the given time.
    /// Called from main thread via nonisolated wrapper.
    nonisolated public func search(for time: TimeInterval) -> [SubtitlePart] {
        // For external subtitle files, parts are pre-parsed and sorted.
        // We need to do a synchronous search, so we capture parts in init.
        // In practice, the caller should use the async searchAsync method.
        []
    }

    /// Async search that respects actor isolation.
    public func searchAsync(for time: TimeInterval) -> [SubtitlePart] {
        var result = [SubtitlePart]()
        for part in parts {
            if part.start <= time, part.end >= time {
                result.append(part)
            } else if part.start > time {
                break
            }
        }
        return result
    }

    // MARK: - File Loading

    /// Open and parse an external subtitle file via FFmpeg.
    /// - Parameters:
    ///   - url: URL of the subtitle file (local or remote).
    ///   - options: KSOptions for codec configuration.
    /// - Returns: The parsed subtitle parts array.
    @discardableResult
    public func loadFile(url: URL) throws -> [SubtitlePart] {
        shutdown()

        var fmtCtx: UnsafeMutablePointer<AVFormatContext>?
        let path = url.isFileURL ? url.path : url.absoluteString

        let ret = avformat_open_input(&fmtCtx, path, nil, nil)
        guard ret >= 0, let fmtCtx else {
            throw NSError(errorCode: .subtitleFormatUnSupport)
        }
        formatCtx = fmtCtx

        guard avformat_find_stream_info(fmtCtx, nil) >= 0 else {
            shutdown()
            throw NSError(errorCode: .subtitleFormatUnSupport)
        }

        // Find the first subtitle stream
        subtitleStreamIndex = -1
        for i in 0 ..< Int32(fmtCtx.pointee.nb_streams) {
            if fmtCtx.pointee.streams[Int(i)]!.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_SUBTITLE {
                subtitleStreamIndex = i
                break
            }
        }

        guard subtitleStreamIndex >= 0 else {
            shutdown()
            throw NSError(errorCode: .subtitleFormatUnSupport)
        }

        let stream = fmtCtx.pointee.streams[Int(subtitleStreamIndex)]!
        let codecpar = stream.pointee.codecpar!

        // Set up codec context
        guard let codec = avcodec_find_decoder(codecpar.pointee.codec_id) else {
            shutdown()
            throw NSError(errorCode: .codecSubtitleSendPacket)
        }

        guard let ctx = avcodec_alloc_context3(codec) else {
            shutdown()
            throw NSError(errorCode: .codecSubtitleSendPacket)
        }
        codecCtx = ctx

        avcodec_parameters_to_context(ctx, codecpar)
        guard avcodec_open2(ctx, codec, nil) >= 0 else {
            shutdown()
            throw NSError(errorCode: .codecSubtitleSendPacket)
        }

        // Parse ASS header if present
        if let header = ctx.pointee.subtitle_header, ctx.pointee.subtitle_header_size > 0 {
            let headerStr = String(cString: header)
            _ = assParse.canParse(scanner: Scanner(string: headerStr))
        }

        // Calculate time base
        let timebase = Timebase(stream.pointee.time_base)
        if stream.pointee.start_time != Int64(AV_NOPTS_VALUE) {
            startTime = timebase.cmtime(for: stream.pointee.start_time).seconds
        }

        // Read and decode all subtitle packets
        parts.removeAll()
        let packet = av_packet_alloc()
        defer { av_packet_free(&packet) }

        while av_read_frame(fmtCtx, packet) >= 0 {
            defer { av_packet_unref(packet) }

            guard packet!.pointee.stream_index == subtitleStreamIndex else {
                continue
            }

            var gotSubtitle: Int32 = 0
            let decodeRet = avcodec_decode_subtitle2(ctx, &subtitle, &gotSubtitle, packet)
            guard decodeRet >= 0, gotSubtitle != 0 else {
                continue
            }

            let pts = packet!.pointee.pts != Int64(AV_NOPTS_VALUE)
                ? packet!.pointee.pts
                : packet!.pointee.dts

            var start = timebase.cmtime(for: pts).seconds
                + TimeInterval(subtitle.start_display_time) / 1000.0
            if start >= startTime {
                start -= startTime
            }

            var duration = 0.0
            if subtitle.end_display_time != UInt32.max {
                duration = TimeInterval(subtitle.end_display_time - subtitle.start_display_time) / 1000.0
            }
            if duration == 0, packet!.pointee.duration != 0 {
                duration = timebase.cmtime(for: packet!.pointee.duration).seconds
            }

            let decodedParts = decodeSubtitleRects()
            for part in decodedParts {
                part.start = start
                part.end = duration > 0 ? start + duration : .infinity
                parts.append(part)
            }

            avsubtitle_free(&subtitle)
        }

        // Sort by start time
        parts.sort { $0.start < $1.start }
        endTime = parts.last?.end ?? 0

        return parts
    }

    /// Get all parsed parts.
    public func getParts() -> [SubtitlePart] {
        parts
    }

    // MARK: - Subtitle Rect Decoding

    /// Decode subtitle rects from the current AVSubtitle.
    private func decodeSubtitleRects() -> [SubtitlePart] {
        var decodedParts = [SubtitlePart]()

        for i in 0 ..< Int(subtitle.num_rects) {
            guard let rect = subtitle.rects[i]?.pointee else { continue }

            if let text = rect.text {
                let str = String(cString: text)
                decodedParts.append(SubtitlePart(0, 0, str))
            } else if let ass = rect.ass {
                let scanner = Scanner(string: String(cString: ass))
                if let part = assParse.parsePart(scanner: scanner) {
                    decodedParts.append(part)
                }
            }
            // Note: SUBTITLE_BITMAP rects are handled by SubtitleDecode in the
            // embedded path, not here in the external file path.
        }

        return decodedParts
    }

    // MARK: - Lifecycle

    /// Release all FFmpeg resources.
    public func shutdown() {
        avsubtitle_free(&subtitle)
        if let codecCtx {
            avcodec_close(codecCtx)
            avcodec_free_context(&self.codecCtx)
        }
        self.codecCtx = nil

        if formatCtx != nil {
            avformat_close_input(&formatCtx)
        }
        formatCtx = nil
        subtitleStreamIndex = -1
        parts.removeAll()
        startTime = 0
        endTime = 0
    }
}

/// Convenience factory to create and load an FFmpegSubtitle from a URL.
public extension FFmpegSubtitle {
    /// RE: FFmpegSubtitle_createWithURL at 0x101362AE4
    static func create(url: URL) async throws -> FFmpegSubtitle {
        let actor = FFmpegSubtitle()
        try await actor.loadFile(url: url)
        return actor
    }
}
