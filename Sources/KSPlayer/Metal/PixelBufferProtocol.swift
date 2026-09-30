//
//  PixelBufferProtocol.swift
//  KSPlayer-iOS
//
//  Created by kintan on 2019/12/31.
//

import AVFoundation
import CoreVideo
import Foundation
import Libavutil
import simd
import VideoToolbox
#if canImport(UIKit)
import UIKit
#endif

public protocol PixelBufferProtocol: AnyObject {
    var width: Int { get }
    var height: Int { get }
    var bitDepth: Int32 { get }
    var leftShift: UInt8 { get }
    var planeCount: Int { get }
    var formatDescription: CMVideoFormatDescription? { get }
    var aspectRatio: CGSize { get set }
    var yCbCrMatrix: CFString? { get set }
    var colorPrimaries: CFString? { get set }
    var transferFunction: CFString? { get set }
    var colorspace: CGColorSpace? { get set }
    // s98 — THIS PROTOCOL IS MISSING FOUR REQUIREMENTS, and they are now RECOVERED. The
    // deferral note in Resample.swift called this "a ~12-requirement protocol layer ...
    // unverifiable with current tools (no witness-table verifier)". It IS verifiable, and the
    // gap is exactly four get/set/modify properties (4 x 3 = those 12 slots): the descriptor
    // @0x1039f108c declares 40 requirements and this protocol declares 28.
    //
    // Names, types AND positions, read by walking CVBuffer's witness table 0x1041d9f98 at
    // wt+8*(slot+1): slot 21 holds 0x101a89788, which the trie names
    // `__C.CVBufferRef.hdr10PlusData.getter : Foundation.Data?` outright; slots 26, 29 and 32
    // hold one-instruction thunks branching to 0x101a898c4, 0x101a899a4 and 0x101a89c44 — the
    // getters the trie names displayInfo, contentInfo and ambientViewingEnvironment. Slot 33
    // is independently named ambientViewingEnvironment.setter, corroborating the last one.
    // Exactly four `Data?` get/set/modify properties exist on the CVBufferRef extension and
    // these are they — the set matches the gap with nothing left over. Full order is:
    //   ... colorspace(18-20), hdr10PlusData(21-23), cvPixelBuffer(24), isFullRangeVideo(25),
    //   displayInfo(26-28), contentInfo(29-31), ambientViewingEnvironment(32-34), 5 methods.
    //
    // NOT DECLARED YET: adding them breaks conformance because CVPixelBuffer's extension does
    // not implement them. All four are CVBuffer ATTACHMENT accessors keyed by CoreVideo
    // CFString constants (displayInfo and contentInfo are 3-instruction thunks that load a key
    // from __got 0x1041088e8 / 0x1041088c8 and tail-call the shared helper 0x101a899b0;
    // hdr10PlusData reads its key from 0x1041091a8 and calls 0x10345a9c0). Writing them needs
    // those keys named plus the four setters — that is the remaining work, and it is now a
    // bounded body-reconstruction task rather than an unverifiable one.
    // ⚑[tool=decode_witness_table ref=KSPlayer.PixelBufferProtocol:0x1039f108c result=40-reqs-vs-28]
    var hdr10PlusData: Data? { get set }
    var cvPixelBuffer: CVPixelBuffer? { get }
    var isFullRangeVideo: Bool { get }
    var displayInfo: Data? { get set }
    var contentInfo: Data? { get set }
    var ambientViewingEnvironment: Data? { get set }
    func cgImage() -> CGImage?
    func textures() -> [MTLTexture]
    func widthOfPlane(at planeIndex: Int) -> Int
    func heightOfPlane(at planeIndex: Int) -> Int
    func matche(formatDescription: CMVideoFormatDescription) -> Bool
}

extension PixelBufferProtocol {
    var size: CGSize { CGSize(width: width, height: height) }

