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
import Foundation
import Libavformat
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
/// ⚑ s107: this protocol had FIVE requirements declared and the descriptor @0x1039efe84 says
/// **seven**. The two missing ones are added below, and their POSITIONS are read rather than
/// appended: walking `KSMEPlayer`'s witness table @0x1041d7c28 slot by slot and following each
/// 1-instruction thunk gives the order outright —
///   req0 `sourceDidChange(loadingState:)` · req1 `sourceDidOpened()` · req2 **`sourceDidEOF()`** ·
///   req3 `sourceDidFailed(error:)` · req4 `sourceDidFinished()` ·
///   req5 `sourceDidChange(oldBitRate:newBitrate:)` (its witness 0x101a45ed4 is an unnamed
///   reabstraction thunk, so this one is by elimination) · req6 **`sourceDidClear()`**.
/// A requirement's index is its witness-table slot, so appending the two at the end would have
/// put `sourceDidEOF` in the wrong slot.
public protocol MEPlayerDelegate: AnyObject {
    func sourceDidChange(loadingState: LoadingState)
    func sourceDidOpened()
    func sourceDidEOF()
    func sourceDidFailed(error: Error?)
    func sourceDidFinished()
    func sourceDidChange(oldBitRate: Int64, newBitrate: Int64)
    func sourceDidClear()
}

// MARK: protocol

// ⚑ L7 lane 13: Forward requirement list = five lone getters (protocol_surface fwd_units g×5). Order read from
//   Packet's witness table 0x1041d8d90 (conf 0x10356b578): +0x8 assetTrack(+0x40)→timebase, +0x10 field +0x18
//   timestamp, +0x18 field +0x10 duration, +0x20 field +0x20 position, +0x28 field +0x28 size. The setters
//   are MEFrame's (below).
public protocol ObjectQueueItem {
    var timebase: Timebase { get }
    var timestamp: Int64 { get }
    var duration: Int64 { get }
    // byte position
    var position: Int64 { get }
    // ⚑[tool=type_surface ref=ObjectQueueItem:requirements result=5 getters] Forward's requirement list
    //   is five lone getters; AudioFrame satisfies `size` with a computed getter (no stored field).
    var size: Int32 { get }
}

extension ObjectQueueItem {
    public var seconds: TimeInterval { cmtime.seconds }
    var cmtime: CMTime { timebase.cmtime(for: timestamp) }
}

public protocol FrameOutput: AnyObject {
    // The binary SPLITS renderSource by output kind: AudioBaseOutput and AudioDataBuffer carry
    // `AudioOutputRenderSourceDelegate?` while MetalPlayView carries
    // `VideoOutputRenderSourceDelegate?` — all six accessors and both direct field offsets say
    // so. One combined requirement cannot express that, so it moves down to AudioOutput and
    // VideoOutput.
    func play()
    func pause()
    func flush()
    func invalidate()
}

// ⚑ L7 lane 13: Forward MEFrame = base + 4 (setter, modify) pairs; AudioFrame's witness table 0x1041d8dc0
//   (conf 0x10356b588) stores fields +0x20 timebase, +0x28 timestamp, +0x30 duration, +0x38 position in that order.
protocol MEFrame: ObjectQueueItem {
    var timebase: Timebase { get set }
    var timestamp: Int64 { get set }
    var duration: Int64 { get set }
    var position: Int64 { get set }
}

// MARK: model

// for MEPlayer
public extension KSOptions {
    nonisolated(unsafe) static var stackSize = 65536

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
    public var cmtime: CMTime { CMTime(value: Int64(num), timescale: den) }
}

// ⚑ L7 lane 13: public (lane 10): Forward KSOptions.makeDecode 0x1019b604c keeps swift_beginAccess on
//   packet+0x40 and the ObjectQueueItem witnesses (0x101a63a44…) beginAccess every field; the trie exports
//   the field accessors but no Packet init (init stays internal).
public final class Packet: ObjectQueueItem {
    public var duration: Int64 = 0
    public var timestamp: Int64 = 0
    public var position: Int64 = 0
    public var size: Int32 = 0
    public var timebase: Timebase {
        assetTrack!.timebase
    }

