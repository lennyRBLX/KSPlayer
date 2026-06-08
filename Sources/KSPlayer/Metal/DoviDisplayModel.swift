// DoviDisplayModel.swift
// KSPlayer — Metal DV Renderer
//
// Dolby Vision Metal renderer with runtime MSL shader generation.
// Reconstructed from v1.3.15 binary analysis.
//
// RE sources:
//   .reversal/DisplayMetal.md §DoviDisplayModel
//   .reversal/DolbyVision.md §"dovi_metadata Struct"
//   Binary: DoviDisplayModel at 0x88 (136 bytes), subclass of PlaneDisplayModel (0x70 / 112 bytes)
//
// Architecture:
//   FFmpeg AVDOVIMetadata → DOVIFrameMetadata (header, mapping, color pointers)
//     → DoviGPUMetadata (3008 bytes, packed for GPU)
//       → DoviDisplayModel.draw() → runtime MSL shader → Metal GPU
//
// Shader pipeline (from embedded MSL `process()` function):
//   reshape3(rgb, data.comp)
//   → data.nonlinear * (rgb + data.nonlinear_offset)
//   → pqEOTF(rgb)
//   → data.linear * rgb
//   → pqOETF(rgb)

import Foundation
import Metal
import simd

// MARK: - GPU Metadata Layout (matches MSL struct dovi_metadata)

/// Per-channel reshape data for GPU. Matches MSL `reshape_data` exactly.
/// sizeof = 944 bytes per component (3 total = 2832 bytes)
public struct DoviReshapeData {
    /// Polynomial coefficients for up to 8 segments [float4 x 8 = 128 bytes]
    public var coeffs: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
                        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) =
        (.zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero)
    /// MMR coefficient matrices [float4 x 48 = 768 bytes] (8 segments x 6 terms)
    public var mmr: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
                     SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
                     SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
                     SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
                     SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
                     SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
                     SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
                     SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) =
        (.zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
         .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
         .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
         .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero)
    /// Pivot boundaries [float x 7 = 28 bytes]
    public var pivots: (Float, Float, Float, Float, Float, Float, Float) = (0, 0, 0, 0, 0, 0, 0)
    /// Clamp range
    public var lo: Float = 0
    public var hi: Float = 1
    /// Mode flags
    public var minOrder: UInt8 = 0
    public var maxOrder: UInt8 = 0
    public var numPivots: UInt8 = 0
    public var hasPoly: Bool = false
    public var hasMMR: Bool = false
    public var mmrSingle: Bool = false
}

/// Display-management slot. The shader's `process()` does **not** reference these
/// fields, but the binary's `dovi_metadata` struct reserves 40 bytes here to land the
/// per-component reshape blocks at the Ghidra-verified offset 176. Treat the field
/// names as best-guess from libdovi DM nomenclature; only the 40-byte budget is
/// authoritative.
public struct DoviDMData {
    public var minPQ: Float = 0
    public var maxPQ: Float = 0
    public var avgPQ: Float = 0
    public var targetMaxPQ: Float = 0
    public var slope: Float = 1
    public var offset: Float = 0
    public var power: Float = 1
    public var chromaWeight: Float = 1
    public var saturationGain: Float = 1
    public var msWeight: Float = 0
}

/// Full GPU metadata buffer layout. Mirrors the binary's `dovi_metadata` struct that is
/// uploaded as Metal fragment buffer(0).
///
/// **Layout (Ghidra-verified):** per `.reversal/DolbyVision.md` the buffer is 3008 bytes
/// (0xBC0) with a **176-byte header** and three 944-byte per-component reshape blocks at
/// offsets 176 / 1120 / 2064. The `linear` matrix lives at header offsets 64..111.
///
/// The byte at offset 0 is the **reshape-presence** flag: when zero the binary picks a
/// static cached pipeline; when nonzero it generates a per-frame reshape shader. This is
/// the **inverse polarity** of FFmpeg's `disable_residual_flag`.
public struct DoviGPUMetadata {
    /// Reshape-presence flag (binary semantics). When `0`, draw uses the static cached
    /// pipeline; when nonzero, draw runs the dynamic reshape shader.
    public var hasReshape: UInt8 = 0
    // Padding to 16-byte alignment for the following float3x3 slot.
    private var _pad0: UInt8 = 0
    private var _pad1: UInt8 = 0
    private var _pad2: UInt8 = 0
    private var _pad3: UInt32 = 0
    private var _pad4: UInt32 = 0
    private var _pad5: UInt32 = 0
    /// YCC-to-RGB matrix (applied before PQ EOTF, in PQ domain). Header offset 16..63.
    public var nonlinear: matrix_float3x3 = matrix_identity_float3x3
    /// RGB-to-LMS matrix (applied after PQ EOTF, in linear domain). Header offset 64..111.
    /// **Ghidra-verified offset** -- the binary's NEON matrix multiply reads/writes here.
    public var linear: matrix_float3x3 = matrix_identity_float3x3
    /// Input offset applied before nonlinear matrix. Header offset 112..127 (float3 in float4 slot).
    public var nonlinearOffset: SIMD3<Float> = .zero
    /// Header offset 128.
    public var minLuminance: Float = 0
    /// Header offset 132.
    public var maxLuminance: Float = 10000
    /// 40-byte slot at header offsets 136..175.
    public var dm: DoviDMData = DoviDMData()
    /// Per-channel reshape data [3 components]. Offsets 176 / 1120 / 2064.
    public var comp: (DoviReshapeData, DoviReshapeData, DoviReshapeData) =
        (DoviReshapeData(), DoviReshapeData(), DoviReshapeData())
}

// MARK: - Pixel Format

