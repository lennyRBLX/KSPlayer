//
//  Anime4KPipeline.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15
//  - Anime4KPipeline_configure_pixelBuffer (0x10134057C, 3144 bytes)
//  - Anime4KPipeline_encodeToCommandBuffer (0x101341AD4, 1528 bytes)
//  - Anime4KPipeline_GLSLtoMetalTranspiler (0x10134402C)
//  - Anime4KPipeline_loadPreset (0x101340054, 804 bytes)
//  - Anime4KPipeline_updatePerformanceMetrics_frameTime (0x101342134, 856 bytes)
//  - Anime4KPipeline_getDeviceGPUTier_viaMachineIdentifier (0x101342DA0, 1156 bytes)
//
//  Multi-pass Metal compute pipeline for real-time anime upscaling.
//  GLSL shader presets are transpiled to MSL at preset-load time (not per-frame).
//

import CoreVideo
import Foundation
import Metal
import simd

// MARK: - GPU Tier Detection

public enum GPUTier: Int {
    case low = 0
    case mid = 1
    case high = 2
    case ultra = 3

    /// Binary (Forward v1.3.15) tier mapping:
    ///   iPhone16/17 → 4 (clamped to .ultra since enum max is 3)
    ///   iPhone14/15 → 1 (.mid)
    ///   all others  → 3 (.ultra as default)
    /// Raw values are NOT used as shader indices — only relative ordering matters.
    public static func detect() -> GPUTier {
        #if os(iOS) || os(tvOS)
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 256) {
                String(cString: $0)
            }
        }
        if machine.contains("iPhone16") || machine.contains("iPhone17") {
            return .ultra
        } else if machine.contains("iPhone14") || machine.contains("iPhone15") {
            return .mid
        } else {
            return .ultra
        }
        #else
        return .ultra
        #endif
    }
}

// MARK: - Anime4K Shader Pass

public struct Anime4KShaderPass {
    let name: String
    let computeFunction: MTLComputePipelineState
    let threadgroupSize: MTLSize
    let inputTextureCount: Int
    let outputWidth: Int
    let outputHeight: Int
}

// MARK: - Performance Metrics

public struct Anime4KPerformanceMetrics {
    private var frameTimes: [Double] = []
    private let maxSamples = 30
    public private(set) var droppedFrames: Int = 0
    private let dropThresholdMs: Double = 50.0

    public var averageFrameTimeMs: Double {
        guard !frameTimes.isEmpty else { return 0 }
        return frameTimes.reduce(0, +) / Double(frameTimes.count)
    }

    public var maxFrameTimeMs: Double { frameTimes.max() ?? 0 }
    public var minFrameTimeMs: Double { frameTimes.min() ?? 0 }

    public mutating func record(frameTimeMs: Double) {
        frameTimes.append(frameTimeMs)
        if frameTimes.count > maxSamples {
            frameTimes.removeFirst()
        }
        if frameTimeMs > dropThresholdMs {
            droppedFrames += 1
        }
    }

    public var statsString: String {
        String(format: "Anime4K: avg=%.1fms min=%.1fms max=%.1fms drops=%d",
               averageFrameTimeMs, minFrameTimeMs, maxFrameTimeMs, droppedFrames)
    }
}

// MARK: - GLSL→Metal Transpiler

public enum GLSLToMetalTranspiler {
    public static func transpile(glslSource: String, passName: String) -> String? {
        var msl = """
        #include <metal_stdlib>
        using namespace metal;

        """

        let textureNames = extractTextureNames(from: glslSource)
        for texName in textureNames {
            msl += generateTextureDefines(name: texName)
        }

        msl += """

        kernel void \(passName)(
            texture2d<float, access::read> input [[texture(0)]],
            texture2d<float, access::write> output [[texture(1)]],
            uint2 gid [[thread_position_in_grid]])
        {
            if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
            float2 outputSize = float2(output.get_width(), output.get_height());
            float2 inputSize = float2(input.get_width(), input.get_height());
            float2 pos = float2(gid) / outputSize;
            float2 pt = 1.0 / inputSize;

        """

        let bodyLines = extractShaderBody(from: glslSource)
        for line in bodyLines {
            msl += "    " + convertGLSLLine(line, textureNames: textureNames) + "\n"
        }

        msl += """
        }

        """
        return msl
    }

    private static func generateTextureDefines(name: String) -> String {
        """
        // mpv-compatible texture macros for \(name)
        #define \(name)_pos mtlPos
        #define \(name)_size float2(\(name).get_width(), \(name).get_height())
        #define \(name)_pt (float2(1.0, 1.0) / \(name)_size)
        #define \(name)_tex(pos) \(name).sample(textureSampler, pos)
        #define \(name)_texOff(off) \(name)_tex(\(name)_pos + \(name)_pt * float2(off))

        """
    }

