//
//  Decoder.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/9.
//
import AVFoundation
import CoreMedia
import Libavformat

protocol PlayerItemTrackProtocol: CapacityProtocol, AnyObject {
    init(mediaType: AVFoundation.AVMediaType, frameCapacity: UInt16, options: KSOptions, expanding: Bool)
    // 是否无缝循环
    var isLoopModel: Bool { get set }
    var isEndOfFile: Bool { get set }
    var delegate: CodecCapacityDelegate? { get set }
    func decode()
    func seek(time: TimeInterval)
    func putPacket(packet: Packet)
//    func getOutputRender<Frame: ObjectQueueItem>(where predicate: ((Frame) -> Bool)?) -> Frame?
    func shutdown()
}

class SyncPlayerItemTrack<Frame: MEFrame>: PlayerItemTrackProtocol, CustomStringConvertible {
    var seekTime = 0.0
    fileprivate let options: KSOptions
    fileprivate var decoderMap = [Int32: DecodeProtocol]()
    fileprivate var state = MECodecState.idle {
        didSet {
            if state == .finished {
                seekTime = 0
            }
        }
    }

    var isEndOfFile: Bool = false
    var packetCount: Int { 0 }
    let description: String
    weak var delegate: CodecCapacityDelegate?
    let mediaType: AVFoundation.AVMediaType
    let outputRenderQueue: CircularBuffer<Frame>
    var isLoopModel = false
    var frameCount: Int { outputRenderQueue.count }
    var frameMaxCount: Int {
        Int(outputRenderQueue.maxCount)
    }

    var fps: Float {
        outputRenderQueue.fps
    }

    // Body @0x101a33460 (126 instr), reached through three per-Frame metadata thunks (0x101a3340c / 0x101a33428 /
    // 0x101a33444) that supply x4/x5 = the metadata pair and x6 = the specialized CircularBuffer init entry, which
    // `blr x19` calls. Real Swift arguments are x0..x3 only: x0 mediaType, x1 frameCapacity, x2 options, x3 = this
    // 4th Bool. `frameCapacity` is UInt16, not UInt8: every branch narrows it with `and x0, x22, #0xffff`.
    // ⚑ P28 — the 4th parameter's LABEL is irreducible, not merely unfound. SyncPlayerItemTrack is `internal`, so it
    //   contributes no symbol to the export trie (0 hits for `ItemTrack` across all 57138 trie names) and none to the
    //   symtab; Swift emits parameter labels nowhere else. `expanding` is recon-chosen because the binary forwards
    //   this argument verbatim as CircularBuffer's `expanding:` at all three branches (0x101a33580 / 0x101a33624 /
    //   0x101a3364c). The VALUES below are binary-read, not chosen: audio → sorted false / isClearItem true
    //   (w1=0, w3=1 @0x101a33584-88), video → sorted true / isClearItem true (w1=1, w3=1 @0x101a33650),
    //   else → sorted true / isClearItem !expanding (`bic w3, w8, w21` with w8=1 @0x101a33628).
    //   0x104108730 = _AVMediaTypeAudio and 0x104108740 = _AVMediaTypeVideo, both read from the bind table.
    required init(mediaType: AVFoundation.AVMediaType, frameCapacity: UInt16, options: KSOptions, expanding: Bool) {
        self.options = options
        self.mediaType = mediaType
        description = mediaType.rawValue
        // 默认缓存队列大小跟帧率挂钩,经测试除以4，最优
        if mediaType == .audio {
            outputRenderQueue = CircularBuffer(initialCapacity: UInt(frameCapacity), sorted: false, expanding: expanding, isClearItem: true)
        } else if mediaType == .video {
            outputRenderQueue = CircularBuffer(initialCapacity: UInt(frameCapacity), sorted: true, expanding: expanding, isClearItem: true)
        } else {
            // 有的图片字幕不按顺序来输出，所以要排序下。
            outputRenderQueue = CircularBuffer(initialCapacity: UInt(frameCapacity), sorted: true, expanding: expanding, isClearItem: !expanding)
        }
    }

    func decode() {
        isEndOfFile = false
        state = .decoding
    }

    func seek(time: TimeInterval) {
        if options.isAccurateSeek {
            seekTime = time
        } else {
            seekTime = 0
        }
        isEndOfFile = false
        state = .flush
        outputRenderQueue.flush()
        isLoopModel = false
    }

    func putPacket(packet: Packet) {
        if state == .flush {
            decoderMap.values.forEach { $0.doFlushCodec() }
            state = .decoding
        }
        if state == .decoding {
            doDecode(packet: packet)
        }
    }

