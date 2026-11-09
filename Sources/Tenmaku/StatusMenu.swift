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

@MainActor
final class StatusMenu: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let openSettings: () -> Void
    private let protection: ProtectionController
    private let stateItem = NSMenuItem(title: LegacyCopy.text("Protection Off", "未保護"), action: nil, keyEquivalent: "")
    private let startItem = NSMenuItem(title: LegacyCopy.text("Start Protection", "保護を開始"), action: nil, keyEquivalent: "")
    #if TENMAKU_TEST_BUILD
    private let stopItem = NSMenuItem(title: LegacyCopy.text("Stop Shielding (Test)", "遮蔽を終了（試験用）"), action: nil, keyEquivalent: "")
    #endif

    var indicator: ProtectionIndicator = .unlocked {
        didSet { applyIndicator() }
    }

    init(protection: ProtectionController, openSettings: @escaping () -> Void) {
        self.protection = protection
        self.openSettings = openSettings
        super.init()

        applyIndicator()

        let menu = NSMenu()
        menu.autoenablesItems = false

        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())

        startItem.target = self
        startItem.action = #selector(startProtection)
        menu.addItem(startItem)
        #if TENMAKU_TEST_BUILD
        startItem.title = LegacyCopy.text("Start Shielding (Test)", "遮蔽を開始（試験用）")
        stopItem.target = self
        stopItem.action = #selector(stopProtection)
        stopItem.isEnabled = false
        menu.addItem(stopItem)
        observeTestCommands()
        #endif
        menu.addItem(.separator())

        let settings = NSMenuItem(title: LegacyCopy.text("Settings…", "設定…"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: LegacyCopy.text("Quit Tenmaku", "Tenmaku を終了"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
        protection.onChange = { [weak self] state in self?.apply(state) }
    }

    private func apply(_ state: ProtectionState) {
        switch state {
        case .idle: stateItem.title = LegacyCopy.text("Protection Off", "未保護")
        case .starting: stateItem.title = LegacyCopy.text("Starting…", "開始しています…")
        case .shielded:
            stateItem.title = protection.unlockFailure.map { LegacyCopy.text("Could not unlock: \($0)", "解除できませんでした: \($0)") } ?? LegacyCopy.text("Protection On", "保護中")
        case .interrupted: stateItem.title = LegacyCopy.text("Paused (macOS Session Locked)", "中断中（セッションがロックされています）")
        case .handingOff(let reason): stateItem.title = LegacyCopy.text("Switching to the Lock Screen: \(reason)", "ロックへ引き渡し中: \(reason)")
        case .failed(let reason): stateItem.title = LegacyCopy.text("Failed: \(reason)", "失敗: \(reason)")
        }
        indicator = state == .idle ? .unlocked : .locked
        startItem.isEnabled = state == .idle
        if case .failed = state { startItem.isEnabled = true }
        #if TENMAKU_TEST_BUILD
        writeTestState()
        stopItem.isEnabled = state != .idle && state != .starting
        #endif
    }

    @objc private func startProtection() {
        protection.start()
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
        let image = NSImage(named: indicator.imageName)
        image?.isTemplate = true
        image?.accessibilityDescription = "Tenmaku"
        item.button?.image = image
    }

    @objc private func showSettings() {
        openSettings()
    }
}
