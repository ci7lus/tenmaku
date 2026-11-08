import Foundation

enum LegacyCopy {
    private static let usesJapanese = Bundle.preferredLocalizations(from: ["en", "ja"]).first == "ja"

    static func text(_ english: String, _ japanese: String) -> String {
        usesJapanese ? japanese : english
    }

    static func error(_ message: String) -> String {
        guard usesJapanese else { return message }
        return switch message {
        case "Could not cover all displays.":
            "覆いを全画面に出せませんでした"
        case "Could not seize the input devices.":
            "入力機器を取得できませんでした"
        case "Could not set gamma to zero on all displays.":
            "ガンマを全ゼロにできませんでした"
        case "No input devices were found.":
            "入力機器が見つかりません"
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
