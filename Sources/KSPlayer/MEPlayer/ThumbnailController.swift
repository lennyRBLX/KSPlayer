//
//  ThumbnailController.swift
//
//
//  Created by kintan on 12/27/23.
//

import AVFoundation
import Foundation
import Libavcodec
import Libavformat
#if canImport(UIKit)
import UIKit
#endif
/// ⚑ s107 RESHAPE. This struct had two stored properties and an implicit init. The binary's
/// field descriptor @0x103cbd268 declares **three**, in this order and all `let`:
/// `jpegData`, `_image`, `time`. `image` is not stored at all — it is COMPUTED.
///
/// The layout is read from the accessors, and the pieces corroborate each other:
///   · `jpegData.getter` @0x101a6c318 (11 instr) copies words 0–1 and returns them, doing no
///     work — a stored property, not something derived from an image.
///   · `image.getter` @0x101a6c344 opens `cbz x2` and returns x2 unchanged when non-nil, so
///     word 2 is a stored OPTIONAL image; only on nil does it consult `jpegData`.
///   · `time.getter` is **0x10000e52c**, the image's canonical ICF-folded empty body — the
///     identity getter of a `Double` that arrives and leaves in d0.
///
/// ⚑ The nil encoding is cross-checked, not assumed. `init(image:time:)` @0x101a6c308 sets the
///   `jpegData` slot to `(0, 0xF000000000000000)`, and `image.getter`'s fallback tests
///   `lsr x8, x20, #60` / `cmp #0xe` / `b.ls` — i.e. "top nibble > 0xe". The constant the init
///   writes is exactly the value that test rejects, so the two independently agree that this is
///   `Data?.none`.
public struct FFThumbnail: Sendable {
    public let jpegData: Data?
    /// ⚑ Named `_image` by the field record; it has no getter symbol and no property descriptor,
    ///   unlike its three siblings, which is what makes it private rather than a taste call.
    private let _image: UIImage?
    public let time: TimeInterval

    /// ⚑[tool=export_trie_oracle ref=KSPlayer.FFThumbnail.image.getter:0x101a6c344 result=54-instr]
    /// The stored image when present, else decoded from `jpegData`:
    /// ⚑[tool=decode_objc_selector ref=0x10440b958 result='initWithData:']
    /// ⚑[tool=decode_objc_selector ref=0x10440b838 result='init']
    /// Both nil paths — no data, and `initWithData:` returning nil (`cbnz x22`) — fall to the
    /// bare `UIImage()`, which is why this cannot be spelled with a single `??`.
    public var image: UIImage {
        if let _image {
            return _image
        }
        guard let jpegData, let decoded = UIImage(data: jpegData) else {
            return UIImage()
        }
        return decoded
    }

    /// ⚑ @0x101a6c308, four instructions: `mov x2, x0` (the argument becomes `_image`), then the
    ///   `jpegData` slot is set to the `Data?` nil pair. `time` is never touched — it arrives in
    ///   d0 and is returned in d0.
    public init(image: UIImage, time: TimeInterval) {
        jpegData = nil
        _image = image
        self.time = time
    }

    /// ⚑ @0x101a6c300, TWO instructions: `mov x2, #0` and `ret`. Only `_image` is written; the
    ///   incoming `jpegData` and `time` already sit in the registers the result is returned in.
    ///   ⚑ The parameter is `Data`, NOT `Data?` — the mangled name is `…8jpegData4timeAC10Foundation0D0V_Sdt…`
    ///     with no `Sg` on the first argument, even though the stored property is optional.
    public init(jpegData: Data, time: TimeInterval) {
        self.jpegData = jpegData
        _image = nil
        self.time = time
    }
}

public protocol ThumbnailControllerDelegate: AnyObject {
    func didUpdate(thumbnails: [FFThumbnail], forFile file: URL, withProgress: Int)
}

public class ThumbnailController {
    public weak var delegate: ThumbnailControllerDelegate?
    private let thumbnailCount: Int

