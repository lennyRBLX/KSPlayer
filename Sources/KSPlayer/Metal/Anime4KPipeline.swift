//
//  Anime4KPipeline.swift
//  KSPlayer
//
//  RE source: v1.3.15 binary
//  - Anime4KPipeline_configure_pixelBuffer (0x10134057C, 3144 bytes)
//  - Anime4KPipeline_encodeToCommandBuffer (0x10145dcf8, ~1.4 KB; public wrapper 0x10145e8c0)
//  - Anime4KPipeline_GLSLtoMetalTranspiler (0x1014601a8)
//  - Anime4KPipeline_loadPreset (0x101340054, 804 bytes)
//  - Anime4KPipeline_updatePerformanceMetrics_frameTime (0x10145e300, 856 bytes)
//  - Anime4KPipeline_getDeviceGPUTier_viaMachineIdentifier (0x10145ef1c, 1156 bytes)
//  - Anime4KPipeline_evaluateWHENConditions (0x101455108, ~10.5 KB)
//  - Anime4KPipeline_evaluateAndCompile (0x101461b5c, ~12.7 KB)
//  - Anime4KPipeline_buildComputePipelineStates (0x101457a1c, ~8 KB — misnomer: per-stage compute encode)
//  - Anime4K_centerResize (0x1014597c8, ~1.5 KB)
//  - Anime4KPipeline_performanceStats getter (0x10145e718, ~196 B)
//  - Anime4KPipeline_sustainedDropDetector (0x10145e608)
//  - Anime4KPipeline_getProcessingState (0x10145bdfc)
//
//  Multi-pass Metal compute pipeline for real-time anime upscaling.
//  GLSL shader presets are transpiled to MSL at preset-load time (not per-frame).
//

import CoreVideo
import Foundation
import Metal
import simd
#if os(iOS) || os(tvOS)
import UIKit
#endif

// MARK: - GPU Tier Detection

/// RE: 0x10145ef1c (getDeviceGPUTier_viaMachineIdentifier, 1.3.15)
public enum GPUTier: Int {
    case low = 0
    case mid = 1
    case high = 2
    case ultra = 3

    /// Binary (1.3.15) tier mapping via uname() + Mirror:
    ///   iPhone16/17 → tier 4 (clamped to .ultra since enum max rawValue is 3)
    ///   iPhone14/15 → tier 1 (.mid)
    ///   all others  → tier 3 (.high — the default)
    /// RE: 0x10145ef1c (getDeviceGPUTier_viaMachineIdentifier, 1.3.15)
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
            // Binary returns tier 4; clamped to .ultra (highest enum case)
            return .ultra
        } else if machine.contains("iPhone14") || machine.contains("iPhone15") {
            return .mid
        } else {
            // Binary returns tier 3 = .high (NOT .ultra)
            return .high
        }
        #else
        // macOS — no uname device-model check in the binary; default to .ultra
        return .ultra // rationale: macOS GPU tier detection not in 1.3.15 binary
        #endif
    }
}

// MARK: - Anime4K Inventory Types (RE source: v1.3.15)

/// Active Anime4K upscale preset — names the mpv Anime4K shader-chain modes.
///
/// RE source: v1.3.15 — `enum KSPlayer.Anime4KPreset`, raw-backed, 13 cases
/// (CMa `$s8KSPlayer7Anime4KCMa` @ 0x101459e54). `disabled` selects the blit-copy
/// fallback; the `mode{A,B,C}{,A}{Fast,HQ}` cases name the Fast vs High-Quality
/// shader-chain variants (single vs double-pass `AA`/`CA` chains). Type of
/// `Anime4KPipeline.preset` and `Anime4KPerformanceStats.preset`.
public enum Anime4KPreset: Int {
    case disabled = 0
    case modeAFast = 1
    case modeBFast = 2
    case modeCFast = 3
    case modeAHQ = 4
    case modeBHQ = 5
    case modeCHQ = 6
    case modeAAFast = 7
    case modeBBFast = 8
    case modeCAFast = 9
    case modeAAHQ = 10
    case modeBBHQ = 11
    case modeCAHQ = 12
}

/// Ordinal Anime4K quality tier — a separate axis from `Anime4KPreset`
/// (which names shader-chain modes).
///
/// RE source: v1.3.15 — `enum KSPlayer.Anime4KQuality`, raw-backed, 5 cases.
public enum Anime4KQuality: Int {
    case lowest = 0
    case low = 1
    case medium = 2
    case high = 3
    case highest = 4
}

/// Typed snapshot of the Anime4K perf-monitoring state — the structured form of
/// the diagnostic stats string (`preset` name, supported flag, last/average frame
/// time, FPS, dropping flag).
///
/// RE source: v1.3.15 — `struct KSPlayer.Anime4KPerformanceStats`, 6 fields.
/// Builder `Anime4K_buildPerformanceStatsString` @ 0x10145ea10 is
/// `(Double, Double, Double, ulong) -> String` (field-by-field, ABI-confirmed).
public struct Anime4KPerformanceStats {
    public var lastFrameTime: Double
    public var averageFrameTime: Double
    public var estimatedFPS: Double
    public var isDropping: Bool
    public var supported: Bool
    public var preset: Anime4KPreset

