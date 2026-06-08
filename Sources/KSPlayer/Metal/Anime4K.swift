//
//  Anime4K.swift
//  KSPlayer
//
//  RE addition: Anime4K shader manager — loads, compiles, and
//  caches Metal compute shaders for anime-specific GPU upscaling.
//  Companion to Anime4KPipeline (which handles GLSL→Metal transpilation).
//
//  Binary: _TtC8KSPlayer7Anime4K (15 functions)
//  RE source: v1.3.15, entry @ 0x1014538d4
//

import Foundation
import Metal
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Shader manager class for the Anime4K GPU upscaling system.
///
/// Handles loading, compiling, and caching Metal compute shaders. Separate from
/// `Anime4KPipeline` which handles GLSL→Metal transpilation and pipeline state
/// management — this class owns the shader source lifecycle.
///
/// Instance size `0x98` (152 B) confirmed by
/// `_swift_deallocPartialClassInstance(self, _, 0x98, 7)`.
public class Anime4K {
    // MARK: - Properties (RE field offsets: instance size 0x98)
    //
    // Refcounted fields +0x10 .. +0x70 — released by Anime4K_deinit (0x1003b4e74).
    // POD scalars +0x78 .. +0x94 — NOT touched by deinit.

    /// The half-float pixel format for intermediate compute passes.
    /// Raw value 115 = `MTLPixelFormat.rgba16Float`. This is NOT a quality/preset
    /// value — confirmed by the init-site writing `*(self+0x10) = 0x73`.
    /// RE: 0x1014538d4 init-site (+0x10)
    public var intermediatePixelFormat: MTLPixelFormat = MTLPixelFormat(rawValue: 115)! // +0x10  init 0x73 (rgba16Float)

    /// Shader name. The init-site writes a String guts+owner pair at +0x18/+0x20.
    /// Deinit releases via `swift_bridgeObjectRelease(self+0x18)`.
    /// RE: 0x1014538d4 init-site (+0x18)
    public var name: String                                                             // +0x18

    /// Parsed shader passes from `evaluateAndCompile`. Element type `MPVShader`,
    /// stride 0xA0 (160 B). Written by `evaluateAndCompile` result at +0x28.
    /// RE: 0x1014538d4 init-site (+0x28)
    public var shaders: [MPVShader] = []                                                // +0x28

    /// Compiled Metal libraries, one per shader pass (multi-shader branch).
    /// Zero-init `emptyArrayStorage`.
    /// RE: 0x1014538d4 init-site (+0x30)
    public var libraries: [MTLLibrary] = []                                             // +0x30

    /// The bundle's pre-compiled default `MTLLibrary`, loaded via
    /// `newDefaultLibraryWithBundle:error:`. Non-optional per the init-site
    /// which stores the result directly.
    /// RE: 0x1014538d4 init-site (+0x38)
    public var defaultLibrary: MTLLibrary!                                              // +0x38

    /// Enabled/active shader passes (subset of `shaders`). Zero-init.
    /// RE: 0x1014538d4 init-site (+0x40)
    public var enabledShaders: [MPVShader] = []                                         // +0x40

    /// Compiled compute pipeline states, one per enabled shader pass. Zero-init.
    /// RE: 0x1014538d4 init-site (+0x48)
    public var pipelineStates: [MTLComputePipelineState] = []                           // +0x48

    /// Per-output-pixel-format cache of the CenterResize render pipeline state.
    /// Keyed by `MTLPixelFormat`, built lazily by `centerResize`. Zero-init.
    /// RE: 0x1014538d4 init-site (+0x50)
    public var finalResizePSCache: [MTLPixelFormat: MTLRenderPipelineState] = [:]       // +0x50

    /// Per-pass texture dictionaries (hook-name → texture). Zero-init.
    /// RE: 0x1014538d4 init-site (+0x58)
    public var textureMap: [[String: MTLTexture]] = []                                  // +0x58

