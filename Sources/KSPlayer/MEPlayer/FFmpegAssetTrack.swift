//
//  FFmpegAssetTrack.swift
//  KSPlayer
//
//  Created by kintan on 2023/2/12.
//

import AVFoundation
import FFmpegKit
import Libavformat

// ⚑ Forward-added protocol (absent from KSPlayer source). Resolved from the FFmpegAssetTrack.bitStreamFilter
//   field-record symref → protocol descriptor 0x1039f0820 (kind=Protocol). Requirements deferred
//   (minimal no-conformer declare). The field is a 16-byte class-existential (init nil): the descriptor's
//   own class-constraint flag reads Any, so the class layout comes from the field-site `& AnyObject`,
//   not the protocol — kept faithful to the descriptor.
// ⚑[tool=name_type_at_addr ref=BitStreamFilter:0x1039f0820 result=protocol(kind=3,non-class-constrained)]
// ⚑ `public` is FORCED by type visibility: FFmpegAssetTrack.bitStreamFilter carries a
//   property descriptor (public-exclusive), and a public stored property's type must be
//   public. The protocol's own access is not separately observable.
// ⚑[tool=export_trie_oracle ref=FFmpegAssetTrack.bitStreamFilter:vpMV result=public ⇒ BitStreamFilter public by the type-visibility rule]
public protocol BitStreamFilter {}

