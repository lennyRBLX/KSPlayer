//
//  MetalSubtitleView.swift
//  KSPlayer
//
//  Forward 1.3.17 — NEW Metal subtitle-overlay view (P4 M1 structure). §8.3. Bodies → P4 M2.
//
import Combine
import CoreGraphics
import Foundation
import MetalKit

// MetalDrawable — KSPlayer protocol (§8.6, descriptor-named). ⚑ requirements → P4 M2 (marker assumed for the M1 compile).
protocol MetalDrawable {}

// MetalSubtitleView @0x1039f229c — :MTKView (superclass-read So7MTKViewC). 7 fields reflection-ordered,
// types §8.3/§8.6. Bodies → P4 M2.
class MetalSubtitleView: MTKView {
    public var metalDrawable: (any MetalDrawable)? // §8.6
    public var dynamicRange: DynamicRange = .sdr // ⚑ default inferred → M2
    private var cancellables: Set<AnyCancellable> = []
    private var subtitleImages: [SubtitleImageInfo] = []
    private var pendingTexts: [SubtitleTextInfo] = []
    private var parts: [SubtitlePart] = []
    private var playRatio: Double = 1
    // ⚑ init shape inferred → M2 witness-verify (real init wires the Metal device + Combine subscriptions)
    override init(frame frameRect: CGRect, device: (any MTLDevice)?) {
        super.init(frame: frameRect, device: device)
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }
    // ⚑ UNRESOLVED → P4 M2: the Metal subtitle render bodies
}