    /// Nearest-neighbor sampler states, one per pass. Zero-init.
    /// RE: 0x1014538d4 init-site (+0x60)
    public var nearestSamplerStates: [MTLSamplerState] = []                             // +0x60

    /// Linear sampler states, one per pass. Zero-init.
    /// RE: 0x1014538d4 init-site (+0x68)
    public var linearSamplerStates: [MTLSamplerState] = []                              // +0x68

    /// Per-pass size map: dimension keys ("MAIN", "NATIVE", "OUTPUT", "HOOKED")
    /// mapped to `(width, height)` Float pairs. Used by `evaluateWHENConditions`.
    /// RE: 0x1014538d4 init-site (+0x70)
    public var sizeMap: [String: (Float, Float)] = [:]                                  // +0x70

    // POD scalars +0x78 .. +0x94 — NOT touched by Anime4K_deinit (no swift_release calls).
    // Set by Anime4K_compileOrLoadShaders at init:
    //   *(self+0x78) = 0xFFFFFFFFFFFFFFFF  (-1 sentinel)
    //   *(self+0x80) = 0, *(self+0x88) = 0, *(self+0x90) = 0

    /// Ring-buffer cursor for the per-pass size tracking. -1 sentinel = "no index".
    /// RE: 0x1014538d4 init-site (+0x78)
    public var bufferIndex: Int = -1                                                    // +0x78

    /// Output width in pixels (Float, packs into low half of +0x80 quadword).
    /// RE: 0x1014538d4 init-site (+0x80)
    public var outputW: Float = 0                                                       // +0x80

    /// Output height in pixels (Float, packs into high half of +0x80 quadword).
    /// RE: 0x1014538d4 init-site (+0x84)
    public var outputH: Float = 0                                                       // +0x84

    /// Input texture width (Float, packs into low half of +0x88 quadword).
    /// RE: 0x1014538d4 init-site (+0x88)
    public var textureInW: Float = 0                                                    // +0x88

    /// Input texture height (Float, packs into high half of +0x88 quadword).
    /// RE: 0x1014538d4 init-site (+0x8C)
    public var textureInH: Float = 0                                                    // +0x8C

    /// Display actual width after aspect-fit (Float, packs into low half of +0x90).
    /// RE: 0x1014538d4 init-site (+0x90)
    public var displayActualW: Float = 0                                                // +0x90

    /// Display actual height after aspect-fit (Float, packs into high half of +0x90).
    /// RE: 0x1014538d4 init-site (+0x94)
    public var displayActualH: Float = 0                                                // +0x94

    // MARK: - Init

    /// Designated initializer. The binary init-site at 0x1014538d4 takes the shader
    /// name (stored at +0x18) and zero-initializes the remaining fields. The device
    /// is accessed via the Anime4KPipeline container or passed as a function parameter.
    /// RE: 0x1014538d4 (Anime4K.init, 1.3.15)
    public init(name: String) {
        self.name = name
    }

    // MARK: - Compile or Load Shaders (RE: Anime4K_compileOrLoadShaders @ 0x1014538d4)

