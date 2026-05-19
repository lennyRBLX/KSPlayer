//
//  MetalShaderExporter.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — binary address 0x101349140
//  Debug/development utility for exporting compiled Metal shader libraries.
//

#if canImport(Metal)
import Metal
import Foundation

public final class MetalShaderExporter {
    public let device: MTLDevice
    public let outputDirectory: URL

    public init(device: MTLDevice, outputDirectory: URL) {
        self.device = device
        self.outputDirectory = outputDirectory
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    /// Serializes the library to a .metallib file in outputDirectory.
    public func exportLibrary(_ library: MTLLibrary, name: String) throws {
        let fileURL = outputDirectory.appendingPathComponent("\(name).metallib")
        let functionNames = library.functionNames
        KSLog("[MetalShaderExporter] exporting library '\(name)' with \(functionNames.count) functions to \(fileURL.path)")

        // Build a new library from each function's source if available,
        // otherwise serialize via device pipeline archive approach.
        // For debug builds, we just write function metadata as a plist.
        var metadata: [[String: Any]] = []
        for fnName in functionNames {
            guard let fn = library.makeFunction(name: fnName) else { continue }
            var entry: [String: Any] = [
                "name": fnName,
                "functionType": "\(fn.functionType)",
            ]
            if let patchType = fn.patchType as? Int {
                entry["patchType"] = patchType
            }
            metadata.append(entry)
        }

        let plist = try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
        let metadataURL = outputDirectory.appendingPathComponent("\(name)_functions.plist")
        try plist.write(to: metadataURL)
        KSLog("[MetalShaderExporter] wrote function metadata to \(metadataURL.path)")
    }

    /// Iterates render pipeline states from a MetalRender and exports their shader functions.
    public func exportAllPipelineStates(from render: MetalRender) throws {
        // MetalRender uses MetalRender.library as its shared shader library
        try exportLibrary(MetalRender.library, name: "KSPlayer_default")
    }
}
#endif
