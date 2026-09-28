import Foundation
import Metal
import simd
#if canImport(UIKit)
import UIKit
#endif

// ⚑ STOOD UP IN s107 so `KSOptions.displayEnumDovi` can be declared — that static's storage types
// as `KSPlayer.DoviDisplayModel` and the class was absent from Sources entirely.
//
// Superclass READ, not inferred: the class descriptor @0x1039f0f58 carries a SuperclassType
// symbolic reference of kind 0x02 (indirect) resolving to descriptor **0x1039f0e8c**, which is
// `PlaneDisplayModel`'s. It is corroborated by the once-initializer at 0x1019bc5c0, which zeroes
// exactly 0x10…0x38 (`stp q0,q0,[x0,#0x10]` + `stur q0,[x0,#0x29]`) — precisely PlaneDisplayModel's
// six field slots, whose InstanceSize is 0x39.
//
// Layout READ from the field-offset vector @0x1044ed030 (metadata_init=0, so it is static):
// InstanceSize 0x58, AlignMask 7, three own fields at 0x40 / 0x48 / 0x50. The allocation in that
// same initializer is `swift_allocObject(size: 0x58, alignMask: 7)`, which agrees.
//
// ⚑ PARTIAL, and standing this class up SURFACED its own open row — expected, not a regression:
//   declaring a type makes its undeclared members visible to pin_sweep.
//     · `set(frame:encoder:)` @0x101a825b4, 250 instr — the `DisplayEnum` requirement, an
//       OVERRIDE of PlaneDisplayModel's. Named in the trie, not yet read.
//     · slot 9 of this class's own vtable, impl 0x101a8299c, 181 instr — a PRIVATE helper taking
//       FIVE arguments (x0..x4), so it is not `set` under another name. It exports no symbol, and
//       it does String/Dictionary work, which is what `pipelineMap` above exists for.
//   `set(frame:encoder:)` is not reconstructed here. Slot 9 is now read: `pipeline(source:fragmentFunction:bitDepth:)`
//   below (internal symbol, no private discriminator).
@MainActor
public class DoviDisplayModel: PlaneDisplayModel {
    /// ⚑ Both literals are decoded, not matched to the field name:
    ///   vertexFunction — `mov`+3×`movk` give `mapTextu`, with x1 carrying `re` under count byte
    ///   0xEA (= 0xE0|10) → **"mapTexture"**, the same one PlaneDisplayModel uses.
    ///   fragmentFunction — x2 is `0xD000000000000013`, a LARGE string of 0x13 = 19 bytes, and x3
    ///   is the literal pointer biased by −0x20, so the text is at 0x103d35fc0:
    ///   **"displayICtCpTexture"**. `w4 = 0xa` is the `bitDepth:` argument.
    private lazy var iCtCp10LE = MetalRender.makePipelineState(vertexFunction: "mapTexture", fragmentFunction: "displayICtCpTexture", bitDepth: 10)

    /// ⚑ Same shape, count 0x1b = 27 bytes at 0x103d35fa0: **"displayICtCpBiPlanarTexture"**, and
    ///   `w4 = 0xa` again. The two getters differ ONLY in that literal and its length.
    private lazy var iCtCpBiPlanar10LE = MetalRender.makePipelineState(vertexFunction: "mapTexture", fragmentFunction: "displayICtCpBiPlanarTexture", bitDepth: 10)

    /// ⚑ `[:]` is read: the initializer stores `__swiftEmptyDictionarySingleton` into +0x50.
    ///   ⚑[tool=bind_oracle ref=__got:0x104112d08 result=__swiftEmptyDictionarySingleton]
    ///   An empty `Dictionary` is that non-null singleton, never 0 — so this is a real empty
    ///   literal, not a zeroed slot.
    private var pipelineMap: [String: any MTLRenderPipelineState] = [:]

    // slot 9 @0x101a8299c. key = source + fragmentFunction + bitDepth.description; miss compiles `source`
    // (newLibraryWithSource:options:nil @0x101a82b0c, try! line 44) and builds via MTLLibrary.makePipelineState
    // @0x101a83020 with "mapTexture"; stored back into pipelineMap @0x101a82bac.
    func pipeline(source: String, fragmentFunction: String, bitDepth: Int32) -> MTLRenderPipelineState {
        let key = source + fragmentFunction + String(describing: bitDepth)
        if let pipeline = pipelineMap[key] {
            return pipeline
        }
        let library = try! MetalRender.device.makeLibrary(source: source, options: nil)
        let pipeline = library.makePipelineState(vertexFunction: "mapTexture", fragmentFunction: fragmentFunction, bitDepth: bitDepth)
        pipelineMap[key] = pipeline
        return pipeline
    }
    override public func set(frame: VideoVTBFrame, encoder: MTLRenderCommandEncoder) {
        // L7 lane 4: Forward body @0x101a825b4 READ; not landed — it needs two decls outside this body:
        //   (1) the KSDOVIMetadata shader-source builder @0x101a82044 (self in x20, returns String?; emits
        //       "reshape_poly"/"appledm" Metal source) — undeclared in Sources;
        //   (2) MetalRender.leftShiftMatrixBuffer / leftShiftSixMatrixBuffer (statics 0x104c63710 / 0x104c63718)
        //       read directly here — `private` in MetalRender.swift.
        // Forward shape, for when both land:
        //   guard let doviData = frame.doviData else { super.set(frame: frame, encoder: encoder); return }
        //   var metadata = doviData
        //   let pixelBuffer = frame.pixelBuffer
        //   let planeCount = pixelBuffer.planeCount
        //   let state: MTLRenderPipelineState
        //   if metadata.disable_residual_flag != 0, let source = doviData.<builder@0x101a82044> {
        //       state = pipeline(source: source, fragmentFunction: planeCount == 3 ? "displayICtCpTexture" : "displayICtCpBiPlanarTexture", bitDepth: 10)
        //   } else {
        //       state = planeCount == 3 ? iCtCp10LE : iCtCpBiPlanar10LE
        //   }
        //   encoder.setRenderPipelineState(state)
        //   let leftShift = pixelBuffer.leftShift == 0 ? MetalRender.leftShiftMatrixBuffer : MetalRender.leftShiftSixMatrixBuffer
        //   metadata.linear = KSOptions.doviMatrix * metadata.linear
        //   let buffer = MetalRender.device.makeBuffer(bytes: &metadata, length: MemoryLayout<KSDOVIMetadata>.size)
        //   buffer?.label = "dovi"
        //   encoder.setFragmentBuffer(buffer, offset: 0, index: 0)
        //   encoder.setFragmentBuffer(leftShift, offset: 0, index: 1)
        //   encoder.setFrontFacing(.clockwise)
        //   encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        fatalError("L7: DoviDisplayModel.set — Forward body unread")
    }
}
