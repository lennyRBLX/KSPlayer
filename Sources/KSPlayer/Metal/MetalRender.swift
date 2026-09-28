//
//  MetalRender.swift
//  KSPlayer-iOS
//
//  Created by kintan on 2020/1/11.
//
@preconcurrency import Accelerate
import CoreVideo
import Foundation
import Metal
import QuartzCore
import simd
import UIKit

class MetalRender {

    // s100 @0x101a83020 (278 instr) is an MTLLibrary method: body reads self from x20 (`mov x0,x20` -> newFunctionWithName:), callers pass x5 = swift_getObjectType(library).
    static func makePipelineState(fragmentFunction: String, isSphere: Bool = false, bitDepth: Int32 = 8) -> MTLRenderPipelineState {
        library.makePipelineState(vertexFunction: isSphere ? "mapSphereTexture" : "mapTexture", fragmentFunction: fragmentFunction, bitDepth: bitDepth)
    }
    static func makePipelineState(vertexFunction: String, fragmentFunction: String, bitDepth: Int32 = 8) -> MTLRenderPipelineState {
        library.makePipelineState(vertexFunction: vertexFunction, fragmentFunction: fragmentFunction, bitDepth: bitDepth)
    }
    static let library: MTLLibrary = {
        var library: MTLLibrary!
        library = device.makeDefaultLibrary()
        if library == nil {
            library = try? device.makeDefaultLibrary(bundle: .module)
        }
        return library
    }()

    nonisolated(unsafe) static let renderPassDescriptor = MTLRenderPassDescriptor()
    /// ⚑ static getter 0x10002d9d4 — `mov x0, #0` / `ret`, the image's canonical constant-zero
    /// body. Its storage at 0x10356c4e0 independently reads 0 as well, so both routes agree on
    /// the value. `0` is `MTLStorageModeShared` per the SDK's own MTLResource.h
    /// (`typedef NS_ENUM(NSUInteger, MTLStorageMode) { MTLStorageModeShared = 0, ... }`), which
    /// is what licenses spelling it `.shared` rather than `MTLStorageMode(rawValue: 0)!`.
    /// Trie: `static KSPlayer.MetalRender.fragmentTextureStorageMode.getter : __C.MTLStorageMode`.
    @used nonisolated(unsafe) static var fragmentTextureStorageMode: MTLStorageMode = .shared
    static let commandQueue = MetalRender.device.makeCommandQueue()
    static let samplerState: MTLSamplerState? = {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        return MetalRender.device.makeSamplerState(descriptor: samplerDescriptor)
    }()

    private nonisolated(unsafe) static let colorConversion601VideoRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_601_4.pointee.videoRange.buffer

    private nonisolated(unsafe) static let colorConversion601FullRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_601_4.pointee.buffer

    private nonisolated(unsafe) static let colorConversion709VideoRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_709_2.pointee.videoRange.buffer

    private nonisolated(unsafe) static let colorConversion709FullRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_709_2.pointee.buffer

    private nonisolated(unsafe) static let colorConversionSMPTE240MVideoRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_SMPTE_240M_1995.videoRange.buffer

    private nonisolated(unsafe) static let colorConversionSMPTE240MFullRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_SMPTE_240M_1995.buffer

    private nonisolated(unsafe) static let colorConversion2020VideoRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_2020.videoRange.buffer

    private nonisolated(unsafe) static let colorConversion2020FullRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_2020.buffer

    private nonisolated(unsafe) static let colorOffsetVideoRangeMatrixBuffer: MTLBuffer? = {
        var firstColumn = SIMD3<Float>(-16.0 / 255.0, -128.0 / 255.0, -128.0 / 255.0)
        let buffer = MetalRender.device.makeBuffer(bytes: &firstColumn, length: MemoryLayout<SIMD3<Float>>.size)
        buffer?.label = "colorOffset"
        return buffer
    }()

