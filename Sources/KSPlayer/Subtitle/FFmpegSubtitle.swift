//
//  FFmpegSubtitle.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — FFmpegSubtitle at 0x10147f0dc (createWithURL)
//  Swift actor providing thread-safe external subtitle file parsing via FFmpeg.
//  Opens a separate AVFormatContext (wrapped in FormatContext) for the subtitle
//  file, finds the subtitle stream, demuxes via av_read_frame, and DELEGATES the
//  per-packet decode to an embedded SubtitleDecode instance (the raw
//  avcodec_decode_subtitle2 call lives inside SubtitleDecode's FFmpeg driver, not
//  here). Image (ASS/bitmap) rendering is delegated to AssIncrementImageRenderer.
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
/// Opens a separate `AVFormatContext` (via the `FormatContext` wrapper) for an
/// external subtitle file (independent of the main media context), finds the
/// subtitle stream, and demuxes packets, handing each one to an embedded
/// `SubtitleDecode` for decode → `SubtitleFrame` conversion. Actor isolation
/// serializes FFmpeg operations to prevent data races on seek / track switch.
///
/// RE: 8-field actor ($defaultActor, formatContext, decode, subtitleStreamIndex,
/// preTime, startTime, endTime, parts) with DefaultActorStorage.
/// Conforms to KSSubtitleProtocol.
public actor FFmpegSubtitle: KSSubtitleProtocol {
    /// RE field #2: separate context for the subtitle file. KSPlayer wrapper class;
    /// its inner `formatCtx` is the raw `UnsafeMutablePointer<AVFormatContext>`.
    private var formatContext: FormatContext?
    /// RE field #3: embedded decoder instance. All FFmpeg decode + rect→part
    /// conversion is delegated here (no inline avcodec_decode_subtitle2 in the actor).
    private var decode: SubtitleDecode?
    /// RE field #4: selected stream index inside the subtitle file.
    private var subtitleStreamIndex: Int32 = -1
    /// RE field #5: pre-buffer time for readahead.
    private var preTime: Double = 0
    /// RE field #6: stream start offset.
    private var startTime: Double = 0
    /// RE field #7: stream end time.
    private var endTime: Double = 0
    /// RE field #8: decoded subtitle parts cache.
    private var parts: [SubtitlePart] = []

    public init() {}

    // MARK: - KSSubtitleProtocol

    /// Search for subtitle parts matching the given time.
    ///
    /// RE: KSSubtitleProtocol requires only `search(for:)`. For external subtitle
    /// files the `parts` array is pre-parsed and start-sorted by `loadFile(url:)`,
    /// so this performs a synchronous in-order scan over a lock-protected snapshot
    /// of the finalized cache (writes happen only during the actor-isolated load,
    /// which completes before any search is issued).
    nonisolated public func search(for time: TimeInterval) -> [SubtitlePart] {
        var result = [SubtitlePart]()
        for part in _partsStorage.value {
            if part.start <= time, part.end >= time {
                result.append(part)
            } else if part.start > time {
                break
            }
        }
        return result
    }

    /// Box backing the parts cache for the nonisolated `search(for:)` path. The
    /// actor-isolated `loadFile`/`shutdown` write into it; `search` reads it.
    private let _partsStorage = PartsBox()

    /// Async search that respects actor isolation (used internally by the engine).
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

    /// Create and load an FFmpegSubtitle from a URL.
    ///
    /// RE: FFmpegSubtitle_createWithURL @0x10147f0dc (184B). The old IDA pair
    /// createWithURL@0x101362AE4 / init@0x101362D4C collapse to this single thin
    /// create+load entry: allocate the actor, install the KSSubtitleProtocol
    /// conformance descriptor, then drive the load (FUN_10147f344). The heavy
    /// demux/decode lives in the delegated SubtitleDecode, not here.
    public static func createWithURL(_ url: URL) async throws -> FFmpegSubtitle {
        let actor = FFmpegSubtitle()
        try await actor.loadFile(url: url)
        return actor
    }

    /// Open and parse an external subtitle file via FFmpeg, delegating decode to
    /// an embedded `SubtitleDecode`.
    /// - Parameter url: URL of the subtitle file (local or remote).
    /// - Returns: The parsed subtitle parts array.
    @discardableResult
    public func loadFile(url: URL) throws -> [SubtitlePart] {
        shutdown()

        var fmtCtx: UnsafeMutablePointer<AVFormatContext>?
        let path = FormatContext.getOutputFormatName(for: url)

        let ret = avformat_open_input(&fmtCtx, path, nil, nil)
        guard ret >= 0, let fmtCtx else {
            throw NSError(errorCode: .subtitleFormatUnSupport)
        }
        // Wrap the raw context in the FormatContext wrapper (field #2).
        let wrapper = FormatContext()
        wrapper.formatCtx = fmtCtx
        formatContext = wrapper

        guard avformat_find_stream_info(fmtCtx, nil) >= 0 else {
            shutdown()
            throw NSError(errorCode: .subtitleFormatUnSupport)
        }

        // Find the first subtitle stream (codec_type == AVMEDIA_TYPE_SUBTITLE / 3).
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

        // Build an FFmpegAssetTrack for the subtitle stream and hand it to the
        // embedded SubtitleDecode. SubtitleDecode owns codec-context creation,
        // ASS header parsing, libass setup, and avcodec_decode_subtitle2.
        guard let assetTrack = FFmpegAssetTrack(stream: stream) else {
            shutdown()
            throw NSError(errorCode: .codecSubtitleSendPacket)
        }
        let decoder = SubtitleDecode(assetTrack: assetTrack, options: KSOptions())
        decode = decoder

        // Stream start offset (field #6).
        startTime = assetTrack.startTime.seconds

        // Demux every packet on the subtitle stream and delegate decode. The
        // SubtitleDecode completion (invoked synchronously per packet) yields
        // SubtitleFrame objects; we collect their SubtitlePart payloads.
        parts.removeAll()
        var packetRef = av_packet_alloc()
        defer { av_packet_free(&packetRef) }
        guard let packetRef else {
            shutdown()
            throw NSError(errorCode: .codecSubtitleSendPacket)
        }

        var collected = [SubtitlePart]()
        while av_read_frame(fmtCtx, packetRef) >= 0 {
            defer { av_packet_unref(packetRef) }

            guard packetRef.pointee.stream_index == subtitleStreamIndex else {
                continue
            }

            // Wrap the demuxed AVPacket in a KSPlayer Packet so SubtitleDecode can
            // consume it through the DecodeProtocol path. Packet() already allocates
            // its own corePacket; ref the demuxed data into it.
            let packet = Packet()
            if let corePacket = packet.corePacket {
                av_packet_ref(corePacket, packetRef)
            }
            packet.assetTrack = assetTrack

            // decodeFrame calls the handler synchronously on this actor's executor;
            // collect into a local to avoid actor re-entrancy on `parts`.
            decoder.decodeFrame(from: packet) { result in
                guard case let .success(frame) = result else { return }
                if let subtitleFrame = frame as? SubtitleFrame {
                    collected.append(subtitleFrame.part)
                }
            }
        }

        // Finalize: sort by start time and compute end time.
        collected.sort { $0.start < $1.start }
        parts = collected
        endTime = parts.last?.end ?? 0
        _partsStorage.value = parts

        return parts
    }

    /// Get all parsed parts.
    public func getParts() -> [SubtitlePart] {
        parts
    }

    // MARK: - Text Extraction

    /// Extract a representative text payload and end time from the decoded parts.
    ///
    /// RE: FFmpegSubtitle_extractTextFromRects @0x10147f1b4 (400B). Walks the
    /// decoded parts array (stride 0x60 == SubtitlePart), bridging each rect's text
    /// payload. Produces the leading attributed string (written to +0x90 in the
    /// binary) and computes the end time (+0x98): the last rect's end field, unless
    /// it is infinity, in which case it falls back to that rect's start field.
    /// - Returns: A tuple of the first attributed text found (if any) and the
    ///   computed end time, mirroring the binary's two-slot result.
    @discardableResult
    func extractTextFromRects() -> (text: NSAttributedString?, end: Double) {
        guard !parts.isEmpty else {
            // Binary: writes 0 to both +0x90 and +0x98 on the empty path.
            return (nil, 0)
        }

        var leadingText: NSAttributedString?
        for part in parts {
            // Binary bridges the rect's text C-string; here the part already holds
            // the bridged attributed string. Capture the first non-nil one.
            if leadingText == nil, let text = part.text {
                leadingText = text
                break
            }
        }

        // End time: last rect's end unless infinite, else fall back to its start.
        let last = parts[parts.count - 1]
        let end = last.end.isFinite ? last.end : last.start

        return (leadingText, end)
    }

    // MARK: - Image Rendering (ASS / bitmap)

    /// Render the current subtitle frame as an image via the ASS image renderer.
    ///
    /// RE: FFmpegSubtitle_renderImageViaAss @0x1014802b4 (144B). Reads the pending
    /// ASS frame data, obtains (get-or-create) the AssIncrementImageRenderer from
    /// the embedded SubtitleDecode, renders the overlay for the given time, then
    /// hands off to the async continuation (binary: swift_task_switch →
    /// renderImageContinuation). Kept async to preserve the binary's task-switch
    /// boundary.
    /// - Parameter timeMs: Presentation time in milliseconds for the overlay.
    /// - Returns: The rendered image and its origin, or nil if nothing to draw.
    func renderImageViaAss(at timeMs: Int64) async -> (image: UIImage, origin: CGPoint)? {
        // get-or-create the renderer (binary: AssIncrementImageRenderer_getOrCreateRenderer)
        guard let renderer = decode?.assImageRenderer else {
            return nil
        }
        // render the frame (binary: AssImageRenderer_renderSubtitleFrame).
        // Cross-actor hop: `renderer` is a separate `AssIncrementImageRenderer`
        // actor, so its isolated `renderSubtitleOverlay(at:)` must be awaited.
        let rendered = await renderer.renderSubtitleOverlay(at: timeMs)
        // task-switch boundary → continuation half of the pipeline.
        await renderImageContinuation()
        return rendered
    }

    /// Async continuation of the render-image pipeline.
    ///
    /// RE: FFmpegSubtitle_renderImageContinuation @0x10142056c. Releases the frame
    /// captured by renderImageViaAss and resumes the suspended task (binary:
    /// swift_release of the captured frame at +0x28, then indirect resume). In
    /// Swift the release is automatic; this is the explicit continuation point.
    private func renderImageContinuation() async {
        // The captured ASS frame is released automatically by ARC at this suspension
        // point; the continuation simply resumes the caller's task.
        await Task.yield()
    }

    /// Cleanup path of the render-image pipeline.
    ///
    /// RE: FFmpegSubtitle_renderImageCleanup @0x1013fccd8. Tears down the per-render
    /// async frame scratch (binary: swift_task_alloc of a cleanup record wired to
    /// FUN_1004762a4, then FUN_1013fc6d8). Here it shuts down the renderer's
    /// incremental state so the next frame starts clean.
    ///
    /// `async` because the embedded decoder's image renderer is a separate
    /// `AssIncrementImageRenderer` actor; its isolated `shutdown()` must be
    /// awaited across the actor boundary (a synchronous cross-actor isolated call
    /// is not expressible). The binary's swift_task_alloc cleanup record already
    /// stages this teardown on the task, so the suspension point is faithful.
    func renderImageCleanup() async {
        // Release the incremental ASS render scratch held by the embedded decoder's
        // image renderer. Full teardown happens in shutdown(); this is the per-frame
        // cleanup counterpart to renderImageViaAss/renderImageContinuation.
        await decode?.assImageRenderer?.shutdown()
    }

    // MARK: - Lifecycle

    /// Release all FFmpeg resources.
    ///
    /// RE: FFmpegSubtitle_dealloc @0x10147fa1c. The binary stages the teardown
    /// across a task-switch (swift_task_switch → FUN_10147fa84) that drains the
    /// embedded decoder and closes the format context. With the corrected field
    /// layout (FormatContext wrapper + delegated SubtitleDecode), cleanup shuts the
    /// decoder down and closes the wrapped context. The dealloc_thunk @0x1007d0a48
    /// is a compiler-generated ObjC thunk and needs no Swift reconstruction.
    public func shutdown() {
        decode?.shutdown()
        decode = nil

        if let wrapper = formatContext, wrapper.formatCtx != nil {
            avformat_close_input(&wrapper.formatCtx)
        }
        formatContext = nil

        subtitleStreamIndex = -1
        parts.removeAll()
        _partsStorage.value = []
        preTime = 0
        startTime = 0
        endTime = 0
    }
}

/// Thread-safe box backing the parts cache for the nonisolated `search(for:)` path.
/// Writes occur only during the actor-isolated load; reads occur only after load
/// completes (the documented invariant in `search(for:)`).
private final class PartsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: [SubtitlePart] = []
    var value: [SubtitlePart] {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
}
