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

    var indicator: ProtectionIndicator = .unlocked {
        didSet { applyIndicator() }
    }

    init(openSettings: @escaping () -> Void) {
        self.openSettings = openSettings
        super.init()

        applyIndicator()

        let menu = NSMenu()
        menu.autoenablesItems = false

        let state = NSMenuItem(title: LegacyCopy.text("Protection Off", "未保護"), action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)
        menu.addItem(.separator())

        // Stage 2 implements activation through the gamma and cover processes.
        let start = NSMenuItem(title: LegacyCopy.text("Start Protection", "保護を開始"), action: nil, keyEquivalent: "")
        start.isEnabled = false
        menu.addItem(start)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: LegacyCopy.text("Settings…", "設定…"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: LegacyCopy.text("Quit Tenmaku", "Tenmaku を終了"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
    }

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
