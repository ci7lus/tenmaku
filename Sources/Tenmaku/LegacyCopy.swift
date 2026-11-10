import Foundation

enum LegacyCopy {
    private static let usesJapanese = Bundle.preferredLocalizations(from: ["en", "ja"]).first == "ja"

    static func text(_ english: String, _ japanese: String) -> String {
        usesJapanese ? japanese : english
    }

    static func error(_ message: String) -> String {
        guard usesJapanese else { return message }
        return switch message {
        case "Allow Accessibility for TenmakuInput.":
            "TenmakuInput のアクセシビリティを許可してください"
        case "Allow Input Monitoring for TenmakuInput.":
            "TenmakuInput の入力監視を許可してください"
        case "Check the Input Monitoring and Accessibility permissions for TenmakuInput.":
            "TenmakuInput の入力監視とアクセシビリティの許可を確認してください"
        case "Could not confirm that the keys and buttons were released.":
            "キーとボタンの解放を確認できませんでした"
        case "Could not cover all displays.":
            "覆いを全画面に出せませんでした"
        case "Could not monitor input control.":
            "入力の制御を監視できませんでした"
        case "Could not seize the input devices.":
            "入力機器を取得できませんでした"
        case "Could not set gamma to zero on all displays.":
            "ガンマを全ゼロにできませんでした"
        case "Could not start input control.":
            "入力の制御を開始できませんでした"
        case "Input control has stopped.":
            "入力の制御が停止しています"
        case "No input devices were found.":
            "入力機器が見つかりません"
        case "Release the keys and mouse buttons you are holding.":
            "押しているキーとマウスボタンを離してください"
        case "Set the hold duration to between 1 and 30 seconds.":
            "長押しは1〜30秒で設定してください"
        default:
            formattedError(message)
        }
    }

    private static func formattedError(_ message: String) -> String {
        let prefix = "Check the Input Monitoring permission ("
        let suffix = ")."
        guard message.hasPrefix(prefix), message.hasSuffix(suffix) else { return message }
        let status = message.dropFirst(prefix.count).dropLast(suffix.count)
        return "入力監視の許可を確認してください（\(status)）"
    }
}
