//
//  Phase2RemuxTest.swift
//  KSPlayerTests
//
//  Forward 1.3.17 reconstruction — P2 remux cluster (Wave-2 M3) behavioral arbitration.
//
//  Behaviorally arbitrates the reconstructed remux cluster (Remuxer.write → OutputStreamInfo
//  slot13 buildTranscodeContext → Copy/BSF dispatch). The 4 cases below are BINARY-DERIVED
//  (orchestrator-owned); they are implemented EXACTLY as specified — no new assertions, none
//  weakened. The library surface is NOT bent to the test: assertions target the recovered API.
//
//  - Case 1: existing transcodeMap ctx is REUSED + ctx.transcode is INVOKED (the primary effect,
//            terminal witness call @L161) forwarding packet + outPacket.
//  - Case 2: non-AAC → Copy is dispatched as a static singleton (NOT stored in transcodeMap);
//            CopyTranscodeContext.transcode runs (proof: outPacket.pos == -1).
//  - Case 3: DTS-clamp = min(max(pts,0), max(dts,0)), recorded once per stream.
//  - Case 4: AAC + ADTS → BSF stored OR Copy fallthrough (deferred par-setup); both accepted.
//
@testable import KSPlayer
import Libavformat
import Libavcodec
import Foundation
import XCTest

// MARK: - Mock (orchestrator-specified)

/// Records every `transcode` invocation so Case 1 can prove the existing per-stream context is
/// REUSED and INVOKED with the forwarded input packet + the OSI's outPacket buffer.
final class MockTranscodeContext: TranscodeProtocol {
    private(set) var transcodeCalls: [(input: UnsafeMutablePointer<AVPacket>?, output: UnsafeMutablePointer<AVPacket>?)] = []
    func transcode(_ input: UnsafeMutablePointer<AVPacket>?, output: UnsafeMutablePointer<AVPacket>?, completion: (UnsafeMutablePointer<AVPacket>?) -> Void) {
        transcodeCalls.append((input, output)); completion(output)
    }
    func drain(_ completion: (UnsafeMutablePointer<AVPacket>?) -> Void) {}
    func close() {}
}

final class Phase2RemuxTest: XCTestCase {

    // MARK: - Shared setup helpers

    /// Build an `AVFormatContext` with one output stream (index 0) whose codec_id is `codecID`,
    /// then an `OutputStreamInfo` over it wired for the BUILD path: empty `assetTrackMap`
    /// (so `assetTrackMap[0] == nil` → BUILD branch), `streamMapping[0]=0`,
    /// `timeBaseMap[0]=1/1000`, and a live `outPacket`.
    private func makeOutputStreamInfo(codecID: AVCodecID, removeADTS: Bool) -> OutputStreamInfo {
        let fmt = avformat_alloc_context()!
        let outStream = avformat_new_stream(fmt, nil)!          // → index 0
        outStream.pointee.codecpar.pointee.codec_id = codecID

        let osi = OutputStreamInfo(formatCtx: fmt)
        // BUILD path: leave assetTrackMap EMPTY (assetTrackMap[0] == nil).
        osi.streamMapping[0] = 0
        osi.timeBaseMap[0] = AVRational(num: 1, den: 1000)
        osi.outPacket = av_packet_alloc()
        osi.removeADTS = removeADTS
        return osi
    }

    /// An 8-byte packet on stream 0 with the ADTS sync bytes (0xFF, 0xF0) set, and the given
    /// pts/dts. idx == 0 throughout.
    private func makePacket(pts: Int64, dts: Int64) -> UnsafeMutablePointer<AVPacket> {
        let pkt = av_packet_alloc()!
        _ = av_new_packet(pkt, 8)
        pkt.pointee.stream_index = 0
        pkt.pointee.data[0] = 0xFF
        pkt.pointee.data[1] = 0xF0
        pkt.pointee.pts = pts
        pkt.pointee.dts = dts
        return pkt
    }

    private func makeRemuxer(_ osi: OutputStreamInfo) -> Remuxer {
        Remuxer(formatCtx: osi.formatCtx, outputStreamInfo: osi, mediaType: nil)
    }

    // MARK: - Case 1: Reuse + invocation (the primary effect)

    /// s13 must REUSE the pre-existing per-stream context and INVOKE ctx.transcode, forwarding
    /// the input packet + the OSI's outPacket buffer (terminal witness call @L161).
    func testCase1_ReusesExistingContextAndInvokesTranscode() {
        let osi = makeOutputStreamInfo(codecID: AV_CODEC_ID_AAC, removeADTS: true)
        let mock = MockTranscodeContext()
        osi.transcodeMap[0] = mock                               // pre-set the per-stream ctx
        let pkt = makePacket(pts: 0, dts: 0)
        let remuxer = makeRemuxer(osi)

        remuxer.write(pkt)

        XCTAssertEqual(mock.transcodeCalls.count, 1)
        XCTAssertEqual(mock.transcodeCalls.first?.input, pkt)            // forwards the input packet
        XCTAssertEqual(mock.transcodeCalls.first?.output, osi.outPacket) // forwards outPacket buffer
    }

