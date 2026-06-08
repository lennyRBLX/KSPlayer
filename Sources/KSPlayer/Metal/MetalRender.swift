//
//  MetalRender.swift
//  KSPlayer-iOS
//
//  Created by kintan on 2020/1/11.
//
import Accelerate
import CoreVideo
import Foundation
import Metal
import QuartzCore
import simd

class MetalRender {
    /// RE: 0x1014683c4 (device once-body, 1.3.15) — DAT_104458f68
    static let device = MTLCreateSystemDefaultDevice()!
    /// RE: 0x10146852c (library once-body — carryover misnomer "sharedInstance_init", 1.3.15) — DAT_103d0f3e8
    static let library: MTLLibrary = {
        var library: MTLLibrary!
        library = device.makeDefaultLibrary()
        if library == nil {
            library = try? device.makeDefaultLibrary(bundle: .module)
        }
        return library
    }()

    /// RE: 0x101468428 (textureCache once-body, 1.3.15) — DAT_104458f70
    /// Lazy CVMetalTextureCache for zero-copy IOSurface plane→texture mapping.
    /// Built via CVMetalTextureCacheCreate; consumed by texture(pixelBuffer:).
    private static var textureCache: CVMetalTextureCache? = {
        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        guard status == kCVReturnSuccess else { return nil }
        return cache
    }()

    /// RE: FUN_1014449f8 @ 0x1014449f8 (delayed CVMetalTextureCache flush, 1.3.15)
    /// Called from MetalPlayView.clearDisplay after a 1-second Task.sleep on MainActor.
    /// Flushes the shared CVMetalTextureCache (DAT_104458f70) to release GPU texture resources.
    static func flushTextureCache() {
        if let cache = textureCache {
            CVMetalTextureCacheFlush(cache, 0)
        }
    }

    private let renderPassDescriptor = MTLRenderPassDescriptor()
    private let commandQueue = MetalRender.device.makeCommandQueue()

    private lazy var colorConversion601VideoRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_601_4.pointee.videoRange.buffer

    private lazy var colorConversion601FullRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_601_4.pointee.buffer

    private lazy var colorConversion709VideoRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_709_2.pointee.videoRange.buffer

    private lazy var colorConversion709FullRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_709_2.pointee.buffer

    private lazy var colorConversionSMPTE240MVideoRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_SMPTE_240M_1995.videoRange.buffer

    private lazy var colorConversionSMPTE240MFullRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_SMPTE_240M_1995.buffer

    private lazy var colorConversion2020VideoRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_2020.videoRange.buffer

    private lazy var colorConversion2020FullRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_2020.buffer

    private lazy var colorOffsetVideoRangeMatrixBuffer: MTLBuffer? = {
        var firstColumn = SIMD3<Float>(-16.0 / 255.0, -128.0 / 255.0, -128.0 / 255.0)
        let buffer = MetalRender.device.makeBuffer(bytes: &firstColumn, length: MemoryLayout<SIMD3<Float>>.size)
        buffer?.label = "colorOffset"
        return buffer
    }()

    private lazy var colorOffsetFullRangeMatrixBuffer: MTLBuffer? = {
        var firstColumn = SIMD3<Float>(0, -128.0 / 255.0, -128.0 / 255.0)
        let buffer = MetalRender.device.makeBuffer(bytes: &firstColumn, length: MemoryLayout<SIMD3<Float>>.size)
        buffer?.label = "colorOffset"
        return buffer
    }()

    private lazy var leftShiftMatrixBuffer: MTLBuffer? = {
        var firstColumn = SIMD3<UInt8>(1, 1, 1)
        let buffer = MetalRender.device.makeBuffer(bytes: &firstColumn, length: MemoryLayout<SIMD3<UInt8>>.size)
        buffer?.label = "leftShift"
        return buffer
    }()

    private lazy var leftShiftSixMatrixBuffer: MTLBuffer? = {
        var firstColumn = SIMD3<UInt8>(64, 64, 64)
        let buffer = MetalRender.device.makeBuffer(bytes: &firstColumn, length: MemoryLayout<SIMD3<UInt8>>.size)
        buffer?.label = "leftShift"
        return buffer
    }()

    // MARK: - BCS (Brightness/Contrast/Saturation) adjustment buffer

    /// Metal buffer for brightness/contrast/saturation uniforms (float3)
    private var bcsBuffer: MTLBuffer? = {
        var bcs = SIMD3<Float>(0.0, 1.0, 1.0) // brightness=0, contrast=1, saturation=1
        let buffer = MetalRender.device.makeBuffer(bytes: &bcs, length: MemoryLayout<SIMD3<Float>>.size)
        buffer?.label = "bcsAdjust"
        return buffer
    }()

