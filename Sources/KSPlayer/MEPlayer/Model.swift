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

final class SubtitleFrame: MEFrame {
    var timestamp: Int64 = 0
    var timebase: Timebase
    var duration: Int64 = 0
    var position: Int64 = 0
    var size: Int32 = 0
    let part: SubtitlePart
    init(part: SubtitlePart, timebase: Timebase) {
        self.part = part
        self.timebase = timebase
    }
}

public final class AudioFrame: MEFrame {
    // MARK: - Stored fields (RE: AudioFrame, verified offsets from
    // Forward v1.3.15 — see `.reversal/AudioPipeline.md`).
    //
    //   +0x10 (UInt32)  numberOfSamples / sampleCount
    //   +0x18 (ptr)     audioFormat
    //   +0x20 (4+4)     timebase (value + timescale)
    //   +0x28 (Int64)   timestamp (presentation pts)
    //   +0x30 (Int64)   duration
    //   +0x38 (Int64)   position (stream byte position from MEFrame)
    //   +0x40 (ptr)     data (buffer array)
    //   +0x48 (UInt32)  linesize / dataSize per buffer
    //   +0x4c (UInt32)  bytesPerFrame (the binary calls it `sampleSize`)
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
        sampleSize = UInt32(audioFormat.sampleSize)
        let count = audioFormat.isInterleaved ? 1 : audioFormat.channelCount
        data = (0 ..< count).map { _ in
            UnsafeMutablePointer<UInt8>.allocate(capacity: dataSize)
        }
    }

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
        let sampleSizeInt = Int(audioFormat.sampleSize)
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
    var leftShift: UInt8 { 0 }
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
    func matche(formatDescription _: CMVideoFormatDescription) -> Bool { false }
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

public struct EDRMetaData {
    var displayData: MasteringDisplayMetadata?
    var contentData: ContentLightMetadata?
    var ambientViewingEnvironment: AmbientViewingEnvironment?
    /// HDR Vivid presence flag — set when `AV_FRAME_DATA_DYNAMIC_HDR_VIVID`
    /// (binary side-data type `0x19`) was observed on the source frame.
    var isVIVID: Bool = false
}

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

public struct ContentLightMetadata {
    let MaxCLL: UInt16
    let MaxFALL: UInt16
}

// https://developer.apple.com/documentation/technotes/tn3145-hdr-video-metadata
public struct AmbientViewingEnvironment {
    let ambient_illuminance: UInt32
    let ambient_light_x: UInt16
    let ambient_light_y: UInt16
}
