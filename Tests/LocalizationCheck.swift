import Foundation
import TenmakuShared

/// Launch as an app to test language selection in Bundle.main without changing displays or input.
@main
struct LocalizationCheck {
    static func main() {
        let english = CommandLine.arguments[1] != "ja"
        check(L10n.settingsGeneral(), english ? "General" : "一般")
        check(L10n.walkthroughHelperTitle(), english ? "Install Helper (Optional)" : "ヘルパーのインストール（任意）")
        check(L10n.settingsUnlockHold(), english ? "Hold Duration to Unlock" : "Touch ID解除開始キーのホールド時間")
        check(L10n.settingsUnlockHoldSeconds(1), english ? "1 second" : "1秒")
        check(L10n.settingsUnlockHoldSeconds(5), english ? "5 seconds" : "5秒")
        precondition(L10n.unlockGuideMessage(7).contains(english ? "7 seconds" : "7秒"))
        precondition(L10n.unlockGuideMessage(1).contains(english ? "1 second." : "1秒"))
        precondition(L10n.unlockEscapeMessage(3).contains(english ? "3 seconds" : "3秒"))
        precondition(L10n.unlockEscapeMessage(1).contains(english ? "1 second to" : "1秒"))
        check(L10n.settingsUnlockKey(), english ? "Touch ID Unlock Key" : "Touch ID解除開始キー")
        let selectedKeyMessage = L10n.unlockGuideSelectedKeyMessage("Tab", L10n.settingsUnlockHoldSeconds(7))
        precondition(selectedKeyMessage.contains("Tab"))
        precondition(selectedKeyMessage.contains(english ? "7 seconds" : "7秒間"))
        check(L10n.menuFailed("DETAIL"), english ? "Failed: DETAIL" : "失敗: DETAIL")
        check(localizedLayerError(LayerFailure.gammaFailed.error()),
              english ? "Could not adjust the colors on some displays." : "表示色を変更できなかった画面があります")
        check(localizedLayerError(LayerFailure.inputMonitoringDenied.error(status: -536870174)),
              english ? "Check the Input Monitoring permission (0xe00002e2)." : "入力監視の許可を確認してください（0xe00002e2）")
        check(localizedLayerError(NSError(domain: LayerFailure.domain, code: 999)),
              english ? "An unknown lock error occurred." : "ロックの処理で不明なエラーが発生しました")
        check(localizedLayerError(NSError(domain: "other", code: 1)),
              english ? "An unknown lock error occurred." : "ロックの処理で不明なエラーが発生しました")
        for failure in LayerFailure.allCases {
            let text = localizedLayerError(failure.error())
            precondition(!text.isEmpty && !text.contains(LayerFailure.domain), "Untranslated error: \(failure)")
            if english { precondition(text.range(of: "[ぁ-んァ-ヶ一-龯]", options: .regularExpression) == nil, text) }
        }
        print("\(CommandLine.arguments[1]): Language selection, plurals, and error messages passed")
    }

    static func check(_ actual: String, _ expected: String) {
        precondition(actual == expected, "Expected: \(expected) / Actual: \(actual)")
    }
}
