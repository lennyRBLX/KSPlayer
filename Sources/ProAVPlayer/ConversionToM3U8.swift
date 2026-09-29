//
//  ConversionToM3U8.swift
//  ProAVPlayer
//
//  P3b M1 (structure) — Forward-new entry that converts a source into local HLS (M3U8) under a
//  temp save dir and hands it to LocalHLSServer. Field types resolved deterministically
//  (field-record + decode_composite + the field-store decompile); method bodies + the real init → M2.
//  Binary: desc=0x1039f5150, vtable=1 (vtable-empty; methods devirtualized → M2 / witness-anchoring).
//

import Foundation
import AVFoundation
@preconcurrency import KSPlayer
#if canImport(UIKit)
import UIKit
#endif

/// Produces the local HLS (master M3U8 + segments) under `videoSaveURL` for `LocalHLSServer` to serve.
/// Forward-new (ProAVPlayer module).
final class ConversionToM3U8: @unchecked Sendable {
    // 2 reflection fields (order = layout). Types: decode_composite + the field-store decompile.
    // ⚑ binary NON-optional (field-record mangle has no `Sg`; FUN_101b6bf88 value-witness-copies a URL
    //   value directly into the field — value type, not Optional). `!` (IUO) is the M1 placeholder-init
    //   stand-in; the real construction (NSTemporaryDirectory temp dir, "m3u8") → M2.
    private let videoSaveURL: URL
    private var localHLSServer: LocalHLSServer? = nil   // optional (mangle `Sg`; init-stored nil)

    /// FUN_101b6be44 — lazy global: NSTemporaryDirectory()/"m3u8".
    static let shared = ConversionToM3U8(videoSaveURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("m3u8"))

    /// FUN_101b6bf88 — stores videoSaveURL (localHLSServer nil) then best-effort wipes the save dir.
    init(videoSaveURL: URL) {
        self.videoSaveURL = videoSaveURL
        try? FileManager.default.removeItem(at: videoSaveURL)
    }