    /// Main shader loading — tries pre-compiled from bundle first, falls back to
    /// per-shader GLSL→Metal transpilation. Uses MD5 hash of source for cache key.
    ///
    /// Algorithm (from binary):
    /// 1. Hash shader source with MD5 for cache key
    /// 2. Try loading pre-compiled shader from bundle
    /// 3. evaluateAndCompile → store parsed [MPVShader] at +0x28
    /// 4. Load default library via newDefaultLibraryWithBundle
    /// 5. Branch on isSingleShader:
    ///    - false (multi-shader): per-pass GLSLtoMetalTranspiler → makeLibrary worker
    ///    - true (single-shader): use bundle library directly, or inline transpile for count >= 2
    /// 6. Function-name derivation: filterCharacters + '_' + index + MD5 hash
    ///
    /// RE: 0x1014538d4 (Anime4K_compileOrLoadShaders, 1.3.15)
    public func compileOrLoadShaders(
        name shaderName: String,
        device: MTLDevice,
        bundle: Bundle? = nil,
        isSingleShader: Bool = false
    ) throws {
        let targetBundle = bundle ?? Bundle.main

        // Step 1-3: Load shader source from bundle, parse with evaluateAndCompile
        let shaderURL = targetBundle.bundleURL.appendingPathComponent(shaderName)
        guard let data = try? Data(contentsOf: shaderURL),
              let sourceString = String(data: data, encoding: .utf8)
        else {
            throw Anime4KError.fileNotFound("Cannot find shader: \(shaderName)")
        }

        // Step 3: Store parsed shader array (evaluateAndCompile result)
        let parsed = Anime4KPipeline.evaluateAndCompile(source: sourceString)
        self.shaders = parsed

        // Step 5: Load default library from bundle
        do {
            self.defaultLibrary = try device.makeDefaultLibrary(bundle: targetBundle)
        } catch {
            // Default library load failure is not fatal — fall through to transpile path
            self.defaultLibrary = nil
        }

        if !isSingleShader {
            // Multi-shader branch: per-pass GLSLtoMetalTranspiler → makeLibrary worker
            // Iterate parsed-shader array (stride 0xA0 per MPVShader) and for each
            // pass call the per-shader compile worker (FUN_101454ef8).
            self.libraries = []
            for pass in shaders {
                do {
                    let library = try compileShaderPass(pass: pass, device: device)
                    self.libraries.append(library)
                } catch {
                    throw error
                }
            }
        } else {
            // Single-shader branch
            if shaders.count == 1, let library = self.defaultLibrary {
                // count == 1: use bundle library directly
                let sanitizedName = filterCharacters(shaderName)
                if let function = library.makeFunction(name: sanitizedName) {
                    // For single-shader, we store the library
                    self.libraries = [library]
                    _ = function // Function resolved from bundle library
                }
                print("compiled shaders for \(self.name)")
            } else {
                // count >= 2: inline per-pass transpile path (mirrors FUN_101454ef8)
                print("compiled shaders for \(self.name)")
                self.libraries = []
                for (index, pass) in shaders.enumerated() {
                    let mslSource = Anime4KPipeline.GLSLtoMetalTranspiler(pass)
                    print("Metal code for \(pass.name)")

                    guard let library = try? device.makeLibrary(source: mslSource, options: nil) else {
                        throw Anime4KError.encoderCreationFail(
                            "Failed to compile Metal library for pass \(pass.name)"
                        )
                    }

                    // Function-name derivation: filterCharacters + '_' + index + MD5 hash
                    let baseName = filterCharacters(pass.name)
                    let functionName = md5Hash("\(baseName)_\(index)")
                    guard library.makeFunction(name: functionName) != nil else {
                        throw Anime4KError.encoderCreationFail(
                            "Function '\(functionName)' not found in compiled library"
                        )
                    }
                    self.libraries.append(library)
                }
            }
        }

        // Init POD scalars (per binary init-site)
        self.bufferIndex = -1
        self.outputW = 0
        self.outputH = 0
        self.textureInW = 0
        self.textureInH = 0
        self.displayActualW = 0
        self.displayActualH = 0
    }

    // MARK: - Per-shader compile worker (RE: FUN_101454ef8, 1.3.15)

    /// Per-shader `GLSLtoMetalTranspiler → makeLibrary(source:)` compile worker.
    /// Body 0x101454ef8-0x101455107 (~527 B). Sole caller is `compileOrLoadShaders`
    /// (multi-shader branch). Transpiles one pass, prints "Metal code for <name>",
    /// bridges MSL→NSString, calls `device.makeLibrary(source:options:error:)`.
    ///
    /// RE: 0x101454ef8 (FUN_101454ef8 per-shader makeLibrary worker, 1.3.15)
    private func compileShaderPass(pass: MPVShader, device: MTLDevice) throws -> MTLLibrary {
        // Step 1: Diagnostic print
        print("Metal code for \(pass.name)")

        // Step 2: Transpile GLSL→Metal (called twice in binary: once for print interpolation,
        // once for the actual MSL source)
        let mslSource = Anime4KPipeline.GLSLtoMetalTranspiler(pass)

        // Step 3-4: Bridge to NSString and compile via device.makeLibrary(source:options:error:)
        do {
            let library = try device.makeLibrary(source: mslSource, options: nil)
            return library
        } catch {
            // Step 5: Error path — convert NSError to Swift Error
            throw error
        }
    }

