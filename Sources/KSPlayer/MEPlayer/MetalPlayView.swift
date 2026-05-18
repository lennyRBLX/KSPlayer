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
    var displayLayerDelegate: DisplayLayerDelegate? { get set }
    var options: KSOptions { get set }
    var displayLayer: AVSampleBufferDisplayLayer { get }
    var pixelBuffer: PixelBufferProtocol? { get }
    init(options: KSOptions)
    func invalidate()
    func readNextFrame()
}

public final class MetalPlayView: UIView, VideoOutput {
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
                        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: preferredFramesPerSecond, maximum: 2 * preferredFramesPerSecond, __preferred: preferredFramesPerSecond)
                    } else {
                        displayLink.preferredFramesPerSecond = Int(preferredFramesPerSecond) << 1
                    }
                }
                options.updateVideo(refreshRate: fps, isDovi: isDovi, formatDescription: formatDescription)
            }
        }
    }

    public private(set) var pixelBuffer: PixelBufferProtocol?
    /// displayLink drives Metal path only. AVSBDL path uses requestMediaDataWhenReady.
    private var displayLink: CADisplayLink!
    public var options: KSOptions
    public weak var renderSource: OutputRenderSourceDelegate?
    var displayView = AVSampleBufferDisplayView() {
        didSet {
            displayLayerDelegate?.change(displayLayer: displayView.displayLayer)
        }
    }

    private let metalView = MetalView()
    public weak var displayLayerDelegate: DisplayLayerDelegate?
    public init(options: KSOptions) {
        self.options = options
        super.init(frame: .zero)
        addSubview(displayView)
        addSubview(metalView)
        metalView.isHidden = true
        displayLink = CADisplayLink(target: self, selector: #selector(renderFrame))
        displayLink.add(to: .main, forMode: .common)
        pause()
    }

    public func play() {
        if options.isUseDisplayLayer() {
            if displayView.isHidden {
                displayView.isHidden = false
                metalView.isHidden = true
                metalView.clear()
            }
            displayView.owner = self
            displayView.play(renderSource: renderSource)
        } else {
            displayLink.isPaused = false
        }
    }

    public func pause() {
        if options.isUseDisplayLayer() {
            displayView.pause()
        }
        displayLink.isPaused = true
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
        if options.display == .plane {
            super.touchesMoved(touches, with: with)
        } else {
            options.display.touchesMoved(touch: touches.first!)
        }
    }
    #else
    override public func touchesMoved(with event: NSEvent) {
        if options.display == .plane {
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
            displayView.flush(keepImage: true)
        }
    }

    public func flushAndRemoveImage() {
        pixelBuffer = nil
        if displayView.isHidden {
            metalView.clear()
        } else {
            displayView.flush(keepImage: false)
        }
    }

    public func invalidate() {
        displayView.stopRequestingData()
        displayLink.invalidate()
    }

    public func readNextFrame() {
        if options.isUseDisplayLayer() {
            displayView.readNextFrame(renderSource: renderSource, options: options, owner: self)
        } else {
            draw(force: true)
        }
    }

//    deinit {
//        print()
//    }
}

extension MetalPlayView {
    @objc private func renderFrame() {
        if options.isUseDisplayLayer() {
            return
        }
        draw(force: false)
    }

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
            // DV routing (RE: MEPlayerItem_processFrameSideData @ 0x101407908 + MetalPlayView_renderFrameImpl @ 0x10144529c)
            // Binary detects side data type 0x18 (DOVI_METADATA), converts to GPU metadata, routes to DoviDisplayModel.draw()
            var doviMetadata: DoviGPUMetadata?
            if isDovi, KSOptions.enhanceDolby,
               let doviData = frame.doviData,
               let header = doviData.header, let mapping = doviData.mapping {
                doviMetadata = DoviGPUMetadata.from(header: header, mapping: mapping, color: doviData.color)
            }
            metalView.draw(pixelBuffer: pixelBuffer, display: options.display, size: size, doviMetadata: doviMetadata)
            renderSource?.setVideo(time: cmtime, position: frame.position)
        }
    }

    private func checkFormatDescription(pixelBuffer: PixelBufferProtocol) {
        if formatDescription == nil || !pixelBuffer.matche(formatDescription: formatDescription!) {
            if formatDescription != nil {
                let wasPlaying = !displayLink.isPaused || displayView.isPlaying
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
        }
    }
}

class MetalView: UIView {
    private let render = MetalRender()
    #if canImport(UIKit)
    override public class var layerClass: AnyClass { CAMetalLayer.self }
    #endif
    var metalLayer: CAMetalLayer {
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
            render.clear(drawable: drawable)
        }
    }

    func draw(pixelBuffer: PixelBufferProtocol, display: DisplayEnum, size: CGSize,
              doviMetadata: DoviGPUMetadata? = nil) {
        metalLayer.drawableSize = size
        metalLayer.pixelFormat = KSOptions.colorPixelFormat(bitDepth: pixelBuffer.bitDepth)

        // DV path: force ITU-R 2100 PQ color space (RE: MetalPlayView_renderFrameImpl @ 0x10144529c)
        // Binary checks if display == doviSingleton → CGColorSpaceCreateWithName(kCGColorSpaceITUR_2100_PQ)
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

    private var controlTimebase: CMTimebase?
    private let requestQueue = DispatchQueue(label: "ks.player.avsbdl.queue")
    private weak var activeRenderSource: OutputRenderSourceDelegate?
    weak var owner: MetalPlayView?
    private(set) var isPlaying = false
    private var isRequestingData = false

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
