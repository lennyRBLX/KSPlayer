//
//  Anime4K.swift
//  KSPlayer
//
//  Forward 1.3.17 reconstruction. `Anime4K` loads and compiles a bundled MPV-format `.glsl` shader
//  into Metal libraries/pipeline states for real-time upscaling. It is the core of the Anime4K
//  subsystem (held by `Anime4KPipeline.anime4Ks`). Root class (super=None).
//
//  ⚑ THIS COMMIT IS A PARTIAL (Tier-B campaign, commit 1 of the Anime4K class):
//    • The 20-field LAYOUT is fully decoded (names/order/types/let-var — nominal descriptor 0x1039f0878,
//      __swift5_fieldmd; the two symref types resolved: defaultLibrary "So10MTLLibrary_p"=MTLLibrary,
//      finalResizePSCache key symref -> MTLPixelFormat / value MTLRenderPipelineState).
//    • init @0x101a70318 is reconstructed ONLY for its certain parts (name, bufferCount clamp,
//      defaultLibrary). The shader file-read + parse (parseShaders @0x101a7e52c) and the per-shader
//      Metal-compile loop building `libraries` (transformSource @0x101a7cd84 + makeLibrary(source:))
//      are PINNED to follow-on commits (see the ⚑ markers in init). `shaders`/`libraries` hold []
//      placeholders that a follow-on commit fills. No reconstructed code instantiates Anime4K yet, so
//      the placeholders are unreachable.
//    • The var fields' `= []`/`[:]`/`0`/`-1` are the init's decoded constant defaults (written as
//      declaration defaults; the init's compiler prologue sets them). intermediatePixelFormat default
//      = .rgba16Float (raw 0x73=115).
//    • access level ⚑ INFERRED `public` ⚑[tool=nm ref=Anime4K result=local-symbols-stripped];
//      non-`final` from the 46-slot accessor vtable (a final class emits none).
//
import Foundation
import CryptoKit
import Metal
import simd

public class Anime4K {
    let intermediatePixelFormat: MTLPixelFormat = .rgba16Float
    let bufferCount: Int
    let name: String
    let shaders: [MPVShader]
    let libraries: [MTLLibrary]
    let defaultLibrary: MTLLibrary
    var enabledShaders: [MPVShader] = []
    var pipelineStates: [MTLComputePipelineState] = []
    var finalResizePSCache: [MTLPixelFormat: MTLRenderPipelineState] = [:]
    var textureMap: [[String: MTLTexture]] = []
    var nearestSamplerStates: [MTLSamplerState] = []
    var linearSamplerStates: [MTLSamplerState] = []
    var sizeMap: [String: (Float, Float)] = [:]
    var bufferIndex: Int = -1
    var outputW: Float = 0
    var outputH: Float = 0
    var textureInW: Float = 0
    var textureInH: Float = 0
    var displayActualW: Float = 0
    var displayActualH: Float = 0

    // L7 lane 21: Forward keeps the designated init out of line (self in x20; exportShader @0x101a81064 and
    // Anime4KPipeline @0x101a79b84 both `bl 0x101a70318`); the build inlined it into both callers.
    // ⚑[invented=init(name:url:device:usePrecompiled:bufferCount:) addr=0x101a70318 exhaustion=name_exhaustion_gate approved=jweaver]
    @inline(never)
    init(name: String, url: String, device: MTLDevice, usePrecompiled: Bool, bufferCount: Int) throws {
        self.name = name
        self.bufferCount = max(bufferCount, 1)
        // ⚑[tool=decompile ref=Anime4K.init:0x101a70318 result=pinned] `parseShaders` IS reconstructed
        //   below as of this commit, but the init's own shader FILE-READ that feeds it
        //   (url.appendingPathComponent(name) -> Data(contentsOf:) -> String, throwing on a decode
        //   failure) is a separate part of init's ~1400-instruction body and is NOT yet verified —
        //   its throw's error type has not been discharged at that site (session 55 proved this
        //   subsystem uses TWO distinct error enums, so init's throws must be read individually, not
        //   assumed). It lands with the compile loop in the follow-on commit; `shaders` holds []
        //   until then, and `self.shaders = try parseShaders(source)` is wired at the same time.
        self.shaders = []
        // ⚑ bundle .module INFERRED (DAT_104c63040 = the lazily-inited resource bundle read across KSPlayer).
        self.defaultLibrary = try device.makeDefaultLibrary(bundle: .module)
        // ⚑[tool=decompile ref=transformSource:0x101a7cd84 result=pinned] the per-shader Metal-compile loop
        //   building `libraries` (usePrecompiled branch + MD5 cache key + transformSource +
        //   device.makeLibrary(source:options:), throws on compile failure) lands in a follow-on commit;
        //   `libraries` holds [] for now.
        self.libraries = []
    }

