import XCTest
@testable import TenmakuShared

final class InputHoldDurationsTests: XCTestCase {
    func testDefaultsKeepExistingHoldTimes() {
        XCTAssertEqual(InputHoldDurations.standard.seconds(isEscape: false), 5)
        XCTAssertEqual(InputHoldDurations.standard.seconds(isEscape: true), 10)
    }

    func testNormalAndEscapeDurationsAreIndependent() throws {
        let durations = try XCTUnwrap(InputHoldDurations(unlockSeconds: 7, escapeSeconds: 3))
        XCTAssertEqual(durations.seconds(isEscape: false), 7)
        XCTAssertEqual(durations.seconds(isEscape: true), 3)
        XCTAssertNotNil(InputHoldDurations(unlockSeconds: 1, escapeSeconds: 30))
        XCTAssertNotNil(InputHoldDurations(unlockSeconds: 30, escapeSeconds: 1))
    }

    func testInvalidDurationsAreRejectedBeforeUse() {
        for invalid in [0.0, -1, 31, .infinity, -.infinity, .nan] {
            XCTAssertNil(InputHoldDurations(unlockSeconds: invalid, escapeSeconds: 10))
            XCTAssertNil(InputHoldDurations(unlockSeconds: 5, escapeSeconds: invalid))
        }
    }
}
