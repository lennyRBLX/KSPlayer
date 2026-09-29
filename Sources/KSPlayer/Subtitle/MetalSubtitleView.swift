//
//  MetalSubtitleView.swift
//  KSPlayer
//
//  Forward 1.3.17 — NEW Metal subtitle-overlay view (P4 M1 structure). §8.3. Bodies → P4 M2.
//
import Metal
import Combine
import CoreGraphics
import Foundation
import MetalKit
import QuartzCore
#if canImport(UIKit)
import UIKit
#endif

// MetalDrawable — KSPlayer protocol (§8.6, descriptor 0x1039f2274; trie names MetalDrawableMp / MetalDrawableTL).
// Forward's __swift5_proto has no conformer, so the requirement names come from no witness; both are INFERRED.
// The protocol_surface pass records two instance-method requirements (flags 0x11), at wt+0x8 and wt+0x10.
// Public (L7 lane 12): `MetalSubtitleView.metalDrawable` has a property descriptor (…13metalDrawable…vpMV) on a
// public class, so its type must be public for that property to typecheck.
public protocol MetalDrawable {
    // wt+0x8 — Forward metalDrawable didSet 0x101abfc64: x0 = `layer as! CAMetalLayer` (cast @0x101abfd04),
    // x1/x2 = the opened existential's metadata/wt, `blr [wt+0x8]` @0x101abfd14, and no result is used.
    // INFERRED name (vtable-ledger: MetalDrawable req0 wt+0x8, Forward caller 0x101abfd14, no symbol).
    func setup(layer: CAMetalLayer)
    // wt+0x10 — Forward draw(in:) 0x101ac0e24: x0 = the render command encoder, d0/d1 = p0.drawableSize,
    // `blr [wt+0x10]`. The caller does not call endEncoding afterwards.
    // INFERRED name (vtable-ledger: MetalDrawable req1 wt+0x10, Forward caller in 0x101ac0e24, no symbol).
    func draw(encoder: any MTLRenderCommandEncoder, size: CGSize)
}

