import SwiftUI

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
    @AppStorage(DefaultsKey.shieldMode) private var shieldMode: ShieldMode = .gammaAndCover

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
