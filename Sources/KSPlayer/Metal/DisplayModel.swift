//
//  DisplayModel.swift
//  KSPlayer-iOS
//
//  Created by kintan on 2020/1/11.
//

import Foundation
import Metal
import simd
#if canImport(UIKit)
import UIKit
#endif

// The `extension DisplayEnum` that used to sit here is GONE. It switched on the enum cases
// .plane/.vr/.vrBox and forwarded to three static instances. None of that exists in the binary:
// DisplayEnum is a class-constrained protocol and the forwarding is ordinary witness dispatch,
// so the whole layer was scaffolding for a type kind Forward does not have.

// PUBLIC, not `private class`. The binary emits a public-exclusive property descriptor for
// `isSphere` on this class, and a public member of a file-private class is not expressible.
// Widening is also what lets KSOptions.display hold one of these as an existential and what
// lets ThumbnailDoviDisplayModel subclass it from another file.
@MainActor
public class PlaneDisplayModel: DisplayEnum {
    private lazy var yuv = MetalRender.makePipelineState(vertexFunction: "mapTexture", fragmentFunction: "displayYUVTexture")
    private lazy var yuvp010LE = MetalRender.makePipelineState(vertexFunction: "mapTexture", fragmentFunction: "displayYUVTexture", bitDepth: 10)
    private lazy var nv12 = MetalRender.makePipelineState(vertexFunction: "mapTexture", fragmentFunction: "displayNV12Texture")
    private lazy var p010LE = MetalRender.makePipelineState(vertexFunction: "mapTexture", fragmentFunction: "displayNV12Texture", bitDepth: 10)
    private lazy var bgra = MetalRender.makePipelineState(vertexFunction: "mapTexture", fragmentFunction: "displayTexture")

    // DisplayEnum requirement 0. STORED with a declaration default, at offset 0x38 — the class's
    // field_offset_vector is 5 lazy slots (0x10..0x37) then isSphere, InstanceSize 0x39.
    public nonisolated let isSphere = false

    // The six stored properties this class used to declare — indexCount, indexType,
    // primitiveType, indexBuffer, posBuffer, uvBuffer — together with genSphere() and the init
    // that filled them, are REMOVED. The binary's PlaneDisplayModel has exactly six field
    // records: the five $__lazy_storage_$_ pipeline slots plus isSphere, and no init beyond the
    // implicit one. That absence is the whole reason set(frame:encoder:) below draws
    // non-indexed: there is no index buffer to draw from.

    public nonisolated init() {}

    // Slot 33 @0x101a81a10, 46 instructions, read end to end. `frame` is used for exactly two
    // things and nothing else: `frame.pixelBuffer` (a 2-word class existential at frame+0x18)
    // and `frame.adjustBuffer` (frame+0x48 — identified BY TYPE as the only MTLBuffer-typed
    // field among VideoVTBFrame's 14 records). The body touches no stored field of this class;
    // `self` is consumed only as the receiver of the pipeline call.
    //
    // The four selector sends were named from Ghidra's __objc_msgSend_stub entries, not guessed:
    // 0x10346b020 setRenderPipelineState:, 0x103469b00 setFragmentBuffer:offset:atIndex:,
    // 0x103469c60 setFrontFacingWinding:, 0x103461380 drawPrimitives:vertexStart:vertexCount:.
    // Immediates: fragment buffer index 3, winding 0 (= .clockwise), and drawPrimitives
    // (4, 0, 4) where MTLPrimitiveType 4 is .triangleStrip.
    //
    // The third statement's callee 0x101a86ea4 exports no symbol of its own, but it is NOT
    // unnameable: the exported `MetalRender.setFragmentBuffer(encoder:pixelBuffer:)` sits at
    // 0x101a83720 and its entire body is one instruction, `b 0x101a86ea4`.
    public func set(frame: VideoVTBFrame, encoder: MTLRenderCommandEncoder) {
        // No unwrap: VideoVTBFrame.pixelBuffer is a non-optional `let` in the source now too, so
        // this matches the binary, which loads the field with no nil check.
        let pixelBuffer = frame.pixelBuffer
        let state = pipeline(pixelBuffer: pixelBuffer)
        encoder.setRenderPipelineState(state)
        MetalRender.setFragmentBuffer(encoder: encoder, pixelBuffer: pixelBuffer)
        encoder.setFragmentBuffer(frame.adjustBuffer, offset: 0, index: 3)
        encoder.setFrontFacing(.clockwise)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    // DisplayEnum requirement 2. The witness is a bare `ret` — an empty body, not a missing one.
    public func touchesMoved(touch: UITouch) {}

    // Slot 32 @0x101a81f08, 51 instructions. PRIVATE in the binary (the mangled name carries a
    // private discriminator) and NOT a protocol requirement. It takes the pixel buffer
    // existential and reads both selectors off it itself — `planeCount` through witness slot 4
    // (wt+0x28) and `bitDepth` through slot 2 (wt+0x18), which match PixelBufferProtocol's
    // declaration order. The previous `(planeCount:bitDepth:)` spelling is a real trie negative.
    // The selection itself is unchanged; only the parameter shape moved.
    private func pipeline(pixelBuffer: PixelBufferProtocol) -> MTLRenderPipelineState {
        switch pixelBuffer.planeCount {
        case 3:
            if pixelBuffer.bitDepth == 10 {
                return yuvp010LE
            } else {
                return yuv
            }
        case 2:
            if pixelBuffer.bitDepth == 10 {
                return p010LE
            } else {
                return nv12
            }
        default:
            return bgra
        }
    }
}

@MainActor
public class SphereDisplayModel: DisplayEnum {
    // DisplayEnum requirement 0, stored at offset 0x38 with a declaration default, exactly as on
    // PlaneDisplayModel. NOTE its getter is NOT in the trie — only Plane's is — so the address
    // 0x10002c740 (`mov w0,#1; ret`) is anchored solely by this class's witness table.
    public nonisolated let isSphere = true