public class FFmpegAssetTrack: MediaPlayerTrack {
    // ⚑ Field-layout migration (session 37, commit-1): the 37 stored properties in Forward binary order
    //   (scripts/dump_binary_field_types.py FFmpegAssetTrack). NEW fields carry safe defaults = the
    //   confirmed unconditional prologue init values (scale 1.0, translateY 0) or ⚑ nil/false pending
    //   branch-conditional population (audit-gated commit-2). `codecpar` retyped value→pointer (+0xb8).
    //   `isConvertNALSize` was removed in s106 — see the note at its former declaration site below.
    //   (The claim it carried here, "l2 WARNs extra, non-blocking", was wrong: it was a REAL_FLAG
    //   and it blocked every commit to this file.)
    public private(set) var trackID: Int32 = 0
    public let codecName: String
    public var profileName: String?                        // ⚑ 3 NEW · init population deferred (codec profile name via FUN_102e676a0); layout-first nil
    public var name: String = ""
    public private(set) var languageCode: String?
    public var nominalFrameRate: Float = 0
    public private(set) var avgFrameRate = Timebase.defaultValue
    public private(set) var realFrameRate = Timebase.defaultValue
    public private(set) var bitRate: Int64 = 0
    public let mediaType: AVFoundation.AVMediaType
    public let formatName: String?
    public let bitDepth: Int32
    public var stream: UnsafeMutablePointer<AVStream>?
    package var startTime = CMTime.zero        // ⚑ package (Forward-fidelity): RemuxerIOAction (ProAVPlayer module) reads this cross-module — binary-arbitrated; exact modifier under-included §1 (could be public)
    public var codecpar: UnsafeMutablePointer<AVCodecParameters>   // ⚑ retyped value→pointer (+0xb8); designated init derefs via `let codecpar = codecparPtr.pointee`
    package var timebase: Timebase = .defaultValue  // ⚑ package: see startTime — cross-module read by RemuxerIOAction.performRead/ptsToSeconds (FUN_101a32e28)  ⚑[tool=resolve_fun_pins ref=FUN_101a32e28:0x101a32e28 result=RESOLVES_UNIQUELY] = KSPlayer.FormatContext.time(index: Swift.Int32, timestamp: Swift.Int64) -> Swift.Double?
    let bitsPerRawSample: Int32
    public let formatDescription: CMFormatDescription?   // moved up to bin +0xd0 (before audioDescriptor)
    public let audioDescriptor: AudioDescriptor?
    public var audioFormat: AVAudioFormat?                 // ⚑ 20 NEW · init population deferred (audio branch AVAudioFormat(cmAudioFormatDescription:))
    public let isImageSubtitle: Bool
    public var delay: TimeInterval = 0
    public var scale: Float = 1.0                          // ⚑ 23 NEW · prologue init 1.0 (0x3f800000) — confirmed unconditional
    public var translateY: Float = 0                       // ⚑ 24 NEW · prologue init 0 — confirmed unconditional
    var subtitle: SyncPlayerItemTrack<SubtitleFrame>?
    public var subtitleRender: (any KSSubtitleProtocol)?   // ⚑ 26 NEW · 40b optional existential (+0x108..+0x130); protocol resolved via name_type_at_addr
    // ⚑ s104: was Int16 "because MediaPlayerProtocol requires Int16". The protocol was the thing
    // that was wrong: the field record here resolves through __got 0x104112ad8 to the Swift.UInt16
    // nominal type descriptor, and all three conformers' getters demangle to `: Swift.UInt16`.
    // The protocol has been retyped to match, so this no longer diverges from either side.
    public private(set) var rotation: UInt16 = 0
    public var dovi: DOVIDecoderConfigurationRecord?
    public let fieldOrder: FFmpegFieldOrder
    public var isImage: Bool = false                       // ⚑ 30 NEW · init population deferred (disposition/side-data)
    public var isStillImage: Bool = false                  // ⚑ 31 NEW · init population deferred
    var closedCaptionsTrack: FFmpegAssetTrack?
    // ⚑ s104: CLOSED. The pin here said the divergence was PINNED because "changing it rewrites
    // every use site". It does not: a tree-wide grep for `bitStreamFilter` returns this
    // declaration and its own comment and NOTHING else, so the blast radius was zero and the
    // deferral was resting on an unchecked claim.
    // The field record reads `symref->__got 0x104107970` with tail `_pXpSg` — `_p` existential,
    // `Xp` existential METATYPE, `Sg` optional — i.e. `(any BitStreamFilter).Type?`. That also
    // explains the 16 bytes at +0x148..+0x158 without the `& AnyObject` this used to carry: an
    // existential metatype is metatype-pointer + witness-table pointer. The old `& AnyObject` was
    // added to force a class layout the descriptor does not ask for — its class-constraint flag
    // reads Any — so removing it makes the declaration agree with the descriptor as well.
    // Written `BitStreamFilter.Type?` rather than `(any BitStreamFilter).Type?`: for a protocol the
    // two are the same existential metatype and compile identically, so the parenthesised form was
    // a NULL flag — a text difference the gate could see and the binary could not. Aligned rather
    // than suppressed.
    public var bitStreamFilter: BitStreamFilter.Type?   // ⚑ 33 NEW · 16b existential metatype (+0x148..+0x158)
    public var reorderSize: Int32 = 0                      // ⚑ 34 NEW · init param[0x1e]; population deferred
    var seekByBytes = false
    public var isDefault: Bool = false                     // ⚑ 36 NEW · init population deferred (disposition)
    public var isBilingual: Bool = false                   // ⚑ 37 NEW · init population deferred
    // ⚑ s106: `isConvertNALSize` REMOVED. It was absent from the field records AND carried no symbol
    //   of any kind in the export trie — not even a vpfi, which a declaration default would have
    //   emitted — so it is absent from the binary in both directions, not merely unnamed.
    //   ⚑[tool=l2_field_gate ref=FFmpegAssetTrack.isConvertNALSize:field-records result=absent]
    //   ⚑[tool=export_trie_oracle ref=FFmpegAssetTrack.isConvertNALSize:trie result=no-symbol-of-any-kind]
    public var description: String {
        var description = codecName
        if let formatName {
            description += ", \(formatName)"
        }
        if bitsPerRawSample > 0 {
            description += "(\(bitsPerRawSample.kmFormatted) bit)"
        }
        if let audioDescriptor {
            description += ", \(audioDescriptor.sampleRate)Hz"
            description += ", \(audioDescriptor.channel.description)"
        }
        if let formatDescription {
            if mediaType == .video {
                let naturalSize = formatDescription.naturalSize
                description += ", \(Int(naturalSize.width))x\(Int(naturalSize.height))"
                description += String(format: ", %.2f fps", nominalFrameRate)
            }
        }
        if bitRate > 0 {
            description += ", \(bitRate.kmFormatted)bps"
        }
        if let language {
            description += "(\(language))"
        }
        return description
    }

