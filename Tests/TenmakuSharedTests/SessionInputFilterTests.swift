import CoreGraphics
import Foundation
import XCTest
@testable import TenmakuShared

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition { throw CheckFailure(description: message) }
}

// Create CGEvents without installing an event tap or posting events.
private func event(pid: Int64 = 0, key: CGKeyCode? = nil, button: Int64? = nil, repeating: Bool = false) -> CGEvent {
    let event = CGEvent(source: nil)!
    if let key {
        event.type = .keyDown
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(key))
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeating ? 1 : 0)
    } else if let button {
        event.type = .otherMouseDown
        event.setIntegerValueField(.mouseEventButtonNumber, value: button)
    }
    // Keep keyboard and mouse fields on separate CGEvents.
    event.setIntegerValueField(.eventSourceUnixProcessID, value: pid)
    return event
}

final class SessionInputFilterTests: XCTestCase {
    func testMissedKeyUpKeepsInputBlockedUntilConfirmedSystemLock() throws {
        var filter = SessionInputFilter()
        filter.engage()
        _ = filter.handle(type: .keyDown, event: event(key: 0), now: 0)
        // If Secure Event Input hides a release event, keep tracking the held input through normal unlock.
        filter.release(afterSessionLock: false)
        try expect(filter.isDraining, "Held input passed through before its release was confirmed")
        try expect(!filter.handle(type: .mouseMoved, event: event(), now: 10), "Input passed through while waiting for release")
        // The caller can release input again after verifying the lock screen is active so macOS can receive authentication input.
        filter.release(afterSessionLock: true)
        try expect(!filter.isDraining && !filter.hasPressedControls, "Input remained blocked after the lock was confirmed")
        try expect(filter.handle(type: .keyDown, event: event(key: 0), now: 11), "Input could not reach macOS authentication")
    }

    // Pass physical input while the filter is inactive.
    func testIdleInput() throws {
        var filter = SessionInputFilter()
        try expect(filter.handle(type: .keyDown, event: event(), now: 0), "A key press was blocked while the filter was inactive")
        try expect(!filter.isEngaged && !filter.isDraining && !filter.hasPressedControls, "The inactive filter tracked input as pressed")
    }