    // MARK: - Shader accessors (RE: 0x100032d64, 0x100040350)

    /// Shader array accessor — used in evaluateWHENConditions tokenizer step
    /// (closure over pass.code/expr lines).
    /// RE: 0x100032d64 (shaderAccessor1, 1.3.15)
    func shaderAccessor1(_ index: Int) -> MPVShader? {
        guard index >= 0, index < shaders.count else { return nil }
        return shaders[index]
    }

    /// Shader array accessor variant.
    /// RE: 0x100040350 (shaderAccessor3, 1.3.15)
    func shaderAccessor3(_ index: Int) -> MPVShader? {
        guard index >= 0, index < enabledShaders.count else { return nil }
        return enabledShaders[index]
    }

    // MARK: - Quality (RE: Anime4K_configureQualityLevel @ 0x10133df5c)

    /// RE: 0x10133df5c (Anime4K_configureQualityLevel, 1.3.15)
    public func configureQualityLevel(_ level: Int) {
        intermediatePixelFormat = MTLPixelFormat(rawValue: UInt(level)) ?? .rgba16Float
    }

    // MARK: - MPV Shader Copy/Destroy (RE: 0x10000cb6c, 0x10133de78)

    /// Copy MPV-format shader data. Returns a deep copy of the current `shaders` array.
    /// Per the binary, this copies the `MPVShader` value-type data via the
    /// MPVShader value-witness table's `initializeWithCopy`.
    /// RE: 0x10000cb6c (Anime4K_copyMPVShader, 1.3.15)
    public func copyMPVShader() -> [MPVShader] {
        shaders
    }

    /// Release compiled pipelines + library. Clears all compiled state.
    /// RE: 0x10133de78 (Anime4K_destroyMPVShader, 1.3.15)
    public func destroyMPVShader() {
        libraries.removeAll()
        defaultLibrary = nil
        pipelineStates.removeAll()
        enabledShaders.removeAll()
        finalResizePSCache.removeAll()
        textureMap.removeAll()
        nearestSamplerStates.removeAll()
        linearSamplerStates.removeAll()
    }

    // MARK: - Performance Stats (RE: Anime4K_buildPerformanceStatsString @ 0x10145ea10)

    /// Join performance stats into a formatted string. The binary signature is
    /// `(Double, Double, Double, ulong) -> String` where:
    /// - param_1 = lastFrameTime → "- Last: {ms} ms"
    /// - param_2 = averageFrameTime → "- Average: {ms} ms"
    /// - param_3 = estimatedFPS → "- FPS: {fps}"
    /// - param_4 bits: 0x100 = supported, 0x1 = isDropping, high half = preset
    ///
    /// RE: 0x10145ea10 (Anime4K_buildPerformanceStatsString, 1.3.15)
    public static func buildPerformanceStatsString(
        lastFrameTime: Double,
        averageFrameTime: Double,
        estimatedFPS: Double,
        supported: Bool,
        isDropping: Bool,
        preset: Anime4KPreset
    ) -> String {
        var lines: [String] = []
        lines.append("Preset: \(preset)")
        lines.append("- Supported: \(supported ? "true" : "false")")
        lines.append("- Last: \(lastFrameTime * 1000.0) ms")
        lines.append("- Average: \(averageFrameTime * 1000.0) ms")
        lines.append("- FPS: \(estimatedFPS)")
        lines.append("- Dropping: \(isDropping ? "true" : "false")")
        return lines.joined(separator: "\n")
    }

    // MARK: - Center Resize Render Pass (RE: Anime4K_centerResize @ 0x1014597c8)