    private lazy var yuv = MetalRender.makePipelineState(vertexFunction: "mapSphereTexture", fragmentFunction: "displayYUVTexture")
    private lazy var yuvp010LE = MetalRender.makePipelineState(vertexFunction: "mapSphereTexture", fragmentFunction: "displayYUVTexture", bitDepth: 10)
    private lazy var nv12 = MetalRender.makePipelineState(vertexFunction: "mapSphereTexture", fragmentFunction: "displayNV12Texture")
    private lazy var p010LE = MetalRender.makePipelineState(vertexFunction: "mapSphereTexture", fragmentFunction: "displayNV12Texture", bitDepth: 10)
    private lazy var bgra = MetalRender.makePipelineState(vertexFunction: "mapSphereTexture", fragmentFunction: "displayTexture")
    private var fingerRotationX = Float(0)
    private var fingerRotationY = Float(0)
    fileprivate var modelViewMatrix = matrix_identity_float4x4
    let indexCount: Int
    let indexType = MTLIndexType.uint16
    let primitiveType = MTLPrimitiveType.triangle
    let indexBuffer: MTLBuffer
    let posBuffer: MTLBuffer?
    let uvBuffer: MTLBuffer?
    @MainActor
    fileprivate init() {
        let (indices, positions, uvs) = SphereDisplayModel.genSphere()
        let device = MetalRender.device
        indexCount = indices.count
        indexBuffer = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt16>.size * indexCount)!
        posBuffer = device.makeBuffer(bytes: positions, length: MemoryLayout<simd_float4>.size * positions.count)
        uvBuffer = device.makeBuffer(bytes: uvs, length: MemoryLayout<simd_float2>.size * uvs.count)
        #if canImport(UIKit) && canImport(CoreMotion)
        if KSOptions.enableSensor {
            MotionSensor.shared.start()
        }
        #endif
    }

