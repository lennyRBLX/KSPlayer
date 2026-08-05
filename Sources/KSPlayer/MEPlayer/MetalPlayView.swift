//
//  MetalPlayView.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/11.
//

import AVFoundation
import Combine
import CoreMedia
#if canImport(MetalKit)
import MetalKit
#endif
public protocol DisplayLayerDelegate: NSObjectProtocol {
    func change(displayLayer: AVSampleBufferDisplayLayer)
}

public protocol VideoOutput: FrameOutput {
    var renderSource: VideoOutputRenderSourceDelegate? { get set }
    // Source-only; removal derived and ready, but it is its own unit (see the field below).
    var displayLayerDelegate: DisplayLayerDelegate? { get set }
    var options: KSOptions { get set }
    var displayLayer: AVSampleBufferDisplayLayer { get }
    var pixelBuffer: PixelBufferProtocol? { get }
    init(options: KSOptions)
    func invalidate()
    func readNextFrame()
}

public final class MetalPlayView: UIView, @preconcurrency VideoOutput {
    public var displayLayer: AVSampleBufferDisplayLayer {
        displayView.displayLayer
    }

    private var isDovi: Bool = false
    private var formatDescription: CMFormatDescription? {
        didSet {
            options.updateVideo(refreshRate: fps, isDovi: isDovi, formatDescription: formatDescription)
        }
    }

    private var fps = Float(60) {
        didSet {
            if fps != oldValue {
                if KSOptions.preferredFrame {
                    let preferredFramesPerSecond = ceil(fps)
                    if #available(iOS 15.0, tvOS 15.0, macOS 14.0, *) {
                        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: preferredFramesPerSecond, maximum: 2 * preferredFramesPerSecond, __preferred: preferredFramesPerSecond)
                    } else {
                        displayLink?.preferredFramesPerSecond = Int(preferredFramesPerSecond) << 1
                    }
                }
                options.updateVideo(refreshRate: fps, isDovi: isDovi, formatDescription: formatDescription)
            }
        }
    }

    /// ⚑[tool=field_offset_vector ref=MetalPlayView.rotation result=index-3@0x1c]
    /// Placed HERE, not appended: the binary's field-offset vector puts `rotation` at index 3
    /// (offset 0x1c), between `fps` (2) and `pixelBuffer` (4), and stored-property order is part
    /// of the layout rather than a style choice.
    ///
    /// It is a plain STORED property, not computed — its getter @0x101a5e8b4 is a
    /// `swift_beginAccess` on `self + <offset global 0x1044ea8b0>` followed by a bare `ldrh w0`,
    /// with a matching setter and modify coroutine. A computed property would show work here.
    ///
    /// `public` is PROVEN by its `vpMV` (property descriptor @0x10356b4e0), not inferred from the
    /// enclosing class. The default is READ from its own `vpfi` @0x10002dab0 — `mov w0, #0` /
    /// `ret` — so `= 0` is transcribed, not assumed to be the zero default.
    /// ⚑[tool=export_trie_oracle ref=MetalPlayView.rotation:0x10356b4e0 result=vpMV-public]
    public var rotation: UInt16 = 0
    public private(set) var pixelBuffer: PixelBufferProtocol?
    public var options: KSOptions
    // Binary type is the NARROWER `VideoOutputRenderSourceDelegate?`; OutputRenderSourceDelegate
    // refines it with the audio half, which this view never uses.
    public weak var renderSource: VideoOutputRenderSourceDelegate?
    /// ⚑[tool=field_offset_vector ref=MetalPlayView.drawable result=index-7@0x48]
    /// Placed at its field-record index (7, offset 0x48), between `renderSource` (6) and
    /// `metalView` (8) — layout, not style.
    ///
    /// Stored, not computed: the getter @0x101a5ec80 is a `swift_beginAccess` on
    /// `self + <offset global 0x1044ea8d0>` followed by an outlined indirect copy into the sret
    /// (`bl 0x1001263e0`), with a matching setter and modify coroutine. `public` is proven by its
    /// `vpMV`.
    ///
    /// ⚑ It has NO `vpfi`, so there is no declaration default — writing one would be fabrication.
    ///   The value comes from `init(options:)`, and the assignment there is read in full below.
    public var drawable: Drawable
    private let metalView = MetalView()
    // AVSampleBufferAudioRenderer AVSampleBufferRenderSynchronizer AVSampleBufferDisplayLayer
    private var displayView = AVSampleBufferDisplayView() {
        didSet {
            displayLayerDelegate?.change(displayLayer: displayView.displayLayer)
        }
    }

    /// 用displayLink会导致锁屏无法draw，
    /// 用DispatchSourceTimer的话，在播放4k视频的时候repeat的时间会变长,
    /// 用MTKView的draw(in:)也是不行，会卡顿
    // Binary type is `DisplayLinkProtocol?`, not `CADisplayLink!`. DisplayLinkProtocol was
    // reconstructed precisely to abstract UIKit's CADisplayLink and the macOS CVDisplayLink shim
    // behind one interface, and CADisplayLink already conforms — this field never migrated.
    private var displayLink: DisplayLinkProtocol?
