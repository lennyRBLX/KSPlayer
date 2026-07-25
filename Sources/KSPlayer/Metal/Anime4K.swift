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
        // ⚑[tool=decompile ref=parseShaders:0x101a7e52c result=pinned] the shader file-read
        //   (url.appendingPathComponent(name) -> Data(contentsOf:) -> String; a String-decode failure
        //   throws Anime4KError.fileCorrupt(name)) and parse into [MPVShader] land in a follow-on commit;
        //   `shaders` holds [] for now.
        self.shaders = []
        // ⚑ bundle .module INFERRED (DAT_104c63040 = the lazily-inited resource bundle read across KSPlayer).
        self.defaultLibrary = try device.makeDefaultLibrary(bundle: .module)
        // ⚑[tool=decompile ref=transformSource:0x101a7cd84 result=pinned] the per-shader Metal-compile loop
        //   building `libraries` (usePrecompiled branch + MD5 cache key + transformSource +
        //   device.makeLibrary(source:options:), throws on compile failure) lands in a follow-on commit;
        //   `libraries` holds [] for now.
        self.libraries = []
    }
}
