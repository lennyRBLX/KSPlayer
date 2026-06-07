//
//  Model.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/9.
//

import AVFoundation
import CoreMedia
import Libavcodec
#if canImport(UIKit)
import UIKit
#endif

// MARK: enum

enum MESourceState {
    case idle
    case opening
    case opened
    case reading
    case seeking
    case paused
    case finished
    case closed
    case failed
}

// MARK: delegate

public protocol OutputRenderSourceDelegate: AnyObject {
    func getVideoOutputRender(force: Bool) -> VideoVTBFrame?
    func getAudioOutputRender() -> AudioFrame?
    func setAudio(time: CMTime, position: Int64)
    func setVideo(time: CMTime, position: Int64)
}

protocol CodecCapacityDelegate: AnyObject {
    func codecDidFinished(track: some CapacityProtocol)
}

protocol MEPlayerDelegate: AnyObject {
    func sourceDidChange(loadingState: LoadingState)
    func sourceDidOpened()
    func sourceDidFailed(error: NSError?)
    func sourceDidFinished()
    func sourceDidChange(oldBitRate: Int64, newBitrate: Int64)
}

// MARK: protocol

public protocol ObjectQueueItem {
    var timebase: Timebase { get }
    var timestamp: Int64 { get set }
    var duration: Int64 { get set }
    // byte position
    var position: Int64 { get set }
    var size: Int32 { get set }
}

extension ObjectQueueItem {
    var seconds: TimeInterval { cmtime.seconds }
    var cmtime: CMTime { timebase.cmtime(for: timestamp) }
}

public protocol FrameOutput: AnyObject {
    var renderSource: OutputRenderSourceDelegate? { get set }
    func pause()
    func flush()
    func play()
}

protocol MEFrame: ObjectQueueItem {
    var timebase: Timebase { get set }
}

// MARK: model

// for MEPlayer
public extension KSOptions {
    /// 开启VR模式的陀飞轮
    static var enableSensor = true
    static var stackSize = 65536
    static var isClearVideoWhereReplace = true
    /// Matches Forward v1.3.15 binary default. The Play app's
    /// `PlayerPreferences.makeOptions()` overrides this per `audioEngineType` selection.
    static var audioPlayerType: AudioOutput.Type = AudioEnginePlayer.self
    static var videoPlayerType: (VideoOutput & UIView).Type = MetalPlayView.self
    /// RE: Binary default is 1 (send_field, doubling frame rate)
    static var yadifMode = 1
    static var deInterlaceAddIdet = false
    static func colorSpace(ycbcrMatrix: CFString?, transferFunction: CFString?) -> CGColorSpace? {
        switch ycbcrMatrix {
        case kCVImageBufferYCbCrMatrix_ITU_R_709_2:
            return CGColorSpace(name: CGColorSpace.itur_709)
        case kCVImageBufferYCbCrMatrix_ITU_R_601_4:
            return CGColorSpace(name: CGColorSpace.sRGB)
        case kCVImageBufferYCbCrMatrix_ITU_R_2020:
            if transferFunction == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ {
                if #available(macOS 11.0, iOS 14.0, tvOS 14.0, *) {
                    return CGColorSpace(name: CGColorSpace.itur_2100_PQ)
                } else if #available(macOS 10.15.4, iOS 13.4, tvOS 13.4, *) {
                    return CGColorSpace(name: CGColorSpace.itur_2020_PQ)
                } else {
                    return CGColorSpace(name: CGColorSpace.itur_2020_PQ_EOTF)
                }
            } else if transferFunction == kCVImageBufferTransferFunction_ITU_R_2100_HLG {
                if #available(macOS 11.0, iOS 14.0, tvOS 14.0, *) {
                    return CGColorSpace(name: CGColorSpace.itur_2100_HLG)
                } else {
                    return CGColorSpace(name: CGColorSpace.itur_2020)
                }
            } else {
                return CGColorSpace(name: CGColorSpace.itur_2020)
            }
        default:
            return CGColorSpace(name: CGColorSpace.sRGB)
        }
    }

    static func colorSpace(colorPrimaries: CFString?) -> CGColorSpace? {
        switch colorPrimaries {
        case kCVImageBufferColorPrimaries_ITU_R_709_2:
            return CGColorSpace(name: CGColorSpace.sRGB)
        case kCVImageBufferColorPrimaries_DCI_P3:
            if #available(macOS 10.15.4, iOS 13.4, tvOS 13.4, *) {
                return CGColorSpace(name: CGColorSpace.displayP3_PQ)
            } else {
                return CGColorSpace(name: CGColorSpace.displayP3_PQ_EOTF)
            }
        case kCVImageBufferColorPrimaries_ITU_R_2020:
            if #available(macOS 11.0, iOS 14.0, tvOS 14.0, *) {
                return CGColorSpace(name: CGColorSpace.itur_2100_PQ)
            } else if #available(macOS 10.15.4, iOS 13.4, tvOS 13.4, *) {
                return CGColorSpace(name: CGColorSpace.itur_2020_PQ)
            } else {
                return CGColorSpace(name: CGColorSpace.itur_2020_PQ_EOTF)
            }
        default:
            return CGColorSpace(name: CGColorSpace.sRGB)
        }
    }

    static func pixelFormat(planeCount: Int, bitDepth: Int32) -> [MTLPixelFormat] {
        if planeCount == 3 {
            if bitDepth > 8 {
                return [.r16Unorm, .r16Unorm, .r16Unorm]
            } else {
                return [.r8Unorm, .r8Unorm, .r8Unorm]
            }
        } else if planeCount == 2 {
            if bitDepth > 8 {
                return [.r16Unorm, .rg16Unorm]
            } else {
                return [.r8Unorm, .rg8Unorm]
            }
        } else {
            return [colorPixelFormat(bitDepth: bitDepth)]
        }
    }

    static func colorPixelFormat(bitDepth: Int32) -> MTLPixelFormat {
        // Per `.reversal/DolbyVision.md §"Three-Tier Pipeline State Selection / Tier 2
        // lazy pipelines"`: the binary's DV pipeline states are built with the extended-
        // range 10-bit format `bgra10_xr`. `bgr10a2Unorm` clamps to `[0,1]`, which clips
        // PQ peak-brightness samples; `bgra10_xr` supports values outside `[0,1]` and is
        // the format the shared pipeline initialiser `FUN_101469418` passes when wiring
        // up `DAT_104458f78` (ICtCp) and `DAT_104458f80` (BiPlanar).
        if bitDepth == 10 {
            return .bgra10_xr
        } else {
            return .bgra8Unorm
        }
    }
}

