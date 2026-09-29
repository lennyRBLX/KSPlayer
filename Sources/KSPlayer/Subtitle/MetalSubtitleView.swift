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
// The two loops are `if count != 0 { i = 0; repeat { closure(i, …) } while i != count }` with no range trap,
// i.e. `indices.forEach` whose closure stayed out of line: per-image 0x101ac1444 (x0 i, x1 images, x2 encoder,
// x3 &instances, x4 Self; d0 scale, d1/d2 size, s3 brightness) and per-text 0x101ac25b0 (x0 i, x1 texts,
// x2 encoder, x3 Self; d0/d1 size, d2 scale, s3 brightness). Capture order follows first use in each body.
// brightness: `tst w2,#0xff` is dynamicRange.isHDR (ICF'd getter 0x1019e1af0); exposure 0x104c6314c is read under
// beginAccess, `fcvt d` → exp2 (0x10345bc5c) → `fcvt s`, then `fcsel ge` against 0 = Swift max(0, v).
extension MTLRenderCommandEncoder {
    func drawSubtitle(images: [SubtitleImageInfo], texts: [SubtitleTextInfo], dynamicRange: DynamicRange, size: CGSize, scale: CGFloat) {
        var brightness: Float = 1
        if dynamicRange.isHDR, KSOptions.subtitleExposure != 0 {
            brightness = max(0, Float(exp2(Double(KSOptions.subtitleExposure))))
        }
        setFragmentSamplerState(MetalRender.samplerState, index: 0)
        var instances = [AssLayerSource]()
        images.indices.forEach { index in
            let image = images[index]
            let colors = assLayerColors(role: image.styleRole)
            let rect = image.rect * scale
            switch image.source {
            case let .prerendered(texture):
                drawTexture(rect: rect, size: size, brightness: brightness, texture: texture)
            case let .palette(bitmap, palette, width, height, stride):
                // 0x101ac1544..0x101ac1cfc: width/height > 0, then the bitmap's withUnsafeBytes (inline, slice,
                // large and empty Data arms) builds an .r8Uint (0xd) texture; a nil base or nil texture skips the draw.
                guard width > 0, height > 0 else { break }
                let texture: MTLTexture? = bitmap.withUnsafeBytes { buffer in
                    guard let baseAddress = buffer.baseAddress else { return nil }
                    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Uint, width: width, height: height, mipmapped: false)
                    descriptor.usage = .shaderRead
                    descriptor.storageMode = .shared
                    guard let texture = MetalRender.device.makeTexture(descriptor: descriptor) else { return nil }
                    texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: baseAddress, bytesPerRow: stride)
                    return texture
                }
                if let texture {
                    drawPalette(rect: rect, size: size, brightness: brightness, texture: texture, palette: palette)
                }
            case let .assBlend(layers, boundingRect):
                // 0x101ac1618..0x101ac19e8: GetWidth/GetHeight guards, reserveCapacity(count + layers.count)
                // (overflow-checked), then one 0x50-byte AssLayerSource per non-empty layer. The colour word is
                // RGBA with inverted alpha: lanes c>>24, c>>16&0xff, c>>8&0xff, 0xff & ~c (`bic`), ucvtf.4s / 255.
                let scaleX = boundingRect.width > 0 ? rect.width / boundingRect.width : 1
                let scaleY = boundingRect.height > 0 ? rect.height / boundingRect.height : 1
                instances.reserveCapacity(instances.count + layers.count)
                for layer in layers where layer.w > 0 && layer.h > 0 {
                    let x = rect.minX + scaleX * (Double(layer.dstX) - boundingRect.minX)
                    let y = rect.minY + scaleY * (Double(layer.dstY) - boundingRect.minY)
                    var color = layer.color
                    if let colors {
                        let styleColor: UIColor?
                        switch layer.type {
                        case .character:
                            styleColor = colors.0
                        case .outline:
                            styleColor = colors.1
                        case .shadow:
                            styleColor = colors.2
                        case .other:
                            styleColor = nil
                        }
                        if let styleColor {
                            color = styleColor.assColor(replacing: color)
                        }
                    }
                    let rgba = SIMD4<Float>(Float(color >> 24), Float((color >> 16) & 0xFF), Float((color >> 8) & 0xFF), Float(0xFF - (color & 0xFF))) / 255
                    instances.append(AssLayerSource(bitmap: layer.bitmap, width: layer.w, height: layer.h, stride: layer.stride,
                                                    origin: SIMD2<Float>(Float(x), Float(y)),
                                                    size: SIMD2<Float>(Float(scaleX * Double(layer.w)), Float(scaleY * Double(layer.h))),
                                                    color: rgba))
                }
            }
        }
        drawAtlas(size: size, brightness: brightness, layers: instances)
        #if canImport(UIKit)
        texts.indices.forEach { index in
            if let (texture, rect) = texts[index].subtitleTexture(size: size, scale: scale) {
                drawTexture(rect: rect, size: size, brightness: brightness, texture: texture)
            }
        }
        #endif
        endEncoding()
    }

    // Forward 0x101ac1f68 — name INFERRED. Pipeline once 0x1044ef610 → 0x101ac2d18 (storage 0x1044ef618).
    // Vertex bytes at index 0; fragment: texture 0, palette bytes 0 (skipped on a nil base), texture size 1,
    // brightness 2; triangle strip of 4.
    private func drawPalette(rect: CGRect, size: CGSize, brightness: Float, texture: MTLTexture, palette: Data) {
        setRenderPipelineState(palettePipeline)
        let vertices = MetalRender.subtitleVertices(rect: rect, size: size)
        setVertexBytes(vertices, length: MemoryLayout<VertexIn>.stride * vertices.count, index: 0)
        setFragmentTexture(texture, index: 0)
        palette.withUnsafeBytes { buffer in
            if let baseAddress = buffer.baseAddress {
                setFragmentBytes(baseAddress, length: buffer.count, index: 0)
            }
        }
        var textureSize = SIMD2<Float>(Float(texture.width), Float(texture.height))
        setFragmentBytes(&textureSize, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
        var brightness = brightness
        setFragmentBytes(&brightness, length: MemoryLayout<Float>.size, index: 2)
        drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    // Forward 0x101ac2260 — name INFERRED. Pipeline once 0x1044ef620 → 0x101ac2c68 (storage 0x1044ef628).
    private func drawTexture(rect: CGRect, size: CGSize, brightness: Float, texture: MTLTexture) {
        setRenderPipelineState(subtitlePipeline)
        let vertices = MetalRender.subtitleVertices(rect: rect, size: size)
        setVertexBytes(vertices, length: MemoryLayout<VertexIn>.stride * vertices.count, index: 0)
        setFragmentTexture(texture, index: 0)
        var brightness = brightness
        setFragmentBytes(&brightness, length: MemoryLayout<Float>.size, index: 0)
        drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    // Forward 0x101ac23b4 — name INFERRED. Packs through 0x101ac3110, then one instanced strip:
    // buffer = device.makeBuffer(bytes:length: count * 0x30 (checked), options: []), pipeline once 0x1044ef638 →
    // 0x101ac2cc0 (storage 0x1044ef640), viewport (fcvtn.2s) vertex bytes 1, instance buffer 2, brightness fragment 0,
    // atlas texture fragment 0.
    private func drawAtlas(size: CGSize, brightness: Float, layers: [AssLayerSource]) {
        guard let (texture, instances) = packAssAtlas(layers: layers), !instances.isEmpty,
              let buffer = MetalRender.device.makeBuffer(bytes: instances, length: instances.count * MemoryLayout<AssAtlasInstance>.stride, options: [])
        else {
            return
        }
        setRenderPipelineState(assAtlasPipeline)
        var viewport = SIMD2<Float>(Float(size.width), Float(size.height))
        setVertexBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
        setVertexBuffer(buffer, offset: 0, index: 2)
        var brightness = brightness
        setFragmentBytes(&brightness, length: MemoryLayout<Float>.size, index: 0)
        setFragmentTexture(texture, index: 0)
        drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: instances.count)
    }
}

// Pipeline statics — names INFERRED; each is a swift_once global whose initializer calls 0x101ac2df0 with
// bitDepth 8 (`mov w4,#0x8`). Function-name strings are read from the Forward binary (small-string movz/movk and
// __cstring 0x103d3a4b0 / 0x103d3a4d0).
// ⚑ GAP (review): Shaders.metal has none of vertexTexture / paletteFragment / subtitleFragment / assAtlasVertex /
// assLayerFragment, so the first subtitle draw would hit the fatalError below until those shaders exist.
// 0x1044ef610 → 0x101ac2d18, storage 0x1044ef618
private let palettePipeline = makeSubtitlePipeline(vertexFunction: "vertexTexture", fragmentFunction: "paletteFragment", bitDepth: 8)
// 0x1044ef620 → 0x101ac2c68, storage 0x1044ef628
private let subtitlePipeline = makeSubtitlePipeline(vertexFunction: "vertexTexture", fragmentFunction: "subtitleFragment", bitDepth: 8)
// 0x1044ef638 → 0x101ac2cc0, storage 0x1044ef640
private let assAtlasPipeline = makeSubtitlePipeline(vertexFunction: "assAtlasVertex", fragmentFunction: "assLayerFragment", bitDepth: 8)

// Forward 0x101ac2df0 (200 insns) — name INFERRED. The fragment name goes into the fatalError message; colorAttachments[0]
// is fetched twice (pixelFormat, then the force-unwrapped attachment for the three blend setters: enabled,
// destinationRGB 5, destinationAlpha 5). KSOptions.colorPixelFormat is inlined (`cmp w21,#0xa` → 0x5e : 0x50).
// fatalError file "KSPlayer/MetalSubtitleView.swift" (0x103d3a450, len 0x20), line 0x23e.
private func makeSubtitlePipeline(vertexFunction: String, fragmentFunction: String, bitDepth: Int32) -> MTLRenderPipelineState {
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = MetalRender.library.makeFunction(name: vertexFunction)
    descriptor.fragmentFunction = MetalRender.library.makeFunction(name: fragmentFunction)
    descriptor.colorAttachments[0].pixelFormat = KSOptions.colorPixelFormat(bitDepth: bitDepth)
    let colorAttachment = descriptor.colorAttachments[0]!
    colorAttachment.isBlendingEnabled = true
    colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
    colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    do {
        return try MetalRender.device.makeRenderPipelineState(descriptor: descriptor)
    } catch {
#sourceLocation(file: "KSPlayer/MetalSubtitleView.swift", line: 574)
        fatalError("MetalSubtitleView: failed to compile '\(fragmentFunction)' pipeline: \(error)")
#sourceLocation()
    }
}

// Forward 0x101ac1da0 (114 insns) — name INFERRED. w0 = role; returns x0/x1/x2 = (fill, outline, shadow) or nil.
// Only .secondary with a non-nil KSOptions.secondaryTextStyle (0x1044e50c8, beginAccess) resolves colours, via
// KSOptions.textStyle(role: .secondary) (0x1019c4770). Outline: strokeWidth (+0x38) > 0 ? strokeColor : .clear.
// Shadow: `==` .clear first (0x103458674), then blur (+0x58) > 0, offset.width != 0, offset.height != 0.
fileprivate func assLayerColors(role: SubtitleTextRole) -> (UIColor, UIColor, UIColor)? {
    guard role == .secondary, KSOptions.secondaryTextStyle != nil else {
        return nil
    }
    let style = KSOptions.textStyle(role: .secondary)
    let outlineColor = style.textStrokeWidth > 0 ? style.textStrokeColor : UIColor.clear
    let shadowColor: UIColor
    if style.textShadowColor == UIColor.clear {
        shadowColor = UIColor.clear
    } else if style.textShadowBlurRadius > 0 || style.textShadowOffset.width != 0 || style.textShadowOffset.height != 0 {
        shadowColor = style.textShadowColor
    } else {
        shadowColor = UIColor.clear
    }
    return (style.textColor, outlineColor, shadowColor)
}

// Forward 0x101ac2a1c (147 insns) — name INFERRED. self (UIColor) in x20, w0 = ASS colour word (RRGGBBTT, TT =
// transparency). getRed(_:green:blue:alpha:) with alpha preset to 1; on failure the word is returned unchanged.
// Transparency is computed first (trap order), clamped as `v < 1 ? round(255 - max(0,v)*255) : 0`, which is
// Swift max(0, min(1, v)); each channel as `c < 255 ? max(0,c) : 255` = max(0, min(255, c)).
extension UIColor {
    fileprivate func assColor(replacing color: UInt32) -> UInt32 {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return color
        }
        let transparency = UInt32((255 - max(0, min(1, (1 - Double(color & 0xFF) / 255) * alpha)) * 255).rounded())
        let r = UInt32(max(0, min(255, (red * 255).rounded())))
        let g = UInt32(max(0, min(255, (green * 255).rounded())))
        let b = UInt32(max(0, min(255, (blue * 255).rounded())))
        return r << 24 | g << 16 | b << 8 | transparency
    }
}