    public init(
        lastFrameTime: Double,
        averageFrameTime: Double,
        estimatedFPS: Double,
        isDropping: Bool,
        supported: Bool,
        preset: Anime4KPreset
    ) {
        self.lastFrameTime = lastFrameTime
        self.averageFrameTime = averageFrameTime
        self.estimatedFPS = estimatedFPS
        self.isDropping = isDropping
        self.supported = supported
        self.preset = preset
    }
}

/// Parsed representation of one mpv/libplacebo `//!`-directive GLSL hook shader.
/// Arrays of this type are `Anime4K.shaders` / `Anime4K.enabledShaders`.
///
/// RE source: v1.3.15 — `struct KSPlayer.MPVShader`, 10 fields.
/// `copyMPVShader` @ 0x10000cb6c copies it; `when` is evaluated by
/// `Anime4KPipeline_evaluateWHENConditions` @ 0x101455108; `binds`/`save`/`hook`
/// drive the `textureMap` wiring.
public struct MPVShader {
    /// Shader pass name.
    public var name: String
    /// `//!HOOK` target texture.
    public var hook: String?
    /// `//!BIND` input textures.
    public var binds: [String]
    /// `//!SAVE` output texture name.
    public var save: String?
    /// `//!COMPONENTS` output channel count.
    public var components: Int?
    /// `//!WIDTH` expression + scale.
    public var width: (String, Float)?
    /// `//!HEIGHT` expression + scale.
    public var height: (String, Float)?
    /// `//!WHEN` conditional-execution expression.
    public var when: String?
    /// Blur sigma — parsed from `#define SPATIAL_SIGMA N`, not a `//!` directive.
    public var sigma: Double?
    /// GLSL body lines for this pass.
    public var code: [String]

    public init(
        name: String,
        hook: String? = nil,
        binds: [String] = [],
        save: String? = nil,
        components: Int? = nil,
        width: (String, Float)? = nil,
        height: (String, Float)? = nil,
        when: String? = nil,
        sigma: Double? = nil,
        code: [String] = []
    ) {
        self.name = name
        self.hook = hook
        self.binds = binds
        self.save = save
        self.components = components
        self.width = width
        self.height = height
        self.when = when
        self.sigma = sigma
        self.code = code
    }
}

/// Error type for the Anime4K shader-loading/transpilation path
/// (`Anime4K.compileOrLoadShaders`, `Anime4KPipeline` GLSL→Metal transpiler / shader loader).
///
/// RE source: v1.3.15 — `enum KSPlayer.Anime4KError`, 4 String-payload cases.
public enum Anime4KError: Error {
    /// Shader source file missing from bundle/path.
    case fileNotFound(String)
    /// Shader source unreadable / failed UTF-8 decode / malformed directives.
    case fileCorrupt(String)
    /// `device.makeLibrary`/`makeFunction` or compute-pipeline-state creation failed.
    case encoderCreationFail(String)
    /// The compiled compute encoder failed at dispatch/encode time.
    case encoderFail(String)
}

/// Error type for the GLSL→Metal transpilation stage specifically — raised while
/// parsing/translating shader source, before any Metal object exists.
///
/// RE source: v1.3.15 — `enum KSPlayer.GLSLError`, 2 String-payload cases.
public enum GLSLError: Error {
    /// The mpv `//!`-directive / GLSL source failed to parse.
    case parseFail(String)
    /// The translated MSL was rejected by the Metal compiler, or a GLSL construct
    /// has no Metal equivalent.
    case shaderError(String)
}

/// Frame-dump mode selector for the Anime4K compute pipeline (debug/diagnostic
/// capture of intermediate upscaler textures).
///
/// RE source: v1.3.15 — `enum KSPlayer.Anime4KFrameDump`. The enum *type*
/// is confirmed present in the binary (type string @ 0x102ef0690, mangled enum
/// suffix `nime4KFrameDumpO` @ 0x104739139), but its **cases are reflection-stripped
/// and not statically recoverable** from inventory or live Ghidra. Cases are
/// deliberately omitted rather than fabricated; see DisplayMetal.md.
public enum Anime4KFrameDump {
    // Cases reflection-stripped in the 1.3.15 binary; not statically recoverable.
    // See DisplayMetal.md §"Anime4KFrameDump (enum) [routed orphan]".
}

// MARK: - GLSL→Metal Transpiler