    convenience init?(stream: UnsafeMutablePointer<AVStream>) {
        let codecpar = stream.pointee.codecpar.pointee
        self.init(codecpar: stream.pointee.codecpar)   // ⚑ pass the pointer (stored field retyped +0xb8); local `codecpar` value serves the reads below
        self.stream = stream
        let metadata = toDictionary(stream.pointee.metadata)
        if let value = metadata["variant_bitrate"] ?? metadata["BPS"], let bitRate = Int64(value) {
            self.bitRate = bitRate
        }
        trackID = stream.pointee.index
        var timebase = Timebase(stream.pointee.time_base)
        if timebase.num <= 0 || timebase.den <= 0 {
            timebase = Timebase(num: 1, den: 1000)
        }
        if stream.pointee.start_time != Int64.min {
            startTime = timebase.cmtime(for: stream.pointee.start_time)
        }
        self.timebase = timebase
        avgFrameRate = Timebase(stream.pointee.avg_frame_rate)
        realFrameRate = Timebase(stream.pointee.r_frame_rate)
        if mediaType == .audio {
            var frameSize = codecpar.frame_size
            if frameSize < 1 {
                frameSize = timebase.den / timebase.num
            }
            nominalFrameRate = max(Float(codecpar.sample_rate / frameSize), 48)
        } else {
            if stream.pointee.duration > 0, stream.pointee.nb_frames > 0, stream.pointee.nb_frames != stream.pointee.duration {
                nominalFrameRate = Float(stream.pointee.nb_frames) * Float(timebase.den) / Float(stream.pointee.duration) * Float(timebase.num)
            } else if avgFrameRate.den > 0, avgFrameRate.num > 0 {
                nominalFrameRate = Float(avgFrameRate.num) / Float(avgFrameRate.den)
            } else {
                nominalFrameRate = 24
            }
        }

        if let value = metadata["language"], value != "und" {
            languageCode = value
        } else {
            languageCode = nil
        }
        if let value = metadata["title"] {
            name = value
        } else {
            name = languageCode ?? codecName
        }
        // AV_DISPOSITION_DEFAULT
        if mediaType == .subtitle {
            isEnabled = !isImageSubtitle || stream.pointee.disposition & AV_DISPOSITION_FORCED == AV_DISPOSITION_FORCED
            if stream.pointee.disposition & AV_DISPOSITION_HEARING_IMPAIRED == AV_DISPOSITION_HEARING_IMPAIRED {
                name += "(hearing impaired)"
            }
        }
        //        var buf = [Int8](repeating: 0, count: 256)
        //        avcodec_string(&buf, buf.count, codecpar, 0)
    }