    deinit {
        av_packet_unref(corePacket)
        av_packet_free(&corePacket)
    }
    // ⚑[tool=export_trie_oracle ref=Packet.corePacket:vpMV result=property descriptor present ⇒ the GETTER is public; the private setter is unobservable and is kept as reconstructed]
    // ⚑[tool=ffmpeg_name_oracle ref=av_packet_alloc:0x102d61878 result=CONFIRMED] (avcodec/packet.o, instr 16 / size 64)
    // ⚑ Forward pfi `$s8KSPlayer6PacketC04coreB0SpySo8AVPacketVGSgvpfi` = 0x10002d9d4 (merged `mov x0,#0; ret` nil
    //   initializer, hence src_file KSAVPlayer.swift); all 3 inlined construction sites (0x101a1aee8 transcode,
    //   0x101a51310, 0x101a675e4) store nil at +0x30 with the other defaults, then av_packet_alloc →
    //   swift_beginAccess(+0x30, modify) → store: the allocation is an init-body reassignment.
    public private(set) var corePacket: UnsafeMutablePointer<AVPacket>?
    init() {
        corePacket = av_packet_alloc()
    }
    // ⚑ s105: field record [5] of 7 on descriptor 0x1039effec, mangle `Sb` = Swift.Bool. Declared
    // HERE rather than appended because a stored property's order is its layout: the record sits
    // between corePacket [4] and assetTrack [6], and `timebase`/`isKeyFrame` below are computed,
    // so they occupy no slot and do not displace it.
    // `var` (not `let`) is established by the trie exporting getter, setter AND modify for it.
    // The default is read, not assumed: the variable-initialization expression is at 0x10002dab0,
    // which is `mov w0, #0 / ret` — false.
    // ⚑[tool=export_trie_oracle ref=Packet.isFlush:vpfi@0x10002dab0 result=false]
    public var isFlush = false

    var isKeyFrame: Bool {
        if let corePacket {
            return corePacket.pointee.flags & AV_PKT_FLAG_KEY == AV_PKT_FLAG_KEY
        } else {
            return false
        }
    }

    // OPTIONAL, not IUO. The trie prints `Packet.assetTrack.getter : KSPlayer.FFmpegAssetTrack?`,
    // and a field record cannot tell `T!` from `T?` — so `?` is the only spelling the binary
    // supports, and MEMORY forbids writing `T!` off a field record.
    // Declaration default: Forward emits `variable initialization expression of assetTrack` (0x10002d9d4, `mov x0,#0`).
    // ⚑ L7 lane 13: trie exports assetTrack getter only (vg/vpWvd/vpMV/vpfi), no setter/modify → internal(set).
    public internal(set) var assetTrack: FFmpegAssetTrack? = nil {
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
}

final class SubtitleFrame: MEFrame {
    var timestamp: Int64 = 0
    var timebase: Timebase
    var duration: Int64 = 0
    var position: Int64 = 0
    var size: Int32 = 0
    let part: SubtitlePart
    // @0x101a63adc — timing is derived here, not by the caller (decodeFrame(from:completionHandler:) @0x101a69de8
    // only constructs and delivers).
    init(part: SubtitlePart, timebase: Timebase) {
        self.part = part
        self.timebase = timebase
        timestamp = timebase.getPosition(from: part.start)
        if part.end.isFinite {
            duration = max(timebase.getPosition(from: part.end) - timestamp, 0)
        } else {
            duration = Int64.max - max(timestamp, 0)
        }
    }
}

public final class AudioFrame: MEFrame {
    // UInt32, not Int. The trie prints both `AudioFrame.dataSize.getter : Swift.UInt32` and
    // `AudioFrame.init(dataSize: Swift.UInt32, audioFormat: __C.AVAudioFormat)`.
    public let dataSize: UInt32
    public let audioFormat: AVAudioFormat
    public internal(set) var timebase = Timebase.defaultValue
    public var timestamp: Int64 = 0
    public var duration: Int64 = 0
    public var position: Int64 = 0
    public var data: [UnsafeMutablePointer<UInt8>?]
    // ⚑[tool=field_surface ref=AudioFrame:fieldmd result=8 fields, no size] Computed. Getter 0x101a63ff0:
    //   `ldr w19,[x20,#0x10]` + tbnz #31 trap (Int32(dataSize)), data.count with `lsr #31` trap
    //   (Int32(count)), `mul` then `cmp x0, w0, sxtw` overflow trap.
    public var size: Int32 { Int32(dataSize) * Int32(data.count) }
    public var numberOfSamples: UInt32 = 0
    public init(dataSize: UInt32, audioFormat: AVAudioFormat) {
        self.dataSize = dataSize
        self.audioFormat = audioFormat
        let count = audioFormat.isInterleaved ? 1 : audioFormat.channelCount
        data = (0 ..< count).map { _ in
            UnsafeMutablePointer<UInt8>.allocate(capacity: Int(dataSize))
        }
    }

