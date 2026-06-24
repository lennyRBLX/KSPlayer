import XCTest
@testable import KSPlayer

final class ProAVPlayerTests: XCTestCase {
    func testConversionInfoInit() {
        let info = ConversionInfo(duration: 120.0, startTime: 0)
        XCTAssertEqual(info.duration, 120.0)
        XCTAssertEqual(info.startTime, 0)
        // targetDuration (binary +0x38) defaults to user-visible duration when unspecified.
        XCTAssertEqual(info.targetDuration, 120.0)
        XCTAssertEqual(info.lastReportedPosition, 0)
        XCTAssertFalse(info.suppressStartOffset)
        XCTAssertEqual(info.effectiveStartOffset, 0)
    }

    func testConversionInfoWithBounds() {
        let bounds = CMTimeRange(start: CMTime(seconds: 10, preferredTimescale: 90000),
                                 duration: CMTime(seconds: 50, preferredTimescale: 90000))
        let info = ConversionInfo(duration: 60.0, startTime: 10.0, bounds: bounds)
        XCTAssertEqual(info.duration, 60.0)
        XCTAssertEqual(info.startTime, 10.0)
        XCTAssertNotNil(info.bounds)
        XCTAssertEqual(info.effectiveStartOffset, 10.0)
    }

    /// Binary: `_TtC11ProAVPlayer13ProPlayerItem::currentTime` and
    /// `ProAVPlayer_handleEndOfStream` both zero out the start offset when the
    /// flag at `*(self + 0x60) + 0x18` is non-zero. The Swift side mirrors that
    /// branch through `suppressStartOffset` -> `effectiveStartOffset`.
    func testSuppressStartOffsetZeroesEffectiveOffset() {
        let info = ConversionInfo(duration: 60.0, startTime: 10.0)
        XCTAssertEqual(info.effectiveStartOffset, 10.0)
        info.suppressStartOffset = true
        XCTAssertEqual(info.effectiveStartOffset, 0)
    }

    /// Binary: `ConversionInfo_updatePositionAndTrigger @ 0x101544474` debounces
    /// position writes -- the field at +0x40 is only overwritten when the delta
    /// from the incoming position is >= 1.0s.
    func testUpdatePositionDebouncesUnderOneSecond() {
        final class Spy: ConversionInfoDelegate {
            var positionUpdates: [TimeInterval] = []
            func conversionDidComplete(_ info: ConversionInfo) {}
            func conversionDidFail(_ info: ConversionInfo, error: Error) {}
            func conversionInfo(_ info: ConversionInfo, didUpdatePosition position: TimeInterval) {
                positionUpdates.append(position)
            }
        }
        let info = ConversionInfo(duration: 600.0, startTime: 0)
        info.targetDuration = 600
        info.convertedDuration = 100 // small converted window -> trigger expected
        let spy = Spy()
        info.delegate = spy

        // First call moves lastReportedPosition from 0 to 0.5? Debounce: delta < 1.0 -> no-op.
        info.updatePositionAndTrigger(0.5)
        XCTAssertEqual(info.lastReportedPosition, 0)
        XCTAssertTrue(spy.positionUpdates.isEmpty)

        // Second call: delta = 1.0 -> passes debounce -> position written -> trigger evaluated.
        info.updatePositionAndTrigger(1.0)
        XCTAssertEqual(info.lastReportedPosition, 1.0)
    }

    /// Binary trigger predicate: `(targetDuration - effectiveStartOffset - position) < convertedDuration`.
    /// When `remaining < convertedDuration`, the binary spawns an async extension request via
    /// `ProAVPlayer_createAsyncTask`. The Swift port routes that through the delegate.
    func testUpdatePositionFiresDelegateWhenRemainingIsSmall() {
        final class Spy: ConversionInfoDelegate {
            var positionUpdates: [TimeInterval] = []
            func conversionDidComplete(_ info: ConversionInfo) {}
            func conversionDidFail(_ info: ConversionInfo, error: Error) {}
            func conversionInfo(_ info: ConversionInfo, didUpdatePosition position: TimeInterval) {
                positionUpdates.append(position)
            }
        }
        let info = ConversionInfo(duration: 100.0, startTime: 0)
        info.targetDuration = 100
        info.convertedDuration = 90 // remaining (100 - 0 - 20) = 80 < 90 -> trigger
        let spy = Spy()
        info.delegate = spy

        info.updatePositionAndTrigger(20.0)
        XCTAssertEqual(spy.positionUpdates, [20.0])
    }