    #if !os(tvOS)
    /// INFERRED name: Forward has no trie symbol for this getter. Forward 0x101a88500 (223 insns),
    /// laid out directly after `size` (0x101a884b4). Body read from the disasm: witness reads of
    /// displayInfo (wt+0xd8) and contentInfo (wt+0xf0) → hdr10(displayInfo:contentInfo:opticalOutputScale:)
    /// with 10000 (0x461c4000); else ambientViewingEnvironment (wt+0x108) → iOS 17 availability test →
    /// hlg(ambientViewingEnvironment:) or `.hlg`; else transferFunction (wt+0x80) PQ →
    /// hdr10(minLuminance: 0.1 (0x3dcccccd), maxLuminance: 1000 (0x447a0000), opticalOutputScale: 10000);
    /// HLG → `.hlg` when DynamicRange.availableHDRModes contains tag 2 (.hlg), else the same hdr10.
    var edrMetadata: CAEDRMetadata? {
        if let displayInfo, let contentInfo {
            return CAEDRMetadata.hdr10(displayInfo: displayInfo, contentInfo: contentInfo, opticalOutputScale: 10000)
        }
        if let ambientViewingEnvironment {
            if #available(macOS 14.0, iOS 17.0, *) {
                return CAEDRMetadata.hlg(ambientViewingEnvironment: ambientViewingEnvironment)
            }
            return CAEDRMetadata.hlg
        }
        if transferFunction == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ {
            return CAEDRMetadata.hdr10(minLuminance: 0.1, maxLuminance: 1000, opticalOutputScale: 10000)
        }
        if transferFunction == kCVImageBufferTransferFunction_ITU_R_2100_HLG {
            if DynamicRange.availableHDRModes.contains(.hlg) {
                return CAEDRMetadata.hlg
            }
            return CAEDRMetadata.hdr10(minLuminance: 0.1, maxLuminance: 1000, opticalOutputScale: 10000)
        }
        return nil
    }
    #endif

    // INFERRED name: Forward 0x101a88b68 (KSPlayer/PixelBufferProtocol.swift, no trie symbol) is a
    // protocol-extension method — self x20, dovi x0/x1, Self metadata x2, witness table x3 — laid out
    // after edrMetadata (0x101a88500); CVBuffer specialization 0x101a6c9ec. Witness reads:
    // transferFunction get/set wt+0x80/+0x88, colorPrimaries get wt+0x68, colorspace get/set wt+0x98/+0xa0;
    // KSOptions.colorSpace(colorPrimaries:transferFunction:dovi:) 0x1019c6878; the dovi fallbacks inline
    // CGColorSpaceCreateWithName(kCGColorSpaceITUR_2100_PQ / _HLG) keyed on dv_bl_signal_compatibility_id
    // (x0 byte 7: < 2 → PQ, == 4 → HLG).
    func configureColorSpace(dovi: DOVIDecoderConfigurationRecord?) { // INFERRED
        if transferFunction == nil, let dovi {
            switch dovi.dv_bl_signal_compatibility_id {
            case 0, 1:
                transferFunction = kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ
            case 4:
                transferFunction = kCVImageBufferTransferFunction_ITU_R_2100_HLG
            default:
                break
            }
        }
        if let colorPrimaries {
            colorspace = KSOptions.colorSpace(colorPrimaries: colorPrimaries, transferFunction: transferFunction, dovi: dovi)
        }
        if colorspace == nil, let dovi {
            switch dovi.dv_bl_signal_compatibility_id {
            case 0, 1:
                colorspace = KSOptions.colorSpace2020PQ
            case 4:
                colorspace = KSOptions.colorSpace2020HLG
            default:
                break
            }
        }
    }
}