    init(array: [AudioFrame]) {
        audioFormat = array[0].audioFormat
        timebase = array[0].timebase
        timestamp = array[0].timestamp
        position = array[0].position
        var dataSize = UInt32(0)
        for frame in array {
            duration += frame.duration
            dataSize += frame.dataSize
            numberOfSamples += frame.numberOfSamples
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
        for i in 0 ..< data.count {
            switch audioFormat.commonFormat {
            case .pcmFormatInt16:
                let capacity = Int(dataSize) / MemoryLayout<Int16>.size
                data[i]?.withMemoryRebound(to: Int16.self, capacity: capacity) { src in
                    var des = ContiguousArray<Float>(repeating: 0, count: Int(capacity))
                    for j in 0 ..< capacity {
                        des[j] = max(-1.0, min(Float(src[j]) / 32767.0, 1.0))
                    }
                    array.append(des)
                }
            case .pcmFormatInt32:
                let capacity = Int(dataSize) / MemoryLayout<Int32>.size
                data[i]?.withMemoryRebound(to: Int32.self, capacity: capacity) { src in
                    var des = ContiguousArray<Float>(repeating: 0, count: Int(capacity))
                    for j in 0 ..< capacity {
                        des[j] = max(-1.0, min(Float(src[j]) / 2_147_483_647.0, 1.0))
                    }
                    array.append(des)
                }
            default:
                let capacity = Int(dataSize) / MemoryLayout<Float>.size
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
                let capacity = Int(dataSize) / MemoryLayout<Int16>.size
                data[i]?.withMemoryRebound(to: Int16.self, capacity: capacity) { src in
                    pcmBuffer.int16ChannelData?[i].update(from: src, count: capacity)
                }
            case .pcmFormatInt32:
                let capacity = Int(dataSize) / MemoryLayout<Int32>.size
                data[i]?.withMemoryRebound(to: Int32.self, capacity: capacity) { src in
                    pcmBuffer.int32ChannelData?[i].update(from: src, count: capacity)
                }
            default:
                let capacity = Int(dataSize) / MemoryLayout<Float>.size
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
        let sampleCount = CMItemCount(numberOfSamples)
        let dataByteSize = min(sampleCount * Int(audioFormat.sampleSize), Int(dataSize))
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
                    dataLength: outBlockBuffer.dataLength,
                    flags: 0
                )
            }
        }
        var sampleBuffer: CMSampleBuffer?
        let duration: CMTime
        if audioFormat.commonFormat == .otherFormat {
            duration = timebase.cmtime(for: self.duration)
        } else {
            duration = CMTime(value: 1, timescale: Int32(audioFormat.sampleRate))
        }
        let timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: cmtime, decodeTimeStamp: .invalid)
        let sampleSizeEntryCount: CMItemCount
        let sampleSizeArray: [Int]?
        if audioFormat.commonFormat == .otherFormat {
            sampleSizeEntryCount = 1
            sampleSizeArray = [Int(dataSize)]
        } else if audioFormat.isInterleaved {
            sampleSizeEntryCount = 1
            sampleSizeArray = [Int(audioFormat.sampleSize)]
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
    // NON-OPTIONAL `let`, supplied at init. Field record 1 is flags=0 with tail `_p` and NO
    // `Sg`; the trie exports pixelBuffer.getter with no setter and no modify; and
    // VideoSwresample.change(avframe:) allocates the frame AFTER obtaining the buffer
    // (_swift_allocObject @0x101a661d0 follows the buffer work at 0x101a6615c) — three
    // independent reads of the same fact.
    public let pixelBuffer: PixelBufferProtocol // @+0x18 (was corePixelBuffer)
    // 交叉视频的duration会不准，直接减半了
    public var duration: Int64 = 0
    public var position: Int64 = 0
    public var timestamp: Int64 = 0
    public let fps: Float
    public var size: Int32 = 0
    public var adjustBuffer: MTLBuffer? // @+0x48, field-record So9MTLBuffer_pSg; render-side, nil here
    // edrMetaData, isKeyFrame, dovi, doviData, rpuBuffer are `let` (field-record flags 0; the trie exports
    // getters only: no setter, modify or vpfi), supplied by the init.
    public let edrMetaData: EDRMetaData?
    public let isKeyFrame: Bool
    public let dovi: DOVIDecoderConfigurationRecord?
    public let isDovi: Bool
    // KSDOVIMetadata uses the imported-C 3008-byte inline layout. The nested Bool at metadata
    // offset 0x457 supplies Optional's extra inhabitant, so this field remains KSDOVIMetadata?.
    // Field record 13 of 14 is `<SYM:2@0x1039eb100>Sg`, confirming the optional wrapper.
    let doviData: KSDOVIMetadata?
    public let rpuBuffer: Data? // @+0xc50 — AV_FRAME_DATA_DOVI_RPU_BUFFER raw bytes
    // Inlined at both Forward construction sites (VideoSwresample.change 0x101a660dc, VT output closure
    // 0x101a6d734): after the pixelBuffer store both call the colorspace helper (0x101a88b68, CVBuffer
    // specialization 0x101a6c9ec) with dovi, then store fps, isKeyFrame, isDovi (= dovi != nil), dovi,
    // edrMetaData, doviData, rpuBuffer. The init itself is dead-stripped; parameter order is ours.
    init(pixelBuffer: PixelBufferProtocol, fps: Float, isKeyFrame: Bool, dovi: DOVIDecoderConfigurationRecord?, edrMetaData: EDRMetaData?, doviData: KSDOVIMetadata?, rpuBuffer: Data?) {
        self.pixelBuffer = pixelBuffer
        pixelBuffer.configureColorSpace(dovi: dovi)
        self.fps = fps
        self.isKeyFrame = isKeyFrame
        isDovi = dovi != nil
        self.dovi = dovi
        self.edrMetaData = edrMetaData
        self.doviData = doviData
        self.rpuBuffer = rpuBuffer
    }
}

// ⚑ Forward 0x101a654f4 (Model.swift, 69 insns, unnamed internal; lane-12 gap): MasteringDisplayMetadata passed
//   by value (x0–x2) → 8× [UInt8].append(UInt16) 0x1019e7290, 2× append(UInt32) 0x1019e7374, 0x101a83650, Data.
//   Sole caller CAMetalLayer.updateInfo 0x101a84b18 (MetalRender.swift, lane 12). Placed after VideoVTBFrame's
//   deinit 0x101a65480 per Forward layout. Name/shape INFERRED (lane 12's local `data(_:)` signature).
func data(_ displayData: MasteringDisplayMetadata) -> Data { // INFERRED
    var bytes = [UInt8]()
    bytes.append(displayData.display_primaries_r_x)
    bytes.append(displayData.display_primaries_r_y)
    bytes.append(displayData.display_primaries_g_x)
    bytes.append(displayData.display_primaries_g_y)
    bytes.append(displayData.display_primaries_b_x)
    bytes.append(displayData.display_primaries_b_y)
    bytes.append(displayData.white_point_x)
    bytes.append(displayData.white_point_y)
    bytes.append(displayData.minLuminance)
    bytes.append(displayData.maxLuminance)
    bytes.reverse()
    return Data(bytes)
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
        if pixelBuffer.transferFunction == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ {
            return CAEDRMetadata.hdr10(minLuminance: 0.1, maxLuminance: 1000, opticalOutputScale: 10000)
        } else if pixelBuffer.transferFunction == kCVImageBufferTransferFunction_ITU_R_2100_HLG {
            return CAEDRMetadata.hlg
        }
        return nil
    }
    #endif
}

// ⚑[tool=field_surface ref=EDRMetaData:fieldmd result=4 let]
public struct EDRMetaData {
    let displayData: MasteringDisplayMetadata?
    let contentData: ContentLightMetadata?
    let ambientViewingEnvironment: AmbientViewingEnvironment?
    let isVIVID: Bool
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

//  Forward 1.3.17 reconstruction — P2 remux cluster (Wave 2). NEW Forward-only class (root, no superclass).
//  The packet-writer that fronts OutputStreamInfo: per packet it clamps the DTS, records it, then drives
//  the per-stream Copy/BSF builder (OutputStreamInfo slot13). Reconstructed FAITHFUL from write/slot7
//  (0x101a65df0, 94 instr). Descriptor 0x1039f01e8, accessor 0x101a6608c.
//  `final` not binary-pinned (no library evolution) — M2 verifies; matches the Copy/BSF/OSI `final` choice.
public class Remuxer { // not final: Forward vtable has 9 slots (slot 7 write(_:) @0x101a65df0)
    // 5 stored fields — reflection-authoritative NAMES + ORDER; offsets from the driver store-sequence (size 0x34).
    let formatCtx: UnsafeMutablePointer<AVFormatContext>  // +0x10 ⚑ inferred (symref); driver stores formatContext[+0x18];
                                                          //   matches the 1C.5 FormatContext convention (OSI.formatCtx is exactly this)
    let outputStreamInfo: OutputStreamInfo               // +0x18  grounded (write reads it; the P3 builder returns OSI here)
    // ⚑ MODULE-QUALIFIED s102. Unqualified, `AVMediaType` resolved HERE to Libavutil's C enum, because
    //   this file imports Libavcodec/Libavformat and not AVFoundation — a silent wrong type, since the
    //   binary `objc_retain`s this field (@0x101a484b4, stored `str x21,[x23,#0x20]` @0x101a484b0) and
    //   a C enum is not retainable. The value arrives from MEPlayerItem.startRecord, whose trie
    //   signature types it `__C.AVMediaType?` (mangled `So07AVMediaH0aSg`, an `a`-kind typealias).
    //   ⚑[tool=export_trie_oracle ref=MEPlayerItem.startRecord(url:mediaType:):0x101a483d4 result=AVMediaType-optional]
    let mediaType: AVFoundation.AVMediaType?              // +0x20  l2_field_gate property-symbol (class-proven) = AVMediaType? (OPTIONAL)
    var startTime: [Int32: Int64] = [:]                  // +0x28  per-stream DTS map. CLASS-SCOPED field-record = SDy (DICTIONARY),
                                                         //   key Int32 (stream_index), value Int64 (clamped DTS) — corroborated by write()'s
                                                         //   keyed-set. NOT Array, NOT CMTime?, NOT Double: l2_field_gate's `Double` is an
                                                         //   UNSCOPED property-symbol match (another class's startTime); the class-scoped
                                                         //   field-record + write-usage are authoritative (§19). ⚑ key/value width via §7-walled symref
    var lock: os_unfair_lock = os_unfair_lock()          // +0x30  (4-byte os_unfair_lock, init 0)