    /// @0x101b6c0bc (nonisolated async; body 0x101b6c180…). Opens the source, builds the ffmpeg HLS muxer options
    /// and the master playlist, starts a ConversionInfo and returns (served url, info).
    /// #file "ProAVPlayer/ConversionToM3U8.swift", KSLog line 208; "task cancell" verbatim.
    func record(url: URL, options: KSOptions) async throws -> (URL, ConversionInfo) {
        let server: LocalHLSServer
        if let localHLSServer {
            server = localHLSServer
        } else {
            server = try LocalHLSServer(rootDirectory: videoSaveURL, port: KSOptions.localHLSServerPort)  // FUN_101b705ec
            localHLSServer = server
        }
        options.formatContextOptions["reconnect_streamed"] = 1                          // KSOptions vtable +0x578 modify
        let formatContext = try FormatContext(url: url, options: options, inFormat: nil) // 0x101a33e78 (P4)
        var formatContextOptions = [String: Any]()
        formatContextOptions["strict"] = "experimental"
        formatContextOptions["hls_flags"] = "delete_segments+append_list+independent_segments"
        // ⚑ Int64-typed values (Swift.Int64 metadata on every store); the /4 is spelled hlsTime (4) — UNSURE.
        let hlsTime: Int64 = 4
        let maxBufferDuration: Double
        if options.isLive == true || formatContext.duration <= 120 || formatContext.fileSize < 1 || KSOptions.maxM3U8FileSize < formatContext.fileSize {
            let bufferDuration: Int64
            if formatContext.bitrate < 9 {                                                // `cmp #9; mov #0x708`
                bufferDuration = 1800
            } else {
                bufferDuration = max(KSOptions.maxM3U8FileSize * 8 / formatContext.bitrate, KSOptions.minM3U8BufferDuration * 2)
            }
            formatContextOptions["hls_list_size"] = bufferDuration / hlsTime
            maxBufferDuration = Double(bufferDuration / 2)
        } else {
            formatContextOptions["hls_list_size"] = Int64(0)
            maxBufferDuration = formatContext.duration
        }
        formatContextOptions["hls_time"] = hlsTime
        formatContextOptions["min_frag_duration"] = hlsTime
        formatContextOptions["hls_segment_type"] = "fmp4"
        formatContextOptions["movflags"] = "empty_moov+frag_keyframe+default_base_moof"
        var masterM3U8 = "#EXTM3U\n"
        let audioTracks = formatContext.assetTracks.filter { $0.mediaType == .audio }
        let audioTrackID = options.wantedAudio(tracks: audioTracks)?.trackID ?? audioTracks.first?.trackID  // vtable +0x6f0
        var audios = Array(audioTracks.enumerated())
        if let audioTrackID, let first = audios.first(where: { $0.element.trackID == audioTrackID }) {
            audios = [first] + audios.filter { $0.element.trackID != audioTrackID }
        }
        let videoTracks = formatContext.assetTracks.filter { $0.mediaType == .video }.sorted { $0.bitRate > $1.bitRate }
        for (index, track) in videoTracks.enumerated() {
            track.isEnabled = index == 0                                                  // FUN_101a1f3a0
        }
        var varStreamMap = ""
        if let videoTrack = videoTracks.first {
            // static [bb, bt, tt, tb] = [3,5,2,4] @0x1044f2a30
            if audioTracks.first?.codecName != "pcm_bluray", formatContext.formatName == "mpegts" || formatContext.formatName == "hls",
               [FFmpegFieldOrder.bb, .bt, .tt, .tb].contains(videoTrack.fieldOrder) {
                formatContextOptions["hls_segment_type"] = nil
            }
            if let dovi = videoTrack.dovi, dovi.dv_profile == 7 {
                formatContextOptions["strict"] = nil
            }
        }
        let isFmp4 = (formatContextOptions["hls_segment_type"] as? String) == "fmp4"
        // ⚑ computed and discarded in Forward (loop @0x101b6d384 breaks, result never read) — UNSURE, kept for shape.
        _ = formatContext.assetTracks.contains { $0.mediaType == .video && $0.dynamicRange != .sdr }
        var hasAudioGroup = false
        if !audioTracks.isEmpty, isFmp4 || audioTracks.count > 1 {
            varStreamMap += "v:0,agroup:audio "
            for (index, track) in audios {
                let audioName = "audio_\(track.trackID)"
                var language = track.languageCode ?? audioName
                if language.isEmpty {
                    language = audioName
                }
                let isDefault = track.trackID == audioTrackID
                let name = trackName(track, tracks: audioTracks)                           // FUN_101b6fcf8
                varStreamMap += "a:" + index.description + ",agroup:audio,language:" + language + ",name:" + audioName
                varStreamMap += isDefault ? ",default:yes " : " "
                masterM3U8 += "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"group_audio\",LANGUAGE=\"\(language)\",NAME=\"\(name)\",CHANNELS=\"\(track.audioFormat?.channelCount ?? 2)\",AUTOSELECT=YES,DEFAULT=\(isDefault ? "YES" : "NO"),URI=\"playlist_\(audioName).m3u8\"\n"  // grow(0x86)
            }
            hasAudioGroup = true
        }
        for track in formatContext.assetTracks where track.mediaType == .subtitle {
            if track.isImageSubtitle {
                track.isEnabled = false
            }
        }
        if !varStreamMap.isEmpty {
            formatContextOptions["var_stream_map"] = varStreamMap
        }
        if let videoTrack = videoTracks.first, let dynamicRange = videoTrack.dynamicRange {
            masterM3U8 += "#EXT-X-STREAM-INF:BANDWIDTH=\(videoTrack.bitRate),AVERAGE-BANDWIDTH=\(videoTrack.bitRate),RESOLUTION=\(videoTrack.naturalSize.string),FRAME-RATE=\(String(format: "%.2f", videoTrack.nominalFrameRate))"  // grow(0x4f)
            if let videoRange = videoTrack.videoRange {
                masterM3U8 += ",VIDEO-RANGE=\(videoRange)"
            }
            if let codecs = videoTrack.codecs, codecs > 1000 {
                // dovi +0x134 dv_profile / +0x139 dv_bl_signal_compatibility_id — switch shape UNSURE
                var supplementalCodecs = ""
                if let dovi = videoTrack.dovi {
                    if dovi.dv_profile == 10, dovi.dv_bl_signal_compatibility_id == 4 {
                        supplementalCodecs = "SUPPLEMENTAL-CODECS=dav1/db4h,"
                    } else if dovi.dv_profile == 8, dovi.dv_bl_signal_compatibility_id == 4 {
                        supplementalCodecs = "SUPPLEMENTAL-CODECS=dvh1/db4h,"
                    } else if dovi.dv_profile == 8, dovi.dv_bl_signal_compatibility_id == 1 {
                        supplementalCodecs = "SUPPLEMENTAL-CODECS=dvh1/db1p,"
                    }
                }
                masterM3U8 += ",\(supplementalCodecs)CODECS=\"\(codecs.string)\""
            }
            if hasAudioGroup {
                masterM3U8 += ",AUDIO=\"group_audio\""
            }
            masterM3U8 += "\nplaylist_0.m3u8\n"
            options.dynamicRange = dynamicRange                                            // vtable +0x778
            if dynamicRange != .sdr, await !UIApplication.isHDRScreen {                    // P3
                await updateVideo(refreshRate: videoTrack.nominalFrameRate, dynamicRange: dynamicRange, options: options)
            }
        }
        let dir = videoSaveURL.appendingPathComponent(Date().description.replacingOccurrences(of: " ", with: "_"))
        let remuxerIOAction = try RemuxerIOAction(formatContext: formatContext, dir: dir, options: options,
                                                  formatContextOptions: formatContextOptions, masterM3U8Context: masterM3U8)
        let m3u8Info = ConversionInfo(server: server, remuxerIOAction: remuxerIOAction, maxBufferDuration: maxBufferDuration)  // FUN_101b6b2a4
        let url = try await m3u8Info.run(startPlayTime: options.startPlayTime)            // 0x101b69598 (P1); vtable +0x358
        KSLog("remote url=" + url.absoluteString, file: "ProAVPlayer/ConversionToM3U8.swift", function: "record(url:options:)", line: 208)
        if Task.isCancelled {
            await m3u8Info.close()                                                         // 0x101b6a22c (P2)
            throw KSPlayerError(code: 0, description: "task cancell")
        }
        return (url, m3u8Info)
    }