    /// Parses the MPV-format `.hook` shader text into `[MPVShader]` (@0x101a7e52c, 693 instructions;
    /// its only caller is `init`). Reconstructed from the full control flow + every string constant.
    ///
    /// Decode notes (the non-obvious calls, so a reader need not re-derive them):
    ///   • the empty-line test really is `count == 0` — the binary calls `String.get_count`, which
    ///     `isEmpty` would not.
    ///   • a `//!` line is handled by MUTATING a copy: the binary stores the line to a frame slot,
    ///     retains it (the +1 that forces COW), calls `String.removeSubrange` for the first 3
    ///     characters, then RE-LOADS that slot. So the tokens and `WHEN` see the stripped copy while
    ///     the untouched original survives — which is why `throw` carries `line`, not `directive`.
    ///   • the numeric parsers differ deliberately: sigma is optional-bound (the assignment sits
    ///     inside the parser's success branch, and a failure leaves sigma untouched), WIDTH/HEIGHT
    ///     force-unwrap (a parse failure traps), and COMPONENTS assigns the `Int?` straight through
    ///     (both the value and the Optional tag byte are stored). Confirmed by dyld bind:
    ///     @0x101a972e8 -> __swift_stdlib_strtod_clocale (Double), @0x101a7ccac ->
    ///     __swift_stdlib_strtof_clocale (Float).
    ///   • `max(Int(sigma), 1)` is the binary's `if n < 2 { n = 1 }` — identical over Int — and
    ///     `n * 2 + 1` is its `n << 1 | 1`.
    ///   • WIDTH/HEIGHT with 4 tokens: the OPERATOR is `tokens[3]` and the scale is `Float(tokens[2])`,
    ///     which reads backwards but is what the binary does. Element base is +0x20, stride 0x10, so
    ///     the operator compare loads +0x50 (index 3) while the value fed to the Float parser loads
    ///     +0x40 (index 2) under a `count < 3` bounds check — a `count < 4` check would be required
    ///     to subscript index 3, and none is emitted. The operator is compared BEFORE the target
    ///     split, and each of the `*` and `/` arms performs that split independently, so a malformed
    ///     operator throws without the split's trapping subscript ever running.
    ///   • ⚑ the `String(describing:)` spelling is the one detail the decompile does not discriminate:
    ///     a CustomStringConvertible `description` witness IS invoked (so it is not `String(_: Int)`,
    ///     which would not call it), but interpolation `"\(…)"` is an equivalent-codegen alternative.
    // ⚑[invented=configure addr=0x101a71b00 exhaustion=name_exhaustion_gate approved=jweaver]
    func configure(
        _ device: MTLDevice,
        _ nativeWidth: Int,
        _ nativeHeight: Int,
        _ mainWidth: Int,
        _ mainHeight: Int,
        _ displayLimitWidth: Int,
        _ displayLimitHeight: Int
    ) throws {
        enabledShaders = []
        nearestSamplerStates = []
        linearSamplerStates = []
        pipelineStates = []
        textureMap = []
        sizeMap = [:]
        bufferIndex = -1

        textureInW = Float(mainWidth)
        textureInH = Float(mainHeight)

        let scale = min(Float(displayLimitWidth) / Float(nativeWidth),
                        Float(displayLimitHeight) / Float(nativeHeight))
        displayActualW = (scale * Float(nativeWidth)).rounded()
        displayActualH = (scale * Float(nativeHeight)).rounded()
        // Forward stores 0x88/0x8c after 0x98/0x9c (stp @0x101a71d98).
        outputW = textureInW
        outputH = textureInH

        sizeMap["MAIN"] = (Float(mainWidth), Float(mainHeight))
        sizeMap["NATIVE"] = (Float(nativeWidth), Float(nativeHeight))
        sizeMap["OUTPUT"] = (displayActualW, displayActualH)
        print("[Anime4K] Size map: MAIN=\(mainWidth)x\(mainHeight), NATIVE=\(nativeWidth)x\(nativeHeight), OUTPUT=\(displayActualW)x\(displayActualH)")

        for (index, shader) in shaders.enumerated() {
            if let when = shader.when {
                // Forward: 30-char literal then append(name), append(": "), append(when), no grow.
                print("[Anime4K] Evaluating WHEN for " + shader.name + ": " + when)
                print("[Anime4K] Current sizeMap: MAIN=\(sizeMap["MAIN"]?.0 ?? 0)x\(sizeMap["MAIN"]?.1 ?? 0), OUTPUT=\(sizeMap["OUTPUT"]?.0 ?? 0)x\(sizeMap["OUTPUT"]?.1 ?? 0)")

                let tokens = when.split(separator: " ").map(String.init).filter { $0 != "WHEN" }
                var stack = [Float]()
                for token in tokens {
                    switch token {
                    case "+", "-", "*", "/", "<", ">":
                        let rhs = stack.removeLast()
                        let lhs = stack.removeLast()
                        let result: Float
                        switch token {
                        case "+":
                            result = lhs + rhs
                        case "-":
                            result = lhs - rhs
                        case "*":
                            result = lhs * rhs
                        case "/":
                            result = lhs / rhs
                        case "<":
                            result = lhs < rhs ? 1 : 0
                        case ">":
                            result = lhs > rhs ? 1 : 0
                        default:
                            fatalError("Should not reach here", line: 201)
                        }
                        print("[Anime4K]   \(lhs) \(token) \(rhs) = \(result)")
                        stack.append(result)
                    default:
                        if token.hasSuffix(".w") {
                            let key = String(token.dropLast(2))
                            let value = sizeMap[key]!.0
                            print("[Anime4K]   Push \(key).w = \(value)")
                            stack.append(value)
                        } else if token.hasSuffix(".h") {
                            let key = String(token.dropLast(2))
                            let value = sizeMap[key]!.1
                            print("[Anime4K]   Push \(key).h = \(value)")
                            stack.append(value)
                        } else {
                            let number = Float(token)!
                            print("[Anime4K]   Push number: \(number)")
                            stack.append(number)
                        }
                    }
                }

                guard stack.count == 1 else {
                    throw Anime4KError.encoderFail("Failed to evaluate WHEN condition: \(when), stack count: \(stack.count)")
                }
                let result = stack.removeLast()
                // Forward interpolates shader.name here (retain of the name bridge @grow(0x2a)).
                print("[Anime4K] WHEN condition result for \(shader.name): \(result)")
                if result == 0 {
                    print("[Anime4K] ❌ Skip shader \(shader.name) - WHEN condition failed")
                    continue
                }
                print("[Anime4K] ✅ Enable shader \(shader.name) - WHEN condition passed")
            }

            enabledShaders.append(shader)
            let library = libraries[index]
            outputW = textureInW
            outputH = textureInH

            if let hook = shader.hook {
                // Forward's missing-key path removes "HOOKED" (0x1019c18a4 @0x101a73888), no trap.
                sizeMap["HOOKED"] = sizeMap[hook]
            }
            if let width = shader.width {
                outputW = width.1 * sizeMap[width.0]!.0
            }
            if let height = shader.height {
                outputH = height.1 * sizeMap[height.0]!.1
            }
            if let save = shader.save, save != "MAIN" {
                sizeMap[save] = (outputW, outputH)
            }

            // Forward: every name use goes through the ".-()" filter (0x101a7688c), recomputed at
            // each site; error texts are `+` chains (literal seed, no grow); UTF-8 bytes via
            // data(using:)! (_data(using:allowLossyConversion:) + nil trap).
            var function = library.makeFunction(name: shader.name.filter { !".-()".contains($0) })
            if function == nil {
                if shaders.count < 2 {
                    throw Anime4KError.encoderFail("Function '" + shader.name.filter { !".-()".contains($0) } + "' not found in library")
                }

                let nameWithoutGLSLSuffix = shader.name.replacingOccurrences(of: ".glsl", with: "")
                let hashInput = "\(nameWithoutGLSLSuffix)_\(index)".data(using: .utf8)!
                let digest = Insecure.MD5.hash(data: hashInput)
                    .map { String(format: "%02X", $0) }
                    .joined()
                let functionName = shader.name.filter { !".-()".contains($0) } + "_" + digest
                function = library.makeFunction(name: functionName)
                if function == nil {
                    throw Anime4KError.encoderFail("Function '" + shader.name.filter { !".-()".contains($0) } + "' or '" + functionName + "' not found in library")
                }
            }

            let pipelineState = try device.makeComputePipelineState(function: function!)
            pipelineStates.append(pipelineState)
        }
    }