    private static func extractTextureNames(from glsl: String) -> [String] {
        var names = Set<String>()
        let pattern = try? NSRegularExpression(pattern: #"uniform\s+sampler2D\s+(\w+)"#)
        let range = NSRange(glsl.startIndex..., in: glsl)
        pattern?.enumerateMatches(in: glsl, range: range) { match, _, _ in
            if let match, let nameRange = Range(match.range(at: 1), in: glsl) {
                names.insert(String(glsl[nameRange]))
            }
        }
        if names.isEmpty {
            names.insert("HOOKED")
        }
        return Array(names).sorted()
    }

    private static func extractShaderBody(from glsl: String) -> [String] {
        var lines = [String]()
        var inMain = false
        var braceDepth = 0
        for line in glsl.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("void main") || trimmed.contains("vec4 hook()") {
                inMain = true
                braceDepth = 0
                continue
            }
            if inMain {
                braceDepth += trimmed.filter({ $0 == "{" }).count
                braceDepth -= trimmed.filter({ $0 == "}" }).count
                if braceDepth < 0 { break }
                if !trimmed.isEmpty && trimmed != "{" {
                    lines.append(trimmed)
                }
            }
        }
        return lines
    }

    private static func convertGLSLLine(_ line: String, textureNames _: [String]) -> String {
        var result = line
        result = result.replacingOccurrences(of: "vec2", with: "float2")
        result = result.replacingOccurrences(of: "vec3", with: "float3")
        result = result.replacingOccurrences(of: "vec4", with: "float4")
        result = result.replacingOccurrences(of: "mat2", with: "float2x2")
        result = result.replacingOccurrences(of: "mat3", with: "float3x3")
        result = result.replacingOccurrences(of: "mat4", with: "float4x4")
        result = result.replacingOccurrences(of: "texture2D(", with: "input.read(uint2(")
        result = result.replacingOccurrences(of: "gl_FragCoord", with: "float2(gid)")
        result = result.replacingOccurrences(of: "gl_FragColor", with: "outputColor")
        return result
    }
}

// MARK: - Anime4KPipeline

public final class Anime4KPipeline {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var passes: [Anime4KShaderPass] = []
    private var intermediateTextures: [MTLTexture] = []
    private var outputTexture: MTLTexture?
    private var currentPreset: String?
    public private(set) var metrics = Anime4KPerformanceMetrics()
    public let gpuTier: GPUTier

    public init?(device: MTLDevice? = nil) {
        guard let dev = device ?? MTLCreateSystemDefaultDevice() else { return nil }
        self.device = dev
        guard let queue = dev.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        self.gpuTier = GPUTier.detect()
    }

    public func loadPreset(_ presetName: String, inputWidth: Int, inputHeight: Int, scaleFactor: Int = 2) -> Bool {
        guard let shaderSources = Anime4KPresets.shaderPasses(for: presetName) else {
            KSLog("[anime4k] unknown preset: \(presetName)")
            return false
        }

        passes.removeAll()
        intermediateTextures.removeAll()

        let outWidth = inputWidth * scaleFactor
        let outHeight = inputHeight * scaleFactor

        for (index, source) in shaderSources.enumerated() {
            let passName = "anime4k_pass_\(index)"
            guard let msl = GLSLToMetalTranspiler.transpile(glslSource: source, passName: passName) else {
                KSLog("[anime4k] transpilation failed for pass \(index)")
                continue
            }

            do {
                let library = try device.makeLibrary(source: msl, options: nil)
                guard let function = library.makeFunction(name: passName) else { continue }
                let pipeline = try device.makeComputePipelineState(function: function)

                let pass = Anime4KShaderPass(
                    name: passName,
                    computeFunction: pipeline,
                    threadgroupSize: MTLSize(width: 16, height: 16, depth: 1),
                    inputTextureCount: 1,
                    outputWidth: outWidth,
                    outputHeight: outHeight
                )
                passes.append(pass)
            } catch {
                KSLog("[anime4k] compute pipeline error pass \(index): \(error)")
                continue
            }

            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float,
                width: outWidth,
                height: outHeight,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .private
            if let texture = device.makeTexture(descriptor: descriptor) {
                intermediateTextures.append(texture)
            }
        }

        let outDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: outWidth,
            height: outHeight,
            mipmapped: false
        )
        outDesc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        outDesc.storageMode = .private
        outputTexture = device.makeTexture(descriptor: outDesc)

