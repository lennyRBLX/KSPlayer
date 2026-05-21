//
//  AssImageRenderer.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — alternative to NSAttributedString rendering
//  Uses libass C library to render ASS/SSA subtitles to bitmap images (CGImage).
//  Follows the same libass integration pattern as LibassSubtitleRenderer.
//

import CoreGraphics
import Foundation
import Libass
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
#if canImport(Metal)
import Metal
#endif

// MARK: - AssImageRenderer

/// Renders ASS/SSA subtitle text + style to CGImage or MTLTexture using the libass library.
/// Provides an alternative to NSAttributedString-based rendering for complex ASS styling
/// (blur, animations, vector drawings, etc.) that NSAttributedString cannot reproduce.
///
/// Usage:
/// ```
/// let renderer = AssImageRenderer(videoWidth: 1920, videoHeight: 1080)
/// renderer.loadHeader(assHeaderString)
/// if let result = renderer.renderToImage(text: dialogueLine, style: styleName, at: timeMs) {
///     // result.image is a UIImage, result.origin is the placement point
/// }
/// ```
public class AssImageRenderer {
    private var library: OpaquePointer?
    private var renderer: OpaquePointer?
    private var track: OpaquePointer?
    private var videoWidth: Int32
    private var videoHeight: Int32
    private let lock = NSLock()

    // MARK: - Initialization

    /// Create an AssImageRenderer for the given video dimensions.
    /// - Parameters:
    ///   - videoWidth: Width of the video frame in pixels.
    ///   - videoHeight: Height of the video frame in pixels.
    ///   - fontsDir: Optional directory for custom font lookup.
    public init(videoWidth: Int32, videoHeight: Int32, fontsDir: URL? = nil) {
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight

        library = ass_library_init()
        guard let library else { return }

        // Extract fonts embedded in MKV/ASS containers
        ass_set_extract_fonts(library, 1)

        if let fontsDir {
            ass_set_fonts_dir(library, fontsDir.path)
        }

        renderer = ass_renderer_init(library)
        guard let renderer else { return }

        ass_set_frame_size(renderer, videoWidth, videoHeight)
        ass_set_storage_size(renderer, videoWidth, videoHeight)
        // Use fontconfig for system font fallback (same as LibassSubtitleRenderer)
        ass_set_fonts(renderer, nil, "sans-serif", 1, nil, 1)
    }

    deinit {
        shutdown()
    }

    // MARK: - Lifecycle

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

    // MARK: - Configuration

    /// Load ASS header/style definitions (the `[Script Info]` + `[V4+ Styles]` sections).
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

        // Default PlayRes if not specified
        if track.pointee.PlayResX <= 0 {
            track.pointee.PlayResX = 1280
        }
        if track.pointee.PlayResY <= 0 {
            track.pointee.PlayResY = 720
        }
    }

    /// Add an embedded font (extracted from container) to the library.
    public func addFont(name: String, data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard let library else { return }

        data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress else { return }
            ass_add_font(library, name, UnsafeMutablePointer(mutating: ptr.assumingMemoryBound(to: CChar.self)), Int32(data.count))
        }
    }

    /// Update the rendering frame size (e.g., on video resize).
    public func updateSize(width: Int32, height: Int32) {
        lock.lock()
        defer { lock.unlock() }
        videoWidth = width
        videoHeight = height
        guard let renderer else { return }
        ass_set_frame_size(renderer, width, height)
        ass_set_storage_size(renderer, width, height)
    }

    // MARK: - Rendering to CGImage

    /// Render a subtitle dialogue line at a given timestamp and return a CGImage.
    /// - Parameters:
    ///   - text: The ASS dialogue text (may include inline override tags).
    ///   - pts: Presentation timestamp in milliseconds.
    ///   - duration: Duration of the subtitle event in milliseconds.
    /// - Returns: A tuple of (CGImage, origin) or nil if nothing was rendered.
    public func renderToImage(text: String, pts: Int64, duration: Int64) -> (image: CGImage, origin: CGPoint)? {
        lock.lock()
        defer { lock.unlock() }
        guard let renderer, let track else { return nil }

        // Add the dialogue chunk for rendering
        text.withCString { cStr in
            ass_process_chunk(track, UnsafeMutablePointer(mutating: cStr), Int32(text.utf8.count), pts, duration)
        }

        var changed: Int32 = 0
        guard let frame = ass_render_frame(renderer, track, pts, &changed) else {
            return nil
        }

        return compositeFrameToCGImage(frame)
    }

    /// Render the current track state at a timestamp (for pre-loaded tracks).
    /// - Parameter timeMs: Timestamp in milliseconds.
    /// - Returns: A tuple of (CGImage, origin) or nil if nothing was rendered.
    public func renderAtTime(_ timeMs: Int64) -> (image: CGImage, origin: CGPoint)? {
        lock.lock()
        defer { lock.unlock() }
        guard let renderer, let track else { return nil }

        var changed: Int32 = 0
        guard let frame = ass_render_frame(renderer, track, timeMs, &changed) else {
            return nil
        }

        return compositeFrameToCGImage(frame)
    }

    // MARK: - Rendering to UIImage (convenience)

    /// Convenience: render and return a UIImage instead of CGImage.
    public func renderToUIImage(text: String, pts: Int64, duration: Int64) -> (image: UIImage, origin: CGPoint)? {
        guard let result = renderToImage(text: text, pts: pts, duration: duration) else { return nil }
        return (UIImage(cgImage: result.image), result.origin)
    }

    // MARK: - Rendering to MTLTexture

    #if canImport(Metal)
    /// Render a subtitle to an MTLTexture for Metal-based compositing.
    /// - Parameters:
    ///   - text: The ASS dialogue text.
    ///   - pts: Presentation timestamp in milliseconds.
    ///   - duration: Duration in milliseconds.
    ///   - device: The Metal device to create the texture on.
    /// - Returns: A tuple of (MTLTexture, origin) or nil if nothing was rendered.
    public func renderToTexture(text: String, pts: Int64, duration: Int64, device: MTLDevice) -> (texture: MTLTexture, origin: CGPoint)? {
        guard let result = renderToImage(text: text, pts: pts, duration: duration) else { return nil }
        let cgImage = result.image
        let width = cgImage.width
        let height = cgImage.height

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        // Render CGImage into the texture's pixel data
        let bytesPerRow = width * 4
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixelData,
            bytesPerRow: bytesPerRow
        )

        return (texture, result.origin)
    }
    #endif

    // MARK: - Internal compositing

    /// Composite all ASS_Image layers into a single CGImage.
    /// RE: AssImageRenderer_renderSubtitleFrame @ 0x101474e8c calls
    /// ASSImage_linkedListToArray (0x1014734bc) once after
    /// `ass_render_frame` returns, then iterates the value-typed array.
    /// This Swift reconstruction follows the same shape via
    /// `ASSImage.linkedListToArray` / `ASSImage.boundingBox`.
    private func compositeFrameToCGImage(_ head: UnsafeMutablePointer<ASS_Image>) -> (image: CGImage, origin: CGPoint)? {
        let layers = ASSImage.linkedListToArray(head)
        guard let bounds = ASSImage.boundingBox(of: layers) else { return nil }

        let width = Int(bounds.width)
        let height = Int(bounds.height)
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)

        // Alpha-blend each ASS_Image layer into the buffer
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
        return (cgImage, bounds.origin)
    }

    /// Alpha-blend a single ASS_Image layer into the RGBA buffer.
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