// MetalSubtitleView @0x1039f229c — :MTKView (superclass-read So7MTKViewC). 7 fields reflection-ordered,
// types §8.3/§8.6. Bodies → P4 M2.
// FIELD-OFFSET GLOBALS, s109 — recorded because deriving this cost a full pass and the obvious
// shortcut is WRONG. This class's seven offset globals are 0x1044ef5a8, 5b8, 5c0, 5c8, 5d0, 5d8
// and 5e0 (exactly seven references across the class's code, matching the seven field records),
// and its field-offset vector @0x1044230b8 gives offsets 0x8, 0x30, 0x38, 0x40, 0x48, 0x50, 0x58.
// The globals are NOT in field order, so pairing the two ascending sequences produces a wrong map:
//   · 0x5a8 -> metalDrawable  and  0x5b8 -> dynamicRange are trie-pinned by their `vpWvd` symbols.
//   · 0x5b8 is initialised with `strb wzr` — a one-byte store — confirming the enum.
//   · 0x5d0 -> cancellables, NOT the 0x38-by-position candidate: the init stores __got 0x104112d10
//     there, which bind_oracle names `__swiftEmptySetSingleton`. The three array fields get
//     0x104112d00 (__swiftEmptyArrayStorage) and a Dictionary would get 0x104112d08 — the three
//     singletons are adjacent and distinguishing them is the whole trick.
//   · 0x5e0 -> playRatio: its init store is the immediate 0x3ff0000000000000, i.e. 1.0.
// ✅ CLOSED in s112: {0x5c0, 0x5c8, 0x5d8} -> {subtitleImages, pendingTexts, parts}. The note below
//   was right that the ORDER OF THE GLOBALS says nothing — but the VALUE each global holds does, and
//   that is a different reading. Each of these globals stores the field's byte offset, and the
//   field-offset vector @0x1044230b8 assigns those offsets to fields in field-record order:
//     0x5a8 -> 0x8  metalDrawable   0x5b8 -> 0x30 dynamicRange   0x5d0 -> 0x38 cancellables
//     0x5c0 -> 0x40 subtitleImages  0x5c8 -> 0x48 pendingTexts   0x5d8 -> 0x50 parts
//     0x5e0 -> 0x58 playRatio
//   The method is validated ON THIS CLASS by the four anchors that were already known independently
//   (metalDrawable, dynamicRange, cancellables, playRatio): all four land on the offset their own
//   global holds, so the three unknowns are read the same way, not guessed.
//   It also CORROBORATES the semantic reading recorded below: 0x5d8 is `parts`, and `parts` is what
//   `mtkView(_:drawableSizeWillChange:)` feeds to the layout helper @0x101abc398, whose two returned
//   words land in `subtitleImages` and `pendingTexts` — i.e. parts is the source list and the other
//   two are derived from it. Two independent routes, same answer.
//   ⚑[tool=field_offset_vector ref=MetalSubtitleView.subtitleImages:0x1044230b8 result=0x40]
//   ⚑[tool=recover_field_offsets ref=MetalSubtitleView.parts:0x1044ef5d8 result=parts]
//   Still unresolved and still not to be guessed: 0x1044ef5b0 holds offset 0x0, which is no field of
//   this class — the vector has no 0x0 entry — so that global is not a MetalSubtitleView field at all.
//   ⚑[tool=recover_field_offsets ref=MetalSubtitleView:0x1044ef5b0 result=NOT_RECOVERED]
//
//   The original note, kept because its warning is still correct:
//   {0x5c0, 0x5c8, 0x5d8} are all `[…]` initialised from the same empty-array singleton, so nothing
//   at the init distinguishes them, and neither the export trie nor the field records order the
//   globals. Do NOT guess the three from field order.
// ⚑[tool=bind_oracle ref=__got:0x104112d10 result=__swiftEmptySetSingleton]
// ⚑[tool=field_offset_vector ref=MetalSubtitleView:0x1044230b8 result=offsets-0x8-0x30-0x38-0x40-0x48-0x50-0x58]
// MTKViewDelegate: Forward has the objc thunk drawInMTKView: (0x101ac1380), and init 0x101ac03cc sets delegate = self.
// Public (L7 lane 12): the trie names carry property descriptors MetalSubtitleViewC12dynamicRange…vpMV and
// …C13metalDrawable…vpMV, which are emitted only for public properties of a public class. The two
// MTKViewDelegate witnesses are then public too, because a public class witnessing a public protocol must be.
// Everything else stays as it was: the stored fields keep the private discriminator
// _1D4F9FA947E132855061D664DF1FC640, and init(subtitleModel:), updateSubtitle and init(coder:) have no trie name.
public class MetalSubtitleView: MTKView, MTKViewDelegate {
    // Forward setter 0x101abff8c / modify call the didSet FUN_101abfc64 (161 insns).
    // Nil: the layer is reset to the SDR subtitle configuration. Set: layer config is left to requirement wt+0x8.
    // The edrMetadata / wantsExtendedDynamicRangeContent calls are API_UNAVAILABLE(tvos), so they get the
    // MetalRender `#if !os(tvOS)` guard.
    public var metalDrawable: (any MetalDrawable)? { // §8.6 — offset global 0x1044ef5a8 (vpWvd)
        didSet {
            if let metalDrawable {
                metalDrawable.setup(layer: layer as! CAMetalLayer)
            } else {
                (layer as! CAMetalLayer).framebufferOnly = true
                (layer as! CAMetalLayer).drawableSize = drawableSize
                colorPixelFormat = .bgra8Unorm
                if !KSOptions.enableHDRSubtitle {
                    (layer as! CAMetalLayer).colorspace = nil
                }
                #if !os(tvOS)
                (layer as! CAMetalLayer).edrMetadata = nil
                if !KSOptions.enableHDRSubtitle {
                    (layer as! CAMetalLayer).wantsExtendedDynamicRangeContent = false
                }
                #endif
            }
            #if canImport(UIKit)
            setNeedsDisplay()
            #else
            needsDisplay = true
            #endif
        }
    }
    public var dynamicRange: DynamicRange = .sdr { // ⚑ default inferred → M2; offset global 0x1044ef5b8 (vpWvd)
        didSet {
            #if os(iOS)
            guard oldValue != dynamicRange else { return }
            guard KSOptions.enableHDRSubtitle else { return }
            let selectedName: CFString
            switch dynamicRange {
            case .sdr:
                selectedName = CGColorSpace.sRGB
            case .hdr10:
                selectedName = CGColorSpace.itur_2100_PQ
            case .hlg, .dolbyVision:
                selectedName = CGColorSpace.itur_2100_HLG
            }
            let colorLayer = layer as! CAMetalLayer
            colorLayer.colorspace = CGColorSpace(name: selectedName)
            let currentDynamicRange = dynamicRange
            let edrLayer = layer as! CAMetalLayer
            edrLayer.wantsExtendedDynamicRangeContent = currentDynamicRange != .sdr
                && (window?.windowScene?.screen.currentEDRHeadroom ?? 0) > 1.0
            #endif
        }
    }
    @used public final func mtkView(_ p0: MTKView, drawableSizeWillChange: CGSize) {
        #if os(iOS)
        updateSubtitle(size: drawableSizeWillChange)
        #endif
    }
    // Forward 0x101ac0e24. With a metalDrawable set, requirement wt+0x10 gets (encoder, p0.drawableSize).
    // Otherwise the encoder subtitle helper @0x101ac11ec gets (subtitleImages, pendingTexts, dynamicRange,
    // p0.drawableSize, UITraitCollection.current.displayScale), with Self from swift_getObjectType(encoder).
    // Both callees end the encoding themselves.
    public final func draw(in p0: MTKView) {
        guard let drawable = p0.currentDrawable,
              let commandBuffer = MetalRender.commandQueue?.makeCommandBuffer()
        else {
            return
        }
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            if let metalDrawable {
                metalDrawable.draw(encoder: encoder, size: p0.drawableSize)
            } else {
                #if canImport(UIKit)
                encoder.drawSubtitle(images: subtitleImages, texts: pendingTexts, dynamicRange: dynamicRange, size: p0.drawableSize, scale: UITraitCollection.current.displayScale)
                #else
                encoder.drawSubtitle(images: subtitleImages, texts: pendingTexts, dynamicRange: dynamicRange, size: p0.drawableSize, scale: 1)
                #endif
            }
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    private var cancellables: Set<AnyCancellable> = [] // offset global 0x1044ef5d0 (empty-set singleton)
    private var subtitleImages: [SubtitleImageInfo] = [] // offset global 0x1044ef5c0 -> field offset 0x40
    private var pendingTexts: [SubtitleTextInfo] = [] // offset global 0x1044ef5c8 -> field offset 0x48
    private var parts: [SubtitlePart] = [] // offset global 0x1044ef5d8 -> field offset 0x50
    private var playRatio: Double = 1 // offset global 0x1044ef5e0 (init stores 1.0)
    /// Vtable F21: a get-only unit with a dead slot, so Forward keeps no body, callers or strings.
    /// Name and type are INFERRED. The declaration only holds the slot so that init (F22) and updateSubtitle (F23) line up.
    var unreadSlot21: Bool { false }
    /// Forward 0x101ac03cc (vtable F22, dead slot; called directly by both KSPlayerLayer designated inits).
    /// Label INFERRED — the init is internal, so no trie name; the only argument is the layer's SubtitleModel.
    /// Sink closure 0x101ac3a3c → 0x101ac0810 (MainActor check, KSPlayer/MetalSubtitleView.swift:99).
    init(subtitleModel: SubtitleModel) {
        super.init(frame: .zero, device: MetalRender.device)
        framebufferOnly = true
        enableSetNeedsDisplay = true
        autoResizeDrawable = true
        isPaused = true
        delegate = self
        backingLayer?.isOpaque = false
        subtitleModel.$parts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] parts in
                guard let self else { return }
                playRatio = subtitleModel.playRatio
                self.parts = parts
                #if os(iOS)
                updateSubtitle(size: nil)
                #endif
            }
            .store(in: &cancellables)
    }

    // init(frame:device:) is not declared. Forward 0x1033961ac is the compiler-synthesized
    // _swift_stdlib_reportUnimplementedInitializer trap, emitted because init(subtitleModel:) is a new designated init.
    required init(coder: NSCoder) {
        super.init(coder: coder)
    }
    // Callers of the slot-40 method below: mtkView(_:drawableSizeWillChange:) @0x101ac0d48 and the init sink.

    #if os(iOS)
    /// Vtable slot 40 @0x101ac0a90 (flags 0x10, the last of 24 entries starting at slot 17). Argument:
    /// Optional<CGSize> as x0/x1 plus tag w2. On nil it falls back to `drawableSize`. It divides by
    /// UITraitCollection.current.displayScale and calls layoutSubtitle with literal 1. It stores the
    /// pair into subtitleImages/pendingTexts and tail-calls setNeedsDisplay.
    /// `parts` (0x5d8) and `playRatio` (0x5e0) are loaded before the trait-collection sends.
    @used func updateSubtitle(size: CGSize?) { // name inferred; @used keeps the body while its callers are absent
        let size = size ?? drawableSize
        let parts = parts
        let playRatio = playRatio
        let scale = UITraitCollection.current.displayScale
        (subtitleImages, pendingTexts) = layoutSubtitle(playRatio: playRatio, size: CGSize(width: size.width / scale, height: size.height / scale), fontWidthMode: 1, parts: parts)
        setNeedsDisplay()
    }
    #endif
}

