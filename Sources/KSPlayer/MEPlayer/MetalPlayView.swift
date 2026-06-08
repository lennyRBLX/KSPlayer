//
//  MetalPlayView.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/11.
//

import AVFoundation
import Combine
import CoreMedia
import Dispatch
#if canImport(MetalKit)
import MetalKit
#endif

// MARK: - DisplayLinkProtocol

/// RE: binary field at MetalPlayView+0x88 uses protocol-typed existential (DisplayLinkProtocol?)
/// rather than concrete CADisplayLink?. This protocol abstracts over iOS's native CADisplayLink
/// and the macOS CVDisplayLink-based polyfill, allowing the same field to hold either.
protocol DisplayLinkProtocol: AnyObject {
    var isPaused: Bool { get set }
    var preferredFramesPerSecond: Int { get set }
    @available(iOS 15.0, tvOS 15.0, macOS 14.0, *)
    var preferredFrameRateRange: CAFrameRateRange { get set }
    var timestamp: TimeInterval { get }
    var duration: TimeInterval { get }
    var targetTimestamp: TimeInterval { get }
    func add(to runloop: RunLoop, forMode mode: RunLoop.Mode)
    func invalidate()
}

#if canImport(UIKit)
extension CADisplayLink: DisplayLinkProtocol {}
#endif

// MARK: - KSPlayer.Drawable protocol

/// RE: protocol descriptor $s8KSPlayer8DrawableP @ 0x10370fb54 (1.3.15)
/// Two conformances in binary:
///   - CAMetalLayer: WT @ 0x103a27550 (+0x08 = draw/present, +0x10 = clear/blank)
///   - RealityKit.TextureResource.Drawable: WT @ 0x103a27568
/// MetalPlayView.init boxes the metalView's CAMetalLayer into the 40-byte existential
/// field at +0x48 using TargetProtocolConformanceDescriptor_103a27550.
public protocol Drawable {
    /// Witness slot +0x08: draw/present a rendered frame through the EDR/colorspace
    /// pipeline (FUN_10146a0c4 -> FUN_101469550 -> FUN_10146bec4 for CAMetalLayer).
    /// The render and anime4KPipeline are owned by MetalPlayView and passed in;
    /// MetalView has zero stored properties in the binary (types.json confirmed).
    func draw(
        pixelBuffer: PixelBufferProtocol,
        display: DisplayEnum,
        size: CGSize,
        doviMetadata: DoviGPUMetadata?,
        options: KSOptions,
        render: MetalRender,
        anime4KPipeline: Anime4KPipeline?
    )
    /// Witness slot +0x10: clear/blank the drawable surface.
    /// For CAMetalLayer: FUN_10146a0e4 -> setEDRMetadata:nil + FUN_10146b508 (MTLLoadActionClear).
    /// The render instance is owned by MetalPlayView, not MetalView (zero stored properties).
    func clear(render: MetalRender)
}

/// RE: protocol descriptor $s8KSPlayer10KSDrawableP @ 0x10370fb3a (1.3.15)
/// Distinct from Drawable. Binary protocol descriptor confirmed but relationship
/// to Drawable is unclear from reversal doc. Declared here for type completeness.
public protocol KSDrawable {}

// MARK: - CAMetalLayer : KSPlayer.Drawable conformance

/// RE: TargetProtocolConformanceDescriptor @ 0x103a27550 (CAMetalLayer : KSPlayer.Drawable, 1.3.15)
/// WT slots: +0x08 = FUN_10146a0c4 (draw/present), +0x10 = FUN_10146a0e4 (clear/blank).
/// MetalPlayView.init boxes metalView.metalLayer (CAMetalLayer) into the 40-byte existential
/// at +0x48 using this conformance. The clear witness is the load-bearing path: it resets
/// EDR metadata and issues an MTLLoadActionClear present (FUN_10146a0e4 -> FUN_10146b508).
extension CAMetalLayer: Drawable {
    /// RE: FUN_10146a0c4 (draw/present witness +0x08, 1.3.15)
    /// In the binary this routes through the full EDR/present chain (FUN_101469550 -> FUN_10146bec4).
    /// In the reconstructed source the equivalent path goes through MetalPlayView.renderToMetalView
    /// which operates directly on the metalLayer. This conformance satisfies the existential boxing
    /// at +0x48; the actual draw dispatch does not go through the drawable field.
    public func draw(
        pixelBuffer _: PixelBufferProtocol,
        display _: DisplayEnum,
        size _: CGSize,
        doviMetadata _: DoviGPUMetadata?,
        options _: KSOptions,
        render _: MetalRender,
        anime4KPipeline _: Anime4KPipeline?
    ) {
        assertionFailure("CAMetalLayer.draw should not be called directly -- use MetalPlayView.renderToMetalView")
    }

    /// RE: FUN_10146a0e4 (clear/blank witness +0x10, 1.3.15)
    /// Unwraps the CAMetalLayer from the existential, calls setEDRMetadata:nil,
    /// nextDrawable, then FUN_10146b508 (MTLLoadActionClear present).
    /// This is the LIVE path dispatched via drawable.clear(render:) in MetalPlayView.clearDisplay.
    public func clear(render _: MetalRender) {
        #if !os(tvOS)
        if #available(iOS 16.0, *) {
            edrMetadata = nil
        }
        #endif
        guard let drawable = nextDrawable() else { return }
        // RE: FUN_10146b508 (clear-present helper, 1.3.15)
        // Uses shared MTLRenderPassDescriptor + command queue with MTLLoadActionClear.
        guard let commandQueue = device?.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }
        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = drawable.texture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else { return }
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        drawable.present()
    }
}

// MARK: - Protocols

public protocol DisplayLayerDelegate: NSObjectProtocol {
    func change(displayLayer: AVSampleBufferDisplayLayer)
}

public protocol VideoOutput: FrameOutput {
    var displayLayerDelegate: DisplayLayerDelegate? { get set }
    var options: KSOptions { get set }
    var displayLayer: AVSampleBufferDisplayLayer { get }
    var pixelBuffer: PixelBufferProtocol? { get }
    init(options: KSOptions)
    func invalidate()
    func readNextFrame()
}

// MARK: - MetalPlayView

/// RE: _TtC8KSPlayer13MetalPlayView (1.3.15)
/// Field-offset vector: 0x103d0d998..0x103d0da10
/// ObjC method-list header: 0x102e27c60 (entsize 12, count 10)
public final class MetalPlayView: UIView, VideoOutput {
    public var displayLayer: AVSampleBufferDisplayLayer {
        displayView.displayLayer
    }

