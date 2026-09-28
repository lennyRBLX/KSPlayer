//
//  MetalShaderExporter.swift
//  KSPlayer
//
//  Forward 1.3.17 reconstruction. Offline tool: converts the bundled Anime4K GLSL hooks to .metal files.
//  MetalShaderExporter — non-final class, vtable size 3: __allocating_init 0x60 @0x101a804a4, exportAll 0x68, exportShader 0x70.
//
import Foundation
import Metal

// ExporterError @0x1039f0e70 — conformances LocalizedError @0x10356c3a0 + Error @0x10356c3e8;
// custom errorDescription @0x101a818fc. Cases in field-record order (payload case first).
enum ExporterError: LocalizedError {
    case exportFailed(String)
    case noMetalDevice

    var errorDescription: String? {
        switch self {
        case let .exportFailed(message):
            "Export failed: \(message)"
        case .noMetalDevice:
            "No Metal device available"
        }
    }
}

public class MetalShaderExporter {
    private let device: MTLDevice
    private let outputDirectory: URL

    // @0x101a804ec
    public init(outputDirectory: URL) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ExporterError.noMetalDevice
        }
        self.device = device
        self.outputDirectory = outputDirectory
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)
    }

    // slot 0x68 @0x101a80750. The 14-entry (url, name) literal is the static array @0x1044ecaf0.
    public func exportAll() throws {
        print("🔨 Anime4K Metal Shader Exporter")
        print("=================================\n")
        print("📁 Output directory: \(outputDirectory.path)\n")
        let shaders = [
            ("Restore", "Anime4K_Clamp_Highlights.glsl"),
            ("Restore", "Anime4K_Restore_CNN_M.glsl"),
            ("Restore", "Anime4K_Restore_CNN_S.glsl"),
            ("Restore", "Anime4K_Restore_CNN_Soft_M.glsl"),
            ("Restore", "Anime4K_Restore_CNN_Soft_S.glsl"),
            ("Restore", "Anime4K_Restore_CNN_Soft_VL.glsl"),
            ("Restore", "Anime4K_Restore_CNN_VL.glsl"),
            ("Upscale", "Anime4K_AutoDownscalePre_x2.glsl"),
            ("Upscale", "Anime4K_AutoDownscalePre_x4.glsl"),
            ("Upscale", "Anime4K_Upscale_CNN_x2_M.glsl"),
            ("Upscale", "Anime4K_Upscale_CNN_x2_S.glsl"),
            ("Upscale", "Anime4K_Upscale_CNN_x2_VL.glsl"),
            ("Upscale+Denoise", "Anime4K_Upscale_Denoise_CNN_x2_M.glsl"),
            ("Upscale+Denoise", "Anime4K_Upscale_Denoise_CNN_x2_VL.glsl"),
        ]
        var successCount = 0
        var failCount = 0
        for (url, name) in shaders {
            do {
                try exportShader(name: name, url: url)
                successCount += 1
            } catch {
                print("❌ Failed to export \(name): \(error)")
                failCount += 1
            }
        }
        print("\n" + String(repeating: "=", count: 50))
        // Forward @0x101a80b20/0x101a80bc4: small literal first, then Int via the
        // CustomStringConvertible.description witness (interpolation), not BinaryInteger.description.
        print("✅ Success: \(successCount)")
        if failCount > 0 {
            print("❌ Failed: \(failCount)")
        }
        print("\n📦 下一步：")
        print("1. 将 \(outputDirectory.lastPathComponent) 文件夹复制到项目的 Metal/Anime4K/ 目录")
        print("2. 在 Xcode 中添加这些 .metal 文件到项目")
        print("3. 确保 'Target Membership' 勾选了你的 target")
        print("4. Build 后这些 shader 会自动编译到 default.metallib")
    }

    // slot 0x70 @0x101a80e84 — ⚑ INVENTED name (no symbol); internal, throws (exportAll catches it).
    // transformSource() is called with the 0xa0-byte MPVShader as indirect self @0x101a812f8.
    func exportShader(name: String, url: String) throws {
        print("📄 Processing: \(url)/\(name)")
        let anime4k = try Anime4K(name: name, url: url, device: device, usePrecompiled: false, bufferCount: 2)
        let baseName = name.replacingOccurrences(of: ".glsl", with: "")
        for (index, shader) in anime4k.shaders.enumerated() {
            let metalSource = shader.transformSource()
            var fileName = baseName
            if anime4k.shaders.count != 1 {
                // Forward @0x101a81324: append("_") straight into fileName, then the index through the
                // CustomStringConvertible.description witness (interpolation) — two appends, no temp.
                fileName += "_"
                fileName += "\(index)"
            }
            fileName += ".metal"
            let fileURL = outputDirectory.appendingPathComponent(fileName)
            let content = "//\n// \(fileName)\n// Auto-generated from \(name)\n// Anime4K Shader - Precompiled Metal Version\n//\n// Original function name: \(shader.name.filter { !".-()".contains($0) })\n// DO NOT EDIT - This file is auto-generated\n//\n" + metalSource
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            // Forward: "   ✅ " seeds one buffer; fileName, " (", filtered name, ")" appended with no
            // retain/release pairs — an interpolation (10 literal bytes + 2x2 <= 15, so no grow).
            print("   ✅ \(fileName) (\(shader.name.filter { !".-()".contains($0) }))")
        }
    }
}