    // ⚑[invented=encode addr=0x101a7448c exhaustion=name_exhaustion_gate approved=jweaver]
    func encode(
        _ device: MTLDevice,
        _ commandBuffer: MTLCommandBuffer,
        _ inputTexture: MTLTexture
    ) throws -> MTLTexture {
        guard pipelineStates.count == enabledShaders.count else {
            throw Anime4KError.encoderFail("Pipeline state count \(pipelineStates.count) mismatch shader count \(shaders.count)")
        }
        if pipelineStates.isEmpty {
            return inputTexture
        }

        bufferIndex = (bufferIndex + 1) % bufferCount
        if textureMap.count <= bufferIndex {
            textureMap.append([:])
            let samplerDescriptor = MTLSamplerDescriptor()
            samplerDescriptor.magFilter = .nearest
            samplerDescriptor.minFilter = .nearest
            samplerDescriptor.sAddressMode = .clampToEdge
            samplerDescriptor.tAddressMode = .clampToEdge
            nearestSamplerStates.append(device.makeSamplerState(descriptor: samplerDescriptor)!)
            samplerDescriptor.magFilter = .linear
            samplerDescriptor.minFilter = .linear
            linearSamplerStates.append(device.makeSamplerState(descriptor: samplerDescriptor)!)
        }

        textureMap[bufferIndex]["MAIN"] = inputTexture
        textureMap[bufferIndex]["NATIVE"] = inputTexture

        // Forward converts outputW/outputH at each use (after `output.width` @0x101a74864 and after
        // the descriptor alloc @0x101a74a60), not hoisted before the lookup.
        if let output = textureMap[bufferIndex]["output"],
           output.width == Int(outputW),
           output.height == Int(outputH),
           output.pixelFormat == intermediatePixelFormat {
        } else {
            let descriptor = MTLTextureDescriptor()
            descriptor.width = Int(outputW)
            descriptor.height = Int(outputH)
            descriptor.pixelFormat = intermediatePixelFormat
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .private
            textureMap[bufferIndex]["output"] = device.makeTexture(descriptor: descriptor)
        }

        for (index, shader) in enabledShaders.enumerated() {
            var stageWidth = textureInW
            var stageHeight = textureInH
            if let hook = shader.hook {
                // Forward's nil path @0x101a74d48 removes "HOOKED" (0x1019c18a4), no trap.
                sizeMap["HOOKED"] = sizeMap[hook]
            }
            if let width = shader.width {
                stageWidth = width.1 * sizeMap[width.0]!.0
            }
            if let height = shader.height {
                stageHeight = height.1 * sizeMap[height.0]!.1
            }

            guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
                let filteredName = shader.name.filter { !".-()".contains($0) }
                throw Anime4KError.encoderCreationFail(filteredName)
            }
            encoder.setComputePipelineState(pipelineStates[index])
            let sampler = textureInW <= stageWidth
                ? nearestSamplerStates[bufferIndex]
                : linearSamplerStates[bufferIndex]
            encoder.setSamplerState(sampler, index: 0)

            var binds = shader.binds
            if shader.hook == "MAIN", !binds.contains("MAIN") {
                binds.append("MAIN")
            }
            // Forward: missing key -> (save check | throw) -> create; then ONE setTexture of the
            // dictionary lookup (0x101a75124..0x101a754ac); "HOOKED" with nil hook keeps "HOOKED".
            for (bindIndex, bind) in binds.enumerated() {
                var effectiveKey = bind
                if bind == "HOOKED", let hook = shader.hook {
                    effectiveKey = hook
                }
                if textureMap[bufferIndex][effectiveKey] == nil {
                    guard effectiveKey == shader.save else {
                        throw Anime4KError.encoderFail("texture \(effectiveKey) is missing")
                    }
                    let descriptor = MTLTextureDescriptor()
                    descriptor.width = Int(stageWidth)
                    descriptor.height = Int(stageHeight)
                    descriptor.pixelFormat = intermediatePixelFormat
                    descriptor.usage = [.shaderRead, .shaderWrite]
                    descriptor.storageMode = .private
                    textureMap[bufferIndex][effectiveKey] = device.makeTexture(descriptor: descriptor)
                }
                encoder.setTexture(textureMap[bufferIndex][effectiveKey], index: bindIndex)
            }

            let outputKey: String
            if let save = shader.save, save != "MAIN" {
                outputKey = save
            } else {
                outputKey = "output"
            }
            // Forward: contains() on the raw shader.binds (0x10001e034 with the pre-append array),
            // nil lookup as the `||` fallback, one shared create site (0x101a757d4).
            if shader.binds.contains(outputKey) || textureMap[bufferIndex][outputKey] == nil {
                if let output = textureMap[bufferIndex][outputKey],
                   output.width == Int(stageWidth),
                   output.height == Int(stageHeight),
                   output.pixelFormat == intermediatePixelFormat {
                } else {
                    let descriptor = MTLTextureDescriptor()
                    descriptor.width = Int(stageWidth)
                    descriptor.height = Int(stageHeight)
                    descriptor.pixelFormat = intermediatePixelFormat
                    descriptor.usage = [.shaderRead, .shaderWrite]
                    descriptor.storageMode = .private
                    textureMap[bufferIndex][outputKey] = device.makeTexture(descriptor: descriptor)
                }
            }

            let outputTexture = textureMap[bufferIndex][outputKey]!
            encoder.setTexture(outputTexture, index: binds.count)
            let threadgroups = MTLSize(
                width: (outputTexture.width + 15) / 16,
                height: (outputTexture.height + 15) / 16,
                depth: outputTexture.arrayLength
            )
            let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
            encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
            encoder.endEncoding()
        }

