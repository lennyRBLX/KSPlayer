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
    private var graph: UnsafeMutablePointer<AVFilterGraph>?
    private var bufferSrcContext: UnsafeMutablePointer<AVFilterContext>?
    private var bufferSinkContext: UnsafeMutablePointer<AVFilterContext>?
    private var filters: String?
    let timebase: Timebase
    // ⚑ inferred (§7-walled, no concrete field-record) — type from arg-shape; do not "improve"
    // order = binary field-descriptor order (height before width — reflection-authoritative)
    private var format: AVPixelFormat = AV_PIX_FMT_NONE
    private var height: Int32 = 0
    private var width: Int32 = 0
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
    private func setup(filters: String, params: UnsafeMutablePointer<AVBufferSrcParameters>, isAudio: Bool) -> Bool {
        var inputs = avfilter_inout_alloc()
        var outputs = avfilter_inout_alloc()
        // Divergence 4 (vs upstream): free both inout lists on ALL exit paths via `defer`
        // (upstream frees only inside the first guard-fail).
        defer {
            avfilter_inout_free(&inputs)
            avfilter_inout_free(&outputs)
        }
        var ret = avfilter_graph_parse2(graph, filters, &inputs, &outputs)
        guard ret >= 0, let graph, let inputs, let outputs else {
            return false
        }
        // Divergence 5: filter-name selection is inverted vs upstream (per the slot22 decompile).
        // ⚑ POLARITY UNRESOLVED→P3: this isAudio→name mapping is opposite upstream's; the canonical
        // polarity is set by the (devirt) caller filter() — reconcile in P3.
        let bufferSink = avfilter_get_by_name(isAudio ? "buffersink" : "abuffersink")
        ret = avfilter_graph_create_filter(&bufferSinkContext, bufferSink, "out", nil, nil, graph)
        guard ret >= 0 else { return false }
        ret = avfilter_link(outputs.pointee.filter_ctx, UInt32(outputs.pointee.pad_idx), bufferSinkContext, 0)
        guard ret >= 0 else { return false }
        let buffer = avfilter_get_by_name(isAudio ? "buffer" : "abuffer")
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
    public func filter(options: KSOptions, inputFrame: UnsafeMutablePointer<AVFrame>, completionHandler: (UnsafeMutablePointer<AVFrame>) -> Void) {
        // FLAGGED placeholder — isAudio unrecoverable here (devirt). Named `audioFlag`
        // to avoid re-introducing the removed `isAudio` member.
        let audioFlag = false
        let filters: String
        if audioFlag {
            filters = options.audioFilters.joined(separator: ",")
        } else {
            // ⚑ Forward dropped options.autoDeInterlace (field absent) + the idet auto-detection (KSOptions.filter),
            //   so the base idet-filter auto-append is Forward-removed. Verify Forward's de-interlace path.
            filters = options.videoFilters.joined(separator: ",")
        }
        guard !filters.isEmpty else {
            completionHandler(inputFrame)
            return
        }
        // Local builder; named `srcParams` to avoid re-introducing the removed `params` member.
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
        if format != AVPixelFormat(srcParams.format) || width != srcParams.width || height != srcParams.height || self.filters != filters {
            format = AVPixelFormat(srcParams.format)
            width = srcParams.width
            height = srcParams.height
            self.filters = filters
            if !setup(filters: filters, params: &srcParams, isAudio: audioFlag) {
                completionHandler(inputFrame)
                return
            }
        }
        let ret = av_buffersrc_add_frame_flags(bufferSrcContext, inputFrame, 0)
        if ret < 0 {
            return
        }
        while av_buffersink_get_frame_flags(bufferSinkContext, inputFrame, 0) >= 0 {
            completionHandler(inputFrame)
            // 一定要加av_frame_unref，不然会内存泄漏。
            av_frame_unref(inputFrame)
        }
    }
    // setup2 removed — no binary witness, dead in Forward (referenced removed `params`, no vtable/unresolved slot).
}