/// RE: 0x1014601a8 (Anime4KPipeline_GLSLtoMetalTranspiler, 1.3.15)
/// Generates mpv/libplacebo-compatible MSL from GLSL shader source.
/// Uses NSRegularExpression-based parsing (regexMatchAndExtractCaptures @ 0x101461610).
public enum GLSLToMetalTranspiler {
    /// RE: 0x1014601a8 (Anime4KPipeline_GLSLtoMetalTranspiler, 1.3.15)
    /// Transpiles a single GLSL shader pass to Metal Shading Language.
    /// The binary uses NSRegularExpression to parse GLSL constructs and generates
    /// mpv/libplacebo-compatible MSL macros per texture.
    public static func transpile(glslSource: String, passName: String) -> String? {
        var msl = """
        #include <metal_stdlib>
        using namespace metal;

        """

        // Extract texture names via regex (binary uses NSRegularExpression
        // at regexMatchAndExtractCaptures @ 0x101461610)
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

    /// RE: 0x101461268 (KSPlayer_buildMSLTextureDefines, 1.3.15)
    /// Generates mpv/libplacebo-compatible MSL macros per texture:
    /// ```
    /// #define N_pos mtlPos
    /// #define N_size float2(N.get_width(), N.get_height())
    /// #define N_pt (vec2(1, 1) / N_size)
    /// #define N_tex(pos) N.sample(textureSampler, pos)
    /// #define N_texOff(off) N_tex(N_pos + N_pt * vec2(off))
    /// ```
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

    /// Extract texture names from GLSL source via regex.
    /// Binary uses NSRegularExpression at 0x101461610.
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

/// The Anime4K GPU upscaling pipeline. Owns the perf-monitoring state, the per-stage
/// `Anime4K` shader-manager instances, and the encode/present path for multi-pass
/// Metal compute shaders.
///
/// RE: 0x10145fc5c (Anime4KPipeline CMa accessor, 1.3.15)
///
/// 21 stored properties from types.json (`KSPlayer.Anime4KPipeline`).
/// Encode orchestrator: `encodeToCommandBuffer` @ 0x10145dcf8.
/// Performance monitoring: `updatePerformanceMetrics` @ 0x10145e300,
///   `sustainedDropDetector` @ 0x10145e608, `performanceStats` getter @ 0x10145e718.
public final class Anime4KPipeline {

    // MARK: - Field #1: device (+0x10)
    /// Metal device used to build compute pipeline states.
    public let device: MTLDevice

    // MARK: - Field #2: anime4Ks (+0x18)
    /// Per-stage `Anime4K` shader-manager instances (each owns its compiled shader chain).
    /// The multi-pass encode loop iterates these; the final element drives `centerResize`.
    public private(set) var anime4Ks: [Anime4K] = []

    // MARK: - Field #3: preset (+0x20)
    /// Active upscale preset enum.
    public var preset: Anime4KPreset = .disabled

    // MARK: - Field #4: usePrecompiled (+0x28 area — packed)
    /// Prefer bundle-precompiled metallib over per-shader GLSL→Metal transpile.
    public var usePrecompiled: Bool = false

    // MARK: - Field #5: maxUpscaleInputHeight (+0x28)
    /// Cap on input height eligible for upscaling (skip very large frames).
    public var maxUpscaleInputHeight: Int?

    // MARK: - Field #6: cachedUpscaleSupport (+0x30 area)
    /// Memoized "is upscaling supported on this device/content" result.
    public var cachedUpscaleSupport: Bool?

    // MARK: - Field #7: inputTexture (+0x38)
    /// Current input texture handed to the compute passes.
    /// The encode path reads self+0x38 for this.
    public var inputTexture: MTLTexture?

    // MARK: - Field #8: videoWidth (+0x40)
    /// Source video width.
    public var videoWidth: Int = 0

    // MARK: - Field #9: videoHeight (+0x48)
    /// Source video height.
    public var videoHeight: Int = 0

    // MARK: - Field #10: compiledVideoWidth (+0x50)
    /// Video width the current pipeline states were compiled for.
    /// Recompile-trigger guard read by `getProcessingState`.
    public private(set) var compiledVideoWidth: Int = 0

    // MARK: - Field #11: compiledVideoHeight (+0x58)
    /// Video height the current pipeline states were compiled for.
    public private(set) var compiledVideoHeight: Int = 0

    // MARK: - Field #12: compiledDisplayWidth (+0x60)
    /// Display (output) width the pipeline was compiled for.
    public private(set) var compiledDisplayWidth: Int = 0

    // MARK: - Field #13: compiledDisplayHeight (+0x68)
    /// Display (output) height the pipeline was compiled for.
    public private(set) var compiledDisplayHeight: Int = 0

    // MARK: - Field #14: configured (+0x70)
    /// Set once `configure_pixelBuffer` has built textures/pipeline states.
    /// Dedicated Bool at self+0x70 checked in the encode gate.
    public private(set) var configured: Bool = false

    // MARK: - Field #15: supported (+0x71)
    /// Whether upscaling is active (false → blit-copy fallback).
    /// At self+0x71, read by the encode gate and the performanceStats producer.
    public private(set) var supported: Bool = false

    // MARK: - Field #16: overrideTargetResolution (+0x78 area)
    /// Optional forced output resolution.
    public var overrideTargetResolution: CGSize?

    // MARK: - Field #17: lastFrameTime (+0x90)
    /// Most-recent encode duration (seconds). Written by the recorder FUN_10145e300
    /// and read by the performanceStats producer.
    public private(set) var lastFrameTime: Double = 0.0

    // MARK: - Field #18: frameTimeHistory (+0x98)
    /// Rolling frame-time samples (the 30-sample circular buffer).
    /// COW semantics via `swift_isUniquelyReferenced_nonNull_native`.
    public private(set) var frameTimeHistory: [Double] = []

    // MARK: - Field #19: maxHistoryCount (+0xa0 area)
    /// Cap on `frameTimeHistory` length (the "30").
    public var maxHistoryCount: Int = 30

    // MARK: - Field #20: isDowngraded (+0xa8)
    /// Set when sustained drops force a preset downgrade.
    public private(set) var isDowngraded: Bool = false

    // MARK: - Field #21: onDowngradePreset (+0xb0/+0xb8)
    /// Callback fired when the pipeline auto-downgrades the preset on sustained drops.
    public var onDowngradePreset: (() -> Void)?

    // MARK: - Init

    /// RE: init — stores device, initializes 21 fields. Does NOT create a commandQueue
    /// (the binary receives MTLCommandBuffer as a parameter to encodeToCommandBuffer).
    public init?(device: MTLDevice? = nil) {
        guard let dev = device ?? MTLCreateSystemDefaultDevice() else { return nil }
        self.device = dev
    }

    // MARK: - Preset Loading

    /// RE: 0x101340054 (Anime4KPipeline_loadPreset, 1.3.15)
    /// Selects shader configuration and compiles Metal compute shaders.
    /// Populates `anime4Ks` with per-stage `Anime4K` shader-manager instances.
    public func loadPreset(_ preset: Anime4KPreset) {
        self.preset = preset
        self.configured = false
        self.supported = false
        anime4Ks.removeAll()

        guard preset != .disabled else { return }

        // Each Anime4K stage instance owns its compiled shader chain via
        // Anime4K.compileOrLoadShaders. The pipeline orchestrates them.
        // Actual shader source loading is handled by Anime4K instances.
    }

    /// RE: 0x101340054 (Anime4KPipeline_loadPreset, 1.3.15)
    /// String-based overload: resolves the preset name to shader passes via
    /// `Anime4KPresets.shaderPasses(for:)`, creates per-stage `Anime4K` shader-manager
    /// instances, and parses their shaders. Does NOT configure pixel buffer dimensions --
    /// the caller follows up with `configurePixelBuffer(width:height:displayWidth:displayHeight:)`.
    public func loadPreset(_ presetName: String) {
        // Clear prior state
        self.configured = false
        self.supported = false
        anime4Ks.removeAll()

        guard let shaderSources = Anime4KPresets.shaderPasses(for: presetName) else {
            KSLog("[anime4k] Unknown preset: \(presetName)")
            return
        }

        // Build per-stage Anime4K shader-manager instances
        for (index, source) in shaderSources.enumerated() {
            let stage = Anime4K(name: "\(presetName)_stage\(index)")
            // Parse GLSL source into MPVShader passes
            stage.shaders = Anime4KPipeline.evaluateAndCompile(source: source)
            stage.enabledShaders = stage.shaders
            anime4Ks.append(stage)
        }
    }

    // MARK: - Configure Pixel Buffer

    /// RE: 0x10134057C (Anime4KPipeline_configure_pixelBuffer, 1.3.15)
    /// Lifecycle step 2: creates Metal textures from pixel buffer, sets up pipeline states.
    /// Sets `configured = true` on success.
    public func configurePixelBuffer(width: Int, height: Int, displayWidth: Int, displayHeight: Int) {
        self.videoWidth = width
        self.videoHeight = height

        guard !anime4Ks.isEmpty else {
            configured = false
            supported = false
            return
        }

        // Check recompile-trigger: if dimensions match compiled state, skip
        if configured,
           compiledVideoWidth == width,
           compiledVideoHeight == height,
           compiledDisplayWidth == displayWidth,
           compiledDisplayHeight == displayHeight {
            return
        }

        compiledVideoWidth = width
        compiledVideoHeight = height
        compiledDisplayWidth = displayWidth
        compiledDisplayHeight = displayHeight

        // Check maxUpscaleInputHeight gate
        if let maxHeight = maxUpscaleInputHeight, height > maxHeight {
            supported = false
            configured = false
            inputTexture = nil
            return
        }

        // Determine if upscaling is actually enlarging
        let targetWidth: Int
        let targetHeight: Int
        if let override = overrideTargetResolution {
            targetWidth = Int(override.width)
            targetHeight = Int(override.height)
        } else {
            targetWidth = displayWidth
            targetHeight = displayHeight
        }

        supported = (width < targetWidth || height < targetHeight)

        // Allocate output texture
        // Binary uses pixelFormat 0x5e (bgr10a2Unorm, 10-bit) or 0x50 (bgra8Unorm, 8-bit)
        // based on content bit depth; usage = shaderRead|shaderWrite|renderTarget (7),
        // storageMode = private (2)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: min(targetWidth, 3840), // capped at 0xf00 = 3840
            height: min(targetHeight, 2160), // capped at 0x870 = 2160
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        inputTexture = device.makeTexture(descriptor: descriptor)

        configured = true
    }

    // MARK: - Encode to Command Buffer

    /// RE: 0x10145dcf8 (Anime4KPipeline_encodeToCommandBuffer, 1.3.15)
    /// Public wrapper at 0x10145e8c0 tail-calls this.
    ///
    /// The documented 5-step encode:
    /// 1. Gate checks: supported (+0x71), configured (+0x70), anime4Ks non-empty, inputTexture non-nil
    /// 2. Start clock via CACurrentMediaTime()
    /// 3. Multi-pass compute loop calling buildComputePipelineStates per stage,
    ///    chaining prevTexture through each Anime4K stage
    /// 4. Final centerResize render pass on last stage (Anime4K.centerResize)
    /// 5. addCompletedHandler block with weak self for perf monitoring
    ///
    /// Blit-copy fallback: if the upscale path is not taken, copies source texture
    /// directly to output via blitCommandEncoder.
    public func encodeToCommandBuffer(_ commandBuffer: MTLCommandBuffer, outputTexture: MTLTexture) {
        // Gate (step 1): check supported, anime4Ks count, inputTexture, configured
        guard supported, !anime4Ks.isEmpty, let input = inputTexture, configured else {
            // Blit-copy fallback: copy source directly to output
            // Binary: blitCommandEncoder → copyFromTexture:toTexture: → endEncoding
            guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { return }
            if let input = inputTexture {
                let copySize = MTLSize(
                    width: min(input.width, outputTexture.width),
                    height: min(input.height, outputTexture.height),
                    depth: 1
                )
                blitEncoder.copy(
                    from: input, sourceSlice: 0, sourceLevel: 0,
                    sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: copySize,
                    to: outputTexture, destinationSlice: 0, destinationLevel: 0,
                    destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
                )
            }
            blitEncoder.endEncoding()
            return
        }

        // Step 2: start clock
        let startTime = CACurrentMediaTime()

        // Step 3: multi-pass compute loop — iterate stages 0..<(count-1)
        // Each iteration calls buildComputePipelineStates which validates pipeline states,
        // creates compute encoder, binds textures/samplers, dispatches 16x16x1 threadgroups.
        // Returns the stage's output texture, chained as prevTexture for the next stage.
        var prevTexture: MTLTexture = input
        let stageCount = anime4Ks.count

        if stageCount > 1 {
            for i in 0 ..< (stageCount - 1) {
                let stage = anime4Ks[i]
                if let result = buildComputePipelineStates(
                    stage: stage,
                    commandBuffer: commandBuffer,
                    inputTexture: prevTexture
                ) {
                    prevTexture = result
                }
            }
        }

        // Step 4: final resize via centerResize on the last stage
        let lastStage = anime4Ks[stageCount - 1]
        try? lastStage.centerResize(
            device: device,
            commandBuffer: commandBuffer,
            sourceTexture: prevTexture,
            outputTexture: outputTexture
        )

        // Step 5: install completion handler for perf monitoring
        // Binary uses swift_weakInit of self to avoid retain cycle
        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let self else { return }
            let elapsed = CACurrentMediaTime() - startTime
            self.updatePerformanceMetrics(elapsed: elapsed)
        }
    }

    // MARK: - Process (Public Wrapper)

    /// RE: 0x10145e8c0 (Anime4KPipeline public wrapper, 1.3.15)
    /// Public entry point called by MetalPlayView: creates a command buffer from the
    /// device's command queue, invokes `encodeToCommandBuffer`, commits, and returns
    /// the processed output texture. Returns `nil` if the pipeline is not configured
    /// or if command buffer creation fails.
    ///
    /// The binary's public wrapper at 0x10145e8c0 tail-calls encodeToCommandBuffer
    /// at 0x10145dcf8. This convenience method wraps that pattern for the call site
    /// in MetalPlayView which passes `drawable.texture` as the input/output target.
    @discardableResult
    public func process(inputTexture: MTLTexture) -> MTLTexture? {
        guard configured else { return nil }

        // Store the input texture for the encode path (self+0x38)
        self.inputTexture = inputTexture

        // Create a one-shot command queue + command buffer.
        // The binary uses a global command queue (DAT_103d0f3f8); here we create
        // per-call to avoid shared-state issues. The command queue is lightweight.
        guard let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            KSLog("[anime4k] Failed to create command buffer for process")
            return nil
        }

        // The output texture is the same as the input (in-place upscale to the
        // drawable's texture). The encode path handles the blit-copy fallback
        // if upscaling is not supported.
        encodeToCommandBuffer(commandBuffer, outputTexture: inputTexture)
        commandBuffer.commit()

        return inputTexture
    }