    private nonisolated(unsafe) static let colorOffsetFullRangeMatrixBuffer: MTLBuffer? = {
        var firstColumn = SIMD3<Float>(0, -128.0 / 255.0, -128.0 / 255.0)
        let buffer = MetalRender.device.makeBuffer(bytes: &firstColumn, length: MemoryLayout<SIMD3<Float>>.size)
        buffer?.label = "colorOffset"
        return buffer
    }()

    private nonisolated(unsafe) static let leftShiftMatrixBuffer: MTLBuffer? = {
        var firstColumn = SIMD3<UInt8>(1, 1, 1)
        let buffer = MetalRender.device.makeBuffer(bytes: &firstColumn, length: MemoryLayout<SIMD3<UInt8>>.size)
        buffer?.label = "leftShit"
        return buffer
    }()

    private nonisolated(unsafe) static let leftShiftSixMatrixBuffer: MTLBuffer? = {
        var firstColumn = SIMD3<UInt8>(64, 64, 64)
        let buffer = MetalRender.device.makeBuffer(bytes: &firstColumn, length: MemoryLayout<SIMD3<UInt8>>.size)
        buffer?.label = "leftShit"
        return buffer
    }()

    static func clear(drawable: CAMetalDrawable) {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
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
    }

    // MetalRender.draw is GONE. It had no counterpart in the binary under any name; Forward's
    // real render entry point is the MTLRenderCommandEncoder extension at the bottom of this
    // file, and keeping a second one would have meant inventing a call path.

