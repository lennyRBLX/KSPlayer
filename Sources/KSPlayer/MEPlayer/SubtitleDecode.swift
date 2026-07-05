//
//  SubtitleDecode.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/11.
//

import CoreGraphics
import Foundation
import Libavformat
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// SubtitleDecode @0x1039f0530 — Forward 1.3.17. 10 stored fields (reflection-authoritative), types §8.3/§8.6.
// The recon's VideoSwresample `scale` bitmap path is GONE — the binary uses the ASS-image pipeline
// (assImageRenderer/pendingASSImageSubtitles); +assetTrack/isASS/fontsDir/subtitleHeader. Bodies → P4 M2.
class SubtitleDecode: DecodeProtocol {
    private var assImageRenderer: AssIncrementImageRenderer?
    private var codecContext: UnsafeMutablePointer<AVCodecContext>?
    private var subtitle: AVSubtitle = AVSubtitle()
    private var startTime: Double = 0
    private var assParse: AssParse?
    private var assetTrack: FFmpegAssetTrack
    private var isASS: Bool = false
    private var fontsDir: String?
    private var subtitleHeader: String?
    private var pendingASSImageSubtitles: [(subtitle: String, start: Double, duration: Double)] = [] // §8.6
    // ⚑ init shape inferred → M2 witness-verify (real init builds the codec ctx + ASS parse from assetTrack)
    required init(assetTrack: FFmpegAssetTrack, options _: KSOptions) {
        self.assetTrack = assetTrack
    }

    // ⚑ UNRESOLVED → P4 M2: the ASS-image decode pipeline (decodeFrame → SubtitlePart via render:Either)
    func decode() {}
    func decodeFrame(from _: Packet, completionHandler _: @escaping (Result<MEFrame, Error>) -> Void) {}
    func doFlushCodec() {}
    func shutdown() {}
}