public enum DoviPixelFormat: Int, Sendable {
    case nv12 = 2      // YUV/NV12 biplanar
    case ictcp = 3     // ICtCp (Dolby Vision perceptual color space)
}

// MARK: - Display Color Matrix (global singleton)

/// Display-side color adaptation matrix; pre-multiplied into the `linear` matrix on
/// the CPU before the metadata buffer is uploaded to the GPU.
///
/// In the binary this is the global at `DAT_104458840..10445886F` (48 bytes,
/// 3 x float4 columns; guarded by `_swift_beginAccess(&DAT_104458840, ...)`).
/// **Initial value (Ghidra-verified): identity.** The lazy initializer
/// `FUN_1013a2d80` copies from the constant blob at `_DAT_102ee9340` encoding identity.
///
/// The binary exposes a public setter (`FUN_1013a2e64`) that writes 48 bytes under
/// `_swift_beginAccess(..., 1, 0)`. As shipped, the matrix stays identity for the
/// entire process lifetime.
private var _displayColorMatrix: matrix_float3x3 = matrix_identity_float3x3

/// RE: 0x1013a2d80 (displayColorMatrix lazy init, 1.3.15)
/// RE: 0x1013a2e64 (displayColorMatrix setter, 1.3.15)
public enum DisplayColorMatrix {
    /// Read the current display color matrix.
    public static var matrix: matrix_float3x3 {
        _displayColorMatrix
    }

    /// Set the display color matrix. Binary: `FUN_1013a2e64`.
    /// Writes 48 bytes to `DAT_104458840` under `_swift_beginAccess`.
    public static func setMatrix(_ value: matrix_float3x3) {
        _displayColorMatrix = value
    }
}

// MARK: - Reshape-Mode Discriminant

/// DV reshape-mode discriminant function.
///
/// Reads the byte at blob offset `+0x457` (blob-relative `0x3d7`) and returns:
/// - `0`: no-DV / passthrough
/// - `1`: plane fallback (drawStandard)
/// - `N > 1`: reshape mode
///
/// The binary reads `frame[+0x457]` via raw pointer arithmetic on the 3008-byte (0xBC0)
/// DoviData blob. This function takes `UnsafeRawPointer` to match that access pattern --
/// callers are responsible for ensuring the pointer addresses at least 0xBC0 bytes
/// (the fixed blob size copied by `memcpy(stack, frame+0x80, 0xbc0)`).
///
/// Used by `DoviDisplayModel.draw`, `ThumbnailDoviDisplayModel.draw`, and the EDR routine.
/// `MetalPlayView_checkRenderDataFlags` at `0x10136faa4` is byte-identical.
///
/// RE: 0x101415b68 (FUN_101415b68, 1.3.15)
func doviReshapeModeDiscriminant(_ blob: UnsafeRawPointer) -> Int {
    let tag = Int(blob.load(fromByteOffset: 0x457, as: UInt8.self))
    if tag > 1 {
        // Binary: `(frame[+0x457] + 0x7ffffffe) & 0x7fffffff) + 1`
        // This preserves values > 1 as-is for reshape mode selection.
        return ((tag &+ 0x7fff_fffe) & 0x7fff_ffff) &+ 1
    }
    return 0
}

// MARK: - DoviDisplayModel

/// Dolby Vision Metal display model with per-frame MSL shader generation.
///
/// **Binary layout:** 136 bytes (0x88), subclass of `PlaneDisplayModel` (112 bytes / 0x70).
/// Added fields beyond PlaneDisplayModel:
///   - `iCtCp10LE` at +0x70: lazy ICtCp YUV-plane DV pipeline (10-bit)
///   - `iCtCpBiPlanar10LE` at +0x78: lazy ICtCp NV12/bi-planar DV pipeline (10-bit)
///   - `pipelineMap` at +0x80: per-frame-keyed reshape pipeline cache
///
/// RE: 0x1013a30cc (KSOptions_createDoviDisplayModel allocation, 1.3.15)
public class DoviDisplayModel: PlaneDisplayModel {

    // MARK: - Added fields (beyond PlaneDisplayModel's 0x70 layout)

    /// Lazy ICtCp YUV-plane DV pipeline state (10-bit, planeCount == 3).
    /// Binary: +0x70, initialized via FUN_10146725c using MetalRender_buildRenderPipelineState
    /// with fragment descriptor at 0x1033376f0.
    /// RE: 0x10146725c (iCtCp10LE lazy init, 1.3.15)
    private var iCtCp10LE: MTLRenderPipelineState?

    /// Lazy ICtCp NV12/bi-planar DV pipeline state (10-bit, planeCount != 3).
    /// Binary: +0x78, initialized via FUN_101467328 with fragment function
    /// "displayICtCpBiPlanarTexture" (length 0x1b=27).
    /// RE: 0x101467328 (iCtCpBiPlanar10LE lazy init, 1.3.15)
    private var iCtCpBiPlanar10LE: MTLRenderPipelineState?

    /// Per-frame-keyed reshape pipeline cache. Binary keys by the generated MSL source
    /// string (not by fragment name + bitDepth), since each RPU produces unique shader code.
    /// Binary: +0x80, `[String : MTLRenderPipelineState]`.
    /// RE: 0x10146782c (DoviDisplayModel_compileOrCacheShader, 1.3.15)
    private var pipelineMap: [String: MTLRenderPipelineState] = [:]

    // MARK: - Draw