enum MECodecState {
    case idle
    case decoding
    case flush
    case closed
    case failed
    case finished
}

public struct Timebase {
    static let defaultValue = Timebase(num: 1, den: 1)
    public let num: Int32
    public let den: Int32
    func getPosition(from seconds: TimeInterval) -> Int64 { Int64(seconds * TimeInterval(den) / TimeInterval(num)) }

    func cmtime(for timestamp: Int64) -> CMTime { CMTime(value: timestamp * Int64(num), timescale: den) }
}

extension Timebase {
    public var rational: AVRational { AVRational(num: num, den: den) }

    init(_ rational: AVRational) {
        num = rational.num
        den = rational.den
    }
}

/// RE: Packet (7 fields per types.json). Constructor not individually addressed
/// in TrackDecode.md; Packet_wrapAndDeliver at 0x1013fec8c is TranscodeIO scope.
final class Packet: ObjectQueueItem {
    // MARK: - Stored fields (RE: Packet, 7 fields per types.json)
    var duration: Int64 = 0
    var timestamp: Int64 = 0
    var position: Int64 = 0
    var size: Int32 = 0
    private(set) var corePacket = av_packet_alloc()
    /// Forward field; flush-marker discriminator. When true, `corePacket == nil`
    /// and the packet is injected by the seek path to signal decoders to flush.
    var isFlush: Bool = false

    // MARK: - Computed accessors (not stored on the binary's Packet)
    var timebase: Timebase {
        assetTrack.timebase
    }

    var isKeyFrame: Bool {
        if let corePacket {
            return corePacket.pointee.flags & AV_PKT_FLAG_KEY == AV_PKT_FLAG_KEY
        } else {
            return false
        }
    }

    var assetTrack: FFmpegAssetTrack! {
        didSet {
            guard let packet = corePacket?.pointee else {
                return
            }
            timestamp = packet.pts == Int64.min ? packet.dts : packet.pts
            position = packet.pos
            duration = packet.duration
            size = packet.size
        }
    }

    deinit {
        av_packet_unref(corePacket)
        av_packet_free(&corePacket)
    }
}

/// RE: allocAndInit at 0x10144a314, initWithReshapeBuffer at 0x10144a244
/// Object allocation size: 0xC40 bytes (alignment 0xF), confirmed by
/// `swift_allocObject(0xc40, 0xf)` in allocAndInit.
final class SubtitleFrame: MEFrame {
    var timestamp: Int64 = 0
    var timebase: Timebase
    var duration: Int64 = 0
    var position: Int64 = 0
    var size: Int32 = 0
    let part: SubtitlePart