    /// Update BCS buffer from KSOptions values
    func updateBCS(brightness: Float, contrast: Float, saturation: Float) {
        var bcs = SIMD3<Float>(brightness, contrast, saturation)
        bcsBuffer?.contents().copyMemory(from: &bcs, byteCount: MemoryLayout<SIMD3<Float>>.size)
    }

    /// Whether BCS adjustments are non-identity (requires post-processing)
    var needsBCSAdjustment: Bool {
        guard let buffer = bcsBuffer else { return false }
        let ptr = buffer.contents().bindMemory(to: SIMD3<Float>.self, capacity: 1)
        let bcs = ptr.pointee
        return bcs.x != 0.0 || bcs.y != 1.0 || bcs.z != 1.0
    }

    // MARK: - Dolby Vision display model (RE: MetalPlayView_renderFrameImpl @ 0x1014457f4)

    /// Process-wide DoviDisplayModel singleton, created on first DV frame.
    /// Binary uses swift_once(&DAT_103d06280, KSOptions_createDoviDisplayModel) -> DAT_104458878.
    /// All callers share the same instance; this property is a thin actor-isolated accessor.
    /// RE: 0x1013a30cc (KSOptions_createDoviDisplayModel, 1.3.15)
    @MainActor
    private var doviDisplayModel: DoviDisplayModel { KSOptions.createDoviDisplayModel() }

