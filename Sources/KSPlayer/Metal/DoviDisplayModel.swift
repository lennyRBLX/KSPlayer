import DOVIRPUShim
import Foundation
import Metal
import simd
#if canImport(UIKit)
import UIKit
#endif

// L7 lane 15: class first (pipeline try! = line 44, `mov w4,#0x2c` @0x101a82c64; .o order set < pipeline < mmrShader). Notes below.
public class DoviDisplayModel: PlaneDisplayModel {
    private lazy var iCtCp10LE = MetalRender.makePipelineState(vertexFunction: "mapTexture", fragmentFunction: "displayICtCpTexture", bitDepth: 10)
    private lazy var iCtCpBiPlanar10LE = MetalRender.makePipelineState(vertexFunction: "mapTexture", fragmentFunction: "displayICtCpBiPlanarTexture", bitDepth: 10)
    private var pipelineMap: [String: any MTLRenderPipelineState] = [:]
    override public func set(frame: VideoVTBFrame, encoder: MTLRenderCommandEncoder) {
        guard let doviData = frame.doviData else {
            super.set(frame: frame, encoder: encoder)
            return
        }
        var metadata = doviData
        let pixelBuffer = frame.pixelBuffer
        let planeCount = pixelBuffer.planeCount
        let state: MTLRenderPipelineState
        if metadata.disable_residual_flag != 0, let source = doviData.shaderSource {
            state = pipeline(source: source, fragmentFunction: planeCount == 3 ? "displayICtCpTexture" : "displayICtCpBiPlanarTexture", bitDepth: 10)
        } else {
            state = planeCount == 3 ? iCtCp10LE : iCtCpBiPlanar10LE
        }
        encoder.setRenderPipelineState(state)
        let leftShift = pixelBuffer.leftShift == 0 ? MetalRender.leftShiftMatrixBuffer : MetalRender.leftShiftSixMatrixBuffer
        metadata.linear = KSOptions.doviMatrix * metadata.linear
        let buffer = MetalRender.device.makeBuffer(bytes: &metadata, length: MemoryLayout<KSDOVIMetadata>.size)
        buffer?.label = "dovi"
        encoder.setFragmentBuffer(buffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(leftShift, offset: 0, index: 1)
        encoder.setFrontFacing(.clockwise)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
    // slot 9 @0x101a8299c; notes below the class.
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
}

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
//   `set(frame:encoder:)` is now read (L7 lane 12). Slot 9 is now read: `pipeline(source:fragmentFunction:bitDepth:)`
//   below (internal symbol, no private discriminator).
// ----- member notes (moved below the class, L7 lane 15) -----
// iCtCp10LE:
    /// ⚑ Both literals are decoded, not matched to the field name:
    ///   vertexFunction — `mov`+3×`movk` give `mapTextu`, with x1 carrying `re` under count byte
    ///   0xEA (= 0xE0|10) → **"mapTexture"**, the same one PlaneDisplayModel uses.
    ///   fragmentFunction — x2 is `0xD000000000000013`, a LARGE string of 0x13 = 19 bytes, and x3
    ///   is the literal pointer biased by −0x20, so the text is at 0x103d35fc0:
    ///   **"displayICtCpTexture"**. `w4 = 0xa` is the `bitDepth:` argument.
// iCtCpBiPlanar10LE:
    /// ⚑ Same shape, count 0x1b = 27 bytes at 0x103d35fa0: **"displayICtCpBiPlanarTexture"**, and
    ///   `w4 = 0xa` again. The two getters differ ONLY in that literal and its length.
// pipelineMap:
    /// ⚑ `[:]` is read: the initializer stores `__swiftEmptyDictionarySingleton` into +0x50.
    ///   ⚑[tool=bind_oracle ref=__got:0x104112d08 result=__swiftEmptyDictionarySingleton]
    ///   An empty `Dictionary` is that non-null singleton, never 0 — so this is a real empty
    ///   literal, not a zeroed slot.
// pipeline(source:fragmentFunction:bitDepth:):
    // slot 9 @0x101a8299c. key = source + fragmentFunction + bitDepth.description; miss compiles `source`
    // (newLibraryWithSource:options:nil @0x101a82b0c, try! line 44 — kept on line 44 above) and builds via MTLLibrary.makePipelineState
    // @0x101a83020 with "mapTexture"; stored back into pipelineMap @0x101a82bac.
// set(frame:encoder:):
    // L7 lane 12: Forward 0x101a825b4 (250 insns). The nil branch is PlaneDisplayModel.set inlined (its private
    // pipeline(pixelBuffer:) 0x101a81f08, MetalRender.setFragmentBuffer 0x101a86ea4, adjustBuffer at index 3).
    // Pixel-buffer witnesses: planeCount wt+0x28, then leftShift wt+0x20 after setRenderPipelineState.
    // "displayICtCpTexture" (0x13 B @0x103d35fc0) when planeCount == 3, else "displayICtCpBiPlanarTexture" (0x1b B @0x103d35fa0).

// L7 lane 12: KSDOVIMetadata shader-source builder, Forward 0x101a82044 (246 insns; the first function of
// DoviDisplayModel.o by the sorted-.o layout, so it precedes the class). Called only by DoviDisplayModel.set
// @0x101a826e4 with x20 = the unwrapped doviData (self, indirect) and no other args; the caller tests x1 for nil,
// so the result is String?, although every Forward path returns a value. No trie symbol / discriminator:
// name INFERRED. Literals read from Forward: header 0x9d5 B @0x103d38530, footer 0x9b2 B @0x103d38f80,
// per-comp pieces @0x103d38f10 / 0x103d38f30 / 0x103d38f60 / 0x103d39940 / 0x103d39960 / 0x103d399b0.
// The comps go through a 3-element array literal (swift_allocObject 0xb30 + three 0x3b0 memcpys from +0xb0/+0x460/+0x810).
extension KSDOVIMetadata {
    // INFERRED name (Forward 0x101a82044, no symbol)
    var shaderSource: String? {
        var source = """
        #include <metal_stdlib>
        using namespace metal;

        inline float3 pqEOTF(float3 rgb) {
        rgb = pow(max(rgb,0.0), float3(4096.0/(2523 * 128)));
        rgb = max(rgb - float3(3424./4096), 0.0) / (float3(2413./4096 * 32) - float3(2392./4096 * 32) * rgb);
        rgb = pow(rgb, float3(4096.0 * 4 / 2610));
        return rgb;
        }

        inline float pqEOTFScalar(float rgb) {
        rgb = pow(max(rgb,0.0), float(4096.0/(2523 * 128)));
        rgb = max(rgb - float(3424./4096), 0.0) / (float(2413./4096 * 32) - float(2392./4096 * 32) * rgb);
        rgb = pow(rgb, float(4096.0 * 4 / 2610));
        return rgb;
        }

        inline float3 pqOETF(float3 rgb) {
        rgb = pow(max(rgb,0.0), float3(2610./4096 / 4));
        rgb = (float3(3424./4096) + float3(2413./4096 * 32) * rgb) / (float3(1.0) + float3(2392./4096 * 32) * rgb);
        rgb = pow(rgb, float3(2523./4096 * 128));
        return rgb;
        }

        struct VertexIn
        {
        float4 pos [[attribute(0)]];
        float2 uv [[attribute(1)]];
        };

        struct VertexOut {
        float4 renderedCoordinate [[position]];
        float2 textureCoordinate;
        };

        // Triangle Strip
        constant float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
        };
        // 对应纹理坐标
        constant float2 uvs[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
        };
        vertex VertexOut mapTexture(uint vertexID [[vertex_id]]) {
        VertexOut outVertex;
        outVertex.renderedCoordinate = float4(positions[vertexID], 0.0, 1.0);
        outVertex.textureCoordinate = uvs[vertexID];
        return outVertex;
        }

        struct dovi_metadata {
        uint8_t disable_residual_flag;
        // Colorspace transformation metadata
        float3x3 nonlinear;     // before PQ, also called "ycc_to_rgb"
        float3x3 linear;        // after PQ, also called "rgb_to_lms"
        simd_float3 nonlinear_offset;  // input offset ("ycc_to_rgb_offset")
        float minLuminance;
        float maxLuminance;
        struct dm_data {
        float min_pq;
        float max_pq;
        float avg_pq;
        float target_max_pq;
        float slope;
        float offset;
        float power;
        float chroma_weight;
        float saturation_gain;
        float ms_weight;
        } dm;
        struct reshape_data {
        float4 coeffs[8];
        float4 mmr[8*6];
        float pivots[7];
        float lo;
        float hi;
        uint8_t min_order;
        uint8_t max_order;
        uint8_t num_pivots;
        bool has_poly;
        bool has_mmr;
        bool mmr_single;
        } comp[3];
        };

        float reshape_poly(float s, float4 coeffs)
        {
        s = (coeffs.z * s + coeffs.y) * s + coeffs.x;
        return s;
        }

        #define pivot(i) float4(bool4(s >= data.pivots[i]))
        #define coef(i) data.coeffs[i]
        float3 reshape3(float3 rgb, constant dovi_metadata::reshape_data datas[3]) {
        float3 sig = clamp(rgb, 0.0, 1.0);
        float s;
        float4 coeffs;
        dovi_metadata::reshape_data data;

        """
        for (i, data) in [comp.0, comp.1, comp.2].enumerated() {
            source += "s = sig[\(i)];\ndata = datas[\(i)];\n"
            source += data.num_pivots > 2 ? "coeffs = mix(mix(mix(coef(0), coef(1), pivot(0)),\n             mix(coef(2), coef(3), pivot(2)),\n             pivot(1)),\n         mix(mix(coef(4), coef(5), pivot(4)),\n             mix(coef(6), coef(7), pivot(6)),\n             pivot(5)),\n         pivot(3));\n" : "coeffs = data.coeffs[0];\n"
            if data.has_poly {
                if data.has_mmr {
                    source += "if (coeffs.w == 0.0) {\n    s = reshape_poly(s, coeffs);\n} else {\n    \(data.mmrShader)\n}\n"
                } else {
                    source += "s = reshape_poly(s, coeffs);\n"
                }
            } else {
                source += "{\n    \(data.mmrShader)\n}\n"
            }
            source += "rgb[\(i)] = clamp(s, data.lo, data.hi);\n"
        }
        source += "return rgb;\n}\n"
        source += """

        inline float3 appledm(float3 rgb, dovi_metadata::dm_data data) {
            float luma = dot(rgb, float3(0.2627, 0.6780, 0.0593));
            float sceneMaxNits = pqEOTFScalar(data.max_pq);
            float y = luma / sceneMaxNits;
            y = y * data.slope + data.offset;
            y = pow(clamp(y, 0.0, 1.0), data.power);
            if (abs(data.ms_weight) > 1e-4) {
                float midPoint = pqEOTFScalar(data.avg_pq) / sceneMaxNits;
                float shift = data.ms_weight * (y - midPoint) * (1.0 - y) * y;
                y += shift;
            }
            rgb *= y / luma;
            if (abs(data.chroma_weight - 1.0) > 1e-4) {
                float Yfinal = dot(rgb, float3(0.2627, 0.6780, 0.0593));
                rgb = Yfinal + (rgb - Yfinal) * data.chroma_weight;
            }
            return rgb;
        }

        inline float3 process(float3 rgb, constant dovi_metadata& data) {
            rgb = reshape3(rgb, data.comp);
            rgb = data.nonlinear*(rgb + data.nonlinear_offset);
            rgb = pqEOTF(rgb);
            rgb = data.linear*rgb;
            // rgb = appledm(rgb, data.dm);
            rgb = pqOETF(rgb);
            return rgb;
        }

        fragment float4 displayICtCpTexture(VertexOut in [[ stage_in ]],
                                    texture2d<half> yTexture [[ texture(0) ]],
                                    texture2d<half> uTexture [[ texture(1) ]],
                                    texture2d<half> vTexture [[ texture(2) ]],
                                    sampler textureSampler [[ sampler(0) ]],
                                    constant dovi_metadata& data [[ buffer(0) ]],
                                    constant uchar3& leftShift [[ buffer(1) ]])
        {
        float3 rgb;
        rgb.x = yTexture.sample(textureSampler, in.textureCoordinate).r;
        rgb.y = uTexture.sample(textureSampler, in.textureCoordinate).r;
        rgb.z = vTexture.sample(textureSampler, in.textureCoordinate).r;
        rgb = rgb*float3(leftShift);
        return float4(process(rgb, data), 1);
        }

        fragment float4 displayICtCpBiPlanarTexture(VertexOut in [[ stage_in ]],
                                            texture2d<half> lumaTexture [[ texture(0) ]],
                                            texture2d<half> chromaTexture [[ texture(1) ]],
                                            sampler textureSampler [[ sampler(0) ]],
                                            constant dovi_metadata& data [[ buffer(0) ]],
                                            constant uchar3& leftShift [[ buffer(1) ]])
        {
        float3 rgb;
        rgb.x = lumaTexture.sample(textureSampler, in.textureCoordinate).r;
        rgb.yz = float2(chromaTexture.sample(textureSampler, in.textureCoordinate).rg);
        rgb = rgb*float3(leftShift);
        return float4(process(rgb, data), 1);
        }
        """
        return source
    }
}

// L7 lane 12: KSDOVIReshapeData MMR shader piece, Forward 0x101a82d08 (107 insns; emitted after
// DoviDisplayModel.pipeline in DoviDisplayModel.o). Called only by the builder above (@0x101a82170, x20 = &data,
// returns String). Reads mmr_single +0x3a9, max_order +0x3a5, min_order +0x3a4. Literals @0x103d39ac0 / 0x103d39ce0 /
// 0x103d39ae0 / 0x103d39cc0 / 0x103d39ca0 / 0x103d39b90 / 0x103d39c80 / 0x103d39c20. No symbol: name INFERRED.
extension KSDOVIReshapeData {
    // INFERRED name (Forward 0x101a82d08, no symbol)
    var mmrShader: String {
        var source = ""
        source += mmr_single ? "uint mmr_idx = 0;" : "uint mmr_idx = coeffs.y;"
        source += "\nfloat4 sigX;\ns = coeffs.x;\nsigX.xyz = sig.xxy * sig.yzz;\nsigX.w = sigX.x * sig.z;\ns += dot(data.mmr[mmr_idx + 0].xyz, sig);\ns += dot(data.mmr[mmr_idx + 1], sigX);"
        if max_order >= 2 {
            if min_order < max_order {
                source += "uint order = uint(coeffs.w);"
            }
            if min_order < 2 {
                source += "if (order >= 2) {"
            }
            source += "float3 sig2 = sig * sig;\nfloat4 sigX2 = sigX * sigX;\ns += dot(data.mmr[mmr_idx + 2].xyz, sig2);\ns += dot(data.mmr[mmr_idx + 3], sigX2);"
            if max_order == 3 {
                if min_order < 3 {
                    source += "if (order >= 3) {"
                }
                source += "s += dot(data.mmr[mmr_idx + 4].xyz, sig2 * sig);\ns += dot(data.mmr[mmr_idx + 5], sigX2 * sigX);"
                if min_order < 3 {
                    source += "}"
                }
            }
            if min_order < 2 {
                source += "}"
            }
        }
        return source
    }
}
