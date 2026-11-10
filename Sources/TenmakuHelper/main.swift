import Foundation
import IOKit
import IOKit.hid
import IOKit.pwr_mgt
import TenmakuShared

private let seizeOption = IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
private let drainTimeoutSeconds = 30.0
private let escapeHoldSeconds = 10.0
private let escapeUsage = UInt32(kHIDUsage_KeyboardEscape)

private struct PressedControl: Hashable {
    let device: UInt64
    let page: UInt32
    let usage: UInt32
}

final class InputLayer: NSObject, ShieldLayer, @unchecked Sendable {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    // Deduplicate by registry ID because a device can match more than one usage.
    private var seized: [UInt64: IOHIDDevice] = [:]
    private var engaged = false
    private var complete = false
    private var pressed: Set<PressedControl> = []
    private var draining = false
    private var unlockRequested = false
    private var escapeRequested = false
    private var holds: [PressedControl: DispatchWorkItem] = [:]
    private var unlockHoldSeconds = Double(defaultUnlockHoldSeconds)
    private var generation = 0
    private var sleepAssertion: IOPMAssertionID?
    #if TENMAKU_TEST_BUILD
    private var crashWatcher: DispatchSourceTimer?
    #endif

    override init() {
        super.init()
        let usages = [kHIDUsage_GD_Keyboard, kHIDUsage_GD_Keypad, kHIDUsage_GD_Mouse, kHIDUsage_GD_Pointer]
        let matching = usages.map { [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: $0] }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            Unmanaged<InputLayer>.fromOpaque(context!).takeUnretainedValue().deviceAppeared(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            Unmanaged<InputLayer>.fromOpaque(context!).takeUnretainedValue().deviceRemoved(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    func preflight(reply: @escaping @Sendable (String?) -> Void) {
        DispatchQueue.main.async { [self] in
            guard !engaged else { return reply(nil) }
            guard let device = physicalDevices().first else { return reply("No input devices were found.") }
            let result = IOHIDDeviceOpen(device, seizeOption)
            guard result == kIOReturnSuccess else {
                reply("Check the Input Monitoring permission (\(String(format: "0x%08x", result))).")
                // The running daemon does not pick up permission changes. Restart it on the next connection.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(0) }
                return
            }
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            reply(nil)
        }
    }

    func engage(reply: @escaping @Sendable (String?) -> Void) {
        DispatchQueue.main.async { [self] in
            let devices = physicalDevices()
            guard !devices.isEmpty else { return reply("No input devices were found.") }
            engaged = true
            complete = true
            draining = false
            unlockRequested = false
            escapeRequested = false
            for device in devices where !seize(device) {
                stop()
                return reply("Could not seize the input devices.")
            }
            preventIdleSleep()
            generation += 1
            #if TENMAKU_TEST_BUILD
            let current = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + testAutoReleaseSeconds) { [self] in
                if current == generation { stop() }
            }
            watchForTestCrash()
            #endif
            reply(nil)
        }
    }

    func release(reply: @escaping @Sendable (String?) -> Void) {
        DispatchQueue.main.async { [self] in
            stop()
            reply(nil)
        }
    }

    func isIdle() -> Bool {
        !engaged && seized.isEmpty
    }

    func setUnlockHold(seconds: Double, reply: @escaping @Sendable (String?) -> Void) {
        DispatchQueue.main.async { [self] in
            unlockHoldSeconds = seconds
            reply(nil)
        }
    }

    func takeUnlockRequest(reply: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.main.async { [self] in
            reply(unlockRequested)
            unlockRequested = false
        }
    }

    func takeEscapeRequest(reply: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.main.async { [self] in
            reply(escapeRequested)
            escapeRequested = false
        }
    }

    func sessionIsLocked(uid: UInt32, reply: @escaping @Sendable (Bool) -> Void) {
        reply(consoleSessionIsLocked(uid: uid) == true)
    }

    func isEngaged(reply: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.main.async { [self] in
            reply(engaged && complete && !seized.isEmpty)
        }
    }

    #if TENMAKU_TEST_BUILD
    // The test user cannot force-quit a process running as root.
    private func watchForTestCrash() {
        guard crashWatcher == nil else { return }
        let path = "/private/tmp/tenmaku-test-crash-helper"
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(50))
        timer.setEventHandler {
            guard FileManager.default.fileExists(atPath: path) else { return }
            try? FileManager.default.removeItem(atPath: path)
            kill(getpid(), SIGKILL)
        }
        timer.resume()
        crashWatcher = timer
    }
    #endif

    // Prevent the displays and Mac from sleeping while idle so Codex and Claude can keep working.
    private func preventIdleSleep() {
        guard sleepAssertion == nil else { return }
        var id = IOPMAssertionID(0)
        // A sleep assertion failure leaves shielding and input blocking available, so proceed with activation.
        guard IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Tenmaku lock" as CFString,
            &id
        ) == kIOReturnSuccess else { return }
        sleepAssertion = id
    }