    /// Main render entry point. Called once per frame.
    ///
    /// Implements the binary's 9-step DV draw pipeline:
    /// 1. Extract RPU blob (3008 bytes, 0xBC0)
    /// 2. Read reshape-mode discriminant via FUN_101415b68
    ///    - discriminant == 1 -> PlaneDisplayModel fallback (drawStandard)
    ///    - discriminant > 1 -> reshape mode
    /// 3. Select fragment function by pixelFormat
    /// 4. Set fragment buffers in DV-specific layout: dovi@0, leftShift@1
    ///    (Distinct from the standard path's MetalRender_setYCbCrColorConversionFragmentBuffers
    ///    which binds matrix@0 / colorOffset@1 / leftShift@2 / self+0x48@3.
    ///    The DV path uses only 2 fragment buffers vs the standard path's 4.)
    /// 5. Per-frame RPU->reshape-matrix transform (displayColorMatrix * linear)
    /// 6. Generate reshape shader / select static pipeline
    /// 7. Compile/cache shader
    /// 8. Encode draw call
    /// 9. ICtCp color space rendering with DV tone mapping
    ///
    /// RE: 0x1014673f4 (DoviDisplayModel_draw, 1.3.15)
    public func draw(encoder: MTLRenderCommandEncoder, metadata: DoviGPUMetadata,
                     pixelFormat: DoviPixelFormat, bitDepth: Int32, textures: [MTLTexture]) {

        // Step 2: reshape-mode discriminant check.
        // The binary reads the discriminant from the 3008-byte blob. When the discriminant
        // is 1, it routes to PlaneDisplayModel's standard draw (plane fallback) and returns.
        // Since we receive pre-parsed metadata here, we use hasReshape == 0 as the
        // equivalent of the non-reshape condition.
        if metadata.hasReshape == 0 {
            // No-reshape branch: use static ICtCp pipeline based on pixelFormat.
            // Binary: FUN_10146725c (planeCount==3 / .ictcp) caches at self+0x70,
            //         FUN_101467328 (else / .nv12) caches at self+0x78.
            let state: MTLRenderPipelineState?
            if pixelFormat == .ictcp {
                state = getOrCreateICtCpPipeline(cached: &iCtCp10LE,
                                                  fragmentName: "displayICtCpTexture",
                                                  bitDepth: 10)
            } else {
                state = getOrCreateICtCpPipeline(cached: &iCtCpBiPlanar10LE,
                                                  fragmentName: "displayICtCpBiPlanarTexture",
                                                  bitDepth: 10)
            }
            guard let pipelineState = state else { return }

            encoder.setRenderPipelineState(pipelineState)
            encoder.setFragmentSamplerState(MetalRender.doviSamplerState, index: 0)

            for (index, texture) in textures.enumerated() {
                encoder.setFragmentTexture(texture, index: index)
            }

            // Binary binds leftShift at fragment index 1 (doc line 65).
            if let lsBuffer = MetalRender.doviLeftShiftBuffer {
                encoder.setFragmentBuffer(lsBuffer, offset: 0, index: 1)
            }

            set(encoder: encoder)
            return
        }

        // Step 3: Reshape branch -- select fragment function by pixelFormat.
        // Binary: planeCount == 3 (.ictcp) -> tri-planar ICtCp, else (.nv12) -> bi-planar NV12/ICtCp.
        let fragmentName: String
        if pixelFormat == .ictcp {
            fragmentName = "displayICtCpTexture"
        } else {
            fragmentName = "displayICtCpBiPlanarTexture"
        }

        // Step 6-7: Generate per-frame reshape shader and compile/cache it.
        let shaderSource = generateReshapeShader(metadata: metadata, fragmentName: fragmentName)

        guard let pipelineState = compileOrCacheShader(
            source: shaderSource,
            bitDepth: bitDepth
        ) else { return }

        // Step 5: Per-frame RPU->reshape-matrix transform.
        // The binary multiplies displayColorMatrix against the RPU's linear matrix.
        var uploadMetadata = metadata
        uploadMetadata.linear = DisplayColorMatrix.matrix * metadata.linear

        // Step 6: Build fragment MTLBuffer from the 3008-byte metadata blob.
        guard let dataBuffer = MetalRender.device.makeBuffer(
            bytes: &uploadMetadata,
            length: MemoryLayout<DoviGPUMetadata>.size,
            options: .storageModeShared
        ) else { return }
        dataBuffer.label = "dovi"

        // Step 4+8: Set pipeline state and fragment buffers.
        // Binary DV binding order (doc lines 65-68): dovi@0, leftShift@1.
        // NOT the standard path's matrix@0/colorOffset@1/leftShift@2/self+0x48@3.
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentSamplerState(MetalRender.doviSamplerState, index: 0)

        for (index, texture) in textures.enumerated() {
            encoder.setFragmentTexture(texture, index: index)
        }

        encoder.setFragmentBuffer(dataBuffer, offset: 0, index: 0)

        if let lsBuffer = MetalRender.doviLeftShiftBuffer {
            encoder.setFragmentBuffer(lsBuffer, offset: 0, index: 1)
        }

        // Step 8: Encode draw call via inherited PlaneDisplayModel.set(encoder:).
        set(encoder: encoder)
    }

    // MARK: - ICtCp Pipeline State (lazy, static)

    /// Lazy static ICtCp pipeline builder for the no-reshape branch.
    /// Binary: FUN_10146725c / FUN_101467328 -- uses MetalRender_buildRenderPipelineState
    /// with vertex function "mapTexture" and bitDepth 10.
    private func getOrCreateICtCpPipeline(cached: inout MTLRenderPipelineState?,
                                           fragmentName: String,
                                           bitDepth: Int32) -> MTLRenderPipelineState? {
        if let existing = cached { return existing }
        cached = MetalRender.makePipelineState(fragmentFunction: fragmentName, bitDepth: bitDepth)
        return cached
    }

