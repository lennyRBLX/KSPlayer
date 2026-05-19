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
    // MARK: - Properties (RE field offsets: 0x10 - 0x70)

    public var qualityLevel: Int = 115
    private let device: MTLDevice
    private var shaderSource: String = ""
    private var parsedShaders: [[String: Any]] = []
    private var compiledPipelines: [MTLFunction] = []
    private var metalLibrary: MTLLibrary?

    private var shaderNames: [String] = []
    private var shaderPaths: [String] = []
    private var cachedTextures: [String] = []
    private var qualitySuffixes: [String] = []
    private var filterResults: [String] = []
    private var performanceStats: [String] = []

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
