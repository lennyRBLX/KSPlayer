//
//  Model.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/9.
//

import AVFoundation
import CoreMedia
import DOVIRPUShim
import Libavcodec
import Metal
#if canImport(UIKit)
import UIKit
#endif

// MARK: enum

// Forward 1.3.17 renamed/reshaped base `MESourceState` into a type NESTED in MEPlayerItem
// (`MEPlayerItem.State`; field-38 `state: State`). Cases + discriminant order are FAITHFUL —
// decoded from the binary's nominal descriptor @0x1039ef8b0 (parent context = MEPlayerItem,
// NumPayloadCases=0, NumEmptyCases=10) and its __swift5_fieldmd case records (in order).
// Divergences from base MESourceState (9 cases): case-2 `opened`→`ready`; NEW `endOfStream`
// (raw 6) inserted, shifting `finished`/`closed`/`failed` to 7/8/9. The 8/9 adjacency is why
// MEPlayerItem's interrupt predicate compiles to `(state & 0xfe) == 8` (≡ .closed || .failed).
// ⚑[tool=fetch_reflection_fields ref=MEPlayerItem.State:0x1039ef8b0 result=enum/10-empty-cases]
extension MEPlayerItem {
    enum State {
        case idle        // 0
        case opening     // 1
        case ready       // 2  (base `opened`)
        case reading     // 3
        case seeking     // 4
        case paused      // 5
        case endOfStream // 6  (NEW in Forward)
        case finished    // 7
        case closed      // 8  ← interrupt terminal pair
        case failed      // 9  ← interrupt terminal pair
    }
}

// MARK: delegate

// Forward 1.3.17 SPLIT the render-source delegate into two protocols (audio / video); the binary has NO combined
// (search_strings: only `AudioOutputRenderSourceDelegate` @0x1039ef… + `VideoOutputRenderSourceDelegate` @0x1039efe1c,
// each 2 instance methods, `: AnyObject`). MEPlayerItem conforms BOTH (superclass_conformance-confirmed).
// getAudioOutputRender returns `Either<AudioFrame, Bool>`, NOT `AudioFrame?`: the witness returns TWO
//   registers (x0 = payload, x1 = tag), and x0's MEANING changes with the tag — an AudioFrame on tag 0,
//   a Bool on tag 1 — which no tuple spelling reproduces (a tuple's element positions are fixed).
//   `.left(frame)` = a frame is available; `.right(isEOF)` = no frame, plus whether the stream has ended.
//   Proven at THREE independent sites: MEPlayerItem's witness impl @0x101a59088 (returns 16 bytes),
//   AudioDataBuffer @0x101a123d0 (stores x0's low bit into its `eof` field on tag 1), and AudioBaseOutput
//   @0x101a12c70 (`csel x8,xzr,x23,eq` — keeps .left, discards .right's Bool; it has no eof field).
// ⚑[tool=disassemble ref=getAudioOutputRender_witness:0x101a59088 result=undefined1[16]=x0_payload+x1_tag]
public protocol AudioOutputRenderSourceDelegate: AnyObject {
    func getAudioOutputRender() -> Either<AudioFrame, Bool>
    func setAudio(time: CMTime, position: Int64)
}

public protocol VideoOutputRenderSourceDelegate: AnyObject {
    func getVideoOutputRender(force: Bool) -> VideoVTBFrame?
    func setVideo(time: CMTime, position: Int64)
}

// ⚑ BRIDGE (session 16b): the recon's combined `OutputRenderSourceDelegate` is kept as a refinement of the two REAL
//   protocols so the Phase-N render-output hierarchy (FrameOutput.renderSource, AudioOutput/VideoOutput, the 5 renderers'
//   renderSource fields) need not be retyped now — FrameOutput.renderSource couples the full retyping into a render-output
//   subsystem reconstruction (a follow-on). The binary has NO combined ⇒ this is a source-extra bridge (P51, not flagged).
public protocol OutputRenderSourceDelegate: AudioOutputRenderSourceDelegate, VideoOutputRenderSourceDelegate {}

protocol CodecCapacityDelegate: AnyObject {
    func codecDidFinished(track: some CapacityProtocol)
}