    /// RE: 0x10144a244 (initWithReshapeBuffer, 208 B, 1.3.15)
    /// Real initialiser. Zeroes fields at +0x28..+0x74, sets +0x78=0x200 sentinel,
    /// memcpys 0xBC0-byte line-data template into +0x80, stores codec params at
    /// +0x18/+0x20/+0x40/+0x7a/+0x7b.
    /// In the Swift reconstruction, we preserve the interface: codec params arrive
    /// via SubtitlePart, the reshape buffer state is implicit in the part's data.
    init(part: SubtitlePart, timebase: Timebase) {
        self.part = part
        self.timebase = timebase
    }

    /// RE: 0x101447974 (parseAndExtractSubtitles, 300 B, 1.3.15)
    /// Parses raw subtitle content. Calls per-segment byte extractor
    /// (FUN_101449660 x8, FUN_101449744 x2), dispatches through AssImageParse
    /// witness table parseContent, returns array slice.
    /// Sole caller: MetalPlayView_renderFrameImpl at 0x10144529c.
    func parseAndExtractSubtitles(using parser: KSParseProtocol) -> [SubtitlePart] {
        let scanner = Scanner(string: part.text?.string ?? "")
        var results = [SubtitlePart]()
        while !scanner.isAtEnd {
            if let parsed = parser.parsePart(scanner: scanner) {
                results.append(parsed)
            }
        }
        return results
    }

    /// RE: 0x10144a7fc (adjustTimestamps, 244 B, 1.3.15)
    /// Subtracts per-stream delay from self.timestamp (+0x08) and self.duration (+0x10).
    /// Delay looked up from transcodeMap via FUN_1013a7944. Traps on signed overflow.
    /// Sole caller: FUN_10144a964 (closure wrapper).
    func adjustTimestamps(delay: Int64) {
        let (adjustedTimestamp, tsOverflow) = timestamp.subtractingReportingOverflow(delay)
        guard !tsOverflow else {
            fatalError("SubtitleFrame.adjustTimestamps: timestamp overflow subtracting delay \(delay) from \(timestamp)")
        }
        timestamp = adjustedTimestamp

        let (adjustedDuration, durOverflow) = duration.subtractingReportingOverflow(delay)
        guard !durOverflow else {
            fatalError("SubtitleFrame.adjustTimestamps: duration overflow subtracting delay \(delay) from \(duration)")
        }
        duration = adjustedDuration
    }

    /// RE: 0x10144a168 (createCodecState, 172 B, 1.3.15)
    /// Creates codec state. Dispatches on param_1: 2 = type-A static object,
    /// 3 = type-B static object, else = allocates general object with width
    /// (0x5E if param_2==10, else 0x50) at +0x20.
    /// Callers: configureVideoColorSpace at 0x10146eb24, FUN_10146b76c,
    /// thunk 0x101447a8c.
    static func createCodecState(type: Int, param: Int = 0) -> Int {
        switch type {
        case 2:
            // Type-A static object
            return 2
        case 3:
            // Type-B static object
            return 3
        default:
            // General object: width is 0x5E (94) if param==10, else 0x50 (80)
            return param == 10 ? 0x5E : 0x50
        }
    }

    /// RE: 0x10144791c (assertDataNotNil, 60 B, 1.3.15)
    /// Runtime assertion. Reads self+0x40, traps if nil, returns *(self+0x40)+0xC0.
    /// VWT-referenced only.
    func assertDataNotNil() -> Int {
        guard part.text != nil else {
            fatalError("SubtitleFrame.assertDataNotNil: data at +0x40 is nil")
        }
        // Returns offset 0xC0 (192) from the data pointer — in the binary this is
        // a stride into the reshape buffer. Return the buffer width sentinel.
        return 0xC0
    }

    /// RE: 0x101447814 (deinitBuffers, 252 B, 1.3.15)
    /// Cleanup function. Calls VWT destroy on buffer, converts CMTime to seconds,
    /// computes scaled duration, subtracts from timestamp pointer. Traps on
    /// overflow/NaN/Int64-range.
    /// Sole caller: FUN_101407090 (FFmpegDecode region).
    func deinitBuffers() {
        // Convert CMTime to seconds, compute scaled duration
        let seconds = timebase.cmtime(for: timestamp).seconds
        guard !seconds.isNaN, !seconds.isInfinite else {
            fatalError("SubtitleFrame.deinitBuffers: CMTime seconds is NaN or Inf")
        }
        let scaledDuration = timebase.cmtime(for: duration).seconds
        guard !scaledDuration.isNaN, !scaledDuration.isInfinite else {
            fatalError("SubtitleFrame.deinitBuffers: scaled duration is NaN or Inf")
        }
        // In the binary, this subtracts scaled duration from the timestamp pointer
        // and destroys the buffer via VWT. In the Swift reconstruction, the buffer
        // lifecycle is managed by ARC on SubtitlePart.
    }