extension CVPixelBuffer: PixelBufferProtocol {
    // The four HDR-attachment properties, all read from CVBuffer attachments and differing only
    // in their key. Shape read from the binary: the getter is CVBufferGetAttachment(self, key,
    // nil), a nil test, a retain, then a conditional cast to Data; the setter bridges Data to
    // NSData and calls CVBufferSetAttachment(self, key, value, mode) with mode immediate
    // `mov w3, #0x1` = .shouldPropagate.
    //
    // displayInfo and contentInfo are 3-instruction thunks that load their key from __got and
    // tail-call one shared getter at 0x101a899b0; the bind table names those two slots
    // _kCVImageBufferMasteringDisplayColorVolumeKey (0x1041088e8) and
    // _kCVImageBufferContentLightLevelInfoKey (0x1041088c8), and hdr10PlusData's key slot
    // (0x1041091a8) _kCMSampleAttachmentKey_HDR10PlusPerFrameData.
    //
    // ambientViewingEnvironment is the odd one out: its key is not a CoreVideo constant but a
    // Swift string literal bridged to NSString — the 25-char "AmbientViewingEnvironment",
    // decoded at the adrp+add result 0x103d39fe0. (Decoding at the biased register value
    // 0x103d39fc0 instead yields 'nCreateForImageBuffer ...', which is the nativeBias trap.)
    private func hdrAttachment(_ key: CFString) -> Data? {
        CVBufferGetAttachment(self, key, nil)?.takeUnretainedValue() as? Data
    }

    private func setHDRAttachment(_ key: CFString, _ newValue: Data?) {
        if let newValue {
            CVBufferSetAttachment(self, key, newValue as NSData, .shouldPropagate)
        }
    }

    public var hdr10PlusData: Data? {
        // Forward 0x101a89788: the attachment is fetched and cast to Data, the result is released
        // on success, and the getter returns nil on every path.
        get {
            _ = CVBufferGetAttachment(self, kCMSampleAttachmentKey_HDR10PlusPerFrameData, nil)?.takeUnretainedValue() as? Data
            return nil
        }
        set { setHDRAttachment(kCMSampleAttachmentKey_HDR10PlusPerFrameData, newValue) }
    }

    public var displayInfo: Data? {
        get { hdrAttachment(kCVImageBufferMasteringDisplayColorVolumeKey) }
        set { setHDRAttachment(kCVImageBufferMasteringDisplayColorVolumeKey, newValue) }
    }

    public var contentInfo: Data? {
        get { hdrAttachment(kCVImageBufferContentLightLevelInfoKey) }
        set { setHDRAttachment(kCVImageBufferContentLightLevelInfoKey, newValue) }
    }

    public var ambientViewingEnvironment: Data? {
        // Forward releases the bridged key right after CVBufferGetAttachment, before the nil test.
        get {
            let value = CVBufferGetAttachment(self, "AmbientViewingEnvironment" as CFString, nil)
            return value?.takeUnretainedValue() as? Data
        }
        // Forward tests newValue for nil before bridging the key.
        set {
            if let newValue {
                CVBufferSetAttachment(self, "AmbientViewingEnvironment" as CFString, newValue as NSData, .shouldPropagate)
            }
        }
    }

    public var leftShift: UInt8 { 0 }
    public var cvPixelBuffer: CVPixelBuffer? { self }
    public var width: Int { CVPixelBufferGetWidth(self) }
    public var height: Int { CVPixelBufferGetHeight(self) }
    public var aspectRatio: CGSize {
        get {
            if let ratio = CVBufferGetAttachment(self, kCVImageBufferPixelAspectRatioKey, nil)?.takeUnretainedValue() as? NSDictionary,
               let horizontal = (ratio[kCVImageBufferPixelAspectRatioHorizontalSpacingKey] as? NSNumber)?.intValue,
               let vertical = (ratio[kCVImageBufferPixelAspectRatioVerticalSpacingKey] as? NSNumber)?.intValue,
               horizontal > 0, vertical > 0
            {
                return CGSize(width: horizontal, height: vertical)
            } else {
                return CGSize(width: 1, height: 1)
            }
        }
        set {
            if let aspectRatio = newValue.aspectRatio {
                CVBufferSetAttachment(self, kCVImageBufferPixelAspectRatioKey, aspectRatio, .shouldPropagate)
            }
        }
    }