    /// RE: +0x78, Bool (1 byte), field-offset [0x103d0d9e8]
    private var isDovi: Bool = false

    /// RE: +0x10, CMFormatDescription? (CFType, ObjC retained), field-offset [0x103d0d9d8]
    private var formatDescription: CMFormatDescription? {
        didSet {
            options.updateVideo(refreshRate: fps, isDovi: isDovi, formatDescription: formatDescription)
        }
    }

    /// RE: +0x18, Float (32-bit), field-offset [0x103d0d9e0]
    /// Binary init sets to 1.0f, not 60.
    private var fps = Float(1.0) {
        didSet {
            if fps != oldValue {
                updateFPS()
            }
        }
    }

    /// RE: +0x1C, UInt16 (2 bytes, POD), field-offset [0x103d0d9a8]
    /// Init-zeroed. Sole consumer is layoutSubviews (FUN_101444530) which reads it as a
    /// degree value and applies CGAffineTransformMakeRotation(rotation * pi/180).
    private var rotation: UInt16 = 0

    /// RE: +0x20, PixelBufferProtocol? (existential, 2 quadwords), field-offset [0x103d0d9b0]
    public private(set) var pixelBuffer: PixelBufferProtocol?

    /// RE: +0x30, KSOptions (Swift class ref), field-offset [0x103d0d9b8]
    public var options: KSOptions

    /// RE: +0x38, weak VideoOutputRenderSourceDelegate?, field-offset [0x103d0d9c0]
    public weak var renderSource: OutputRenderSourceDelegate?

    /// RE: +0x48, KSPlayer.Drawable (40-byte Swift existential container), field-offset [0x103d0d9c8]
    /// In init, the metalView's CAMetalLayer is boxed into this existential with
    /// TargetProtocolConformanceDescriptor_103a27550 (CAMetalLayer : KSPlayer.Drawable).
    /// Consumed by clearDisplay (FUN_101444704) which dispatches the Drawable witness +0x10 (clear/blank).
    private var drawable: any Drawable

    /// RE: +0x70, KSPlayer.MetalView (UIView subclass, ObjC retained), field-offset [0x103d0d998]
    private let metalView = MetalView()

    /// The shared MetalRender instance used by the draw/present pipeline.
    /// In the binary this is consumed via the Drawable witness chain (FUN_10146a0c4 -> FUN_101469550
    /// -> FUN_10146bec4); MetalView itself has zero stored properties (types.json confirmed).
    /// Ownership lives here on MetalPlayView, not on MetalView.
    private let render = MetalRender()

    /// Anime4K upscale pipeline. In the binary, the Anime4K pass runs on the present/commit tail
    /// (FUN_10146bec4) via global singletons (command-queue DAT_103d0f3f8, sampler DAT_103d0f400),
    /// not as a MetalView stored property. Ownership lives here on MetalPlayView.
    private lazy var anime4KPipeline: Anime4KPipeline? = {
        guard KSOptions.enableAnime4K else { return nil }
        return Anime4KPipeline(device: MetalRender.device)
    }()

    /// RE: +0x08, Bool (1 byte), field-offset [0x103d0d9d0]
    /// Read by renderFrameIfActive (tbz early-exit). Written by play/pause.
    private var isPaused = true

    /// RE: +0x79, Bool (1 byte), field-offset [0x103d0d9f0]
    /// Read by renderFrameIfActive (tbnz early-exit). Written by enterBackground/enterForeground.
    private var isBackground: Bool = false

    /// RE: +0x80, KSPlayer.AVSampleBufferDisplayView (UIView subclass, ObjC retained), field-offset [0x103d0d9a0]
    var displayView = AVSampleBufferDisplayView() {
        didSet {
            displayLayerDelegate?.change(displayLayer: displayView.displayLayer)
        }
    }

    /// RE: +0x88, DisplayLinkProtocol? (Optional Swift object), field-offset [0x103d0d9f8]
    private var displayLink: (any DisplayLinkProtocol)?

    /// RE: +0x98, DispatchSourceTimer (OS_dispatch_source_timer), field-offset [0x103d0da00]
    /// Confirmed by MetalPlayView_updateFPS which calls OS_dispatch_source_timer.schedule(deadline:repeating:leeway:).
    /// The init builds it via OS_dispatch_source.makeTimerSource(flags:queue:) on DispatchQueue.main.
    /// Created but NOT scheduled in init -- scheduling deferred to enterForeground/updateFPS.
    /// Non-optional: binary init unconditionally assigns via makeTimerSource; reference persists
    /// through cancel() (DispatchSourceTimer object stays allocated after cancellation).
    private var backgroundTimer: DispatchSourceTimer

    /// RE: +0xA0, Bool (1 byte, POD), field-offset [0x103d0da10]
    /// Selects the backgroundTimer (DispatchSourceTimer) scheduling path vs the displayLink
    /// path in updateFPS. Copied from KSOptions.renderUseDispatchSourceTimer in init.
    private var renderUseDispatchSourceTimer: Bool = false

    /// Tracks whether the DispatchSourceTimer is currently suspended. DispatchSourceTimer
    /// starts in a suspended state and resume/suspend calls must be balanced.
    private var isTimerSuspended: Bool = true

    public weak var displayLayerDelegate: DisplayLayerDelegate?