    /// RE: 0x101448194 (set_data, 100 B, 1.3.15)
    /// Validates data dimensions: checks non-negative count at +0x10, reads buffer
    /// width from *(self+0x40)+0x10, verifies product is exact. Traps on negative
    /// count or overflow. VWT-referenced only.
    func validateData(count: Int, width: Int) -> Bool {
        guard count >= 0 else {
            fatalError("SubtitleFrame.validateData: negative count \(count)")
        }
        let (product, overflow) = count.multipliedReportingOverflow(by: width)
        guard !overflow else {
            fatalError("SubtitleFrame.validateData: overflow computing \(count) * \(width)")
        }
        _ = product
        return true
    }

    /// RE: 0x101447aa4 (releaseHelper, 20 B, 1.3.15)
    /// Constructs CMTime(value:timescale:) from packed Int64 parameter.
    static func releaseHelper(packed: Int64) -> CMTime {
        let timescale = Int32(truncatingIfNeeded: packed >> 32)
        let value = CMTimeValue(Int32(truncatingIfNeeded: packed))
        return CMTime(value: value, timescale: timescale)
    }

    /// RE: 0x101447808 (releaseRef, 12 B, 1.3.15)
    /// Packs two 32-bit halves into one 64-bit return value.
    static func releaseRef(high: Int32, low: Int32) -> Int64 {
        (Int64(high) << 32) | Int64(UInt32(bitPattern: low))
    }

    /// RE: 0x10144a634 (releaseOptional, 44 B, 1.3.15)
    /// Conditional objc_release: checks Optional discriminator bit (0x100 mask),
    /// releases the payload if .some.
    static func releaseOptional(_ object: AnyObject?) {
        // In the binary, this manually checks the Optional discriminator and
        // calls objc_release. In Swift reconstruction, ARC handles this
        // automatically. The function exists as a VWT entry point.
        _ = object // ARC release on scope exit
    }
}

public final class AudioFrame: MEFrame {
    // MARK: - Stored fields (RE: AudioFrame, verified offsets from
    // v1.3.15 — see `.reversal/AudioPipeline.md` lines 2726-2746).
    // Offsets verified against `AudioFrame_mergeFramesFromArray` (0x101449c04)
    // and `AudioFrame_createCMSampleBuffer` (0x10144726c).
    //
    //   +0x10 (UInt32)  dataSize — total BYTES per buffer (swift_slowAlloc
    //                   size + memcpy length; createCMSampleBuffer byte cap)
    //   +0x18 (ptr)     audioFormat
    //   +0x20 (4+4)     timebase (KSPlayer.Timebase = {num: Int32, den: Int32};
    //                   merge writes 0x100000001 = num=1, den=1)
    //   +0x28 (Int64)   timestamp (presentation pts)
    //   +0x30 (Int64)   duration
    //   +0x38 (Int64)   position (stream byte position from MEFrame)
    //   +0x40 (ptr)     data (buffer array)
    //   +0x48 (UInt32)  numberOfSamples — PCM sample count (passed as the
    //                   sampleCount arg to CMSampleBufferCreateReady)
    //   +0x4c (UInt32)  sampleSize — bytes per sample-frame (stored once by
    //                   initBuffers from bytesPerFrame; read at +0x48 * +0x4c)
    public let dataSize: UInt32
    public let audioFormat: AVAudioFormat
    public internal(set) var timebase = Timebase.defaultValue
    public var timestamp: Int64 = 0
    public var duration: Int64 = 0
    public var position: Int64 = 0
    public var data: [UnsafeMutablePointer<UInt8>?]
    public var numberOfSamples: UInt32 = 0
    /// Per-sample byte size, stored at Forward `+0x4c`.
    ///
    /// Verified via `AudioFrame_initBuffers` (`0x10144834c`) which calls
    /// `AudioFrame_bytesPerFrame` (`0x1014484b4`) once and caches the result
    /// at `+0x4c`. The merge function at `0x101449c04` and
    /// `AudioFrame_createCMSampleBuffer` (`0x10144726c`) read the cached slot
    /// rather than recomputing.
    public var sampleSize: UInt32 = 0

    // MARK: - ObjectQueueItem.size (computed, not stored)
    /// `size` is required by `ObjectQueueItem` but the binary does not store
    /// it on `AudioFrame` — derive it from the sample size and sample count
    /// instead so the protocol is satisfied without adding a 10th field.
    public var size: Int32 {
        get { Int32(clamping: UInt64(sampleSize) * UInt64(numberOfSamples)) }
        set {
            // Allow protocol-driven writes to be a no-op recompute hint;
            // accumulators in `init(array:)` track raw bytes via sampleSize.
            _ = newValue
        }
    }