    // NOT private: the trie exports `static KSPlayer.MetalRender.setFragmentBuffer(encoder:pixelBuffer:)`
    // at 0x101a83720, and a private static would export nothing. Both display models call it.
    static func setFragmentBuffer(encoder: MTLRenderCommandEncoder, pixelBuffer: PixelBufferProtocol) {
        if pixelBuffer.planeCount > 1 {
            let isFullRangeVideo = pixelBuffer.isFullRangeVideo
            let leftShift = pixelBuffer.leftShift == 0 ? leftShiftMatrixBuffer : leftShiftSixMatrixBuffer
            let yCbCrMatrix = pixelBuffer.yCbCrMatrix
            let buffer: MTLBuffer?
            if yCbCrMatrix == kCVImageBufferYCbCrMatrix_ITU_R_601_4 {
                buffer = isFullRangeVideo ? colorConversion601FullRangeMatrixBuffer : colorConversion601VideoRangeMatrixBuffer
            } else if yCbCrMatrix == kCVImageBufferYCbCrMatrix_SMPTE_240M_1995 {
                buffer = isFullRangeVideo ? colorConversionSMPTE240MFullRangeMatrixBuffer : colorConversionSMPTE240MVideoRangeMatrixBuffer
            } else if yCbCrMatrix == kCVImageBufferYCbCrMatrix_ITU_R_2020 {
                buffer = isFullRangeVideo ? colorConversion2020FullRangeMatrixBuffer : colorConversion2020VideoRangeMatrixBuffer
            } else {
                buffer = isFullRangeVideo ? colorConversion709FullRangeMatrixBuffer : colorConversion709VideoRangeMatrixBuffer
            }
            let colorOffset = isFullRangeVideo ? colorOffsetFullRangeMatrixBuffer : colorOffsetVideoRangeMatrixBuffer
            encoder.setFragmentBuffer(buffer, offset: 0, index: 0)
            encoder.setFragmentBuffer(colorOffset, offset: 0, index: 1)
            encoder.setFragmentBuffer(leftShift, offset: 0, index: 2)
        }
    }
    public static let device = MTLCreateSystemDefaultDevice()!
    /// ⚑[tool=disassemble ref=MetalRender.mtlTextureCache:addressor@0x101a82f14 once-init@0x101a83794 result=45-instr]
    /// A `swift_once`-guarded static: the addressor checks the token at 0x1044eda8, runs the init
    /// at 0x101a83794, and returns the storage 0x104c636e8. The init is one CoreVideo call whose
    /// every operand is named:
    ///   `x0 = [kCFAllocatorDefault]`  __got 0x104108c40
    ///   `x1 = 0`, `x3 = 0`            the two attribute dictionaries, both nil
    ///   `x2 = [0x104c636e0]`          which the trie names `static MetalRender.device : MTLDevice`
    ///                                 — the property declared directly above
    ///   `x4 = sp`                     the out-parameter, read back and stored to 0x104c636e8
    ///   ⚑[tool=bind_oracle ref=__got:0x1041087b8 result=_CVMetalTextureCacheCreate]
    /// The function's own result is discarded — nothing branches on it — so there is no `guard`
    /// and no error path to write.
    /// ⚑ `let`, not `var`, and that is read: the trie exports an `unsafeMutableAddressor` and a
    /// getter for this static and NO setter. The remaining stores in the body are the
    /// `___stack_chk_guard` load/compare pair (__got 0x10410bc10), not a second write.
    /// Access read from its vpMV.
    /// ⚑ `nonisolated(unsafe)` is a COMPILER requirement, not a binary reading: strict concurrency
    /// rejects a static of the non-Sendable `CVMetalTextureCache?` without it. The annotation has
    /// no runtime representation, so it cannot diverge from the image; it is the same device this
    /// repo already uses on the KSOptions statics.
    nonisolated(unsafe) public static let mtlTextureCache: CVMetalTextureCache? = {
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        return cache
    }()
}
extension MTLLibrary {
    func makePipelineState(vertexFunction: String, fragmentFunction: String, bitDepth: Int32 = 8) -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.colorAttachments[0].pixelFormat = KSOptions.colorPixelFormat(bitDepth: bitDepth)
        descriptor.vertexFunction = makeFunction(name: vertexFunction)
        descriptor.fragmentFunction = makeFunction(name: fragmentFunction)
        if vertexFunction == "mapSphereTexture" { // vertex DESCRIPTOR only for the sphere vertex function (0x101a83148 compare)
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
        }
        return try! device.makeRenderPipelineState(descriptor: descriptor) // swiftlint:disable:this force_try
    }
}
extension MetalRender {
    static func texture(pixelBuffer: CVPixelBuffer) -> [MTLTexture] {
        guard let iosurface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else {
            return []
        }
        let formats = KSOptions.pixelFormat(planeCount: pixelBuffer.planeCount, bitDepth: pixelBuffer.bitDepth)
        return (0 ..< pixelBuffer.planeCount).compactMap { index in
            let width = pixelBuffer.widthOfPlane(at: index)
            let height = pixelBuffer.heightOfPlane(at: index)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: formats[index], width: width, height: height, mipmapped: false)
            return device.makeTexture(descriptor: descriptor, iosurface: iosurface, plane: index)
        }
    }

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

// Forward's actual render entry point, and the reason MetalRender.draw had no counterpart:
// `$sSo23MTLRenderCommandEncoderP8KSPlayerE4draw5frame7displayyAC13VideoVTBFrameC_AC11DisplayEnum_ptF`
// @0x101a84830, 151 instructions. `self` is the ENCODER — the binary's swiftself register holds
// it — and there is no drawable parameter and no command-buffer work here at all; the caller
// owns that. Statement order read from the body:
//   textures() through the pixelBuffer's witness slot at wt+0x128, which resolves to
//   (extension in KSPlayer):__C.CVBufferRef.textures() -> [MTLTexture]
//   -> empty-guard early return
//   -> pushDebugGroup("RenderFrame")          [stub 0x103466b80]
//   -> setFragmentSamplerState(_:index: 0)    [stub 0x103469b80]
//   -> per texture: setLabel: then setFragmentTexture:atIndex:  [stubs 0x103469f80 / 0x103469ba0]
//   -> display.set(frame:encoder:) through the DisplayEnum witness table at wt+0x10
//   -> popDebugGroup()                        [stub 0x1034663e0]
//   -> endEncoding()                          [stub 0x1034616c0]
// It notably does NOT call setRenderPipelineState and does NOT call MetalRender.setFragmentBuffer
// — both moved into DisplayEnum.set(frame:encoder:), which is what forced that requirement to
// take the frame.
//
// Both string literals here are register-form small strings ("RenderFrame" with a count-11
// discriminator, "texture" with count-7), which decode_string_literal has no path for; they were
// read from the mov/movk immediates.
public extension MTLRenderCommandEncoder {
    @MainActor
    func draw(frame: VideoVTBFrame, display: any DisplayEnum) {
        // No unwrap: VideoVTBFrame.pixelBuffer is a non-optional `let` in the source now too, so
        // this matches the binary, which loads the field with no nil check.
        let pixelBuffer = frame.pixelBuffer
        let inputTextures = pixelBuffer.textures()
        guard !inputTextures.isEmpty else { return }
        pushDebugGroup("RenderFrame")
        setFragmentSamplerState(MetalRender.samplerState, index: 0)
        for (index, texture) in inputTextures.enumerated() {
            texture.label = "texture\(index)"
            setFragmentTexture(texture, index: index)
        }
        display.set(frame: frame, encoder: self)
        popDebugGroup()
        endEncoding()
    }
}