    /// Binary: vtable slot 0 @0x101a6c49c — ALLOCATING_INIT_INLINED (18 instr). The initializing body is
    /// inlined into the allocating entry, so there is no separate inner body and the whole layout reads
    /// straight off this one function. Everything below is disasm + decompile, in agreement:
    /// ⚑[tool=init_thunk_probe.py ref=ThumbnailController.init:0x101a6c49c result=CONFIRMED]
    ///
    /// `mov w1,#0x28` / `mov w2,#0x7` → `_swift_allocObject(size 0x28 = 40, alignMask 7)`. Unlike the
    /// resilient-layout case, that size is a CONSTANT in the binary, so it pins the field layout exactly:
    /// 40 = 16 header + 16 + 8, and both members are accounted for with nothing left over —
    ///   · `delegate` occupies self+0x10..0x1f as a weak CLASS EXISTENTIAL (two words): `str xzr,[x0,#0x18]`
    ///     zeroes the witness-table word and `_swift_unknownObjectWeakInit(self+0x10, 0)` @0x10345d174
    ///     zeroes the object word. The implicit `nil` IS that weakInit — there is no source initializer to
    ///     recover. `unknownObject` (rather than the native-only entry) means the referent may be an
    ///     Objective-C object, which independently corroborates the class-bound `: AnyObject` on the
    ///     protocol above — a non-class-bound protocol could not be held `weak` at all.
    ///   · `thumbnailCount` is the single `Int` at self+0x20 (`str x19,[x20,#0x20]`, a full 64-bit store of
    ///     the saved x0; `dump_binary_field_types.py` independently types it `Swift.Int`).
    ///
    /// ARITY 1: x0 is the only argument register read — x1..x7 are untouched. That refutes a second
    /// parameter AND a second DEFAULTED one, since a default-argument generator runs at the CALL site and
    /// its value would still arrive in x1. NON-THROWING: no swifterror (x21) round-trip and no error path.
    ///
    /// ⚑ the `= 100` default is NEITHER confirmed NOR refuted here, and is retained from upstream rather
    /// than recovered: the constant is materialized by a default-argument generator at the call site, and
    /// `get_xrefs_to 0x101a6c49c` returns DATA references only (0x1039f06a4, 0x1044eb718, 0x10506e399) —
    /// there is no in-binary call site to read a literal 100 out of, and an uncalled generator is
    /// dead-stripped under -O WMO. The label `thumbnailCount:` is likewise upstream, not recovered: this
    /// init contains no logging, so it materializes no `#function` literal to read a signature from.
    /// ⚑ No dependency on the sibling types (ThumbnailQueue / ThumbnailSession) — this init
    /// allocates nothing and calls nothing but `_swift_allocObject` and `_swift_unknownObjectWeakInit`.
    /// Checked deliberately: standing up a type that has no source declaration would be a different and
    /// much larger unit than reconstructing an init.
    public init(thumbnailCount: Int = 100) {
        self.thumbnailCount = thumbnailCount
    }

    public func generateThumbnail(for url: URL, thumbWidth: Int32 = 240) async throws -> [FFThumbnail] {
        let count = thumbnailCount
        return try await Self.peeksTask(url: url, thumbWidth: thumbWidth, count: count, owner: self)
    }

    private static func peeksTask(url: URL, thumbWidth: Int32, count: Int, owner: ThumbnailController) async throws -> [FFThumbnail] {
        nonisolated(unsafe) let strongOwner = owner
        let progress: @Sendable ([FFThumbnail], URL, Int) -> Void = { thumbs, fileURL, index in
            Task { @MainActor in
                strongOwner.delegate?.didUpdate(thumbnails: thumbs, forFile: fileURL, withProgress: index)
            }
        }
        return try await Task.detached {
            try Self.getPeeks(for: url, thumbWidth: thumbWidth, thumbnailCount: count, progress: progress)
        }.value
    }

