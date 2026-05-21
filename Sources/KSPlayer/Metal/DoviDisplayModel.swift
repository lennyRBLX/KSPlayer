// DoviDisplayModel.swift
// KSPlayer — Metal DV Renderer
//
// Dolby Vision Metal renderer with runtime MSL shader generation.
// Corrected from SenPlayer v6.0.6 binary analysis (DoviDisplayModel at 0x1008cd448).
//
// RE sources:
//   RE/62 — DoviDisplayModel (draw, generateReshapeShader, compileOrCacheShader)
//   SenPlayer shader source at 0x102ff60f0 (complete MSL with struct definitions)
//   SenPlayer draw decompilation (FUN_1008cd448): dual-matrix multiply + leftShift buffer
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
    /// Polynomial coefficients for up to 8 segments [float4 × 8 = 128 bytes]
    public var coeffs: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
                        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) =
        (.zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero)
    /// MMR coefficient matrices [float4 × 48 = 768 bytes] (8 segments × 6 terms)
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
    /// Pivot boundaries [float × 7 = 28 bytes]
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
/// **Layout (Ghidra-verified):** per `.reversal/DolbyVision.md §"dovi_metadata Struct"`
/// the buffer is 3008 bytes (0xBC0) with a **176-byte header** and three 944-byte
/// per-component reshape blocks at offsets 176 / 1120 / 2064. The `linear` matrix lives
/// at header offsets 64..111 (3 × float4 columns) -- directly observable in the NEON
/// SIMD `fmul`/`fmla` lanes of `DoviDisplayModel_draw` at `0x10146762c..101467664`
/// where it is multiplied by the (currently-identity) `displayColorMatrix` global at
/// `DAT_104458840`. The remaining header offsets are derived from the Metal alignment
/// rules required to land `comp[0]` at exactly offset 176.
///
/// The byte at offset 0 is the **reshape-presence** flag: when zero the binary picks a
/// static cached pipeline (`DAT_104458f78` / `DAT_104458f80`); when nonzero it generates
/// a per-frame reshape shader. This is the **inverse polarity** of FFmpeg's
/// `disable_residual_flag` (the field is exposed under that name through the
/// AVDOVIRpuDataHeader Swift binding, but the binary populates this byte with the
/// inverted "has reshape data" semantic).
public struct DoviGPUMetadata {
    /// Reshape-presence flag (binary semantics). When `0`, draw uses the static cached
    /// pipeline; when nonzero, draw runs the dynamic reshape shader. See
    /// `.reversal/DolbyVision.md §"Header sub-fields"`.
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
    /// 40-byte slot at header offsets 136..175. Required to land `comp[0]` at the
    /// Ghidra-verified offset 176. The in-tree shader does not reference these fields;
    /// see `DoviDMData` for the libdovi-derived field-name guesses.
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

// MARK: - DoviDisplayModel

public final class DoviDisplayModel {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    /// Cached pipeline states keyed by "fragmentName + bitDepth"
    private var pipelineCache: [String: MTLRenderPipelineState] = [:]

    /// Pre-built pipeline states for non-reshape frames (lazy)
    private var ictcpPipelineState: MTLRenderPipelineState?
    private var biplanarPipelineState: MTLRenderPipelineState?

    /// Metal buffers for fullscreen quad (separate pos/uv, matching PlaneDisplayModel)
    private var posBuffer: MTLBuffer?
    private var uvBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?

    /// Static shader library containing vertex/fragment functions for non-reshape path
    private var defaultLibrary: MTLLibrary?

    /// Display-side color adaptation matrix; pre-multiplied into the `linear` matrix on
    /// the CPU before the metadata buffer is uploaded to the GPU.
    ///
    /// In the binary this is the global at `DAT_104458840..10445886F` (48 bytes,
    /// 3 × float4 columns; guarded by `_swift_beginAccess(&DAT_104458840, ...)`),
    /// applied via NEON `fmul`/`fmla` lanes in `DoviDisplayModel_draw @ 0x1014673f4`
    /// at instructions `0x10146762c..101467664`.
    ///
    /// **Initial value (Ghidra-verified): identity.** The lazy initializer
    /// `FUN_1013a2d80` (via `_swift_once(&DAT_103d060f8, ...)`) copies 48 bytes from
    /// the constant blob at `_DAT_102ee9340` which encodes
    /// `{1,0,0,0, 0,1,0,0, 0,0,1,0}`. The binary does expose a public setter
    /// (`FUN_1013a2e64`) so display-side code could replace the matrix, but as
    /// shipped it stays identity for the entire process lifetime. This Swift port
    /// matches the binary by defaulting to identity here.
    private var displayColorMatrix: matrix_float3x3 = matrix_identity_float3x3

