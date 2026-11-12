import AppKit

enum ProtectionIndicator {
    case unlocked
    case locked

    var imageName: String {
        switch self {
        case .unlocked: "StatusOpen"
        case .locked: "StatusClosed"
        }
    }
}

private let doorAnimationDuration = Duration.milliseconds(400)
private let doorAnimationFrameInterval = 1.0 / 60
private let statusIconViewBoxSide = 800.0
// The area between the walls below the roof, in viewBox units with the origin at the lower-left corner.
private let doorOpening = NSRect(x: 287, y: 112, width: 226, height: 359)

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let openSettings: () -> Void
    private let protection: ProtectionController
    private let stateItem = NSMenuItem(title: L10n.menuIdle(), action: nil, keyEquivalent: "")
    private let startItem = NSMenuItem(title: L10n.protectionStart(), action: nil, keyEquivalent: "")
    private let unlockItem = NSMenuItem(title: L10n.protectionUnlock(), action: nil, keyEquivalent: "")
    private let quitItem = NSMenuItem(title: L10n.menuQuit(), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    #if TENMAKU_TEST_BUILD
    private let stopItem = NSMenuItem(title: L10n.menuTestStop(), action: nil, keyEquivalent: "")
    #endif

    private var doorAnimation: Timer?
    private var doorAnimationStart = ContinuousClock.now
    private var doorProgress = 0.0
    private var doorAnimationFrom = 0.0
    private var doorAnimationTo = 0.0
    private var doorCloseCompletion: CheckedContinuation<Void, Never>?

    var indicator: ProtectionIndicator = .unlocked {
        didSet {
            // Repeated updates for the same state leave the door animation running.
            guard indicator != oldValue else { return }
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                startDoorAnimation()
            } else {
                applyIndicator()
            }
        }
    }

    init(protection: ProtectionController, openSettings: @escaping () -> Void) {
        self.protection = protection
        self.openSettings = openSettings
        super.init()

        applyIndicator()

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())

        startItem.target = self
        startItem.action = #selector(startProtection)
        menu.addItem(startItem)
        unlockItem.target = self
        unlockItem.action = #selector(requestUnlock)
        unlockItem.isEnabled = false
        menu.addItem(unlockItem)
        #if TENMAKU_TEST_BUILD
        startItem.title = L10n.menuTestStart()
        stopItem.target = self
        stopItem.action = #selector(stopProtection)
        stopItem.isEnabled = false
        menu.addItem(stopItem)
        observeTestCommands()
        #endif
        menu.addItem(.separator())

        let settings = NSMenuItem(title: L10n.menuSettings(), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(quitItem)

        item.menu = menu
        protection.onChange = { [weak self] state in self?.apply(state) }
        protection.onBeforeEngage = { [weak self] in await self?.waitForDoorClose() }
    }

    func menuWillOpen(_ menu: NSMenu) {
        quitItem.isEnabled = protection.canQuit
    }

    private func apply(_ state: ProtectionState) {
        switch state {
        case .idle: stateItem.title = L10n.menuIdle()
        case .starting: stateItem.title = L10n.menuStarting()
        case .shielded:
            stateItem.title = protection.unlockFailure.map { L10n.menuUnlockFailed($0) } ?? L10n.menuShielded()
        case .interrupted: stateItem.title = L10n.menuInterrupted()
        case .handingOff(let reason): stateItem.title = L10n.menuHandingOff(reason)
        case .failed(let reason): stateItem.title = L10n.menuFailed(reason)
        }
        switch state {
        case .idle, .failed: indicator = .unlocked
        case .starting, .shielded, .interrupted, .handingOff: indicator = .locked
        }
        startItem.isEnabled = state == .idle
        unlockItem.isEnabled = protection.canRequestUnlock
        if case .failed = state { startItem.isEnabled = true }
        #if TENMAKU_TEST_BUILD
        writeTestState()
        stopItem.isEnabled = state != .idle && state != .starting
        #endif
    }

    @objc private func startProtection() {
        protection.start()
    }

    @objc private func requestUnlock() {
        protection.requestUnlock()
    }

    #if TENMAKU_TEST_BUILD
    @objc private func stopProtection() {
        protection.stop()
    }

    // Automated tests cannot operate the menu if the icon is hidden by menu bar overflow.
    private func observeTestCommands() {
        let center = DistributedNotificationCenter.default()
        for (name, command) in [("start", startProtection), ("stop", stopProtection)] as [(String, () -> Void)] {
            nonisolated(unsafe) let command = command
            center.addObserver(forName: .init("jp.pronama.tenmaku.test.\(name)"), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { command() }
            }
        }
        writeTestState()
    }

    private func writeTestState() {
        let path = NSHomeDirectory() + "/Library/Caches/jp.pronama.tenmaku.test-state"
        try? stateItem.title.write(toFile: path, atomically: true, encoding: .utf8)
    }
    #endif

    private func applyIndicator() {
        doorAnimation?.invalidate()
        doorAnimation = nil
        doorProgress = indicator == .locked ? 1 : 0
        show(NSImage(named: indicator.imageName))
        doorCloseCompletion?.resume()
        doorCloseCompletion = nil
    }

    private func show(_ image: NSImage?) {
        image?.isTemplate = true
        image?.accessibilityDescription = "Tenmaku"
        item.button?.image = image
    }

    private func startDoorAnimation() {
        doorAnimation?.invalidate()
        doorAnimationFrom = doorProgress
        doorAnimationTo = indicator == .locked ? 1 : 0
        guard doorAnimationFrom != doorAnimationTo else {
            applyIndicator()
            return
        }
        doorAnimationStart = .now
        show(doorImage(progress: doorProgress))
        // Use the common run loop modes so the animation continues during menu tracking.
        let timer = Timer(timeInterval: doorAnimationFrameInterval, target: self, selector: #selector(advanceDoorAnimation), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        doorAnimation = timer
    }

    private func waitForDoorClose() async {
        guard indicator == .locked, doorAnimation != nil else { return }
        await withCheckedContinuation { doorCloseCompletion = $0 }
    }

    @objc private func advanceDoorAnimation() {
        let elapsed = (ContinuousClock.now - doorAnimationStart) / doorAnimationDuration
        guard elapsed < 1 else {
            applyIndicator()
            return
        }
        // Accelerate when closing and decelerate when opening. Resume from the current position on reversal.
        let eased = doorAnimationTo > doorAnimationFrom ? elapsed * elapsed : 1 - (1 - elapsed) * (1 - elapsed)
        doorProgress = doorAnimationFrom + (doorAnimationTo - doorAnimationFrom) * eased
        show(doorImage(progress: doorProgress))
    }

    private func doorImage(progress: Double) -> NSImage? {
        guard let open = NSImage(named: ProtectionIndicator.unlocked.imageName),
              let closed = NSImage(named: ProtectionIndicator.locked.imageName) else { return nil }
        return NSImage(size: open.size, flipped: false) { rect in
            open.draw(in: rect)
            // The images only differ at the door. Clip that region from the closed image and slide it in from above.
            let scale = rect.width / statusIconViewBoxSide
            let opening = NSRect(
                x: doorOpening.minX * scale,
                y: doorOpening.minY * scale,
                width: doorOpening.width * scale,
                height: doorOpening.height * scale
            )
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: opening).addClip()
            closed.draw(in: rect.offsetBy(dx: 0, dy: opening.height * (1 - progress)))
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
    }

    @objc private func showSettings() {
        openSettings()
    }
}