    private static func getPeeks(for url: URL, thumbWidth: Int32 = 240, thumbnailCount: Int, progress: @Sendable ([FFThumbnail], URL, Int) -> Void) throws -> [FFThumbnail] {
        let urlString: String
        if url.isFileURL {
            urlString = url.path
        } else {
            urlString = url.absoluteString
        }
        var thumbnails = [FFThumbnail]()
        var formatCtx = avformat_alloc_context()
        defer {
            avformat_close_input(&formatCtx)
        }
        var result = avformat_open_input(&formatCtx, urlString, nil, nil)
        guard result == 0, let formatCtx else {
            // ⚑[tool=ffmpeg_name_oracle ref=avformat_open_input:0x1030e5dac result=CONFIRMED]
            // ⚑ code is the LIVE open-input return; message is the 25-byte literal at
            //   0x103d34f00 = `formatOpenInput`'s raw value. In the binary this throw is factored out
            //   of the thumbnail bodies into the shared helper 0x101a308c4-0x101a31310.
            throw KSPlayerError(code: result, description: KSPlayerErrorCode.formatOpenInput.rawValue)
        }
        result = avformat_find_stream_info(formatCtx, nil)
        guard result == 0 else {
            throw KSPlayerError(code: result, description: KSPlayerErrorCode.formatFindStreamInfo.rawValue)
        }
        var videoStreamIndex = -1
        for i in 0 ..< Int32(formatCtx.pointee.nb_streams) {
            if formatCtx.pointee.streams[Int(i)]?.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_VIDEO {
                videoStreamIndex = Int(i)
                break
            }
        }
        guard videoStreamIndex >= 0, let videoStream = formatCtx.pointee.streams[videoStreamIndex] else {
            throw KSPlayerError(code: 0, description: "No video stream")
        }

        let videoAvgFrameRate = videoStream.pointee.avg_frame_rate
        if videoAvgFrameRate.den == 0 || av_q2d(videoAvgFrameRate) == 0 {
            throw KSPlayerError(code: 0, description: "Avg frame rate = 0, ignore")
        }
        var codecContext = try videoStream.pointee.codecpar.pointee.createContext(options: nil)
        defer {
            var codecContext: UnsafeMutablePointer<AVCodecContext>? = codecContext
            avcodec_free_context(&codecContext)
        }
        let thumbHeight = thumbWidth * codecContext.pointee.height / codecContext.pointee.width
        let reScale = VideoSwresample(dstWidth: thumbWidth, dstHeight: thumbHeight, isDovi: false)
//        let duration = formatCtx.pointee.duration
        // 因为是针对视频流来进行seek。所以不能直接取formatCtx的duration
        let duration = av_rescale_q(formatCtx.pointee.duration,
                                    AVRational(num: 1, den: AV_TIME_BASE), videoStream.pointee.time_base)
        let interval = duration / Int64(thumbnailCount)
        var packet = AVPacket()
        let timeBase = Timebase(videoStream.pointee.time_base)
        var frame = av_frame_alloc()
        defer {
            av_frame_free(&frame)
        }
        guard let frame else {
            // ⚑[tool=ffmpeg_name_oracle ref=av_frame_alloc:0x103240100 result=CONFIRMED]
            throw KSPlayerError(code: 0, description: "can not av_frame_alloc")
        }
        for i in 0 ..< thumbnailCount {
            let seek_pos = interval * Int64(i) + videoStream.pointee.start_time
            avcodec_flush_buffers(codecContext)
            result = av_seek_frame(formatCtx, Int32(videoStreamIndex), seek_pos, AVSEEK_FLAG_BACKWARD)
            guard result == 0 else {
                return thumbnails
            }
            avcodec_flush_buffers(codecContext)
            while av_read_frame(formatCtx, &packet) >= 0 {
                if packet.stream_index == Int32(videoStreamIndex) {
                    if avcodec_send_packet(codecContext, &packet) < 0 {
                        break
                    }
                    let ret = avcodec_receive_frame(codecContext, frame)
                    if ret < 0 {
                        if ret == -EAGAIN {
                            continue
                        } else {
                            break
                        }
                    }
                    let image = (try? reScale.transfer(frame: frame.pointee))?.cgImage().map {
                        UIImage(cgImage: $0)
                    }
                    let currentTimeStamp = frame.pointee.best_effort_timestamp
                    if let image {
                        let thumbnail = FFThumbnail(image: image, time: timeBase.cmtime(for: currentTimeStamp).seconds)
                        thumbnails.append(thumbnail)
                        progress(thumbnails, url, i)
                    }
                    break
                }
            }
        }
        av_packet_unref(&packet)
        reScale.shutdown()
        return thumbnails
    }
}

