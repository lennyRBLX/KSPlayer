// DoviDisplayModel.swift
// EnhancedPlayer — Core
//
// Dolby Vision Metal renderer with runtime MSL shader generation.
// Reconstructed from Forward v1.3.15 binary: DoviDisplayModel at 0x10134xxxx.
//
// RE sources:
//   RE/62 — DoviDisplayModel (9 functions: draw, generateReshapeShader, generateMMRCode,
//           compileOrCacheShader, getStandardPipelineState, getOrCreateICtCp/BiPlanar)
//   RE/73 — Display/Metal pipeline (12 classes, ~100 fields)
//   RE/56 — Render pipeline (MetalPlayView, DisplayModel hierarchy)
//
// Architecture:
//   FFmpeg/libdovi RPU → KSDOVIRPUBuffer (2977 bytes, ring-indexed)
//     → dovi_metadata (2976 bytes copied to GPU)
//       → DoviDisplayModel.draw() → generateReshapeShader() [runtime MSL]
//         → compileOrCacheShader() [MTLDevice compile + cache]
//           → Metal GPU execution
//
// The render data block is exactly 2976 bytes = sizeof(dovi_metadata).
// Per-component reshape data is 944 bytes × 3 channels.
// Cache key: fragmentName + bitDepth string (e.g. "displayICtCpBiPlanarTexture10").

import Foundation
import Metal
import simd

// MARK: - Reshape Component (944 bytes per channel)

/// Per-channel reshape data extracted from DV RPU metadata.
/// Layout from RE/62 §2.2: 944 bytes per component (3 total = 2832 bytes of reshape).
public struct DoviReshapeComponent {
    /// Polynomial coefficients for up to 8 segments [float4 × 8 = 128 bytes]
    public var coeffs: [SIMD4<Float>] = Array(repeating: .zero, count: 8)
    /// MMR coefficient matrices [float4 × 48 = 768 bytes] (8 segments × 6 terms)
    public var mmr: [SIMD4<Float>] = Array(repeating: .zero, count: 48)
    /// Pivot boundaries [float × 7 = 28 bytes]
    public var pivots: [Float] = Array(repeating: 0, count: 7)
    /// Clamp range
    public var lo: Float = 0
    public var hi: Float = 1
    /// MMR polynomial order range
    public var minOrder: UInt8 = 0
    public var maxOrder: UInt8 = 0
    /// Pivot count (determines single-segment vs 8-segment codegen)
    public var numPivots: UInt8 = 0
    /// Mode flags
    public var hasPoly: Bool = false
    public var hasMMR: Bool = false
    public var mmrSingle: Bool = false
}

// MARK: - DOVI Metadata (2976 bytes, GPU-uploaded)

/// Full per-frame DV metadata block. The first ~144 bytes are color matrix + flags,
/// followed by 3 × 944 bytes of reshape component data.
public struct DoviMetadata {
    public var colorMatrix: matrix_float3x3 = matrix_identity_float3x3
    public var reshapeComponents: [DoviReshapeComponent] = Array(repeating: DoviReshapeComponent(), count: 3)
    public var hasReshapeData: Bool = false
    public var pixelFormat: DoviPixelFormat = .nv12
    public var bitDepth: Int32 = 10
}

public enum DoviPixelFormat: Int, Sendable {
    case nv12 = 2      // YUV/NV12 biplanar
    case ictcp = 3     // ICtCp (Dolby Vision perceptual color space)
}

// MARK: - DoviDisplayModel

/// Metal-based DV renderer. 136 bytes in binary (RE/62 §1).
/// Ivar layout: +16..+88 render data, +88 vertex MTLBuffer, +96 index MTLBuffer,
///              +112 cached ICtCp pipeline, +120 cached BiPlanar pipeline,
///              +128 Dictionary<String, MTLRenderPipelineState> shader cache.
public final class DoviDisplayModel {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    /// Cached pipeline states keyed by "fragmentName + bitDepth" (RE/62 §2.3)
    private var pipelineCache: [String: MTLRenderPipelineState] = [:]

