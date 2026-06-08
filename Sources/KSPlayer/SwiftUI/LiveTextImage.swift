//
//  LiveTextImage.swift
//  KSPlayer
//
//  Created by kintan on 2023/5/4.
//

import SwiftUI
#if canImport(VisionKit)
import VisionKit

/// VisionKit "Live Text" subtitle/image OCR support.
///
/// RE: section 18.17. Type-level CMa anchor: 0x1014AF96C
/// (`LiveTextImageView` ObjC metadata accessor; the `LiveTextImage`
/// value type itself carries the VisionKit interaction/analyzer state).
///
/// SwiftUI conformance: `UIViewRepresentable` (iOS) / `NSViewRepresentable`
/// (macOS, via `makeNSView`). The doc (§18.17) describes `LiveTextImage`
/// only as a "types.json struct, 3 fields" (cgImage / analyzer / interaction)
/// and does not literally name the SwiftUI protocol; the representable
/// conformance is the correct shape for a struct that produces a
/// `UIImageView` from a `CGImage`, and no binary anchor contradicts it.
@available(iOS 16.0, macOS 13.0, macCatalyst 17.0, *)
@MainActor
public struct LiveTextImage: UIViewRepresentable {
    // types.json roster (3 fields): field #1 stores a CGImage, not a
    // UIKit UIImage. `ImageAnalyzer.analyze` and `UIImageView.image`
    // are both fed from this CGImage below.
    public let cgImage: CGImage
    private let analyzer = ImageAnalyzer()
    #if canImport(UIKit)
    public typealias UIViewType = UIImageView
    private let interaction = ImageAnalysisInteraction()
    public init(cgImage: CGImage) {
        self.cgImage = cgImage
    }

    public func makeUIView(context _: Context) -> UIViewType {
        // RE: 0x1014AF920 — alloc/init the view, then attach the
        // ImageAnalysisInteraction as a distinct step (the binary kept
        // alloc/init+attach as a named entry point; preserved here).
        LiveTextImageView.makeWithInteraction(interaction)
    }

    public func updateUIView(_ view: UIViewType, context _: Context) {
        updateView(view)
    }
    #else
    public typealias NSViewType = UIImageView
    // Cross-platform port: macOS has no ImageAnalysisInteraction; it
    // uses ImageAnalysisOverlayView added as a subview instead. types.json
    // captured only the iOS shape (ImageAnalysisInteraction) because the
    // binary is the iOS app — this #else branch is required by the
    // iOS/tvOS/macOS multi-target constraint, not a regression.
    @MainActor
    private let interaction = ImageAnalysisOverlayView()
    public init(cgImage: CGImage) {
        self.cgImage = cgImage
    }

    public func makeNSView(context _: Context) -> NSViewType {
        // RE: 0x1014B0058 — bare alloc/init of LiveTextImageView from the
        // representable (no interaction attach on this path; macOS attaches
        // the overlay as a subview below instead).
        let imageView = LiveTextImageView.make()
        interaction.autoresizingMask = [.width, .height]
        interaction.frame = imageView.bounds
        interaction.trackingImageView = imageView
        imageView.addSubview(interaction)
        return imageView
    }

    public func updateNSView(_ view: NSViewType, context _: Context) {
        updateView(view)
    }
    #endif
    @MainActor
    private func updateView(_ view: UIImageView) {
        view.image = UIImage(cgImage: cgImage)
        view.sizeToFit()
        let image = cgImage
        Task { @MainActor in
            do {
                let configuration = ImageAnalyzer.Configuration([.text])
                let analysis = try await analyzer.analyze(image, orientation: .up, configuration: configuration)
                interaction.preferredInteractionTypes = .textSelection
                interaction.analysis = analysis
            } catch {
                print(error.localizedDescription)
            }
        }
    }
}
#endif

#if os(macOS)
public extension Image {
    init(uiImage: UIImage) {
        self.init(nsImage: uiImage)
    }
}
#endif

public extension UIImage {
    func fitRect(_ fitSize: CGSize) -> CGRect {
        let hZoom = fitSize.width / size.width
        let vZoom = fitSize.height / size.height
        let zoom = min(min(hZoom, vZoom), 1)
        let newSize = size * zoom
        return CGRect(origin: CGPoint(x: (fitSize.width - newSize.width) / 2, y: fitSize.height - newSize.height), size: newSize)
    }
}

/// ObjC-rooted `UIImageView` subclass with zero intrinsic content size.
///
/// RE: 0x1014AF96C (LiveTextImageView ObjC metadata accessor / CMa, 1.3.15).
/// NOTE: the linker symbol `$s8KSPlayer17LiveTextImageViewCMa` resolves to
/// 0x1013931B4, but that is a 4-byte branch trampoline tail-calling an
/// unrelated function (KSAVPlayer attachPlayerToLayer/resumeState) — a
/// false-friend. The real `_objc_opt_self` accessor is 0x1014AF96C.
class LiveTextImageView: UIImageView {
    override var intrinsicContentSize: CGSize {
        .zero
    }

    #if canImport(UIKit)
    /// RE: 0x1014AF920 (LiveTextImageView alloc/init + addInteraction, 1.3.15).
    /// Binary symbol: `LiveTextImageView_alloc_init_withInteraction` (doc §18.17 table).
    /// Alloc/init the view and attach the ImageAnalysisInteraction. Kept as a
    /// distinct entry point to mirror the binary's named alloc/init+attach
    /// function (API Surface Preservation).
    @MainActor
    static func makeWithInteraction(_ interaction: ImageAnalysisInteraction) -> LiveTextImageView {
        let imageView = LiveTextImageView()
        imageView.addInteraction(interaction)
        return imageView
    }
    #endif

    /// RE: 0x1014B0058 (LiveTextImageView alloc/init from a builder closure, 1.3.15).
    /// Binary symbol: `LiveTextImageView_alloc_init_fromClosure` (doc §18.17 table).
    /// Bare alloc/init wrapper — the SwiftUI makeUIView/makeNSView construction
    /// path that builds a LiveTextImageView() from the representable.
    @MainActor
    static func make() -> LiveTextImageView {
        LiveTextImageView()
    }
}
#endif