    /// Terminal Anime4K render pass: builds/caches a CenterResize{Vertex,Fragment}
    /// `MTLRenderPipelineState` per output pixel format (in the +0x50 cache),
    /// sets up a render pass to the output drawable with loadAction .dontCare /
    /// storeAction .store, passes (srcW,srcH,dstW,dstH) as 16 fragment bytes,
    /// and draws a 6-vertex fullscreen quad sampling the upscaled texture.
    ///
    /// Self is the final `Anime4KPipeline.anime4Ks[count-1]` stage object.
    /// Args: device, commandBuffer, source/upscaled texture, output/destination texture.
    ///
    /// RE: 0x1014597c8 (Anime4K_centerResize, 1.3.15)
    public func centerResize(
        device: MTLDevice,
        commandBuffer: MTLCommandBuffer,
        sourceTexture: MTLTexture,
        outputTexture: MTLTexture
    ) throws {
        // Step 1: Prime compute state via buildComputePipelineStates
        // (bail on pending error — the binary calls bl 0x101457a1c here)

        // Step 2: Pixel-format cache key
        let outputFormat = outputTexture.pixelFormat

        // Step 3: Cache lookup in finalResizePSCache (+0x50)
        if finalResizePSCache[outputFormat] == nil {
            // Step 4: Pipeline build on cache miss
            let descriptor = MTLRenderPipelineDescriptor()

            // Load CenterResizeVertex and CenterResizeFragment from defaultLibrary (+0x38)
            guard let library = self.defaultLibrary else {
                throw Anime4KError.encoderCreationFail(
                    "Failed to create render pipeline for format: \(outputFormat.rawValue)"
                )
            }

            // String-anchored: "CenterResizeVertex" at 0x1033396e0, "CenterResizeFragment" at 0x103339700
            guard let vertexFunction = library.makeFunction(name: "CenterResizeVertex") else {
                throw Anime4KError.encoderCreationFail(
                    "Failed to create render pipeline for format: \(outputFormat.rawValue)"
                )
            }
            guard let fragmentFunction = library.makeFunction(name: "CenterResizeFragment") else {
                throw Anime4KError.encoderCreationFail(
                    "Failed to create render pipeline for format: \(outputFormat.rawValue)"
                )
            }

            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = outputFormat

            do {
                let pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
                finalResizePSCache[outputFormat] = pipelineState
            } catch {
                throw error
            }
        }

        // Step 5: Re-lookup — guard against missing pipeline
        guard let renderPipeline = finalResizePSCache[outputFormat] else {
            throw Anime4KError.encoderCreationFail(
                "Failed to create render pipeline for format: \(outputFormat.rawValue)"
            )
        }

        // Step 6: Viewport struct (16 B = 4 x Float): srcW, srcH, dstW, dstH
        var viewport: [Float] = [
            Float(sourceTexture.width),
            Float(sourceTexture.height),
            Float(outputTexture.width),
            Float(outputTexture.height)
        ]

        // Step 7: Render-pass descriptor
        let rpDescriptor = MTLRenderPassDescriptor()
        rpDescriptor.colorAttachments[0].texture = outputTexture
        rpDescriptor.colorAttachments[0].loadAction = .dontCare   // MTLLoadActionDontCare = 0
        rpDescriptor.colorAttachments[0].storeAction = .store     // MTLStoreActionStore = 1

        // Step 8: Encode the fullscreen-quad draw
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpDescriptor) else {
            throw Anime4KError.encoderCreationFail("RenderCommandEncoder creation failed")
        }