    /// Pre-built pipeline states for non-reshape frames (lazy, RE/62 §2.6, §2.7)
    private var ictcpPipelineState: MTLRenderPipelineState?
    private var biplanarPipelineState: MTLRenderPipelineState?

    /// Metal buffers for vertex/index data
    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?

    /// The static shader library containing vertex function "mapTexture"
    /// and fallback fragment functions (non-reshape paths)
    private var defaultLibrary: MTLLibrary?

    /// Display-side color adaptation matrix (BT.2020 → display gamut)
    /// Binary globals: xmmword_1041F7740, algn_1041F7750, xmmword_1041F7760
    private let displayColorMatrix: matrix_float3x3 = matrix_float3x3(
        SIMD3<Float>(1.0, 0.0, 0.0),
        SIMD3<Float>(0.0, 1.0, 0.0),
        SIMD3<Float>(0.0, 0.0, 1.0)
    )

    public init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        self.defaultLibrary = device.makeDefaultLibrary()
        setupBuffers()
    }

    // MARK: - Draw (RE/62 §2.1: DoviDisplayModel_draw, 0x10134AEA0, 1080 bytes)

    /// Main render entry point. Called once per frame.
    /// 1. Copy 2976 bytes of render data into stack buffer
    /// 2. Check render flags — if no DV data, fallback to standard DisplayModel path
    /// 3. Query pixel format (2=NV12, 3=ICtCp)
    /// 4. If reshape present: generate shader, compile/cache, render
    /// 5. If no reshape: use pre-built pipeline states
    /// 6. Apply 3x3 color matrix transform (NEON SIMD) before GPU upload
    /// 7. Create MTLBuffer with transformed render data, bind to fragment slot 0
    /// 8. Draw indexed primitives
    public func draw(encoder: MTLRenderCommandEncoder, metadata: DoviMetadata,
                     textures: [MTLTexture]) {

        guard metadata.hasReshapeData else {
            drawStandard(encoder: encoder, metadata: metadata, textures: textures)
            return
        }

        let fragmentName: String
        switch metadata.pixelFormat {
        case .ictcp:
            fragmentName = "displayICtCpBiPlanarTexture"
        case .nv12:
            fragmentName = "displayYUVTexture"
        }

        // Generate reshape shader from RPU metadata
        let shaderSource = generateReshapeShader(metadata: metadata, fragmentName: fragmentName)

        // Compile or retrieve from cache
        guard let pipelineState = compileOrCacheShader(
            source: shaderSource,
            fragmentName: fragmentName,
            bitDepth: metadata.bitDepth
        ) else { return }

        // Apply display color matrix to render data (CPU-side pre-multiplication)
        var renderData = metadata
        for i in 0..<3 {
            let row = renderData.colorMatrix[i]
            renderData.colorMatrix[i] = displayColorMatrix * row
        }

        // Upload render data as fragment buffer
        guard let dataBuffer = device.makeBuffer(bytes: &renderData, length: MemoryLayout<DoviMetadata>.size,
                                                 options: .storageModeShared) else { return }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBuffer(dataBuffer, offset: 0, index: 0)

        for (index, texture) in textures.enumerated() {
            encoder.setFragmentTexture(texture, index: index)
        }

        if let vb = vertexBuffer, let ib = indexBuffer {
            encoder.setVertexBuffer(vb, offset: 0, index: 0)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: 6,
                                          indexType: .uint16, indexBuffer: ib, indexBufferOffset: 0)
        }
    }

    // MARK: - Reshape Shader Generation (RE/62 §2.2: 0x10134B2D8, 984 bytes)

    /// Runtime MSL code generation from RPU reshape data.
    /// Generates PQ EOTF/OETF, reshape_poly, reshape3, and fragment functions.
    /// Per component: selects branchless 8-segment mix() tree or single-segment path.
    func generateReshapeShader(metadata: DoviMetadata, fragmentName: String) -> String {
        var source = doviShaderHeader

        // Generate reshape3() function body
        source += "float3 reshape3(float3 sig, constant dovi_metadata& data) {\n"
        source += "    float3 result = sig;\n"

        for channel in 0..<3 {
            let comp = metadata.reshapeComponents[channel]
            let s = "sig[\(channel)]"
            let resultVar = "result[\(channel)]"

            if comp.numPivots < 3 {
                // Single segment: direct polynomial
                source += "    { float4 coeffs = data.reshape[\(channel)].coeffs[0];\n"
                source += "      \(resultVar) = reshape_poly(\(s), coeffs);\n"
                source += "      \(resultVar) = clamp(\(resultVar), data.reshape[\(channel)].lo, data.reshape[\(channel)].hi); }\n"
            } else {
                // 8-segment branchless binary mix() tree (RE/62 §2.2)
                source += "    { float s = \(s);\n"
                source += "      float4 coeffs = mix(mix(mix(data.reshape[\(channel)].coeffs[0], data.reshape[\(channel)].coeffs[1], step(data.reshape[\(channel)].pivots[0], s)),\n"
                source += "                              mix(data.reshape[\(channel)].coeffs[2], data.reshape[\(channel)].coeffs[3], step(data.reshape[\(channel)].pivots[2], s)), step(data.reshape[\(channel)].pivots[1], s)),\n"
                source += "                          mix(mix(data.reshape[\(channel)].coeffs[4], data.reshape[\(channel)].coeffs[5], step(data.reshape[\(channel)].pivots[4], s)),\n"
                source += "                              mix(data.reshape[\(channel)].coeffs[6], data.reshape[\(channel)].coeffs[7], step(data.reshape[\(channel)].pivots[6], s)), step(data.reshape[\(channel)].pivots[5], s)),\n"
                source += "                          step(data.reshape[\(channel)].pivots[3], s));\n"

                if comp.hasPoly && !comp.hasMMR {
                    source += "      \(resultVar) = reshape_poly(s, coeffs);\n"
                } else if comp.hasMMR && !comp.hasPoly {
                    source += generateMMRCode(channel: channel, comp: comp)
                } else {
                    // Hybrid: coeffs.w == 0 → poly, else MMR
                    source += "      if (coeffs.w == 0.0) { \(resultVar) = reshape_poly(s, coeffs); }\n"
                    source += "      else {\n"
                    source += generateMMRCode(channel: channel, comp: comp)
                    source += "      }\n"
                }

                source += "      \(resultVar) = clamp(\(resultVar), data.reshape[\(channel)].lo, data.reshape[\(channel)].hi); }\n"
            }
        }

        source += "    return result;\n}\n\n"

        // Fragment function
        source += generateFragmentFunction(name: fragmentName, pixelFormat: metadata.pixelFormat)

        return source
    }

    // MARK: - MMR Code Generation (RE/62 §2.4: 0x10134BA3C, 428 bytes)

    /// Generates MSL for Multi-channel Multi-resolution Regression.
    /// Order 1: linear cross-channel, Order 2: quadratic, Order 3: cubic.
    /// Uses float4 dot products for coefficient packing.
    private func generateMMRCode(channel: Int, comp: DoviReshapeComponent) -> String {
        var code = ""
        let prefix = "data.reshape[\(channel)]"

        if comp.mmrSingle {
            code += "        uint order = uint(coeffs.w);\n"
        }

        // Order 1 (linear): sigX = sig.xxy * sig.yzz, sigX.w = sigX.x * sig.z
        code += "        float3 sig3 = float3(result);\n"
        code += "        float4 sigX; sigX.xyz = sig3.xxy * sig3.yzz; sigX.w = sigX.x * sig3.z;\n"
        code += "        float s2 = dot(\(prefix).mmr[0], float4(1.0, sig3)) + dot(\(prefix).mmr[1], sigX);\n"

        if comp.maxOrder >= 2 {
            let guard2 = comp.minOrder < comp.maxOrder ? "if (order >= 2) " : ""
            code += "        \(guard2){\n"
            code += "          float4 sig2 = float4(sig3 * sig3, 0); float4 sigX2 = sigX * sigX;\n"
            code += "          s2 += dot(\(prefix).mmr[2], sig2) + dot(\(prefix).mmr[3], sigX2);\n"
            code += "        }\n"
        }

        if comp.maxOrder >= 3 {
            let guard3 = comp.minOrder < comp.maxOrder ? "if (order >= 3) " : ""
            code += "        \(guard3){\n"
            code += "          float4 sig3p = float4(sig3 * sig3 * sig3, 0);\n"
            code += "          float4 sigX3 = sigX * sigX * sigX;\n"
            code += "          s2 += dot(\(prefix).mmr[4], sig3p) + dot(\(prefix).mmr[5], sigX3);\n"
            code += "        }\n"
        }

        code += "        result[\(channel)] = s2;\n"
        return code
    }

    // MARK: - Compile or Cache (RE/62 §2.3: 0x10134B6B0, 724 bytes)

    /// Cache key: fragmentName + String(bitDepth), e.g. "displayICtCpBiPlanarTexture10".
    /// Cache miss: MTLDevice.newLibraryWithSource → buildRenderPipelineState.
    /// Cache hit: return existing pipeline state.
    private func compileOrCacheShader(source: String, fragmentName: String, bitDepth: Int32) -> MTLRenderPipelineState? {
        let cacheKey = fragmentName + String(bitDepth)

        if let cached = pipelineCache[cacheKey] {
            return cached
        }

        // Compile MSL at runtime
        let compileOptions = MTLCompileOptions()
        compileOptions.fastMathEnabled = true

        do {
            let library = try device.makeLibrary(source: source, options: compileOptions)
            guard let vertexFunc = library.makeFunction(name: "mapTexture"),
                  let fragmentFunc = library.makeFunction(name: fragmentName) else {
                return nil
            }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunc
            descriptor.fragmentFunction = fragmentFunc
            descriptor.colorAttachments[0].pixelFormat = .bgra10_xr

            let state = try device.makeRenderPipelineState(descriptor: descriptor)
            pipelineCache[cacheKey] = state
            return state
        } catch {
            // RE/62 §2.3: fatal error at DoviDisplayModel.swift:46 on compile failure
            assertionFailure("[DoviDisplayModel] Shader compilation failed: \(error)")
            return nil
        }
    }

    // MARK: - Standard (non-reshape) path

    private func drawStandard(encoder: MTLRenderCommandEncoder, metadata: DoviMetadata, textures: [MTLTexture]) {
        let state: MTLRenderPipelineState?
        switch metadata.pixelFormat {
        case .ictcp:
            state = getOrCreateICtCpPipelineState()
        case .nv12:
            state = getOrCreateBiPlanarPipelineState()
        }
        guard let pipelineState = state else { return }

        encoder.setRenderPipelineState(pipelineState)
        for (index, texture) in textures.enumerated() {
            encoder.setFragmentTexture(texture, index: index)
        }
        if let vb = vertexBuffer, let ib = indexBuffer {
            encoder.setVertexBuffer(vb, offset: 0, index: 0)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: 6,
                                          indexType: .uint16, indexBuffer: ib, indexBufferOffset: 0)
        }
    }

    /// RE/62 §2.6: lazy ICtCp pipeline at self+112
    private func getOrCreateICtCpPipelineState() -> MTLRenderPipelineState? {
        if let existing = ictcpPipelineState { return existing }
        guard let lib = defaultLibrary,
              let vert = lib.makeFunction(name: "mapTexture"),
              let frag = lib.makeFunction(name: "displayICtCpBiPlanarTexture") else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vert
        desc.fragmentFunction = frag
        desc.colorAttachments[0].pixelFormat = .bgra10_xr
        ictcpPipelineState = try? device.makeRenderPipelineState(descriptor: desc)
        return ictcpPipelineState
    }

    /// RE/62 §2.7: lazy BiPlanar pipeline at self+120
    private func getOrCreateBiPlanarPipelineState() -> MTLRenderPipelineState? {
        if let existing = biplanarPipelineState { return existing }
        guard let lib = defaultLibrary,
              let vert = lib.makeFunction(name: "mapTexture"),
              let frag = lib.makeFunction(name: "displayYUVTexture") else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vert
        desc.fragmentFunction = frag
        desc.colorAttachments[0].pixelFormat = .bgra10_xr
        biplanarPipelineState = try? device.makeRenderPipelineState(descriptor: desc)
        return biplanarPipelineState
    }

    // MARK: - Setup

    private func setupBuffers() {
        // Fullscreen quad vertices (position + texcoord)
        let vertices: [Float] = [
            -1,  1, 0, 1,   0, 0,  // top-left
             1,  1, 0, 1,   1, 0,  // top-right
            -1, -1, 0, 1,   0, 1,  // bottom-left
             1, -1, 0, 1,   1, 1,  // bottom-right
        ]
        let indices: [UInt16] = [0, 1, 2, 2, 1, 3]

        vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.size, options: .storageModeShared)
        indexBuffer = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt16>.size, options: .storageModeShared)
    }

    // MARK: - Fragment Function Generation

    private func generateFragmentFunction(name: String, pixelFormat: DoviPixelFormat) -> String {
        switch pixelFormat {
        case .ictcp:
            return """
            fragment float4 \(name)(VertexOut in [[stage_in]],
                                     texture2d<float> texY [[texture(0)]],
                                     texture2d<float> texUV [[texture(1)]],
                                     constant dovi_metadata& data [[buffer(0)]]) {
                constexpr sampler s(filter::linear);
                float y = texY.sample(s, in.texCoord).r;
                float2 uv = texUV.sample(s, in.texCoord).rg;
                float3 ictcp = float3(y, uv.x - 0.5, uv.y - 0.5);
                float3 reshaped = reshape3(ictcp, data);
                float3 linear = pqEOTF(reshaped);
                float3 rgb = data.colorMatrix * linear;
                return float4(pqOETF(rgb), 1.0);
            }
            """
        case .nv12:
            return """
            fragment float4 \(name)(VertexOut in [[stage_in]],
                                     texture2d<float> texY [[texture(0)]],
                                     texture2d<float> texUV [[texture(1)]],
                                     constant dovi_metadata& data [[buffer(0)]]) {
                constexpr sampler s(filter::linear);
                float y = texY.sample(s, in.texCoord).r;
                float2 uv = texUV.sample(s, in.texCoord).rg - 0.5;
                float3 yuv = float3(y, uv);
                float3 reshaped = reshape3(yuv, data);
                float3 linear = pqEOTF(reshaped);
                float3 rgb = data.colorMatrix * linear;
                return float4(pqOETF(rgb), 1.0);
            }
            """
        }
    }
}