    private func allowIdleSleep() {
        guard let id = sleepAssertion else { return }
        IOPMAssertionRelease(id)
        sleepAssertion = nil
    }

    // Releasing a device with controls held can send a press to the desktop. Keep the device seized until those controls are released.
    private func stop() {
        generation += 1
        engaged = false
        allowIdleSleep()
        holds.values.forEach { $0.cancel() }
        holds = [:]
        for id in Array(seized.keys) where !isPressed(id) { close(id) }
        guard !seized.isEmpty else { return }
        draining = true
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + drainTimeoutSeconds) { [self] in
            guard draining, current == generation else { return }
            draining = false
            Array(seized.keys).forEach(close)
        }
    }

    private func isPressed(_ id: UInt64) -> Bool {
        pressed.contains { $0.device == id }
    }

    private func close(_ id: UInt64) {
        guard let device = seized.removeValue(forKey: id) else { return }
        IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        pressed = pressed.filter { $0.device != id }
    }

    private func physicalDevices() -> [IOHIDDevice] {
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        var unique: [UInt64: IOHIDDevice] = [:]
        for device in devices where isPhysical(device) {
            unique[registryID(device)] = device
        }
        return Array(unique.values)
    }

    private func isPhysical(_ device: IOHIDDevice) -> Bool {
        IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String != "Virtual"
    }

    private func registryID(_ device: IOHIDDevice) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id)
        return id
    }

    private func seize(_ device: IOHIDDevice) -> Bool {
        let id = registryID(device)
        guard seized[id] == nil else { return true }
        guard IOHIDDeviceOpen(device, seizeOption) == kIOReturnSuccess else { return false }
        seized[id] = device
        IOHIDDeviceRegisterInputValueCallback(device, { context, _, _, value in
            Unmanaged<InputLayer>.fromOpaque(context!).takeUnretainedValue().valueChanged(value)
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        return true
    }

    private func valueChanged(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let isKey = page == kHIDPage_KeyboardOrKeypad && (4...231).contains(usage)
        guard isKey || page == kHIDPage_Button else { return }
        let isEscape = page == kHIDPage_KeyboardOrKeypad && usage == escapeUsage
        let control = PressedControl(device: registryID(IOHIDElementGetDevice(element)), page: page, usage: usage)
        if IOHIDValueGetIntegerValue(value) != 0 {
            pressed.insert(control)
            if isKey && engaged { beginHold(control, isEscape: isEscape) }
        } else {
            pressed.remove(control)
            holds.removeValue(forKey: control)?.cancel()
            if draining, !isPressed(control.device) {
                close(control.device)
                draining = !seized.isEmpty
            }
        }
    }

    // Using Esc to request unlock would start Touch ID during the 10-second hold.
    private func beginHold(_ control: PressedControl, isEscape: Bool) {
        holds[control]?.cancel()
        let hold = DispatchWorkItem { [self] in
            holds[control] = nil
            if isEscape { escapeRequested = true } else { unlockRequested = true }
        }
        holds[control] = hold
        DispatchQueue.main.asyncAfter(deadline: .now() + (isEscape ? escapeHoldSeconds : unlockHoldSeconds), execute: hold)
    }

    private func deviceAppeared(_ device: IOHIDDevice) {
        guard engaged, isPhysical(device), !seize(device) else { return }
        complete = false
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        let id = registryID(device)
        seized[id] = nil
        pressed = pressed.filter { $0.device != id }
        for control in holds.keys where control.device == id {
            holds.removeValue(forKey: control)?.cancel()
        }
    }
}

if CommandLine.arguments.contains(requestInputMonitoringArgument) {
    IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    exit(0)
}

let layer = InputLayer()
let listener = LayerListener(service: .input, layer: layer)
listener.resume()
exitWhenIdle { [layer] in layer.isIdle() }
RunLoop.main.run()
