//
//  KSPlayerItem.swift
//  Pods
//
//  Created by kintan on 16/5/21.
//
//

import AVFoundation
import Foundation
import MediaPlayer

public class KSPlayerResource: Equatable, Hashable {
    public static func == (lhs: KSPlayerResource, rhs: KSPlayerResource) -> Bool {
        lhs.definitions == rhs.definitions
    }

    public let name: String
    public let definitions: [KSPlayerResourceDefinition]
    public let cover: URL?
    public let subtitleDataSource: (any SubtitleDataSource)?
    public var nowPlayingInfo: KSNowPlayableMetadata?
    public let extinf: [String: String]?
    /**
     Player recource item with url, used to play single difinition video

     - parameter name:      video name
     - parameter url:       video url
     - parameter cover:     video cover, will show before playing, and hide when play
     - parameter subtitleURLs: video subtitles
     */
    public convenience init(url: URL, options: KSOptions = KSOptions(), name: String = "", cover: URL? = nil, subtitleURLs: [URL]? = nil, extinf: [String: String]? = nil) {
        let definition = KSPlayerResourceDefinition(url: url, definition: "", options: options)
        let subtitleDataSource: ConstantURLSubtitleDataSource?
        // 0x101b165fc = KSPlayerResource.__allocating_init(url:options:name:cover:subtitleURLs:extinf:). Its
        // prologue pins the parameter registers exactly as declared here: x0 url → x24, x1 options → x28,
        // x2/x3 name, x4 cover, x5 subtitleURLs → x20, x6 extinf. The guard at 0x101b166cc is a bare
        // `cbz x20` — the optional array's nil test and nothing else. There is no count test and no element
        // load, so the reconstruction's `let first = subtitleURLs.first` was an addition, and the URL handed
        // to the data source is THIS init's own `url`: at 0x101b166f8 the call passes x0 = a value-witness
        // copy of x24 and x1 = x20 (the raw [URL]) into 0x101aa5958. The map moved into that init.
        // ⚑[tool=export_trie_oracle ref=$s8KSPlayer0A8ResourceC3url7options4name5cover12subtitleURLs6extinfAC10Foundation3URLV_AA9KSOptionsCSSALSgSayALGSgSDyS2SGSgtcfC:0x101b165fc result=OWNER_MATCH]
        if let subtitleURLs {
            subtitleDataSource = ConstantURLSubtitleDataSource(url: url, subtitleURLs: subtitleURLs)
        } else {
            subtitleDataSource = nil
        }

        self.init(name: name, definitions: [definition], cover: cover, subtitleDataSource: subtitleDataSource, extinf: extinf)
    }

    /**
     Play resouce with multi definitions

     - parameter name:        video name
     - parameter definitions: video definitions
     - parameter cover:       video cover
     - parameter subtitle:   video subtitle
     */
    public init(name: String, definitions: [KSPlayerResourceDefinition], cover: URL? = nil, subtitleDataSource: (any SubtitleDataSource)? = nil, extinf: [String: String]? = nil) {
        self.name = name
        self.cover = cover
        self.subtitleDataSource = subtitleDataSource
        self.definitions = definitions
        self.extinf = extinf
        nowPlayingInfo = KSNowPlayableMetadata(title: name)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(definitions)
    }
}

extension KSPlayerResource: Identifiable {
    public var id: KSPlayerResource { self }
}

public struct KSPlayerResourceDefinition: Hashable {
    public static func == (lhs: KSPlayerResourceDefinition, rhs: KSPlayerResourceDefinition) -> Bool {
        lhs.url == rhs.url
    }

    public let url: URL
    public let definition: String
    public let options: KSOptions
    public init(url: URL) {
        self.init(url: url, definition: url.lastPathComponent)
    }

    /**
     Video recource item with defination name and specifying options

     - parameter url:        video url
     - parameter definition: url deifination
     - parameter options:    specifying options for the initialization of the AVURLAsset
     */
    public init(url: URL, definition: String, options: KSOptions = KSOptions()) {
        self.url = url
        self.definition = definition
        self.options = options
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

extension KSPlayerResourceDefinition: Identifiable {
    public var id: Self { self }
}

public struct KSNowPlayableMetadata {
    private let mediaType: MPNowPlayingInfoMediaType?
    private let isLiveStream: Bool?
    private let title: String
    private let artist: String?
    private let artwork: MPMediaItemArtwork?
    private let albumArtist: String?
    private let albumTitle: String?
    public var nowPlayingInfo: [String: Any] {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = mediaType?.rawValue
        nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = isLiveStream
        nowPlayingInfo[MPMediaItemPropertyTitle] = title
        nowPlayingInfo[MPMediaItemPropertyArtist] = artist
        if #available(OSX 10.13.2, *) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }
        nowPlayingInfo[MPMediaItemPropertyAlbumArtist] = albumArtist
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = albumTitle
        return nowPlayingInfo
    }

    public init(mediaType: MPNowPlayingInfoMediaType? = nil, isLiveStream: Bool? = nil, title: String, artist: String? = nil,
                artwork: MPMediaItemArtwork? = nil, albumArtist: String? = nil, albumTitle: String? = nil)
    {
        self.mediaType = mediaType
        self.isLiveStream = isLiveStream
        self.title = title
        self.artist = artist
        self.artwork = artwork
        self.albumArtist = albumArtist
        self.albumTitle = albumTitle
    }

    public init(mediaType: MPNowPlayingInfoMediaType? = nil, isLiveStream: Bool? = nil, title: String, artist: String? = nil, image: UIImage, albumArtist: String? = nil, albumTitle: String? = nil) {
        self.mediaType = mediaType
        self.isLiveStream = isLiveStream
        self.title = title
        self.artist = artist
        self.albumArtist = albumArtist
        self.albumTitle = albumTitle
        artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
