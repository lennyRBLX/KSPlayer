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
import Metal

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

    init(name: String, url: URL, device: MTLDevice, usePrecompiled: Bool, bufferCount: Int) throws {
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
    ///   • ⚑ the `String(describing:)` spelling is the one detail the decompile does not discriminate:
    ///     a CustomStringConvertible `description` witness IS invoked (so it is not `String(_: Int)`,
    ///     which would not call it), but interpolation `"\(…)"` is an equivalent-codegen alternative.
    private func parseShaders(_ text: String) throws -> [MPVShader] {
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
                        let target = String(tokens[1].split(separator: ".")[0])
                        if tokens[2] == "*" {
                            current!.width = (target, Float(tokens[3])!)
                        } else if tokens[2] == "/" {
                            current!.width = (target, 1.0 / Float(tokens[3])!)
                        } else {
                            throw GLSLError.parseFail(line)
                        }
                    } else if tokens.count == 2 {
                        current!.width = (String(tokens[1].split(separator: ".")[0]), 1.0)
                    }
                case "HEIGHT":
                    if tokens.count == 4 {
                        let target = String(tokens[1].split(separator: ".")[0])
                        if tokens[2] == "*" {
                            current!.height = (target, Float(tokens[3])!)
                        } else if tokens[2] == "/" {
                            current!.height = (target, 1.0 / Float(tokens[3])!)
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

    /// ⚑ INFERRED name ⚑[tool=recover_swift_function_name ref=regexMatches:0x101a7dfe8 result=none]
    ///   — `#function` is absent from the stripped image and the tool returns no name. The signature
    ///   is read off the call site: (pattern String, subject String) -> [String], where element 0 is
    ///   the whole match and element 1 the first capture group (`parseShaders` tests `count == 2`).
    /// ⚑[tool=decompile ref=regexMatches:0x101a7dfe8 result=pinned] BODY NOT RECONSTRUCTED (300
    ///   instructions). It is a real private method rather than an inlined closure because it has a
    ///   second caller — the shader-source transform @0x101a7cd84 — so it lands with that transform
    ///   in the follow-on commit. `fatalError` is deliberate: returning `[]` would fabricate a
    ///   plausible-but-wrong "no match". Unreachable today — nothing reconstructed instantiates
    ///   `Anime4K`.
    private func regexMatches(_ pattern: String, _ text: String) -> [String] {
        fatalError("⚑[tool=decompile ref=regexMatches:0x101a7dfe8 result=pinned] not yet reconstructed")
    }
}