    // Block all in-scope PID 0 events while the filter is engaged.
    func testPhysicalInput() throws {
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .mouseMoved,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]
        for type in types {
            var filter = SessionInputFilter()
            filter.engage()
            try expect(!filter.handle(type: type, event: event(key: 56), now: 0), "In-scope event \(type.rawValue) passed through")
        }
    }

    // Block unknown sources the same way as PID 0.
    func testUnknownSource() throws {
        var filter = SessionInputFilter()
        filter.engage()
        // The field has no missing-value sentinel, so unknown and missing sources are both 0 at the API boundary.
        try expect(!filter.handle(type: .mouseMoved, event: event(pid: 0), now: 0), "An event from an unknown source passed through")
        try expect(!filter.handle(type: .keyDown, event: event(pid: -1), now: 0), "An event with a negative PID passed through")
    }

    // Pass events with positive PIDs without tracking them as presses or holds.
    func testSyntheticInput() throws {
        var filter = SessionInputFilter()
        filter.engage()
        try expect(filter.handle(type: .keyDown, event: event(pid: 1234, key: 1), now: 0), "A synthetic key press was blocked")
        try expect(filter.handle(type: .leftMouseDown, event: event(pid: 1234), now: 0), "A synthetic click was blocked")
        try expect(!filter.hasPressedControls, "Synthetic input counted as a physical press")
        try expect(!filter.takeUnlockRequest(now: 60), "Synthetic input made an unlock request")
        filter.release()
        try expect(!filter.isDraining, "Synthetic input left the filter draining")
    }

    // Key repeat preserves the original hold start and issues only one request.
    func testRepeatHold() throws {
        var filter = SessionInputFilter(unlockHoldSeconds: 5)
        filter.engage()
        _ = filter.handle(type: .keyDown, event: event(key: 0), now: 10)
        _ = filter.handle(type: .keyDown, event: event(key: 0, repeating: true), now: 14)
        try expect(!filter.takeUnlockRequest(now: 14.99), "A request was made before the hold threshold")
        try expect(filter.takeUnlockRequest(now: 15), "Key repeat extended the required hold")
        try expect(!filter.takeUnlockRequest(now: 20), "The same hold made repeated requests")
        _ = filter.handle(type: .keyDown, event: event(key: 0, repeating: true), now: 21)
        try expect(!filter.takeUnlockRequest(now: 30), "Key repeat made a second request")
        _ = filter.handle(type: .keyUp, event: event(key: 0), now: 31)
        _ = filter.handle(type: .keyDown, event: event(key: 0), now: 32)
        try expect(filter.takeUnlockRequest(now: 37), "Pressing the key again did not make a request")
    }

    // Request normal unlock after the configured hold duration.
    func testCustomHoldDuration() throws {
        var filter = SessionInputFilter(unlockHoldSeconds: 1.5)
        filter.engage()
        _ = filter.handle(type: .keyDown, event: event(key: 9), now: 2)
        try expect(!filter.takeUnlockRequest(now: 3.49), "A request was made before the configured hold threshold")
        try expect(filter.takeUnlockRequest(now: 3.5), "The configured hold duration was ignored")
    }

    // Holding a modifier also requests normal unlock.
    func testModifierHold() throws {
        var filter = SessionInputFilter(unlockHoldSeconds: 2)
        filter.engage()
        _ = filter.handle(type: .flagsChanged, event: event(key: 55), now: 1)
        try expect(filter.takeUnlockRequest(now: 3), "The filter missed a Command hold")
        try expect(!filter.takeUnlockRequest(now: 4), "A single Command hold made multiple requests")
    }

    // Track the left, right, and additional mouse buttons independently.
    func testMouseButtons() throws {
        var filter = SessionInputFilter()
        filter.engage()
        _ = filter.handle(type: .leftMouseDown, event: event(button: 0), now: 1)
        _ = filter.handle(type: .rightMouseDown, event: event(button: 1), now: 2)
        _ = filter.handle(type: .otherMouseDown, event: event(button: 2), now: 3)
        filter.release()
        _ = filter.handle(type: .leftMouseUp, event: event(button: 0), now: 4)
        try expect(filter.isDraining, "Releasing the left button also released the other buttons")
        _ = filter.handle(type: .rightMouseUp, event: event(button: 1), now: 5)
        try expect(filter.isDraining, "Releasing the right button also released the additional button")
        _ = filter.handle(type: .otherMouseUp, event: event(button: 2), now: 6)
        try expect(!filter.isDraining, "The filter kept draining after the additional button was released")
    }

    // Brief presses leave no unlock request.
    func testEarlyRelease() throws {
        var filter = SessionInputFilter(unlockHoldSeconds: 2)
        filter.engage()
        _ = filter.handle(type: .keyDown, event: event(key: 8), now: 1)
        _ = filter.handle(type: .keyUp, event: event(key: 8), now: 2.9)
        try expect(!filter.takeUnlockRequest(now: 100), "A released key made a request")
        try expect(!filter.hasPressedControls, "A released key remained tracked as pressed")
    }

    // Holding Esc for 10 seconds requests handoff only.
    func testEscapeHold() throws {
        var filter = SessionInputFilter(unlockHoldSeconds: 1)
        filter.engage()
        _ = filter.handle(type: .keyDown, event: event(key: 53), now: 4)
        try expect(!filter.takeUnlockRequest(now: 5), "Esc requested normal unlock")
        try expect(!filter.takeEscapeRequest(now: 13.99), "A request was made before the Esc hold threshold")
        try expect(filter.takeEscapeRequest(now: 14), "Holding Esc for 10 seconds did not make a request")
        try expect(!filter.takeEscapeRequest(now: 20), "A single Esc hold made multiple requests")
    }

    // Keep the normal unlock request until the next poll when the key is released after the threshold.
    func testReleasedHoldRequest() throws {
        var filter = SessionInputFilter()
        filter.engage()
        _ = filter.handle(type: .keyDown, event: event(key: 0), now: 0)
        _ = filter.handle(type: .keyUp, event: event(key: 0), now: 5.1)
        try expect(filter.takeUnlockRequest(now: 5.2), "The request from holding for more than 5 seconds disappeared on release")
        try expect(!filter.takeUnlockRequest(now: 5.3), "The same hold returned another request")
    }

    // Releasing a regular key just before the threshold leaves no request.
    func testEarlyHoldRelease() throws {
        var filter = SessionInputFilter()
        filter.engage()
        _ = filter.handle(type: .keyDown, event: event(key: 0), now: 0)
        _ = filter.handle(type: .keyUp, event: event(key: 0), now: 4.9)
        try expect(!filter.takeUnlockRequest(now: 5.2), "A hold shorter than 5 seconds left a request")
    }

    // Keep the Esc request until the next poll when Esc is released after the threshold.
    func testReleasedEscapeRequest() throws {
        var filter = SessionInputFilter()
        filter.engage()
        _ = filter.handle(type: .keyDown, event: event(key: 53), now: 0)
        _ = filter.handle(type: .keyUp, event: event(key: 53), now: 10.1)
        try expect(!filter.takeUnlockRequest(now: 10.2), "Esc left a normal unlock request")
        try expect(filter.takeEscapeRequest(now: 10.2), "The request from holding Esc for more than 10 seconds disappeared on release")
        try expect(!filter.takeEscapeRequest(now: 10.3), "The same Esc hold returned another request")
    }

    // Releasing Esc just before the threshold leaves no request.
    func testEarlyEscapeRelease() throws {
        var filter = SessionInputFilter()
        filter.engage()
        _ = filter.handle(type: .keyDown, event: event(key: 53), now: 0)
        _ = filter.handle(type: .keyUp, event: event(key: 53), now: 9.9)
        try expect(!filter.takeEscapeRequest(now: 10.2), "Holding Esc for less than 10 seconds left a request")
    }

    // Unlocking and reengaging cancel pending requests.
    func testReleaseAndReengageClearRequests() throws {
        var filter = SessionInputFilter()
        filter.engage()
        _ = filter.handle(type: .keyDown, event: event(key: 0), now: 0)
        _ = filter.handle(type: .keyUp, event: event(key: 0), now: 5.1)
        filter.release()
        try expect(!filter.takeUnlockRequest(now: 5.2), "A pending request remained after unlock")
        filter.engage()
        _ = filter.handle(type: .keyDown, event: event(key: 53), now: 6)
        _ = filter.handle(type: .keyUp, event: event(key: 53), now: 16.1)
        filter.engage()
        try expect(!filter.takeEscapeRequest(now: 16.2), "An earlier Esc request remained after reengaging")
    }

    // Releasing a modifier resets its hold.
    func testModifierRelease() throws {
        var filter = SessionInputFilter(unlockHoldSeconds: 2)
        filter.engage()
        _ = filter.handle(type: .flagsChanged, event: event(key: 56), now: 1)
        try expect(filter.hasPressedControls, "The filter missed the Shift press")
        _ = filter.handle(type: .flagsChanged, event: event(key: 56), now: 2)
        try expect(!filter.hasPressedControls, "The filter missed the Shift release")
        try expect(!filter.takeUnlockRequest(now: 100), "A released Shift key made a request")
    }

    // Toggling Caps Lock leaves no hold or drain state.
    func testCapsLock() throws {
        var filter = SessionInputFilter()
        filter.engage(pressedKeys: [57])
        _ = filter.handle(type: .flagsChanged, event: event(key: 57), now: 0)
        try expect(!filter.takeUnlockRequest(now: 100), "Toggling Caps Lock made a request")
        filter.release()
        try expect(!filter.isDraining && !filter.hasPressedControls, "Toggling Caps Lock left the filter draining")
    }

    // Track input held before engagement and block it until release after unlock.
    func testInitialPressedControls() throws {
        var filter = SessionInputFilter()
        filter.engage(pressedKeys: [12], pressedButtons: [0])
        try expect(filter.isEngaged && filter.hasPressedControls, "The filter lost track of a press from before engagement")
        try expect(!filter.takeUnlockRequest(now: 100), "A press from before engagement made a new unlock request")
        filter.release()
        try expect(!filter.isEngaged && filter.isDraining, "Held input was unblocked on unlock")
        try expect(!filter.handle(type: .keyDown, event: event(key: 12, repeating: true), now: 10000), "Repeat events from a held key passed through")
        try expect(!filter.handle(type: .keyUp, event: event(key: 12), now: 10001), "Release of a held key passed through")
        try expect(filter.isDraining, "Draining ended while a button was still held")
        try expect(!filter.handle(type: .leftMouseUp, event: event(), now: 10002), "Release of a held button passed through")
        try expect(!filter.isDraining && !filter.hasPressedControls, "The filter kept draining after all controls were released")
        try expect(filter.handle(type: .keyDown, event: event(key: 12), now: 10003), "A new key press was blocked after draining")
    }

    // Block new physical input during draining until it is released.
    func testDrainingInput() throws {
        var filter = SessionInputFilter()
        filter.engage(pressedKeys: [56])
        filter.release()
        try expect(!filter.handle(type: .keyDown, event: event(key: 0), now: 1), "A new key press passed through while Shift was held")
        try expect(filter.handle(type: .keyDown, event: event(pid: 1234, key: 0), now: 1), "A synthetic key press was blocked while draining")
        try expect(!filter.handle(type: .flagsChanged, event: event(key: 56), now: 2), "The held Shift key release passed through")
        try expect(filter.isDraining, "Draining ended before the newly pressed key was released")
        try expect(!filter.handle(type: .mouseMoved, event: event(), now: 3), "Pointer movement passed through while draining")
        try expect(!filter.handle(type: .keyUp, event: event(key: 0), now: 4), "Release of a newly pressed physical key passed through")
        try expect(!filter.isDraining, "The filter kept draining after the new physical key was released")
    }

    // Synthetic release events leave held physical input in place.
    func testSyntheticRelease() throws {
        var filter = SessionInputFilter()
        filter.engage(pressedKeys: [0])
        filter.release()
        try expect(filter.handle(type: .keyUp, event: event(pid: 1234, key: 0), now: 1), "A synthetic release was blocked")
        try expect(filter.isDraining, "A synthetic release ended draining for physical input")
        _ = filter.handle(type: .keyUp, event: event(key: 0), now: 2)
        try expect(!filter.isDraining, "The filter kept draining after the physical key was released")
    }

    // Reengaging preserves held input and cancels earlier hold requests.
    func testReengage() throws {
        var filter = SessionInputFilter()
        filter.engage()
        _ = filter.handle(type: .keyDown, event: event(key: 1), now: 1)
        filter.release()
        filter.engage()
        try expect(filter.isEngaged && !filter.isDraining && filter.hasPressedControls, "The filter lost track of held input on reengagement")
        try expect(!filter.takeUnlockRequest(now: 100), "An earlier hold made a request after reengaging")
        _ = filter.handle(type: .keyUp, event: event(key: 1), now: 101)
        _ = filter.handle(type: .keyDown, event: event(key: 1), now: 102)
        try expect(filter.takeUnlockRequest(now: 107), "A new hold did not make a request after reengaging")
        filter.release()
        try expect(!filter.takeUnlockRequest(now: 200) && !filter.takeEscapeRequest(now: 200), "A request remained after unlock")
    }

    // Pass out-of-scope events while the filter is engaged.
    func testUnrelatedEvent() throws {
        var filter = SessionInputFilter()
        filter.engage()
        try expect(filter.handle(type: .null, event: event(), now: 0), "An out-of-scope event was blocked")
    }
}
