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

// **DoviDisplayModel is intentionally absent from this switch.** The binary swaps
// `KSOptions.display` to a DoviDisplayModel singleton (`DAT_104458878`) when DV side data
// arrives -- see .reversal/DolbyVision.md §DoviDisplayModel and §"Dynamic DoviDisplayModel
// Activation". This port keeps `DisplayEnum` strictly about geometry (plane / VR / VR-box)
// and routes the DV reshape path out-of-band via the `doviMetadata:` parameter on
// `MetalView.draw`. Rationale: the DV path needs per-frame `DoviGPUMetadata`, which doesn't
// fit a stateless enum case cleanly; and the inverted enhanceDolby semantics
// (see `KSOptions.enhanceDolby`) mean most DV content is actually rendered by AVPlayer,
// not by `DoviDisplayModel`.
//
// STRUCTURAL NOTE (binary divergence -- intentional):
// The binary implements `DisplayEnum` as a PROTOCOL (not a Swift enum) with conformer
// singletons dispatched via existential witness tables:
//
//   Plane/Dovi WT: 0x103a274f8 (descriptor 0x102ef0bf0)
//     [wt+0x08] = 0x10002a3cc (return false) -- Bool touch-enable gate
//     [wt+0x10] = 0x101466ccc -> vtable [meta+0x138] -- set(encoder:)
//     [wt+0x18] = 0x10000b080 (nullsub_2, no-op) -- touchesMoved (unreachable, gate false)
//
//   VR/VRBox WT: 0x103a27808 (descriptor 0x102ef0ea8)
//     [wt+0x08] = 0x10028e848 (return true) -- Bool touch-enable gate
//     [wt+0x10] = 0x101470df0 -> vtable [meta+0x198] -- set(encoder:)
//     [wt+0x18] = 0x101470dfc -> tail-call 0x101470b84 -- touchesMoved (handlePanGesture)
//
// This reconstruction uses a Swift enum with switch-dispatch instead. The behavior is
// equivalent: enum cases map to singleton conformers, switch arms replicate WT dispatch.
// The enum form is idiomatic Swift (simpler callsites, exhaustive switch, no existential
// boxing overhead on `KSOptions.display`). The binary's conformer singletons (PlaneDisplayModel
// at DAT_104458870, VRDisplayModel at DAT_104458880, VRBoxDisplayModel at DAT_104458888)
// are preserved as private statics below.
//
// Binary protocol requirements (3 WT slots):
//   [wt+0x08] = isInteractive (Bool gate) -> DisplayEnum.isInteractive
//   [wt+0x10] = set(encoder:)             -> DisplayEnum.set(encoder:)
//   [wt+0x18] = touchesMoved(touch:)      -> DisplayEnum.touchesMoved(touch:)
// pipeline(planeCount:bitDepth:) is NOT a WT slot -- it is class-virtual, invoked internally.
//
// The extra cases .auto and .metalPQ are reconstruction additions (not in the binary).
// Binary conformer factory typos "vrDiaplay"/"vrBoxDiaplay" corrected per auto-fix rule.
extension DisplayEnum {
    /// RE: KSOptions_createPlaneDisplayModel @ 0x1013a2f48 (singleton DAT_104458870)
    private static var planeDisplay = PlaneDisplayModel()
    /// RE: factory FUN_1013a32a0 -> FUN_1013a333c (singleton DAT_104458880, 256 bytes)
    private static var vrDisplay = VRDisplayModel()
    /// RE: factory FUN_1013a331c -> FUN_1013a333c (singleton DAT_104458888, 320 bytes)
    private static var vrBoxDisplay = VRBoxDisplayModel()

    /// RE: existential witness slot [wt+0x10] -- each conformer binds its own
    /// geometry/pipeline via class-virtual dispatch.
    func set(encoder: MTLRenderCommandEncoder) {
        switch self {
        case .plane, .auto, .metalPQ:
            DisplayEnum.planeDisplay.set(encoder: encoder)
        case .vr:
            DisplayEnum.vrDisplay.set(encoder: encoder)
        case .vrBox:
            DisplayEnum.vrBoxDisplay.set(encoder: encoder)
        }
    }

    /// RE: pipeline(planeCount:bitDepth:) -- invoked internally by set(encoder:)/drawSetup
    /// via the Sphere/VR render-pipeline dispatcher 0x101470908.
    func pipeline(planeCount: Int, bitDepth: Int32) -> MTLRenderPipelineState {
        switch self {
        case .plane, .auto, .metalPQ:
            return DisplayEnum.planeDisplay.pipeline(planeCount: planeCount, bitDepth: bitDepth)
        case .vr:
            return DisplayEnum.vrDisplay.pipeline(planeCount: planeCount, bitDepth: bitDepth)
        case .vrBox:
            return DisplayEnum.vrBoxDisplay.pipeline(planeCount: planeCount, bitDepth: bitDepth)
        }
    }

