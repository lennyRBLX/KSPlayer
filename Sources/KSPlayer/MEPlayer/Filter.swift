//
//  Filter.swift
//  KSPlayer
//
//  Created by kintan on 2021/8/7.
//

import Foundation
import Libavfilter
import Libavutil

class MEFilter {
    // MARK: - Fields (RE: MEFilter, 9 fields per types.json)
    // Field order below mirrors the binary type-dump declaration order. The
    // `isAudio: Bool` field claimed by earlier source revisions is not
    // present in the binary — the audio/video dispatch is driven by
    // `height == 0` (audio) instead.

    private var graph: UnsafeMutablePointer<AVFilterGraph>?              // #1
    private var bufferSrcContext: UnsafeMutablePointer<AVFilterContext>? // #2
    private var bufferSinkContext: UnsafeMutablePointer<AVFilterContext>?// #3
    private var filters: String?                                         // #4
    let timebase: Timebase                                               // #5
    /// Cached pixel/sample format. Replaces upstream's heap-allocated
    /// `AVBufferSrcParameters` pointer; comparing three Int32s is cheaper
    /// than a full struct comparison.
    private var format: Int32 = 0                                        // #6
    /// Cached frame height. `0` indicates an audio filter chain.
    private var height: Int32 = 0                                        // #7
    /// Cached frame width.
    private var width: Int32 = 0                                         // #8
    private let nominalFrameRate: Float                                  // #9

    /// Computed audio/video discriminator. The binary does not store
    /// `isAudio` as a field; it is recovered from `height == 0` on the
    /// cached frame metrics. Initial value (before the first frame) reflects
    /// the constructor parameter via the `initialIsAudio` shadow.
    private var isAudio: Bool {
        if height == 0 && width == 0 {
            return initialIsAudio
        }
        return height == 0
    }
    private let initialIsAudio: Bool
    deinit {
        graph?.pointee.opaque = nil
        avfilter_graph_free(&graph)
    }

    /// RE: 0x10141ca38 (MEFilter_init, 1.3.15)
    public init(timebase: Timebase, isAudio: Bool, nominalFrameRate: Float, options: KSOptions) {
        graph = avfilter_graph_alloc()
        graph?.pointee.opaque = Unmanaged.passUnretained(options).toOpaque()
        self.timebase = timebase
        self.initialIsAudio = isAudio
        self.nominalFrameRate = nominalFrameRate
    }

    /// RE: 0x10141c7a8 (MEFilter_setupFilterGraph, 1.3.15)
    private func setup(filters: String, params: inout AVBufferSrcParameters) -> Bool {
        var inputs = avfilter_inout_alloc()
        var outputs = avfilter_inout_alloc()
        var ret = avfilter_graph_parse2(graph, filters, &inputs, &outputs)
        guard ret >= 0, let graph, let inputs, let outputs else {
            avfilter_inout_free(&inputs)
            avfilter_inout_free(&outputs)
            return false
        }
        let bufferSink = avfilter_get_by_name(isAudio ? "abuffersink" : "buffersink")
        ret = avfilter_graph_create_filter(&bufferSinkContext, bufferSink, "out", nil, nil, graph)
        guard ret >= 0 else { return false }
        ret = avfilter_link(outputs.pointee.filter_ctx, UInt32(outputs.pointee.pad_idx), bufferSinkContext, 0)
        guard ret >= 0 else { return false }
        let buffer = avfilter_get_by_name(isAudio ? "abuffer" : "buffer")
        bufferSrcContext = avfilter_graph_alloc_filter(graph, buffer, "in")
        guard bufferSrcContext != nil else { return false }
        av_buffersrc_parameters_set(bufferSrcContext, &params)
        ret = avfilter_init_str(bufferSrcContext, nil)
        guard ret >= 0 else { return false }
        ret = avfilter_link(bufferSrcContext, 0, inputs.pointee.filter_ctx, UInt32(inputs.pointee.pad_idx))
        guard ret >= 0 else { return false }
        if let ctx = params.hw_frames_ctx {
            let framesCtxData = UnsafeMutableRawPointer(ctx.pointee.data).bindMemory(to: AVHWFramesContext.self, capacity: 1)
            inputs.pointee.filter_ctx.pointee.hw_device_ctx = framesCtxData.pointee.device_ref
        }
        ret = avfilter_graph_config(graph, nil)
        guard ret >= 0 else { return false }
        return true
    }

