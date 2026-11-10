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
    @AppStorage(DefaultsKey.escapeHoldSeconds) private var escapeHoldSeconds = defaultEscapeHoldSeconds

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
                    holdDurationRow(title: L10n.settingsUnlockHold(), message: L10n.settingsUnlockHoldMessage(), seconds: $unlockHoldSeconds)
                }
                Section {
                    holdDurationRow(title: L10n.settingsEscapeHold(), message: L10n.settingsEscapeHoldMessage(), seconds: $escapeHoldSeconds)
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

    private func holdDurationRow(title: String, message: String, seconds: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                HStack(spacing: 6) {
                    Text(L10n.settingsUnlockHoldSeconds(seconds.wrappedValue))
                        .monospacedDigit()
                    Stepper(title, value: seconds, in: 1...30)
                        .labelsHidden()
                        .fixedSize()
                        .accessibilityValue(L10n.settingsUnlockHoldSeconds(seconds.wrappedValue))
                }
                .fixedSize()
            }
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
