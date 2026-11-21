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
    func content(protection: ProtectionController, setup: WalkthroughModel) -> AnyView {
        switch self {
        case .walkthrough: AnyView(WalkthroughView(protection: protection, setup: setup))
        case .general: AnyView(GeneralSettingsView(protection: protection))
        }
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let protection: ProtectionController

    init(protection: ProtectionController) {
        self.protection = protection
    }

    private var settingsWindow: NSWindow?
    private var setup: WalkthroughModel?
    private var observation: Task<Void, Never>?

    private func makeWindow(setup: WalkthroughModel) -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for tab in SettingsTab.allCases {
            let host = NSHostingController(rootView: tab.content(protection: protection, setup: setup))
            host.sizingOptions = .preferredContentSize
            host.title = tab.title
            let item = NSTabViewItem(viewController: host)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            tabs.addTabViewItem(item)
        }

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    func show(tab: SettingsTab? = nil, onlyIfNeeded: Bool = false) {
        observation?.cancel()
        observation = Task { [weak self] in
            let permissions = await WalkthroughPermissions.read()
            guard !Task.isCancelled, let self else { return }
            let completed = UserDefaults.standard.bool(forKey: DefaultsKey.walkthroughCompleted)
            let needsSetup = !completed || permissions.firstMissing != nil
            if onlyIfNeeded && !needsSetup { return }

            let model: WalkthroughModel
            if let setup {
                model = setup
                model.update(permissions)
                model.step = permissions.initialStep(completed: completed)
            } else {
                model = WalkthroughModel(permissions: permissions, completed: completed)
                setup = model
            }
            let window = settingsWindow ?? makeWindow(setup: model)
            settingsWindow = window
            let tabs = window.contentViewController as? NSTabViewController
            tabs?.selectedTabViewItemIndex = (tab ?? (needsSetup ? .walkthrough : .general)).rawValue
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)

            // System Settings can stay in front while the user makes several changes.
            // Serialize the probes so a slow XPC reply cannot overwrite a newer result.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard window.isVisible else { return }
                let next = await WalkthroughPermissions.read()
                guard !Task.isCancelled else { return }
                protection.refreshHelperStatus()
                model.update(next)
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        observation?.cancel()
        observation = nil
    }
}