    /// RE: 0x101442fe8 (MetalPlayView.init designated, 1.3.15) / 0x101442fb8 (allocating wrapper)
    public init(options: KSOptions) {
        self.options = options
        // Step 3 (moved before super.init): Build DispatchSourceTimer on DispatchQueue.main.
        // Timer source created here; event handler set after super.init (captures [weak self]).
        // Timer is created but NOT scheduled -- scheduling deferred to resume/updateFPS.
        backgroundTimer = DispatchSource.makeTimerSource(flags: [], queue: .main)
        // Step 5 (moved before super.init): Box metalView's CAMetalLayer into the drawable existential.
        // Binary field at +0x48 is a 40-byte non-optional existential container, always assigned.
        // RE: the binary boxes the CAMetalLayer (not the MetalView) using
        // TargetProtocolConformanceDescriptor_103a27550 (CAMetalLayer : KSPlayer.Drawable).
        drawable = metalView.metalLayer
        super.init(frame: .zero)
        // Step 3 cont'd: Set event handler now that self is available for weak capture.
        backgroundTimer.setEventHandler { [weak self] in
            self?.backgroundTimerFired()
        }
        // Step 2: Build + pin subviews. Binary pins via MetalView_resetDrawableSize (4 NSLayoutConstraints).
        addSubview(displayView)
        addSubview(metalView)
        metalView.isHidden = true
        // Step 4: Build CADisplayLink, add to main runloop, start paused.
        let link = CADisplayLink(target: self, selector: #selector(renderFrame))
        link.add(to: .main, forMode: .common)
        link.isPaused = true
        displayLink = link
        // Step 6: Copy renderUseDispatchSourceTimer from KSOptions.
        renderUseDispatchSourceTimer = options.renderUseDispatchSourceTimer
        // Step 8: Prime the AVSampleBufferDisplayLayer with a 1x1 BGRA CVPixelBuffer.
        primeDisplayLayer()
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Play / Pause

    /// RE: 0x1014439b0 (set isPaused = false, 1.3.15)
    /// Writes isPaused=0; if was paused && !renderUseDispatchSourceTimer -> displayLink.isPaused = false;
    /// resumes backgroundTimer if not cancelled.
    public func play() {
        let wasPaused = isPaused
        isPaused = false
        if options.isUseDisplayLayer() {
            if displayView.isHidden {
                displayView.isHidden = false
                metalView.isHidden = true
                metalView.clear(render: render)
            }
            displayView.owner = self
            displayView.play(renderSource: renderSource)
        } else {
            if wasPaused, !renderUseDispatchSourceTimer {
                displayLink?.isPaused = false
            }
            resumeBackgroundTimerIfNeeded()
        }
    }

    /// RE: 0x101443a8c (set isPaused = true, 1.3.15)
    /// Writes isPaused=1; if was unpaused && !renderUseDispatchSourceTimer -> displayLink.isPaused = true;
    /// suspends backgroundTimer if not cancelled.
    public func pause() {
        let wasPaused = isPaused
        isPaused = true
        if options.isUseDisplayLayer() {
            displayView.pause()
        }
        if !wasPaused, !renderUseDispatchSourceTimer {
            displayLink?.isPaused = true
        }
        suspendBackgroundTimerIfNeeded()
    }

    // MARK: - UIView Overrides

    /// RE: 0x1014446f4 / FUN_101444530 (layoutSubviews, 1.3.15)
    /// super.layoutSubviews, loops setFrame: on each subview, reads rotation (+0x1C) and
    /// when != 0 applies CGAffineTransformMakeRotation(rotation * pi/180) as the view
    /// transform (else identity). SOLE consumer of the rotation field.
    override public func layoutSubviews() {
        super.layoutSubviews()
        for subview in subviews {
            subview.frame = bounds
        }
        if rotation != 0 {
            let angle = CGFloat(rotation) * .pi / 180.0
            transform = CGAffineTransform(rotationAngle: angle)
        } else {
            transform = .identity
        }
    }

    override public func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        subview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            subview.leftAnchor.constraint(equalTo: leftAnchor),
            subview.topAnchor.constraint(equalTo: topAnchor),
            subview.bottomAnchor.constraint(equalTo: bottomAnchor),
            subview.rightAnchor.constraint(equalTo: rightAnchor),
        ])
    }

    /// RE: 0x101443f70 / FUN_1014440b0 (setContentMode: + propagation helper, 1.3.15)
    /// After super.setContentMode: runs, mirrors contentMode to metalView and, for modes
    /// in {scaleToFill, scaleAspectFit, scaleAspectFill, redraw}, casts displayView.layer
    /// to AVSampleBufferDisplayLayer and sets videoGravity.
    override public var contentMode: UIViewContentMode {
        didSet {
            propagateContentMode()
        }
    }

    /// RE: FUN_1014440b0 (contentMode propagation helper, 1.3.15)
    /// Called by both setContentMode: and coroutine modify-resume. Mirrors contentMode
    /// to metalView and, for modes in {0,1,2,4} (bitmask 0x17), sets displayView's
    /// AVSampleBufferDisplayLayer videoGravity.
    private func propagateContentMode() {
        metalView.contentMode = contentMode
        // Binary bitmask gate: mode < 5 && ((0x17 >> mode) & 1)
        // Matches: scaleToFill(0), scaleAspectFit(1), scaleAspectFill(2), redraw(4)
        switch contentMode {
        case .scaleToFill:
            displayView.displayLayer.videoGravity = .resize
        case .scaleAspectFit, .center:
            displayView.displayLayer.videoGravity = .resizeAspect
        case .scaleAspectFill:
            displayView.displayLayer.videoGravity = .resizeAspectFill
        #if canImport(UIKit)
        case .redraw:
            // Mode 4 passes the bitmask gate; set aspect as default
            displayView.displayLayer.videoGravity = .resizeAspect
        #endif
        default:
            break
        }
    }

    /// RE: FUN_101444280 @ 0x101444280 (MetalPlayView.touchesMoved, 1.3.15)
    /// Binary reads the DisplayEnum existential witness table [wt+0x08] (Bool gate):
    /// false (Plane/Dovi WT 0x103a274f8) -> super.touchesMoved; true (VR/VRBox WT
    /// 0x103a27808) -> [wt+0x18] = DisplayModel_handlePanGesture @ 0x101470b84.
    #if canImport(UIKit)
    override public func touchesMoved(_ touches: Set<UITouch>, with: UIEvent?) {
        if options.display.isInteractive {
            options.display.touchesMoved(touch: touches.first!)
        } else {
            super.touchesMoved(touches, with: with)
        }
    }
    #else
    override public func touchesMoved(with event: NSEvent) {
        if options.display.isInteractive {
            options.display.touchesMoved(touch: event.allTouches().first!)
        } else {
            super.touchesMoved(with: event)
        }
    }
    #endif

    // MARK: - PiP Delegate Callbacks

    /// RE: 0x101446d9c (didStartPIPTo:, ObjC method-list entry0, 1.3.15)
    /// PiP-start callback. If metalView is not hidden, calls MetalView_resetDrawableSize
    /// (4-NSLayoutConstraint superview pin).
    func didStartPIPTo() {
        if !metalView.isHidden {
            resetMetalViewConstraints()
        }
    }

    /// RE: 0x101446ea8 (didStopPIP, ObjC method-list entry1, 1.3.15)
    /// PiP-stop callback. If metalView is not hidden: (1) resetDrawableSize (re-pin constraints)
    /// AND (2) setFrame to self.bounds. Restores Metal render-surface geometry on PiP exit.
    func didStopPIP() {
        if !metalView.isHidden {
            resetMetalViewConstraints()
            metalView.frame = bounds
        }
    }

    // MARK: - Background / Foreground Lifecycle

    /// RE: FUN_101444bf4 @ 0x101444bf4 (enterBackground, 1.3.15)
    /// Writes isBackground=true. Then iff !renderUseDispatchSourceTimer && !isPaused,
    /// reschedules backgroundTimer DispatchSourceTimer via schedule(deadline: now + 1.0/fps, repeating:).
    /// Spins up the 1/fps DispatchSourceTimer fallback when backgrounding on the CADisplayLink path.
    func enterBackground() {
        isBackground = true
        if !renderUseDispatchSourceTimer, !isPaused {
            let interval = fps > 0 ? 1.0 / Double(fps) : 1.0 / 60.0
            backgroundTimer.schedule(
                deadline: .now() + interval,
                repeating: interval,
                leeway: .milliseconds(1)
            )
        }
    }

    /// RE: FUN_101444d68 @ 0x101444d68 (enterForeground, 1.3.15)
    /// Writes isBackground=false. Then iff !renderUseDispatchSourceTimer parks backgroundTimer
    /// to distantFuture. Then iff metalView.isHidden and pixelBuffer present and formatDescription
    /// non-nil, re-enqueues the last frame via enqueue. Restores on-screen frame after
    /// returning from background.
    func enterForeground() {
        isBackground = false
        if !renderUseDispatchSourceTimer {
            backgroundTimer.schedule(deadline: .distantFuture, repeating: .never)
        }
        // Re-enqueue the last frame if the Metal surface is hidden (AVSBDL path)
        if metalView.isHidden,
           let pixelBuffer,
           let cvPixelBuffer = pixelBuffer.cvPixelBuffer,
           formatDescription != nil {
            enqueue(imageBuffer: cvPixelBuffer)
        }
    }

    // MARK: - Public Interface

    /// RE: 0x101444704 (flush) -- see also stop (FUN_101444aa0)
    public func flush() {
        pixelBuffer = nil
        if displayView.isHidden {
            metalView.clear(render: render)
        } else {
            displayView.flush(keepImage: true)
        }
    }

    public func flushAndRemoveImage() {
        pixelBuffer = nil
        if displayView.isHidden {
            metalView.clear(render: render)
        } else {
            displayView.flush(keepImage: false)
        }
    }

    /// RE: 0x101444aa0 (stop/teardown, Ghidra mislabel ReadCacheIOContext_setLogicalPos, 1.3.15)
    /// Calls clearDisplay first; stops displayLink via invalidate; if isPaused resumes
    /// backgroundTimer, then unconditionally cancels backgroundTimer. Full teardown of
    /// both tick sources.
    public func invalidate() {
        clearDisplay()
        displayLink?.invalidate()
        if isPaused {
            resumeBackgroundTimerIfNeeded()
        }
        backgroundTimer.cancel()
    }

    public func readNextFrame() {
        if options.isUseDisplayLayer() {
            displayView.readNextFrame(renderSource: renderSource, options: options, owner: self)
        } else {
            draw(force: true)
        }
    }
}