    /// RE: existential witness slot [wt+0x18] -- meaningful only for sphere/VR conformers.
    /// PlaneDisplayModel no-ops (nullsub_2 @ 0x10000b080, unreachable since the
    /// isInteractive gate is false). Sphere/VR -> DisplayModel_handlePanGesture @ 0x101470b84.
    func touchesMoved(touch: UITouch) {
        switch self {
        case .vr:
            DisplayEnum.vrDisplay.touchesMoved(touch: touch)
        case .vrBox:
            DisplayEnum.vrBoxDisplay.touchesMoved(touch: touch)
        default:
            // RE: Plane/Dovi WT [wt+0x18] = nullsub_2 @ 0x10000b080 (no-op)
            break
        }
    }
}

/// Base display model for flat-plane quad rendering (4-vertex fullscreen quad).
/// Binary: `PlaneDisplayModel` (112 bytes / 0x70). The base vertex data, pipeline
/// selection, and `set(encoder:)` call are shared by `DoviDisplayModel` and
/// `ThumbnailDoviDisplayModel` which both subclass this type.
/// RE: 0x101466cd8 (DisplayModel_initBaseVertexData, 1.3.15)
class PlaneDisplayModel {
    private lazy var yuv = MetalRender.makePipelineState(fragmentFunction: "displayYUVTexture")
    private lazy var yuvp010LE = MetalRender.makePipelineState(fragmentFunction: "displayYUVTexture", bitDepth: 10)
    private lazy var nv12 = MetalRender.makePipelineState(fragmentFunction: "displayNV12Texture")
    private lazy var p010LE = MetalRender.makePipelineState(fragmentFunction: "displayNV12Texture", bitDepth: 10)
    private lazy var bgra = MetalRender.makePipelineState(fragmentFunction: "displayTexture")
    /// Whether this model uses sphere projection vertex function (`mapSphereTexture`)
    /// instead of flat-plane (`mapTexture`). False for PlaneDisplayModel, true for
    /// SphereDisplayModel and its subclasses. Binary offset +0x38.
    /// RE: types.json field #6 on PlaneDisplayModel (shared flag set true by SphereDisplayModel)
    let isSphere: Bool
    let indexCount: Int
    let indexType = MTLIndexType.uint16
    let primitiveType = MTLPrimitiveType.triangleStrip
    let indexBuffer: MTLBuffer
    let posBuffer: MTLBuffer?
    let uvBuffer: MTLBuffer?

    /// RE: 0x101466cd8 (DisplayModel_initBaseVertexData, 1.3.15)
    /// Singleton allocated by KSOptions_createPlaneDisplayModel @ 0x1013a2f48
    init() {
        let (indices, positions, uvs) = PlaneDisplayModel.genBaseVertexData()
        let device = MetalRender.device
        isSphere = false
        indexCount = indices.count
        indexBuffer = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt16>.size * indexCount)!
        posBuffer = device.makeBuffer(bytes: positions, length: MemoryLayout<simd_float4>.size * positions.count)
        uvBuffer = device.makeBuffer(bytes: uvs, length: MemoryLayout<simd_float2>.size * uvs.count)
    }

    // Renamed from upstream's `genSphere()` -- that name is misleading because this
    // returns a 4-vertex flat quad, not a sphere. Binary uses
    // `DisplayModel_initBaseVertexData @ 0x101466cd8` (see .reversal/DisplayMetal.md
    // §PlaneDisplayModel). Reversal-doc rule: name by what it does in this codebase.
    private static func genBaseVertexData() -> ([UInt16], [simd_float4], [simd_float2]) {
        let indices: [UInt16] = [0, 1, 2, 3]
        let positions: [simd_float4] = [
            [-1.0, -1.0, 0.0, 1.0],
            [-1.0, 1.0, 0.0, 1.0],
            [1.0, -1.0, 0.0, 1.0],
            [1.0, 1.0, 0.0, 1.0],
        ]
        let uvs: [simd_float2] = [
            [0.0, 1.0],
            [0.0, 0.0],
            [1.0, 1.0],
            [1.0, 0.0],
        ]
        return (indices, positions, uvs)
    }

    /// RE: 0x101466648 (PlaneDisplayModel.set(encoder:), 1.3.15)
    func set(encoder: MTLRenderCommandEncoder) {
        encoder.setFrontFacing(.clockwise)
        encoder.setVertexBuffer(posBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uvBuffer, offset: 0, index: 1)
        encoder.drawIndexedPrimitives(type: primitiveType, indexCount: indexCount, indexType: indexType, indexBuffer: indexBuffer, indexBufferOffset: 0)
    }

    /// RE: 0x101466be0 (PlaneDisplayModel.pipeline(planeCount:bitDepth:), 1.3.15)
    /// Dispatches to exactly 5 lazy pipeline states:
    ///   3 planes, 8-bit  -> yuv
    ///   3 planes, 10-bit -> yuvp010LE
    ///   2 planes, 8-bit  -> nv12
    ///   2 planes, 10-bit -> p010LE
    ///   1 plane, any     -> bgra
    func pipeline(planeCount: Int, bitDepth: Int32) -> MTLRenderPipelineState {
        switch planeCount {
        case 3:
            if bitDepth == 10 {
                return yuvp010LE
            } else {
                return yuv
            }
        case 2:
            if bitDepth == 10 {
                return p010LE
            } else {
                return nv12
            }
        case 1:
            return bgra
        default:
            return bgra
        }
    }
}