        return textureMap[bufferIndex]["output"]!
    }

    // ⚑[invented=encode addr=0x101a76090 exhaustion=name_exhaustion_gate approved=jweaver]
    func encode(
        _ device: MTLDevice,
        _ commandBuffer: MTLCommandBuffer,
        _ inputTexture: MTLTexture,
        _ outputTexture: MTLTexture
    ) throws {
        let resizedTexture = try encode(device, commandBuffer, inputTexture)
        let pixelFormat = outputTexture.pixelFormat

        if finalResizePSCache[pixelFormat] == nil {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = defaultLibrary.makeFunction(name: "CenterResizeVertex")
            descriptor.fragmentFunction = defaultLibrary.makeFunction(name: "CenterResizeFragment")
            descriptor.colorAttachments[0]!.pixelFormat = pixelFormat
            finalResizePSCache[pixelFormat] = try device.makeRenderPipelineState(descriptor: descriptor)
        }

        guard let pipelineState = finalResizePSCache[pixelFormat] else {
            throw Anime4KError.encoderFail(
                "Failed to create render pipeline for format: \(pixelFormat)"
            )
        }

        // Forward @0x101a76298..0x101a762c4: four scalar Floats held in s8/s9/s10/s0 across the
        // width/height sends, then `stp s8,s9` / `stp s10,s0` into one 16-byte stack slot — a plain
        // 4-Float tuple, not a SIMD4 lane-insert chain. L7 lane 21: all four values are computed before
        // the first store, so the tuple is assigned as one value (an initializing `var sizes = (…)` stores
        // each element right after its scvtf).
        var sizes: (Float, Float, Float, Float)
        sizes = (
            Float(resizedTexture.width),
            Float(resizedTexture.height),
            Float(outputTexture.width),
            Float(outputTexture.height)
        )

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0]!.texture = outputTexture
        pass.colorAttachments[0]!.loadAction = .dontCare
        pass.colorAttachments[0]!.storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            throw Anime4KError.encoderCreationFail("RenderCommandEncoder for CenterResize")
        }
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(resizedTexture, index: 0)
        encoder.setFragmentBytes(&sizes, length: 16, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
    }

    private final func parseShaders(_ text: String) throws -> [MPVShader] {
        var shaders = [MPVShader]()
        var current: MPVShader?
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for line in lines {
            if line.count == 0 {
                continue
            }
            if !line.hasPrefix("//") {
                if line.contains("#define SPATIAL_SIGMA") {
                    let matches = regexMatches("#define SPATIAL_SIGMA (\\d+).*", line)
                    if matches.count == 2, let sigma = Double(matches[1]) {
                        current!.sigma = sigma
                    }
                }
                if line.contains("#define KERNELSIZE int(max(int(SPATIAL_SIGMA), 1) * 2 + 1)"),
                   let sigma = current!.sigma {
                    current!.code.append("#define KERNELSIZE " + String(describing: max(Int(sigma), 1) * 2 + 1))
                } else {
                    current!.code.append(line)
                }
            } else if line.hasPrefix("//!") {
                var directive = line
                directive.removeFirst(3)
                let tokens = directive.split(separator: " ").map(String.init)
                switch tokens[0] {
                case "DESC":
                    if current != nil {
                        shaders.append(current!)
                    }
                    current = MPVShader(name: tokens[1], hook: nil, binds: [], save: nil, components: nil,
                                        width: nil, height: nil, when: nil, sigma: nil, code: [])
                case "HOOK":
                    current!.hook = tokens[1]
                    if current!.hook == "PREKERNEL" {
                        current!.hook = "MAIN"
                    }
                case "BIND":
                    current!.binds.append(tokens[1])
                case "SAVE":
                    current!.save = tokens[1]
                case "WIDTH":
                    if tokens.count == 4 {
                        if tokens[3] == "*" {
                            current!.width = (String(tokens[1].split(separator: ".")[0]), Float(tokens[2])!)
                        } else if tokens[3] == "/" {
                            current!.width = (String(tokens[1].split(separator: ".")[0]), 1.0 / Float(tokens[2])!)
                        } else {
                            throw GLSLError.parseFail(line)
                        }
                    } else if tokens.count == 2 {
                        current!.width = (String(tokens[1].split(separator: ".")[0]), 1.0)
                    }
                case "HEIGHT":
                    if tokens.count == 4 {
                        if tokens[3] == "*" {
                            current!.height = (String(tokens[1].split(separator: ".")[0]), Float(tokens[2])!)
                        } else if tokens[3] == "/" {
                            current!.height = (String(tokens[1].split(separator: ".")[0]), 1.0 / Float(tokens[2])!)
                        } else {
                            throw GLSLError.parseFail(line)
                        }
                    } else if tokens.count == 2 {
                        current!.height = (String(tokens[1].split(separator: ".")[0]), 1.0)
                    }
                case "COMPONENTS":
                    current!.components = Int(tokens[1])
                case "WHEN":
                    current!.when = directive
                default:
                    throw GLSLError.parseFail(line)
                }
            }
        }
        if current != nil {
            shaders.append(current!)
        }
        return shaders
    }

    /// ⚑[tool=decompile ref=transformSource:0x101a7cd84 result=pinned] the per-shader Metal-compile
    ///   loop that consumes `MPVShader.transformSource` is still pinned in `init` above. Ownership of
    ///   that transform was DISCHARGED this session and it is a method on `MPVShader`, NOT on this
    ///   class — see the note on `regexMatches` below.
}