    /// RE: 0x10146b508 (clear-present helper, 1.3.15); Drawable protocol slot +0x10 witness: 0x10146a0e4
    func clear(drawable: MTLDrawable) {
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        guard let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else {
            return
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    /// RE: 0x10146a0c4 -> 0x101469550 -> 0x10146bec4 (videoPipeline protocol-witness chain, 1.3.15)
    /// Standard (non-DV) render path. Binary creates and binds ZERO sampler states in this path —
    /// only three fragment buffers (matrix@0 / colorOffset@1 / leftShift@2). The only MTLSamplerState
    /// in the binary belongs to the Anime4K upscale path (DAT_103d0f400), not MetalRender.
    @MainActor
    func draw(pixelBuffer: PixelBufferProtocol, display: DisplayEnum = .plane, drawable: CAMetalDrawable) {
        let inputTextures = pixelBuffer.textures()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        guard !inputTextures.isEmpty, let commandBuffer = commandQueue?.makeCommandBuffer(), let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        encoder.pushDebugGroup("RenderFrame")
        let state: MTLRenderPipelineState
        if needsBCSAdjustment, pixelBuffer.planeCount == 2, display == .plane {
            state = MetalRender.bcsPipelineState(bitDepth: pixelBuffer.bitDepth)
        } else {
            state = display.pipeline(planeCount: pixelBuffer.planeCount, bitDepth: pixelBuffer.bitDepth)
        }
        encoder.setRenderPipelineState(state)
        for (index, texture) in inputTextures.enumerated() {
            texture.label = "texture\(index)"
            encoder.setFragmentTexture(texture, index: index)
        }
        setFragmentBuffer(pixelBuffer: pixelBuffer, encoder: encoder)
        display.set(encoder: encoder)
        encoder.popDebugGroup()
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    /// Dolby Vision render path (RE: MetalPlayView_renderFrameImpl @ 0x10144529c).
    /// When options.display holds the DoviDisplayModel singleton, the binary routes here
    /// instead of the standard DisplayEnum path. Uses runtime-generated reshape shaders.
    @MainActor
    func drawDovi(pixelBuffer: PixelBufferProtocol, drawable: CAMetalDrawable, metadata: DoviGPUMetadata) {
        let inputTextures = pixelBuffer.textures()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        guard !inputTextures.isEmpty,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor),
              let dovi = doviDisplayModel
        else {
            return
        }
        encoder.pushDebugGroup("RenderDovi")
        // Binary checks planeCount for ICtCp vs NV12 routing (DoviDisplayModel_draw @ 0x1014673f4)
        let pixelFormat: DoviPixelFormat = pixelBuffer.planeCount >= 3 ? .ictcp : .nv12
        dovi.draw(encoder: encoder, metadata: metadata, pixelFormat: pixelFormat,
                  bitDepth: pixelBuffer.bitDepth, textures: inputTextures)
        encoder.popDebugGroup()
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    /// RE: 0x10146ba30 (setYCbCrColorConversionFragmentBuffers, body 10146ba30-10146bec3, 1172 B, 1.3.15)
    /// Thunk at 0x1014683c0 is a 4-byte tail-call into 0x10146ba30.
    /// Binds matrix@0 / colorOffset@1 / leftShift@2. Early-returns when planeCount < 2 (BGRA).
    private func setFragmentBuffer(pixelBuffer: PixelBufferProtocol, encoder: MTLRenderCommandEncoder) {
        if pixelBuffer.planeCount > 1 {
            let buffer: MTLBuffer?
            let yCbCrMatrix = pixelBuffer.yCbCrMatrix
            let isFullRangeVideo = pixelBuffer.isFullRangeVideo
            if yCbCrMatrix == kCVImageBufferYCbCrMatrix_ITU_R_709_2 {
                buffer = isFullRangeVideo ? colorConversion709FullRangeMatrixBuffer : colorConversion709VideoRangeMatrixBuffer
            } else if yCbCrMatrix == kCVImageBufferYCbCrMatrix_SMPTE_240M_1995 {
                buffer = isFullRangeVideo ? colorConversionSMPTE240MFullRangeMatrixBuffer : colorConversionSMPTE240MVideoRangeMatrixBuffer
            } else if yCbCrMatrix == kCVImageBufferYCbCrMatrix_ITU_R_2020 {
                buffer = isFullRangeVideo ? colorConversion2020FullRangeMatrixBuffer : colorConversion2020VideoRangeMatrixBuffer
            } else {
                buffer = isFullRangeVideo ? colorConversion601FullRangeMatrixBuffer : colorConversion601VideoRangeMatrixBuffer
            }
            encoder.setFragmentBuffer(buffer, offset: 0, index: 0)
            let colorOffset = isFullRangeVideo ? colorOffsetFullRangeMatrixBuffer : colorOffsetVideoRangeMatrixBuffer
            encoder.setFragmentBuffer(colorOffset, offset: 0, index: 1)
            // RE: leftShift selection gated by pixelBuffer[+0x20] (bitDepth query), NOT leftShift field.
            // DAT_104458f78 = (1,1,1) for 8-bit, DAT_104458f80 = (64,64,64) for 10-bit.
            // 10-bit P010 stores 10 significant bits in high bits of 16-bit word, needs x64 normalize.
            let leftShift = pixelBuffer.bitDepth > 8 ? leftShiftSixMatrixBuffer : leftShiftMatrixBuffer
            encoder.setFragmentBuffer(leftShift, offset: 0, index: 2)
        }
        if needsBCSAdjustment {
            encoder.setFragmentBuffer(bcsBuffer, offset: 0, index: 3)
        }
    }

    /// RE: 0x101467e04 (makePipelineState standalone wrapper, DEAD by code-xref — reflection-only, 1.3.15)
    /// Live pipeline creation goes directly through buildRenderPipelineState @0x101467ed0 from lazy getters.
    /// This standalone wrapper is preserved as a convenience; the shipped binary inlined it at every call site.
    static func makePipelineState(fragmentFunction: String, isSphere: Bool = false, bitDepth: Int32 = 8) -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.colorAttachments[0].pixelFormat = KSOptions.colorPixelFormat(bitDepth: bitDepth)
        descriptor.vertexFunction = library.makeFunction(name: isSphere ? "mapSphereTexture" : "mapTexture")
        descriptor.fragmentFunction = library.makeFunction(name: fragmentFunction)
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float4
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].bufferIndex = 1
        vertexDescriptor.attributes[1].offset = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<simd_float4>.stride
        vertexDescriptor.layouts[1].stride = MemoryLayout<simd_float2>.stride
        descriptor.vertexDescriptor = vertexDescriptor
        // swiftlint:disable force_try
        return try! library.device.makeRenderPipelineState(descriptor: descriptor)
        // swftlint:enable force_try
    }

    /// RE: 0x10146b76c (MetalRender.texture(pixelBuffer:), 1.3.15)
    /// Zero-copy CVMetalTextureCache path: lazily inits textureCache (DAT_104458f70),
    /// bails to empty array if cache is nil, detects bitDepth=10 from FourCC set,
    /// then per-plane CVMetalTextureCacheCreateTextureFromImage -> CVMetalTextureGetTexture.
    static func texture(pixelBuffer: CVPixelBuffer) -> [MTLTexture] {
        guard let cache = textureCache else {
            return []
        }
        let isPlanar = CVPixelBufferIsPlanar(pixelBuffer)
        let planeCount = isPlanar ? CVPixelBufferGetPlaneCount(pixelBuffer) : 1
        let formatType = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let bitDepth: Int32 = formatType.bitDepth
        let formats = KSOptions.pixelFormat(planeCount: planeCount, bitDepth: bitDepth)
        var textures = [MTLTexture]()
        textures.reserveCapacity(planeCount)
        for plane in 0 ..< planeCount {
            let width = isPlanar ? CVPixelBufferGetWidthOfPlane(pixelBuffer, plane) : CVPixelBufferGetWidth(pixelBuffer)
            let height = isPlanar ? CVPixelBufferGetHeightOfPlane(pixelBuffer, plane) : CVPixelBufferGetHeight(pixelBuffer)
            var cvTexture: CVMetalTexture?
            let status = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault,
                cache,
                pixelBuffer,
                nil,
                formats[plane],
                width,
                height,
                plane,
                &cvTexture
            )
            guard status == kCVReturnSuccess, let cvTex = cvTexture,
                  let texture = CVMetalTextureGetTexture(cvTex) else {
                continue
            }
            textures.append(texture)
        }
        return textures
    }