    public init(dataSize: Int, audioFormat: AVAudioFormat) {
        self.dataSize = UInt32(clamping: dataSize)
        self.audioFormat = audioFormat
        sampleSize = AudioFrame.bytesPerFrame(for: audioFormat)
        let count = audioFormat.isInterleaved ? 1 : audioFormat.channelCount
        data = (0 ..< count).map { _ in
            UnsafeMutablePointer<UInt8>.allocate(capacity: dataSize)
        }
    }

    /// RE: 0x10144834c (initBuffers, 360 B, 1.3.15)
    /// Allocates per-channel buffer array; calls `bytesPerFrame`, queries
    /// `channelCount` / `isInterleaved`. Can be called independently to
    /// (re)allocate buffers, separate from the initializer.
    func initBuffers(dataSize: Int) {
        // Deallocate any existing buffers
        for i in 0 ..< data.count {
            data[i]?.deinitialize(count: Int(self.dataSize))
            data[i]?.deallocate()
        }
        // Recompute sampleSize from audioFormat
        sampleSize = AudioFrame.bytesPerFrame(for: audioFormat)
        // Allocate per-channel buffers
        let channelCount = audioFormat.isInterleaved ? 1 : Int(audioFormat.channelCount)
        data = (0 ..< channelCount).map { _ in
            UnsafeMutablePointer<UInt8>.allocate(capacity: dataSize)
        }
    }

    /// RE: 0x1014484b4 (bytesPerFrame, 348 B, 1.3.15)
    /// Computes bytes-per-frame from `commonFormat`:
    ///   0 (pcmFormatFloat32) = 4 * channelCount (interleaved) or 4
    ///   1 (pcmFormatFloat64) = 8 (non-interleaved) or 8 * channelCount
    ///   2 (pcmFormatInt16)   = 2 * channelCount (interleaved) or 2
    ///   3 (pcmFormatInt32)   = 4 * channelCount (interleaved) or 4
    /// Thunk at 0x10144902c tail-calls this function.
    static func bytesPerFrame(for format: AVAudioFormat) -> UInt32 {
        let ch = format.channelCount
        switch format.commonFormat {
        case .pcmFormatFloat32:
            return format.isInterleaved ? ch * 4 : 4
        case .pcmFormatFloat64:
            return format.isInterleaved ? ch * 8 : 8
        case .pcmFormatInt16:
            return format.isInterleaved ? ch * 2 : 2
        case .pcmFormatInt32:
            return format.isInterleaved ? ch * 4 : 4
        case .otherFormat:
            return format.isInterleaved ? ch * 4 : 4
        @unknown default:
            return format.isInterleaved ? ch * 4 : 4
        }
    }

    // NOTE: 0x10144a970 was previously reconstructed here as
    // `AudioFrame.createFromVideoSwresample`. That was a Ghidra mislabel:
    // `.reversal/AudioPipeline.md` (function-table line 3018 + correction-log
    // line 3714) confirms 0x10144a970 is a VIDEO frame factory (memcpy 0x1a8 of
    // a 0xbc0-byte video payload, video conformance 0x103a26618, shares video
    // helper FUN_10144aea8 with the proven-video 0x10144aab0) that calls NO
    // CoreAudio. It belongs in DisplayMetal.md, not on AudioFrame, so the stale
    // factory is removed. CROSS-FILE NEEDED: the real 0x10144a970 video-frame
    // factory should be reconstructed in the Metal/video-frame cluster
    // (DisplayMetal.md), not here.

    /// RE: 0x101449c04 (mergeFramesFromArray, 1380 B, 1.3.15)
    /// Two-pass merge: copies audioFormat/timebase/timestamp/position/sampleSize
    /// from `array[0]`; sums dataSize(+0x10), duration(+0x30) and
    /// numberOfSamples(+0x48) across all frames; allocates `channelCount` planar
    /// output buffers (1 if interleaved) and memcpys each source frame's
    /// per-channel data into the contiguous output at +0x40.
    init(array: [AudioFrame]) {
        audioFormat = array[0].audioFormat
        timebase = array[0].timebase
        timestamp = array[0].timestamp
        position = array[0].position
        sampleSize = array[0].sampleSize
        var dataSize: UInt32 = 0
        for frame in array {
            duration += frame.duration
            dataSize &+= frame.dataSize
            numberOfSamples &+= frame.numberOfSamples
        }
        self.dataSize = dataSize
        let count = audioFormat.isInterleaved ? 1 : audioFormat.channelCount
        data = (0 ..< count).map { _ in
            UnsafeMutablePointer<UInt8>.allocate(capacity: Int(dataSize))
        }
        var offset = 0
        for frame in array {
            for i in 0 ..< data.count {
                data[i]?.advanced(by: offset).initialize(from: frame.data[i]!, count: Int(frame.dataSize))
            }
            offset += Int(frame.dataSize)
        }
    }