//    private let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
    // displayLayerDelegate is a source-only construct — zero-hit across the whole demangled trie,
    // and MetalPlayView's field descriptor does not list it. Its REMOVAL is derived and ready. The
    // KSMEPlayer block that held it up is gone (unit 6 landed), so it is now just its own unit:
    // dropping it touches this protocol, this field, the displayView didSet and two KSMEPlayer sites.
    public weak var displayLayerDelegate: DisplayLayerDelegate?
    public init(options: KSOptions) {
        self.options = options
        // ⚑[tool=export_trie_oracle ref=MetalPlayView.init(options:):0x101a5eda8 result=drawable-store@0x101a5f0ec]
        // Read from the init, via the OFFSET GLOBAL — this class is `metadata_init=1`, so field
        // accesses index by a register loaded from a per-field global and never use a literal
        // offset. The chain at 0x101a5f098..0x101a5f0f0 is: load `self.<global 0x1044ea8a0>`
        // (= metalView), send `layer` (selref 0x10440bf70), cast, then store into
        // `self + <global 0x1044ea8d0>` (= drawable).
        // ⚑ The cast is FORCED, not conditional: the helper is
        //   `swift_dynamicCastObjCClassUnconditional` (__got 0x104112e20) and the class operand is
        //   `OBJC_CLASS_$_CAMetalLayer` (__objc_classrefs 0x104410d20). A conditional `as?` would
        //   use the nullable variant. `CAMetalLayer : Drawable` is witness 0x1041d9e70.
        // ⚑[tool=bind_oracle ref=__got:0x104112e20 result=swift_dynamicCastObjCClassUnconditional]
        // ⚑[tool=bind_oracle ref=__objc_classrefs:0x104410d20 result=CAMetalLayer]
        drawable = metalView.layer as! CAMetalLayer
        super.init(frame: .zero)
        addSubview(displayView)
        addSubview(metalView)
        metalView.isHidden = true
        //        displayLink = CADisplayLink(block: renderFrame)
        displayLink = CADisplayLink(target: self, selector: #selector(renderFrame))
        // 一定要用common。不然在视频上面操作view的话，那就会卡顿了。
        displayLink?.add(to: .main, forMode: .common)
        pause()
    }

    public func play() {
        displayLink?.isPaused = false
    }

    public func pause() {
        displayLink?.isPaused = true
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

    override public var contentMode: UIViewContentMode {
        didSet {
            metalView.contentMode = contentMode
            switch contentMode {
            case .scaleToFill:
                displayView.displayLayer.videoGravity = .resize
            case .scaleAspectFit, .center:
                displayView.displayLayer.videoGravity = .resizeAspect
            case .scaleAspectFill:
                displayView.displayLayer.videoGravity = .resizeAspectFill
            default:
                break
            }
        }
    }

    #if canImport(UIKit)
    override public func touchesMoved(_ touches: Set<UITouch>, with: UIEvent?) {
        if !options.display.isSphere {
            super.touchesMoved(touches, with: with)
        } else {
            options.display.touchesMoved(touch: touches.first!)
        }
    }
    #else
    override public func touchesMoved(with event: NSEvent) {
        if !options.display.isSphere {
            super.touchesMoved(with: event)
        } else {
            options.display.touchesMoved(touch: event.allTouches().first!)
        }
    }
    #endif

    public func flush() {
        pixelBuffer = nil
        if displayView.isHidden {
            metalView.clear()
        } else {
            displayView.displayLayer.flushAndRemoveImage()
        }
    }

    /// ⚑[tool=export_trie_oracle ref=MetalPlayView.didStartPIP(to:):0x101a6305c result=18-instr]
    ///   · `bl 0x103463f40` is an ObjC send whose selref 0x10440bd98 decodes to **`isHidden`**;
    ///     `tbnz w0,#0` skips the call when it is true, hence the negation.
    ///     ⚑[tool=decode_objc_selector ref=0x10440bd98 result='isHidden']
    ///   · `bl 0x1019f245c` is `UIView.addSub(view:)` (UXKit.swift, reconstructed alongside this).
    ///     The registers fix the direction: swiftself is the incoming `to:` view and the argument
    ///     is the field, so the field is added INTO `view`.
    ///
    /// ⚑ The receiver is `metalView`, and the anchor is BINARY-INTERNAL. Its offset global
    ///   0x1044ea8a0 has no `vpWvd`, so the name cannot be read directly. `init(options:)`
    ///   @0x101a5f098 loads this same global, sends `layer` (selref 0x10440bf70) and casts the
    ///   result to `CAMetalLayer` — the conformance witness 0x1041d9e70 is
    ///   `$sSo12CAMetalLayerC8KSPlayer8DrawableACWP`. Only `MetalView` has
    ///   `layerClass = CAMetalLayer.self` (line 321); `AVSampleBufferDisplayView` declares
    ///   `AVSampleBufferDisplayLayer` (line 395). So 0x1044ea8a0 is `metalView`.
    /// ⚑ An EARLIER version of this comment named it `displayView`, cross-referenced from
    ///   `flush()`'s SOURCE. That was wrong: `flush()` is itself mis-reconstructed against the
    ///   binary (its else-branch reads `drawable` @0x8d0, which no `displayLayer` access explains),
    ///   so anchoring on it anchored on an unverified body. Anchor on binary facts — a witness
    ///   table, a `vpWvd`, a decoded selector — never on reconstructed source.
    /// ⚑ Do NOT extrapolate from the neighbouring `vpWvd` globals (0x1044ea8b0 rotation · 8b8
    ///   pixelBuffer · 8c0 options · 8c8 renderSource · 8d0 drawable): they are contiguous at
    ///   stride 8, but extending that run backward gives 0x8a0 → `formatDescription`, which cannot
    ///   answer `isHidden`. The global array is not index-ordered across this class.
    public func didStartPIP(to view: UIView) {
        if !metalView.isHidden {
            view.addSub(view: metalView)
        }
    }

    /// ⚑[tool=export_trie_oracle ref=MetalPlayView.didStopPIP():0x101a5e2d8 result=20-instr]
    /// Shares `didStartPIP`'s guard exactly — the same `isHidden` send on the same global
    /// 0x1044ea8a0 (`metalView`, see above), with `tbz w0,#0` branching to the work when the
    /// bit is CLEAR, i.e. when it is not hidden.
    ///
    /// The direction of the re-parent is the mirror of `didStartPIP` and is read from the
    /// registers, not assumed: here `bl 0x1019f245c` leaves swiftself as **self** and passes
    /// `metalView` as the argument, so the view comes BACK into this one.
    ///   · `bl 0x10345ece0` → selref 0x10440a900 = **`bounds`**, sent to `self`.
    ///   · the tail `b 0x103469bc0` → selref 0x10440d4b8 = **`setFrame:`**, sent to `displayView`
    ///     with that rect still live in the FP registers — i.e. `metalView.frame = bounds`.
    /// ⚑[tool=decode_objc_selector ref=0x10440a900 result='bounds']
    /// ⚑[tool=decode_objc_selector ref=0x10440d4b8 result='setFrame:']
    public func didStopPIP() {
        if !metalView.isHidden {
            addSub(view: metalView)
            metalView.frame = bounds
        }
    }

    public func invalidate() {
        displayLink?.invalidate()
    }

    public func readNextFrame() {
        draw(force: true)
    }

//    deinit {
//        print()
//    }
}

extension MetalPlayView {
    @objc private func renderFrame() {
        draw(force: false)
    }

    private func draw(force: Bool) {
        autoreleasepool {
            guard let frame = renderSource?.getVideoOutputRender(force: force) else {
                return
            }
            pixelBuffer = frame.pixelBuffer
            guard let pixelBuffer else {
                return
            }
            isDovi = frame.isDovi
            fps = frame.fps
            let cmtime = frame.cmtime
            let par = pixelBuffer.size
            let sar = pixelBuffer.aspectRatio
            // The two arguments come from the binary's own signature. `isHDRScreen` is the static
            // KSOptions.isHDRScreen, which is Optional there; the `?? false` coalesce at this call
            // site is OURS — the default is not read from the caller.
            if let pixelBuffer = pixelBuffer.cvPixelBuffer,
               options.isUseDisplayLayer(frame: frame, isHDRScreen: KSOptions.isHDRScreen ?? false) {
                if displayView.isHidden {
                    displayView.isHidden = false
                    metalView.isHidden = true
                    metalView.clear()
                }
                if let dar = options.customizeDar(sar: sar, par: par) {
                    pixelBuffer.aspectRatio = CGSize(width: dar.width, height: dar.height * par.width / par.height)
                }
                checkFormatDescription(pixelBuffer: pixelBuffer)
                set(pixelBuffer: pixelBuffer, time: cmtime)
            } else {
                if !displayView.isHidden {
                    displayView.isHidden = true
                    metalView.isHidden = false
                    displayView.displayLayer.flushAndRemoveImage()
                }
                let size: CGSize
                if !options.display.isSphere {
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
                metalView.draw(frame: frame, display: options.display, size: size)
            }
            renderSource?.setVideo(time: cmtime, position: frame.position)
        }
    }

    private func checkFormatDescription(pixelBuffer: PixelBufferProtocol) {
        if formatDescription == nil || !pixelBuffer.matche(formatDescription: formatDescription!) {
            if formatDescription != nil {
                displayView.removeFromSuperview()
                displayView = AVSampleBufferDisplayView()
                displayView.frame = frame
                addSubview(displayView)
            }
            formatDescription = pixelBuffer.formatDescription
        }
    }

    private func set(pixelBuffer: CVPixelBuffer, time: CMTime) {
        guard let formatDescription else { return }
        displayView.enqueue(imageBuffer: pixelBuffer, formatDescription: formatDescription, time: time)
    }
}

class MetalView: UIView {
    // NO STORED PROPERTIES. MetalView's binary field descriptor reports NumFields=0, so the
    // `private let render = MetalRender()` that used to sit here is a field the binary does not
    // have. It is not needed either: the render entry point is an extension on
    // MTLRenderCommandEncoder and everything else MetalRender exposes is static.
    #if canImport(UIKit)
    override public class var layerClass: AnyClass { CAMetalLayer.self }
    #endif
    public var metalLayer: CAMetalLayer {
        // swiftlint:disable force_cast
        layer as! CAMetalLayer
        // swiftlint:enable force_cast
    }

    init() {
        super.init(frame: .zero)
        #if !canImport(UIKit)
        layer = CAMetalLayer()
        #endif
        metalLayer.device = MetalRender.device
        metalLayer.framebufferOnly = true
//        metalLayer.displaySyncEnabled = false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func clear() {
        if let drawable = metalLayer.nextDrawable() {
            MetalRender.clear(drawable: drawable)
        }
    }

    // Carries the FRAME rather than the pixel buffer, because DisplayEnum's requirement is
    // set(frame:encoder:). Every caller already had a frame in scope.
    func draw(frame: VideoVTBFrame, display: any DisplayEnum, size: CGSize) {
        // No unwrap: VideoVTBFrame.pixelBuffer is a non-optional `let` in the source now too, so
        // this matches the binary, which loads the field with no nil check.
        let pixelBuffer = frame.pixelBuffer
        metalLayer.drawableSize = size
        metalLayer.pixelFormat = KSOptions.colorPixelFormat(bitDepth: pixelBuffer.bitDepth)
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
        guard let drawable = metalLayer.nextDrawable() else {
            KSLog("[video] CAMetalLayer not readyForMoreMediaData")
            return
        }
        MetalRender.renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        guard let commandBuffer = MetalRender.commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: MetalRender.renderPassDescriptor)
        else {
            return
        }
        encoder.draw(frame: frame, display: display)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

class AVSampleBufferDisplayView: UIView {
    #if canImport(UIKit)
    override public class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    #endif
    var displayLayer: AVSampleBufferDisplayLayer {
        // swiftlint:disable force_cast
        layer as! AVSampleBufferDisplayLayer
        // swiftlint:enable force_cast
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        #if !canImport(UIKit)
        layer = AVSampleBufferDisplayLayer()
        #endif
        var controlTimebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &controlTimebase)
        if let controlTimebase {
            displayLayer.controlTimebase = controlTimebase
            CMTimebaseSetTime(controlTimebase, time: .zero)
            CMTimebaseSetRate(controlTimebase, rate: 1.0)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func enqueue(imageBuffer: CVPixelBuffer, formatDescription: CMVideoFormatDescription, time: CMTime) {
        let timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        //        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: imageBuffer, formatDescription: formatDescription, sampleTiming: [timing], sampleBufferOut: &sampleBuffer)
        if let sampleBuffer {
            if let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) as? [NSMutableDictionary], let dic = attachmentsArray.first {
                dic[kCMSampleAttachmentKey_DisplayImmediately] = true
            }
            if displayLayer.isReadyForMoreMediaData {
                displayLayer.enqueue(sampleBuffer)
            } else {
                KSLog("[video] AVSampleBufferDisplayLayer not readyForMoreMediaData. video time \(time), controlTime \(displayLayer.timebase.time) ")
                displayLayer.enqueue(sampleBuffer)
            }
            if #available(macOS 11.0, iOS 14, tvOS 14, *) {
                if displayLayer.requiresFlushToResumeDecoding {
                    KSLog("[video] AVSampleBufferDisplayLayer requiresFlushToResumeDecoding so flush")
                    displayLayer.flush()
                }
            }
            if displayLayer.status == .failed {
                KSLog("[video] AVSampleBufferDisplayLayer status failed so flush")
                displayLayer.flush()
                //                    if let error = displayLayer.error as NSError?, error.code == -11847 {
                //                        displayLayer.stopRequestingMediaData()
                //                    }
            }
        }
    }
}

#if os(macOS)
import CoreVideo

class CADisplayLink {
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
