import AppKit
import Carbon
import TenmakuShared

@MainActor
enum UnlockKeyCapture {
    static func begin(onCapture: @escaping @MainActor (UnlockKey) -> Void) {
        guard let parent = NSApp.keyWindow, parent.attachedSheet == nil else { return }

        let alert = NSAlert()
        alert.messageText = L10n.settingsUnlockKeyCaptureTitle()
        alert.informativeText = L10n.settingsUnlockKeyCaptureMessage()
        alert.addButton(withTitle: L10n.commonCancel()).keyEquivalent = "\u{1b}"
        var captured: UnlockKey?
        let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let windowNumber = event.windowNumber
            let keyCode = event.keyCode
            let isModifier = event.type == .flagsChanged
            let isRepeat = !isModifier && event.isARepeat
            let consumed = MainActor.assumeIsolated {
                guard windowNumber == alert.window.windowNumber else { return false }
                if Int(keyCode) == kVK_Escape { return false }
                if isRepeat || (isModifier && !CGEventSource.keyState(.combinedSessionState, key: keyCode)) {
                    return true
                }
                guard let key = UnlockKey(virtualKey: keyCode) else {
                    NSSound.beep()
                    return true
                }
                captured = key
                parent.endSheet(alert.window, returnCode: .alertFirstButtonReturn)
                return true
            }
            return consumed ? nil : event
        }
        alert.beginSheetModal(for: parent) { _ in
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let captured { onCapture(captured) }
        }
    }
}