        currentPreset = presetName
        return !passes.isEmpty
    }

    public func process(inputTexture: MTLTexture) -> MTLTexture? {
        guard !passes.isEmpty, let outputTexture else { return nil }

        let startTime = CACurrentMediaTime()

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return nil }

        var currentInput = inputTexture
        for (index, pass) in passes.enumerated() {
            let currentOutput = index < intermediateTextures.count ? intermediateTextures[index] : outputTexture

            guard let encoder = commandBuffer.makeComputeCommandEncoder() else { continue }
            encoder.setComputePipelineState(pass.computeFunction)
            encoder.setTexture(currentInput, index: 0)
            encoder.setTexture(currentOutput, index: 1)

            let w = pass.computeFunction.threadExecutionWidth
            let h = pass.computeFunction.maxTotalThreadsPerThreadgroup / w
            let threadsPerGroup = MTLSize(width: w, height: h, depth: 1)
            let gridSize = MTLSize(width: pass.outputWidth, height: pass.outputHeight, depth: 1)
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerGroup)
            encoder.endEncoding()

            currentInput = currentOutput
        }

        if currentInput !== outputTexture {
            guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { return nil }
            let sourceSize = MTLSize(width: min(currentInput.width, outputTexture.width),
                                     height: min(currentInput.height, outputTexture.height),
                                     depth: 1)
            blitEncoder.copy(from: currentInput, sourceSlice: 0, sourceLevel: 0,
                             sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: sourceSize,
                             to: outputTexture, destinationSlice: 0, destinationLevel: 0,
                             destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blitEncoder.endEncoding()
        }

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let elapsed = (CACurrentMediaTime() - startTime) * 1000.0
        metrics.record(frameTimeMs: elapsed)

        return outputTexture
    }

    public var isConfigured: Bool { !passes.isEmpty }
    public var presetName: String? { currentPreset }
}

// MARK: - Built-in Presets

public enum Anime4KPresets {
    public static func shaderPasses(for preset: String) -> [String]? {
        switch preset {
        case "Mode A":
            return [Anime4KShaders.restoreCNN_VL, Anime4KShaders.upscale_CNN_x2_VL]
        case "Mode B":
            return [Anime4KShaders.restoreCNN_M, Anime4KShaders.upscale_CNN_x2_M]
        case "Mode C":
            return [Anime4KShaders.restoreCNN_S, Anime4KShaders.upscale_CNN_x2_S]
        case "Mode A+A":
            return [Anime4KShaders.restoreCNN_VL, Anime4KShaders.upscale_CNN_x2_VL,
                    Anime4KShaders.restoreCNN_M, Anime4KShaders.upscale_CNN_x2_M]
        default:
            return nil
        }
    }

    public static var availablePresets: [String] {
        ["Mode A", "Mode B", "Mode C", "Mode A+A"]
    }
}

// MARK: - Shader Sources (stubs for GLSL sources loaded from bundle)

public enum Anime4KShaders {
    public static let restoreCNN_VL = """
    // Anime4K Restore CNN VL
    // Placeholder — actual GLSL loaded from Anime4K shader pack
    uniform sampler2D HOOKED;
    vec4 hook() {
        vec2 pos = HOOKED_pos;
        vec4 color = HOOKED_tex(pos);
        return color;
    }
    """

    public static let restoreCNN_M = """
    uniform sampler2D HOOKED;
    vec4 hook() {
        vec2 pos = HOOKED_pos;
        vec4 color = HOOKED_tex(pos);
        return color;
    }
    """

    public static let restoreCNN_S = """
    uniform sampler2D HOOKED;
    vec4 hook() {
        vec2 pos = HOOKED_pos;
        vec4 color = HOOKED_tex(pos);
        return color;
    }
    """

    public static let upscale_CNN_x2_VL = """
    uniform sampler2D HOOKED;
    vec4 hook() {
        vec2 pos = HOOKED_pos;
        vec4 color = HOOKED_tex(pos);
        return color;
    }
    """

    public static let upscale_CNN_x2_M = """
    uniform sampler2D HOOKED;
    vec4 hook() {
        vec2 pos = HOOKED_pos;
        vec4 color = HOOKED_tex(pos);
        return color;
    }
    """

    public static let upscale_CNN_x2_S = """
    uniform sampler2D HOOKED;
    vec4 hook() {
        vec2 pos = HOOKED_pos;
        vec4 color = HOOKED_tex(pos);
        return color;
    }
    """
}
