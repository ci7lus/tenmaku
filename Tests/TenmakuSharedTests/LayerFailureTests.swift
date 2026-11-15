import Foundation
import XCTest
@testable import TenmakuShared

final class LayerFailureTests: XCTestCase {
    func testWireErrorPreservesCodeAndStatusWithoutLocalizedText() throws {
        let error = LayerFailure.inputMonitoringDenied.error(status: -536870174)
        let data = try NSKeyedArchiver.archivedData(withRootObject: error, requiringSecureCoding: true)
        let decoded = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: NSError.self, from: data))
        XCTAssertEqual(decoded.domain, LayerFailure.domain)
        XCTAssertEqual(LayerFailure(rawValue: decoded.code), .inputMonitoringDenied)
        XCTAssertEqual(decoded.userInfo[LayerFailure.statusKey] as? Int32, -536870174)
        XCTAssertNil(decoded.userInfo[NSLocalizedDescriptionKey])
    }

    func testFailureCrossesTheShieldLayerXPCReply() throws {
        let responder = FailureResponder()
        let listener = NSXPCListener.anonymous()
        listener.delegate = responder
        listener.resume()
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: ShieldLayer.self)
        connection.resume()
        defer {
            connection.invalidate()
            listener.invalidate()
        }
        let received = expectation(description: "Receive a language-independent failure over XPC")
        let proxy = try XCTUnwrap(connection.remoteObjectProxyWithErrorHandler { error in
            XCTFail("XPC: \(error)")
            received.fulfill()
        } as? ShieldLayer)
        proxy.preflight(unlockHoldSeconds: 7, escapeHoldSeconds: 3) { error in
            XCTAssertEqual(error?.domain, LayerFailure.domain)
            XCTAssertEqual(error?.code, LayerFailure.inputMonitoringDenied.rawValue)
            XCTAssertEqual((error?.userInfo[LayerFailure.statusKey] as? NSNumber)?.int32Value, -536870174)
            XCTAssertNil(error?.userInfo[NSLocalizedDescriptionKey])
            received.fulfill()
        }
        wait(for: [received], timeout: 5)
        withExtendedLifetime(responder) {}
    }

    func testErrorWithoutStatusHasNoDiagnosticArguments() {
        let error = LayerFailure.inputControlStopped.error()
        XCTAssertEqual(LayerFailure(rawValue: error.code), .inputControlStopped)
        XCTAssertTrue(error.userInfo.isEmpty)
    }

    func testCoverControlExposesHandoffAndInheritedShieldLayerMethods() throws {
        let responder = FailureResponder()
        let listener = NSXPCListener.anonymous()
        listener.delegate = responder
        listener.resume()
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: CoverControl.self)
        connection.resume()
        defer {
            connection.invalidate()
            listener.invalidate()
        }
        let handoff = expectation(description: "Receive shielding confirmation for handoff over XPC")
        let protection = expectation(description: "Receive shared status over XPC")
        let layer = try XCTUnwrap(connection.remoteObjectProxyWithErrorHandler { error in
            XCTFail("XPC: \(error)")
        } as? ShieldLayer)
        let cover = try XCTUnwrap(layer as? CoverControl)
        cover.holdForHandoff { covered in
            XCTAssertTrue(covered)
            handoff.fulfill()
        }
        layer.hasProtection { held in
            XCTAssertFalse(held)
            protection.fulfill()
        }
        wait(for: [handoff, protection], timeout: 5)
        withExtendedLifetime(responder) {}
    }

    func testSelectedKeyReachesInputPreflightOverXPC() throws {
        let responder = FailureResponder(interface: NSXPCInterface(with: InputControl.self))
        let listener = NSXPCListener.anonymous()
        listener.delegate = responder
        listener.resume()
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: InputControl.self)
        connection.resume()
        defer {
            connection.invalidate()
            listener.invalidate()
        }
        let received = expectation(description: "Receive the configured release key over XPC")
        let input = try XCTUnwrap(connection.remoteObjectProxyWithErrorHandler { error in
            XCTFail("XPC: \(error)")
        } as? InputControl)
        input.preflight(unlockHoldSeconds: 7, escapeHoldSeconds: 3, unlockKeyUsage: UnlockKey.space.rawValue) { error in
            XCTAssertNil(error)
            received.fulfill()
        }
        wait(for: [received], timeout: 5)
        withExtendedLifetime(responder) {}
    }
}

private final class FailureResponder: NSObject, NSXPCListenerDelegate, CoverControl, InputControl {
    private let interface: NSXPCInterface

    init(interface: NSXPCInterface = NSXPCInterface(with: CoverControl.self)) {
        self.interface = interface
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = interface
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func preflight(unlockHoldSeconds: Double, escapeHoldSeconds: Double, reply: @escaping @Sendable (NSError?) -> Void) {
        reply(LayerFailure.inputMonitoringDenied.error(status: -536870174))
    }

    func preflight(unlockHoldSeconds: Double, escapeHoldSeconds: Double, unlockKeyUsage: Int, reply: @escaping @Sendable (NSError?) -> Void) {
        XCTAssertEqual(unlockHoldSeconds, 7)
        XCTAssertEqual(escapeHoldSeconds, 3)
        XCTAssertEqual(unlockKeyUsage, UnlockKey.space.rawValue)
        reply(nil)
    }

    func engage(unlockHoldSeconds: Double, escapeHoldSeconds: Double, reply: @escaping @Sendable (NSError?) -> Void) { reply(nil) }
    func engage(unlockHoldSeconds: Double, escapeHoldSeconds: Double, unlockKeyUsage: Int, reply: @escaping @Sendable (NSError?) -> Void) { reply(nil) }
    func release(afterSessionLock: Bool, reply: @escaping @Sendable (NSError?) -> Void) { reply(nil) }
    func isEngaged(reply: @escaping @Sendable (Bool) -> Void) { reply(false) }
    func takeUnlockRequest(reply: @escaping @Sendable (Bool) -> Void) { reply(false) }
    func takeEscapeRequest(reply: @escaping @Sendable (Bool) -> Void) { reply(false) }
    func hasProtection(reply: @escaping @Sendable (Bool) -> Void) { reply(false) }
    func restoreCover(reply: @escaping @Sendable (NSError?) -> Void) { reply(nil) }
    func holdForHandoff(reply: @escaping @Sendable (Bool) -> Void) { reply(true) }
}