    // MARK: - Case 2: Copy build dispatch

    /// Non-AAC (H264) → Copy. Copy is a static singleton: it is NOT stored in transcodeMap, and
    /// CopyTranscodeContext.transcode runs (proof: outPacket.pos stamped to -1).
    func testCase2_CopyDispatchNotStoredAndRuns() {
        let osi = makeOutputStreamInfo(codecID: AV_CODEC_ID_H264, removeADTS: true)
        // transcodeMap EMPTY.
        let pkt = makePacket(pts: 0, dts: 0)
        let remuxer = makeRemuxer(osi)

        remuxer.write(pkt)

        XCTAssertNil(osi.transcodeMap[0])                        // Copy singleton not stored
        XCTAssertEqual(osi.outPacket!.pointee.pos, -1)           // CopyTranscodeContext.transcode ran
    }

    // MARK: - Case 3: DTS-clamp

    /// startTime[idx] = min(max(pts,0), max(dts,0)), recorded ONCE PER STREAM (first packet wins —
    /// binary `if startTime[idx] == nil`, body-audit-confirmed faithful).
    func testCase3_DTSClampRecordedOncePerStream() {
        // (a) Clamp arithmetic, non-zero result: fresh stream, pts=20, dts=15 → min(max(20,0),max(15,0)) = 15.
        let osiA = makeOutputStreamInfo(codecID: AV_CODEC_ID_H264, removeADTS: false)
        let remuxerA = makeRemuxer(osiA)
        remuxerA.write(makePacket(pts: 20, dts: 15))
        XCTAssertEqual(remuxerA.startTime[0], 15)

        // (b) Negative clamp → 0, AND once-per-stream: a 2nd packet on the SAME stream must NOT overwrite.
        let osiB = makeOutputStreamInfo(codecID: AV_CODEC_ID_H264, removeADTS: false)
        let remuxerB = makeRemuxer(osiB)
        remuxerB.write(makePacket(pts: -5, dts: 10))          // min(max(-5,0),max(10,0)) = min(0,10) = 0
        XCTAssertEqual(remuxerB.startTime[0], 0)
        remuxerB.write(makePacket(pts: 20, dts: 15))          // same stream 0 — guarded by `if startTime[0]==nil`
        XCTAssertEqual(remuxerB.startTime[0], 0)              // UNCHANGED (once-per-stream, NOT 15)
    }

    // MARK: - Case 4: AAC dispatch (best-effort; document the outcome)

    /// AAC + ADTS-syncword + removeADTS → BSF dispatch.
    /// BSF stored if av_bsf_init succeeds; nil = fell back to Copy because the par-setup
    /// (FUN_1029f5584) is deferred-UNRESOLVED → Copy fallthrough. Accept BOTH; do NOT fail on nil.
    func testCase4_AACDispatchBSFOrCopyFallback() {
        let osi = makeOutputStreamInfo(codecID: AV_CODEC_ID_AAC, removeADTS: true)
        // transcodeMap EMPTY; ADTS bytes set by makePacket.
        let pkt = makePacket(pts: 0, dts: 0)
        let remuxer = makeRemuxer(osi)

        remuxer.write(pkt)

        let stored = osi.transcodeMap[0]
        let isBSF = stored is BSFTranscodeContext
        let isNil = stored == nil
        XCTAssertTrue(isBSF || isNil,
                      "AAC dispatch must store a BSFTranscodeContext OR fall back to Copy (nil).")
    }

    // MARK: - Deferred paths (anti-rot — visible as SKIPS every run; reconstruct in the named owner)
    //         Full detail: play/docs/superpowers/reports/task-P2-wave2-deferred-bodies.md

    /// Full remux → segments (spec §6 literal). Needs a demuxer + media fixture + the OSI builder
    /// FUN_101a1d014. Deferred to P3 where the driver 0x101a483d4 / MEPlayerItem write path land.
    func testFullRemuxToSegments_DEFERRED_P3() throws {
        throw XCTSkip("DEFERRED → P3: full remux→segments needs a demuxer + media fixture + FUN_101a1d014 OSI builder")
    }

    /// s13 steady-state per-packet enqueue (else-branch when assetTrackMap[idx] EXISTS, FUN_101a1ae90).
    /// Core packet-copy FUN_102d622ec is UNRESOLVED.
    func testSteadyStateEnqueue_DEFERRED_P3() throws {
        throw XCTSkip("DEFERRED → P3: s13 steady-state enqueue FUN_101a1ae90 (packet-copy core FUN_102d622ec unresolved)")
    }

    /// Remuxer write-output completion body (writeOutputPacket, FUN_101a660d0) — emits the transcoded
    /// packet to the output format ctx (av_write_frame / av_interleaved_write_frame — devirt-unresolved).
    func testWriteOutputCompletion_DEFERRED_P3() throws {
        throw XCTSkip("DEFERRED → P3: Remuxer write-output FUN_101a660d0 (av_write devirt-unresolved)")
    }
}