// MARK: - Render Loop

extension MetalPlayView {
    /// RE: 0x101443938 (renderFrameIfActive gate, 1.3.15) + 0x1014451b4 (renderFrame selector trampoline)
    /// The CADisplayLink @selector(renderFrame) target. Gated: if (!isBackground && !isPaused)
    /// { autoreleasePoolPush; renderFrameImpl; pop }.
    @objc private func renderFrame() {
        if isBackground || isPaused {
            return
        }
        if options.isUseDisplayLayer() {
            return
        }
        draw(force: false)
    }

    /// RE: FUN_101443728 @ 0x101443728 (DispatchSourceTimer event handler, 1.3.15)
    /// @MainActor-guarded. If renderUseDispatchSourceTimer && !isBackground:
    ///   if !isPaused -> autoreleasePoolPush -> renderFrameImpl -> pop.
    /// Else: pulls a frame from renderSource and stores into pixelBuffer.
    private func backgroundTimerFired() {
        if renderUseDispatchSourceTimer, !isBackground {
            if !isPaused {
                draw(force: false)
            }
        } else {
            // Pull-and-store path: grab a frame for the AVSBDL layer
            guard let frame = renderSource?.getVideoOutputRender(force: false) else { return }
            pixelBuffer = frame.corePixelBuffer
        }
    }

    /// RE: 0x10144529c (renderFrameImpl, 1.3.15)
    /// The AVSBDL-path frame update helper for frames arriving via the display layer callback.
    func drawFrame(_ frame: VideoVTBFrame) {
        pixelBuffer = frame.corePixelBuffer
        guard let pixelBuffer else { return }
        isDovi = frame.isDovi
        fps = frame.fps
        let par = pixelBuffer.size
        let sar = pixelBuffer.aspectRatio
        if let cvPixelBuffer = pixelBuffer.cvPixelBuffer {
            if let dar = options.customizeDar(sar: sar, par: par) {
                cvPixelBuffer.aspectRatio = CGSize(width: dar.width, height: dar.height * par.width / par.height)
            }
            checkFormatDescription(pixelBuffer: pixelBuffer)
        }
        renderSource?.setVideo(time: frame.cmtime, position: frame.position)
    }

    /// RE: 0x10144529c (renderFrameImpl Metal/DV path, 1.3.15)
    private func draw(force: Bool) {
        autoreleasepool {
            guard let frame = renderSource?.getVideoOutputRender(force: force) else {
                return
            }
            pixelBuffer = frame.corePixelBuffer
            guard let pixelBuffer else {
                return
            }
            isDovi = frame.isDovi
            fps = frame.fps
            let cmtime = frame.cmtime
            let par = pixelBuffer.size
            let sar = pixelBuffer.aspectRatio

            // Binary: renderFrameImpl checks isUseDisplayLayer(frame:isHDRScreen:) to route
            // between AVSBDL and Metal paths. EDR headroom is read from
            // [[[self window] screen] currentEDRHeadroom] to compute isHDRScreen.
            #if !os(tvOS)
            let isHDRScreen: Bool = {
                #if canImport(UIKit)
                if #available(iOS 16, *) {
                    return (window?.screen ?? UIScreen.main).currentEDRHeadroom > 1.0
                }
                #elseif os(macOS)
                if #available(macOS 14.0, *) {
                    return window?.screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0 > 1.0
                }
                #endif
                return false
            }()
            #else
            let isHDRScreen = false
            #endif

