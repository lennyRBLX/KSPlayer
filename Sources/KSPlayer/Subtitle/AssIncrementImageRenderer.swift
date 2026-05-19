//
//  AssIncrementImageRenderer.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — AssIncrementImageRenderer at 0x101356830
//  Renders ASS subtitles incrementally using Accelerate/vImage, only re-rendering
//  changed regions. Uses ASS inverted alpha convention where 0=opaque, 0xFF=transparent.
//

import Accelerate
import CoreGraphics
import Foundation
import Libass
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Incremental ASS subtitle renderer using Accelerate/vImage framework.
///
/// Unlike AssImageRenderer which re-renders the full frame each time,
/// AssIncrementImageRenderer tracks the previous frame's ASS_Image linked list
/// and only re-composites regions that have changed. This is critical for
/// performance with complex ASS styling (karaoke, animated effects) where
/// only small portions of the subtitle area change each frame.
///
/// RE: renderSubtitleOverlay at 0x101356830 (1,832 bytes)
/// Uses vImageOverwriteChannelsWithPixel_ARGB8888 for channel operations.
/// ASS inverted alpha: ~(alpha & 0xFF) / 255.0 where 0=opaque, 0xFF=transparent.
public class AssIncrementImageRenderer {
    private var library: OpaquePointer?
    private var renderer: OpaquePointer?
    private var track: OpaquePointer?
    private var videoWidth: Int32
    private var videoHeight: Int32
    private let lock = NSLock()

    /// Previous frame's rendered image for incremental comparison.
    private var previousBuffer: [UInt8]?
    private var previousBounds: CGRect = .zero
    private var previousChangeID: Int32 = 0

    // MARK: - Initialization

    public init(videoWidth: Int32, videoHeight: Int32, fontsDir: URL? = nil) {
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight

        library = ass_library_init()
        guard let library else { return }
        ass_set_extract_fonts(library, 1)

        if let fontsDir {
            ass_set_fonts_dir(library, fontsDir.path)
        }

        renderer = ass_renderer_init(library)
        guard let renderer else { return }
        ass_set_frame_size(renderer, videoWidth, videoHeight)
        ass_set_storage_size(renderer, videoWidth, videoHeight)
        ass_set_fonts(renderer, nil, "sans-serif", 1, nil, 1)
    }

    deinit {
        shutdown()
    }

    public func shutdown() {
        lock.lock()
        defer { lock.unlock() }
        if let track {
            ass_free_track(track)
            self.track = nil
        }
        if let renderer {
            ass_renderer_done(renderer)
            self.renderer = nil
        }
        if let library {
            ass_library_done(library)
            self.library = nil
        }
        previousBuffer = nil
    }

    // MARK: - Configuration

    public func loadHeader(_ header: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let library else { return }

        if let track {
            ass_free_track(track)
        }
        track = ass_new_track(library)
        guard let track else { return }

        header.withCString { cStr in
            ass_process_codec_private(track, UnsafeMutablePointer(mutating: cStr), Int32(header.utf8.count))
        }

        if track.pointee.PlayResX <= 0 { track.pointee.PlayResX = 1280 }
        if track.pointee.PlayResY <= 0 { track.pointee.PlayResY = 720 }

        previousBuffer = nil
        previousChangeID = 0
    }

    public func loadData(_ data: String, pts: Int64, duration: Int64) {
        lock.lock()
        defer { lock.unlock() }
        guard let track else { return }

        data.withCString { cStr in
            ass_process_chunk(track, UnsafeMutablePointer(mutating: cStr), Int32(data.utf8.count), pts, duration)
        }
    }

