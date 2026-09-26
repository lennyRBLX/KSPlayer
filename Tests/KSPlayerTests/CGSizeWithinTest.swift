@testable import KSPlayer
import XCTest

final class CGSizeWithinTest: XCTestCase {
    func testWithinPreservesExactAspectRatio() {
        let result = CGSize(width: 1920, height: 1080).within(ratio: 16.0 / 9.0)

        XCTAssertEqual(result.width, 1920)
        XCTAssertEqual(result.height, 1080)
    }

    func testWithinFitsByWidthWithIntegerConversions() {
        let result = CGSize(width: 801.75, height: 601.5).within(ratio: 2)

        XCTAssertEqual(result.width, 801)
        XCTAssertEqual(result.height, 400)
    }

    func testWithinFitsByHeightWithIntegerConversions() {
        let result = CGSize(width: 1000.75, height: 500.75).within(ratio: 1.5)

        XCTAssertEqual(result.width, 751)
        XCTAssertEqual(result.height, 500)
    }

    func testWithinReturnsSelfWhenIntegerWidthsMatch() {
        let size = CGSize(width: 8.9, height: 4.1)

        let result = size.within(ratio: 2)

        XCTAssertEqual(result.width, size.width)
        XCTAssertEqual(result.height, size.height)
    }

    func testWithinAllowsZeroWidth() {
        let result = CGSize(width: 0, height: 100).within(ratio: 2)

        XCTAssertEqual(result.width, 0)
        XCTAssertEqual(result.height, 0)
    }

    func testWithinReturnsSelfForPositiveAndNegativeZeroRatios() {
        let size = CGSize(width: 12.75, height: 8.5)

        let positiveZero = size.within(ratio: 0)
        let negativeZero = size.within(ratio: -Double.zero)

        XCTAssertEqual(positiveZero.width, size.width)
        XCTAssertEqual(positiveZero.height, size.height)
        XCTAssertEqual(negativeZero.width, size.width)
        XCTAssertEqual(negativeZero.height, size.height)
    }
}
