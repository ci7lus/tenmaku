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
        proxy.preflight { error in
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
}

private final class FailureResponder: NSObject, NSXPCListenerDelegate, ShieldLayer {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: ShieldLayer.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func preflight(reply: @escaping @Sendable (NSError?) -> Void) {
        reply(LayerFailure.inputMonitoringDenied.error(status: -536870174))
    }
    func engage(reply: @escaping @Sendable (NSError?) -> Void) { reply(nil) }
    func release(afterSessionLock: Bool, reply: @escaping @Sendable (NSError?) -> Void) { reply(nil) }
    func setUnlockHold(seconds: Double, reply: @escaping @Sendable (NSError?) -> Void) { reply(nil) }
    func isEngaged(reply: @escaping @Sendable (Bool) -> Void) { reply(false) }
    func takeUnlockRequest(reply: @escaping @Sendable (Bool) -> Void) { reply(false) }
    func takeEscapeRequest(reply: @escaping @Sendable (Bool) -> Void) { reply(false) }
    func hasProtection(reply: @escaping @Sendable (Bool) -> Void) { reply(false) }
}