    deinit {
        for i in 0 ..< data.count {
            data[i]?.deinitialize(count: Int(dataSize))
            data[i]?.deallocate()
        }
        data.removeAll()
    }

    public func toFloat() -> [ContiguousArray<Float>] {
        var array = [ContiguousArray<Float>]()
        let dataSizeInt = Int(dataSize)
        for i in 0 ..< data.count {
            switch audioFormat.commonFormat {
            case .pcmFormatInt16:
                let capacity = dataSizeInt / MemoryLayout<Int16>.size
                data[i]?.withMemoryRebound(to: Int16.self, capacity: capacity) { src in
                    var des = ContiguousArray<Float>(repeating: 0, count: Int(capacity))
                    for j in 0 ..< capacity {
                        des[j] = max(-1.0, min(Float(src[j]) / 32767.0, 1.0))
                    }
                    array.append(des)
                }
            case .pcmFormatInt32:
                let capacity = dataSizeInt / MemoryLayout<Int32>.size
                data[i]?.withMemoryRebound(to: Int32.self, capacity: capacity) { src in
                    var des = ContiguousArray<Float>(repeating: 0, count: Int(capacity))
                    for j in 0 ..< capacity {
                        des[j] = max(-1.0, min(Float(src[j]) / 2_147_483_647.0, 1.0))
                    }
                    array.append(des)
                }
            default:
                let capacity = dataSizeInt / MemoryLayout<Float>.size
                data[i]?.withMemoryRebound(to: Float.self, capacity: capacity) { src in
                    var des = ContiguousArray<Float>(repeating: 0, count: Int(capacity))
                    for j in 0 ..< capacity {
                        des[j] = src[j]
                    }
                    array.append(ContiguousArray<Float>(des))
                }
            }
        }
        return array
    }

    public func toPCMBuffer() -> AVAudioPCMBuffer? {
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: numberOfSamples) else {
            return nil
        }
        pcmBuffer.frameLength = pcmBuffer.frameCapacity
        let dataSizeInt = Int(dataSize)
        for i in 0 ..< min(Int(pcmBuffer.format.channelCount), data.count) {
            switch audioFormat.commonFormat {
            case .pcmFormatInt16:
                let capacity = dataSizeInt / MemoryLayout<Int16>.size
                data[i]?.withMemoryRebound(to: Int16.self, capacity: capacity) { src in
                    pcmBuffer.int16ChannelData?[i].update(from: src, count: capacity)
                }
            case .pcmFormatInt32:
                let capacity = dataSizeInt / MemoryLayout<Int32>.size
                data[i]?.withMemoryRebound(to: Int32.self, capacity: capacity) { src in
                    pcmBuffer.int32ChannelData?[i].update(from: src, count: capacity)
                }
            default:
                let capacity = dataSizeInt / MemoryLayout<Float>.size
                data[i]?.withMemoryRebound(to: Float.self, capacity: capacity) { src in
                    pcmBuffer.floatChannelData?[i].update(from: src, count: capacity)
                }
            }
        }
        return pcmBuffer
    }

    public func toCMSampleBuffer() -> CMSampleBuffer? {
        var outBlockListBuffer: CMBlockBuffer?
        CMBlockBufferCreateEmpty(allocator: kCFAllocatorDefault, capacity: UInt32(data.count), flags: 0, blockBufferOut: &outBlockListBuffer)
        guard let outBlockListBuffer else {
            return nil
        }
        // RE: 0x10144726c reads the STORED sampleSize field (+0x4c), set once by
        // initBuffers from bytesPerFrame, and multiplies it by numberOfSamples
        // (+0x48) to derive the block-buffer byte size — it does NOT query
        // audioFormat.sampleSize live. For interleaved formats the two agree;
        // use the stored field to preserve binary behavior.
        let sampleSizeInt = Int(sampleSize)
        let sampleCount = CMItemCount(numberOfSamples)
        let dataByteSize = sampleCount * sampleSizeInt
        if dataByteSize > Int(dataSize) {
            assertionFailure("dataByteSize: \(dataByteSize),render.dataSize: \(dataSize)")
        }
        for i in 0 ..< data.count {
            var outBlockBuffer: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: dataByteSize,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: dataByteSize,
                flags: kCMBlockBufferAssureMemoryNowFlag,
                blockBufferOut: &outBlockBuffer
            )
            if let outBlockBuffer {
                CMBlockBufferReplaceDataBytes(
                    with: data[i]!,
                    blockBuffer: outBlockBuffer,
                    offsetIntoDestination: 0,
                    dataLength: dataByteSize
                )
                CMBlockBufferAppendBufferReference(
                    outBlockListBuffer,
                    targetBBuf: outBlockBuffer,
                    offsetToData: 0,
                    dataLength: CMBlockBufferGetDataLength(outBlockBuffer),
                    flags: 0
                )
            }
        }
        var sampleBuffer: CMSampleBuffer?
        // 因为sampleRate跟timescale没有对齐，所以导致杂音。所以要让duration为invalid
