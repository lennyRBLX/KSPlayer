@testable import KSPlayer
import XCTest

/// Phase-1 foundation tests. Task 1C.1: construction smoke test for the
/// IO-cancellation primitives. Cancel/isCancelled behavior is NOT in the
/// Forward 1.3.17 binary and is deferred to Task 1C.9 — do not add it here.
final class Phase1FoundationTest: XCTestCase {
    func testIOInterruptContextConstructs() {
        let ctx = IOInterruptContext { false }   // designated init: init(_ block:)
        XCTAssertFalse(ctx.flag)                 // initial flag == false (binary: self.flag = 0)
    }
}