// Forward 0x101ac3110 (513 insns, no forward_fn file tag; MetalSubtitleView range) — name INFERRED. Shelf packing:
// maxSize = the MetalRender static at 0x104c63700 (once 0x1044ed2b0 → 0x101a839c8:
// device.supportsFamily(.apple3) ? 16384 : 8192); start width = max(1, pow2(min(max(64, max width ?? 1,
// ceil(sqrt(max(Σ w*h, 1)))), maxSize))), doubled (checked) while it still fits; a layer wider than the atlas, or a
// row past maxSize, restarts the pass. Height = pow2(y + rowHeight) ≤ maxSize. .r8Unorm (0xa) texture, shaderRead,
// shared; each bitmap replaces region (origin, w, h) at its stride and yields an AssAtlasInstance with uv / (W, H).
private func packAssAtlas(layers: [AssLayerSource]) -> (MTLTexture, [AssAtlasInstance])? {
    guard !layers.isEmpty else {
        return nil
    }
    let maxSize = MetalRender.maxTextureSize
    let maxWidth = layers.map(\.width).max() ?? 1
    var area = 0
    for layer in layers {
        area += layer.width * layer.height
    }
    let side = Int(Double(max(area, 1)).squareRoot().rounded(.up))
    var atlasWidth = max(1, nextPowerOfTwo(min(max(64, maxWidth, side), maxSize)))
    while atlasWidth <= maxSize {
        var origins = [SIMD2<Int>]()
        origins.reserveCapacity(layers.count)
        var x = 0
        var y = 0
        var rowHeight = 0
        var fits = true
        for layer in layers {
            if layer.width > atlasWidth {
                fits = false
                break
            }
            if x + layer.width > atlasWidth {
                y += rowHeight
                x = 0
                rowHeight = 0
            }
            if y + layer.height > maxSize {
                fits = false
                break
            }
            origins.append(SIMD2<Int>(x, y))
            x += layer.width
            rowHeight = max(rowHeight, layer.height)
        }
        if fits {
            let atlasHeight = nextPowerOfTwo(y + rowHeight)
            guard atlasHeight <= maxSize else {
                return nil
            }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: atlasWidth, height: atlasHeight, mipmapped: false)
            descriptor.usage = .shaderRead
            descriptor.storageMode = .shared
            guard let texture = MetalRender.device.makeTexture(descriptor: descriptor) else {
                return nil
            }
            var instances = [AssAtlasInstance]()
            instances.reserveCapacity(layers.count)
            let width = Float(atlasWidth)
            let height = Float(atlasHeight)
            for (index, layer) in layers.enumerated() {
                let origin = origins[index]
                layer.bitmap.withUnsafeBytes { buffer in
                    if let baseAddress = buffer.baseAddress {
                        texture.replace(region: MTLRegionMake2D(origin.x, origin.y, layer.width, layer.height), mipmapLevel: 0, withBytes: baseAddress, bytesPerRow: layer.stride)
                    }
                }
                instances.append(AssAtlasInstance(origin: layer.origin, size: layer.size,
                                                  uvOrigin: SIMD2<Float>(Float(origin.x) / width, Float(origin.y) / height),
                                                  uvSize: SIMD2<Float>(Float(layer.width) / width, Float(layer.height) / height),
                                                  color: layer.color))
            }
            return (texture, instances)
        }
        atlasWidth *= 2
    }
    return nil
}