    /// Linear texture sampler (matches MetalRender's sampler at index 0)
    private var samplerState: MTLSamplerState?

    /// leftShift buffer (buffer index 1) — bit-depth normalization
    /// For 10-bit: leftShift = (1, 1, 1) — samples already normalized
    /// For >10-bit: shifts would scale down to [0,1] range
    private var leftShiftBuffer: MTLBuffer?

    /// Per-frame render metadata (written by updateMetadata, read by draw)
    private var renderMetadata = DoviGPUMetadata()

    public init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        self.defaultLibrary = device.makeDefaultLibrary()

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        self.samplerState = device.makeSamplerState(descriptor: samplerDescriptor)

        setupBuffers()
    }

    // MARK: - Draw

    /// Main render entry point. Called once per frame.
    ///
    /// Reads the reshape-presence flag at metadata header offset 0: when **zero** the
    /// binary uses a static cached pipeline (`DAT_104458f78` / `DAT_104458f80`), when
    /// nonzero it generates a per-frame reshape shader. The reshape-presence flag is
    /// the inverse polarity of FFmpeg's `disable_residual_flag` — see `DoviGPUMetadata`.
    public func draw(encoder: MTLRenderCommandEncoder, metadata: DoviGPUMetadata,
                     pixelFormat: DoviPixelFormat, bitDepth: Int32, textures: [MTLTexture]) {

        if metadata.hasReshape == 0 {
            drawStandard(encoder: encoder, pixelFormat: pixelFormat, bitDepth: bitDepth, textures: textures)
            return
        }

        let fragmentName: String
        switch pixelFormat {
        case .ictcp:
            fragmentName = "displayICtCpBiPlanarTexture"
        case .nv12:
            fragmentName = "displayYUVTexture"
        }

        // Generate reshape shader from per-frame metadata
        let shaderSource = generateReshapeShader(metadata: metadata, fragmentName: fragmentName)

        guard let pipelineState = compileOrCacheShader(
            source: shaderSource,
            fragmentName: fragmentName,
            bitDepth: bitDepth
        ) else { return }

        // Apply displayColorMatrix to the linear matrix (CPU-side pre-multiplication)
        var uploadMetadata = metadata
        uploadMetadata.linear = displayColorMatrix * metadata.linear

        // Upload metadata as fragment buffer 0
        guard let dataBuffer = device.makeBuffer(
            bytes: &uploadMetadata,
            length: MemoryLayout<DoviGPUMetadata>.size,
            options: .storageModeShared
        ) else { return }
        dataBuffer.label = "dovi"

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentSamplerState(samplerState, index: 0)

        for (index, texture) in textures.enumerated() {
            encoder.setFragmentTexture(texture, index: index)
        }

        encoder.setFragmentBuffer(dataBuffer, offset: 0, index: 0)

        if let lsBuffer = leftShiftBuffer {
            encoder.setFragmentBuffer(lsBuffer, offset: 0, index: 1)
        }

        encoder.setFrontFacing(.clockwise)
        encoder.setVertexBuffer(posBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uvBuffer, offset: 0, index: 1)
        if let ib = indexBuffer {
            encoder.drawIndexedPrimitives(
                type: .triangleStrip,
                indexCount: 4,
                indexType: .uint16,
                indexBuffer: ib,
                indexBufferOffset: 0
            )
        }
    }

    // MARK: - Standard (non-reshape) path