        encoder.setRenderPipelineState(renderPipeline)
        // Bind source (upscaled) texture to fragment slot 0
        encoder.setFragmentTexture(sourceTexture, index: 0)
        // Pass the 16-byte viewport struct as fragment bytes at index 0
        encoder.setFragmentBytes(&viewport, length: MemoryLayout<Float>.size * 4, index: 0)
        // Draw 6 vertices = 2 triangles = one fullscreen quad
        // Primitive type 3 = .triangle (NOT triangleStrip)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
    }

    // MARK: - Quality Suffix (RE: Anime4K_appendQualitySuffix @ 0x101459e74)

    /// Append quality suffix derived from the active `Anime4KPreset` to a shader name.
    /// The genuine quality suffix is derived from the preset, not from the
    /// `intermediatePixelFormat` constant.
    /// RE: 0x101459e74 (Anime4K_appendQualitySuffix, 1.3.15)
    public func appendQualitySuffix(_ name: String, preset: Anime4KPreset = .disabled) -> String {
        "\(name)_q\(preset.rawValue)"
    }

    // MARK: - Filter (RE: Anime4K_filterCharacters @ 0x101459f18)

    /// Remove `()-.` from string (shader name sanitization for Metal function identifiers).
    /// Binary verified set: 0x29 `)`, 0x28 `(`, 0x2d `-`, 0x2e `.`
    /// RE: 0x101459f18 (Anime4K_filterCharacters, 1.3.15)
    public func filterCharacters(_ input: String) -> String {
        input.filter { $0 != "(" && $0 != ")" && $0 != "-" && $0 != "." }
    }

    // MARK: - Shader Value Init (RE: Anime4K_initializeShaderValue @ 0x1000054f4)

    /// Initialize default shader parameter values. Sets up the initial state
    /// for shader parameters before compilation/evaluation.
    /// RE: 0x1000054f4 (Anime4K_initializeShaderValue, 1.3.15)
    public func initializeShaderValue() {
        // Initialize shader fields to defaults per the binary's init pattern:
        // Zero the size-tracking scalars, reset the buffer index, clear maps.
        bufferIndex = -1
        outputW = 0
        outputH = 0
        textureInW = 0
        textureInH = 0
        displayActualW = 0
        displayActualH = 0
        sizeMap.removeAll()
    }

    // MARK: - String Comparison Helpers (RE: 0x10145a048, 0x10145a104, 0x10145a178)

    /// String comparison helper.
    /// RE: 0x10145a048 (Anime4K_compareStringRange, 1.3.15)
    func compareStringRange(_ a: String, _ b: String) -> Bool {
        a == b
    }

    /// Small string comparison (optimized path for short strings).
    /// RE: 0x10145a104 (Anime4K_compareSmallStringRange, 1.3.15)
    func compareSmallStringRange(_ a: String, _ b: String) -> Bool {
        a == b
    }

    /// String comparison variant — third comparison helper.
    /// RE: 0x10145a178 (Anime4K_compareStringRange2, 1.3.15)
    func compareStringRange2(_ a: String, _ b: String) -> Bool {
        a == b
    }

    // MARK: - MD5 Cache Key

    /// MD5 hash helper used by `compileOrLoadShaders` for cache keys and
    /// Metal function naming. Produces a deterministic hex string from the input.
    /// The binary uses `CryptoKit.Insecure.MD5` with `"%02X"` format (uppercase hex).
    /// RE: derived from compileOrLoadShaders @ 0x1014538d4 (CryptoKit.Insecure.MD5 usage)
    func md5Hash(_ string: String) -> String {
        #if canImport(CryptoKit)
        let data = Data(string.utf8)
        let digest = Insecure.MD5.hash(data: data)
        // Binary uses "%02X" (uppercase hex, format literal 0x58323025)
        return digest.map { String(format: "%02X", $0) }.joined()
        #else
        return String(string.hashValue)
        #endif
    }

    // MARK: - Deinit (RE: Anime4K_deinit @ 0x1003b4e74)

    /// Deinit releases the contiguous run of refcounted fields:
    /// swift_bridgeObjectRelease(self+0x18) (name String), then swift_release
    /// over self+0x28..+0x70 (shaders..sizeMap). POD fields at +0x78..+0x94
    /// are not touched.
    /// RE: 0x1003b4e74 (Anime4K_deinit, 1.3.15)
    deinit {
        destroyMPVShader()
    }
}
