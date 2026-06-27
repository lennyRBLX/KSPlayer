@testable import KSPlayer
@testable import PreLoadIOContext   // CacheIOContext's fields are internal (faithful) → @testable
import Foundation
import XCTest

/// Phase-1 foundation tests.
/// - 1C.1: IO-cancellation primitives (construction + registration path). Cancel/
///   isCancelled behavior is NOT in the Forward 1.3.17 binary → deferred to 1C.9.
/// - 1C.2: CacheEntry Codable round-trip + the bounds-check method.
/// - 1C.9: L3 capability — CacheIOContext construction + IO/cancellation surface +
///   getContext AVIO bridge (functional read/cancel is FFmpeg-monolithic → P2).
final class Phase1FoundationTest: XCTestCase {

    // MARK: 1C.1 — IOInterrupt

    func testIOInterruptContextConstructs() {
        let ctx = IOInterruptContext { false }   // designated init: init(_ block:)
        XCTAssertFalse(ctx.flag)                 // initial flag == false (binary: self.flag = 0)
    }

    /// The block is stored and callable; flag is a mutable var.
    func testIOInterruptContextStoresBlock() {
        let ctx = IOInterruptContext { true }
        XCTAssertEqual(ctx.block?(), true)       // closure stored at self.block (+0x18/+0x20)
        ctx.flag = true
        XCTAssertTrue(ctx.flag)
    }

    /// Constructing several contexts exercises the registry path (lazy `_swift_once`
    /// singleton + locked nextID increment + contexts[id] = weak(self)) without crash.
    /// token.id is `fileprivate` (the binary's private IOInterruptToken) → not asserted here.
    func testIOInterruptContextRegistrationDoesNotCrash() {
        var contexts: [IOInterruptContext] = []
        for _ in 0 ..< 5 { contexts.append(IOInterruptContext(nil)) }
        XCTAssertEqual(contexts.count, 5)
        XCTAssertTrue(contexts.allSatisfy { !$0.flag })
    }

    // MARK: 1C.2 — CacheEntry

    /// Round-trips through the SYNTHESIZED Codable. Verifies the field types
    /// (logicalPos/physicalPos UInt64, size/maxSize UInt32, eof Bool) survive
    /// encode→decode — this is the regression guard for the UInt64 type fix.
    func testCacheEntryCodableRoundTrip() throws {
        let entry = CacheEntry(logicalPos: 0xFFFF_FFFF_0001,   // > UInt32.max → proves 64-bit
                               physicalPos: 0x1_0000_0002,
                               size: 4096,
                               maxSize: 65_536)
        entry.eof = true

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(CacheEntry.self, from: data)

        XCTAssertEqual(decoded.logicalPos, 0xFFFF_FFFF_0001)
        XCTAssertEqual(decoded.physicalPos, 0x1_0000_0002)
        XCTAssertEqual(decoded.size, 4096)
        XCTAssertEqual(decoded.eof, true)
        XCTAssertEqual(decoded.maxSize, 65_536)
    }

    /// maxSize == nil must round-trip as absent (encodeIfPresent/decodeIfPresent).
    func testCacheEntryCodableOptionalMaxSize() throws {
        let entry = CacheEntry(logicalPos: 1, physicalPos: 2, size: 3, maxSize: nil)
        let decoded = try JSONDecoder().decode(CacheEntry.self,
                                               from: JSONEncoder().encode(entry))
        XCTAssertNil(decoded.maxSize)
        XCTAssertFalse(decoded.eof)   // init defaults eof = false
    }

    /// Bounds-check (slot 10 @0x1019e29e4): true when size > 16MB, or maxSize present
    /// and maxSize < size + length; else false.
    func testCacheEntryIsExceeded() {
        // size > 16MB → true regardless of maxSize
        XCTAssertTrue(CacheEntry(logicalPos: 0, physicalPos: 0,
                                 size: 0x100_0001, maxSize: nil).isExceeded(0))
        // size <= 16MB, no maxSize → false
        XCTAssertFalse(CacheEntry(logicalPos: 0, physicalPos: 0,
                                  size: 100, maxSize: nil).isExceeded(0))
        // maxSize < size + length → true
        XCTAssertTrue(CacheEntry(logicalPos: 0, physicalPos: 0,
                                 size: 100, maxSize: 150).isExceeded(60))   // 160 > 150
        // maxSize >= size + length → false
        XCTAssertFalse(CacheEntry(logicalPos: 0, physicalPos: 0,
                                  size: 100, maxSize: 150).isExceeded(40))  // 140 <= 150
    }

    // MARK: 1C.3 — DirectoryWatcher

    /// `DirectoryWatcher` is an `actor` whose only field `source` starts nil, so
    /// `isWatching` is false right after init (binary: init sets *(self+0x70)=0;
    /// isWatching returns *(self+0x70) != 0). Actor-isolated → `await`.
    func testDirectoryWatcherInitialState() async {
        let w = DirectoryWatcher()
        let watching = await w.isWatching          // actor-isolated → await
        XCTAssertFalse(watching)                    // source == nil at init
    }

    // MARK: 1C.9 — L3 capability (CacheIOContext construct + IO/cancellation surface)

    /// Phase-1 L3 capability test (REDUCED scope, forced by the binary). CacheIOContext's
    /// `read` is FFmpeg-monolithic in Forward 1.3.17 (the cache-read is not separable from
    /// the stripped-FFmpeg download branch) → UNRESOLVED→P2, so FUNCTIONAL read/cancel is
    /// deferred. This asserts the reconstructed Phase-1 surface: the cache context
    /// CONSTRUCTS, its fields init to the binary defaults, the cancellation field
    /// (`interrupt: AVIOInterruptCB?` — NOT the plan's draft `interruptContext.makeToken()`)
    /// is present, and the inherited `getContext()` bridges to an FFmpeg AVIOContext without
    /// crashing. Functional read-returns->0 / cancel-returns--1 → P2.
    func testCacheIOContextConstructsAndBridges() {
        let ctx = CacheIOContext(cacheKey: "phase1-l3",
                                 formatContextOptions: nil,
                                 interrupt: nil,
                                 saveFile: false,
                                 isReadComplete: false)
        XCTAssertEqual(ctx.bytesRead, 0)        // init default (UInt64)
        XCTAssertTrue(ctx.entryList.isEmpty)     // init default [] ([CacheFileEntry])
        XCTAssertNil(ctx.interrupt)              // cancellation surface present, nil as passed
        XCTAssertFalse(ctx.isReadComplete)       // init param
        // getContext() (inherited AbstractAVIOContext, 1C.4) allocs an FFmpeg AVIOContext
        // wrapping this context's IO callbacks — the L3 IO-bridge capability. Calling it
        // without crashing is the assertion (reading THROUGH it is the P2 functional path).
        // (One-time AVIOContext alloc; intentionally not freed — test-process-scoped.)
        _ = ctx.getContext()
    }
}