            if !displayView.isHidden {
                displayView.isHidden = true
                metalView.isHidden = false
                displayView.flush(keepImage: false)
            }
            let size: CGSize
            if options.display == .plane {
                if let dar = options.customizeDar(sar: sar, par: par) {
                    size = CGSize(width: par.width, height: par.width * dar.height / dar.width)
                } else {
                    size = CGSize(width: par.width, height: par.height * sar.height / sar.width)
                }
            } else {
                size = KSOptions.sceneSize
            }
            checkFormatDescription(pixelBuffer: pixelBuffer)
            #if !os(tvOS)
            if #available(iOS 16, *) {
                metalView.metalLayer.edrMetadata = frame.edrMetadata
            }
            #endif
            // DV routing -- gate is independent of enhanceDolby per binary decompile at
            // 0x101407908 (processFrameSideData does NOT read DAT_104450978).
            // Three-gate guard per binary (DolbyVision.md lines 899-909):
            //   1. track flag bit 0 at +0x13a (isDovi)
            //   2. AVFrame.format == 2 (pixel format is VideoToolbox hardware-decoded)
            //   3. KSOptions.hardwareDecode == 1
            // Gate 2 is a per-frame check that the decoded frame is actually in
            // VideoToolbox pixel format; the Swift equivalent at render time is
            // pixelBuffer.cvPixelBuffer != nil (only CVPixelBuffer-backed frames
            // originate from the VideoToolbox decode path).
            var doviMetadata: DoviGPUMetadata?
            if isDovi,
               pixelBuffer.cvPixelBuffer != nil,
               options.hardwareDecode,
               let doviData = frame.doviData,
               doviData.header != nil, doviData.mapping != nil {
                doviMetadata = DoviGPUMetadata.from(header: doviData.header, mapping: doviData.mapping, color: doviData.color)
            }
            metalView.draw(pixelBuffer: pixelBuffer, display: options.display, size: size, doviMetadata: doviMetadata, options: options, render: render, anime4KPipeline: anime4KPipeline)
            renderSource?.setVideo(time: cmtime, position: frame.position)
        }
    }

    /// RE: 0x101445c40 -> 0x1014425bc (format-swap guard + format-reconfigure, 1.3.15)
    /// Compares the frame's format via PixelBufferProtocol.matches(formatDescription:);
    /// on mismatch swaps self.formatDescription and runs the dynamicRange tail:
    /// KSOptions.dynamicRange = isDovi ? .dolbyVision : classifyDynamicRange(fromFormatDescription:)
    /// then KSOptions.updateVideo(refreshRate:isDovi:formatDescription:).
    private func checkFormatDescription(pixelBuffer: PixelBufferProtocol) {
        // Binary spells this "matche" — typo fixed to "matches" per reconstruction rules.
        if formatDescription == nil || !pixelBuffer.matches(formatDescription: formatDescription!) {
            if formatDescription != nil {
                // RE: FUN_1014425bc (format-reconfigure path, 1.3.15)
                // On format dimension mismatch: rebuild displayView, create BGRA CVPixelBuffer,
                // enqueue to prime, then run dynamicRange tail.
                let wasPlaying = !(displayLink?.isPaused ?? isPaused) || displayView.isPlaying
                displayView.stopRequestingData()
                displayView.removeFromSuperview()
                displayView = AVSampleBufferDisplayView()
                displayView.frame = frame
                addSubview(displayView)
                if wasPlaying, options.isUseDisplayLayer() {
                    displayView.play(renderSource: renderSource)
                }
            }
            formatDescription = pixelBuffer.formatDescription
            // RE: DynamicRange tail (LAB_1014426c8, 1.3.15)
            // KSOptions.dynamicRange = isDovi ? 3 : KSOptions_classifyDynamicRange_fromFormatDescription()
            if isDovi {
                options.dynamicRange = .dolbyVision
            } else if let fmt = formatDescription {
                let code = KSOptions.classifyDynamicRange(codecTag: 0, formatDescription: fmt)
                options.dynamicRange = DynamicRange(rawValue: Int32(code)) ?? .sdr
            }
        }
    }

    /// RE: FUN_1014427a4 @ 0x1014427a4 (updateFPS, 1.3.15)
    /// Handles fps change: UIScreen.maximumFramesPerSecond clamp, calls KSOptions[+0xa08]
    /// Bool predicate to select displayLink vs DispatchSourceTimer scheduling, schedules
    /// backgroundTimer when appropriate, shares the dynamicRange + KSOptions.updateVideo tail
    /// with format-reconfigure.
    private func updateFPS() {
        // Clamp to screen max (binary reads UIScreen.maximumFramesPerSecond)
        #if canImport(UIKit) && !os(tvOS)
        let screenMax = Float(UIScreen.main.maximumFramesPerSecond)
        let clampedFps = min(fps, screenMax)
        #else
        let clampedFps = fps
        #endif

        if KSOptions.preferredFrame {
            let preferred = ceil(clampedFps)
            if let displayLink {
                if #available(iOS 15.0, tvOS 15.0, macOS 14.0, *) {
                    displayLink.preferredFrameRateRange = CAFrameRateRange(
                        minimum: preferred,
                        maximum: 2 * preferred,
                        __preferred: preferred
                    )
                } else {
                    displayLink.preferredFramesPerSecond = Int(preferred) << 1
                }
            }
        }

        // RE: KSOptions[+0xa08] Bool predicate selects displayLink vs DispatchSourceTimer path
        // The binary checks renderUseDispatchSourceTimer to decide scheduling.
        if renderUseDispatchSourceTimer {
            let interval = clampedFps > 0 ? 1.0 / Double(clampedFps) : 1.0 / 60.0
            backgroundTimer.schedule(
                deadline: .now() + interval,
                repeating: interval,
                leeway: .milliseconds(1)
            )
        }

        // DynamicRange + updateVideo tail (shared with format-reconfigure)
        if isDovi {
            options.dynamicRange = .dolbyVision
        } else if let fmt = formatDescription {
            let code = KSOptions.classifyDynamicRange(codecTag: 0, formatDescription: fmt)
            options.dynamicRange = DynamicRange(rawValue: Int32(code)) ?? .sdr
        }
        options.updateVideo(refreshRate: fps, isDovi: isDovi, formatDescription: formatDescription)
    }
}

