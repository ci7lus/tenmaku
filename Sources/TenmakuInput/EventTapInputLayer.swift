import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import IOKit.pwr_mgt
import TenmakuShared

/// Unprivileged input control that runs independently of the UI.
final class EventTapInputLayer: NSObject, ShieldLayer, @unchecked Sendable {
    private var filter = SessionInputFilter()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var faulted = false
    private var sleepAssertion: IOPMAssertionID?
    private var generation = 0
    private var releaseReplies: [@Sendable (NSError?) -> Void] = []

    private static let eventTypes: [CGEventType] = [
        .keyDown, .keyUp, .flagsChanged, .mouseMoved,
        .leftMouseDown, .leftMouseUp, .leftMouseDragged,
        .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel,
    ]

    func preflight(unlockHoldSeconds: Double, escapeHoldSeconds: Double, reply: @escaping @Sendable (NSError?) -> Void) {
        DispatchQueue.main.async { [self] in
            guard InputHoldDurations(unlockSeconds: unlockHoldSeconds, escapeSeconds: escapeHoldSeconds) != nil else {
                return reply(LayerFailure.invalidUnlockHold.error())
            }
            if filter.isEngaged { return reply(isHealthy ? nil : LayerFailure.inputControlStopped.error()) }
            if filter.isDraining { return reply(LayerFailure.inputControlsHeld.error()) }
            if IsSecureEventInputEnabled() { return reply(LayerFailure.secureEventInput.error()) }
            if let failure = permissionFailure() { return reply(failure) }
            // A tap that includes mouse events can still be created without keyboard permissions, with only the key events removed from its mask.
            let keyboardMask = CGEventMask(1) << CGEventType.keyDown.rawValue | CGEventMask(1) << CGEventType.keyUp.rawValue
            guard let probe = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: keyboardMask,
                callback: { _, _, event, _ in Unmanaged.passUnretained(event) }, userInfo: nil),
                  let probeSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, probe, 0) else {
                return reply(LayerFailure.inputPermissionsMissing.error())
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), probeSource, .commonModes)
            let enabled = CGEvent.tapIsEnabled(tap: probe)
            CFMachPortInvalidate(probe)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), probeSource, .commonModes)
            reply(enabled ? nil : LayerFailure.inputControlStartFailed.error())
        }
    }

    func engage(unlockHoldSeconds: Double, escapeHoldSeconds: Double, reply: @escaping @Sendable (NSError?) -> Void) {
        DispatchQueue.main.async { [self] in
            guard let durations = InputHoldDurations(unlockSeconds: unlockHoldSeconds, escapeSeconds: escapeHoldSeconds) else {
                return reply(LayerFailure.invalidUnlockHold.error())
            }
            if filter.isEngaged { return reply(isHealthy ? nil : LayerFailure.inputControlStopped.error()) }
            if filter.isDraining { return reply(LayerFailure.inputControlsHeld.error()) }
            if IsSecureEventInputEnabled() { return reply(LayerFailure.secureEventInput.error()) }
            if let failure = permissionFailure() { return reply(failure) }
            let mask = Self.eventTypes.reduce(CGEventMask(0)) { $0 | CGEventMask(1) << $1.rawValue }
            guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: mask,
                callback: { _, type, event, context in
                    let layer = Unmanaged<EventTapInputLayer>.fromOpaque(context!).takeUnretainedValue()
                    return layer.handle(type: type, event: event)
                }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
                return reply(LayerFailure.inputControlStartFailed.error())
            }
            guard let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
                CFMachPortInvalidate(newTap)
                return reply(LayerFailure.inputControlMonitorFailed.error())
            }
            tap = newTap
            source = newSource
            faulted = false
            let keys = Set((0..<128).compactMap { code -> CGKeyCode? in
                let key = CGKeyCode(code)
                return CGEventSource.keyState(.hidSystemState, key: key) ? key : nil
            })
            let buttons = Set((0..<32).compactMap { number -> Int64? in
                guard let button = CGMouseButton(rawValue: UInt32(number)),
                      CGEventSource.buttonState(.hidSystemState, button: button) else { return nil }
                return Int64(number)
            })
            filter = SessionInputFilter(holdDurations: durations)
            filter.engage(pressedKeys: keys, pressedButtons: buttons)
            CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
            preventIdleSleep()
            generation += 1
            #if TENMAKU_TEST_BUILD
            let current = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + testAutoReleaseSeconds) { [self] in
                if generation == current { stop() }
            }
            #endif
            reply(isHealthy ? nil : LayerFailure.inputControlStartFailed.error())
        }
    }

    func release(afterSessionLock: Bool, reply: @escaping @Sendable (NSError?) -> Void) {
        DispatchQueue.main.async { [self] in
            if afterSessionLock, LockedScreenLayout.confirmed() == nil {
                return reply(LayerFailure.sessionLockUnconfirmed.error())
            }
            stop(afterSessionLock: afterSessionLock)
            guard filter.isDraining else {
                finishReleases(nil)
                return reply(nil)
            }
            releaseReplies.append(reply)
            let current = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
                guard generation == current, filter.isDraining else { return }
                // Keep the display shielded if Secure Event Input prevented receiving a release and the user still cannot interact.
                // Keep filtering here so the UI can maintain shielding and hand off to the system lock.
                finishReleases(LayerFailure.inputReleaseUnconfirmed.error())
            }
        }
    }

    func isEngaged(reply: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.main.async { [self] in reply(filter.isEngaged && isHealthy) }
    }

    func takeUnlockRequest(reply: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.main.async { [self] in reply(filter.takeUnlockRequest(now: ProcessInfo.processInfo.systemUptime)) }
    }

    func takeEscapeRequest(reply: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.main.async { [self] in reply(filter.takeEscapeRequest(now: ProcessInfo.processInfo.systemUptime)) }
    }

    func hasProtection(reply: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.main.async { [self] in reply(filter.isEngaged || filter.isDraining || tap != nil) }
    }

    func isIdle() -> Bool { !filter.isEngaged && !filter.isDraining }

    private var isHealthy: Bool {
        guard let tap else { return false }
        return !faulted && CFMachPortIsValid(tap) && CGEvent.tapIsEnabled(tap: tap) && permissionFailure() == nil
    }

    private func permissionFailure() -> NSError? {
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
            return LayerFailure.inputAccessibilityDenied.error()
        }
        guard CGPreflightListenEventAccess() else { return LayerFailure.inputListenDenied.error() }
        return nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Report the interruption to the monitor so it can hand off to the system lock.
            faulted = true
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let pass = filter.handle(type: type, event: event, now: ProcessInfo.processInfo.systemUptime)
        if !filter.isEngaged && !filter.isDraining {
            removeTap()
            finishReleases(nil)
        }
        return pass ? Unmanaged.passUnretained(event) : nil
    }

    private func stop(afterSessionLock: Bool = false) {
        generation += 1
        // The caller retries release after confirming the lock screen is present.
        // After handing off to macOS authentication, discard tracking for any release events that were missed.
        filter.release(afterSessionLock: afterSessionLock)
        if let assertion = sleepAssertion {
            IOPMAssertionRelease(assertion)
            sleepAssertion = nil
        }
        if !filter.isDraining { removeTap() }
    }

    private func finishReleases(_ failure: NSError?) {
        let replies = releaseReplies
        releaseReplies = []
        replies.forEach { $0(failure) }
    }

    private func removeTap() {
        if let tap { CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private func preventIdleSleep() {
        guard sleepAssertion == nil else { return }
        var assertion = IOPMAssertionID(0)
        if IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn), "Tenmaku lock" as CFString, &assertion) == kIOReturnSuccess {
            sleepAssertion = assertion
        }
    }
}