    private func setup2(filters: String, params: inout AVBufferSrcParameters) -> Bool {
        guard let graph else {
            return false
        }
        let bufferName = isAudio ? "abuffer" : "buffer"
        let bufferSrc = avfilter_get_by_name(bufferName)
        var ret = avfilter_graph_create_filter(&bufferSrcContext, bufferSrc, "ksplayer_\(bufferName)", params.arg, nil, graph)
        av_buffersrc_parameters_set(bufferSrcContext, &params)
        let bufferSink = avfilter_get_by_name(bufferName + "sink")
        ret = avfilter_graph_create_filter(&bufferSinkContext, bufferSink, "ksplayer_\(bufferName)sink", nil, nil, graph)
        guard ret >= 0 else { return false }
        //        av_opt_set_int_list(bufferSinkContext, "pix_fmts", [AV_PIX_FMT_GRAY8, AV_PIX_FMT_NONE] AV_PIX_FMT_NONE,AV_OPT_SEARCH_CHILDREN)
        var inputs = avfilter_inout_alloc()
        var outputs = avfilter_inout_alloc()
        outputs?.pointee.name = strdup("in")
        outputs?.pointee.filter_ctx = bufferSrcContext
        outputs?.pointee.pad_idx = 0
        outputs?.pointee.next = nil
        inputs?.pointee.name = strdup("out")
        inputs?.pointee.filter_ctx = bufferSinkContext
        inputs?.pointee.pad_idx = 0
        inputs?.pointee.next = nil
        let filterNb = Int(graph.pointee.nb_filters)
        ret = avfilter_graph_parse_ptr(graph, filters, &inputs, &outputs, nil)
        guard ret >= 0 else {
            avfilter_inout_free(&inputs)
            avfilter_inout_free(&outputs)
            return false
        }
        for i in 0 ..< Int(graph.pointee.nb_filters) - filterNb {
            swap(&graph.pointee.filters[i], &graph.pointee.filters[i + filterNb])
        }
        ret = avfilter_graph_config(graph, nil)
        guard ret >= 0 else { return false }
        return true
    }

    public func filter(options: KSOptions, inputFrame: UnsafeMutablePointer<AVFrame>, completionHandler: (UnsafeMutablePointer<AVFrame>) -> Void) {
        let filters: String
        if isAudio {
            filters = options.audioFilters.joined(separator: ",")
        } else {
            if options.autoDeInterlace, !options.videoFilters.contains("idet") {
                options.videoFilters.append("idet")
            }
            filters = options.videoFilters.joined(separator: ",")
        }
        guard !filters.isEmpty else {
            completionHandler(inputFrame)
            return
        }
        // RE: v1.3.15 binary optimization — compare only format/height/width (3 Int32s)
        // instead of full AVBufferSrcParameters struct to decide if filter graph needs rebuild
        let frameFormat = inputFrame.pointee.format
        let frameHeight = inputFrame.pointee.height
        let frameWidth = inputFrame.pointee.width
        if self.format != frameFormat || self.height != frameHeight || self.width != frameWidth || self.filters != filters {
            self.format = frameFormat
            self.height = frameHeight
            self.width = frameWidth
            self.filters = filters
            // Build full params for av_buffersrc_parameters_set (needed by setup)
            var params = AVBufferSrcParameters()
            params.format = frameFormat
            params.time_base = timebase.rational
            params.width = frameWidth
            params.height = frameHeight
            params.sample_aspect_ratio = inputFrame.pointee.sample_aspect_ratio
            params.frame_rate = AVRational(num: 1, den: Int32(nominalFrameRate))
            if let ctx = inputFrame.pointee.hw_frames_ctx {
                params.hw_frames_ctx = av_buffer_ref(ctx)
            }
            params.sample_rate = inputFrame.pointee.sample_rate
            params.ch_layout = inputFrame.pointee.ch_layout
            if !setup(filters: filters, params: &params) {
                completionHandler(inputFrame)
                return
            }
        }
        let ret = av_buffersrc_add_frame_flags(bufferSrcContext, inputFrame, 0)
        if ret < 0 {
            return
        }
        while av_buffersink_get_frame_flags(bufferSinkContext, inputFrame, 0) >= 0 {
//                timebase = Timebase(av_buffersink_get_time_base(bufferSinkContext))
            completionHandler(inputFrame)
            // 一定要加av_frame_unref，不然会内存泄漏。
            av_frame_unref(inputFrame)
        }
    }
}
