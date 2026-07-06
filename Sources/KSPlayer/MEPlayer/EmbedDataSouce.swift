//
//  EmbedDataSouce.swift
//  KSPlayer-7de52535
//
//  Created by kintan on 2018/8/7.
//
import Foundation
import Libavcodec
import Libavutil

extension FFmpegAssetTrack: SubtitleInfo {
    public var subtitleID: String {
        String(trackID)
    }
}

// ⚑ BINARY-ABSENT (§3): FFmpegAssetTrack: KSSubtitleProtocol is NOT in Forward (proto 0x1039f18a0 __swift5_proto
//   reverse-walk = NONE). This whole EmbedDataSouce file is the pre-migration typo'd leftover flagged for separate
//   reconciliation (§3). The signature is bridged to the async KSSubtitleProtocol requirement (session 21) ONLY to
//   keep the target compiling under the P55 migration; the body is NOT binary-verified.
extension FFmpegAssetTrack: KSSubtitleProtocol {
    public func search(with query: KSSubtitleQuery) async -> [SubtitlePart] {
        let time = query.time
        return subtitle?.outputRenderQueue.search { item -> Bool in
            item.part == time
        }.map(\.part) ?? []
    }
}

extension KSMEPlayer: SubtitleDataSource {
    public var infos: [any SubtitleInfo] {
        tracks(mediaType: .subtitle).compactMap { $0 as? (any SubtitleInfo) }
    }
}
