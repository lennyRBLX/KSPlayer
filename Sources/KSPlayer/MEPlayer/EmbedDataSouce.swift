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
    // ⚑ L7: Forward 0x101a186a8 → 0x101a186c0 / resume 0x101a189fc. The +0x108 existential (`subtitleRender`)
    //   is copied out and awaited first; a non-empty result is returned as is. Otherwise the queue path runs:
    //   the specialized CircularBuffer.search 0x101a16b54 gets the query ADDRESS (the closure reads `query.time`),
    //   an empty result returns the `[]` literal (release + __swiftEmptyArrayStorage), and a non-empty one goes
    //   through the mutating helper 0x101a18c4c with `query.size` (`ldp d0,d1,[query,#0x8]`, x20 = &parts).
    public func search(with query: KSSubtitleQuery) async -> [SubtitlePart] {
        if let subtitleRender {
            let parts = await subtitleRender.search(with: query)
            if !parts.isEmpty {
                return parts
            }
        }
        var parts = subtitle?.outputRenderQueue.search { item -> Bool in
            item.part == query.time
        }.map(\.part) ?? []
        if parts.isEmpty {
            return []
        }
        parts.adjust(size: query.size)
        return parts
    }
}

extension Array where Element == SubtitlePart {
    /// Forward FUN_101a18c4c (179 insns, NOT IN TRIE: no exported symbol). Placed here by Forward's layout: it sits
    /// between FFmpegAssetTrack.search (0x101a186a8) and KSMEPlayer.infos (0x101a18f68). Callers: this file's
    /// `search` (0x101a18968 / 0x101a18c08) and FFmpegSubtitle.search (0x101a9ff60, 0x101a9f698).
    /// Self in x20 = mutating Array method; `size` in d0/d1. Element stride 0x88 = SubtitlePart.
    /// INFERRED: the name `adjust(size:)` and its label (no symbol); the internal access (a cross-file caller).
    /// - i != 0 and parts[i-1].end == .infinity (`fcmp` vs 0x7ff0000000000000): when parts[i].isEmpty (the inlined
    ///   `.right` tag + `string` count test) or parts[i-1].start < parts[i].start (`fcmp prev,cur; b.pl` skips),
    ///   parts[i-1].end = parts[i].start.
    /// - KSOptions.isResizeImageSubtitle (0x104c63153, beginAccess hoisted out of the loop) and a `.left` render:
    ///   rect scaled lane-wise by size / displaySize (`fdiv v2.2D` then two `fmul`), displaySize = size, and the
    ///   halfword at +0x80 (styleRole, Either tag) stored as 0 = .primary / .left.
    mutating func adjust(size: CGSize) {
        for i in 0 ..< count {
            if i != 0, self[i - 1].end == .infinity, self[i].isEmpty || self[i - 1].start < self[i].start {
                self[i - 1].end = self[i].start
            }
            if KSOptions.isResizeImageSubtitle, case let .left(info) = self[i].render {
                let hZoom = size.width / info.displaySize.width
                let vZoom = size.height / info.displaySize.height
                let rect = CGRect(x: info.rect.origin.x * hZoom, y: info.rect.origin.y * vZoom, width: info.rect.size.width * hZoom, height: info.rect.size.height * vZoom)
                self[i].render = .left(SubtitleImageInfo(rect: rect, source: info.source, displaySize: size, styleRole: .primary))
            }
        }
    }
}

extension KSMEPlayer: SubtitleDataSource {
    public var infos: [any SubtitleInfo] {
        tracks(mediaType: .subtitle).compactMap { $0 as? (any SubtitleInfo) }
    }
}
