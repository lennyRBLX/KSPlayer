// swift-tools-version:6.2
import Foundation
import PackageDescription

let package = Package(
    name: "KSPlayer",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .tvOS(.v26), .macOS(.v26), .visionOS(.v26)],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "KSPlayer",
            // todo clang: warning: using sysroot for 'iPhoneSimulator' but targeting 'MacOSX' [-Wincompatible-sysroot]
//            type: .dynamic,
            targets: ["KSPlayer"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        .target(
            name: "KSPlayer",
            dependencies: [
                .product(name: "FFmpegKit", package: "FFmpegKit"),
                .product(name: "libass", package: "FFmpegKit"),
                "DisplayCriteria",
                "DOVIRPUShim",
            ],
            resources: [.process("Metal/Shaders.metal")],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        // C shim bridging FFmpeg's private ff_dovi_rpu_parse API for the
        // VTB Dolby Vision decode path. The binary (v1.3.15) calls this
        // directly; see TrackDecode.md L704-714 for the Phase 2 chain.
        // Depends on Libavcodec (contains ff_dovi_rpu_parse symbol) and
        // Libavutil (public AVDOVIMetadata types in dovi_meta.h).
        .target(
            name: "DOVIRPUShim",
            dependencies: [
                .product(name: "Libavcodec", package: "FFmpegKit"),
                .product(name: "Libavutil", package: "FFmpegKit"),
            ],
            path: "Sources/DOVIRPUShim",
            publicHeadersPath: "include"
        ),
        // C shim exposing FFmpeg's private libavformat/url.h surface — the URLContext
        // type and the ffurl_* protocol API. FFmpegKit ships public headers only, so
        // URLContext was unnameable in Swift even though the symbols are linked in;
        // Forward's field records type URLContextDownload.context as
        // UnsafeMutablePointer<__C.URLContext>?. Same pattern as DOVIRPUShim.
        .target(
            name: "FFURLShim",
            dependencies: [
                .product(name: "Libavformat", package: "FFmpegKit"),
                .product(name: "Libavutil", package: "FFmpegKit"),
            ],
            path: "Sources/FFURLShim",
            publicHeadersPath: "include"
        ),
        .target(
            name: "DisplayCriteria"
        ),
        .target(
            name: "PreLoadIOContext",
            dependencies: [
                "KSPlayer",
                "FFURLShim",
                .product(name: "FFmpegKit", package: "FFmpegKit"),
                .product(name: "Libavformat", package: "FFmpegKit"),
            ],
            path: "Sources/PreLoadIOContext"
        ),
        .target(
            name: "ProAVPlayer",
            dependencies: ["KSPlayer", "PreLoadIOContext"],
            path: "Sources/ProAVPlayer",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "KSPlayerTests",
            dependencies: ["KSPlayer", "PreLoadIOContext"],
            resources: [.process("Resources")]
        ),
    ]
)

package.dependencies += [
    .package(path: "../FFmpegKit"),
]
