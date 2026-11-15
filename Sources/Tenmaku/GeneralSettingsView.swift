import SwiftUI
import TenmakuShared

struct GeneralSettingsView: View {
    @ObservedObject var protection: ProtectionController
    @AppStorage(DefaultsKey.unlockKey) private var unlockKey = UnlockKey.any
    @AppStorage(DefaultsKey.customUnlockKeyEnabled) private var customUnlockKeyEnabled: Bool?
    @AppStorage(DefaultsKey.unlockHoldSeconds) private var unlockHoldSeconds = defaultUnlockHoldSeconds
    @AppStorage(DefaultsKey.escapeHoldSeconds) private var escapeHoldSeconds = defaultEscapeHoldSeconds

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Picker(L10n.settingsUnlockKey(), selection: customSelection) {
                            Text(L10n.settingsUnlockKeyAny()).tag(false)
                            Text(L10n.settingsUnlockKeyCustom()).tag(true)
                        }
                        .pickerStyle(.menu)
                        if preference.isCustom {
                            HStack {
                                Text(unlockKey == .any ? L10n.settingsUnlockKeyUnassigned() : unlockKey.title)
                                    .accessibilityLabel(L10n.settingsUnlockKey())
                                    .accessibilityValue(unlockKey == .any ? L10n.settingsUnlockKeyUnassigned() : unlockKey.title)
                                Spacer()
                                Button(L10n.settingsUnlockKeyCapture(), action: capture)
                                if unlockKey != .any {
                                    Button(L10n.settingsUnlockKeyClear()) {
                                        customUnlockKeyEnabled = true
                                        unlockKey = .any
                                    }
                                }
                            }
                        }
                        Text(L10n.settingsUnlockKeyMessage())
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

    private var preference: UnlockKeyPreference {
        UnlockKeyPreference(savedKey: unlockKey, customEnabled: customUnlockKeyEnabled)
    }

    private var customSelection: Binding<Bool> {
        Binding {
            preference.isCustom
        } set: { isCustom in
            customUnlockKeyEnabled = isCustom
            if isCustom, unlockKey == .any {
                DispatchQueue.main.async { capture() }
            }
        }
    }

    private func capture() {
        UnlockKeyCapture.begin { key in unlockKey = key }
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
}