//        let duration = CMTime(value: CMTimeValue(sampleCount), timescale: CMTimeScale(audioFormat.sampleRate))
        let duration = CMTime.invalid
        let timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: cmtime, decodeTimeStamp: .invalid)
        let sampleSizeEntryCount: CMItemCount
        let sampleSizeArray: [Int]?
        if audioFormat.isInterleaved {
            sampleSizeEntryCount = 1
            sampleSizeArray = [sampleSizeInt]
        } else {
            sampleSizeEntryCount = 0
            sampleSizeArray = nil
        }
        CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: outBlockListBuffer, formatDescription: audioFormat.formatDescription, sampleCount: sampleCount, sampleTimingEntryCount: 1, sampleTimingArray: [timing], sampleSizeEntryCount: sampleSizeEntryCount, sampleSizeArray: sampleSizeArray, sampleBufferOut: &sampleBuffer)
        return sampleBuffer
    }
}

/// Per-frame Dolby Vision metadata extracted from AVFrame side data (RE/67).
/// RE: Forward v1.3.15 KSDOVIMetadata is a 176-byte copied/owned struct.
/// Stores copied pointee values instead of raw pointers to avoid dangling
/// references after AVFrame is freed.
public struct DOVIFrameMetadata {
    public let rpuData: Data?
    public let header: AVDOVIRpuDataHeader?
    public let mapping: AVDOVIDataMapping?
    public let color: AVDOVIColorMetadata?

    /// Initialize by copying values from FFmpeg pointers (safe after AVFrame freed)
    public init(rpuData: Data?,
                header: UnsafePointer<AVDOVIRpuDataHeader>?,
                mapping: UnsafePointer<AVDOVIDataMapping>?,
                color: UnsafePointer<AVDOVIColorMetadata>?) {
        self.rpuData = rpuData
        self.header = header?.pointee
        self.mapping = mapping?.pointee
        self.color = color?.pointee
    }
}

public final class VideoVTBFrame: MEFrame {
    // MARK: - Stored fields (RE: VideoVTBFrame, 12 fields per types.json)
    public var timebase = Timebase.defaultValue
    /// Decoded image data — non-Optional in the binary's `types.json` dump.
    /// Provide a sentinel placeholder for callers that have not yet supplied
    /// the buffer (e.g. transient construction in the FFmpeg decode path).
    var pixelBuffer: PixelBufferProtocol
    // 交叉视频的duration会不准，直接减半了
    public var duration: Int64 = 0
    public var position: Int64 = 0
    public var timestamp: Int64 = 0
    public let fps: Float
    public var size: Int32 = 0
    public var adjustBuffer: MTLBuffer?
    public var edrMetaData: EDRMetaData? = nil
    public var isKeyFrame: Bool = false
    public let isDovi: Bool
    /// Per-frame DV RPU + mapping data for Metal reshape shader.
    public var doviData: DOVIFrameMetadata?

    init(fps: Float, isDovi: Bool, pixelBuffer: PixelBufferProtocol = VideoVTBFrame.placeholderPixelBuffer) {
        self.fps = fps
        self.isDovi = isDovi
        self.pixelBuffer = pixelBuffer
    }

    /// Backwards-compatibility shim for sites that still expect an Optional.
    /// Mirrors the previous `corePixelBuffer` accessor while the underlying
    /// storage is non-Optional per the binary layout.
    var corePixelBuffer: PixelBufferProtocol? {
        get { pixelBuffer is PlaceholderPixelBuffer ? nil : pixelBuffer }
        set {
            if let newValue {
                pixelBuffer = newValue
            } else {
                pixelBuffer = VideoVTBFrame.placeholderPixelBuffer
            }
        }
    }

    fileprivate static let placeholderPixelBuffer: PixelBufferProtocol = PlaceholderPixelBuffer()
}