    /// FUN_101b70014 — MainActor (record hops to it). Only the KSLog survives; `options` is unused here
    /// (⚑ likely a platform-conditional body). #file line 228. ⚑ member vs free function UNSURE.
    @MainActor private func updateVideo(refreshRate: Float, dynamicRange: DynamicRange, options: KSOptions) {
        KSLog("[video] refreshRate=\(refreshRate),dynamicRange=\(dynamicRange)", file: "ProAVPlayer/ConversionToM3U8.swift", function: "updateVideo(refreshRate:dynamicRange:options:)", line: 228)
    }

    // vtable-empty (devirtualized) → M2 via witness-table-anchoring (the e651ff8 technique) + the real
    // init (FUN_101b6bf88 stores videoSaveURL, nils localHLSServer). Structure-only here (P15).
}

/// FUN_101b6fcf8 (args: track, tracks; no self). Display name = name, or description (0x101a1fd10) if the name is empty.
/// If another track has the same display name, `" #" + trackID` is appended.
/// ⚑ NAME INFERRED (no symbol).
// L7: internal — ProAVPlayer 0x101b79024 calls it directly (bl 0x101b6fcf8 @0x101b79548).
func trackName(_ track: FFmpegAssetTrack, tracks: [FFmpegAssetTrack]) -> String {
    let name = track.name.isEmpty ? track.description : track.name
    for other in tracks where other !== track {
        if (other.name.isEmpty ? other.description : other.name) == name {
            return name + " #" + track.trackID.description
        }
    }
    return name
}