    func getOutputRender(where predicate: ((Frame, Int) -> Bool)?) -> Frame? {
        let outputFecthRender = outputRenderQueue.pop(where: predicate)
        if outputFecthRender == nil {
            if state == .finished, frameCount == 0 {
                delegate?.codecDidFinished(track: self)
            }
        }
        return outputFecthRender
    }

    func shutdown() {
        if state == .idle {
            return
        }
        state = .closed
        outputRenderQueue.shutdown()
    }

    private var lastPacketBytes = Int32(0)
    private var lastPacketSeconds = Double(-1)
    // Forward-added stored field, every part binary-read: __swift5_fieldmd names it and places it here, between
    // lastPacketSeconds and bitrate (field 13 of 14, `var Sb`), and the init @0x101a33460 seeds it with
    // `strb wzr, [x20, #0x78]` @0x101a3853c-analogue — i.e. false. Its READER is not reconstructed yet; the
    // related `CircularBuffer.seek(seconds:needKeyFrame:)` in the trie is the likely consumer, its own unit.
    var isNeedKeyFrame = false
    // ⚑ `bitrate` is `Swift.Int` in __swift5_fieldmd (field 14, `var Si`), not the `Double` spelled here. The init's
    //   `str xzr, [x20, #0x80]` cannot discriminate the two (both are 8 zero bytes), and doDecode's arithmetic below
    //   is the body that would settle it — left as recorded type debt, its own unit.
    var bitrate = Double(0)
    fileprivate func doDecode(packet: Packet) {
        if packet.isKeyFrame, packet.assetTrack.mediaType != .subtitle {
            let seconds = packet.seconds
            let diff = seconds - lastPacketSeconds
            if lastPacketSeconds < 0 || diff < 0 {
                bitrate = 0
                lastPacketBytes = 0
                lastPacketSeconds = seconds
            } else if diff > 1 {
                bitrate = Double(lastPacketBytes) / diff
                lastPacketBytes = 0
                lastPacketSeconds = seconds
            }
        }
        lastPacketBytes += packet.size
        let decoder = decoderMap.value(for: packet.assetTrack.trackID, default: makeDecode(assetTrack: packet.assetTrack))
//        var startTime = CACurrentMediaTime()
        decoder.decodeFrame(from: packet) { [weak self] result in
            guard let self else {
                return
            }
            do {
//                if packet.assetTrack.mediaType == .video {
//                    print("[video] decode time: \(CACurrentMediaTime()-startTime)")
//                    startTime = CACurrentMediaTime()
//                }
                let frame = try result.get()
                if self.state == .flush || self.state == .closed {
                    return
                }
                if self.seekTime > 0 {
                    let timestamp = frame.timestamp + frame.duration
//                    KSLog("seektime \(self.seekTime), frame \(frame.seconds), mediaType \(packet.assetTrack.mediaType)")
                    if timestamp <= 0 || frame.timebase.cmtime(for: timestamp).seconds < self.seekTime {
                        return
                    } else {
                        self.seekTime = 0.0
                    }
                }
                if let frame = frame as? Frame {
                    self.outputRenderQueue.push(frame)
                    self.outputRenderQueue.fps = packet.assetTrack.nominalFrameRate
                }
            } catch {
                KSLog("Decoder did Failed : \(error)")
                if decoder is VideoToolboxDecode {
                    decoder.shutdown()
                    self.decoderMap[packet.assetTrack.trackID] = FFmpegDecode(assetTrack: packet.assetTrack, options: self.options)
                    KSLog("VideoCodec switch to software decompression")
                    self.doDecode(packet: packet)
                } else {
                    self.state = .failed
                }
            }
        }
        if options.decodeAudioTime == 0, mediaType == .audio {
            options.decodeAudioTime = CACurrentMediaTime()
        }
        if options.decodeVideoTime == 0, mediaType == .video {
            options.decodeVideoTime = CACurrentMediaTime()
        }
    }
}

final class AsyncPlayerItemTrack<Frame: MEFrame>: SyncPlayerItemTrack<Frame> {
    private let operationQueue = OperationQueue()
    private var decodeOperation: BlockOperation!
    // 无缝播放使用的PacketQueue
    private var loopPacketQueue: CircularBuffer<Packet>?
    var packetQueue = CircularBuffer<Packet>()
    override var packetCount: Int { packetQueue.count }
    override var isLoopModel: Bool {
        didSet {
            if isLoopModel {
                loopPacketQueue = CircularBuffer<Packet>()
                isEndOfFile = true
            } else {
                if let loopPacketQueue {
                    packetQueue.shutdown()
                    packetQueue = loopPacketQueue
                    self.loopPacketQueue = nil
                    if decodeOperation.isFinished {
                        decode()
                    }
                }
            }
        }
    }