    private func drawStandard(encoder: MTLRenderCommandEncoder, pixelFormat: DoviPixelFormat,
                              bitDepth: Int32, textures: [MTLTexture]) {
        let state: MTLRenderPipelineState?
        switch pixelFormat {
        case .ictcp:
            state = getOrCreatePipelineState(
                fragmentName: "displayICtCpBiPlanarTexture",
                bitDepth: bitDepth,
                cached: &ictcpPipelineState
            )
        case .nv12:
            state = getOrCreatePipelineState(
                fragmentName: "displayYUVTexture",
                bitDepth: bitDepth,
                cached: &biplanarPipelineState
            )
        }
        guard let pipelineState = state else { return }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentSamplerState(samplerState, index: 0)

        for (index, texture) in textures.enumerated() {
            encoder.setFragmentTexture(texture, index: index)
        }

        if let lsBuffer = leftShiftBuffer {
            encoder.setFragmentBuffer(lsBuffer, offset: 0, index: 3)
        }

        encoder.setFrontFacing(.clockwise)
        encoder.setVertexBuffer(posBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uvBuffer, offset: 0, index: 1)
        if let ib = indexBuffer {
            encoder.drawIndexedPrimitives(
                type: .triangleStrip,
                indexCount: 4,
                indexType: .uint16,
                indexBuffer: ib,
                indexBufferOffset: 0
            )
        }
    }

    // MARK: - Reshape Shader Generation

    /// Runtime MSL code generation from RPU reshape data.
    /// Generates the header + reshape3() + fragment function.
    func generateReshapeShader(metadata: DoviGPUMetadata, fragmentName: String) -> String {
        var source = doviShaderHeader

        // reshape3 uses per-component data from dovi_metadata::reshape_data array
        source += reshapeFunction(metadata: metadata)

        // Fragment function
        source += generateFragmentFunction(name: fragmentName)

        return source
    }

    /// Generate the reshape3 function body from metadata.
    /// Uses #define macros for pivot/coef access (matching binary shader snippets).
    private func reshapeFunction(metadata: DoviGPUMetadata) -> String {
        var source = ""

        // The static shader already defines reshape3 via macros. For runtime generation,
        // we emit per-component logic based on the metadata flags.
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

    private func compileOrCacheShader(source: String, fragmentName: String, bitDepth: Int32) -> MTLRenderPipelineState? {
        let cacheKey = fragmentName + String(bitDepth)

        if let cached = pipelineCache[cacheKey] {
            return cached
        }

        do {
            let library = try device.makeLibrary(source: source, options: nil)
            guard let vertexFunc = library.makeFunction(name: "mapTexture"),
                  let fragmentFunc = library.makeFunction(name: fragmentName) else {
                return nil
            }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunc
            descriptor.fragmentFunction = fragmentFunc
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

            let state = try device.makeRenderPipelineState(descriptor: descriptor)
            pipelineCache[cacheKey] = state
            return state
        } catch {
            assertionFailure("[DoviDisplayModel] Shader compilation failed: \(error)")
            return nil
        }
    }

    // MARK: - Pipeline State Helpers

    private func getOrCreatePipelineState(fragmentName: String, bitDepth: Int32,
                                          cached: inout MTLRenderPipelineState?) -> MTLRenderPipelineState? {
        if let existing = cached { return existing }
        guard let lib = defaultLibrary,
              let vert = lib.makeFunction(name: "mapTexture"),
              let frag = lib.makeFunction(name: fragmentName) else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vert
        desc.fragmentFunction = frag
        desc.colorAttachments[0].pixelFormat = KSOptions.colorPixelFormat(bitDepth: bitDepth)

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float4
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].bufferIndex = 1
        vertexDescriptor.attributes[1].offset = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<simd_float4>.stride
        vertexDescriptor.layouts[1].stride = MemoryLayout<simd_float2>.stride
        desc.vertexDescriptor = vertexDescriptor

        cached = try? device.makeRenderPipelineState(descriptor: desc)
        return cached
    }

    // MARK: - Setup