    var isPlanar: Bool { CVPixelBufferIsPlanar(self) }

    public var planeCount: Int { isPlanar ? CVPixelBufferGetPlaneCount(self) : 1 }
    public var formatDescription: CMVideoFormatDescription? {
        var formatDescription: CMVideoFormatDescription?
        let err = CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: self, formatDescriptionOut: &formatDescription)
        if err != noErr {
            KSLog("Error at CMVideoFormatDescriptionCreateForImageBuffer \(err)", line: 144)
        }
        return formatDescription
    }

    public var isFullRangeVideo: Bool {
        CVBufferGetAttachment(self, kCMFormatDescriptionExtension_FullRangeVideo, nil)?.takeUnretainedValue() as? Bool ?? false
    }

    public var attachmentsDic: CFDictionary? {
        CVBufferGetAttachments(self, .shouldPropagate)
    }

    public var yCbCrMatrix: CFString? {
        get {
            CVBufferGetAttachment(self, kCVImageBufferYCbCrMatrixKey, nil)?.takeUnretainedValue() as? NSString
        }
        set {
            if let newValue {
                CVBufferSetAttachment(self, kCVImageBufferYCbCrMatrixKey, newValue, .shouldPropagate)
            }
        }
    }

    public var colorPrimaries: CFString? {
        get {
            CVBufferGetAttachment(self, kCVImageBufferColorPrimariesKey, nil)?.takeUnretainedValue() as? NSString
        }
        set {
            if let newValue {
                CVBufferSetAttachment(self, kCVImageBufferColorPrimariesKey, newValue, .shouldPropagate)
            }
        }
    }

    public var transferFunction: CFString? {
        get {
            CVBufferGetAttachment(self, kCVImageBufferTransferFunctionKey, nil)?.takeUnretainedValue() as? NSString
        }
        set {
            if let newValue {
                CVBufferSetAttachment(self, kCVImageBufferTransferFunctionKey, newValue, .shouldPropagate)
            }
        }
    }

    public var colorspace: CGColorSpace? {
        // Forward 0x101a896bc: CVBufferGetAttachment(kCVImageBufferCGColorSpaceKey) → nil test →
        // retain → unconditional cast to CGColorSpace; no platform split.
        get {
            CVBufferGetAttachment(self, kCVImageBufferCGColorSpaceKey, nil).map { $0.takeUnretainedValue() as! CGColorSpace }
        }
        set {
            if let newValue {
                CVBufferSetAttachment(self, kCVImageBufferCGColorSpaceKey, newValue, .shouldPropagate)
            }
        }
    }

    public var bitDepth: Int32 {
        CVPixelBufferGetPixelFormatType(self).bitDepth
    }

    public func cgImage() -> CGImage? {
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(self, options: nil, imageOut: &cgImage)
        return cgImage
    }

    public func widthOfPlane(at planeIndex: Int) -> Int {
        CVPixelBufferGetWidthOfPlane(self, planeIndex)
    }

    public func heightOfPlane(at planeIndex: Int) -> Int {
        CVPixelBufferGetHeightOfPlane(self, planeIndex)
    }

    func baseAddressOfPlane(at planeIndex: Int) -> UnsafeMutableRawPointer? {
        CVPixelBufferGetBaseAddressOfPlane(self, planeIndex)
    }

    public func textures() -> [MTLTexture] {
        MetalRender.texture(pixelBuffer: self)
    }

    public func matche(formatDescription: CMVideoFormatDescription) -> Bool {
        CMVideoFormatDescriptionMatchesImageBuffer(formatDescription, imageBuffer: self)
    }
}

class PixelBuffer: PixelBufferProtocol {
    let bitDepth: Int32
    let width: Int
    let height: Int
    let planeCount: Int
    var aspectRatio: CGSize