// Inlined twice in 0x101ac3110 — name INFERRED: `v == 0` → 1, else 1 << (64 - clz(v - 1)) (smart shift, 0 at 64).
private func nextPowerOfTwo(_ value: Int) -> Int {
    value == 0 ? 1 : 1 << (Int.bitWidth - (value - 1).leadingZeroBitCount)
}

#if canImport(UIKit)
extension SubtitleTextInfo {
    // Forward 0x101ac26a4 (222 insns) — name INFERRED. Indirect result (x8) of (MTLTexture, CGRect)?; self in x20.
    // Width is displaySize?.width ?? size.width / scale; the position is self.position ?? KSOptions.textPosition
    // (once 0x1044e5288); `.center` horizontal alignment adds a centred NSMutableParagraphStyle over the whole
    // string. Renderer 0x1019ea6c4 gets (width - (left + right margin), scale, strokeWidth; backgroundColor,
    // strokeColor, &insets). Frame: top → scale*verticalMargin, bottom → H - content - scale*verticalMargin,
    // else centred; leading/trailing likewise, with content = max(extent - scale*(inset pair), 1). Result origin is
    // shifted back by scale*insets.left/top; size is the texture's width/height.
    fileprivate func subtitleTexture(size: CGSize, scale: CGFloat) -> (MTLTexture, CGRect)? {
        guard text.length > 0 else {
            return nil
        }
        let attributedText = NSMutableAttributedString(attributedString: text)
        let width = displaySize?.width ?? size.width / scale
        let style = KSOptions.textStyle(role: styleRole)
        let position = position ?? KSOptions.textPosition
        if position.horizontalAlign == .center {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            attributedText.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attributedText.length))
        }
        var insets = UIEdgeInsets.zero
        guard let context = attributedText.subtitleContext(width: width - (position.leftMargin + position.rightMargin), scale: scale, strokeWidth: style.textStrokeWidth, backgroundColor: style.textBackgroundColor, strokeColor: style.textStrokeColor, insets: &insets),
              let texture = context.subtitleTexture()
        else {
            return nil
        }
        let textureWidth = Double(texture.width)
        let textureHeight = Double(texture.height)
        let y: CGFloat
        if position.verticalAlign == .top {
            y = scale * position.verticalMargin
        } else {
            let contentHeight = max(textureHeight - scale * insets.top - scale * insets.bottom, 1)
            if position.verticalAlign == .bottom {
                y = size.height - contentHeight - scale * position.verticalMargin
            } else {
                y = (size.height - contentHeight) * 0.5
            }
        }
        let x: CGFloat
        if position.horizontalAlign == .leading {
            x = scale * position.leftMargin
        } else {
            let contentWidth = max(textureWidth - scale * insets.left - scale * insets.right, 1)
            if position.horizontalAlign == .trailing {
                x = size.width - contentWidth - scale * position.rightMargin
            } else {
                x = (size.width - contentWidth) * 0.5
            }
        }
        return (texture, CGRect(x: x - scale * insets.left, y: y - scale * insets.top, width: textureWidth, height: textureHeight))
    }
}
#endif

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
