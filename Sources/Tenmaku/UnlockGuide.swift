import AppKit

@MainActor
enum UnlockGuide {
    typealias Decision = (startLock: Bool, hideNextTime: Bool)
    private static let suppressionKey = "hideUnlockGuide"

    static func confirmIfNeeded(
        seconds: Int,
        defaults: UserDefaults = .standard,
        present: @MainActor (Int) -> Decision = show
    ) -> Bool {
        if defaults.bool(forKey: suppressionKey) { return true }
        let decision = present(seconds)
        defaults.set(decision.hideNextTime, forKey: suppressionKey)
        return decision.startLock
    }

    private static func show(seconds: Int) -> Decision {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.unlockGuideTitle()
        alert.informativeText = L10n.unlockGuideMessage(seconds)
        alert.addButton(withTitle: L10n.protectionStart())
        alert.addButton(withTitle: L10n.commonCancel()).keyEquivalent = "\u{1b}"
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = L10n.unlockGuideHideNextTime()
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        return (response == .alertFirstButtonReturn, alert.suppressionButton?.state == .on)
    }
}