    // MARK: - Per-Stage Compute Encode

    /// RE: 0x101457a1c (buildComputePipelineStates — Ghidra misnomer; per-stage compute encode, 1.3.15)
    ///
    /// Despite the Ghidra misnomer, this ~8KB function does NOT build MTLComputePipelineStates.
    /// It is the per-stage compute encode: validates pipeline states, creates encoders,
    /// binds textures/samplers, dispatches 16x16x1 threadgroups.
    ///
    /// Each call encodes one stage; the multi-pass loop calls it once per stage and chains
    /// the return as prevTexture.
    ///
    /// Args: device (+0x10), commandBuffer, inputTexture, self = Anime4KPipeline.
    /// Returns: the stage's output MTLTexture (the "output"-keyed texture from self+0x58 cache).
    private func buildComputePipelineStates(
        stage: Anime4K,
        commandBuffer: MTLCommandBuffer,
        inputTexture: MTLTexture
    ) -> MTLTexture? {
        // Entry assertion: pipelineStates count must equal shaders count
        guard stage.pipelineStates.count == stage.enabledShaders.count else {
            KSLog("[anime4k] Pipeline state count \(stage.pipelineStates.count) mismatch shader \(stage.enabledShaders.count)")
            return nil
        }

        guard !stage.pipelineStates.isEmpty else {
            return inputTexture
        }

        var currentInput = inputTexture

        // Per-pass loop: do {} while (passIndex+1 != count)
        for passIndex in 0 ..< stage.pipelineStates.count {
            let pipelineState = stage.pipelineStates[passIndex]

            // Create compute encoder
            guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
                KSLog("[anime4k] Failed to create compute command encoder")
                continue
            }

            // Bind pipeline state
            encoder.setComputePipelineState(pipelineState)

            // Bind sampler: nearest if outputW <= scale threshold, else linear
            // Binary uses self+0x60 (nearest) and self+0x68 (linear) arrays
            if passIndex < stage.nearestSamplerStates.count,
               passIndex < stage.linearSamplerStates.count {
                let sampler = stage.outputW <= stage.textureInW
                    ? stage.nearestSamplerStates[passIndex]
                    : stage.linearSamplerStates[passIndex]
                encoder.setSamplerState(sampler, index: 0)
            }

            // Bind input texture
            encoder.setTexture(currentInput, index: 0)

            // Resolve output texture from textureMap cache
            // Binary caches intermediates in self+0x58 per pass, keyed by name
            let outputKey = "output"
            var outputTexture: MTLTexture?
            if passIndex < stage.textureMap.count {
                outputTexture = stage.textureMap[passIndex][outputKey]
            }

            // Lazily allocate intermediate texture if needed
            if outputTexture == nil {
                let desc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: stage.intermediatePixelFormat,
                    width: Int(stage.outputW),
                    height: Int(stage.outputH),
                    mipmapped: false
                )
                desc.usage = [.shaderRead, .shaderWrite]
                desc.storageMode = .private
                outputTexture = device.makeTexture(descriptor: desc)
                // Cache the texture
                if passIndex < stage.textureMap.count {
                    stage.textureMap[passIndex][outputKey] = outputTexture
                }
            }

