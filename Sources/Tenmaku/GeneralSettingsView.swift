import SwiftUI
import TenmakuShared

enum ShieldMode: String, CaseIterable, Identifiable {
    case gammaAndCover
    case gammaOnly

    var id: Self { self }

    var title: String {
        switch self {
        case .gammaAndCover: L10n.shieldGammaAndCover()
        case .gammaOnly: L10n.shieldGammaOnly()
        }
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var protection: ProtectionController
    @AppStorage(DefaultsKey.shieldMode) private var shieldMode: ShieldMode = .gammaAndCover
    @AppStorage(DefaultsKey.unlockHoldSeconds) private var unlockHoldSeconds = defaultUnlockHoldSeconds

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(L10n.settingsDisplayShielding())
                            Spacer()
                            Picker(L10n.settingsDisplayShielding(), selection: $shieldMode) {
                                ForEach(ShieldMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        Text(shieldExplanation)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(L10n.settingsUnlockHold())
                            Spacer()
                            HStack(spacing: 6) {
                                Text(L10n.settingsUnlockHoldSeconds(unlockHoldSeconds))
                                    .monospacedDigit()
                                Stepper(L10n.settingsUnlockHold(), value: $unlockHoldSeconds, in: 1...30)
                                    .labelsHidden()
                                    .fixedSize()
                                    .accessibilityValue(L10n.settingsUnlockHoldSeconds(unlockHoldSeconds))
                            }
                            .fixedSize()
                        }
                        Text(L10n.settingsUnlockHoldMessage())
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(L10n.protectionStart(), action: protection.start)
                Button(L10n.protectionUnlock(), action: protection.requestUnlock)
                    .disabled(!protection.canRequestUnlock)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 30)
            .padding(.bottom, 20)
        }
        .frame(width: 520)
        .fixedSize()
    }

    private var shieldExplanation: String {
        switch shieldMode {
        case .gammaAndCover:
            L10n.settingsGammaAndCoverMessage()
        case .gammaOnly:
            L10n.settingsGammaOnlyMessage()
        }
    }
}