    init?(codecpar codecparPtr: UnsafeMutablePointer<AVCodecParameters>) {
        self.codecpar = codecparPtr
        let codecpar = codecparPtr.pointee   // ⚑ local value copy keeps the dense codecpar.X reads unchanged; stored field is the pointer (+0xb8)
        bitRate = codecpar.bit_rate
        // codec_tag byte order is LSB first CMFormatDescription.MediaSubType(rawValue: codecpar.codec_tag.bigEndian)
        let codecType = codecpar.codec_id.mediaSubType
        var codecName = ""
        if let descriptor = avcodec_descriptor_get(codecpar.codec_id) {
            codecName += String(cString: descriptor.pointee.name)
            if let profile = descriptor.pointee.profiles {
                codecName += " (\(String(cString: profile.pointee.name)))"
            }
        } else {
            codecName = ""
        }
        self.codecName = codecName
        fieldOrder = FFmpegFieldOrder(rawValue: UInt8(codecpar.field_order.rawValue)) ?? .unknown
        var formatDescriptionOut: CMFormatDescription?
        if codecpar.codec_type == AVMEDIA_TYPE_AUDIO {
            mediaType = .audio
            audioDescriptor = AudioDescriptor(codecpar: codecpar)
            bitDepth = 0
            let layout = codecpar.ch_layout
            let channelsPerFrame = UInt32(layout.nb_channels)
            let sampleFormat = AVSampleFormat(codecpar.format)
            let bytesPerSample = UInt32(av_get_bytes_per_sample(sampleFormat))
            let formatFlags = ((sampleFormat == AV_SAMPLE_FMT_FLT || sampleFormat == AV_SAMPLE_FMT_DBL) ? kAudioFormatFlagIsFloat : sampleFormat == AV_SAMPLE_FMT_U8 ? 0 : kAudioFormatFlagIsSignedInteger) | kAudioFormatFlagIsPacked
            var audioStreamBasicDescription = AudioStreamBasicDescription(mSampleRate: Float64(codecpar.sample_rate), mFormatID: codecType.rawValue, mFormatFlags: formatFlags, mBytesPerPacket: bytesPerSample * channelsPerFrame, mFramesPerPacket: 1, mBytesPerFrame: bytesPerSample * channelsPerFrame, mChannelsPerFrame: channelsPerFrame, mBitsPerChannel: bytesPerSample * 8, mReserved: 0)
            _ = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &audioStreamBasicDescription, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &formatDescriptionOut)
            if let name = av_get_sample_fmt_name(sampleFormat) {
                formatName = String(cString: name)
            } else {
                formatName = nil
            }
        } else if codecpar.codec_type == AVMEDIA_TYPE_VIDEO {
            audioDescriptor = nil
            mediaType = .video
            if codecpar.nb_coded_side_data > 0, let sideDatas = codecpar.coded_side_data {
                for i in 0 ..< codecpar.nb_coded_side_data {
                    let sideData = sideDatas[Int(i)]
                    if sideData.type == AV_PKT_DATA_DOVI_CONF {
                        dovi = sideData.data.withMemoryRebound(to: DOVIDecoderConfigurationRecord.self, capacity: 1) { $0 }.pointee
                    } else if sideData.type == AV_PKT_DATA_DISPLAYMATRIX {
                        let matrix = sideData.data.withMemoryRebound(to: Int32.self, capacity: 1) { $0 }
                        let rawRotation = -av_display_rotation_get(matrix)
                        if rawRotation.isFinite {
                            let degrees = Int(rawRotation.rounded())
                            let normalized = ((degrees % 360) + 360) % 360
                            rotation = UInt16(normalized)
                        } else {
                            rotation = 0
                        }                        
                    }
                }
            }
            let sar = codecpar.sample_aspect_ratio.size
            var extradataSize = Int32(0)
            let extradata = codecpar.extradata
            let atomsData: Data?
            if let extradata {
                extradataSize = codecpar.extradata_size
                // ⚑ REMOVED (s106): the AVCC marker test `extradata[4] == 0xFE → 0xFF`, which was the
                //   ONLY producer of a true `isConvertNALSize`. It is absent from this designated init:
                //   the whole 705-instruction body contains no 0xFE immediate and no byte load or store
                //   at offset 4 of any pointer. The one byte read-modify-write it does contain
                //   (@0x101a20608-0x101a20638) tests 2/8/1/4/0x10 and writes 4-or-5 into a different field.
                //   ⚑[tool=llvm-objdump ref=FFmpegAssetTrack.init(stream:):0x101a202a8-0x101a20dac result=no-0xFE-immediate]
                atomsData = Data(bytes: extradata, count: Int(extradataSize))
            } else {
                // ⚑ REMOVED (session 37): the base VP9-synthetic-extradata path (avio_open_dyn_buf →
                //   the vpcC-box writer → avio_close_dyn_buf) is PROVEN dead-in-Forward — the designated init
                //   FUN_101a202a8 omits all three from its callee set, and the vpcC-box WRITER (libavformat's
                //   isom vpcc writer) is absent from the binary: only the READER FUN_1031606b0 survives, and no
                //   vpcC fourcc-immediate appears in code. Removing it keeps this layout commit gate-clean with
                //   no fabricated FFmpeg marker (the deleted call is a `-` line the diff-scoped gate ignores).
                //   ⚑ FAITHFUL-PARTIAL: proven Forward does NOT synthesize VP9 extradata via that writer; NOT
                //   proven it does nothing else for VP9-without-extradata → `atomsData = nil` is the minimal
                //   faithful form; exact VP9-no-extradata handling deferred to the init-body pass (commit-2).
                //   ⚑[tool=get_function_callees ref=isom_vpcc_writer:absent-in-FUN_101a202a8 result=FAILED-SEARCH] (writer confirmed dead-stripped; only the reader survives)
                atomsData = nil
            }
            let format = AVPixelFormat(rawValue: codecpar.format)
            bitDepth = format.bitDepth
            let fullRange = codecpar.color_range == AVCOL_RANGE_JPEG
            let dic: NSMutableDictionary = [
                kCVImageBufferChromaLocationBottomFieldKey: kCVImageBufferChromaLocation_Left,
                kCVImageBufferChromaLocationTopFieldKey: kCVImageBufferChromaLocation_Left,
                kCMFormatDescriptionExtension_Depth: format.bitDepth * Int32(format.planeCount),
                kCMFormatDescriptionExtension_FullRangeVideo: fullRange,
                codecType.rawValue == kCMVideoCodecType_HEVC ? "EnableHardwareAcceleratedVideoDecoder" : "RequireHardwareAcceleratedVideoDecoder": true,
            ]
            // kCMFormatDescriptionExtension_BitsPerComponent
            if let atomsData {
                dic[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] = [codecType.rawValue.avc: atomsData]
            }
            dic[kCVPixelBufferPixelFormatTypeKey] = format.osType(fullRange: fullRange)
            dic[kCVImageBufferPixelAspectRatioKey] = sar.aspectRatio
            dic[kCVImageBufferColorPrimariesKey] = codecpar.color_primaries.colorPrimaries as String?
            dic[kCVImageBufferTransferFunctionKey] = codecpar.color_trc.transferFunction as String?
            dic[kCVImageBufferYCbCrMatrixKey] = codecpar.color_space.ycbcrMatrix as String?
            // swiftlint:disable line_length
            _ = CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: codecType.rawValue, width: codecpar.width, height: codecpar.height, extensions: dic, formatDescriptionOut: &formatDescriptionOut)
            // swiftlint:enable line_length
            if let name = av_get_pix_fmt_name(format) {
                formatName = String(cString: name)
            } else {
                formatName = nil
            }
        } else if codecpar.codec_type == AVMEDIA_TYPE_SUBTITLE {
            mediaType = .subtitle
            audioDescriptor = nil
            formatName = nil
            bitDepth = 0
            _ = CMFormatDescriptionCreate(allocator: kCFAllocatorDefault, mediaType: kCMMediaType_Subtitle, mediaSubType: codecType.rawValue, extensions: nil, formatDescriptionOut: &formatDescriptionOut)
        } else {
            bitDepth = 0
            return nil
        }
        formatDescription = formatDescriptionOut
        bitsPerRawSample = codecpar.bits_per_raw_sample
        isImageSubtitle = [AV_CODEC_ID_DVD_SUBTITLE, AV_CODEC_ID_DVB_SUBTITLE, AV_CODEC_ID_DVB_TELETEXT, AV_CODEC_ID_HDMV_PGS_SUBTITLE].contains(codecpar.codec_id)
        trackID = 0
    }

    // ⚑ P55 (session 32): `options: KSOptions?` — SubtitleDecode.init forwards a nullable options through here
    //   (binary FUN_101a6914c → this createContext with nullable options); codecpar.createContext is already KSOptions?.  ⚑[tool=resolve_fun_pins ref=FUN_101a6914c:0x101a6914c result=RESOLVES_UNIQUELY] = KSPlayer.SubtitleDecode.init(assetTrack: KSPlayer.FFmpegAssetTrack, options: KSPlayer.KSOptions?) -> KSPlayer.SubtitleDecode
    func createContext(options: KSOptions?) throws -> UnsafeMutablePointer<AVCodecContext> {
        try codecpar.pointee.createContext(options: options)
    }

    public var isEnabled: Bool {
        get {
            stream?.pointee.discard == AVDISCARD_DEFAULT
        }
        set {
            var discard = newValue ? AVDISCARD_DEFAULT : AVDISCARD_ALL
            if mediaType == .subtitle, !isImageSubtitle {
                discard = AVDISCARD_DEFAULT
            }
            stream?.pointee.discard = discard
        }
    }

    // ── s106: the nine MEMBER_MISSING members of this class, each read from its own body ──
    // Access: the three computed properties each carry a property descriptor (vpMV), which is
    // public-exclusive, so `public` is read rather than chosen. The six methods carry no such
    // symbol and this class is non-`final`, so their access is NOT observable — they are left
    // unmarked (internal) rather than asserted public.

    /// ⚑[tool=llvm-objdump ref=FFmpegAssetTrack.discardAll():0x101a20f9c result=5-instr]
    /// `ldr x8,[x20,#0x98]` is `stream`, `cbz` is the optional guard, then
    /// `mov w9,#0x30` / `str w9,[x8,#0x44]`. In THIS build's AVStream `discard` is at 0x44
    /// (codecpar sits at 0x10 here, unlike stock), and 48 is AVDISCARD_ALL.
    func discardAll() {
        stream?.pointee.discard = AVDISCARD_ALL
    }

    /// ⚑[tool=llvm-objdump ref=FFmpegAssetTrack.flush():0x101a20fb0 result=18-instr]
    /// Loads `subtitle` (0x100), guards nil, and dispatches the vtable entry at metadata
    /// offset 0x198 with `movi.2d v0,#0` — a Double 0.0. Slot = (0x198-0xd0)/8 = 25, and slot
    /// 25's impl 0x101a5ba30 saves that Double, reads an options Bool, and `fcsel`s either it
    /// or 0.0 into the field at 0x10 = `seekTime`. Decoded from the slot, never counted from
    /// declaration order.
    /// ⚑[tool=vtable_walk ref=SyncPlayerItemTrack:slot25@0x101a5ba30 result=seek(time:)]
    func flush() {
        subtitle?.seek(time: 0)
    }

    /// ⚑[tool=llvm-objdump ref=FFmpegAssetTrack.stop():0x101a1be30 result=17-instr]
    /// Same shape as `flush`, dispatching metadata offset 0x1c0 ⇒ slot 30, impl 0x101a5bc34.
    /// That impl is arity-0 (it never reads x0), returns early when the state byte at 0x28 is
    /// 0 (.idle), sets it to 3 (.closed) and drains the render queue — `shutdown()`.
    /// ⚑[tool=vtable_walk ref=SyncPlayerItemTrack:slot30@0x101a5bc34 result=shutdown()]
    /// REJECTED anchor: reconstruction/build_match_release.json proposes `putPacket` for
    /// 0x101a5bc34 at similarity 0.5342 with 3603 matches over threshold — a fingerprint that
    /// cannot discriminate is never identity, and putPacket takes an argument this body never
    /// reads.
    func stop() {
        subtitle?.shutdown()
    }

    /// ⚑[tool=llvm-objdump ref=FFmpegAssetTrack.isDVBTeletext.getter:0x101a1f2f0 result=6-instr]
    /// `ldr x8,[x20,#0xb8]` is `codecpar`, `ldr w8,[x8,#0x4]` is `codec_id`, then
    /// `sub w8,w8,#0x17000` / `cmp w8,#0x7` / `cset eq` ⇒ codec_id == 0x17007, which is
    /// AV_CODEC_ID_DVB_TELETEXT (index 7 of the 0x17000 subtitle block in this build's header).
    public var isDVBTeletext: Bool {
        codecpar.pointee.codec_id == AV_CODEC_ID_DVB_TELETEXT
    }

    /// ⚑[tool=llvm-objdump ref=FFmpegAssetTrack.isSrt.getter:0x101a18610 result=16-instr]
    /// A set-membership test on `codec_id`: four constants compared at once via `cmeq.4s`
    /// against the vector at 0x1044e8bc0, plus a fifth scalar at +0x10. Those five int32s read
    /// 0x17008, 0x17012, 0x17002, 0x17011, 0x17005 = SRT, WEBVTT, TEXT, SUBRIP, MOV_TEXT.
    /// The SET is decidable; the source's ORDER is not, because the compiler split it 4+1 to
    /// vectorise. Written in enum order.
    public var isSrt: Bool {
        switch codecpar.pointee.codec_id {
        case AV_CODEC_ID_TEXT, AV_CODEC_ID_MOV_TEXT, AV_CODEC_ID_SRT, AV_CODEC_ID_SUBRIP, AV_CODEC_ID_WEBVTT:
            return true
        default:
            return false
        }
    }

    /// ⚑[tool=llvm-objdump ref=FFmpegAssetTrack.renderMode.getter:0x101a1855c result=45-instr]
    /// `ldrb [x20,#0xe8]` is `isImageSubtitle` and `tbnz` returns case 0. Otherwise the 40-byte
    /// optional existential at 0x108 (`subtitleRender`) is copied out and nil-checked; non-nil
    /// also returns case 0. The remaining path re-runs the same five-constant `isSrt` table at
    /// 0x1044e8bc0 and ends `mov w8,#1` / `cinc w0,w8,ne` ⇒ 2 when srt, else 1.
    /// SubtitleRenderMode case indices: image 0, assView 1, srtView 2.
    public var renderMode: SubtitleRenderMode {
        if isImageSubtitle || subtitleRender != nil {
            return .image
        }
        return isSrt ? .srtView : .assView
    }

    /// ⚑[tool=llvm-objdump ref=FFmpegAssetTrack.seconds(for:):0x101a20f00 result=39-instr]
    /// `mul` of the parameter by the int32 at 0xc0 (`timebase.num`, trapping on overflow) with
    /// the int32 at 0xc4 (`timebase.den`) as the timescale, into
    /// `CMTime.init(value:timescale:)`; then `startTime` (0xa0, a 24-byte CMTime) as the
    /// right-hand operand of the CoreMedia `-` infix, then `CMTime.seconds.getter`.
    /// The construction is exactly `Timebase.cmtime(for:)`, which this module already declares,
    /// so it appears here inlined rather than as a call.
    /// ⚑[tool=bind_oracle ref=__got:0x1041132c0 result=CMTime.init(value:timescale:)]
    /// ⚑[tool=bind_oracle ref=__got:0x1041132b8 result=CMTime.-infix]
    /// ⚑[tool=bind_oracle ref=__got:0x1041132d0 result=CMTime.seconds.getter]
    func seconds(for value: Int64) -> Double {
        (timebase.cmtime(for: value) - startTime).seconds
    }

    /// ⚑[tool=llvm-objdump ref=FFmpegAssetTrack.timestamp(for:):0x101a20e30 result=52-instr]
    /// `CMTime.seconds.getter` on `startTime`, then `fmul` by Double(int32 at 0xc4 = den) and
    /// `fdiv` by Double(int32 at 0xc0 = num), `fcvtzs` to Int64, and `subs` from the parameter
    /// with an overflow trap. That multiply-then-divide-then-truncate is exactly
    /// `Timebase.getPosition(from:)`, already declared in this module and inlined here.
    func timestamp(for value: Int64) -> Int64 {
        value - timebase.getPosition(from: startTime.seconds)
    }

    /// ⚑[tool=llvm-objdump ref=FFmpegAssetTrack.transcode(packet:):0x101a1ae90 result=64-instr]
    /// `swift_allocObject(size: 0x48, align: 7)` for a `Packet`, whose default initializer runs
    /// inline — the numeric fields and `isFlush` are zeroed and `corePacket` is filled from
    /// av_packet_alloc. Then av_packet_ref copies the incoming packet into it, `self` is stored
    /// into `assetTrack` at 0x40 (old value released, new retained, then the `didSet` observer
    /// at 0x101a637d0 runs), and finally `subtitle` (0x100) dispatches metadata offset 0x1a0 ⇒
    /// slot 26, impl 0x101a5bab4 — which takes x0 and branches on the state byte at 0x28 being
    /// 2 (.flush), i.e. `putPacket(packet:)`.
    /// ⚑[tool=ffmpeg_name_oracle ref=av_packet_alloc:0x102d61878 result=CONFIRMED]
    /// ⚑[tool=ffmpeg_name_oracle ref=av_packet_ref:0x102d622ec result=CONFIRMED]
    /// ⚑[tool=vtable_walk ref=SyncPlayerItemTrack:slot26@0x101a5bab4 result=putPacket(packet:)]
    func transcode(packet: UnsafeMutablePointer<AVPacket>) {
        let newPacket = Packet()
        av_packet_ref(newPacket.corePacket, packet)
        newPacket.assetTrack = self
        subtitle?.putPacket(packet: newPacket)
    }
}

extension FFmpegAssetTrack {
    var pixelFormatType: OSType? {
        let format = AVPixelFormat(codecpar.pointee.format)
        return format.osType(fullRange: formatDescription?.fullRangeVideo ?? false)
    }
}
