import CoreGraphics
import Foundation

/// Classify events and track held controls. The caller owns tap installation and event delivery.
/// Pass monotonic uptime. Block PIDs of zero or less because they are indistinguishable from physical input.
public struct SessionInputFilter {
    private struct Hold {
        let startedAt: TimeInterval
        var requested = false
    }

    private let unlockHoldSeconds: Double
    private var pressedKeys: Set<CGKeyCode> = []
    private var pressedButtons: Set<Int64> = []
    private var holds: [CGKeyCode: Hold] = [:]
    private var unlockRequested = false
    private var escapeRequested = false

    public private(set) var isEngaged = false
    public var isDraining: Bool { !isEngaged && hasPressedControls }
    public var hasPressedControls: Bool { !pressedKeys.isEmpty || !pressedButtons.isEmpty }

    public init(unlockHoldSeconds: Double = 5) {
        self.unlockHoldSeconds = unlockHoldSeconds
    }

    public mutating func engage(pressedKeys: Set<CGKeyCode> = [], pressedButtons: Set<Int64> = []) {
        // Keep tracking controls that are still held when protection is restarted.
        self.pressedKeys.formUnion(pressedKeys.subtracting([57]))
        self.pressedButtons.formUnion(pressedButtons)
        holds.removeAll()
        unlockRequested = false
        escapeRequested = false
        isEngaged = true
    }

    public mutating func release(afterSessionLock: Bool = false) {
        isEngaged = false
        holds.removeAll()
        unlockRequested = false
        escapeRequested = false
        if afterSessionLock {
            pressedKeys = []
            pressedButtons = []
        }
    }

    /// Return true to pass the event through, or false for the caller to drop it.
    public mutating func handle(type: CGEventType, event: CGEvent, now: TimeInterval) -> Bool {
        switch type {
        case .keyDown, .keyUp, .flagsChanged,
             .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp, .mouseMoved,
             .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel:
            break
        default:
            return true
        }
        guard isEngaged || isDraining else { return true }
        guard event.getIntegerValueField(.eventSourceUnixProcessID) <= 0 else { return true }

        // Record a completed hold before processing the release so it is available to the next poll.
        settleDueHolds(now: now)
        // Block and track new physical input while draining.
        // Wait for all controls to be released so held modifiers do not carry over to new key presses.
        switch type {
        case .keyDown:
            let code = CGKeyCode(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            guard code != 57 else { return false }
            let wasNew = pressedKeys.insert(code).inserted
            if isEngaged, wasNew, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                holds[code] = Hold(startedAt: now)
            }
        case .keyUp:
            let code = CGKeyCode(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            pressedKeys.remove(code)
            holds.removeValue(forKey: code)
        case .flagsChanged:
            let code = CGKeyCode(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            // Caps Lock reports a toggle without creating a held state.
            guard [54, 55, 56, 58, 59, 60, 61, 62, 63].contains(code) else { return false }
            if pressedKeys.remove(code) != nil {
                holds.removeValue(forKey: code)
            } else {
                pressedKeys.insert(code)
                if isEngaged { holds[code] = Hold(startedAt: now) }
            }
        case .leftMouseDown:
            pressedButtons.insert(0)
        case .rightMouseDown:
            pressedButtons.insert(1)
        case .otherMouseDown:
            pressedButtons.insert(event.getIntegerValueField(.mouseEventButtonNumber))
        case .leftMouseUp:
            pressedButtons.remove(0)
        case .rightMouseUp:
            pressedButtons.remove(1)
        case .otherMouseUp:
            pressedButtons.remove(event.getIntegerValueField(.mouseEventButtonNumber))
        default:
            break
        }
        return false
    }

    public mutating func takeUnlockRequest(now: TimeInterval) -> Bool {
        settleDueHolds(now: now)
        let requested = unlockRequested
        unlockRequested = false
        return requested
    }

    public mutating func takeEscapeRequest(now: TimeInterval) -> Bool {
        settleDueHolds(now: now)
        let requested = escapeRequested
        escapeRequested = false
        return requested
    }

    private mutating func settleDueHolds(now: TimeInterval) {
        guard isEngaged else { return }
        for (code, hold) in holds where !hold.requested {
            let duration = code == 53 ? 10 : unlockHoldSeconds
            if now - hold.startedAt >= duration {
                holds[code]?.requested = true
                if code == 53 { escapeRequested = true } else { unlockRequested = true }
            }
        }
    }
}