// MARK: - Private Helpers

extension MetalPlayView {
    /// RE: FUN_101444704 @ 0x101444704 (clearDisplay, 1.3.15)
    /// Nils self.pixelBuffer. If metalView not hidden: dispatches Drawable witness +0x10
    /// (clear/blank -> FUN_10146a0e4 -> setEDRMetadata:nil + FUN_10146b508 clear-present),
    /// then schedules 1s-delayed CVMetalTextureCacheFlush. If hidden: casts displayView.layer
    /// to AVSampleBufferDisplayLayer and flushes.
    private func clearDisplay() {
        pixelBuffer = nil
        if !metalView.isHidden {
            drawable.clear(render: render)
            // RE: FUN_101447030 -> FUN_1014448f4 -> FUN_10144495c -> FUN_1014449f8
            // Task/continuation chain that flushes CVMetalTextureCache after 1-second delay.
            // The binary flushes DAT_104458f70 (the shared CVMetalTextureCache) after 1s on MainActor.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                MetalRender.flushTextureCache()
            }
        } else {
            displayView.displayLayer.flushAndRemoveImage()
        }
    }

    /// RE: MetalPlayView.init step 8 (primeDisplayLayer, 1.3.15)
    /// Creates a 1x1 BGRA CVPixelBuffer and enqueues it onto the display layer to
    /// prime/initialize the fallback display-layer pipeline at construction.
    private func primeDisplayLayer() {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: 1,
            kCVPixelBufferHeightKey: 1,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            1, 1,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard let pixelBuffer else { return }
        var fmtDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &fmtDesc
        )
        guard let fmtDesc else { return }
        enqueue(imageBuffer: pixelBuffer, formatDescription: fmtDesc)
    }

    /// RE: FUN_101445d1c @ 0x101445d1c (enqueue, 1.3.15)
    /// MetalPlayView method (NOT AVSampleBufferDisplayView) that builds CMSampleBuffer from
    /// CVImageBuffer, sets DisplayImmediately attachment, handles iOS 17+ sampleBufferRenderer
    /// API split, requiresFlush handling, isReadyForMoreMediaData gate, terminal enqueue,
    /// post-enqueue status/flush-on-failure.
    /// 4 LIVE code callers: renderFrameImpl, init (priming), format-reconfigure, foreground-resume.
    private func enqueue(imageBuffer: CVPixelBuffer, formatDescription: CMVideoFormatDescription? = nil) {
        let fmtDesc: CMVideoFormatDescription
        if let formatDescription {
            fmtDesc = formatDescription
        } else if let desc = self.formatDescription {
            fmtDesc = desc as CMVideoFormatDescription
        } else {
            return
        }

        let timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: imageBuffer,
            formatDescription: fmtDesc,
            sampleTiming: [timing],
            sampleBufferOut: &sampleBuffer
        )
        guard let sampleBuffer else { return }

        // RE: Step 2 -- Set DisplayImmediately attachment
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) as? [NSMutableDictionary],
           let dict = attachments.first {
            dict[kCMSampleAttachmentKey_DisplayImmediately] = true
        }

        let layer = displayView.displayLayer

        // RE: Step 3 -- iOS 17+ sampleBufferRenderer API split
        if #available(iOS 17.0, tvOS 17.0, macOS 14.0, *) {
            let renderer = layer.sampleBufferRenderer
            // RE: Step 4 -- requiresFlush handling
            if renderer.requiresFlush {
                KSLog("[video] AVSampleBufferDisplayLayer requiresFlush")
                layer.flush()
            }
            // RE: Step 5 -- isReadyForMoreMediaData gate
            if !renderer.isReadyForMoreMediaData {
                KSLog("[video] AVSampleBufferDisplayLayer not readyForMoreMediaData")
            }
            // RE: Step 6 -- Terminal enqueue
            renderer.enqueue(sampleBuffer)
            // RE: Step 7 -- Post-enqueue status/flush-on-failure
            if renderer.status == .failed {
                KSLog("[video] AVSampleBufferDisplayLayer status failed so flush")
                layer.flush()
            }
        } else {
            // Pre-iOS 17 legacy path
            if #available(macOS 11.0, iOS 14, tvOS 14, *) {
                if layer.requiresFlushToResumeDecoding {
                    KSLog("[video] AVSampleBufferDisplayLayer requiresFlush")
                    layer.flush()
                }
            }
            if !layer.isReadyForMoreMediaData {
                KSLog("[video] AVSampleBufferDisplayLayer not readyForMoreMediaData")
            }
            layer.enqueue(sampleBuffer)
            if layer.status == .failed {
                KSLog("[video] AVSampleBufferDisplayLayer status failed so flush")
                layer.flush()
            }
        }
    }

    /// Pin metalView to superview with 4 NSLayoutConstraints (matches binary MetalView_resetDrawableSize @ 0x1013d5db8).
    private func resetMetalViewConstraints() {
        metalView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            metalView.leftAnchor.constraint(equalTo: leftAnchor),
            metalView.topAnchor.constraint(equalTo: topAnchor),
            metalView.bottomAnchor.constraint(equalTo: bottomAnchor),
            metalView.rightAnchor.constraint(equalTo: rightAnchor),
        ])
    }

    /// Resume the DispatchSourceTimer if it is currently suspended and has not been cancelled.
    /// DispatchSourceTimer resume/suspend must be balanced; over-resuming crashes.
    private func resumeBackgroundTimerIfNeeded() {
        guard isTimerSuspended else { return }
        backgroundTimer.resume()
        isTimerSuspended = false
    }

    /// Suspend the DispatchSourceTimer if it is currently resumed and has not been cancelled.
    private func suspendBackgroundTimerIfNeeded() {
        guard !isTimerSuspended else { return }
        backgroundTimer.suspend()
        isTimerSuspended = true
    }
}

// MARK: - MetalView

