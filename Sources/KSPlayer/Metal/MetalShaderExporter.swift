//
//  MetalShaderExporter.swift
//  KSPlayer
//
//  RE source: v1.3.15 — class-metadata accessor at 0x1014652bc
//  Dev/diagnostic utility: walks the Anime4K shader set, transpiles each via
//  GLSL→Metal, and writes the resulting .metal files to outputDirectory.
//

#if canImport(Metal)
import Metal
import Foundation

/// Error type thrown by ``MetalShaderExporter``.
///
/// RE: 0x1014652bc (ExporterError, 1.3.15) — `enum KSPlayer.ExporterError`, 2 cases.
public enum ExporterError: Error {
    /// A shader/file path or reason string for a failed write/compile.
    case exportFailed(String)
    /// `MTLCreateSystemDefaultDevice()` returned nil, so nothing can be compiled/exported.
    case noMetalDevice
}

/// Dev/diagnostic utility that walks the Anime4K shader set, transpiles each via
/// the GLSL→Metal path, and writes `.metal` files to `outputDirectory`.
///
/// RE: 0x1014652bc (MetalShaderExporter class metadata accessor, 1.3.15)
public final class MetalShaderExporter {
    /// Metal device used to compile shaders before export.
    public let device: MTLDevice
    /// Directory the transpiled/compiled shaders are written to.
    public let outputDirectory: URL

    /// RE: 0x101465080 (MetalShaderExporter.init, 1.3.15)
    ///
    /// Throwing designated init. Calls `MTLCreateSystemDefaultDevice()` internally;
    /// throws `ExporterError.noMetalDevice` if nil. Eagerly creates `outputDirectory`
    /// on disk (mkdir -p); directory-creation failure propagates as a throw.
    public init(outputDirectory: URL) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ExporterError.noMetalDevice
        }
        self.device = device
        self.outputDirectory = outputDirectory
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    /// RE: 0x101465a2c (MetalShaderExporter.compileAndCacheShaders, 1.3.15)
    ///
    /// The real export writer. Processes one shader entry: loads/parses the GLSL via
    /// `Anime4K.compileOrLoadShaders`, builds an output filename (.glsl → .metal),
    /// transpiles each pass via `Anime4KPipeline.GLSLtoMetalTranspiler`, prepends
    /// auto-generated headers, and writes the result to disk.
    ///
    /// Sole caller is the export driver (FUN_1014652f4) which loops a 14-entry shader
    /// table invoking this per entry.
    ///
    /// - Parameters:
    ///   - name: The shader name (e.g. "Anime4K_Clamp_Highlights.glsl").
    ///   - originalFunctionName: The original function name for header attribution.
    ///   - subdirectory: Per-shader subdirectory name under `outputDirectory`.
    public func compileAndCacheShaders(name: String, originalFunctionName: String, subdirectory: String) {
        let shaderDir = outputDirectory.appendingPathComponent(subdirectory)

        // Print target path header
        KSLog(level: .info, "\(shaderDir.path)")

        // Load/parse the GLSL into the [MPVShader] pass list via the same loader
        // documented at compileOrLoadShaders @0x1014538d4
        let anime4k = Anime4K(name: name)
        do {
            try anime4k.compileOrLoadShaders(name: name, device: device)
        } catch {
            KSLog(level: .warning, "Failed to load shaders for \(name): \(error)")
            return
        }

        // Build the output filename: replace .glsl extension with .metal
        let outputFileName = name.replacingOccurrences(of: ".glsl", with: ".metal")
        let outputURL = shaderDir.appendingPathComponent(outputFileName)

        // Ensure the per-shader subdirectory exists
        try? FileManager.default.createDirectory(at: shaderDir, withIntermediateDirectories: true)

        // Transpile each pass and assemble the .metal text
        for pass in anime4k.shaders {
            let metalSource = Anime4KPipeline.GLSLtoMetalTranspiler(pass)

            // Prepend auto-generated headers (verified string literals @0x10333a660, @0x10333a6b0)
            var output = ""
            output.append("\n// Auto-generated from \(name)")
            output.append("\n// Original function name: \(originalFunctionName)\n\n")
            output.append(metalSource)

            // Write to disk: String.write(to:atomically:encoding:.utf8)
            do {
                try output.write(to: outputURL, atomically: true, encoding: .utf8)
                KSLog(level: .info, "\(name) (\(pass.name))")
            } catch {
                KSLog(level: .warning, "Failed to write \(outputURL.path): \(error)")
            }
        }
    }
}
#endif
