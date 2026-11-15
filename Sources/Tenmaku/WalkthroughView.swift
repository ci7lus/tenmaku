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
        case .inputMonitoring: L10n.inputPermissionMonitoring()
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

    @MainActor
    var permission: PermissionState? {
        switch self {
        case .welcome, .summary:
            nil
        case .helper:
            switch SMAppService.daemon(plistName: LayerService.input.plistName).status {
            case .enabled: .granted
            case .requiresApproval: .needsApproval
            // Services that have never been registered can also return .notFound.
            case .notRegistered, .notFound: .missing
            @unknown default: .unavailable(L10n.permissionUnknown())
            }
        case .inputMonitoring:
            // Input Monitoring is granted to the helper app, so check after installation.
            .unavailable(L10n.permissionHelperRequired())
        case .postEvent:
            CGPreflightPostEventAccess() ? .granted : .missing
        }
    }
}

struct WalkthroughView: View {
    @AppStorage(DefaultsKey.walkthroughCompleted) private var completed = false
    @State private var inputMode: InputProtectionMode = .selected
    @State private var step: WalkthroughStep = .welcome
    @State private var permissions: [WalkthroughStep: PermissionState] = [:]
    @State private var refreshGeneration = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                header
                Text(step == .inputMonitoring ? inputMode.permissionTitle : step.title)
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
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(L10n.walkthroughNext()) { move(by: 1) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 520, height: 440)
        .onAppear {
            if completed { step = .summary }
            refresh()
        }
        .onChange(of: step) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
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
            Button(L10n.walkthroughInstall(), action: installHelper)
        case .inputMonitoring:
            Button(L10n.walkthroughRequestPermission(), action: requestInputMonitoring)
                .disabled(permissions[.inputMonitoring] != .missing)
        case .postEvent:
            Button(L10n.walkthroughRequestPermission()) {
                requestPostEventAccess()
                refresh()
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
            step = next
        }
    }

    private func finish() {
        completed = true
        NSApp.keyWindow?.close()
    }

    private func installHelper() {
        let helper = SMAppService.daemon(plistName: LayerService.input.plistName)
        try? helper.register()
        if helper.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        refresh()
    }

    // The daemon cannot request permission. Launch the helper app as the user.
    private func requestInputMonitoring() {
        if inputMode == .eventTap {
            let agent = SMAppService.agent(plistName: LayerService.sessionInput.plistName)
            try? agent.register()
            if agent.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        }
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/Helpers/\(inputMode.appName).app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = [inputMode == .helper ? requestInputMonitoringArgument : requestSessionInputAccessArgument]
        NSWorkspace.shared.openApplication(at: helper, configuration: configuration)
    }

    private func refresh() {
        refreshGeneration += 1
        let generation = refreshGeneration
        let mode = InputProtectionMode.selected
        inputMode = mode
        for item in WalkthroughStep.permissionSteps {
            permissions[item] = item.permission
        }
        let registered = mode == .helper
            ? permissions[.helper] == .granted
            : SMAppService.agent(plistName: mode.service.plistName).status == .enabled
        if mode == .eventTap { permissions[.inputMonitoring] = .missing }
        guard registered else { return }
        Task {
            let failure = await LayerClient(service: mode.service).preflight()
            guard generation == refreshGeneration, mode == inputMode else { return }
            permissions[.inputMonitoring] = failure == nil ? .granted : .missing
        }
    }
}
