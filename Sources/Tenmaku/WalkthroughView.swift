import AppKit
import CoreGraphics
import ServiceManagement
import SwiftUI
import TenmakuShared

enum PermissionState: Equatable {
    case granted
    case missing
    case needsApproval
    case notRequired
    case unavailable(String)

    var label: String {
        switch self {
        case .granted: L10n.permissionGranted()
        case .missing: L10n.permissionMissing()
        case .needsApproval: L10n.permissionNeedsApproval()
        case .notRequired: L10n.permissionSkipped()
        case .unavailable(let reason): reason
        }
    }

    var symbol: String {
        switch self {
        case .granted: "checkmark.circle.fill"
        case .missing, .needsApproval: "exclamationmark.circle.fill"
        case .notRequired: "minus.circle"
        case .unavailable: "circle.dashed"
        }
    }

    var color: Color {
        switch self {
        case .granted: .green
        case .missing, .needsApproval: .orange
        case .notRequired, .unavailable: .secondary
        }
    }
}

enum WalkthroughStep: Int, CaseIterable {
    case welcome
    case helper
    case inputMonitoring
    case postEvent
    case summary

    static let permissionSteps: [WalkthroughStep] = [.helper, .inputMonitoring, .postEvent]

    var symbol: String {
        switch self {
        case .welcome: "" // Show the app icon.
        case .helper: "gearshape.2"
        case .inputMonitoring: "keyboard"
        case .postEvent: "lock"
        case .summary: "checklist"
        }
    }

    var title: String {
        switch self {
        case .welcome: L10n.walkthroughWelcomeTitle()
        case .helper: L10n.walkthroughHelperTitle()
        case .inputMonitoring: L10n.inputPermissionControl()
        case .postEvent: L10n.walkthroughLockTitle()
        case .summary: L10n.walkthroughSummaryTitle()
        }
    }

    var shortTitle: String {
        switch self {
        case .welcome, .summary: ""
        case .helper: L10n.settingsInputBlocking()
        case .inputMonitoring: L10n.walkthroughInputControl()
        case .postEvent: L10n.walkthroughScreenLock()
        }
    }

    func message(inputMode: InputProtectionMode) -> AttributedString {
        let text: String
        switch self {
        case .welcome:
            text = L10n.walkthroughWelcomeMessage()
        case .helper:
            text = L10n.walkthroughHelperMessage()
        case .inputMonitoring:
            text = inputMode.permissionMessage
        case .postEvent:
            text = L10n.walkthroughLockMessage()
        case .summary:
            return AttributedString(L10n.walkthroughStartMessage())
        }
        return (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

struct WalkthroughView: View {
    @ObservedObject var protection: ProtectionController
    @AppStorage(DefaultsKey.walkthroughCompleted) private var completed = false
    @ObservedObject var setup: WalkthroughModel
    private var step: WalkthroughStep { setup.step }
    private var inputMode: InputProtectionMode { setup.permissions.mode }
    private var permissions: WalkthroughPermissions { setup.permissions }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                header
                Text(step.title)
                    .font(.title2.weight(.semibold))
                Text(step.message(inputMode: inputMode))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if step == .summary {
                    summary
                } else if step == .helper, permissions[.helper] == .missing {
                    Label(L10n.permissionNotInstalled(), systemImage: "minus.circle")
                        .foregroundStyle(.secondary)
                } else if let permission = permissions[step] {
                    Label(permission.label, systemImage: permission.symbol)
                        .foregroundStyle(permission.color)
                }
                action
                if step == .helper, let failure = protection.helperChangeFailure {
                    Text(failure).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                pageIndicator
                Spacer()
                if step != .welcome {
                    Button(L10n.walkthroughBack()) { move(by: -1) }
                }
                if step == .summary {
                    Button(L10n.walkthroughDone(), action: finish)
                        .disabled(permissions.firstMissing != nil)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(L10n.walkthroughNext()) { move(by: 1) }
                        .disabled((step == .inputMonitoring || step == .postEvent) && permissions[step] != .granted)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 520, height: 440)
    }

    @ViewBuilder
    private var header: some View {
        if step == .welcome {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
        } else {
            Image(systemName: step.symbol)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Color("AccentColor"))
                .frame(height: 56)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(WalkthroughStep.permissionSteps, id: \.self) { item in
                if let permission = summaryPermission(for: item) {
                    HStack {
                        Text(item.shortTitle)
                        Spacer()
                        Label(
                            item == .helper && (permission == .granted || permission == .notRequired)
                                ? inputMode.title : permission.label,
                            systemImage: permission.symbol
                        )
                            .foregroundStyle(permission.color)
                    }
                }
            }
        }
        .frame(maxWidth: 360)
    }

    private func summaryPermission(for item: WalkthroughStep) -> PermissionState? {
        if item == .helper, permissions[.helper] == .missing { return .notRequired }
        return permissions[item]
    }

    @ViewBuilder
    private var action: some View {
        switch step {
        case .helper where permissions[.helper] == .needsApproval:
            Button(L10n.walkthroughOpenLoginItems()) { SMAppService.openSystemSettingsLoginItems() }
        case .helper where permissions[.helper] == .missing:
            Button(L10n.walkthroughInstall()) {
                Task {
                    await protection.setHelperEnabled(true)
                }
            }
            .disabled(!protection.canQuit)
        case .inputMonitoring:
            Button(L10n.walkthroughRequestPermission(), action: requestInputMonitoring)
                .disabled(permissions[.inputMonitoring] == .granted)
        case .postEvent:
            Button(L10n.walkthroughRequestPermission()) {
                requestPostEventAccess()
            }
            .disabled(permissions[.postEvent] == .granted)
        default:
            EmptyView()
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(WalkthroughStep.allCases, id: \.self) { item in
                Circle()
                    .fill(item == step ? Color("AccentColor") : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
    }

    private func move(by offset: Int) {
        if let next = WalkthroughStep(rawValue: step.rawValue + offset) {
            setup.step = next
        }
    }

    private func finish() {
        guard permissions.firstMissing == nil else { return }
        completed = true
        NSApp.keyWindow?.close()
    }

    // The daemon cannot request permission. Launch the helper app as the user.
    private func requestInputMonitoring() {
        let agent = SMAppService.agent(plistName: LayerService.sessionInput.plistName)
        if agent.status != .enabled { try? agent.register() }
        if agent.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        for mode in inputMode.requiredInputs {
            let app = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/Helpers/\(mode.appName).app")
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.activates = false
            configuration.arguments = [mode == .helper ? requestInputMonitoringArgument : requestSessionInputAccessArgument]
            NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        }
    }
}