    var cvPixelBuffer: CVPixelBuffer? { nil }
    let leftShift: UInt8
    let isFullRangeVideo: Bool
    // ⚑ Forward-added HDR side-data field (binary PixelBuffer @+0x48; init @0x101a8a318 sets an empty
    // default). Reflection field-record is symbolic/unmapped → type inferred `Data` from the 16-byte
    // field size + empty-Data init default (sibling Resample.hdr10PlusData is `Data?`; layout-identical).
    var hdr10PlusData: Data?   // field record carries `Sg` — Data?, not a non-optional Data()
    var colorPrimaries: CFString?
    var transferFunction: CFString?
    var yCbCrMatrix: CFString?
    var colorspace: CGColorSpace?
    var formatDescription: CMFormatDescription? = nil // ⚑ binary field-record is CMFormatDescription? (CMVideoFormatDescription is a CoreMedia alias of the same type); resolves the l2 TYPE MISMATCH
    private let format: AVPixelFormat
    private let formats: [MTLPixelFormat]
    private let widths: [Int]
    private let heights: [Int]
    private let buffers: [MTLBuffer?]
    private let lineSize: [Int]
    // ⚑ Forward-added trailing HDR side-data fields (binary PixelBuffer @+0xb0/+0xc0/+0xd0; init
    // @0x101a8a318 sets empty defaults). Reflection symbolic/unmapped → type inferred `Data` (16-byte
    // fields + empty-Data init default). Total instance size 0xe0 (224 B) confirmed vs the binary alloc.
    var displayInfo: Data?   // field record carries `Sg` — Data?, not a non-optional Data()
    var contentInfo: Data?   // field record carries `Sg` — Data?, not a non-optional Data()
    var ambientViewingEnvironment: Data?   // field record carries `Sg` — Data?, not a non-optional Data()

    init(frame: AVFrame) {
        yCbCrMatrix = frame.colorspace.ycbcrMatrix
        colorPrimaries = frame.color_primaries.colorPrimaries
        transferFunction = frame.color_trc.transferFunction
        colorspace = KSOptions.colorSpace(ycbcrMatrix: yCbCrMatrix, transferFunction: transferFunction)
        width = Int(frame.width)
        height = Int(frame.height)
        isFullRangeVideo = frame.color_range == AVCOL_RANGE_JPEG
        aspectRatio = frame.sample_aspect_ratio.size
        format = AVPixelFormat(rawValue: frame.format)
        leftShift = format.leftShift
        bitDepth = format.bitDepth
        planeCount = Int(format.planeCount)
        let desc = av_pix_fmt_desc_get(format)?.pointee
        let chromaW = desc?.log2_chroma_w == 1 ? 2 : 1
        let chromaH = desc?.log2_chroma_h == 1 ? 2 : 1
        switch planeCount {
        case 3:
            widths = [width, width / chromaW, width / chromaW]
            heights = [height, height / chromaH, height / chromaH]
        case 2:
            widths = [width, width / chromaW]
            heights = [height, height / chromaH]
        default:
            widths = [width]
            heights = [height]
        }
        formats = KSOptions.pixelFormat(planeCount: planeCount, bitDepth: bitDepth)
        var buffers = [MTLBuffer?]()
        var lineSize = [Int]()
        let bytes = Array(tuple: frame.data)
        let bytesPerRow = Array(tuple: frame.linesize).compactMap { Int($0) }
        for i in 0 ..< planeCount {
            let alignment = MetalRender.device.minimumLinearTextureAlignment(for: formats[i])
            lineSize.append(bytesPerRow[i].alignment(value: alignment))
            let buffer: MTLBuffer?
            let size = lineSize[i]
            let byteCount = bytesPerRow[i]
            let height = heights[i]
            if byteCount == size {
                buffer = MetalRender.device.makeBuffer(bytes: bytes[i]!, length: height * size)
            } else {
                buffer = MetalRender.device.makeBuffer(length: heights[i] * lineSize[i])
                let contents = buffer?.contents()
                let source = bytes[i]!
                var j = 0
                // 性能 while > stride(from:to:by:) > for in
                while j < height {
                    contents?.advanced(by: j * size).copyMemory(from: source.advanced(by: j * byteCount), byteCount: byteCount)
                    j += 1
                }
            }
            buffers.append(buffer)
        }
        self.lineSize = lineSize
        self.buffers = buffers
    }