    // Slot 51 @0x101a8c200, 88 instructions. Its first five statements are Plane's, then the two
    // vertex buffers this class does keep. Unlike Plane it issues NO DRAW CALL AT ALL —
    // independently verified: zero drawPrimitives/drawIndexedPrimitives stub calls appear in
    // 0x101a8c200-0x101a8c360. The draw lives in the VR subclasses below, which is consistent.
    //
    // The three leading statements had no counterpart in the previous reconstruction; the four
    // it did have were a strict subset. Field offsets confirm the vertex buffers:
    // posBuffer@0xb0 at index 0, uvBuffer@0xb8 at index 1.
    //
    // The sensor tail is gated on the global `static KSPlayer.KSOptions.enableSensor`
    // (0x1044e5150) and, when the provider returns a non-nil Optional, copies 0x40 bytes into
    // self+0x50 = modelViewMatrix — the only stored field either set() body writes. The provider
    // 0x101a880e4 exports no symbol and has no thunk route, but the existing spelling matches its
    // shape exactly (enableSensor gate, Optional-returning call, assign).
    // ⚑[tool=export_trie_oracle ref=sensor_matrix_provider:0x101a880e4 result=NOT_IN_TRIE]
    public func set(frame: VideoVTBFrame, encoder: MTLRenderCommandEncoder) {
        // No unwrap: VideoVTBFrame.pixelBuffer is a non-optional `let` in the source now too, so
        // this matches the binary, which loads the field with no nil check.
        let pixelBuffer = frame.pixelBuffer
        let state = pipeline(pixelBuffer: pixelBuffer)
        encoder.setRenderPipelineState(state)
        MetalRender.setFragmentBuffer(encoder: encoder, pixelBuffer: pixelBuffer)
        encoder.setFragmentBuffer(frame.adjustBuffer, offset: 0, index: 3)
        encoder.setFrontFacing(.clockwise)
        encoder.setVertexBuffer(posBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uvBuffer, offset: 0, index: 1)
        #if canImport(UIKit) && canImport(CoreMotion)
        if KSOptions.enableSensor, let matrix = MotionSensor.shared.matrix() {
            modelViewMatrix = matrix
        }
        #endif
    }

    @MainActor
    public func touchesMoved(touch: UITouch) {
        #if canImport(UIKit)
        let view = touch.view
        #else
        let view: UIView? = nil
        #endif
        var distX = Float(touch.location(in: view).x - touch.previousLocation(in: view).x)
        var distY = Float(touch.location(in: view).y - touch.previousLocation(in: view).y)
        distX *= 0.005
        distY *= 0.005
        fingerRotationX -= distY * 60 / 100
        fingerRotationY -= distX * 60 / 100
        modelViewMatrix = matrix_identity_float4x4.rotateX(radians: fingerRotationX).rotateY(radians: fingerRotationY)
    }

    func reset() {
        fingerRotationX = 0
        fingerRotationY = 0
        modelViewMatrix = matrix_identity_float4x4
    }

    private static func genSphere() -> ([UInt16], [simd_float4], [simd_float2]) {
        let slicesCount = UInt16(200)
        let parallelsCount = slicesCount / 2
        let indicesCount = Int(slicesCount) * Int(parallelsCount) * 6
        var indices = [UInt16](repeating: 0, count: indicesCount)
        var positions = [simd_float4]()
        var uvs = [simd_float2]()
        var runCount = 0
        let radius = Float(1.0)
        let step = (2.0 * Float.pi) / Float(slicesCount)
        var i = UInt16(0)
        while i <= parallelsCount {
            var j = UInt16(0)
            while j <= slicesCount {
                let vertex0 = radius * sinf(step * Float(i)) * cosf(step * Float(j))
                let vertex1 = radius * cosf(step * Float(i))
                let vertex2 = radius * sinf(step * Float(i)) * sinf(step * Float(j))
                let vertex3 = Float(1.0)
                let vertex4 = Float(j) / Float(slicesCount)
                let vertex5 = Float(i) / Float(parallelsCount)
                positions.append([vertex0, vertex1, vertex2, vertex3])
                uvs.append([vertex4, vertex5])
                if i < parallelsCount, j < slicesCount {
                    indices[runCount] = i * (slicesCount + 1) + j
                    runCount += 1
                    indices[runCount] = UInt16((i + 1) * (slicesCount + 1) + j)
                    runCount += 1
                    indices[runCount] = UInt16((i + 1) * (slicesCount + 1) + (j + 1))
                    runCount += 1
                    indices[runCount] = UInt16(i * (slicesCount + 1) + j)
                    runCount += 1
                    indices[runCount] = UInt16((i + 1) * (slicesCount + 1) + (j + 1))
                    runCount += 1
                    indices[runCount] = UInt16(i * (slicesCount + 1) + (j + 1))
                    runCount += 1
                }
                j += 1
            }
            i += 1
        }
        return (indices, positions, uvs)
    }

