//
//  PointerImagePipeline.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — binary address 0x101368f30
//  Raw pixel buffer for video frame processing and subtitle compositing.
//  This is the pixel buffer abstraction that libass renders into.
//

#if canImport(Metal)
import CoreGraphics
import Metal
import Foundation

public final class PointerImagePipeline {
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

    /// Zeros the entire buffer.
    public func clear() {
        rgbData.initialize(repeating: 0, count: bytesPerRow * height)
    }

    deinit {
        rgbData.deallocate()
    }
}
#endif