    // MARK: - Reshape Shader Generation

    /// Runtime MSL code generation from RPU reshape data.
    /// Generates the header + reshape3() + fragment function.
    /// RE: 0x101466e84 (DoviDisplayModel_generateReshapeShader, 1.3.15)
    func generateReshapeShader(metadata: DoviGPUMetadata, fragmentName: String) -> String {
        var source = doviShaderHeader

        // reshape3 uses per-component data from dovi_metadata::reshape_data array
        source += reshapeFunction(metadata: metadata)

        // Fragment function
        source += generateFragmentFunction(name: fragmentName)

        return source
    }

    /// Generate the reshape3 function body from metadata.
    private func reshapeFunction(metadata: DoviGPUMetadata) -> String {
        var source = ""

        source += "float3 reshape3(float3 rgb, constant dovi_metadata& data) {\n"
        source += "    float3 sig = clamp(rgb, 0.0, 1.0);\n"
        source += "    float s;\n"
        source += "    float4 coeffs;\n"

        let components = [metadata.comp.0, metadata.comp.1, metadata.comp.2]
        for channel in 0..<3 {
            let comp = components[channel]
            source += "    s = sig[\(channel)];\n"

            if comp.numPivots < 3 {
                source += "    s = reshape_poly(s, data.comp[\(channel)].coeffs[0]);\n"
            } else {
                // 8-segment branchless mix tree
                source += "    coeffs = mix(mix(mix(data.comp[\(channel)].coeffs[0], data.comp[\(channel)].coeffs[1], float4(bool4(s >= data.comp[\(channel)].pivots[0]))),\n"
                source += "                     mix(data.comp[\(channel)].coeffs[2], data.comp[\(channel)].coeffs[3], float4(bool4(s >= data.comp[\(channel)].pivots[2]))),\n"
                source += "                     float4(bool4(s >= data.comp[\(channel)].pivots[1]))),\n"
                source += "                 mix(mix(data.comp[\(channel)].coeffs[4], data.comp[\(channel)].coeffs[5], float4(bool4(s >= data.comp[\(channel)].pivots[4]))),\n"
                source += "                     mix(data.comp[\(channel)].coeffs[6], data.comp[\(channel)].coeffs[7], float4(bool4(s >= data.comp[\(channel)].pivots[6]))),\n"
                source += "                     float4(bool4(s >= data.comp[\(channel)].pivots[5]))),\n"
                source += "                 float4(bool4(s >= data.comp[\(channel)].pivots[3])));\n"

                if comp.hasPoly && !comp.hasMMR {
                    source += "    s = reshape_poly(s, coeffs);\n"
                } else if comp.hasMMR && !comp.hasPoly {
                    source += generateMMRCode(channel: channel, comp: comp)
                } else {
                    source += "    if (coeffs.w == 0.0) {\n"
                    source += "        s = reshape_poly(s, coeffs);\n"
                    source += "    } else {\n"
                    source += generateMMRCode(channel: channel, comp: comp)
                    source += "    }\n"
                }
            }

            source += "    sig[\(channel)] = clamp(s, data.comp[\(channel)].lo, data.comp[\(channel)].hi);\n"
        }

        source += "    return sig;\n}\n\n"
        return source
    }

    // MARK: - MMR Code Generation

    /// RE: 0x101467bb8 (DoviDisplayModel_generateMMRCode, 1.3.15)
    private func generateMMRCode(channel: Int, comp: DoviReshapeData) -> String {
        var code = ""

        if comp.mmrSingle {
            code += "        uint order = uint(coeffs.w);\n"
            code += "        uint mmr_idx = 0;\n"
        } else {
            code += "        uint order = uint(coeffs.z);\n"
            code += "        uint mmr_idx = uint(coeffs.y);\n"
        }

        code += "        float4 sigX;\n"
        code += "        s = coeffs.x;\n"
        code += "        sigX.xyz = sig.xxy * sig.yzz;\n"
        code += "        sigX.w = sigX.x * sig.z;\n"
        code += "        s += dot(data.comp[\(channel)].mmr[mmr_idx + 0].xyz, sig);\n"
        code += "        s += dot(data.comp[\(channel)].mmr[mmr_idx + 1], sigX);\n"

        if comp.maxOrder >= 2 {
            code += "        float3 sig2 = sig * sig;\n"
            code += "        float4 sigX2 = sigX * sigX;\n"
            let guard2 = comp.minOrder < comp.maxOrder ? "if (order >= 2) " : ""
            code += "        \(guard2){\n"
            code += "            s += dot(data.comp[\(channel)].mmr[mmr_idx + 2].xyz, sig2);\n"
            code += "            s += dot(data.comp[\(channel)].mmr[mmr_idx + 3], sigX2);\n"
            code += "        }\n"
        }

        if comp.maxOrder >= 3 {
            let guard3 = comp.minOrder < comp.maxOrder ? "if (order >= 3) " : ""
            code += "        \(guard3){\n"
            code += "            s += dot(data.comp[\(channel)].mmr[mmr_idx + 4].xyz, sig2 * sig);\n"
            code += "            s += dot(data.comp[\(channel)].mmr[mmr_idx + 5], sigX2 * sigX);\n"
            code += "        }\n"
        }

        return code
    }

    // MARK: - Compile or Cache

