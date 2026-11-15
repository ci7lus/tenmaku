import Carbon
import CoreGraphics
import IOKit.hid

/// Store the HID key usage in settings and match the corresponding physical position by virtual key code in the event tap.
public enum UnlockKey: Int, CaseIterable, Sendable {
    case any = 0
    case space = 0x2C
    case returnKey = 0x28
    case tab = 0x2B
    case delete = 0x2A
    case left = 0x50
    case right = 0x4F
    case down = 0x51
    case up = 0x52
    case a = 0x04, b, c, d, e, f, g, h, i, j, k, l, m
    case n, o, p, q, r, s, t, u, v, w, x, y, z
    case one, two, three, four, five, six, seven, eight, nine, zero
    case hyphen = 0x2D, equal, openBracket, closeBracket, backslash
    case semicolon = 0x33, quote, grave, comma, period, slash
    case f1 = 0x3A, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    case home = 0x4A, pageUp, forwardDelete, end, pageDown
    case keypadClear = 0x53, keypadDivide, keypadMultiply, keypadMinus, keypadPlus, keypadEnter
    case keypad1, keypad2, keypad3, keypad4, keypad5, keypad6, keypad7, keypad8, keypad9, keypad0, keypadDecimal
    case keypadEqual = 0x67
    case f13 = 0x68, f14, f15, f16, f17, f18, f19, f20
    case keypadComma = 0x85
    case jisRo = 0x87
    case jisYen = 0x89
    case leftControl = 0xE0, leftShift, leftOption, leftCommand, rightControl, rightShift, rightOption, rightCommand

    public init?(virtualKey: CGKeyCode) {
        guard let key = Self.keysByVirtualCode[virtualKey] else { return nil }
        self = key
    }

    public var virtualKeyCode: CGKeyCode? {
        Self.virtualKeys[self].map { CGKeyCode($0) }
    }

    public var ansiLabel: String? {
        switch rawValue {
        case Self.a.rawValue...Self.z.rawValue:
            return UnicodeScalar(65 + rawValue - Self.a.rawValue).map(String.init)
        case Self.one.rawValue...Self.nine.rawValue:
            return String(rawValue - Self.one.rawValue + 1)
        case Self.zero.rawValue:
            return "0"
        default:
            return nil
        }
    }

    public func matches(hidUsage: UInt32) -> Bool {
        hidUsage != kHIDUsage_KeyboardEscape && (self == .any || hidUsage == UInt32(rawValue))
    }

    public func matches(virtualKey: CGKeyCode) -> Bool {
        Int(virtualKey) != kVK_Escape && (self == .any || virtualKey == virtualKeyCode)
    }

    private static let virtualKeys: [Self: Int] = [
        .space: kVK_Space, .returnKey: kVK_Return, .tab: kVK_Tab, .delete: kVK_Delete,
        .left: kVK_LeftArrow, .right: kVK_RightArrow, .down: kVK_DownArrow, .up: kVK_UpArrow,
        .a: kVK_ANSI_A, .b: kVK_ANSI_B, .c: kVK_ANSI_C, .d: kVK_ANSI_D, .e: kVK_ANSI_E,
        .f: kVK_ANSI_F, .g: kVK_ANSI_G, .h: kVK_ANSI_H, .i: kVK_ANSI_I, .j: kVK_ANSI_J,
        .k: kVK_ANSI_K, .l: kVK_ANSI_L, .m: kVK_ANSI_M, .n: kVK_ANSI_N, .o: kVK_ANSI_O,
        .p: kVK_ANSI_P, .q: kVK_ANSI_Q, .r: kVK_ANSI_R, .s: kVK_ANSI_S, .t: kVK_ANSI_T,
        .u: kVK_ANSI_U, .v: kVK_ANSI_V, .w: kVK_ANSI_W, .x: kVK_ANSI_X, .y: kVK_ANSI_Y,
        .z: kVK_ANSI_Z, .one: kVK_ANSI_1, .two: kVK_ANSI_2, .three: kVK_ANSI_3, .four: kVK_ANSI_4,
        .five: kVK_ANSI_5, .six: kVK_ANSI_6, .seven: kVK_ANSI_7, .eight: kVK_ANSI_8,
        .nine: kVK_ANSI_9, .zero: kVK_ANSI_0,
        .hyphen: kVK_ANSI_Minus, .equal: kVK_ANSI_Equal, .openBracket: kVK_ANSI_LeftBracket,
        .closeBracket: kVK_ANSI_RightBracket, .backslash: kVK_ANSI_Backslash,
        .semicolon: kVK_ANSI_Semicolon, .quote: kVK_ANSI_Quote, .grave: kVK_ANSI_Grave,
        .comma: kVK_ANSI_Comma, .period: kVK_ANSI_Period, .slash: kVK_ANSI_Slash,
        .f1: kVK_F1, .f2: kVK_F2, .f3: kVK_F3, .f4: kVK_F4, .f5: kVK_F5, .f6: kVK_F6,
        .f7: kVK_F7, .f8: kVK_F8, .f9: kVK_F9, .f10: kVK_F10, .f11: kVK_F11, .f12: kVK_F12,
        .f13: kVK_F13, .f14: kVK_F14, .f15: kVK_F15, .f16: kVK_F16,
        .f17: kVK_F17, .f18: kVK_F18, .f19: kVK_F19, .f20: kVK_F20,
        .home: kVK_Home, .pageUp: kVK_PageUp, .forwardDelete: kVK_ForwardDelete,
        .end: kVK_End, .pageDown: kVK_PageDown,
        .keypadClear: kVK_ANSI_KeypadClear, .keypadDivide: kVK_ANSI_KeypadDivide,
        .keypadMultiply: kVK_ANSI_KeypadMultiply, .keypadMinus: kVK_ANSI_KeypadMinus,
        .keypadPlus: kVK_ANSI_KeypadPlus, .keypadEnter: kVK_ANSI_KeypadEnter,
        .keypad1: kVK_ANSI_Keypad1, .keypad2: kVK_ANSI_Keypad2, .keypad3: kVK_ANSI_Keypad3,
        .keypad4: kVK_ANSI_Keypad4, .keypad5: kVK_ANSI_Keypad5, .keypad6: kVK_ANSI_Keypad6,
        .keypad7: kVK_ANSI_Keypad7, .keypad8: kVK_ANSI_Keypad8, .keypad9: kVK_ANSI_Keypad9,
        .keypad0: kVK_ANSI_Keypad0, .keypadDecimal: kVK_ANSI_KeypadDecimal,
        .keypadEqual: kVK_ANSI_KeypadEquals,
        .keypadComma: kVK_JIS_KeypadComma, .jisRo: kVK_JIS_Underscore, .jisYen: kVK_JIS_Yen,
        .leftControl: kVK_Control, .leftShift: kVK_Shift, .leftOption: kVK_Option, .leftCommand: kVK_Command,
        .rightControl: kVK_RightControl, .rightShift: kVK_RightShift,
        .rightOption: kVK_RightOption, .rightCommand: kVK_RightCommand,
    ]

    private static let keysByVirtualCode = Dictionary(uniqueKeysWithValues:
        virtualKeys.map { (CGKeyCode($0.value), $0.key) }
    )
}