    private func setupBuffers() {
        let positions: [simd_float4] = [
            [-1.0, -1.0, 0.0, 1.0],
            [-1.0,  1.0, 0.0, 1.0],
            [ 1.0, -1.0, 0.0, 1.0],
            [ 1.0,  1.0, 0.0, 1.0],
        ]
        let uvs: [simd_float2] = [
            [0.0, 1.0],
            [0.0, 0.0],
            [1.0, 1.0],
            [1.0, 0.0],
        ]
        let indices: [UInt16] = [0, 1, 2, 3]

        posBuffer = device.makeBuffer(bytes: positions, length: MemoryLayout<simd_float4>.stride * positions.count, options: .storageModeShared)
        uvBuffer = device.makeBuffer(bytes: uvs, length: MemoryLayout<simd_float2>.stride * uvs.count, options: .storageModeShared)
        indexBuffer = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt16>.size * indices.count, options: .storageModeShared)

        var leftShift: (UInt8, UInt8, UInt8) = (1, 1, 1)
        leftShiftBuffer = device.makeBuffer(bytes: &leftShift, length: 3, options: .storageModeShared)
    }

    // MARK: - Fragment Function Generation

    private func generateFragmentFunction(name: String) -> String {
        // Per .reversal/DolbyVision.md §"Shader Generation": the binary's MSL blob
        // contains two fragment functions selected by pixel-format token —
        // `displayICtCpBiPlanarTexture` for NV12 (Y + interleaved UV, 2 textures) and
        // `displayICtCpTexture` for planar YUV (Y + U + V, 3 textures).
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

// Per `.reversal/DolbyVision.md §"dovi_metadata Struct"`: 3008 bytes total, 176-byte
// header, three 944-byte per-component reshape blocks at offsets 176/1120/2064. The
// `linear` matrix at offsets 64..111 is Ghidra-verified via the NEON SIMD matrix
// multiply in `DoviDisplayModel_draw`. The 40-byte `dm` slot at offsets 136..175 is
// required to land `comp[0]` at the verified offset 176; the in-tree shader does not
// reference it but the slot must exist for offset alignment.
//
// Header byte 0 is "has_reshape" (the binary stores the inverse of FFmpeg's
// `disable_residual_flag`): nonzero -> dynamic reshape, zero -> static pipeline.
struct dovi_metadata {
uint8_t has_reshape;
uint8_t _pad0;
uint8_t _pad1;
uint8_t _pad2;
uint32_t _pad3;
uint32_t _pad4;
uint32_t _pad5;
// header offsets 16..63
float3x3 nonlinear;
// header offsets 64..111 (Ghidra-verified)
float3x3 linear;
// header offsets 112..127
simd_float3 nonlinear_offset;
// header offset 128
float minLuminance;
// header offset 132
float maxLuminance;
// header offsets 136..175 (DM slot - shader does not reference these, kept for layout)
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
// offset 176 / 1120 / 2064
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

// MARK: - Metadata Conversion (AVDOVIMetadata → DoviGPUMetadata)

import Libavutil

extension DoviGPUMetadata {
    /// Convert FFmpeg's DV metadata to GPU-ready format.
    /// This is the critical conversion function that populates the Metal buffer struct
    /// from FFmpeg's rational-number DV metadata.
    /// RE: Forward v1.3.15 — accepts copied value types, not raw pointers.
    public static func from(
        header: AVDOVIRpuDataHeader?,
        mapping: AVDOVIDataMapping?,
        color: AVDOVIColorMetadata?
    ) -> DoviGPUMetadata {
        var meta = DoviGPUMetadata()

        guard let header = header else { return meta }

        // Binary inverts FFmpeg's `disable_residual_flag` when storing into the GPU
        // buffer: header byte 0 is "has reshape data" (1 = use dynamic shader, 0 = use
        // static cached pipeline). See `.reversal/DolbyVision.md §"Header sub-fields"`.
        meta.hasReshape = header.disable_residual_flag == 0 ? 1 : 0

        // Color metadata: matrices and offsets
        if let color = color {
            // ycc_to_rgb matrix → nonlinear (3x3, AVRational[9] row-major)
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

            // ycc_to_rgb_offset → nonlinear_offset
            meta.nonlinearOffset = SIMD3<Float>(
                avRationalToFloat(color.ycc_to_rgb_offset.0),
                avRationalToFloat(color.ycc_to_rgb_offset.1),
                avRationalToFloat(color.ycc_to_rgb_offset.2)
            )

            // rgb_to_lms matrix → linear (3x3, AVRational[9] row-major)
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