    // Slot 50 @0x101a8c134 — the identical 51-instruction shape as Plane's helper, same
    // parameter change. Unlike Plane's, this one is a trie negative, so its name comes from the
    // structural match rather than from a symbol.
    private func pipeline(pixelBuffer: PixelBufferProtocol) -> MTLRenderPipelineState {
        switch pixelBuffer.planeCount {
        case 3:
            if pixelBuffer.bitDepth == 10 {
                return yuvp010LE
            } else {
                return yuv
            }
        case 2:
            if pixelBuffer.bitDepth == 10 {
                return p010LE
            } else {
                return nv12
            }
        default:
            return bgra
        }
    }
}

public class VRDisplayModel: SphereDisplayModel {
    private let modelViewProjectionMatrix: simd_float4x4

    override required init() {
        let size = KSOptions.sceneSize
        let aspect = Float(size.width / size.height)
        let projectionMatrix = simd_float4x4(perspective: Float.pi / 3, aspect: aspect, nearZ: 0.1, farZ: 400.0)
        let viewMatrix = simd_float4x4(lookAt: SIMD3<Float>.zero, center: [0, 0, -1000], up: [0, 1, 0])
        modelViewProjectionMatrix = projectionMatrix * viewMatrix
        super.init()
    }

    // The binary carries VRDisplayModel.set(frame:encoder:) at arity 2, so the override follows
    // its superclass's grounded signature change. The body below is unchanged.
    override public func set(frame: VideoVTBFrame, encoder: MTLRenderCommandEncoder) {
        super.set(frame: frame, encoder: encoder)
        var matrix = modelViewProjectionMatrix * modelViewMatrix
        let matrixBuffer = MetalRender.device.makeBuffer(bytes: &matrix, length: MemoryLayout<simd_float4x4>.size)
        encoder.setVertexBuffer(matrixBuffer, offset: 0, index: 2)
        encoder.drawIndexedPrimitives(type: primitiveType, indexCount: indexCount, indexType: indexType, indexBuffer: indexBuffer, indexBufferOffset: 0)
    }
}

public class VRBoxDisplayModel: SphereDisplayModel {
    private let modelViewProjectionMatrixLeft: simd_float4x4
    private let modelViewProjectionMatrixRight: simd_float4x4
    override required init() {
        let size = KSOptions.sceneSize
        let aspect = Float(size.width / size.height) / 2
        let viewMatrixLeft = simd_float4x4(lookAt: [-0.012, 0, 0], center: [0, 0, -1000], up: [0, 1, 0])
        let viewMatrixRight = simd_float4x4(lookAt: [0.012, 0, 0], center: [0, 0, -1000], up: [0, 1, 0])
        let projectionMatrix = simd_float4x4(perspective: Float.pi / 3, aspect: aspect, nearZ: 0.1, farZ: 400.0)
        modelViewProjectionMatrixLeft = projectionMatrix * viewMatrixLeft
        modelViewProjectionMatrixRight = projectionMatrix * viewMatrixRight
        super.init()
    }

    // As VRDisplayModel above: the binary carries VRBoxDisplayModel.set(frame:encoder:) at
    // arity 2. Body unchanged.
    override public func set(frame: VideoVTBFrame, encoder: MTLRenderCommandEncoder) {
        super.set(frame: frame, encoder: encoder)
        let layerSize = KSOptions.sceneSize
        let width = Double(layerSize.width / 2)
        [(modelViewProjectionMatrixLeft, MTLViewport(originX: 0, originY: 0, width: width, height: Double(layerSize.height), znear: 0, zfar: 0)),
         (modelViewProjectionMatrixRight, MTLViewport(originX: width, originY: 0, width: width, height: Double(layerSize.height), znear: 0, zfar: 0))].forEach { modelViewProjectionMatrix, viewport in
            encoder.setViewport(viewport)
            var matrix = modelViewProjectionMatrix * modelViewMatrix
            let matrixBuffer = MetalRender.device.makeBuffer(bytes: &matrix, length: MemoryLayout<simd_float4x4>.size)
            encoder.setVertexBuffer(matrixBuffer, offset: 0, index: 2)
            encoder.drawIndexedPrimitives(type: primitiveType, indexCount: indexCount, indexType: indexType, indexBuffer: indexBuffer, indexBufferOffset: 0)
        }
    }
}
