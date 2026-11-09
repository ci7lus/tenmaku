import SwiftUI
import TenmakuShared

enum ShieldMode: String, CaseIterable, Identifiable {
    case gammaAndCover
    case gammaOnly

    var id: Self { self }

    var title: String {
        switch self {
        case .gammaAndCover: LegacyCopy.text("Gamma and Cover", "ガンマと覆い")
        case .gammaOnly: LegacyCopy.text("Gamma Only", "ガンマだけ")
        }
    }
}

struct GeneralSettingsView: View {
    let start: () -> Void
    @AppStorage(DefaultsKey.shieldMode) private var shieldMode: ShieldMode = .gammaAndCover
    @AppStorage(DefaultsKey.unlockHoldSeconds) private var unlockHoldSeconds = defaultUnlockHoldSeconds

    var body: some View {
        Form {
            Section {
                Picker(LegacyCopy.text("Screen Shielding", "画面の遮蔽"), selection: $shieldMode) {
                    ForEach(ShieldMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } footer: {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Stepper(LegacyCopy.text("Hold Duration for the Unlock Key: \(unlockHoldSeconds) seconds", "解除するキーの長押し: \(unlockHoldSeconds) 秒"), value: $unlockHoldSeconds, in: 1...30)
            } footer: {
                Text(LegacyCopy.text("While protection is on, hold a key other than Esc for this duration. Touch Touch ID when you hear the sound. This change applies the next time you start protection.", "保護中に Esc 以外のキーをこの秒数押し続けると音が鳴ります。音が鳴ったら Touch ID に触れて解除します。次に保護を開始したときから反映します。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button(LegacyCopy.text("Start Protection", "保護を開始"), action: start)
            } footer: {
                // A display notch can hide the menu bar icon.
                Text(LegacyCopy.text("You can start protection here if the menu bar icon is hidden.", "メニューバーにアイコンが見えないときは、ここから開始できます。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize()
    }

    private var footer: String {
        switch shieldMode {
        case .gammaAndCover:
            LegacyCopy.text("Gamma and a black cover that stays out of captures shield the displays together. If one layer drops, the other stays in place.", "ガンマと、撮影に写らない黒い覆いを重ねて画面を守ります。どちらか一方が外れても、もう一方が残ります。")
        case .gammaOnly:
            LegacyCopy.text("Gamma alone shields the displays. Gamma can reset and reveal the desktop if a process that set gamma exits or if the display configuration changes.", "ガンマだけで画面を守ります。ガンマを設定したプロセス（このアプリ以外も含む）の終了や画面の再構成で、ガンマが元に戻り、内容が見えることがあります。")
        }
    }
}