// Encoder subtitle helper — Forward 0x101ac11ec (101 insns). It is a protocol-extension method on
// MTLRenderCommandEncoder: self (the encoder) arrives in x20 and Self metadata in x3, from the caller's
// swift_getObjectType. x0 is images, x1 texts, w2 dynamicRange, d0/d1 size and d2 scale. No symbol exists
// (internal), so the name is INFERRED (vtable-ledger: no slot — extension method, Forward 0x101ac11ec,
// caller draw(in:) 0x101ac0e24).
// Forward body:
//   brightness = 1, and when dynamicRange != .sdr with KSOptions.subtitleExposure (0x104c6314c) != 0,
//     brightness = max(exp2(subtitleExposure), 0)
//   setFragmentSamplerState(MetalRender.samplerState, 0)
//   var instances = []
//   per-image 0x101ac1444(scale, size, brightness, i, images, self, &instances)
//   atlas draw 0x101ac23b4(size, brightness, instances)
//   per-text 0x101ac25b0(size, scale, brightness, i, texts)
//   endEncoding()
// ⚑ Writer GAP (L7 lane 12 batch 3): the draw tree under 0x101ac1444 / 0x101ac23b4 / 0x101ac25b0 is not
// reconstructed here. It is about 2400 instructions and covers palette and texture quads, ASS atlas packing
// (0x101ac3110) and the text layout at 0x101ac26a4. It needs KSOptions 0x1019c4770 (1291 insns, unpaired in
// the build) and the text-image helper 0x1019ea6c4. Its three swift_once pipeline statics also need Metal
// functions that are absent from Shaders.metal: vertexTexture, assAtlasVertex, paletteFragment, plus two
// 16-byte fragment names at 0x103d3a490 and 0x103d3a4b0.
// Until then the body keeps only the helper's own sampler setup and endEncoding, so nothing crashes; the
// brightness value is left out because nothing here reads it yet.
extension MTLRenderCommandEncoder {
    func drawSubtitle(images: [SubtitleImageInfo], texts: [SubtitleTextInfo], dynamicRange: DynamicRange, size: CGSize, scale: CGFloat) {
        setFragmentSamplerState(MetalRender.samplerState, index: 0)
        endEncoding()
    }
}

// AssLayerSource @0x1039f23bc
// ⚑[tool=field_surface ref=AssLayerSource:fieldmd result=7 let] Every record lacks IsVar; `bitmap`
// resolves to Foundation.Data and `color` to SIMD4<Float>.
public struct AssLayerSource {
    public let bitmap: Data
    public let width: Int
    public let height: Int
    public let stride: Int
    public let origin: SIMD2<Float>
    public let size: SIMD2<Float>
    public let color: SIMD4<Float>
}

// AssAtlasInstance @0x1039f2398 — declaration shape read from the Forward context descriptor (kind, parent,
// conformances, case names). Placement: gap_lower(inferred) (MetalSubtitleView.swift..GestureView.swift).
// ⚑[tool=type_surface ref=AssAtlasInstance:0x1039f2398 result=private struct AssAtlasInstance]
// ⚑[tool=field_surface ref=AssAtlasInstance:fieldmd result=5 var] Lazy owner (no build metadata);
// the fields are taken from Forward's record order, IsVar bits and resolved types.
private struct AssAtlasInstance {
    var origin: SIMD2<Float>
    var size: SIMD2<Float>
    var uvOrigin: SIMD2<Float>
    var uvSize: SIMD2<Float>
    var color: SIMD4<Float>
}