    func textures() -> [MTLTexture] {
        MetalRender.textures(formats: formats, widths: widths, heights: heights, buffers: buffers, lineSizes: lineSize)
    }

    func widthOfPlane(at planeIndex: Int) -> Int {
        widths[planeIndex]
    }

    func heightOfPlane(at planeIndex: Int) -> Int {
        heights[planeIndex]
    }

    // Forward 0x101a8acd4 switches on format (+0x80). RGB24 (2), ARGB (0x19) and RGBA (0x1a) give alphaInfo
    // 0 / 4 / 3 (.none / .first / .last). Those three build PointerImagePipeline(rgbData:stride:width:height:alphaInfo:)
    // inline (allocObject 0x34: buffers[0]!.contents(), lineSize[0], width, height, alphaInfo) and call its
    // cgImage() @0x101a8ada4. Every other format takes the VideoSwresample path (lane 19).
    func cgImage() -> CGImage? {
        let alphaInfo: CGImageAlphaInfo
        switch format {
        case AV_PIX_FMT_RGB24:
            alphaInfo = .none
        case AV_PIX_FMT_ARGB:
            alphaInfo = .first
        case AV_PIX_FMT_RGBA:
            alphaInfo = .last
        default:
            let scale = VideoSwresample(dovi: nil)
            let image = scale.transfer(format: format, width: Int32(width), height: Int32(height), data: buffers.map { $0?.contents().assumingMemoryBound(to: UInt8.self) }, linesize: lineSize.map { Int32($0) })?.cgImage()
            scale.shutdown()
            return image
        }
        return PointerImagePipeline(rgbData: buffers[0]!.contents().assumingMemoryBound(to: UInt8.self), stride: lineSize[0], width: width, height: height, alphaInfo: alphaInfo).cgImage()
    }

    public func matche(formatDescription: CMVideoFormatDescription) -> Bool {
        self.formatDescription == formatDescription
    }
}

extension CGSize {
    var aspectRatio: NSDictionary? {
        if width != 0, height != 0, width != height {
            return [kCVImageBufferPixelAspectRatioHorizontalSpacingKey: width,
                    kCVImageBufferPixelAspectRatioVerticalSpacingKey: height]
        } else {
            return nil
        }
    }
}

extension CVBuffer {
    @used func bytesPerRowOfPlane(at: Int) -> Int { CVPixelBufferGetBytesPerRowOfPlane(self, at) }
}

// INFERRED 0x101a8b878 (162 insns, no trie symbol): free func — d0/d1/w0 args, x20 never read. NSMutableDictionary
//   literal (alloc 0x160 = 5 (Any, Any) pairs, key order as written) → CVPixelBufferCreate; status != 0 releases → nil.
//   Callers: MetalPlayView.init(options:) 0x101a5f3e8 and formatDescription didSet 0x101a5e444 (1, 1, 'BGRA').
func makePixelBuffer(width: CGFloat, height: CGFloat, pixelFormatType: OSType) -> CVPixelBuffer? {
    let attributes: NSMutableDictionary = [
        kCVPixelBufferPixelFormatTypeKey: pixelFormatType,
        kCVPixelBufferMetalCompatibilityKey: true,
        kCVPixelBufferWidthKey: width,
        kCVPixelBufferHeightKey: height,
        kCVPixelBufferIOSurfacePropertiesKey: NSDictionary(),
    ]
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(width), Int(height), pixelFormatType, attributes, &pixelBuffer)
    guard status == kCVReturnSuccess else {
        return nil
    }
    return pixelBuffer
}
