import XCTest
@testable import TenmakuShared

final class EmergencyCoverTests: XCTestCase {
    func testLateGammaResetRestartsFullWait() {
        var state = EmergencyCoverState.starting(deadline: 3)
        state.observe(.black(since: 0), allCovered: false, at: 0.1)
        XCTAssertTrue(state.isReady)
        state.requireCover()
        state.observe(.black(since: 1), allCovered: true, at: 1)
        state.observe(.unstable, allCovered: true, at: 6.4)
        state.observe(.black(since: 6.5), allCovered: true, at: 6.5)
        state.observe(.black(since: 6.5), allCovered: true, at: 12.4)
        XCTAssertTrue(state.needsCover)
        state.observe(.black(since: 6.5), allCovered: true, at: 12.5)
        XCTAssertTrue(state.isReady)
    }

    func testMissingDisplayAndNewConfigurationInvalidateRecovery() {
        var state = EmergencyCoverState.monitoring(blackSince: 0)
        state.requireCover()
        state.observe(.black(since: 0), allCovered: true, at: 0)
        state.observe(.black(since: 0), allCovered: false, at: 7)
        state.observe(.black(since: 0), allCovered: true, at: 8)
        state.requireCover()
        state.observe(.black(since: 0), allCovered: true, at: 14)
        XCTAssertTrue(state.needsCover)
    }

    func testGammaResetBetweenCoverPollsStillRestartsTheWait() {
        var state = EmergencyCoverState.covering(verifiedSince: nil)
        state.observe(.black(since: 1), allCovered: true, at: 1)
        state.observe(.black(since: 6), allCovered: true, at: 7)
        XCTAssertTrue(state.needsCover)
        state.observe(.black(since: 6), allCovered: true, at: 12)
        XCTAssertTrue(state.isReady)
    }

    func testGammaResetBetweenCoverPollsStartsCovering() throws {
        var gamma = GammaStability()
        var state = EmergencyCoverState.starting(deadline: 3)
        gamma.record(allBlack: true, at: 1)
        state.observe(.black(since: try XCTUnwrap(gamma.blackSince)), allCovered: false, at: 1)
        XCTAssertTrue(state.isReady)

        gamma.record(allBlack: false, at: 1.02)
        gamma.record(allBlack: true, at: 1.04)
        state.observe(.black(since: try XCTUnwrap(gamma.blackSince)), allCovered: false, at: 1.05)
        XCTAssertTrue(state.needsCover)
    }

    func testInactiveGammaOnlyGetsStartupGraceOnce() {
        var state = EmergencyCoverState.starting(deadline: 3)
        state.observe(.idle, allCovered: false, at: 1)
        XCTAssertFalse(state.needsCover)
        state.observe(.black(since: 1), allCovered: false, at: 2)
        state.observe(.idle, allCovered: false, at: 2.5)
        XCTAssertTrue(state.needsCover)
        state.observe(.idle, allCovered: true, at: 30)
        XCTAssertTrue(state.needsCover)
    }

    func testMissingGammaAtTheStartupDeadlineRequiresCover() {
        var state = EmergencyCoverState.starting(deadline: 3)
        state.observe(.idle, allCovered: false, at: 3)
        XCTAssertTrue(state.needsCover)
    }

    func testArmingMayAbortOnlyBeforeCoverIsRequested() {
        var state = EmergencyCoverState.starting(deadline: 3)
        XCTAssertTrue(state.canAbortArming)
        state.requireCover()
        XCTAssertTrue(state.needsCover)
        XCTAssertFalse(state.canAbortArming)

        let restoring = EmergencyCoverState.covering(verifiedSince: nil)
        XCTAssertTrue(restoring.needsCover)
        XCTAssertFalse(restoring.canAbortArming)
    }

    func testHandoffKeepsCoverThroughGammaRecoveryAndDisplayChanges() {
        var state = EmergencyCoverState.handoff
        state.requireCover()
        state.observe(.idle, allCovered: true, at: 1)
        state.observe(.black(since: 2), allCovered: true, at: 2)
        state.observe(.black(since: 2), allCovered: true, at: 8)
        XCTAssertTrue(state.needsCover)
        XCTAssertFalse(state.isReady)
    }

    func testGammaSamplingDoesNotCountTimeAcrossAnUnobservedGap() {
        var stability = GammaStability()
        stability.record(allBlack: true, at: 1)
        stability.record(allBlack: true, at: 1.2)
        XCTAssertEqual(stability.blackSince, 1)
        stability.record(allBlack: true, at: 2)
        XCTAssertEqual(stability.blackSince, 2)
        stability.record(allBlack: false, at: 2.1)
        XCTAssertNil(stability.blackSince)
    }

    func testGammaHealthSampleCrossesXPC() throws {
        let responder = GammaHealthResponder()
        let listener = NSXPCListener.anonymous()
        listener.delegate = responder
        listener.resume()
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: GammaHealth.self)
        connection.resume()
        defer {
            connection.invalidate()
            listener.invalidate()
        }
        let received = expectation(description: "Receive gamma status and timing over XPC")
        let proxy = try XCTUnwrap(connection.remoteObjectProxyWithErrorHandler { error in
            XCTFail("XPC: \(error)")
            received.fulfill()
        } as? GammaHealth)
        proxy.sample { active, blackSince in
            XCTAssertTrue(active)
            XCTAssertEqual(blackSince, 123.5)
            received.fulfill()
        }
        wait(for: [received], timeout: 5)
        withExtendedLifetime(responder) {}
    }
}

private final class GammaHealthResponder: NSObject, NSXPCListenerDelegate, GammaHealth {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: GammaHealth.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func sample(reply: @escaping @Sendable (Bool, Double) -> Void) {
        reply(true, 123.5)
    }
}