// The only conformer whose witness table is walkable in this image. The other two are RealityKit
// types (TextureResource and TextureResource.DrawableQueue) whose conformances the binary records
// but whose descriptors are out of image, so they are not declared here.
extension CAMetalLayer: Drawable {
    func updateInfo(frame: VideoVTBFrame, display: DisplayEnum, pipeline: VideoPipeline?) {
        // Forward 0x101a84b18. Four callees have no declaration in this source and are written as
        // local funcs: the MasteringDisplayMetadata byte packer 0x101a654f4 (Model.swift; the
        // ContentLight/AmbientViewing packers are inlined in Forward), the pixelBuffer EDR-metadata
        // helper 0x101a88500 and the layer EDR-headroom check 0x1019f26e4. Byte appends are spelled
        // out because Array<UInt8>.append(UInt16/UInt32) (0x1019e7290/0x1019e7374) is not mutating here.
        func append(_ value: UInt16, to bytes: inout [UInt8]) {
            bytes.append(UInt8(truncatingIfNeeded: value))
            bytes.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        func append(_ value: UInt32, to bytes: inout [UInt8]) {
            bytes.append(UInt8(truncatingIfNeeded: value))
            bytes.append(UInt8(truncatingIfNeeded: value >> 8))
            bytes.append(UInt8(truncatingIfNeeded: value >> 16))
            bytes.append(UInt8(truncatingIfNeeded: value >> 24))
        }
        func data(_ displayData: MasteringDisplayMetadata) -> Data {
            var bytes = [UInt8]()
            append(displayData.display_primaries_r_x, to: &bytes)
            append(displayData.display_primaries_r_y, to: &bytes)
            append(displayData.display_primaries_g_x, to: &bytes)
            append(displayData.display_primaries_g_y, to: &bytes)
            append(displayData.display_primaries_b_x, to: &bytes)
            append(displayData.display_primaries_b_y, to: &bytes)
            append(displayData.white_point_x, to: &bytes)
            append(displayData.white_point_y, to: &bytes)
            append(displayData.minLuminance, to: &bytes)
            append(displayData.maxLuminance, to: &bytes)
            bytes.reverse()
            return Data(bytes)
        }
        #if !os(tvOS)
        func pixelBufferEDRMetadata(_ pixelBuffer: PixelBufferProtocol) -> CAEDRMetadata? {
            if let displayInfo = pixelBuffer.displayInfo, let contentInfo = pixelBuffer.contentInfo {
                return CAEDRMetadata.hdr10(displayInfo: displayInfo, contentInfo: contentInfo, opticalOutputScale: 10000)
            }
            if let ambientViewingEnvironment = pixelBuffer.ambientViewingEnvironment {
                if #available(macOS 14.0, iOS 17.0, *) {
                    return CAEDRMetadata.hlg(ambientViewingEnvironment: ambientViewingEnvironment)
                }
                return CAEDRMetadata.hlg
            }
            if pixelBuffer.transferFunction == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ {
                return CAEDRMetadata.hdr10(minLuminance: 0.1, maxLuminance: 1000, opticalOutputScale: 10000)
            }
            if pixelBuffer.transferFunction == kCVImageBufferTransferFunction_ITU_R_2100_HLG {
                if KSPlayer.DynamicRange.availableHDRModes.contains(.hlg) {
                    return CAEDRMetadata.hlg
                }
                return CAEDRMetadata.hdr10(minLuminance: 0.1, maxLuminance: 1000, opticalOutputScale: 10000)
            }
            return nil
        }
        func isEDRScreen() -> Bool {
            guard let view = delegate as? UIView else {
                return true
            }
            return (view.window?.windowScene?.screen.currentEDRHeadroom ?? 0) > 1.0
        }
        #endif
        if let edrMetaData = frame.edrMetaData {
            let pixelBuffer = frame.pixelBuffer
            pixelBuffer.displayInfo = edrMetaData.displayData.map { data($0) }
            pixelBuffer.contentInfo = edrMetaData.contentData.map { contentData in
                var bytes = [UInt8]()
                append(contentData.MaxCLL, to: &bytes)
                append(contentData.MaxFALL, to: &bytes)
                bytes.reverse()
                return Data(bytes)
            }
            pixelBuffer.ambientViewingEnvironment = edrMetaData.ambientViewingEnvironment.map { ambientViewingEnvironment in
                var bytes = [UInt8]()
                append(ambientViewingEnvironment.ambient_illuminance, to: &bytes)
                append(ambientViewingEnvironment.ambient_light_x, to: &bytes)
                append(ambientViewingEnvironment.ambient_light_y, to: &bytes)
                bytes.reverse()
                return Data(bytes)
            }
        }
        let pixelBuffer = frame.pixelBuffer
        #if !os(tvOS)
        var edrMetadata = pixelBufferEDRMetadata(pixelBuffer)
        if edrMetadata == nil {
            if let doviData = frame.doviData {
                let minLuminance = doviData.minLuminance
                let maxLuminance = doviData.maxLuminance
                var scale: Float = 1.0
                if maxLuminance > 500, !isEDRScreen() {
                    scale = maxLuminance / 500
                }
                edrMetadata = CAEDRMetadata.hdr10(minLuminance: minLuminance / scale, maxLuminance: maxLuminance / scale, opticalOutputScale: 10000)
            }
        } else if !isEDRScreen() {
            edrMetadata = CAEDRMetadata.hdr10(minLuminance: 0.1, maxLuminance: 400, opticalOutputScale: 10000)
        }
        self.edrMetadata = edrMetadata
        framebufferOnly = self.edrMetadata == nil
        #endif
        pixelFormat = KSOptions.colorPixelFormat(bitDepth: pixelBuffer.bitDepth)
        if let colorspace = pixelBuffer.colorspace, self.colorspace != colorspace {
            self.colorspace = colorspace
            KSLog("[video] CAMetalLayer colorspace \(String(describing: colorspace))")
            #if !os(tvOS)
            let name = colorspace.name
            wantsExtendedDynamicRangeContent = colorspace != CGColorSpaceCreateDeviceRGB() && name != CGColorSpace.sRGB && name != CGColorSpace.itur_709 && isEDRScreen()
            KSLog("[video] CAMetalLayer wantsExtendedDynamicRangeContent \(wantsExtendedDynamicRangeContent)")
            #endif
        }
        var size: CGSize
        if display.isSphere {
            size = UIApplication.shared.windows.first?.bounds.size ?? CGSize(width: 1, height: 1)
        } else {
            let pixelSize = pixelBuffer.size
            let aspectRatio = pixelBuffer.aspectRatio
            size = CGSize(width: pixelSize.width, height: pixelSize.height * aspectRatio.height / aspectRatio.width)
        }
        if let pipelineSize = pipeline?.configure(pixelBuffer: pixelBuffer) {
            size = pipelineSize
            framebufferOnly = false
        }
        drawableSize = size
    }
    @used func draw(frame: VideoVTBFrame, display: DisplayEnum, pipeline: VideoPipeline?) {
        // Forward: 1-insn thunk 0x101a854ac → Bool body 0x101a854b0, which calls the CAMetalDrawable
        // render helper 0x101a873b4 `draw(frame:display:drawable:pipeline:)` (inlined here; no decl).
        // The Anime4KFrameDump gate/dump calls (0x101a784d4, 0x101a778a8, 0x101a77d20) have no decl
        // in this source and are not written.
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }
        updateInfo(frame: frame, display: display, pipeline: pipeline)
        guard let drawable = nextDrawable() else {
            KSLog("[video] CAMetalLayer not readyForMoreMediaData")
            return
        }
        if let inputTexture = pipeline?.inputTexture {
            let size = frame.pixelBuffer.size
            if inputTexture.width != Int(size.width) || inputTexture.height != Int(size.height) {
                KSLog("[MetalRender] \u{26A0}\u{FE0F} inputTexture size mismatch: texture=\(inputTexture.width)x\(inputTexture.height), video=\(Int(size.width))x\(Int(size.height))")
            }
            MetalRender.renderPassDescriptor.colorAttachments[0].texture = inputTexture
            MetalRender.renderPassDescriptor.colorAttachments[0].storeAction = .store
        } else {
            MetalRender.renderPassDescriptor.colorAttachments[0].texture = pipeline?.inputTexture ?? drawable.texture
        }
        let pixelBuffer = frame.pixelBuffer
        let inputTextures = pixelBuffer.textures()
        guard !inputTextures.isEmpty,
              let commandBuffer = MetalRender.commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: MetalRender.renderPassDescriptor)
        else {
            return
        }
        encoder.pushDebugGroup("RenderFrame")
        encoder.setFragmentSamplerState(MetalRender.samplerState, index: 0)
        for (index, texture) in inputTextures.enumerated() {
            texture.label = "texture\(index)"
            encoder.setFragmentTexture(texture, index: index)
        }
        nonisolated(unsafe) let unsafeDisplay = display
        nonisolated(unsafe) let unsafeFrame = frame
        nonisolated(unsafe) let unsafeEncoder = encoder
        MainActor.assumeIsolated {
            unsafeDisplay.set(frame: unsafeFrame, encoder: unsafeEncoder)
        }
        encoder.popDebugGroup()
        encoder.endEncoding()
        pipeline?.encode(commandBuffer: commandBuffer, outputTexture: drawable.texture)
        commandBuffer.present(drawable)
        commandBuffer.commit()
        if pipeline == nil {
            commandBuffer.waitUntilCompleted()
        }
    }
    @used func clear() {
        #if !os(tvOS)
        edrMetadata = nil
        #endif
        if let drawable = nextDrawable() {
            MetalRender.clear(drawable: drawable)
        }
    }
}