    /// Update BCS buffer from current KSOptions values
    func updateBCSFromOptions(_ options: KSOptions) {
        updateBCS(brightness: options.brightness, contrast: options.contrast, saturation: options.saturation)
    }

    private static var nv12BCS: MTLRenderPipelineState = makePipelineState(fragmentFunction: "displayNV12BCSTexture")
    private static var nv12BCS10: MTLRenderPipelineState = makePipelineState(fragmentFunction: "displayNV12BCSTexture", bitDepth: 10)

    static func bcsPipelineState(bitDepth: Int32) -> MTLRenderPipelineState {
        bitDepth == 10 ? nv12BCS10 : nv12BCS
    }

    /// RE: software-decode texture path (PixelBuffer class → MTLBuffer → MTLTexture), 1.3.15
    /// Counterpart to the hardware-decode CVMetalTextureCache path above.
    static func textures(formats: [MTLPixelFormat], widths: [Int], heights: [Int], buffers: [MTLBuffer?], lineSizes: [Int]) -> [MTLTexture] {
        (0 ..< formats.count).compactMap { i in
            guard let buffer = buffers[i] else {
                return nil
            }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: formats[i], width: widths[i], height: heights[i], mipmapped: false)
            descriptor.storageMode = buffer.storageMode
            return buffer.makeTexture(descriptor: descriptor, offset: 0, bytesPerRow: lineSizes[i])
        }
    }
}

// swiftlint:disable identifier_name
// private let kvImage_YpCbCrToARGBMatrix_ITU_R_601_4 = vImage_YpCbCrToARGBMatrix(Kr: 0.299, Kb: 0.114)
// private let kvImage_YpCbCrToARGBMatrix_ITU_R_709_2 = vImage_YpCbCrToARGBMatrix(Kr: 0.2126, Kb: 0.0722)
private let kvImage_YpCbCrToARGBMatrix_SMPTE_240M_1995 = vImage_YpCbCrToARGBMatrix(Kr: 0.212, Kb: 0.087)
private let kvImage_YpCbCrToARGBMatrix_ITU_R_2020 = vImage_YpCbCrToARGBMatrix(Kr: 0.2627, Kb: 0.0593)
extension vImage_YpCbCrToARGBMatrix {
    /**
     https://en.wikipedia.org/wiki/YCbCr
     @textblock
            | R |    | 1    0                                                            2-2Kr |   | Y' |
            | G | = | 1   -Kb * (2 - 2 * Kb) / Kg   -Kr * (2 - 2 * Kr) / Kg |  | Cb |
            | B |    | 1   2 - 2 * Kb                                                     0  |  | Cr |
     @/textblock
     */
    /// RE: 0x10146a9a8 (shared 3x3 simd-row builder, 1.3.15)
    /// Per-standard coefficient once-bodies: 0x10146a918 (601), 0x10146a93c (709),
    /// 0x10146a960 (240M), 0x10146a984 (2020). Each sets Kr/Kb globals, feeds two
    /// matrix once-inits (video-range + full-range), which call FUN_10146a9a8 to build
    /// the simd_float3x3 packed into an MTLBuffer labeled "colorConversionMatrix".
    init(Kr: Float, Kb: Float) {
        let Kg = 1 - Kr - Kb
        self.init(Yp: 1, Cr_R: 2 - 2 * Kr, Cr_G: -Kr * (2 - 2 * Kr) / Kg, Cb_G: -Kb * (2 - 2 * Kb) / Kg, Cb_B: 2 - 2 * Kb)
    }

    var videoRange: vImage_YpCbCrToARGBMatrix {
        vImage_YpCbCrToARGBMatrix(Yp: 255 / 219 * Yp, Cr_R: 255 / 224 * Cr_R, Cr_G: 255 / 224 * Cr_G, Cb_G: 255 / 224 * Cb_G, Cb_B: 255 / 224 * Cb_B)
    }

    var buffer: MTLBuffer? {
        var matrix = simd_float3x3([Yp, Yp, Yp], [0.0, Cb_G, Cb_B], [Cr_R, Cr_G, 0.0])
        let buffer = MetalRender.device.makeBuffer(bytes: &matrix, length: MemoryLayout<simd_float3x3>.size)
        buffer?.label = "colorConversionMatrix"
        return buffer
    }
}

// swiftlint:enable identifier_name