// MARK: - Static Shader Header

/// MSL header with PQ transfer functions, structs, and helper functions.
/// Generated shaders are appended after this header.
private let doviShaderHeader = """
#include <metal_stdlib>
using namespace metal;

// PQ (Perceptual Quantizer) SMPTE ST 2084 constants
constant float pq_m1 = 0.1593017578125;
constant float pq_m2 = 78.84375;
constant float pq_c1 = 0.8359375;
constant float pq_c2 = 18.8515625;
constant float pq_c3 = 18.6875;

float3 pqEOTF(float3 x) {
    float3 p = pow(max(x, 0.0), float3(1.0 / pq_m2));
    float3 num = max(p - pq_c1, 0.0);
    float3 den = pq_c2 - pq_c3 * p;
    return pow(num / den, float3(1.0 / pq_m1));
}

float3 pqOETF(float3 x) {
    float3 p = pow(max(x, 0.0), float3(pq_m1));
    float3 num = pq_c1 + pq_c2 * p;
    float3 den = 1.0 + pq_c3 * p;
    return pow(num / den, float3(pq_m2));
}

struct VertexIn {
    float4 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut mapTexture(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = in.position;
    out.texCoord = in.texCoord;
    return out;
}

struct reshape_component {
    float4 coeffs[8];
    float4 mmr[48];
    float pivots[7];
    float lo;
    float hi;
};

struct dovi_metadata {
    float3x3 colorMatrix;
    reshape_component reshape[3];
};

float reshape_poly(float s, float4 coeffs) {
    return coeffs.x + s * (coeffs.y + s * coeffs.z);
}

"""