// VertexIn @0x1039f1034 — declaration shape read from the Forward context descriptor (kind, parent,
// conformances, case names); members not reconstructed. Placement: gap_lower(inferred) (MetalRender.swift..SphereDisplayModel.swift).
// ⚑[tool=type_surface ref=VertexIn:0x1039f1034 result=struct VertexIn]
// ⚑[tool=field_surface ref=VertexIn:fieldmd result=2 let] Lazy owner (no build metadata); fields follow
// Forward's record order, IsVar bits and resolved types.
struct VertexIn {
    let pos: SIMD4<Float>
    let uv: SIMD2<Float>
}

#if canImport(RealityKit)
import RealityKit

extension RealityKit.TextureResource.Drawable {
    @used func present(commandBuffer: MTLCommandBuffer) {
        commandBuffer.present(self)
        commandBuffer.commit()
    }
}

extension RealityKit.TextureResource {
    @used func draw(frame: VideoVTBFrame, display: DisplayEnum, pipeline: VideoPipeline?) {
        // Forward: 1-insn thunk 0x101a85774 → Bool body 0x101a85778; both queue paths call the
        // DrawableQueue body 0x101a85cac (DrawableQueue.draw below).
        let pixelBuffer = frame.pixelBuffer
        var width = pixelBuffer.width
        var height = pixelBuffer.height
        if let size = pipeline?.configure(pixelBuffer: pixelBuffer) {
            width = Int(size.width)
            height = Int(size.height)
            KSLog("[MetalRender] \u{1F4D0} TextureResource using pipeline size: \(width)x\(height)")
        }
        if let drawableQueue, drawableQueue.width == width, drawableQueue.height == height {
            drawableQueue.draw(frame: frame, display: display, pipeline: pipeline)
            return
        }
        let descriptor = TextureResource.DrawableQueue.Descriptor(pixelFormat: KSOptions.colorPixelFormat(bitDepth: pixelBuffer.bitDepth), width: width, height: height, usage: [.renderTarget, .shaderRead, .shaderWrite], mipmapsMode: .none)
        guard let queue = try? TextureResource.DrawableQueue(descriptor) else {
            return
        }
        replace(withDrawables: queue)
        queue.draw(frame: frame, display: display, pipeline: pipeline)
    }
    @used func clear() {
        drawableQueue?.clear()
    }
}

