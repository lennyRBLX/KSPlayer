//
//  PointerImagePipeline.swift
//  KSPlayer
//
//  RE source: v1.3.15 — .reversal/DisplayMetal.md § PointerImagePipeline
//  Class metadata accessor (CMa): 0x101368ee4 (body 101368ee4–101369213)
//  Field descriptor / reflection record: 0x10333cb80
//  ObjC class: _TtC8KSPlayer20PointerImagePipeline
//
//  Genuine PointerImagePipeline accessor set (small-offset fields +0x10..+0x38):
//    getBufferPointers_getter  @ 0x100122E70 (76 B)
//    getHeights_getter         @ 0x10049975C (64 B)
//    getPixelFormats_setter    @ 0x100122EBC (80 B)
//    getSizeProperty           @ 0x100425388 (48 B)
//    setSizeProperty           @ 0x10146FAE8 (64 B)
//
//  NOTE: The following Ghidra symbols are MIS-ATTRIBUTED carryover from IDA
//  and actually belong to KSPlayer.PixelBuffer (resolved via field-shape analysis):
//    createTexturesFromBuffers @ 0x10146F32C → PixelBuffer.textures()
//    processWith...            @ 0x10146F56C → PixelBuffer.cgImage()
//    deinit                    @ 0x10146F9F8 → PixelBuffer.deinit
//
//  ImagePipelineType protocol descriptor @ 0x1033C3270 (data segment).
//  Mangled: $s8KSPlayer17ImagePipelineTypeP @ 0x103711592
//
//  Raw pixel buffer for video frame processing and subtitle compositing.
//  Used by AssImageRenderer (libass subtitle render target) and video frame processor.
//

#if canImport(Metal)
import CoreGraphics
import Metal
import Foundation

// MARK: - ImagePipelineType Protocol

/// RE: protocol descriptor 0x1033C3270, mangled $s8KSPlayer17ImagePipelineTypeP (1.3.15)
///
/// Abstraction for raw pixel buffer pipelines used by the video frame processor
/// and subtitle renderer (AssImageRenderer). Consumers use this protocol to
/// obtain CGImage or MTLTexture representations from a raw pixel buffer without
/// coupling to the concrete PointerImagePipeline class.
public protocol ImagePipelineType {
    /// Raw RGBA pixel data pointer.
    var rgbData: UnsafeMutablePointer<UInt8> { get }
    /// Bytes per row in the pixel buffer.
    var bytesPerRow: Int { get }
    /// Buffer width in pixels.
    var width: Int { get }
    /// Buffer height in pixels.
    var height: Int { get }
    /// Alpha channel format for the pixel data.
    var alphaInfo: CGImageAlphaInfo { get }

    /// Creates a CGImage from the raw pixel buffer.
    func toCGImage() -> CGImage?
    /// Creates an MTLTexture from the raw pixel buffer.
    func toTexture(device: MTLDevice) -> MTLTexture?
    /// Zeros the entire pixel buffer.
    func clear()
}

// MARK: - PointerImagePipeline

/// RE: 0x101368ee4 (PointerImagePipeline CMa, 1.3.15)
///
/// Metal-based pipeline for compositing pointer/cursor imagery into video frames.
/// Renders cursor imagery as part of the video output pipeline (screen recording
/// or remote desktop display scenarios). Conforms to `ImagePipelineType` to allow
/// generic use by video frame processors and subtitle renderers.
///
/// 5 stored properties per field descriptor at 0x10333cb80:
///   rgbData (+0x10), bytesPerRow (+0x18), width (+0x20), height (+0x28), alphaInfo (+0x30)
public final class PointerImagePipeline: ImagePipelineType {
    public let rgbData: UnsafeMutablePointer<UInt8>
    public let bytesPerRow: Int
    public let width: Int
    public let height: Int
    public let alphaInfo: CGImageAlphaInfo

    /// Allocates an RGBA pixel buffer of the specified dimensions.
    ///
    /// - Parameters:
    ///   - width: Buffer width in pixels
    ///   - height: Buffer height in pixels
    ///   - alphaInfo: Alpha channel layout (default: premultipliedLast = RGBA)
    public init(width: Int, height: Int, alphaInfo: CGImageAlphaInfo = .premultipliedLast) {
        self.width = width
        self.height = height
        self.alphaInfo = alphaInfo
        self.bytesPerRow = width * 4 // RGBA = 4 bytes per pixel
        self.rgbData = .allocate(capacity: bytesPerRow * height)
        rgbData.initialize(repeating: 0, count: bytesPerRow * height)
    }

    /// RE: genuine accessor set at 0x100122E70/0x10049975C/0x100425388 (1.3.15)
    /// Creates a CGImage from the raw RGBA buffer.
    public func toCGImage() -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let context = CGContext(
            data: rgbData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: alphaInfo.rawValue
        ) else { return nil }
        return context.makeImage()
    }

    /// RE: genuine accessor set at 0x100122E70/0x10049975C/0x100425388 (1.3.15)
    /// Creates an MTLTexture from the raw buffer and uploads pixel data.
    public func toTexture(device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.replace(region: region, mipmapLevel: 0, withBytes: rgbData, bytesPerRow: bytesPerRow)
        return texture
    }

    /// RE: genuine accessor set at 0x10146FAE8 (setSizeProperty, 1.3.15)
    /// Zeros the entire buffer.
    public func clear() {
        rgbData.initialize(repeating: 0, count: bytesPerRow * height)
    }

    deinit {
        rgbData.deallocate()
    }
}
#endif
