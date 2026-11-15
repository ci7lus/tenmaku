import Carbon
import Foundation
import TenmakuShared

extension UnlockKey {
    var title: String {
        switch self {
        case .any: return L10n.settingsUnlockKeyAny()
        case .space: return L10n.settingsUnlockKeySpace()
        case .returnKey: return L10n.settingsUnlockKeyReturn()
        case .tab: return "Tab"
        case .delete: return L10n.settingsUnlockKeyDelete()
        case .left: return L10n.settingsUnlockKeyLeft()
        case .right: return L10n.settingsUnlockKeyRight()
        case .down: return L10n.settingsUnlockKeyDown()
        case .up: return L10n.settingsUnlockKeyUp()
        case .home: return "Home"
        case .end: return "End"
        case .pageUp: return "Page Up"
        case .pageDown: return "Page Down"
        case .forwardDelete: return "⌦"
        case .leftControl: return L10n.settingsUnlockKeyLeftModifier("⌃")
        case .leftShift: return L10n.settingsUnlockKeyLeftModifier("⇧")
        case .leftOption: return L10n.settingsUnlockKeyLeftModifier("⌥")
        case .leftCommand: return L10n.settingsUnlockKeyLeftModifier("⌘")
        case .rightControl: return L10n.settingsUnlockKeyRightModifier("⌃")
        case .rightShift: return L10n.settingsUnlockKeyRightModifier("⇧")
        case .rightOption: return L10n.settingsUnlockKeyRightModifier("⌥")
        case .rightCommand: return L10n.settingsUnlockKeyRightModifier("⌘")
        case .keypadClear: return L10n.settingsUnlockKeyKeypad("Clear")
        case .keypadEnter: return L10n.settingsUnlockKeyKeypad("Enter")
        case .keypadComma: return L10n.settingsUnlockKeyKeypad(",")
        case .jisRo: return characterInCurrentLayout ?? "_"
        case .jisYen: return characterInCurrentLayout ?? "¥"
        default: break
        }
        if (Self.f1.rawValue...Self.f12.rawValue).contains(rawValue) {
            return "F\(rawValue - Self.f1.rawValue + 1)"
        }
        if (Self.f13.rawValue...Self.f20.rawValue).contains(rawValue) {
            return "F\(rawValue - Self.f13.rawValue + 13)"
        }
        let label = characterInCurrentLayout ?? ansiLabel ?? L10n.settingsUnlockKeyCode(Int(virtualKeyCode ?? 0))
        if (Self.keypadClear.rawValue...Self.keypadDecimal.rawValue).contains(rawValue) || self == .keypadEqual {
            return L10n.settingsUnlockKeyKeypad(label)
        }
        return label
    }

    private var characterInCurrentLayout: String? {
        guard let keyCode = virtualKeyCode,
              let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 8)
        var length = 0
        let result = withExtendedLifetime((source, data)) {
            UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState,
                           characters.count, &length, &characters)
        }
        guard result == noErr, length > 0 else { return nil }
        let text = String(decoding: characters.prefix(length), as: UTF16.self)
        guard text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return text.uppercased()
    }
}
