//
//  LibassSubtitleRenderer.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — libass_ass_set_extract_fonts confirmed at runtime
//  Renders ASS/SSA subtitles as images using libass C library with embedded font extraction.
//

import CoreGraphics
import Foundation
import Libass
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

public class LibassSubtitleRenderer {
    private var library: OpaquePointer?
    private var renderer: OpaquePointer?
    private var track: OpaquePointer?
    private var videoWidth: Int32 = 0
    private var videoHeight: Int32 = 0
    private let lock = NSLock()

    public init(videoWidth: Int32, videoHeight: Int32, fontsDir: URL? = nil) {
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight

        library = ass_library_init()
        guard let library else { return }

        // RE-confirmed: Forward calls ass_set_extract_fonts(1) to extract fonts embedded in MKV/ASS
        ass_set_extract_fonts(library, 1)

        if let fontsDir {
            ass_set_fonts_dir(library, fontsDir.path)
        }

        renderer = ass_renderer_init(library)
        guard let renderer else { return }

        ass_set_frame_size(renderer, videoWidth, videoHeight)
        ass_set_storage_size(renderer, videoWidth, videoHeight)
        // Use fontconfig for system font fallback
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
    }

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

        if track.pointee.PlayResX <= 0 {
            track.pointee.PlayResX = 1280
        }
        if track.pointee.PlayResY <= 0 {
            track.pointee.PlayResY = 720
        }
    }

    public func loadData(_ data: String, pts: Int64, duration: Int64) {
        lock.lock()
        defer { lock.unlock() }
        guard let track else { return }

        data.withCString { cStr in
            ass_process_chunk(track, UnsafeMutablePointer(mutating: cStr), Int32(data.utf8.count), pts, duration)
        }
    }

    /// Add an embedded font (extracted from container) to the library
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
    }

    /// Render subtitle at given timestamp (milliseconds) and return as UIImage
    public func render(at timeMs: Int64) -> (image: UIImage, origin: CGPoint)? {
        lock.lock()
        defer { lock.unlock() }
        guard let renderer, let track else { return nil }

        var changed: Int32 = 0
        guard let frame = ass_render_frame(renderer, track, timeMs, &changed) else {
            return nil
        }

        return compositeFrame(frame)
    }

    private func compositeFrame(_ head: UnsafeMutablePointer<ASS_Image>) -> (image: UIImage, origin: CGPoint)? {
        // RE: ASSImage_linkedListToArray @ 0x1014734bc — snapshot the
        // libass linked list once, then iterate the value-typed array.
        let layers = ASSImage.linkedListToArray(head)
        guard let bounds = ASSImage.boundingBox(of: layers) else { return nil }

        let width = Int(bounds.width)
        let height = Int(bounds.height)
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)

        for layer in layers where layer.width > 0 && layer.height > 0 {
            blendImage(
                layer,
                into: &buffer,
                bufferWidth: width,
                offsetX: Int(layer.dstX - Int32(bounds.minX)),
                offsetY: Int(layer.dstY - Int32(bounds.minY))
            )
        }

        guard let cgImage = createCGImage(from: buffer, width: width, height: height) else { return nil }
        return (UIImage(cgImage: cgImage), bounds.origin)
    }

    private func blendImage(_ layer: ASSImage.Layer, into buffer: inout [UInt8], bufferWidth: Int, offsetX: Int, offsetY: Int) {
        let color = layer.color
        let r = UInt8((color >> 24) & 0xFF)
        let g = UInt8((color >> 16) & 0xFF)
        let b = UInt8((color >> 8) & 0xFF)
        let a = layer.opacity

        guard let bitmap = layer.bitmap else { return }
        let stride = Int(layer.stride)
        let w = Int(layer.width)
        let h = Int(layer.height)

        for y in 0 ..< h {
            for x in 0 ..< w {
                let srcAlpha = UInt16(bitmap[y * stride + x]) * UInt16(a) / 255
                guard srcAlpha > 0 else { continue }

                let dstIdx = ((offsetY + y) * bufferWidth + (offsetX + x)) * 4
                let dstA = UInt16(buffer[dstIdx + 3])
                let outA = srcAlpha + dstA * (255 - srcAlpha) / 255

                if outA > 0 {
                    buffer[dstIdx + 0] = UInt8((UInt16(r) * srcAlpha + UInt16(buffer[dstIdx + 0]) * dstA * (255 - srcAlpha) / 255) / outA)
                    buffer[dstIdx + 1] = UInt8((UInt16(g) * srcAlpha + UInt16(buffer[dstIdx + 1]) * dstA * (255 - srcAlpha) / 255) / outA)
                    buffer[dstIdx + 2] = UInt8((UInt16(b) * srcAlpha + UInt16(buffer[dstIdx + 2]) * dstA * (255 - srcAlpha) / 255) / outA)
                    buffer[dstIdx + 3] = UInt8(outA)
                }
            }
        }
    }

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
