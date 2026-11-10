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
        case .granted: LegacyCopy.text("Allowed", "許可済み")
        case .missing: LegacyCopy.text("Permission Required", "未許可")
        case .needsApproval: LegacyCopy.text("Awaiting Approval", "承認待ち")
        case .notRequired: LegacyCopy.text("Skipped", "スキップ")
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
        case .welcome: LegacyCopy.text("Welcome to Tenmaku", "Tenmaku へようこそ")
        case .helper: LegacyCopy.text("Install Helper (Optional)", "ヘルパーのインストール（任意）")
        case .inputMonitoring: LegacyCopy.text("Allow Input Monitoring", "入力監視を許可する")
        case .postEvent: LegacyCopy.text("Allow Screen Lock", "画面ロックの操作を許可する")
        case .summary: LegacyCopy.text("Setup Status", "準備の状況")
        }
    }

    var shortTitle: String {
        switch self {
        case .welcome, .summary: ""
        case .helper: LegacyCopy.text("Input Blocking", "入力の遮断")
        case .inputMonitoring: LegacyCopy.text("Input Control", "入力の制御")
        case .postEvent: LegacyCopy.text("Screen Lock", "画面ロックの操作")
        }
    }

    func message(inputMode: InputProtectionMode) -> String {
        switch self {
        case .welcome:
            LegacyCopy.text("When you step away from your Mac, Tenmaku hides the screen and blocks the local keyboard and mouse. Codex or Claude can still capture and control the same desktop. End protection with Touch ID when you return.", "Mac から離れている間、画面を隠し、その場のキーボードとマウスからの入力を止めます。Codex や Claude はその間も同じデスクトップを撮影・操作できます。戻ったら Touch ID で保護を解除します。")
        case .helper:
            LegacyCopy.text("The helper can block physical keys while Secure Event Input is active. Click Next to skip installation. Without the helper, Tenmaku cannot detect physical keys or key holds during Secure Event Input. It also blocks AI actions that it cannot distinguish from physical input. You can install the helper here later.", "ヘルパーをインストールすると、Secure Event Input 中の物理キーも止められます。インストールせずに「次へ」でスキップできます。ヘルパーなしでは Secure Event Input 中の物理キーや長押しを検知できません。また、物理入力と区別できない AI の操作も遮断します。あとからここでインストールできます。")
        case .inputMonitoring:
            inputMode.permissionMessage
        case .postEvent:
            LegacyCopy.text("This lets Tenmaku lock your Mac if it can no longer maintain protection.", "保護を続けられなくなったときに、Mac の画面をロックするために使います。")
        case .summary:
            LegacyCopy.text("Click Back to grant missing permissions. Start protection from the menu bar icon or General settings. To unlock, hold a key other than Esc (5 seconds by default) and touch Touch ID when you hear the sound. If Touch ID cannot unlock, hold Esc for 10 seconds to switch to the lock screen.", "足りない項目は「戻る」で設定できます。メニューバーのアイコンか設定の「一般」から保護を開始します。解除するときは、Esc 以外のキーを長押し（既定は 5 秒）して、音が鳴ったら Touch ID に触れます。Touch ID で解除できないときは、Esc を 10 秒長押しするとロック画面へ移ります。")
        }
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
            @unknown default: .unavailable(LegacyCopy.text("Could not determine the status.", "状態を確認できません"))
            }
        case .inputMonitoring:
            // Input Monitoring is granted to the helper app, so check after installation.
            .unavailable(LegacyCopy.text("This is checked after you install the helper.", "ヘルパーをインストールしてから確認します"))
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
                    Label(LegacyCopy.text("Not Installed", "未インストール"), systemImage: "minus.circle")
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
                    Button(LegacyCopy.text("Back", "戻る")) { move(by: -1) }
                }
                if step == .summary {
                    Button(LegacyCopy.text("Done", "完了"), action: finish)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(LegacyCopy.text("Next", "次へ")) { move(by: 1) }
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
            Button(LegacyCopy.text("Open Login Items", "ログイン項目を開く")) { SMAppService.openSystemSettingsLoginItems() }
        case .helper where permissions[.helper] == .missing:
            Button(LegacyCopy.text("Install", "インストール"), action: installHelper)
        case .inputMonitoring:
            Button(LegacyCopy.text("Request Permission", "許可を求める"), action: requestInputMonitoring)
                .disabled(permissions[.inputMonitoring] != .missing)
        case .postEvent:
            Button(LegacyCopy.text("Request Permission", "許可を求める")) {
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