    // Body @0x101a383c0 (277 instr): x0 mediaType, x1 frameCapacity, x2 options, x3 = the same 4th Bool, x4 = the
    // CircularBuffer init entry, incoming x20 = self. It INLINES the super init rather than calling it — the same
    // three-way mediaType branch appears at 0x101a38600 (audio: w1=0, w3=1), 0x101a387b0 (video: w1=1, w3=1) and
    // 0x101a38804 (else: w1=1, `bic w3, w8, w20` = !expanding), each forwarding `and w2, w20, #1` as `expanding:`.
    // ⚑ NOT REPRODUCED HERE (own unit, out of the arity fix): the binary also builds `packetQueue` inside this init
    //   with a mediaType-dependent capacity — audio 2048 / video 512 / else 256 @0x101a384f8 / 0x101a387f4 /
    //   0x101a384dc — and isClearItem = false for audio and else, but `!options.<field>` for video (field-offset
    //   global 0x104c63350, read under swift_beginAccess then `eor w8, w8, #1` @0x101a387ec). Source still declares
    //   `var packetQueue = CircularBuffer<Packet>()` as a property initializer, which that body refutes.
    required init(mediaType: AVFoundation.AVMediaType, frameCapacity: UInt16, options: KSOptions, expanding: Bool) {
        super.init(mediaType: mediaType, frameCapacity: frameCapacity, options: options, expanding: expanding)
        operationQueue.name = "KSPlayer_" + mediaType.rawValue
        operationQueue.maxConcurrentOperationCount = 1
        operationQueue.qualityOfService = .userInteractive
    }

    override func putPacket(packet: Packet) {
        if isLoopModel {
            loopPacketQueue?.push(packet)
        } else {
            packetQueue.push(packet)
        }
    }

    override func decode() {
        isEndOfFile = false
        guard operationQueue.operationCount == 0 else { return }
        decodeOperation = BlockOperation { [weak self] in
            guard let self else { return }
            Thread.current.name = self.operationQueue.name
            Thread.current.stackSize = KSOptions.stackSize
            self.decodeThread()
        }
        decodeOperation.queuePriority = .veryHigh
        decodeOperation.qualityOfService = .userInteractive
        operationQueue.addOperation(decodeOperation)
    }

    private func decodeThread() {
        state = .decoding
        isEndOfFile = false
        decoderMap.values.forEach { $0.decode() }
        outerLoop: while !decodeOperation.isCancelled {
            switch state {
            case .idle:
                break outerLoop
            case .finished, .closed, .failed:
                decoderMap.values.forEach { $0.shutdown() }
                decoderMap.removeAll()
                break outerLoop
            case .flush:
                decoderMap.values.forEach { $0.doFlushCodec() }
                state = .decoding
            case .decoding:
                if isEndOfFile, packetQueue.count == 0 {
                    state = .finished
                } else {
                    guard let packet = packetQueue.pop(wait: true), state != .flush, state != .closed else {
                        continue
                    }
                    autoreleasepool {
                        doDecode(packet: packet)
                    }
                }
            }
        }
    }

    override func seek(time: TimeInterval) {
        if decodeOperation.isFinished {
            decode()
        }
        packetQueue.flush()
        super.seek(time: time)
        loopPacketQueue = nil
    }

    override func shutdown() {
        if state == .idle {
            return
        }
        super.shutdown()
        packetQueue.shutdown()
    }
}

public extension Dictionary {
    mutating func value(for key: Key, default defaultValue: @autoclosure () -> Value) -> Value {
        if let value = self[key] {
            return value
        } else {
            let value = defaultValue()
            self[key] = value
            return value
        }
    }
}

protocol DecodeProtocol {
    func decode()
    func decodeFrame(from packet: Packet, completionHandler: @escaping (Result<MEFrame, Error>) -> Void)
    func doFlushCodec()
    func shutdown()
}

extension SyncPlayerItemTrack {
    func makeDecode(assetTrack: FFmpegAssetTrack) -> DecodeProtocol {
        autoreleasepool {
            if mediaType == .subtitle {
                return SubtitleDecode(assetTrack: assetTrack, options: options)
            } else {
                if mediaType == .video, options.asynchronousDecompression, options.hardwareDecode,
                   let session = DecompressionSession(assetTrack: assetTrack, options: options)
                {
                    return VideoToolboxDecode(options: options, session: session)
                } else {
                    return FFmpegDecode(assetTrack: assetTrack, options: options)
                }
            }
        }
    }
}