/// 360-degree sphere display model for VR content. `@MainActor`, `private`.
/// Binary: `SphereDisplayModel` (15 stored fields, does NOT inherit PlaneDisplayModel --
/// types.json `parent` is empty). Declares its own Sphere-suffixed lazy pipeline backings
/// and geometry fields.
/// RE: 0x1014706e4 (SphereDisplayModel_init, 1.3.15)
@MainActor
private class SphereDisplayModel {
    // Binary names: $__lazy_storage_$_yuvSphere, etc. (Sphere-suffixed in binary,
    // using "Sphere" suffix here to match the binary naming convention).
    private lazy var yuvSphere = MetalRender.makePipelineState(fragmentFunction: "displayYUVTexture", isSphere: true)
    private lazy var yuvp010LESphere = MetalRender.makePipelineState(fragmentFunction: "displayYUVTexture", isSphere: true, bitDepth: 10)
    private lazy var nv12Sphere = MetalRender.makePipelineState(fragmentFunction: "displayNV12Texture", isSphere: true)
    private lazy var p010LESphere = MetalRender.makePipelineState(fragmentFunction: "displayNV12Texture", isSphere: true, bitDepth: 10)
    private lazy var bgraSphere = MetalRender.makePipelineState(fragmentFunction: "displayTexture", isSphere: true)
    /// Binary offset +0x38. Set true in SphereDisplayModel init to switch vertex function
    /// to `mapSphereTexture`. RE: types.json field #6.
    let isSphere: Bool = true
    private var fingerRotationX = Float(0)
    private var fingerRotationY = Float(0)
    fileprivate var modelViewMatrix = matrix_identity_float4x4
    let indexCount: Int
    let indexType = MTLIndexType.uint16
    let primitiveType = MTLPrimitiveType.triangle
    let indexBuffer: MTLBuffer
    let posBuffer: MTLBuffer?
    let uvBuffer: MTLBuffer?

