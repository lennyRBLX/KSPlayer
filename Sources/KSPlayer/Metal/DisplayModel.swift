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
public class PlaneDisplayModel: DisplayEnum {
    private lazy var yuv = MetalRender.makePipelineState(vertexFunction: "mapTexture", fragmentFunction: "displayYUVTexture")
    private lazy var yuvp010LE = MetalRender.makePipelineState(vertexFunction: "mapTexture", fragmentFunction: "displayYUVTexture", bitDepth: 10)
    private lazy var nv12 = MetalRender.makePipelineState(vertexFunction: "mapTexture", fragmentFunction: "displayNV12Texture")
    private lazy var p010LE = MetalRender.makePipelineState(vertexFunction: "mapTexture", fragmentFunction: "displayNV12Texture", bitDepth: 10)
    private lazy var bgra = MetalRender.makePipelineState(vertexFunction: "mapTexture", fragmentFunction: "displayTexture")

    // DisplayEnum requirement 0. STORED with a declaration default, at offset 0x38 — the class's
    // field_offset_vector is 5 lazy slots (0x10..0x37) then isSphere, InstanceSize 0x39.
    public let isSphere = false

    // The six stored properties this class used to declare — indexCount, indexType,
    // primitiveType, indexBuffer, posBuffer, uvBuffer — together with genSphere() and the init
    // that filled them, are REMOVED. The binary's PlaneDisplayModel has exactly six field
    // records: the five $__lazy_storage_$_ pipeline slots plus isSphere, and no init beyond the
    // implicit one. That absence is the whole reason set(frame:encoder:) below draws
    // non-indexed: there is no index buffer to draw from.

    public init() {}

    // Slot 32 @0x101a81f08, 51 instructions. PRIVATE in the binary (the mangled name carries a
    // private discriminator) and NOT a protocol requirement. It takes the pixel buffer
    // existential and reads both selectors off it itself — `planeCount` through witness slot 4
    // (wt+0x28) and `bitDepth` through slot 2 (wt+0x18), which match PixelBufferProtocol's
    // declaration order. The previous `(planeCount:bitDepth:)` spelling is a real trie negative.
    // The selection itself is unchanged; only the parameter shape moved.
    private func pipeline(pixelBuffer: PixelBufferProtocol) -> MTLRenderPipelineState {
        let planeCount = pixelBuffer.planeCount
        let bitDepth = pixelBuffer.bitDepth
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
        default:
            return bgra
        }
    }

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
}