    /// Compile or cache a per-frame reshape shader.
    ///
    /// Binary keys by the generated MSL source string (the per-frame shader is unique
    /// per RPU), not by fragment name + bit depth. The cache is unbounded on the main
    /// render path (unlike ThumbnailDoviDisplayModel's bounded LRU).
    ///
    /// RE: 0x10146782c (DoviDisplayModel_compileOrCacheShader, 1.3.15)
    private func compileOrCacheShader(source: String, bitDepth: Int32) -> MTLRenderPipelineState? {
        // Key by source string -- each RPU can produce unique MSL.
        if let cached = pipelineMap[source] {
            return cached
        }

        do {
            let library = try MetalRender.device.makeLibrary(source: source, options: nil)
            guard let vertexFunc = library.makeFunction(name: "mapTexture") else {
                return nil
            }
            // The fragment function name is embedded in the generated source.
            // Search for the known DV fragment functions.
            let fragmentFunc = library.makeFunction(name: "displayICtCpBiPlanarTexture")
                ?? library.makeFunction(name: "displayICtCpTexture")
                ?? library.makeFunction(name: "displayYUVTexture")
            guard let frag = fragmentFunc else { return nil }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunc
            descriptor.fragmentFunction = frag
            descriptor.colorAttachments[0].pixelFormat = KSOptions.colorPixelFormat(bitDepth: bitDepth)

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

            let state = try MetalRender.device.makeRenderPipelineState(descriptor: descriptor)
            pipelineMap[source] = state
            return state
        } catch {
            assertionFailure("[DoviDisplayModel] Shader compilation failed: \(error)")
            return nil
        }
    }

    // MARK: - Fragment Function Generation