    // init — minimal inferred (devirt slot6, inlined in the P3 driver → signature UNRECOVERABLE).
    // ⚑ init inferred — devirt slot6, built inline by the P3 driver 0x101a483d4 (alloc+field-stores);
    //   exact signature unrecoverable.
    public init(formatCtx: UnsafeMutablePointer<AVFormatContext>,
                outputStreamInfo: OutputStreamInfo,
                mediaType: AVFoundation.AVMediaType?) {
        self.formatCtx = formatCtx
        self.outputStreamInfo = outputStreamInfo
        self.mediaType = mediaType
        // startTime defaults to [:]; lock defaults to os_unfair_lock().
    }

    // ── write (slot7 @0x101a65df0, 94 instr) — FAITHFUL (DTS-clamp + lock + → slot13) ─────────────
    // NAME IS INVENTED AND IS NOW MARKED AS SUCH. `name_exhaustion_gate` closes ALL SEVEN routes on
    //   0x101a65df0 — no trie symbol at the address; the trie carries NO symbol for class
    //   KSPlayer.Remuxer at all (its only Remuxer-bearing symbols are MEPlayerItem's `remuxer` field
    //   and two unrelated ProAVPlayer protocol descriptors); no `#function`/`#file` literal (the body
    //   has ZERO string literals); not an objc selector or IMP; and `masked_twin --scan` finds no twin
    //   anywhere in the image, so it is real source, not emitted-library code. Two call sites, so it
    //   is not INLINE-INSTEAD. Exactly one data pointer references it image-wide: Remuxer's metadata
    //   vtable slot 7 (0x1044eae58 = meta 0x1044eada8 + 0x78 + 0x38) — no witness table, no objc
    //   method list, so the witness-anchoring route is closed too.
    // ⚠️ THE VTABLE-ELIMINATION ROUTE IS CLOSED ON THE MERITS, NOT ON THE GATE'S SAY-SO. The gate
    //   reported "3 slots are unnamed" for this class; that is a TOOL BUG (its regex
    //   `0x([0-9a-f]{9})` also matches the two header addresses `desc=0x1039f01e8` and
    //   `@0x1039f0214` that vtable_walk prints, so it counted headers as impls — the true Impl count
    //   is 1). Corrected, the route would print OPEN, and that OPEN would be VACUOUS: elimination
    //   needs N-1 NAMED siblings and the trie names zero Remuxer methods. Closed either way.
    // ⚠️ THE NAME IS KEPT, NOT CHANGED. `transcode(packet:)` is the binary's convention for this exact
    //   AVPacket-ingest signature (FFmpegAssetTrack and OutputStreamInfo both use it; no trie-named
    //   KSPlayer member with an AVPacket parameter is called `write`). But that is a convention
    //   argument at a DIFFERENT abstraction level — this is the Remuxer's entry point, and the actual
    //   output write happens downstream in the transcode contexts — and swapping one invented name
    //   for another invented name buys
    //   no binary evidence. What was actually wrong here is that a fabricated identifier carried
    //   prose instead of the marker grammar, so no grep could find it. That is fixed.
    //   Header-verified AVPacket offsets: pts@+0x08, dts@+0x10, stream_index@+0x24.
    // ⚑[invented=write addr=0x101a65df0 exhaustion=name_exhaustion_gate approved=jweaver]
    func write(_ packet: UnsafeMutablePointer<AVPacket>) {
        // Guard [A]: the OSI must have stream mappings. *(*(*(self+0x18)+0x40)+0x10) != 0 →
        // outputStreamInfo.streamMapping (OSI+0x40), NOT transcodeMap (OSI+0x18). [orchestrator re-walk fix]
        guard !outputStreamInfo.streamMapping.isEmpty else { return }

        let idx = packet.pointee.stream_index                          // packet+0x24
        // Guard [B]: this stream must be mapped to an output. subscript FUN_1019c10ec → (param_2 & 1).
        // ⚑ [B] binding inferred as streamMapping[idx] (consistent with guard [A]'s streamMapping check).
        guard outputStreamInfo.streamMapping[idx] != nil else { return }

        os_unfair_lock_lock(&lock)                                     // self+0x30
        defer { os_unfair_lock_unlock(&lock) }                         // self+0x30 (binary unlocks on the same path tail)

        // Record the clamped DTS for this stream IF not already recorded. Binary: `if startTime empty ||
        // startTime[idx] miss { … }` (self+0x28: isUniquelyReferenced + keyed-set FUN_1019c235c + the
        // 0x8000000000000000 sentinel swap). startTime (self+0x28) is the Remuxer's OWN [Int32: Int64]
        // DTS map (field-record SDy). DTS clamp = min(max(pts,0), max(dts,0)); the binary computes max(x,0)
        // branchlessly as `x & ~(x>>63)` for pts (packet+0x08) and dts (packet+0x10), then min.
        if startTime[idx] == nil {                                     // self+0x28 empty OR subscript-miss
            let pts = packet.pointee.pts                               // packet+0x08
            let dts = packet.pointee.dts                               // packet+0x10
            startTime[idx] = min(max(pts, 0), max(dts, 0))            // keyed-set FUN_1019c235c on self+0x28
        }

        // Ensure the per-stream context exists and RUN it (OSI.s13). The completion is the write-output
        // callback: ctx.transcode produces the filtered/copied packet, then calls completion(outputPacket)
        // to emit it. Binary: callback FUN_101a660d0 + a closure box capturing self+idx (DAT_1041d9368).
        _ = outputStreamInfo.transcode(packet: packet) { [self] packet in   // FUN_101a1ab5c (File-1 slot13)  ⚑[tool=resolve_fun_pins ref=FUN_101a1ab5c:0x101a1ab5c result=RESOLVES_UNIQUELY] = KSPlayer.OutputStreamInfo.transcode(packet: Swift.UnsafeMutablePointer<__C.AVPacket>, block: ((Swift.UnsafeMutablePointer<__C.AVPacket>) -> ())?) -> Swift.Int32
            // closure body FUN_101a65f68 (via partial-apply 0x101a660d0): rebase pts/dts by startTime[idx].
            let pts = packet.pointee.pts
            if pts != Int64.min {
                packet.pointee.pts = pts - (startTime[idx] ?? 0)
            }
            let dts = packet.pointee.dts
            if dts != Int64.min {
                packet.pointee.dts = dts - (startTime[idx] ?? 0)
            }
        }
    }

    // ⚑ UNRESOLVED → P3: write-output completion body (FUN_101a660d0). Emits the transcoded `outputPacket`
    // to the output format context for `streamIndex` (av_write_frame / av_interleaved_write_frame — the actual
    // write is devirtualized/unresolved). NOT invented. Reconstruct as its own unit (decompile FUN_101a660d0).
    private func writeOutputPacket(_ outputPacket: UnsafeMutablePointer<AVPacket>?, streamIndex: Int32) {
        // UNRESOLVED — devirtualized write-output (FUN_101a660d0); reconstruct as its own unit.
    }

    // slot8 — devirtualized, no readable body.
    // UNRESOLVED → P3: slot8 (devirt, no body)
}