/// RE: _TtC8KSPlayer9MetalView (1.3.15)
/// CMa: $s8KSPlayer9MetalViewCMa @ 0x101443698
/// init: MetalView_init_zeroFrame_setDevice @ 0x10144655c
/// types.json: parent __C.UIView, zero stored properties. MetalView is a thin UIView
/// subclass that overrides layerClass to CAMetalLayer. Its render state lives on the layer
/// and on the MetalRender/Anime4KPipeline instances owned by MetalPlayView, not on
/// MetalView instance fields.
class MetalView: UIView, Drawable {
    #if canImport(UIKit)
    override public class var layerClass: AnyClass { CAMetalLayer.self }
    #endif
    var metalLayer: CAMetalLayer {
        // swiftlint:disable force_cast
        layer as! CAMetalLayer
        // swiftlint:enable force_cast
    }

    /// RE: 0x10144655c (MetalView_init_zeroFrame_setDevice, 1.3.15)
    init() {
        super.init(frame: .zero)
        #if !canImport(UIKit)
        layer = CAMetalLayer()
        #endif
        metalLayer.device = MetalRender.device
        metalLayer.framebufferOnly = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// RE: Drawable witness slot +0x10 (clear/blank, 1.3.15)
    /// FUN_10146a0e4 -> setEDRMetadata:nil + FUN_10146b508 (MTLLoadActionClear present).
    func clear(render: MetalRender) {
        #if !os(tvOS)
        if #available(iOS 16.0, *) {
            metalLayer.edrMetadata = nil
        }
        #endif
        if let drawable = metalLayer.nextDrawable() {
            render.clear(drawable: drawable)
        }
    }

    /// RE: Drawable witness slot +0x08 (draw/present, 1.3.15)
    /// The main render path through FUN_10146a0c4 -> FUN_101469550 (EDR) -> FUN_10146bec4 (present).
    func draw(
        pixelBuffer: PixelBufferProtocol,
        display: DisplayEnum,
        size: CGSize,
        doviMetadata: DoviGPUMetadata? = nil,
        options: KSOptions,
        render: MetalRender,
        anime4KPipeline: Anime4KPipeline?
    ) {
        if !options.canUseSimpleRenderPipeline() {
            render.updateBCSFromOptions(options)
        }
        metalLayer.drawableSize = size
        metalLayer.pixelFormat = KSOptions.colorPixelFormat(bitDepth: pixelBuffer.bitDepth)

        // DV path: force ITU-R 2100 PQ color space.
        if doviMetadata != nil {
            let pqColorspace = CGColorSpace(name: CGColorSpace.itur_2100_PQ)
            if metalLayer.colorspace != pqColorspace {
                metalLayer.colorspace = pqColorspace
                KSLog("[video] CAMetalLayer colorspace \(String(describing: pqColorspace)) (DV)")
                #if !os(tvOS)
                if #available(iOS 16.0, *) {
                    #if os(macOS)
                    metalLayer.wantsExtendedDynamicRangeContent = window?.screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0 > 1.0
                    #else
                    metalLayer.wantsExtendedDynamicRangeContent = true
                    #endif
                    KSLog("[video] CAMetalLayer wantsExtendedDynamicRangeContent \(metalLayer.wantsExtendedDynamicRangeContent)")
                }
                #endif
            }
        } else {
            let colorspace = pixelBuffer.colorspace
            if colorspace != nil, metalLayer.colorspace != colorspace {
                metalLayer.colorspace = colorspace
                KSLog("[video] CAMetalLayer colorspace \(String(describing: colorspace))")
                #if !os(tvOS)
                if #available(iOS 16.0, *) {
                    if let name = colorspace?.name, name != CGColorSpace.sRGB {
                        #if os(macOS)
                        metalLayer.wantsExtendedDynamicRangeContent = window?.screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0 > 1.0
                        #else
                        metalLayer.wantsExtendedDynamicRangeContent = true
                        #endif
                    } else {
                        metalLayer.wantsExtendedDynamicRangeContent = false
                    }
                    KSLog("[video] CAMetalLayer wantsExtendedDynamicRangeContent \(metalLayer.wantsExtendedDynamicRangeContent)")
                }
                #endif
            }
        }

        guard let drawable = metalLayer.nextDrawable() else {
            KSLog("[video] CAMetalLayer not readyForMoreMediaData")
            return
        }

        if let metadata = doviMetadata {
            render.drawDovi(pixelBuffer: pixelBuffer, drawable: drawable, metadata: metadata)
        } else {
            render.draw(pixelBuffer: pixelBuffer, display: display, drawable: drawable)
        }
        // Anime4K upscaling pass — runs after main render, before display.
        // Binary lifecycle is two-step: loadPreset (step 1, selects shader config)
        // then configurePixelBuffer (step 2, creates textures + pipeline states).
        // RE: 0x101340054 (loadPreset), 0x10134057C (configurePixelBuffer)
        if KSOptions.enableAnime4K, let pipeline = anime4KPipeline {
            if !pipeline.configured {
                let inputW = pixelBuffer.cvPixelBuffer.map { CVPixelBufferGetWidth($0) } ?? Int(size.width)
                let inputH = pixelBuffer.cvPixelBuffer.map { CVPixelBufferGetHeight($0) } ?? Int(size.height)
                pipeline.loadPreset(KSOptions.anime4KPreset)
                pipeline.configurePixelBuffer(
                    width: inputW, height: inputH,
                    displayWidth: drawable.texture.width,
                    displayHeight: drawable.texture.height
                )
            }
            if pipeline.configured {
                _ = pipeline.process(inputTexture: drawable.texture)
            }
        }
    }
}

// MARK: - AVSampleBufferDisplayView

/// RE: _TtC8KSPlayer25AVSampleBufferDisplayView (1.3.15)
/// CMa: $s8KSPlayer25AVSampleBufferDisplayViewCMa @ 0x1014436b8
/// init: AVSampleBufferDisplayView_initWithFrame @ 0x1014469c8
class AVSampleBufferDisplayView: UIView {
    #if canImport(UIKit)
    override public class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    #endif
    var displayLayer: AVSampleBufferDisplayLayer {
        // swiftlint:disable force_cast
        layer as! AVSampleBufferDisplayLayer
        // swiftlint:enable force_cast
    }

    private var controlTimebase: CMTimebase?
    private let requestQueue = DispatchQueue(label: "ks.player.avsbdl.queue")
    private weak var activeRenderSource: OutputRenderSourceDelegate?
    weak var owner: MetalPlayView?
    private(set) var isPlaying = false
    private var isRequestingData = false

