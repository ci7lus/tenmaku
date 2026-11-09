import AppKit

@main
@MainActor
enum TenmakuApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenu: StatusMenu?
    private let protection = ProtectionController()
    private lazy var settings = SettingsWindowController(protection: protection)

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusMenu = StatusMenu(protection: protection, openSettings: { [settings] in settings.show() })
        protection.restoreIfEngaged()
        if !UserDefaults.standard.bool(forKey: DefaultsKey.walkthroughCompleted) {
            settings.show(tab: .walkthrough)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return false
    }
}

enum DefaultsKey {
    static let walkthroughCompleted = "walkthroughCompleted"
    static let shieldMode = "shieldMode"
    static let unlockHoldSeconds = "unlockHoldSeconds"
}
