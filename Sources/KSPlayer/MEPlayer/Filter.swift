//
//  Filter.swift
//  KSPlayer
//
//  Created by kintan on 2021/8/7.
//

import Foundation
import Libavfilter
import Libavutil

// ⚑ vtable (descriptor 0x1039ef65c): slots 0-20 = get/set/modify for the 7 `var`s, 21 = init,
//   22 = setup @0x101a3b660, 23 = filter. `private` members are final and get no vtable entry,
//   so the vars and setup are internal (not private).
class MEFilter {
    var graph: UnsafeMutablePointer<AVFilterGraph>?
    var bufferSrcContext: UnsafeMutablePointer<AVFilterContext>?
    var bufferSinkContext: UnsafeMutablePointer<AVFilterContext>?
    var filters: String?
    let timebase: Timebase
    // order = binary field-descriptor order (height before width — reflection-authoritative)
    // ⚑[tool=field_surface ref=MEFilter.format result=forward Swift.Int32] — Int32, not AVPixelFormat; -1 == AV_PIX_FMT_NONE
    var format: Int32 = -1
    var height: Int32 = 0
    var width: Int32 = 0
    private let nominalFrameRate: Float
    deinit {
        graph?.pointee.opaque = nil
        avfilter_graph_free(&graph)
    }

    // UNRESOLVED→P3: init devirt; isAudio not stored (field removed), threading to setup is caller-side
    public init(timebase: Timebase, isAudio: Bool, nominalFrameRate: Float, options: KSOptions) {
        graph = avfilter_graph_alloc()
        graph?.pointee.opaque = Unmanaged.passUnretained(options).toOpaque()
        self.timebase = timebase
        self.nominalFrameRate = nominalFrameRate
    }

    // Forward-faithful (slot22 @ 0x101a3b660). Divergences from upstream setup():
    //   1. isAudio + params are PARAMETERS (param_4 low-bit, param_3) — not self.isAudio/self.params.
    //   2. hw_frames_ctx block DROPPED — avfilter_link → avfilter_graph_config directly.
    //   3. setup()-shape only (no setup2 swap logic).
    func setup(filters: String, params: UnsafeMutablePointer<AVBufferSrcParameters>, isVideo: Bool) -> Bool {
        var inputs = avfilter_inout_alloc()
        var outputs = avfilter_inout_alloc()
        // Divergence 4 (vs upstream): free both inout lists on ALL exit paths via defer
        // (upstream frees only inside the first guard-fail).
        defer {
            avfilter_inout_free(&inputs)
            avfilter_inout_free(&outputs)
        }
        var ret = avfilter_graph_parse2(graph, filters, &inputs, &outputs)
        guard ret >= 0, let graph, let inputs, let outputs else {
            return false
        }
        let bufferSink = avfilter_get_by_name(isVideo ? "buffersink" : "abuffersink")
        ret = avfilter_graph_create_filter(&bufferSinkContext, bufferSink, "out", nil, nil, graph)
        guard ret >= 0 else { return false }
        ret = avfilter_link(outputs.pointee.filter_ctx, UInt32(outputs.pointee.pad_idx), bufferSinkContext, 0)
        guard ret >= 0 else { return false }
        let buffer = avfilter_get_by_name(isVideo ? "buffer" : "abuffer")
        bufferSrcContext = avfilter_graph_alloc_filter(graph, buffer, "in")
        guard bufferSrcContext != nil else { return false }
        av_buffersrc_parameters_set(bufferSrcContext, params)
        ret = avfilter_init_str(bufferSrcContext, nil)
        guard ret >= 0 else { return false }
        ret = avfilter_link(bufferSrcContext, 0, inputs.pointee.filter_ctx, UInt32(inputs.pointee.pad_idx))
        guard ret >= 0 else { return false }
        ret = avfilter_graph_config(graph, nil)
        guard ret >= 0 else { return false }
        return true
    }

    // UNRESOLVED→P3: filter() devirt — not binary-anchored; isAudio source + exact dedup unverified
    public func filter(
        options: KSOptions,
        inputFrame: UnsafeMutablePointer<AVFrame>,
        _ isVideo: Bool,
        completionHandler: (UnsafeMutablePointer<AVFrame>) -> Void
    ) {
        let filters: String
        if isVideo {
            filters = options.videoFilters.joined(separator: ",")
        } else {
            filters = options.audioFilters.joined(separator: ",")
        }
        guard !filters.isEmpty else {
            if self.filters != nil {
                av_buffersrc_close(
                    bufferSrcContext,
                    inputFrame.pointee.pts,
                    UInt32(AV_BUFFERSRC_FLAG_PUSH)
                )
                self.filters = nil
            }
            completionHandler(inputFrame)
            return
        }
        var srcParams = AVBufferSrcParameters()
        srcParams.format = inputFrame.pointee.format
        srcParams.time_base = timebase.rational
        srcParams.width = inputFrame.pointee.width
        srcParams.height = inputFrame.pointee.height
        srcParams.sample_aspect_ratio = inputFrame.pointee.sample_aspect_ratio
        srcParams.frame_rate = AVRational(num: 1, den: Int32(nominalFrameRate))
        if let ctx = inputFrame.pointee.hw_frames_ctx {
            srcParams.hw_frames_ctx = av_buffer_ref(ctx)
        }
        srcParams.sample_rate = inputFrame.pointee.sample_rate
        srcParams.ch_layout = inputFrame.pointee.ch_layout
        if format != srcParams.format || width != srcParams.width || height != srcParams.height || self.filters != filters {
            format = srcParams.format
            width = srcParams.width
            height = srcParams.height
            self.filters = filters
            if !setup(filters: filters, params: &srcParams, isVideo: isVideo) {
                completionHandler(inputFrame)
                return
            }
        }
        let duration = inputFrame.pointee.duration
        let ret = av_buffersrc_add_frame_flags(bufferSrcContext, inputFrame, 0)
        if ret < 0 {
            return
        }
        while av_buffersink_get_frame_flags(bufferSinkContext, inputFrame, 0) >= 0 {
            if !isVideo {
                inputFrame.pointee.duration = duration
            }
            completionHandler(inputFrame)
            av_frame_unref(inputFrame)
        }
    }
    // setup2 removed — no binary witness, dead in Forward (referenced removed `params`, no vtable/unresolved slot).
}
