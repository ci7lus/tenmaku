import AppKit
import CoreGraphics
import ServiceManagement
import SwiftUI

enum PermissionState: Equatable {
    case granted
    case missing
    case needsApproval
    case unavailable(String)

    var label: String {
        switch self {
        case .granted: LegacyCopy.text("Allowed", "許可済み")
        case .missing: LegacyCopy.text("Permission Required", "未許可")
        case .needsApproval: LegacyCopy.text("Awaiting Approval", "承認待ち")
        case .unavailable(let reason): reason
        }
    }

    var symbol: String {
        switch self {
        case .granted: "checkmark.circle.fill"
        case .missing, .needsApproval: "exclamationmark.circle.fill"
        case .unavailable: "circle.dashed"
        }
    }

    var color: Color {
        switch self {
        case .granted: .green
        case .missing, .needsApproval: .orange
        case .unavailable: .secondary
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
        case .helper: LegacyCopy.text("Install the Helper", "ヘルパーを導入する")
        case .inputMonitoring: LegacyCopy.text("Allow Input Monitoring", "入力監視を許可する")
        case .postEvent: LegacyCopy.text("Allow Screen Lock", "画面ロックの操作を許可する")
        case .summary: LegacyCopy.text("Setup Status", "準備の状況")
        }
    }

    var shortTitle: String {
        switch self {
        case .welcome, .summary: ""
        case .helper: LegacyCopy.text("Helper", "ヘルパー")
        case .inputMonitoring: LegacyCopy.text("Input Monitoring", "入力監視")
        case .postEvent: LegacyCopy.text("Screen Lock", "画面ロックの操作")
        }
    }

    var message: String {
        switch self {
        case .welcome:
            LegacyCopy.text("When you step away from your Mac, Tenmaku hides the screen and blocks the local keyboard and mouse. Codex or Claude can still capture and control the same desktop. Use Touch ID to end protection when you return.", "Mac から離れている間、画面を隠して、その場のキーボードとマウスを止めます。Codex や Claude は、その間も同じデスクトップを撮影・操作できます。戻ったら Touch ID で解除します。")
        case .helper:
            LegacyCopy.text("A privileged helper runs in the background to block the keyboard and mouse. Approve it in Login Items in System Settings during installation.", "キーボードとマウスを止めるために、管理者権限のヘルパーをバックグラウンドで動かします。導入するときは、システム設定の「ログイン項目」で承認します。")
        case .inputMonitoring:
            LegacyCopy.text("The helper needs this permission to capture the keyboard and mouse.", "ヘルパーがキーボードとマウスを取得するために必要です。")
        case .postEvent:
            LegacyCopy.text("This lets Tenmaku lock your Mac if it can no longer maintain protection.", "保護を続けられなくなったときに、Mac の画面をロックするために使います。")
        case .summary:
            LegacyCopy.text("Go back to grant missing permissions. A future version will let you start protection.", "足りない項目は、戻って設定できます。保護の開始は、今後の版で使えるようになります。")
        }
    }

    @MainActor
    var permission: PermissionState? {
        switch self {
        case .welcome, .summary:
            nil
        case .helper:
            switch SMAppService.daemon(plistName: "jp.pronama.tenmaku.helper.plist").status {
            case .enabled: .granted
            case .requiresApproval: .needsApproval
            // Services that have never been registered can also return .notFound.
            case .notRegistered, .notFound: .unavailable(LegacyCopy.text("Helper installation is under development.", "導入の機能は開発中です"))
            @unknown default: .unavailable(LegacyCopy.text("Could not determine the status.", "状態を確認できません"))
            }
        case .inputMonitoring:
            // Input Monitoring is granted to the helper app, so check after installation.
            .unavailable(LegacyCopy.text("This is checked after you install the helper.", "ヘルパーの導入後に確認します"))
        case .postEvent:
            CGPreflightPostEventAccess() ? .granted : .missing
        }
    }
}

struct WalkthroughView: View {
    @AppStorage(DefaultsKey.walkthroughCompleted) private var completed = false
    @State private var step: WalkthroughStep = .welcome
    @State private var permissions: [WalkthroughStep: PermissionState] = [:]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                header
                Text(step.title)
                    .font(.title2.weight(.semibold))
                Text(step.message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if step == .summary {
                    summary
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
        .frame(width: 520, height: 340)
        .onAppear(perform: refresh)
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
                if let permission = permissions[item] {
                    HStack {
                        Text(item.shortTitle)
                        Spacer()
                        Label(permission.label, systemImage: permission.symbol)
                            .foregroundStyle(permission.color)
                    }
                }
            }
        }
        .frame(maxWidth: 360)
    }

    @ViewBuilder
    private var action: some View {
        switch step {
        case .helper where permissions[.helper] == .needsApproval:
            Button(LegacyCopy.text("Open Login Items", "ログイン項目を開く")) { SMAppService.openSystemSettingsLoginItems() }
        case .postEvent:
            Button(LegacyCopy.text("Request Permission", "許可を求める")) {
                _ = CGRequestPostEventAccess()
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
        step = .welcome
        NSApp.keyWindow?.close()
    }

    private func refresh() {
        for item in WalkthroughStep.permissionSteps {
            permissions[item] = item.permission
        }
    }
}