/// Runs `pattern` over `text` and returns every range of every match, flattened — for each match,
/// element 0 is the whole match and 1+ are its capture groups. That flattening is why
/// `Anime4K.parseShaders` tests `matches.count == 2` and reads `matches[1]`
/// (@0x101a7dfe8, 300 instructions).
///
/// MODULE SCOPE, not a member — this is a decoded fact, not a style choice:
///   • the function TAKES NO SELF. Neither caller sets x20 (swiftself) before the `bl`: the
///     `parseShaders` site @0x101a7ea38 passes x0/x1 = pattern, x2/x3 = text, and the
///     `transformSource` site @0x101a7d3d0 actually uses x20 as an ARGUMENT SOURCE (`mov x2, x20`)
///     without restoring its own self (saved in x23 at its prologue) first. The body never
///     dereferences x20 and freely clobbers it as a scratch inout pointer.
///   • its two callers belong to DIFFERENT types — `Anime4K.parseShaders` and
///     `MPVShader.transformSource` @0x101a7cd84 (that transform reads x20 at offsets 0x00/0x10/0x18/
///     0x20/0x98, which is MPVShader's field layout, and its `MetalShaderExporter` call site copies
///     0xa0 bytes — MPVShader's exact size — into a stack slot and passes it as indirect self). A
///     member marked `private` on `Anime4K` could not be reached from `MPVShader`, so the earlier
///     placement inside the class was wrong.
///   • ⚑ access level INFERRED. The image is stripped, so no linkage survives. `internal` is the
///     minimum that satisfies the observed cross-type call GIVEN this reconstruction's per-type file
///     split; the original almost certainly used `fileprivate`, since the binary's source
///     organisation puts this whole subsystem in one `KSPlayer/Anime4K.swift`. That difference is a
///     consequence of our file layout, not a claim about the binary.
///   • absence of a self at the ABI is NOT by itself proof of a free function — an unused `self` can
///     be dead-argument-eliminated. What forces module scope here is the cross-type call, which is
///     unambiguous. (`parseShaders` has the same no-self signature but only ONE caller,
///     `Anime4K.init`, so nothing forces it out and it stays a private member.)
///
/// ⚑ INFERRED name ⚑[tool=recover_swift_function_name ref=regexMatches:0x101a7dfe8 result=none]
///   — `#function` is absent from the stripped image and the tool returns no name. The body bakes
///   no `#function`/`#file` literal either (its only literal is the interpolation prefix below,
///   and it uses `print`, not `KSLog`), so the name is not recoverable. The signature is read off
///   the `parseShaders` call site: the 29-count literal lands in the first String pair, the line
///   in the second, so pattern precedes text.
///
/// Decode notes:
///   • the range is `NSRange(text.startIndex..., in: text)`. The instantiated mangled type
///     @0x103c30782 is `<symref>y<symref>G`, whose GOT slots dyld-bind to
///     `_$ss16PartialRangeFromVMn` and `_$sSS5IndexVMn` = `PartialRangeFrom<String.Index>`; the
///     lowerBound immediate 0xf has encodedOffset 0 (bits 63:16), i.e. position 0 = `startIndex`.
///   • ⚠️ the `do`/`catch` is NOT visible in the decompile — Ghidra reports
///     "Removing unreachable block (ram,0x000101a7e04c)" and emits no error handling, while the
///     callee glossary still lists print / localizedDescription / getErrorValue. That
///     contradiction is the tell; the block was recovered by disassembling 0x101a7e04c-0x101a7e130
///     (`cbz x21` at 0x101a7e048 is the error test, and the arm ends by returning the empty array).
///   • the message is interpolation, not `+`: the storage is created EMPTY and grown to a
///     compile-time constant 17 before the 15-character literal is stored, and 17 = 15 + 2*1 =
///     `DefaultStringInterpolation.init(literalCapacity:interpolationCount:)`. `String.+` cannot
///     produce a constant 17 because it appends a right-hand side of unknown length. (The
///     opposite call was correct in `GLSLError.errorDescription`, which has no such init.)
///   • `NSRegularExpression(pattern:)`, `matches(in:range:)`, and `print`'s separator/terminator
///     all pass their DEFAULT arguments (options 0, `" "`, `"\n"`), so the source omits them; an
///     explicit `options: []` would be indistinguishable from omission here.
///   • `groups` is a `map`, NOT an append loop. The binary calls
///     `_createNewBuffer(bufferIsUnique: false, minimumCapacity: numberOfRanges,
///     growForAppend: false)` — i.e. a reserve of exactly n — INSIDE the `numberOfRanges != 0`
///     guard and before the loop, which is `Collection.map`'s `if n == 0 { return [] };
///     reserveCapacity(n)`. The per-iteration growth check is the same callee with
///     `(isUnique, count + 1, growForAppend: true)`, so the two are distinguishable by their third
///     argument. An explicit `groups.reserveCapacity(n)` on an append loop does NOT reproduce it:
///     that call would be emitted outside the `n != 0` guard. In-binary control: `parseShaders`'
///     `lines = …map { $0.trimmingCharacters(…) }` emits the identical `(0, n, 0)` call.
func regexMatches(_ pattern: String, _ text: String) -> [String] {
    var result = [String]()
    do {
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            let groups = (0 ..< match.numberOfRanges).map { i -> String in
                if let range = Range(match.range(at: i), in: text) {
                    return String(text[range])
                } else {
                    return ""
                }
            }
            result += groups
        }
    } catch {
        print("invalid regex: \(error.localizedDescription)")
    }
    return result
}
