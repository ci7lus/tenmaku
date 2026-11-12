import CoreGraphics
import XCTest
@testable import TenmakuShared

final class LockedScreenLayoutTests: XCTestCase {
    private let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let external = CGRect(x: -1920, y: 0, width: 1920, height: 1080)

    func testEveryDisplayNeedsFullCoverage() {
        let displays = [builtIn, external]
        XCTAssertFalse(LockedScreenLayout.coversDisplays(windows: [window(builtIn)], displays: displays))
        XCTAssertFalse(LockedScreenLayout.coversDisplays(
            windows: [window(builtIn), window(external.insetBy(dx: 1, dy: 0))], displays: displays
        ))
        XCTAssertTrue(LockedScreenLayout.coversDisplays(windows: [window(builtIn), window(external)], displays: displays))
        XCTAssertTrue(LockedScreenLayout.coversDisplays(windows: [window(builtIn.union(external))], displays: displays))
    }

    func testUnconfirmedWindowsCannotAuthorizeRelease() {
        XCTAssertFalse(LockedScreenLayout.coversDisplays(windows: [window(builtIn, alpha: 0.99)], displays: [builtIn]))
        XCTAssertFalse(LockedScreenLayout.coversDisplays(windows: [window(builtIn, owner: "Tenmaku")], displays: [builtIn]))
        XCTAssertFalse(LockedScreenLayout.coversDisplays(windows: [window(builtIn, layer: 2000)], displays: [builtIn]))
        XCTAssertFalse(LockedScreenLayout.coversDisplays(windows: [window(builtIn)], displays: []))
    }

    private func window(_ bounds: CGRect, owner: String = "loginwindow", alpha: Double = 1, layer: Int = 2001) -> [String: Any] {
        [
            kCGWindowBounds as String: bounds.dictionaryRepresentation,
            kCGWindowOwnerName as String: owner,
            kCGWindowAlpha as String: alpha,
            kCGWindowLayer as String: layer,
        ]
    }
}