// ⚑ `public` is FORCED by type visibility: MEPlayerItem.delegate carries a property
//   descriptor, so its type must be public. Not separately observed — MEPlayerDelegate
//   has ZERO owner-position symbols in the export trie.
// ⚑[tool=export_trie_oracle ref=MEPlayerItem.delegate:vpMV result=public ⇒ MEPlayerDelegate public by the type-visibility rule]
public protocol MEPlayerDelegate: AnyObject {
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
    public var seconds: TimeInterval { cmtime.seconds }
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
    nonisolated(unsafe) static var enableSensor = true
    nonisolated(unsafe) static var stackSize = 65536
    nonisolated(unsafe) static var isClearVideoWhereReplace = true
    nonisolated(unsafe) static var audioPlayerType: AudioOutput.Type = AudioEnginePlayer.self
    nonisolated(unsafe) static var videoPlayerType: (VideoOutput & UIView).Type = MetalPlayView.self
    nonisolated(unsafe) static var yadifMode = 1
    nonisolated(unsafe) static var deInterlaceAddIdet = false
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
        if bitDepth == 10 {
            return .bgr10a2Unorm
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

public struct Timebase: Sendable {
    static let defaultValue = Timebase(num: 1, den: 1)
    public let num: Int32
    public let den: Int32
    func getPosition(from seconds: TimeInterval) -> Int64 { Int64(seconds * TimeInterval(den) / TimeInterval(num)) }

    package func cmtime(for timestamp: Int64) -> CMTime { CMTime(value: timestamp * Int64(num), timescale: den) }  // ⚑ package: RemuxerIOAction reads cross-module (binary-arbitrated §1)
}

extension Timebase {
    public var rational: AVRational { AVRational(num: num, den: den) }

    init(_ rational: AVRational) {
        num = rational.num
        den = rational.den
    }
}

final class Packet: ObjectQueueItem {
    public var duration: Int64 = 0
    public var timestamp: Int64 = 0
    public var position: Int64 = 0
    public var size: Int32 = 0
    // ⚑[tool=export_trie_oracle ref=Packet.corePacket:vpMV result=property descriptor present ⇒ the GETTER is public; the private setter is unobservable and is kept as reconstructed]
    // ⚑[tool=ffmpeg_name_oracle ref=av_packet_alloc:0x102d61878 result=CONFIRMED] (avcodec/packet.o, instr 16 / size 64)
    public private(set) var corePacket = av_packet_alloc()
    public var timebase: Timebase {
        assetTrack.timebase
    }

    var isKeyFrame: Bool {
        if let corePacket {
            return corePacket.pointee.flags & AV_PKT_FLAG_KEY == AV_PKT_FLAG_KEY
        } else {
            return false
        }
    }

    public var assetTrack: FFmpegAssetTrack! {
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
    public let dataSize: Int
    public let audioFormat: AVAudioFormat
    public internal(set) var timebase = Timebase.defaultValue
    public var timestamp: Int64 = 0
    public var duration: Int64 = 0
    public var position: Int64 = 0
    public var size: Int32 = 0
    public var data: [UnsafeMutablePointer<UInt8>?]
    public var numberOfSamples: UInt32 = 0
    public init(dataSize: Int, audioFormat: AVAudioFormat) {
        self.dataSize = dataSize
        self.audioFormat = audioFormat
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
        var dataSize = 0
        for frame in array {
            duration += frame.duration
            dataSize += frame.dataSize
            size += frame.size
            numberOfSamples += frame.numberOfSamples
        }
        self.dataSize = dataSize
        let count = audioFormat.isInterleaved ? 1 : audioFormat.channelCount
        data = (0 ..< count).map { _ in
            UnsafeMutablePointer<UInt8>.allocate(capacity: dataSize)
        }
        var offset = 0
        for frame in array {
            for i in 0 ..< data.count {
                data[i]?.advanced(by: offset).initialize(from: frame.data[i]!, count: frame.dataSize)
            }
            offset += frame.dataSize
        }
    }

    deinit {
        for i in 0 ..< data.count {
            data[i]?.deinitialize(count: dataSize)
            data[i]?.deallocate()
        }
        data.removeAll()
    }

    public func toFloat() -> [ContiguousArray<Float>] {
        var array = [ContiguousArray<Float>]()
        for i in 0 ..< data.count {
            switch audioFormat.commonFormat {
            case .pcmFormatInt16:
                let capacity = dataSize / MemoryLayout<Int16>.size
                data[i]?.withMemoryRebound(to: Int16.self, capacity: capacity) { src in
                    var des = ContiguousArray<Float>(repeating: 0, count: Int(capacity))
                    for j in 0 ..< capacity {
                        des[j] = max(-1.0, min(Float(src[j]) / 32767.0, 1.0))
                    }
                    array.append(des)
                }
            case .pcmFormatInt32:
                let capacity = dataSize / MemoryLayout<Int32>.size
                data[i]?.withMemoryRebound(to: Int32.self, capacity: capacity) { src in
                    var des = ContiguousArray<Float>(repeating: 0, count: Int(capacity))
                    for j in 0 ..< capacity {
                        des[j] = max(-1.0, min(Float(src[j]) / 2_147_483_647.0, 1.0))
                    }
                    array.append(des)
                }
            default:
                let capacity = dataSize / MemoryLayout<Float>.size
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
        for i in 0 ..< min(Int(pcmBuffer.format.channelCount), data.count) {
            switch audioFormat.commonFormat {
            case .pcmFormatInt16:
                let capacity = dataSize / MemoryLayout<Int16>.size
                data[i]?.withMemoryRebound(to: Int16.self, capacity: capacity) { src in
                    pcmBuffer.int16ChannelData?[i].update(from: src, count: capacity)
                }
            case .pcmFormatInt32:
                let capacity = dataSize / MemoryLayout<Int32>.size
                data[i]?.withMemoryRebound(to: Int32.self, capacity: capacity) { src in
                    pcmBuffer.int32ChannelData?[i].update(from: src, count: capacity)
                }
            default:
                let capacity = dataSize / MemoryLayout<Float>.size
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
        let sampleSize = Int(audioFormat.sampleSize)
        let sampleCount = CMItemCount(numberOfSamples)
        let dataByteSize = sampleCount * sampleSize
        if dataByteSize > dataSize {
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
            sampleSizeArray = [sampleSize]
        } else {
            sampleSizeEntryCount = 0
            sampleSizeArray = nil
        }
        CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: outBlockListBuffer, formatDescription: audioFormat.formatDescription, sampleCount: sampleCount, sampleTimingEntryCount: 1, sampleTimingArray: [timing], sampleSizeEntryCount: sampleSizeEntryCount, sampleSizeArray: sampleSizeArray, sampleBufferOut: &sampleBuffer)
        return sampleBuffer
    }
}

public final class VideoVTBFrame: MEFrame {
    // Field layout = reflection ORDER (Forward 1.3.17; desc 0x1039f0120, size 0xc60=3168 B).
    // Forward-NEW vs upstream: pixelBuffer (RENAMED from corePixelBuffer), adjustBuffer,
    // isKeyFrame, dovi, doviData, rpuBuffer. Types reflection/field-record-resolved.
    public var timebase: Timebase = Timebase.defaultValue
    public var pixelBuffer: PixelBufferProtocol? // @+0x18 (was corePixelBuffer)
    // 交叉视频的duration会不准，直接减半了
    public var duration: Int64 = 0
    public var position: Int64 = 0
    public var timestamp: Int64 = 0
    public let fps: Float
    public var size: Int32 = 0
    public var adjustBuffer: MTLBuffer? // @+0x48, field-record So9MTLBuffer_pSg; render-side, nil here
    public var edrMetaData: EDRMetaData? = nil
    public var isKeyFrame: Bool = false
    public var dovi: DOVIDecoderConfigurationRecord?
    public let isDovi: Bool
    // KSDOVIMetadata = opaque 3008 B inline (DOVIRPUShim). Field record 13 of 14 is
    // `<SYM:2@0x1039eb100>Sg` — the trailing `Sg` IS the optional wrapper, so `?` is the faithful
    // spelling here and `!` would be wrong. The earlier "an opaque blob has no nil-tag inhabitant in
    // 3008 B, so it must be NON-optional" rationale is REFUTED by VideoToolboxDecode.swift:31, which
    // reconstructs the identical type as `KSDOVIMetadata?` and PASSES the same gate.
    // NO declaration default: VideoVTBFrame's vpfi set is exactly {adjustBuffer, duration, position,
    // size, timebase, timestamp} (export_trie_oracle --class VideoVTBFrame) and doviData is NOT in it.
    // The initializer is therefore dropped, not mirrored from VideoToolboxDecode — whose doviData DOES
    // carry a vpfi, which is why the two classes legitimately differ. An optional `var` takes Swift's
    // implicit nil; writing `= nil` would emit a declaration default the binary does not have.
    var doviData: KSDOVIMetadata?
    public var rpuBuffer: Data? // @+0xc50 — AV_FRAME_DATA_DOVI_RPU_BUFFER raw bytes
    init(fps: Float, isDovi: Bool) {
        self.fps = fps
        self.isDovi = isDovi
    }
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
        if pixelBuffer?.transferFunction == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ {
            return CAEDRMetadata.hdr10(minLuminance: 0.1, maxLuminance: 1000, opticalOutputScale: 10000)
        } else if pixelBuffer?.transferFunction == kCVImageBufferTransferFunction_ITU_R_2100_HLG {
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