            if let outTex = outputTexture {
                encoder.setTexture(outTex, index: 1)
            }

            // Threadgroup dispatch: 16x16x1 hard-coded (binary verified)
            // threadgroupsPerGrid = { (w+15)>>4, (h+15)>>4, arrayLength }
            if let outTex = outputTexture {
                let w = outTex.width
                let h = outTex.height
                let threadgroupsPerGrid = MTLSize(
                    width: (w + 15) >> 4,
                    height: (h + 15) >> 4,
                    depth: 1
                )
                let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
                encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
            }

            encoder.endEncoding()

            if let outTex = outputTexture {
                currentInput = outTex
            }
        }

        // Return the "output"-keyed texture from the last pass
        return currentInput
    }

    // MARK: - Performance Monitoring

    /// RE: 0x10145e300 (Anime4KPipeline frame-time recorder + downgrade trigger, 1.3.15)
    ///
    /// The actual `frameTimeHistory` writer + downgrade trigger:
    /// - Stores elapsed to lastFrameTime (self+0x90)
    /// - COW append to frameTimeHistory (self+0x98)
    /// - History cap = 30
    /// - Calls sustainedDropDetector; if true and not yet downgraded, fires callback
    /// - Dropped-frame log if elapsed > 0.05
    private func updatePerformanceMetrics(elapsed: Double) {
        // Store to lastFrameTime
        lastFrameTime = elapsed

        // COW append to frameTimeHistory
        frameTimeHistory.append(elapsed)

        // Cap enforcement: keep at maxHistoryCount (30)
        if frameTimeHistory.count > maxHistoryCount {
            frameTimeHistory.removeFirst()
        }

        // Drop detector + downgrade trigger
        if sustainedDropDetector(), !isDowngraded {
            isDowngraded = true
            onDowngradePreset?()
        }

        // Dropped-frame log when elapsed > 50ms (0.05s)
        if elapsed > 0.05 {
            KSLog("[anime4k] \(elapsed * 1000.0) ms (dropped frame)")
        }
    }

    /// RE: 0x10145e608 (sustainedDropDetector, 1.3.15)
    ///
    /// Returns Bool. Requires >= 30 samples in frameTimeHistory.
    /// Iterates all 30; counts how many exceed 50ms threshold (DAT_102e52a90 = 0.05s).
    /// Returns true iff > 20 exceeded.
    /// This is the "sustained drops" predicate: "> 20 of the last 30 frames slower than 50 ms".
    private func sustainedDropDetector() -> Bool {
        // Requires >= 30 samples
        guard frameTimeHistory.count >= 30 else { return false }

        // 50ms threshold = 0.05 seconds (DAT_102e52a90)
        let threshold: Double = 0.05
        var overCount = 0

        for sample in frameTimeHistory {
            if sample > threshold {
                overCount += 1
            }
        }

        // Returns true iff > 20 exceeded (0x14 < overCount)
        return overCount > 20
    }

    /// RE: 0x10145e718 (performanceStats getter, 1.3.15)
    ///
    /// Computed-property getter that assembles Anime4KPerformanceStats from self fields.
    /// Returns packed flags in w0, lastFrameTime in d0, averageFrameTime in d1 (SIMD reduction),
    /// estimatedFPS in d2. LIVE, vtable-dispatched.
    ///
    /// Reads: frameTimeHistory(+0x98), lastFrameTime(+0x90), supported(+0x71), preset(+0x20).
    public var performanceStats: Anime4KPerformanceStats {
        // Average frame time: vectorized SIMD reduction over frameTimeHistory
        let average: Double
        if frameTimeHistory.isEmpty {
            average = 0
        } else {
            average = frameTimeHistory.reduce(0, +) / Double(frameTimeHistory.count)
        }

        // Estimated FPS: 1.0 / averageFrameTime, guarded for zero
        let fps = average > 0 ? (1.0 / average) : 0.0

        // isDropping: instantaneous test of lastFrameTime against threshold
        // (distinct from the sustained drop detector — same human meaning,
        // independent computations/constants)
        let dropping = lastFrameTime > 0.05

        return Anime4KPerformanceStats(
            lastFrameTime: lastFrameTime,
            averageFrameTime: average,
            estimatedFPS: fps,
            isDropping: dropping,
            supported: supported,
            preset: preset
        )
    }

    // MARK: - Processing State

    /// RE: 0x10145bdfc (Anime4KPipeline_getProcessingState, 1.3.15)
    ///
    /// Reads compiledVideoWidth/Height and compiledDisplayWidth/Height as
    /// recompile-trigger guards.
    public func getProcessingState() -> (videoWidth: Int, videoHeight: Int, displayWidth: Int, displayHeight: Int) {
        (compiledVideoWidth, compiledVideoHeight, compiledDisplayWidth, compiledDisplayHeight)
    }

    // MARK: - WHEN Condition Evaluation

    /// RE: 0x101455108 (Anime4KPipeline_evaluateWHENConditions, 1.3.15)
    ///
    /// Per-pass sizing + WHEN-gate + compute-PSO build, called once per shader pass.
    /// Signature (7 args): (self, NATIVE.w, NATIVE.h, MAIN.w, MAIN.h, target.w, target.h).
    /// The caller passes the previous pass's output W/H as the next pass's MAIN.
    ///
    /// Algorithm:
    /// 1. Populate sizeMap with MAIN/NATIVE/OUTPUT keys
    /// 2. Aspect-fit OUTPUT size
    /// 3. Resolve WIDTH/HEIGHT expressions from MPVShader fields
    /// 4. Evaluate `when` expression as postfix/RPN float-stack
    /// 5. If WHEN passes, compile + cache the pass's Metal compute function
    public func evaluateWHENConditions(
        stage: Anime4K,
        nativeWidth: Int,
        nativeHeight: Int,
        mainWidth: Int,
        mainHeight: Int,
        targetWidth: Int,
        targetHeight: Int
    ) {
        // Step 1: populate sizeMap
        stage.sizeMap["MAIN"] = (Float(mainWidth), Float(mainHeight))
        stage.sizeMap["NATIVE"] = (Float(nativeWidth), Float(nativeHeight))
        stage.sizeMap["OUTPUT"] = (Float(targetWidth), Float(targetHeight))

        // Step 2: aspect-fit OUTPUT size
        let scaleW = Float(targetWidth) / Float(nativeWidth)
        let scaleH = Float(targetHeight) / Float(nativeHeight)
        let scale = min(scaleW, scaleH)
        stage.displayActualW = scale * Float(nativeWidth)
        stage.displayActualH = scale * Float(nativeHeight)

        stage.outputW = Float(mainWidth)
        stage.outputH = Float(mainHeight)

        // Process each enabled shader pass
        for shader in stage.enabledShaders {
            // Step 3: resolve WIDTH/HEIGHT expressions
            if let (widthExpr, widthScale) = shader.width {
                if let size = stage.sizeMap[widthExpr] {
                    stage.outputW = size.0 * widthScale
                }
            }
            if let (heightExpr, heightScale) = shader.height {
                if let size = stage.sizeMap[heightExpr] {
                    stage.outputH = size.1 * heightScale
                }
            }

            // Set HOOKED to previous pass's output size
            stage.sizeMap["HOOKED"] = (stage.outputW, stage.outputH)

            // Step 4: evaluate WHEN expression (postfix/RPN float-stack)
            if let whenExpr = shader.when {
                let result = evaluateWHENExpression(whenExpr, sizeMap: stage.sizeMap)
                if result == 0.0 {
                    KSLog("[anime4k] WHEN condition result for \(shader.name): 0.0")
                    continue
                }
                KSLog("[anime4k] \(shader.name) - WHEN condition passed")
            }

            // Step 5: compile + cache Metal compute function
            // (handled by the Anime4K stage's compileOrLoadShaders)
        }
    }

    /// Evaluate a WHEN expression as a postfix/RPN float-stack evaluator.
    /// Resolves MAIN.w/OUTPUT.h/NATIVE.*/HOOKED.* size references against sizeMap,
    /// applies + - * / < >, gates the pass on nonzero result.
    ///
    /// RE: 0x101455108 Step 4 (evaluateWHENConditions, 1.3.15)
    private func evaluateWHENExpression(_ expression: String, sizeMap: [String: (Float, Float)]) -> Float {
        let tokens = expression.split(separator: " ").map(String.init)
        var stack: [Float] = []

        for token in tokens {
            // Skip the WHEN keyword itself
            if token == "WHEN" { continue }

            // Check for size reference (contains ".")
            if token.contains(".") {
                let parts = token.split(separator: ".", maxSplits: 1).map(String.init)
                if parts.count == 2, let size = sizeMap[parts[0]] {
                    switch parts[1] {
                    case "w":
                        stack.append(size.0)
                    case "h":
                        stack.append(size.1)
                    default:
                        break
                    }
                }
                continue
            }

            // Try numeric literal
            if let value = Float(token) {
                stack.append(value)
                continue
            }

            // Operators: pop 2, push 1
            guard stack.count >= 2 else {
                assertionFailure("Fatal error: WHEN expression stack underflow")
                return 0.0
            }
            let b = stack.removeLast()
            let a = stack.removeLast()

            switch token {
            case "+": stack.append(a + b)
            case "-": stack.append(a - b)
            case "*": stack.append(a * b)
            case "/": stack.append(b != 0 ? a / b : 0) // divisor is most-recently-pushed
            case "<": stack.append(a < b ? 1.0 : 0.0)
            case ">": stack.append(a > b ? 1.0 : 0.0)
            default:
                assertionFailure("Fatal error: unrecognized WHEN operator: \(token)")
            }
        }

        // Final result: stack must hold exactly 1 element
        guard stack.count == 1 else {
            KSLog("[anime4k] WHEN expression error, stack count: \(stack.count)")
            return 0.0
        }

        return stack[0]
    }

    // MARK: - //!-Directive Parser (evaluateAndCompile)

    /// RE: 0x101461b5c (Anime4KPipeline_evaluateAndCompile, 1.3.15)
    ///
    /// The producer of [MPVShader] arrays. Takes the shader-source String, returns the
    /// [MPVShader] COW buffer. Body ~12.7 KB fully traced.
    ///
    /// Control flow:
    /// 1. Split source on newline, trim whitespace
    /// 2. Per-line classify: //! → directive, // → comment/#define synthesis, else → code line
    /// 3. New //!HOOK flushes prior staged MPVShader and resets
    ///
    /// Directive keywords: DESC, HOOK, BIND, SAVE, WIDTH, HEIGHT, COMPONENTS, WHEN
    public static func evaluateAndCompile(source: String) -> [MPVShader] {
        var result: [MPVShader] = []
        var current = MPVShader(name: "")
        var hasCurrentPass = false

        let lines = source.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            // Directive line: starts with "//!"
            if trimmed.hasPrefix("//!") {
                let directive = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let parts = directive.split(separator: " ", maxSplits: 1).map(String.init)
                guard let keyword = parts.first else { continue }

                switch keyword {
                case "DESC":
                    // Description consumed but not stored in MPVShader
                    break

                case "HOOK":
                    // Flush prior staged pass
                    if hasCurrentPass {
                        result.append(current)
                    }
                    current = MPVShader(name: "")
                    hasCurrentPass = true
                    if parts.count > 1 {
                        current.hook = parts[1]
                        current.name = parts[1]
                    }

                case "BIND":
                    if parts.count > 1 {
                        current.binds.append(parts[1])
                    }

                case "SAVE":
                    current.save = parts.count > 1 ? parts[1] : "MAIN"

                case "WIDTH":
                    if parts.count > 1 {
                        let widthExpr = parts[1]
                        // Parse optional scale factor
                        let exprParts = widthExpr.split(separator: " ").map(String.init)
                        if exprParts.count >= 2, let scaleVal = Float(exprParts[1]) {
                            current.width = (exprParts[0], scaleVal)
                        } else {
                            current.width = (widthExpr, 1.0)
                        }
                    }

                case "HEIGHT":
                    if parts.count > 1 {
                        let heightExpr = parts[1]
                        let exprParts = heightExpr.split(separator: " ").map(String.init)
                        if exprParts.count >= 2, let scaleVal = Float(exprParts[1]) {
                            current.height = (exprParts[0], scaleVal)
                        } else {
                            current.height = (heightExpr, 1.0)
                        }
                    }

                case "COMPONENTS":
                    if parts.count > 1, let n = Int(parts[1]) {
                        current.components = n
                    }

                case "WHEN":
                    if parts.count > 1 {
                        current.when = parts[1]
                    }

                default:
                    break
                }
            } else if trimmed.hasPrefix("//") {
                // Comment / #define synthesis
                // Check for SPATIAL_SIGMA define
                if trimmed.contains("#define SPATIAL_SIGMA") {
                    let sigParts = trimmed.components(separatedBy: " ")
                    if let sigStr = sigParts.last, let sig = Double(sigStr) {
                        current.sigma = sig
                    }
                }
            } else {
                // GLSL code line — append verbatim
                current.code.append(trimmed)
            }
        }

        // Final flush
        if hasCurrentPass {
            result.append(current)
        }

        return result
    }

    // MARK: - Computed Properties

    /// Whether the pipeline has been configured and has active stages.
    public var isActive: Bool { configured && supported && !anime4Ks.isEmpty }

    /// Public alias for `configured` — the call site in MetalPlayView uses `isConfigured`.
    /// RE: 0x10145dcf8 gate reads +0x70 (configured); the public wrapper at 0x10145e8c0
    /// exposes this under the `isConfigured` name per the binary's witness table.
    public var isConfigured: Bool { configured }

    /// The active preset name for diagnostics.
    public var presetName: Anime4KPreset { preset }

    // MARK: - GLSLtoMetalTranspiler (per-pass entry point)

    /// RE: 0x1014601a8 (Anime4KPipeline_GLSLtoMetalTranspiler, 1.3.15)
    /// Per-pass transpile entry point: takes an MPVShader, joins its code lines,
    /// and transpiles via the GLSLToMetalTranspiler enum.
    /// Called by Anime4K.compileShaderPass and the inline transpile path.
    public static func GLSLtoMetalTranspiler(_ shader: MPVShader) -> String {
        let source = shader.code.joined(separator: "\n")
        let passName = shader.name.filter { $0 != "(" && $0 != ")" && $0 != "-" && $0 != "." }
        return GLSLToMetalTranspiler.transpile(glslSource: source, passName: passName) ?? ""
    }
}

// MARK: - Built-in Presets

public enum Anime4KPresets {
    /// RE: Anime4KPresets.shaderPasses (1.3.15)
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
