import AppKit
import SwiftUI

enum SettingsTab: Int, CaseIterable {
    case walkthrough
    case general

    var title: String {
        switch self {
        case .walkthrough: L10n.settingsWalkthrough()
        case .general: L10n.settingsGeneral()
        }
    }

    var symbol: String {
        switch self {
        case .walkthrough: "hand.wave"
        case .general: "gearshape"
        }
    }

    @MainActor
    func content(protection: ProtectionController) -> AnyView {
        switch self {
        case .walkthrough: AnyView(WalkthroughView())
        case .general: AnyView(GeneralSettingsView(protection: protection))
        }
    }
}

@MainActor
final class SettingsWindowController {
    private let protection: ProtectionController

    init(protection: ProtectionController) {
        self.protection = protection
    }

    private lazy var tabs: NSTabViewController = {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for tab in SettingsTab.allCases {
            let host = NSHostingController(rootView: tab.content(protection: protection))
            host.sizingOptions = .preferredContentSize
            host.title = tab.title
            let item = NSTabViewItem(viewController: host)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            tabs.addTabViewItem(item)
        }
        return tabs
    }()

    private lazy var window: NSWindow = {
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }()

    func show(tab: SettingsTab? = nil) {
        let selectedTab = tab ?? (UserDefaults.standard.bool(forKey: DefaultsKey.walkthroughCompleted) ? .general : .walkthrough)
        tabs.selectedTabViewItemIndex = selectedTab.rawValue
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