    func testUpdatePositionStaysQuietWhenBufferIsAhead() {
        final class Spy: ConversionInfoDelegate {
            var positionUpdates: [TimeInterval] = []
            func conversionDidComplete(_ info: ConversionInfo) {}
            func conversionDidFail(_ info: ConversionInfo, error: Error) {}
            func conversionInfo(_ info: ConversionInfo, didUpdatePosition position: TimeInterval) {
                positionUpdates.append(position)
            }
        }
        let info = ConversionInfo(duration: 100.0, startTime: 0)
        info.targetDuration = 100
        info.convertedDuration = 10 // remaining (100 - 0 - 20) = 80; 80 >= 10 -> no trigger
        let spy = Spy()
        info.delegate = spy

        info.updatePositionAndTrigger(20.0)
        XCTAssertTrue(spy.positionUpdates.isEmpty)
    }

    func testConversionProgressDefaults() {
        let progress = ConversionProgress()
        XCTAssertEqual(progress.convertedDuration, 0)
        XCTAssertEqual(progress.totalDuration, 0)
        XCTAssertEqual(progress.segmentsWritten, 0)
        XCTAssertFalse(progress.isComplete)
        XCTAssertEqual(progress.progress, 0)
    }

    func testConversionProgressCalculation() {
        var progress = ConversionProgress()
        progress.totalDuration = 100
        progress.convertedDuration = 50
        XCTAssertEqual(progress.progress, 0.5)
    }

    func testConversionProgressCapsAtOne() {
        var progress = ConversionProgress()
        progress.totalDuration = 100
        progress.convertedDuration = 200
        XCTAssertEqual(progress.progress, 1.0)
    }

    /// Binary: `ConversionProgress_setBytesConverted @ 0x10155b890` keeps the larger of the
    /// new value and the existing high-water mark, and skips the -1 sentinel.
    func testConversionProgressBytesConvertedTracksHighWater() {
        var progress = ConversionProgress()
        progress.setBytesConverted(100)
        XCTAssertEqual(progress.bytesConverted, 100)
        XCTAssertEqual(progress.maxBytesConverted, 100)
        progress.setBytesConverted(50)
        // bytesConverted always tracks the latest value; maxBytesConverted is monotonic.
        XCTAssertEqual(progress.bytesConverted, 50)
        XCTAssertEqual(progress.maxBytesConverted, 100)
        // -1 sentinel: bytesConverted is still written, bandwidth update is skipped.
        progress.setBytesConverted(UInt64.max)
        XCTAssertEqual(progress.bytesConverted, UInt64.max)
    }

    func testDemuxerIOInitialState() {
        let demuxer = DemuxerIO()
        XCTAssertEqual(demuxer.state, .ready)
    }

    func testDemuxerIOCloseFromReady() {
        let demuxer = DemuxerIO()
        demuxer.dispatch(.close)
        XCTAssertEqual(demuxer.state, .closed)
    }

    func testDemuxerIOStartReadingFromReady() {
        let demuxer = DemuxerIO()
        demuxer.dispatch(.startReading)
        // startReading is valid from {ready, seeking}; from ready it transitions to
        // reading (binary DemuxerIO_stateMachine @0x101555778, startReading arm).
        XCTAssertEqual(demuxer.state, .reading)
    }

    func testMimeTypeResolution() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("test_hls_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let server = try LocalHLSServer(rootDirectory: dir)
        XCTAssertNotNil(server.baseURL)
        server.stop()
    }
}
