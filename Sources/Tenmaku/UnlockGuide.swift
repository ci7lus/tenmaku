import AppKit
import TenmakuShared

@MainActor
enum UnlockGuide {
    typealias Decision = (startLock: Bool, hideNextTime: Bool)
    private static let suppressionKey = "hideUnlockGuide"

    static func confirmIfNeeded(
        holdDurations: InputHoldDurations,
        inputMode: InputProtectionMode,
        unlockKey: UnlockKey = .any,
        defaults: UserDefaults = .standard,
        present: (@MainActor (InputHoldDurations) -> Decision)? = nil
    ) -> Bool {
        if defaults.bool(forKey: suppressionKey) { return true }
        let decision = present?(holdDurations) ?? show(holdDurations: holdDurations, inputMode: inputMode, unlockKey: unlockKey)
        defaults.set(decision.hideNextTime, forKey: suppressionKey)
        return decision.startLock
    }

    nonisolated static func escapeMessage(seconds: Int, inputMode: InputProtectionMode) -> String {
        let message = L10n.unlockEscapeMessage(seconds)
        return inputMode == .eventTap ? message + "\n" + L10n.unlockSecureEventInput() : message
    }

    nonisolated static func touchIDMessage(seconds: Int, unlockKey: UnlockKey) -> String {
        if unlockKey == .any { return L10n.unlockGuideMessage(seconds) }
        return L10n.unlockGuideSelectedKeyMessage(unlockKey.title, L10n.settingsUnlockHoldSeconds(seconds))
    }

    private static func show(holdDurations: InputHoldDurations, inputMode: InputProtectionMode, unlockKey: UnlockKey) -> Decision {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.unlockGuideTitle()
        alert.informativeText = touchIDMessage(seconds: Int(holdDurations.unlockSeconds), unlockKey: unlockKey)
            + "\n\n" + escapeMessage(seconds: Int(holdDurations.escapeSeconds), inputMode: inputMode)
        alert.addButton(withTitle: L10n.protectionStart())
        alert.addButton(withTitle: L10n.commonCancel()).keyEquivalent = "\u{1b}"
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = L10n.unlockGuideHideNextTime()
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        return (response == .alertFirstButtonReturn, alert.suppressionButton?.state == .on)
    }
}