/// Sentinel `PixelBufferProtocol` used when a `VideoVTBFrame` is constructed
/// before its image data has been attached. The binary stores
/// `pixelBuffer: PixelBufferProtocol` as non-Optional, so source paths that
/// previously left it `nil` use this stand-in until the real buffer arrives.
private final class PlaceholderPixelBuffer: PixelBufferProtocol {
    var width: Int { 0 }
    var height: Int { 0 }
    var bitDepth: Int32 { 8 }
    var leftShift: Int32 { 0 }
    var planeCount: Int { 0 }
    var formatDescription: CMVideoFormatDescription? { nil }
    var aspectRatio: CGSize {
        get { CGSize(width: 1, height: 1) }
        set { _ = newValue }
    }
    var yCbCrMatrix: CFString? {
        get { nil }
        set { _ = newValue }
    }
    var colorPrimaries: CFString? {
        get { nil }
        set { _ = newValue }
    }
    var transferFunction: CFString? {
        get { nil }
        set { _ = newValue }
    }
    var colorspace: CGColorSpace? {
        get { nil }
        set { _ = newValue }
    }
    var cvPixelBuffer: CVPixelBuffer? { nil }
    var isFullRangeVideo: Bool { false }
    func cgImage() -> CGImage? { nil }
    func textures() -> [MTLTexture] { [] }
    func widthOfPlane(at _: Int) -> Int { 0 }
    func heightOfPlane(at _: Int) -> Int { 0 }
    func matches(formatDescription _: CMVideoFormatDescription) -> Bool { false }
}

extension VideoVTBFrame {
    #if !os(tvOS)
    @available(iOS 16, *)
    var edrMetadata: CAEDRMetadata? {
        if var contentData = edrMetaData?.contentData, var displayData = edrMetaData?.displayData {
            let data = Data(bytes: &displayData, count: MemoryLayout<MasteringDisplayMetadata>.stride)
            let data2 = Data(bytes: &contentData, count: MemoryLayout<ContentLightMetadata>.stride)
            return CAEDRMetadata.hdr10(displayInfo: data, contentInfo: data2, opticalOutputScale: 10000)
        }
        if var ambientViewingEnvironment = edrMetaData?.ambientViewingEnvironment {
            let data = Data(bytes: &ambientViewingEnvironment, count: MemoryLayout<AmbientViewingEnvironment>.stride)
            if #available(macOS 14.0, iOS 17.0, *) {
                return CAEDRMetadata.hlg(ambientViewingEnvironment: data)
            } else {
                return CAEDRMetadata.hlg
            }
        }
        if corePixelBuffer?.transferFunction == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ {
            return CAEDRMetadata.hdr10(minLuminance: 0.1, maxLuminance: 1000, opticalOutputScale: 10000)
        } else if corePixelBuffer?.transferFunction == kCVImageBufferTransferFunction_ITU_R_2100_HLG {
            return CAEDRMetadata.hlg
        }
        return nil
    }
    #endif
}

/// RE: Populated by MEPlayerItem_processFrameSideData at 0x101407908 (1.3.15).
/// Composite structure carrying all HDR metadata through the decode->render pipeline.
/// types.json `KSPlayer.EDRMetaData` has four fields.
public struct EDRMetaData {
    /// SMPTE ST 2086 mastering display metadata (AV_FRAME_DATA_MASTERING_DISPLAY_METADATA, Type 11).
    var displayData: MasteringDisplayMetadata?
    /// CTA-861.3 content light level info (AV_FRAME_DATA_CONTENT_LIGHT_LEVEL, Type 14).
    var contentData: ContentLightMetadata?
    /// Ambient viewing environment (AV_FRAME_DATA type 26).
    var ambientViewingEnvironment: AmbientViewingEnvironment?
    /// HDR Vivid presence flag — set when `AV_FRAME_DATA_DYNAMIC_HDR_VIVID`
    /// (binary side-data type `0x19` / type-25) was observed on the source frame.
    /// Flags Chinese HDR Vivid (CUVA) format; does NOT engage DoviDisplayModel reshape.
    var isVIVID: Bool = false
}

/// RE: SMPTE ST 2086 layout (10 fields). Extracted by MEPlayerItem_processFrameSideData
/// at 0x101407908 from AV_FRAME_DATA_MASTERING_DISPLAY_METADATA (Type 11).
public struct MasteringDisplayMetadata {
    let display_primaries_r_x: UInt16
    let display_primaries_r_y: UInt16
    let display_primaries_g_x: UInt16
    let display_primaries_g_y: UInt16
    let display_primaries_b_x: UInt16
    let display_primaries_b_y: UInt16
    let white_point_x: UInt16
    let white_point_y: UInt16
    let minLuminance: UInt32
    let maxLuminance: UInt32
}

/// RE: CTA-861.3 (2 fields). Extracted by MEPlayerItem_processFrameSideData
/// at 0x101407908 from AV_FRAME_DATA_CONTENT_LIGHT_LEVEL (Type 14).
public struct ContentLightMetadata {
    let MaxCLL: UInt16
    let MaxFALL: UInt16
}

/// RE: Ambient viewing environment (3 fields). Extracted by MEPlayerItem_processFrameSideData
/// at 0x101407908 from AV_FRAME_DATA type 26.
/// https://developer.apple.com/documentation/technotes/tn3145-hdr-video-metadata
public struct AmbientViewingEnvironment {
    let ambient_illuminance: UInt32
    let ambient_light_x: UInt16
    let ambient_light_y: UInt16
}