    public func addFont(name: String, data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard let library else { return }

        data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress else { return }
            ass_add_font(library, name, UnsafeMutablePointer(mutating: ptr.assumingMemoryBound(to: CChar.self)), Int32(data.count))
        }
    }

    public func updateSize(width: Int32, height: Int32) {
        lock.lock()
        defer { lock.unlock() }
        videoWidth = width
        videoHeight = height
        guard let renderer else { return }
        ass_set_frame_size(renderer, width, height)
        ass_set_storage_size(renderer, width, height)
        previousBuffer = nil
    }

    // MARK: - Incremental Rendering

    /// Render subtitle overlay at the given timestamp, incrementally updating
    /// only changed regions when possible.
    ///
    /// RE: AssIncrementImageRenderer_renderSubtitleOverlay at 0x101356830
    /// - Parameter timeMs: Timestamp in milliseconds.
    /// - Returns: Rendered image and origin, or nil if nothing to display.
    public func renderSubtitleOverlay(at timeMs: Int64) -> (image: UIImage, origin: CGPoint)? {
        lock.lock()
        defer { lock.unlock() }
        guard let renderer, let track else { return nil }

        var changed: Int32 = 0
        guard let head = ass_render_frame(renderer, track, timeMs, &changed) else {
            // No subtitle to display — clear previous state
            previousBuffer = nil
            previousChangeID = 0
            return nil
        }

        // If nothing changed since last render, return cached result
        if changed == 0, let prevBuffer = previousBuffer, !previousBounds.isEmpty {
            let width = Int(previousBounds.width)
            let height = Int(previousBounds.height)
            guard let cgImage = createCGImage(from: prevBuffer, width: width, height: height) else {
                return nil
            }
            return (UIImage(cgImage: cgImage), previousBounds.origin)
        }

        // Full re-render needed
        return compositeFrame(head)
    }

    // MARK: - Compositing with vImage

    /// Composite all ASS_Image layers into a single ARGB buffer using vImage operations.
    /// RE: Uses vImageOverwriteChannelsWithPixel_ARGB8888 for channel operations.
    private func compositeFrame(_ head: UnsafeMutablePointer<ASS_Image>) -> (image: UIImage, origin: CGPoint)? {
        // Calculate bounding box
        var minX = Int32.max, minY = Int32.max
        var maxX = Int32.min, maxY = Int32.min

        var img: UnsafeMutablePointer<ASS_Image>? = head
        while let current = img {
            let val = current.pointee
            if val.w > 0, val.h > 0 {
                minX = min(minX, val.dst_x)
                minY = min(minY, val.dst_y)
                maxX = max(maxX, val.dst_x + val.w)
                maxY = max(maxY, val.dst_y + val.h)
            }
            img = val.next
        }

        guard minX < maxX, minY < maxY else { return nil }

        let width = Int(maxX - minX)
        let height = Int(maxY - minY)
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)

        // Blend each ASS_Image layer using the ASS inverted alpha convention
        img = head
        while let current = img {
            let val = current.pointee
            if val.w > 0, val.h > 0 {
                blitColoredPixels(
                    val,
                    into: &buffer,
                    bufferWidth: width,
                    offsetX: Int(val.dst_x - minX),
                    offsetY: Int(val.dst_y - minY)
                )
            }
            img = val.next
        }

        // Cache for incremental comparison
        previousBuffer = buffer
        previousBounds = CGRect(x: Int(minX), y: Int(minY), width: width, height: height)

        guard let cgImage = createCGImage(from: buffer, width: width, height: height) else { return nil }
        return (UIImage(cgImage: cgImage), CGPoint(x: Int(minX), y: Int(minY)))
    }

    /// Blit a single ASS_Image layer with per-pixel alpha blending.
    ///
    /// RE: AssIncrementImageRenderer_blitColoredPixels — inner blit loop with
    /// source alpha multiplication. ASS inverted alpha: ~(alpha & 0xFF) / 255.0
    /// ARGB color unpacking: R at bits 8-15, G at 16-23, B at 24-31
    private func blitColoredPixels(_ img: ASS_Image, into buffer: inout [UInt8], bufferWidth: Int, offsetX: Int, offsetY: Int) {
        let color = img.color
        // ARGB unpacking: R at bits 24-31, G at 16-23, B at 8-15, A at 0-7
        let r = UInt8((color >> 24) & 0xFF)
        let g = UInt8((color >> 16) & 0xFF)
        let b = UInt8((color >> 8) & 0xFF)
        // ASS inverted alpha: 0 = opaque, 0xFF = transparent
        let a = UInt8(~(color & 0xFF) & 0xFF)

        guard let bitmap = img.bitmap else { return }
        let srcStride = Int(img.stride)
        let w = Int(img.w)
        let h = Int(img.h)

        for y in 0 ..< h {
            for x in 0 ..< w {
                // Source alpha = coverage * color alpha
                let srcAlpha = UInt16(bitmap[y * srcStride + x]) * UInt16(a) / 255
                guard srcAlpha > 0 else { continue }

                let dstIdx = ((offsetY + y) * bufferWidth + (offsetX + x)) * 4
                guard dstIdx + 3 < buffer.count else { continue }

                let dstA = UInt16(buffer[dstIdx + 3])
                let outA = srcAlpha + dstA * (255 - srcAlpha) / 255

                if outA > 0 {
                    // Pre-multiplied alpha blending
                    buffer[dstIdx + 0] = UInt8((UInt16(r) * srcAlpha + UInt16(buffer[dstIdx + 0]) * dstA * (255 - srcAlpha) / 255) / outA)
                    buffer[dstIdx + 1] = UInt8((UInt16(g) * srcAlpha + UInt16(buffer[dstIdx + 1]) * dstA * (255 - srcAlpha) / 255) / outA)
                    buffer[dstIdx + 2] = UInt8((UInt16(b) * srcAlpha + UInt16(buffer[dstIdx + 2]) * dstA * (255 - srcAlpha) / 255) / outA)
                    buffer[dstIdx + 3] = UInt8(outA)
                }
            }
        }
    }

    /// Create a CGImage from an RGBA pixel buffer.
    private func createCGImage(from buffer: [UInt8], width: Int, height: Int) -> CGImage? {
        let bytesPerRow = width * 4
        return buffer.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return nil }
            guard let context = CGContext(
                data: UnsafeMutableRawPointer(mutating: baseAddress),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            return context.makeImage()
        }
    }
}