/// Forward's field record and initializer put these fields at +0x10 through +0x48.
/// The other queue methods remain separate reconstruction units.
public class ThumbnailQueue {
    private var pendingIndices: [Int]
    private var generatedSet: Set<Int> = []
    private var skippedSet: Set<Int> = []
    private let lock = NSLock()
    public let id: String
    public let count: Int
    public let duration: Double

    public init(id: String, count: Int, duration: Double) {
        self.id = id
        self.count = max(count, 1)
        self.duration = duration
        pendingIndices = Array(0 ..< self.count)
    }

    public func clear() {
        lock.lock()
        pendingIndices = []
        lock.unlock()
    }

    public func markGenerated(_ index: Int) {
        lock.lock()
        generatedSet.insert(index)
        lock.unlock()
    }

    public func isGenerated(_ index: Int) -> Bool {
        lock.lock()
        let result = generatedSet.contains(index)
        lock.unlock()
        return result
    }

    public func isSkipped(_ index: Int) -> Bool {
        lock.lock()
        let result = skippedSet.contains(index)
        lock.unlock()
        return result
    }

    public func putBack(_ index: Int) {
        lock.lock()
        if !generatedSet.contains(index) {
            skippedSet.insert(index)
        }
        lock.unlock()
    }

    public func next() -> Int? {
        lock.lock()
        let result: Int?
        if pendingIndices.isEmpty {
            result = nil
        } else {
            result = pendingIndices.removeFirst()
        }
        lock.unlock()
        return result
    }

    public func skipAllPending() {
        lock.lock()
        for index in pendingIndices {
            skippedSet.insert(index)
        }
        pendingIndices = []
        lock.unlock()
    }

    public func retrySkipped() {
        lock.lock()
        for index in skippedSet {
            if !generatedSet.contains(index) && !pendingIndices.contains(index) {
                pendingIndices.append(index)
            }
        }
        skippedSet = []
        lock.unlock()
    }

    public func reset() {
        lock.lock()
        pendingIndices = Array(0 ..< count)
        generatedSet = []
        lock.unlock()
    }

    public func restoreCached(_ cached: Set<Int>) {
        lock.lock()
        generatedSet.formUnion(cached)
        pendingIndices.removeAll { cached.contains($0) }
        lock.unlock()
    }

    public func restoreCached(where predicate: (Int) -> Bool) {
        lock.lock()
        for index in 0 ..< count {
            if predicate(index) {
                generatedSet.insert(index)
            }
        }
        pendingIndices.removeAll { generatedSet.contains($0) }
        lock.unlock()
    }

    public func seek(toIndex index: Int) {
        lock.lock()
        guard index >= 0, index < count else {
            lock.unlock()
            return
        }

        do {
            var after: [Int] = []
            var before: [Int] = []
            var found = false
            pendingIndices.forEach { pending in
                if pending == index {
                    found = true
                } else if index < pending {
                    after.append(pending)
                } else {
                    before.append(pending)
                }
            }
            after.sort()
            before.sort(by: >)

            var reordered: [Int] = []
            if found {
                reordered.append(index)
            }
            reordered.append(contentsOf: after)
            reordered.append(contentsOf: before)
            before = []
            after = []
            pendingIndices = reordered
        }
        lock.unlock()
    }

    public func seek(toTime time: Double) {
        guard duration > 0 else { return }
        let clampedTime = max(0, min(time, duration))
        let scaledIndex = Int(clampedTime / duration * Double(count))
        let index = min(count - 1, scaledIndex)
        seek(toIndex: index)
    }

    public func index(forTime time: Double) -> Int {
        guard duration > 0 else { return 0 }
        let clampedTime = max(0, min(time, duration))
        let scaledIndex = Int(clampedTime / duration * Double(count))
        return min(count - 1, scaledIndex)
    }

    public func isGenerated(atTime time: Double) -> Bool {
        guard duration > 0 else { return false }
        let clampedTime = max(0, min(time, duration))
        let scaledIndex = Int(clampedTime / duration * Double(count))
        let index = min(count - 1, scaledIndex)
        lock.lock()
        let result = generatedSet.contains(index)
        lock.unlock()
        return result
    }
}
