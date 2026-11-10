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
    }

    static func check(throughMenu: Bool) {
        let protection = ProtectionController()
        let status = StatusMenu(protection: protection, openSettings: {})
        let item = Mirror(reflecting: status).children.first { $0.label == "item" }!.value as! NSStatusItem
        defer { NSStatusBar.system.removeStatusItem(item) }
        func pixels(_ image: NSImage) -> Data {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 180, pixelsHigh: 180,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            image.draw(in: NSRect(x: 0, y: 0, width: 180, height: 180))
            NSGraphicsContext.restoreGraphicsState()
            return Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        }
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
        precondition(protection.engaged, "Protection did not start")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            precondition(frames.subtracting([open, closed]).count >= 8, "Shielding started before the intermediate frames appeared")
        }
        precondition(final == closed, "Shielding started before the door finished closing")
    }
}