    /// RE: 0x1014469c8 (AVSampleBufferDisplayView_initWithFrame, 1.3.15)
    override init(frame: CGRect) {
        super.init(frame: frame)
        #if !canImport(UIKit)
        layer = AVSampleBufferDisplayLayer()
        #endif
        var timebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase)
        if let timebase {
            controlTimebase = timebase
            displayLayer.controlTimebase = timebase
            CMTimebaseSetTime(timebase, time: .zero)
            CMTimebaseSetRate(timebase, rate: 0.0)
        }
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        #endif
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopRequestingData()
    }

    // MARK: - Playback control

    func play(renderSource: OutputRenderSourceDelegate?) {
        activeRenderSource = renderSource
        isPlaying = true
        guard let controlTimebase else { return }
        CMTimebaseSetRate(controlTimebase, rate: 1.0)
        startRequestingData()
    }

    func pause() {
        isPlaying = false
        guard let controlTimebase else { return }
        CMTimebaseSetRate(controlTimebase, rate: 0.0)
        stopRequestingData()
    }

    func flush(keepImage: Bool) {
        isRequestingData = false
        displayLayer.stopRequestingMediaData()
        if keepImage {
            displayLayer.flush()
        } else {
            displayLayer.flushAndRemoveImage()
        }
    }

    func seek(to time: CMTime) {
        isRequestingData = false
        displayLayer.stopRequestingMediaData()
        displayLayer.flush()
        if let controlTimebase {
            CMTimebaseSetTime(controlTimebase, time: time)
        }
    }

    func readNextFrame(renderSource: OutputRenderSourceDelegate?, options: KSOptions, owner: MetalPlayView) {
        self.activeRenderSource = renderSource
        self.owner = owner
        requestQueue.async { [weak self] in
            guard let self, let frame = renderSource?.getVideoOutputRender(force: true) else { return }
            self.enqueueFrame(frame, options: options)
        }
    }

    // MARK: - Pull-based frame delivery

    func stopRequestingData() {
        isRequestingData = false
        displayLayer.stopRequestingMediaData()
    }

    private func startRequestingData() {
        guard !isRequestingData else { return }
        isRequestingData = true
        displayLayer.requestMediaDataWhenReady(on: requestQueue) { [weak self] in
            self?.pullFrames()
        }
    }

    private func pullFrames() {
        while displayLayer.isReadyForMoreMediaData, isPlaying {
            guard let frame = activeRenderSource?.getVideoOutputRender(force: false) else {
                break
            }
            enqueueFrame(frame, options: owner?.options)
        }
    }

    private func enqueueFrame(_ frame: VideoVTBFrame, options: KSOptions?) {
        guard let pixelBuffer = frame.corePixelBuffer,
              let cvPixelBuffer = pixelBuffer.cvPixelBuffer else { return }

        let formatDescription = pixelBuffer.formatDescription
        guard let formatDescription else { return }

        let cmtime = frame.cmtime
        let timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: cmtime, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: cvPixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: [timing],
            sampleBufferOut: &sampleBuffer
        )
        guard let sampleBuffer else { return }

        displayLayer.enqueue(sampleBuffer)

        if #available(macOS 11.0, iOS 14, tvOS 14, *) {
            if displayLayer.requiresFlushToResumeDecoding {
                KSLog("[video] AVSampleBufferDisplayLayer requiresFlushToResumeDecoding")
                displayLayer.flush()
            }
        }
        if displayLayer.status == .failed {
            KSLog("[video] AVSampleBufferDisplayLayer status failed: \(String(describing: displayLayer.error))")
            displayLayer.flush()
        }

        DispatchQueue.main.async { [weak self] in
            self?.owner?.drawFrame(frame)
        }
    }

    // MARK: - Recovery

    @objc private func didBecomeActive() {
        if displayLayer.status == .failed {
            KSLog("[video] AVSampleBufferDisplayLayer recovering from background failure")
            displayLayer.flushAndRemoveImage()
            if isPlaying {
                startRequestingData()
            }
        }
    }
}

// MARK: - macOS CADisplayLink polyfill

#if os(macOS)
import CoreVideo

class CADisplayLink: DisplayLinkProtocol {
    private let displayLink: CVDisplayLink
    private var runloop: RunLoop?
    private var mode = RunLoop.Mode.default
    public var preferredFramesPerSecond = 60
    @available(macOS 12.0, *)
    public var preferredFrameRateRange: CAFrameRateRange {
        get {
            CAFrameRateRange()
        }
        set {}
    }

    public var timestamp: TimeInterval {
        var timeStamp = CVTimeStamp()
        if CVDisplayLinkGetCurrentTime(displayLink, &timeStamp) == kCVReturnSuccess, (timeStamp.flags & CVTimeStampFlags.hostTimeValid.rawValue) != 0 {
            return TimeInterval(timeStamp.hostTime / NSEC_PER_SEC)
        }
        return 0
    }

    public var duration: TimeInterval {
        CVDisplayLinkGetActualOutputVideoRefreshPeriod(displayLink)
    }

    public var targetTimestamp: TimeInterval {
        duration + timestamp
    }

    public var isPaused: Bool {
        get {
            !CVDisplayLinkIsRunning(displayLink)
        }
        set {
            if newValue {
                CVDisplayLinkStop(displayLink)
            } else {
                CVDisplayLinkStart(displayLink)
            }
        }
    }

    public init(target: NSObject, selector: Selector) {
        var displayLink: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        self.displayLink = displayLink!
        CVDisplayLinkSetOutputHandler(self.displayLink) { [weak self] _, _, _, _, _ in
            guard let self else { return kCVReturnSuccess }
            self.runloop?.perform(selector, target: target, argument: self, order: 0, modes: [self.mode])
            return kCVReturnSuccess
        }
        CVDisplayLinkStart(self.displayLink)
    }

    public init(block: @escaping (() -> Void)) {
        var displayLink: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        self.displayLink = displayLink!
        CVDisplayLinkSetOutputHandler(self.displayLink) { _, _, _, _, _ in
            block()
            return kCVReturnSuccess
        }
        CVDisplayLinkStart(self.displayLink)
    }

    open func add(to runloop: RunLoop, forMode mode: RunLoop.Mode) {
        self.runloop = runloop
        self.mode = mode
    }

    public func invalidate() {
        isPaused = true
        runloop = nil
        CVDisplayLinkSetOutputHandler(displayLink) { _, _, _, _, _ in
            kCVReturnError
        }
    }
}
#endif