    private func generateFragmentFunction(name: String) -> String {
        // Per .reversal/DolbyVision.md: two fragment functions selected by pixel-format.
        // "displayICtCpBiPlanarTexture" for NV12 (Y + interleaved UV, 2 textures) and
        // "displayICtCpTexture" for planar YUV (Y + U + V, 3 textures).
        if name == "displayICtCpBiPlanarTexture" {
            return """
            fragment float4 \(name)(VertexOut in [[ stage_in ]],
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
        } else {
            return """
            fragment float4 \(name)(VertexOut in [[ stage_in ]],
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
            """
        }
    }
}

// MARK: - ThumbnailDoviDisplayModel

/// DV-aware thumbnail render path -- a second reshape draw path parallel to `DoviDisplayModel`.
///
/// Unlike `DoviDisplayModel` (which caches reshape pipelines without bound on the single
/// render thread), this variant adds thread-safety (NSLock) and a bounded LRU cache of
/// reshape pipelines for the concurrent off-thread thumbnail generation path.
///
/// **Binary layout:** >= 160 bytes (0xA0), private/nested type with singleton at `DAT_103d0ca08`.
/// Class identity: `_TtC8KSPlayerP33_<hash>25ThumbnailDoviDisplayModel` (P33_ mangling = private).
///
/// RE: 0x1014081cc (ThumbnailDoviDisplayModel once-init, 1.3.15)
/// RE: 0x1014089f8 (ThumbnailDoviDisplayModel.init, 1.3.15)
class ThumbnailDoviDisplayModel: PlaneDisplayModel {

    /// Singleton instance (binary: `DAT_103d0ca08`, once-token `DAT_103d06258`).
    static let shared: ThumbnailDoviDisplayModel = ThumbnailDoviDisplayModel()

    // MARK: - Stored properties (binary-confirmed offsets from init at 0x1014089f8)

    /// ICtCp YUV-plane DV pipeline -- **eager, non-optional** (built at init).
    /// Binary: +0x70. Fragment descriptor at 0x1033376f0.
    /// RE: 0x1014089f8 (init, 1.3.15)
    private let iCtCp: MTLRenderPipelineState

    /// ICtCp NV12/bi-planar DV pipeline -- **eager, non-optional** (built at init).
    /// Binary: +0x78. Fragment descriptor at 0x1033376d0, fragment function
    /// "displayICtCpBiPlanarTexture".
    private let iCtCpBiPlanar: MTLRenderPipelineState

    /// Guards pipelineMap/pipelineOrder for concurrent thumbnail generation.
    /// Binary: +0x80, `[[NSLock alloc] init]` at init.
    private let pipelineLock = NSLock()

    /// LRU capacity cap. Binary: +0x88, written `= 4` at init.
    private let maxCachedPipelines: Int = 4

    /// Per-frame-keyed reshape pipeline cache (same key scheme as DoviDisplayModel.pipelineMap).
    /// Binary: +0x90.
    private var pipelineMap: [String: MTLRenderPipelineState] = [:]

    /// LRU recency list -- evicts the oldest key once count > maxCachedPipelines.
    /// Binary: +0x98.
    private var pipelineOrder: [String] = []

    // MARK: - Init

    /// RE: 0x1014089f8 (ThumbnailDoviDisplayModel.init, 1.3.15)
    private override init() {
        // Build eager pipeline states from MetalRender's shared device/library.
        // Binary: init forces MetalRender.sharedInstance via _swift_once, then builds
        // the two eager pipelines using MetalRender_buildRenderPipelineState.
        iCtCp = MetalRender.makePipelineState(fragmentFunction: "displayICtCpTexture", bitDepth: 10)
        iCtCpBiPlanar = MetalRender.makePipelineState(fragmentFunction: "displayICtCpBiPlanarTexture", bitDepth: 10)
        super.init()
    }

    // MARK: - Draw

    /// DV-aware thumbnail draw. Structurally parallel to `DoviDisplayModel.draw`.
    ///
    /// Control flow (disasm-verified):
    /// 1. memcpy the 3008-byte DoviData reshape blob from the frame.
    /// 2. FUN_101415b68 discriminant: if disc == 1 -> DisplayModel_drawStandard and return.
    /// 3. Else: if reshape flag set -> generateReshapeShader + lock-guarded compileOrCacheShader;
    ///    if clear -> use eager iCtCp/iCtCpBiPlanar pipeline by planeCount == 3.
    /// 4. Set pipeline state, bind leftShift at frag idx 1, inline RPU->reshape-matrix multiply.
    /// 5. Bind 0xBC0 DoviData at frag idx 0, draw indexed primitives.
    ///
    /// RE: 0x101408208 (ThumbnailDoviDisplayModel.draw, 1.3.15)
    /// NOTE: Intentionally uses `planeCount: Int` (not `pixelFormat: DoviPixelFormat`)
    /// matching the binary's simpler thumbnail path. The main DoviDisplayModel.draw
    /// at 0x1014673f4 uses the full DoviPixelFormat enum; this thumbnail variant
    /// branches on planeCount==3 directly. Not a signature bug — verified against binary.
    func draw(encoder: MTLRenderCommandEncoder, metadata: DoviGPUMetadata,
              planeCount: Int, bitDepth: Int32, textures: [MTLTexture]) {

        if metadata.hasReshape == 0 {
            // No-reshape: use eager pipeline based on planeCount.
            let state = planeCount == 3 ? iCtCp : iCtCpBiPlanar

            encoder.setRenderPipelineState(state)
            encoder.setFragmentSamplerState(MetalRender.doviSamplerState, index: 0)

            for (index, texture) in textures.enumerated() {
                encoder.setFragmentTexture(texture, index: index)
            }

            if let lsBuffer = MetalRender.doviLeftShiftBuffer {
                encoder.setFragmentBuffer(lsBuffer, offset: 0, index: 1)
            }

            set(encoder: encoder)
            return
        }

        // Reshape branch: generate per-frame shader.
        let fragmentName = planeCount == 3 ? "displayICtCpTexture" : "displayICtCpBiPlanarTexture"

        // Use the DoviDisplayModel's shared shader generation (same codegen path in binary).
        let shaderSource = DoviDisplayModel.sharedShaderGenerator
            .generateReshapeShader(metadata: metadata, fragmentName: fragmentName)

        guard let pipelineState = compileOrCacheShader(source: shaderSource, bitDepth: bitDepth) else {
            return
        }

        // Per-frame RPU->reshape-matrix transform (same as DoviDisplayModel).
        var uploadMetadata = metadata
        uploadMetadata.linear = DisplayColorMatrix.matrix * metadata.linear

        guard let dataBuffer = MetalRender.device.makeBuffer(
            bytes: &uploadMetadata,
            length: MemoryLayout<DoviGPUMetadata>.size,
            options: .storageModeShared
        ) else { return }
        // Note: thumbnail draw does NOT set the "dovi" buffer label (binary-verified).

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentSamplerState(MetalRender.doviSamplerState, index: 0)

        for (index, texture) in textures.enumerated() {
            encoder.setFragmentTexture(texture, index: index)
        }

        encoder.setFragmentBuffer(dataBuffer, offset: 0, index: 0)

        if let lsBuffer = MetalRender.doviLeftShiftBuffer {
            encoder.setFragmentBuffer(lsBuffer, offset: 0, index: 1)
        }

        set(encoder: encoder)
    }

    // MARK: - Lock-Guarded LRU Compile/Cache

    /// Concurrent analog of `DoviDisplayModel.compileOrCacheShader`.
    /// Lock-guarded with bounded LRU eviction (maxCachedPipelines = 4).
    ///
    /// RE: 0x1014085fc (ThumbnailDoviDisplayModel.compileOrCacheShader, 1.3.15)
    private func compileOrCacheShader(source: String, bitDepth: Int32) -> MTLRenderPipelineState? {
        pipelineLock.lock()

        // Probe cache.
        if let cached = pipelineMap[source] {
            pipelineLock.unlock()
            return cached
        }

        // Cache miss -- compile.
        do {
            let library = try MetalRender.device.makeLibrary(source: source, options: nil)
            guard let vertexFunc = library.makeFunction(name: "mapTexture") else {
                pipelineLock.unlock()
                return nil
            }
            let fragmentFunc = library.makeFunction(name: "displayICtCpBiPlanarTexture")
                ?? library.makeFunction(name: "displayICtCpTexture")
                ?? library.makeFunction(name: "displayYUVTexture")
            guard let frag = fragmentFunc else {
                pipelineLock.unlock()
                return nil
            }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunc
            descriptor.fragmentFunction = frag
            descriptor.colorAttachments[0].pixelFormat = KSOptions.colorPixelFormat(bitDepth: bitDepth)

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

            let state = try MetalRender.device.makeRenderPipelineState(descriptor: descriptor)

            // LRU eviction: if cache is at capacity, evict oldest.
            if pipelineOrder.count >= maxCachedPipelines {
                let evicted = pipelineOrder.removeFirst()
                pipelineMap.removeValue(forKey: evicted)
            }

            // Insert new entry.
            pipelineMap[source] = state
            pipelineOrder.append(source)

            pipelineLock.unlock()
            return state
        } catch {
            pipelineLock.unlock()
            assertionFailure("[ThumbnailDoviDisplayModel] Shader compilation failed: \(error)")
            return nil
        }
    }

    // MARK: - Offscreen Readback

    /// Renders one DV frame offscreen and reads it back as a CGImage in Rec.2100 PQ colorspace.
    /// This is what makes the model "thumbnail" -- it captures a single DV-reshaped frame.
    ///
    /// Flow:
    /// 1. Resolve frame's PixelBufferProtocol, read width/height; bail if <= 0.
    /// 2. Create command queue + offscreen MTLTexture.
    /// 3. Build MTLRenderPassDescriptor (clear, store), create encoder.
    /// 4. Bind sampler + textures, call draw(), endEncoding.
    /// 5. Blit texture to buffer (BGRA, 4 bytes/px), commit + waitUntilCompleted.
    /// 6. Create CGImage with kCGColorSpaceITUR_2100_PQ colorspace.
    ///
    /// RE: 0x1014148b4 (ThumbnailDoviDisplayModel offscreen readback, 1.3.15)
    func renderThumbnail(metadata: DoviGPUMetadata, planeCount: Int, bitDepth: Int32,
                         textures: [MTLTexture], width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return nil }

        let device = MetalRender.device
        guard let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer() else { return nil }

        // Offscreen texture.
        let texDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        texDescriptor.usage = [.renderTarget, .shaderRead]
        guard let offscreenTexture = device.makeTexture(descriptor: texDescriptor) else { return nil }

        // Render pass.
        let rpDesc = MTLRenderPassDescriptor()
        rpDesc.colorAttachments[0].texture = offscreenTexture
        rpDesc.colorAttachments[0].loadAction = .clear
        rpDesc.colorAttachments[0].storeAction = .store
        rpDesc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpDesc) else { return nil }

        // Bind sampler.
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.minFilter = .linear
        if let samplerState = device.makeSamplerState(descriptor: samplerDescriptor) {
            encoder.setFragmentSamplerState(samplerState, index: 0)
        }

        // Bind textures.
        for (index, texture) in textures.enumerated() {
            encoder.setFragmentTexture(texture, index: index)
        }

        // Draw the DV frame.
        draw(encoder: encoder, metadata: metadata, planeCount: planeCount,
             bitDepth: bitDepth, textures: textures)

        encoder.endEncoding()

        // Blit to buffer for CPU readback.
        let bytesPerPixel = 4
        let rowBytes = width * bytesPerPixel
        let bufferLength = rowBytes * height
        guard let readbackBuffer = device.makeBuffer(length: bufferLength, options: .storageModeShared),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { return nil }

        blitEncoder.copy(
            from: offscreenTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOriginMake(0, 0, 0),
            sourceSize: MTLSizeMake(width, height, 1),
            to: readbackBuffer,
            destinationOffset: 0,
            destinationBytesPerRow: rowBytes,
            destinationBytesPerImage: bufferLength
        )
        blitEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Build CGImage in Rec.2100 PQ colorspace.
        let colorSpace = CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)

        guard let provider = CGDataProvider(data: Data(
            bytesNoCopy: readbackBuffer.contents(),
            count: bufferLength,
            deallocator: .none
        ) as CFData) else { return nil }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: rowBytes,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

/// Internal accessor so ThumbnailDoviDisplayModel can use DoviDisplayModel's shader generation.
/// The binary routes both draw paths through the same generateReshapeShader/generateMMRCode.
extension DoviDisplayModel {
    /// A shared instance used only for shader generation by ThumbnailDoviDisplayModel.
    static let sharedShaderGenerator: DoviDisplayModel = {
        // This instance is never used for rendering -- only for the generateReshapeShader method.
        return DoviDisplayModel()
    }()
}

// MARK: - MetalRender Extensions (shared resources for DV path)

extension MetalRender {
    /// Shared linear sampler state for DV fragment shaders (matches sampler at index 0).
    /// Binary: built via _swift_once in the DV draw paths, shared across both
    /// DoviDisplayModel and ThumbnailDoviDisplayModel.
    static let doviSamplerState: MTLSamplerState? = {
        let desc = MTLSamplerDescriptor()
        desc.minFilter = .linear
        desc.magFilter = .linear
        return device.makeSamplerState(descriptor: desc)
    }()

    /// Shared leftShift buffer for DV bit-depth normalization.
    /// Binary: DAT_104458f78 = (1, 1, 1) for DV 10-bit content (ICtCp samples
    /// are already normalized, so leftShift is identity). Distinct from the standard
    /// path's leftShiftMatrixBuffer / leftShiftSixMatrixBuffer which are per-instance.
    /// RE: FUN_101469370 / FUN_1014693c4 (leftShift once-init pair, 1.3.15)
    static let doviLeftShiftBuffer: MTLBuffer? = {
        var leftShift: (UInt8, UInt8, UInt8) = (1, 1, 1)
        return device.makeBuffer(bytes: &leftShift, length: 3, options: .storageModeShared)
    }()
}

// MARK: - Static Shader Header

/// MSL header matching the binary's embedded shader at 0x102ff60f0.
/// Contains PQ transfer functions, structs, vertex shader, reshape helpers, and process().
private let doviShaderHeader = """
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

vertex VertexOut mapTexture(VertexIn input [[stage_in]]) {
VertexOut outVertex;
outVertex.renderedCoordinate = input.pos;
outVertex.textureCoordinate = input.uv;
return outVertex;
}

struct dovi_metadata {
uint8_t has_reshape;
uint8_t _pad0;
uint8_t _pad1;
uint8_t _pad2;
uint32_t _pad3;
uint32_t _pad4;
uint32_t _pad5;
float3x3 nonlinear;
float3x3 linear;
simd_float3 nonlinear_offset;
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

inline float3 process(float3 rgb, constant dovi_metadata& data) {
    rgb = reshape3(rgb, data);
    rgb = data.nonlinear*(rgb + data.nonlinear_offset);
    rgb = pqEOTF(rgb);
    rgb = data.linear*rgb;
    rgb = pqOETF(rgb);
    return rgb;
}

"""

// MARK: - Metadata Conversion (AVDOVIMetadata -> DoviGPUMetadata)

import Libavutil

extension DoviGPUMetadata {
    /// Convert FFmpeg's DV metadata to GPU-ready format.
    /// This is the critical conversion function that populates the Metal buffer struct
    /// from FFmpeg's rational-number DV metadata.
    /// RE: v1.3.15 -- accepts copied value types, not raw pointers.
    public static func from(
        header: AVDOVIRpuDataHeader?,
        mapping: AVDOVIDataMapping?,
        color: AVDOVIColorMetadata?
    ) -> DoviGPUMetadata {
        var meta = DoviGPUMetadata()

        guard let header = header else { return meta }

        // Binary inverts FFmpeg's `disable_residual_flag` when storing into the GPU
        // buffer: header byte 0 is "has reshape data" (1 = use dynamic shader, 0 = use
        // static cached pipeline).
        meta.hasReshape = header.disable_residual_flag == 0 ? 1 : 0

        // Color metadata: matrices and offsets
        if let color = color {
            // ycc_to_rgb matrix -> nonlinear (3x3, AVRational[9] row-major)
            meta.nonlinear = matrix_float3x3(columns: (
                SIMD3<Float>(
                    avRationalToFloat(color.ycc_to_rgb_matrix.0),
                    avRationalToFloat(color.ycc_to_rgb_matrix.3),
                    avRationalToFloat(color.ycc_to_rgb_matrix.6)
                ),
                SIMD3<Float>(
                    avRationalToFloat(color.ycc_to_rgb_matrix.1),
                    avRationalToFloat(color.ycc_to_rgb_matrix.4),
                    avRationalToFloat(color.ycc_to_rgb_matrix.7)
                ),
                SIMD3<Float>(
                    avRationalToFloat(color.ycc_to_rgb_matrix.2),
                    avRationalToFloat(color.ycc_to_rgb_matrix.5),
                    avRationalToFloat(color.ycc_to_rgb_matrix.8)
                )
            ))

            // ycc_to_rgb_offset -> nonlinear_offset
            meta.nonlinearOffset = SIMD3<Float>(
                avRationalToFloat(color.ycc_to_rgb_offset.0),
                avRationalToFloat(color.ycc_to_rgb_offset.1),
                avRationalToFloat(color.ycc_to_rgb_offset.2)
            )

            // rgb_to_lms matrix -> linear (3x3, AVRational[9] row-major)
            meta.linear = matrix_float3x3(columns: (
                SIMD3<Float>(
                    avRationalToFloat(color.rgb_to_lms_matrix.0),
                    avRationalToFloat(color.rgb_to_lms_matrix.3),
                    avRationalToFloat(color.rgb_to_lms_matrix.6)
                ),
                SIMD3<Float>(
                    avRationalToFloat(color.rgb_to_lms_matrix.1),
                    avRationalToFloat(color.rgb_to_lms_matrix.4),
                    avRationalToFloat(color.rgb_to_lms_matrix.7)
                ),
                SIMD3<Float>(
                    avRationalToFloat(color.rgb_to_lms_matrix.2),
                    avRationalToFloat(color.rgb_to_lms_matrix.5),
                    avRationalToFloat(color.rgb_to_lms_matrix.8)
                )
            ))
        }

        // Reshape/mapping data
        if let mapping = mapping {
            for i in 0..<3 {
                var comp = DoviReshapeData()
                let curve = mapping.curves.withUnsafeBufferPointer { $0[i] } // AVDOVIReshapingCurve

                comp.numPivots = curve.num_pivots

                // Convert pivot values
                for j in 0..<min(Int(curve.num_pivots) - 1, 7) {
                    withUnsafeMutablePointer(to: &comp.pivots) { ptr in
                        let base = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: Float.self)
                        base[j] = Float(curve.pivots.withUnsafeBufferPointer { $0[j + 1] }) / 4095.0
                    }
                }

                // Convert polynomial/MMR coefficients per piece
                for piece in 0..<min(Int(curve.num_pivots) - 1, 8) {
                    let method = curve.mapping_idc.withUnsafeBufferPointer { $0[piece] }
                    if method == 0 { // Polynomial
                        comp.hasPoly = true
                        let order = curve.poly_order.withUnsafeBufferPointer { $0[piece] }
                        var coeffVec = SIMD4<Float>.zero
                        for k in 0...Int(order) {
                            let coeff = curve.poly_coef.withUnsafeBufferPointer { buf in
                                avRationalToFloat(buf[piece * 4 + k])
                            }
                            coeffVec[k] = coeff
                        }
                        withUnsafeMutablePointer(to: &comp.coeffs) { ptr in
                            let base = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: SIMD4<Float>.self)
                            base[piece] = coeffVec
                        }
                    } else if method == 1 { // MMR
                        comp.hasMMR = true
                        let order = curve.mmr_order.withUnsafeBufferPointer { $0[piece] }
                        if comp.minOrder == 0 || order < comp.minOrder { comp.minOrder = order }
                        if order > comp.maxOrder { comp.maxOrder = order }

                        // MMR coefficients: 6 float4s per segment
                        let baseIdx = piece * 6
                        // constant term + linear cross-channel
                        var mmr0 = SIMD4<Float>.zero
                        mmr0.x = avRationalToFloat(curve.mmr_constant.withUnsafeBufferPointer { $0[piece] })
                        withUnsafeMutablePointer(to: &comp.mmr) { ptr in
                            let base = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: SIMD4<Float>.self)
                            base[baseIdx] = mmr0
                        }
                    }
                }

                comp.lo = 0
                comp.hi = 1

                // Store component
                withUnsafeMutablePointer(to: &meta.comp) { ptr in
                    let base = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: DoviReshapeData.self)
                    base[i] = comp
                }
            }
        }

        return meta
    }
}

private func avRationalToFloat(_ r: AVRational) -> Float {
    guard r.den != 0 else { return 0 }
    return Float(r.num) / Float(r.den)
}
