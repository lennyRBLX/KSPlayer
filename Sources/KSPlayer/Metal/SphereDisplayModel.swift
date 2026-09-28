import Foundation
import Metal
import simd
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public class SphereDisplayModel: DisplayEnum {
    // FIELD ORDER: the five lazy pipeline slots come FIRST in this class's field records
    // (indices 0-4, offsets 0x10..0x37) and isSphere is index 5 at 0x38 — the same layout
    // PlaneDisplayModel has. The declarations are ordered to match; leading with isSphere, as this
    // file previously did, put the source out of order with the binary.
    //
    // ⚠️ NAMES: these five carry a `Sphere` SUFFIX that Plane's do not, and that is not a mangling
    // artifact. Plane's records read $__lazy_storage_$_yuv / _yuvp010LE / _nv12 / _p010LE / _bgra;
    // this class's read $__lazy_storage_$_yuvSphere / _yuvp010LESphere / _nv12Sphere /
    // _p010LESphere / _bgraSphere. The text inside $__lazy_storage_$_ IS the source property name,
    // so the two classes genuinely spell these differently and the unsuffixed spelling here was
    // wrong.
    // ⚑[tool=fieldrec ref=SphereDisplayModel:0x1039f134c result=suffixed-names-confirmed]
    private lazy var yuvSphere = MetalRender.makePipelineState(fragmentFunction: "displayYUVTexture", isSphere: true)
    private lazy var yuvp010LESphere = MetalRender.makePipelineState(fragmentFunction: "displayYUVTexture", isSphere: true, bitDepth: 10)
    private lazy var nv12Sphere = MetalRender.makePipelineState(fragmentFunction: "displayNV12Texture", isSphere: true)
    private lazy var p010LESphere = MetalRender.makePipelineState(fragmentFunction: "displayNV12Texture", isSphere: true, bitDepth: 10)
    private lazy var bgraSphere = MetalRender.makePipelineState(fragmentFunction: "displayTexture", isSphere: true)

    // DisplayEnum requirement 0, stored at offset 0x38 with a declaration default, exactly as on
    // PlaneDisplayModel. NOTE its getter is NOT in the trie — only Plane's is — so the address
    // 0x10002c740 (`mov w0,#1; ret`) is anchored solely by this class's witness table.
    public nonisolated let isSphere = true
    @exclusivity(unchecked) private var fingerRotationX = Float(0)
    @exclusivity(unchecked) private var fingerRotationY = Float(0)
    @exclusivity(unchecked) fileprivate var modelViewMatrix = matrix_identity_float4x4
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

    // Slot 50 @0x101a8c134 — the identical 51-instruction shape as Plane's helper, same
    // parameter change. Unlike Plane's, this one is a trie negative, so its name comes from the
    // structural match rather than from a symbol.
    private func pipeline(pixelBuffer: PixelBufferProtocol) -> MTLRenderPipelineState {
        let planeCount = pixelBuffer.planeCount
        let bitDepth = pixelBuffer.bitDepth
        switch planeCount {
        case 3:
            if bitDepth == 10 {
                return yuvp010LESphere
            } else {
                return yuvSphere
            }
        case 2:
            if bitDepth == 10 {
                return p010LESphere
            } else {
                return nv12Sphere
            }
        default:
            return bgraSphere
        }
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

    @used func reset() {
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
        // Forward @0x101a8cba8 heap-allocates the 2-element array (allocObject 0x100) and walks it with
        // no closure-entry executor check: a for-in, not `.forEach { }`.
        for (modelViewProjectionMatrix, viewport) in [(modelViewProjectionMatrixLeft, MTLViewport(originX: 0, originY: 0, width: width, height: Double(layerSize.height), znear: 0, zfar: 0)),
                                                      (modelViewProjectionMatrixRight, MTLViewport(originX: width, originY: 0, width: width, height: Double(layerSize.height), znear: 0, zfar: 0))] {
            encoder.setViewport(viewport)
            var matrix = modelViewProjectionMatrix * modelViewMatrix
            let matrixBuffer = MetalRender.device.makeBuffer(bytes: &matrix, length: MemoryLayout<simd_float4x4>.size)
            encoder.setVertexBuffer(matrixBuffer, offset: 0, index: 2)
            encoder.drawIndexedPrimitives(type: primitiveType, indexCount: indexCount, indexType: indexType, indexBuffer: indexBuffer, indexBufferOffset: 0)
        }
    }
}
