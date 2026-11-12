import AppKit

// Simulate the start notification and delay without changing displays or input.
enum ProtectionState: Equatable {
    case idle, starting, shielded, interrupted, handingOff(String), failed(String)
}
@MainActor
final class ProtectionController {
    var onChange: ((ProtectionState) -> Void)?
    var onBeforeEngage: (() async -> Void)?
    var unlockFailure: String?
    var engaged = false
    var canQuit: Bool { !engaged }
    var canRequestUnlock: Bool { engaged }
    func requestUnlock() {}
    func start() {
        onChange?(.starting)
        Task {
            try? await Task.sleep(for: .milliseconds(20))
            await onBeforeEngage?()
            engaged = true
            onChange?(.shielded)
        }
    }
}

@main
@MainActor
struct AnimationCheck {
    static func main() {
        _ = NSApplication.shared
        guard let bundle = Bundle(path: CommandLine.arguments[1]) else {
            fatalError("Specify the Tenmaku.app built by scripts/build.sh.")
        }
        for name in ["StatusOpen", "StatusClosed"] {
            let image = bundle.image(forResource: name)!
            image.setName(name)
        }
        check(throughMenu: true)
        check(throughMenu: false)
        checkFailure(closingFor: 0.5)
        checkFailure(closingFor: 0.2)
        checkRetryDuringOpening()
    }

    static func pixels(_ image: NSImage) -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 180, pixelsHigh: 180,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: 180, height: 180))
        NSGraphicsContext.restoreGraphicsState()
        return Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

    static func statusItem(_ status: StatusMenu) -> NSStatusItem {
        Mirror(reflecting: status).children.first { $0.label == "item" }!.value as! NSStatusItem
    }

    static func check(throughMenu: Bool) {
        let protection = ProtectionController()
        let status = StatusMenu(protection: protection, openSettings: {})
        let item = statusItem(status)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let closed = pixels(NSImage(named: "StatusClosed")!)
        let open = pixels(NSImage(named: "StatusOpen")!)
        let started = ContinuousClock.now
        if throughMenu {
            status.perform(NSSelectorFromString("startProtection"))
        } else {
            // Settings calls the controller directly.
            protection.start()
        }
        var frames = Set<Data>()
        while !protection.engaged && ContinuousClock.now - started < .seconds(2) {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0 / 120))
            frames.insert(pixels(item.button!.image!))
        }
        let elapsed = ContinuousClock.now - started
        let final = pixels(item.button!.image!)
        print("\(throughMenu ? "Menu" : "Settings"): \(elapsed) until shielding, \(frames.count) distinct frames, door closed at end: \(final == closed)")
        precondition(protection.engaged, "Locking did not start")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            precondition(frames.subtracting([open, closed]).count >= 8, "Shielding started before the intermediate frames appeared")
        }
        precondition(final == closed, "Shielding started before the door finished closing")
    }

    static func checkFailure(closingFor duration: TimeInterval) {
        let protection = ProtectionController()
        let status = StatusMenu(protection: protection, openSettings: {})
        let item = statusItem(status)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let open = pixels(NSImage(named: "StatusOpen")!)
        protection.onChange?(.starting)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: duration))
        let before = pixels(item.button!.image!)
        protection.onChange?(.failed("Simulated startup failure"))
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            precondition(pixels(item.button!.image!) == before, "The door jumped to a different position after failure")
        }
        let deadline = Date(timeIntervalSinceNow: 1)
        var frames = Set<Data>()
        while Date() < deadline, pixels(item.button!.image!) != open {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0 / 120))
            frames.insert(pixels(item.button!.image!))
        }
        precondition(pixels(item.button!.image!) == open, "The icon did not return to Open after locking failed")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            precondition(frames.subtracting([before, open]).count >= 3, "The door did not animate open after failure")
        }
        print("Failure (\(duration) seconds after starting): \(frames.count) intermediate opening frames, ended in Open")
    }

    static func checkRetryDuringOpening() {
        let protection = ProtectionController()
        let status = StatusMenu(protection: protection, openSettings: {})
        let item = statusItem(status)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let closed = pixels(NSImage(named: "StatusClosed")!)
        protection.onChange?(.shielded)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        protection.onChange?(.failed("Simulated startup failure"))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        let before = pixels(item.button!.image!)
        protection.start()
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            precondition(pixels(item.button!.image!) == before, "The door jumped to a different position on retry")
        }
        let deadline = Date(timeIntervalSinceNow: 2)
        while !protection.engaged && Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0 / 120))
        }
        precondition(protection.engaged && pixels(item.button!.image!) == closed, "Shielding started before the door closed on retry")
        print("Retry during opening: the door closed from its current position and shielding started after the delay")
    }
}
