//
//  Anime4K.swift
//  KSPlayer
//
//  Forward addition (RE): Anime4K shader manager — loads, compiles, and
//  caches Metal compute shaders for anime-specific GPU upscaling.
//  Companion to Anime4KPipeline (which handles GLSL→Metal transpilation).
//
//  Binary: _TtC8KSPlayer7Anime4K (15 functions)
//  RE source: Forward v1.3.15, entry @ 0x1014538d4
//

import Foundation
import Metal
#if canImport(CryptoKit)
import CryptoKit
#endif

public class Anime4K {
    // MARK: - Properties (RE field offsets: instance size 0x98 from
    //         _swift_deallocPartialClassInstance(self, _, 0x98, 7) in Anime4K_compileOrLoadShaders)

    // Refcounted fields +0x10 .. +0x70 — released by Anime4K_deinit (0x1003b4e74).
    public var qualityLevel: Int = 115                  // +0x10  init 0x73 (115)
    private let device: MTLDevice                       // +0x18
    private var shaderSource: String = ""               // +0x20
    private var parsedShaders: [[String: Any]] = []     // +0x28
    private var compiledPipelines: [MTLFunction] = []   // +0x30
    private var metalLibrary: MTLLibrary?               // +0x38

    private var shaderNames: [String] = []              // +0x40
    private var shaderPaths: [String] = []              // +0x48
    private var cachedTextures: [String] = []           // +0x50
    private var qualitySuffixes: [String] = []          // +0x58
    private var filterResults: [String] = []            // +0x60
    private var performanceStats: [String] = []         // +0x68
    /// Frame-time ring buffer text history (the "additional array" slot at +0x70 in the
    /// reversed binary). 30 samples of recent frame timings used by buildPerformanceStatsString.
    private var frameTimeHistory: [String] = []         // +0x70

    // POD perf-monitor scalars +0x78 .. +0x90 — NOT touched by Anime4K_deinit (no swift_release calls).
    // Set by Anime4K_compileOrLoadShaders at init:
    //   *(self+0x78) = 0xFFFFFFFFFFFFFFFF  (-1 sentinel)
    //   *(self+0x80) = 0
    //   *(self+0x88) = 0
    //   *(self+0x90) = 0

    /// "No last sample" sentinel; ring-buffer cursor for the 30-sample frame-time history.
    private var lastSampleIndex: Int = -1               // +0x78  init -1
    /// Most-recent frame time in ms (raw monotonic ns / Double seconds; layout is 8 bytes POD).
    private var lastFrameTimeMs: Double = 0             // +0x80  init 0
    /// Rolling-average frame time in ms over the history window.
    private var averageFrameTimeMs: Double = 0          // +0x88  init 0
    /// "Currently dropping" flag plus packed counters; stored as 64-bit POD per binary.
    private var droppingState: Int64 = 0                // +0x90  init 0

    // MARK: - Init

    public init(device: MTLDevice) {
        self.device = device
    }

    // MARK: - Compile or Load (RE: Anime4K_compileOrLoadShaders @ 0x1014538d4)

    public func compileOrLoadShaders(name: String, source: String, device: MTLDevice, bundle: Bundle? = nil) throws {
        self.shaderSource = source
        let targetBundle = bundle ?? Bundle.main
        let shaderURL = targetBundle.bundleURL.appendingPathComponent(name)

        if let data = try? Data(contentsOf: shaderURL),
           let sourceString = String(data: data, encoding: .utf8) {
            let parsed = Anime4KPipeline.evaluateAndCompile(sourceString)
            self.parsedShaders = parsed

            if let library = try? device.makeLibrary(source: sourceString, options: nil) {
                self.metalLibrary = library
                compiledPipelines = []
                for shader in parsed {
                    if let funcName = shader["name"] as? String,
                       let function = library.makeFunction(name: funcName) {
                        compiledPipelines.append(function)
                    }
                }
                return
            }
        }

        // Fallback: GLSL→Metal transpilation per shader
        for shader in parsedShaders {
            guard let shaderName = shader["name"] as? String else { continue }
            let metalSource = Anime4KPipeline.GLSLtoMetalTranspiler(shaderName)
            let cacheKey = md5Hash("\(shaderName)_\(qualityLevel)")
            if let library = try? device.makeLibrary(source: metalSource, options: nil),
               let function = library.makeFunction(name: cacheKey) {
                compiledPipelines.append(function)
            }
        }
    }

    // MARK: - Quality (RE: Anime4K_configureQualityLevel @ 0x10133df5c)

    public func configureQualityLevel(_ level: Int) {
        qualityLevel = level
    }

    // MARK: - MPV Shader Copy/Destroy (RE: 0x10000cb6c, 0x10133de78)

    public func copyMPVShader() -> Any? {
        nil
    }

    public func destroyMPVShader() {
        compiledPipelines.removeAll()
        metalLibrary = nil
    }

    // MARK: - Performance Stats (RE: Anime4K_buildPerformanceStatsString @ 0x10145ea10)

    public func buildPerformanceStatsString() -> String {
        performanceStats.joined(separator: "\n")
    }

    // MARK: - Resize (RE: Anime4K_centerResize @ 0x1014597c8)

    public func centerResize(width: Int, height: Int, targetWidth: Int, targetHeight: Int) -> (x: Int, y: Int) {
        let x = (targetWidth - width) / 2
        let y = (targetHeight - height) / 2
        return (x, y)
    }

    // MARK: - Quality Suffix (RE: Anime4K_appendQualitySuffix @ 0x101459e74)

    public func appendQualitySuffix(_ name: String) -> String {
        "\(name)_q\(qualityLevel)"
    }

    // MARK: - Filter (RE: Anime4K_filterCharacters @ 0x101459f18)

    public func filterCharacters(_ input: String) -> String {
        input.filter { $0 != "(" && $0 != ")" && $0 != "-" && $0 != "." }
    }

    // MARK: - Shader Value Init (RE: Anime4K_initializeShaderValue @ 0x1000054f4)

    public func initializeShaderValue() {
        // Initialize default shader parameter values
    }

    // MARK: - String Comparison Helpers (RE: 0x10145a048, 0x10145a104, 0x10145a178)

    func compareStringRange(_ a: String, _ b: String) -> Bool {
        a == b
    }

    func compareSmallStringRange(_ a: String, _ b: String) -> Bool {
        a == b
    }

    // MARK: - MD5 Cache Key

    private func md5Hash(_ string: String) -> String {
        #if canImport(CryptoKit)
        let data = Data(string.utf8)
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        return String(string.hashValue)
        #endif
    }

    // MARK: - Deinit (RE: Anime4K_deinit @ 0x1003b4e74)

    deinit {
        destroyMPVShader()
    }
}