    /// RE: 0x1014706e4 (SphereDisplayModel_init, 1.3.15)
    @MainActor
    fileprivate init() {
        let (indices, positions, uvs) = SphereDisplayModel.generateMesh()
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

    /// Shared per-frame encoder setup for geometry-projected (Sphere/VR/VRBox) display models.
    /// RE: 0x1014709d4 (DisplayModel_drawSetup, 1.3.15)
    /// Body: sets pipeline state, binds YCbCr color conversion fragment buffers (indices 0/1/2),
    /// sets front-facing winding, binds vertex buffers, and refreshes modelViewMatrix from
    /// MotionSensor if KSOptions.enableSensor is set. For non-VR sphere this is the entire
    /// set(encoder:) -- it does NOT issue drawIndexedPrimitives. VR/VRBox subclasses call
    /// this as super then add their own MVP computation and draw call.
    func set(encoder: MTLRenderCommandEncoder) {
        encoder.setFrontFacing(.clockwise)
        encoder.setVertexBuffer(posBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uvBuffer, offset: 0, index: 1)
        #if canImport(UIKit) && canImport(CoreMotion)
        if KSOptions.enableSensor, let matrix = MotionSensor.shared.matrix() {
            modelViewMatrix = matrix
        }
        #endif
    }

    /// RE: 0x101470b84 (DisplayModel_handlePanGesture, 1.3.15)
    /// Accumulates finger delta (delta * -0.005 * 60.0 / 100.0) into fingerRotationX/Y,
    /// rebuilds modelViewMatrix via rotateX/rotateY. This is the address-pinned body
    /// of the abstract SphereDisplayModel.touchesMoved(touch:).
    @MainActor
    func touchesMoved(touch: UITouch) {
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

    /// Sphere mesh generation: 201x101 vertex grid (20,301 vertices), 120,000 indices.
    /// RE: 0x1014716e0 (SphereDisplayModel_generateMesh, 1.3.15)
    /// Binary parameters: slices=200, parallels=100, radius=1.0, 6-index cells
    /// [v, v+201, v+202, v, v+202, v+1].
    private static func generateMesh() -> ([UInt16], [simd_float4], [simd_float2]) {
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

    func pipeline(planeCount: Int, bitDepth: Int32) -> MTLRenderPipelineState {
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
        case 1:
            return bgraSphere
        default:
            return bgraSphere
        }
    }
}

/// Single-eye VR with perspective projection. Extends SphereDisplayModel.
/// Binary: `VRDisplayModel` (256 bytes / 0x100).
/// RE: 0x101470e00 (VRDisplayModel_init, 1.3.15)
private class VRDisplayModel: SphereDisplayModel {
    private let modelViewProjectionMatrix: simd_float4x4

    /// RE: 0x101470e00 (VRDisplayModel_init, 1.3.15)
    /// Binary builds the perspective inline with precomputed sqrt(3) = 1.732051 = 1/tan(pi/6),
    /// confirming FOV = pi/3 (60 degrees). The standalone createPerspectiveMatrix @ 0x101471a60
    /// is DEAD (only reflection metadata reference). createLookAtMatrix @ 0x101471c90 is LIVE
    /// (4 code xrefs) -- Gram-Schmidt camera basis.
    override required init() {
        let size = KSOptions.sceneSize
        let aspect = Float(size.width / size.height)
        let projectionMatrix = simd_float4x4(perspective: Float.pi / 3, aspect: aspect, nearZ: 0.1, farZ: 400.0)
        let viewMatrix = simd_float4x4(lookAt: SIMD3<Float>.zero, center: [0, 0, -1000], up: [0, 1, 0])
        modelViewProjectionMatrix = projectionMatrix * viewMatrix
        super.init()
    }

    /// RE: 0x101470ff0 (VRDisplayModel.set(encoder:), 1.3.15)
    /// NOTE: Ghidra mis-labels this as `SphereDisplayModel_draw` -- it is actually
    /// VRDisplayModel's set(encoder:) override. Verified by vtable slot @ 0x103d0fc28
    /// and by reading modelViewProjectionMatrix @ +0xc0..+0xf8 (a VRDisplayModel-only field).
    /// Calls super (DisplayModel_drawSetup), multiplies MVP, allocates vertex buffer at
    /// index 2, then drawIndexedPrimitives.
    override func set(encoder: MTLRenderCommandEncoder) {
        super.set(encoder: encoder)
        var matrix = modelViewProjectionMatrix * modelViewMatrix
        let matrixBuffer = MetalRender.device.makeBuffer(bytes: &matrix, length: MemoryLayout<simd_float4x4>.size)
        encoder.setVertexBuffer(matrixBuffer, offset: 0, index: 2)
        encoder.drawIndexedPrimitives(type: primitiveType, indexCount: indexCount, indexType: indexType, indexBuffer: indexBuffer, indexBufferOffset: 0)
    }
}

/// Side-by-side stereoscopic VR (cardboard-style). Extends SphereDisplayModel.
/// Binary: `VRBoxDisplayModel` (320 bytes / 0x140). Renders the scene twice
/// with per-eye offset positions (IPD = 0.024 world units).
/// RE: 0x101471158 (VRDisplayModel_setupGeometry -- actually VRBoxDisplayModel init, 1.3.15)
private class VRBoxDisplayModel: SphereDisplayModel {
    private let modelViewProjectionMatrixLeft: simd_float4x4
    private let modelViewProjectionMatrixRight: simd_float4x4

    /// RE: 0x101471158 (VRBoxDisplayModel.init, 1.3.15)
    /// NOTE: Ghidra labels this `VRDisplayModel_setupGeometry` but it is actually
    /// VRBoxDisplayModel's designated init. Verified by: (1) .vrBox factory builds
    /// a 320-byte object via this init, (2) body computes halved aspect and two eye MVPs,
    /// (3) VRBoxDisplayModel_draw @ 0x10147142c consumes both +0xc0 and +0x100 matrices.
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

    /// RE: 0x10147142c (VRBoxDisplayModel_draw, 1.3.15)
    /// Calls super (DisplayModel_drawSetup), then loops twice with per-eye setViewport
    /// + per-eye MVP blocks (+0xc0 / +0x100), allocating a transient 0x40-byte vertex
    /// buffer (index 2) for each eye's MVP.
    override func set(encoder: MTLRenderCommandEncoder) {
        super.set(encoder: encoder)
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
