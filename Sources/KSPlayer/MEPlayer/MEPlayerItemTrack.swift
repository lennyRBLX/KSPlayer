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
    /// Forward witness table 0x1041d89b0: +0x68 / +0x70 sit between seek (+0x60 → vtable 0x198) and
    /// putPacket; +0x70 dispatches to vtable 0x1b8 = F29 updateCache, and MEPlayerItem 0x101a55de4 calls
    /// +0x70 on each cache hit. Requirement names follow the F28/F29 methods (INFERRED, no symbol).
    func seekCache(time: TimeInterval, needKeyFrame: Bool) -> (UInt, TimeInterval)?
    func updateCache(headIndex: UInt, time: TimeInterval)
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
    var packetCount: UInt { 0 }
    let description: String
    weak var delegate: CodecCapacityDelegate?
    let mediaType: AVFoundation.AVMediaType
    let outputRenderQueue: CircularBuffer<Frame>
    var isLoopModel = false
    // Forward frameCount / frameMaxCount getters (vtable #19/#20): plain load of the UInt, no `tbnz #63 → brk` overflow trap.
    // frameCount is UInt (CapacityProtocol: `adds x22,x21,x0; b.hs` @0x1019b8598/0x1019b85ec).
    var frameCount: UInt { outputRenderQueue.count }
    var frameMaxCount: Int {
        Int(bitPattern: outputRenderQueue.maxCount)
    }

    /// Vtable F21 (G, Forward 0x101a5b970): `Double(outputRenderQueue.count) / Double(fps)` — the UInt count is
    /// converted with `ucvtf` (unsigned), so it is not routed through the signed `frameCount`. Overridden by
    /// AsyncPlayerItemTrack (0x101a5d0bc, override-table entry 1) with the packet counts added — the
    /// CapacityProtocol extension formula. Name INFERRED (internal class, no trie symbol).
    var loadedTime: TimeInterval {
        TimeInterval(outputRenderQueue.count) / TimeInterval(fps)
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

    // Forward 0x101a5ba20: `strb #1,[x20,#0x78]` (isNeedKeyFrame) first, then the merged
    // `strh #1,[x20,#0x28]` (isEndOfFile false + state .decoding) — source order follows the store order.
    func decode() {
        isNeedKeyFrame = true
        isEndOfFile = false
        state = .decoding
    }

    // Forward 0x101a5ba30: seekTime, isEndOfFile, isLoopModel setter (vtable +0x158), state .flush,
    // isNeedKeyFrame, then outputRenderQueue.flush().
    func seek(time: TimeInterval) {
        if options.isAccurateSeek {
            seekTime = time
        } else {
            seekTime = 0
        }
        isEndOfFile = false
        isLoopModel = false
        state = .flush
        isNeedKeyFrame = true
        outputRenderQueue.flush()
    }

    // Forward 0x101a5bab4: on `.flush` the decoders are flushed (DecodeProtocol existential stride 0x10),
    // then outputRenderQueue.flush() (CircularBuffer.flush 0x101a17ac4), then state = .decoding; doDecode is
    // called unconditionally afterwards (no second state test).
    func putPacket(packet: Packet) {
        if state == .flush {
            decoderMap.values.forEach { $0.doFlushCodec() }
            outputRenderQueue.flush()
            state = .decoding
        }
        doDecode(packet: packet)
    }

    func getOutputRender(where predicate: ((Frame, UInt) -> Bool)?) -> Frame? {
        let outputFecthRender = outputRenderQueue.pop(where: predicate)
        if outputFecthRender == nil {
            if state == .finished, frameCount == 0 {
                delegate?.codecDidFinished(track: self)
            }
        }
        return outputFecthRender
    }

    /// Vtable F28 (M, Forward 0x100232cd4, ICF-shared `nil` of a two-word payload: x0=0, x1=0, w2=1).
    /// AsyncPlayerItemTrack overrides it (0x101a5db0c) with `packetQueue.seek(seconds:needKeyFrame:)`,
    /// whose `(UInt, Double)?` it returns (d0 = time, w0 = flag). Name and labels INFERRED.
    func seekCache(time _: TimeInterval, needKeyFrame _: Bool) -> (UInt, TimeInterval)? {
        nil
    }

    /// Vtable F29 (M, Forward 0x10000e52c, the app-wide `ret`). AsyncPlayerItemTrack overrides it
    /// (0x101a5db74; x0 = index, d0 = time). Name and labels INFERRED.
    func updateCache(headIndex _: UInt, time _: TimeInterval) {}

    // Forward 0x101a5bc34 (F30; FFmpegAssetTrack.stop dispatches it at +0x1c0).
    func shutdown() {
        if state == .idle {
            return
        }
        state = .closed
        outputRenderQueue.shutdown()
        decoderMap.values.forEach { $0.shutdown() }
        decoderMap.removeAll()
    }

    // ⚑[tool=field_surface ref=SyncPlayerItemTrack.lastPacketBytes:idx10 result=Int64]
    private var lastPacketBytes = Int64(0)
    private var lastPacketSeconds = Double(-1)
    // Forward-added stored field, every part binary-read: __swift5_fieldmd names it and places it here, between
    // lastPacketSeconds and bitrate (field 13 of 14, `var Sb`), and the init @0x101a33460 seeds it with
    // `strb wzr, [x20, #0x78]` @0x101a3853c-analogue — i.e. false. Its READER is not reconstructed yet; the
    // related `CircularBuffer.seek(seconds:needKeyFrame:)` in the trie is the likely consumer, its own unit.
    var isNeedKeyFrame = false
    // ⚑[tool=field_surface ref=SyncPlayerItemTrack.bitrate:idx13 result=Int] `Swift.Int` in __swift5_fieldmd;
    //   the init's `str xzr, [x20, #0x80]` is the zero. doDecode's conversions below follow the type; that
    //   body's exact arithmetic is its own unit.
    var bitrate = 0
    // THE PACKET IS UNWRAPPED ONCE, AT THE TOP, AND THE RAW POINTER IS WHAT REACHES THE DECODER.
    // `decodeFrame` takes `UnsafeMutablePointer<AVPacket>` in Forward, not `Packet` — see the
    // DecodeProtocol requirement below — so `corePacket` has to be non-optional before the call.
    // The binary hoists exactly that guard to the head of this body:
    //   101a373ec  ldr x22,[x21,#0x30]   packet.corePacket     (x21 = the incoming Packet)
    //   101a373f0  cbz x22, 0x101a379d0  -> the epilogue, which ends `ret` at 0x101a379f0
    //   101a373f4  ldrb w8,[x22,#0x28]   corePacket.pointee.flags   = isKeyFrame, INLINED on the
    //   101a373f8  tbz w8,#0x0           AV_PKT_FLAG_KEY            already-unwrapped pointer
    // It is a GUARD-with-return, not a force-unwrap, and the discriminator is in this same body:
    // `assetTrack!` two lines down compiles to `cbz x20 -> brk #0x1` at 0x101a376c4/0x101a37a08,
    // and NO `brk` sits on the corePacket path. Offset 0x30 is corePacket by its own getter's body
    // (0x101a63f38 `ldr x0,[x20,#0x30]`), not by arithmetic on the field records.
    // ⚑[tool=export_trie_oracle ref=Packet.corePacket.getter:0x101a63f18 result=offset-0x30]
    // ⚑[tool=decode_witness_table ref=DecodeProtocol.req1:0x1041d7970 result=thunk-to-0x101a2220c]
    // This body is emitted TWICE — 0x101a373ac (412 instr) and 0x101a5bdb4 (416 instr), both
    // NOT_IN_TRIE, consistent with `fileprivate`. Both carry the identical guard.
    fileprivate func doDecode(packet: Packet) {
        guard let corePacket = packet.corePacket else {
            return
        }
        if packet.isKeyFrame, packet.assetTrack!.mediaType != .subtitle {
            let seconds = packet.seconds
            let diff = seconds - lastPacketSeconds
            if lastPacketSeconds < 0 || diff < 0 {
                bitrate = 0
                lastPacketBytes = 0
                lastPacketSeconds = seconds
            } else if diff > 1 {
                bitrate = Int(Double(lastPacketBytes) / diff)
                lastPacketBytes = 0
                lastPacketSeconds = seconds
            }
        }
        lastPacketBytes += Int64(packet.size)
        let decoder = decoderMap.value(for: packet.assetTrack!.trackID, default: makeDecode(assetTrack: packet.assetTrack!))
//        var startTime = CACurrentMediaTime()
        decoder.decodeFrame(from: corePacket) { [weak self] result in
            guard let self else {
                return
            }
            do {
//                if packet.assetTrack!.mediaType == .video {
//                    print("[video] decode time: \(CACurrentMediaTime()-startTime)")
//                    startTime = CACurrentMediaTime()
//                }
                let frame = try result.get()
                if self.state == .flush || self.state == .closed {
                    return
                }
                if self.seekTime > 0 {
                    let timestamp = frame.timestamp + frame.duration
//                    KSLog("seektime \(self.seekTime), frame \(frame.seconds), mediaType \(packet.assetTrack!.mediaType)")
                    if timestamp <= 0 || frame.timebase.cmtime(for: timestamp).seconds < self.seekTime {
                        return
                    } else {
                        self.seekTime = 0.0
                    }
                }
                if let frame = frame as? Frame {
                    self.outputRenderQueue.push(frame)
                    self.outputRenderQueue.fps = packet.assetTrack!.nominalFrameRate
                }
            } catch {
                KSLog("Decoder did Failed : \(error)")
                if decoder is VideoToolboxDecode {
                    decoder.shutdown()
                    self.decoderMap[packet.assetTrack!.trackID] = FFmpegDecode(assetTrack: packet.assetTrack!, options: self.options)
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
    // ⚑[tool=field_surface ref=AsyncPlayerItemTrack.decodeTask:idx1 result=NSBlockOperation?] Forward's
    //   record names this field `decodeTask` (was `decodeOperation`); `!` and `?` mangle alike.
    private var decodeTask: BlockOperation!
    // 无缝播放使用的PacketQueue
    private var loopPacketQueue: CircularBuffer<Packet>?
    var packetQueue = CircularBuffer<Packet>()
    override var packetCount: UInt { packetQueue.count }
    // Forward 0x101a5d0bc: UInt adds (overflow-checked) of packetQueue, loopPacketQueue and outputRenderQueue
    // counts, converted once, over fps read directly.
    override var loadedTime: TimeInterval {
        TimeInterval(packetQueue.count + (loopPacketQueue?.count ?? 0) + outputRenderQueue.count) / TimeInterval(fps)
    }

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
                    if decodeTask.isFinished {
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
        decodeTask = BlockOperation { [weak self] in
            guard let self else { return }
            Thread.current.name = self.operationQueue.name
            Thread.current.stackSize = KSOptions.stackSize
            self.decodeThread()
        }
        decodeTask.queuePriority = .veryHigh
        decodeTask.qualityOfService = .userInteractive
        operationQueue.addOperation(decodeTask)
    }

    private func decodeThread() {
        state = .decoding
        isEndOfFile = false
        decoderMap.values.forEach { $0.decode() }
        outerLoop: while !decodeTask.isCancelled {
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

    // Forward 0x101a5db0c: retain packetQueue, call its seek(seconds:needKeyFrame:) (0x101a5a9d4), release.
    override func seekCache(time: TimeInterval, needKeyFrame: Bool) -> (UInt, TimeInterval)? {
        packetQueue.seek(seconds: time, needKeyFrame: needKeyFrame)
    }

    // Forward 0x101a5db74 (override-table entry 9): seekTime (options+0x71 isAccurateSeek, fcsel), isLoopModel(+0x60)
    // = false then its didSet 0x101a5d1bc, state(+0x28) = .flush, outputRenderQueue(+0x58).flush() 0x101a17ac4,
    // then packetQueue(+0xa0).update(headIndex:) inlined (CircularBuffer F28). No isEndOfFile / isNeedKeyFrame store.
    override func updateCache(headIndex: UInt, time: TimeInterval) {
        if options.isAccurateSeek {
            seekTime = time
        } else {
            seekTime = 0
        }
        isLoopModel = false
        state = .flush
        outputRenderQueue.flush()
        packetQueue.update(headIndex: headIndex)
    }

    override func seek(time: TimeInterval) {
        if decodeTask.isFinished {
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

// Class-bound: Forward putPacket 0x101a5bab4 / shutdown 0x101a5bc34 walk decoderMap values with a 0x10
// stride and use swift_getObjectType + swift_unknownObjectRetain/Release (16-byte class existential), not the
// 40-byte opaque-existential box helpers.
protocol DecodeProtocol: AnyObject {
    func decode()
    // THE REQUIREMENT TAKES A RAW AVPacket POINTER, NOT `Packet`. All three conformers agree, and
    // each exports its own method descriptor (`…Tq`):
    //   $s8KSPlayer12FFmpegDecodeC11decodeFrame4from17completionHandlerySpySo8AVPacketVG_…  0x101a2220c
    //   $s8KSPlayer14SubtitleDecodeC11decodeFrame4from17completionHandlerySpySo8AVPacketVG_… 0x101a69de8
    //   $s8KSPlayer18VideoToolboxDecodeC11decodeFrame4from17completionHandlerySpySo8AVPacketVG_… 0x101a6ce44
    // `SpySo8AVPacketVG` is `UnsafeMutablePointer<AVPacket>`. Dispatch is through the witness
    // table at requirement index 1, whose slot in each of the three conformances is a branch
    // island to exactly those addresses.
    // ⚑[tool=decode_witness_table ref=SubtitleDecode:DecodeProtocol:0x1041d93f8 result=req1-thunk-0x101a69de8]
    // ⚑[tool=decode_witness_table ref=VideoToolboxDecode:DecodeProtocol:0x1041d95c8 result=req1-thunk-0x101a6ce44]
    // Proof it is a pointer and not the class, from FFmpegDecode's body: the parameter register
    // x24 never reaches an ARC helper, `[x24]` (the isa word) is never read, and the only offset
    // dereferenced out of it is 0x28 — masked with bit 0 and tested at bit 2, i.e. the
    // AV_PKT_FLAG_KEY / AV_PKT_FLAG_DISCARD bits of `flags`. `Packet.size` also sits at 0x28, so
    // the offset alone is ambiguous; the flag masks and the absent ARC traffic are what settle it.
    func decodeFrame(from packet: UnsafeMutablePointer<AVPacket>, completionHandler: @escaping (Result<MEFrame, Error>) -> Void)
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
                   let decode = VideoToolboxDecode(assetTrack: assetTrack, options: options, asynchronous: true)
                {
                    return decode
                } else {
                    return FFmpegDecode(assetTrack: assetTrack, options: options)
                }
            }
        }
    }
}