extension RealityKit.TextureResource.DrawableQueue {
    // ⚑[tool=member_add ref=DrawableQueue.clear():0x10000e52c result=ICF-folded into the shared 1-instr `ret`] empty body.
    @used func clear() {}
    @used func draw(frame: VideoVTBFrame, display: DisplayEnum, pipeline: VideoPipeline?) {
        // Forward: 1-insn thunk 0x101a85ec4 → Bool body 0x101a85cac, which calls the
        // TextureResource.Drawable render helper 0x101a86090 `draw(frame:display:drawable:pipeline:)`
        // (inlined here; no decl). Anime4KFrameDump gate/dump calls not written (no decl).
        guard let drawable = try? nextDrawable() else {
            KSLog("[video] TextureResource not readyForMoreMediaData")
            return
        }
        if let inputTexture = pipeline?.inputTexture {
            let size = frame.pixelBuffer.size
            if inputTexture.width != Int(size.width) || inputTexture.height != Int(size.height) {
                KSLog("[MetalRender] \u{26A0}\u{FE0F} inputTexture size mismatch: texture=\(inputTexture.width)x\(inputTexture.height), video=\(Int(size.width))x\(Int(size.height))")
            }
            MetalRender.renderPassDescriptor.colorAttachments[0].texture = inputTexture
            MetalRender.renderPassDescriptor.colorAttachments[0].storeAction = .store
        } else {
            MetalRender.renderPassDescriptor.colorAttachments[0].texture = pipeline?.inputTexture ?? drawable.texture
        }
        let pixelBuffer = frame.pixelBuffer
        let inputTextures = pixelBuffer.textures()
        guard !inputTextures.isEmpty,
              let commandBuffer = MetalRender.commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: MetalRender.renderPassDescriptor)
        else {
            return
        }
        encoder.pushDebugGroup("RenderFrame")
        encoder.setFragmentSamplerState(MetalRender.samplerState, index: 0)
        for (index, texture) in inputTextures.enumerated() {
            texture.label = "texture\(index)"
            encoder.setFragmentTexture(texture, index: index)
        }
        nonisolated(unsafe) let unsafeDisplay = display
        nonisolated(unsafe) let unsafeFrame = frame
        nonisolated(unsafe) let unsafeEncoder = encoder
        MainActor.assumeIsolated {
            unsafeDisplay.set(frame: unsafeFrame, encoder: unsafeEncoder)
        }
        encoder.popDebugGroup()
        encoder.endEncoding()
        pipeline?.encode(commandBuffer: commandBuffer, outputTexture: drawable.texture)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
#endif
