import ServiceManagement
import TenmakuShared

enum InputProtectionMode: String, CaseIterable {
    case eventTap
    case helper

    var title: String {
        switch self {
        case .eventTap: LegacyCopy.text("Without Helper", "ヘルパーなし")
        case .helper: LegacyCopy.text("With Helper", "ヘルパーあり")
        }
    }

    var service: LayerService {
        switch self {
        case .eventTap: .sessionInput
        case .helper: .input
        }
    }

    var appName: String {
        switch self {
        case .eventTap: "TenmakuInput"
        case .helper: "TenmakuHelper"
        }
    }

    var explanation: String {
        switch self {
        case .eventTap:
            LegacyCopy.text("Tenmaku runs without a privileged helper. It cannot block physical keys or detect key holds while Secure Event Input is active. It also blocks AI actions it cannot distinguish from physical input, including some Claude clicks.", "管理者権限のヘルパーは導入しません。Secure Event Input が有効な間は物理キーを止められず、長押しも検知できません。物理入力と区別できない AI の操作（Claude の一部クリックなど）も遮断します。")
        case .helper:
            LegacyCopy.text("A privileged helper captures the keyboard and mouse. It can block physical keys while Secure Event Input is active. Installation is optional and requires approval in Login Items in System Settings.", "管理者権限のヘルパーがキーボードとマウスを取得します。Secure Event Input 中の物理キーも止められます。導入は任意で、システム設定の「ログイン項目」で承認します。")
        }
    }

    var permissionTitle: String {
        self == .helper ? LegacyCopy.text("Allow Input Monitoring", "入力監視を許可する") : LegacyCopy.text("Allow Input Control", "入力の制御を許可する")
    }

    var permissionMessage: String {
        switch self {
        case .eventTap:
            LegacyCopy.text("Grant Input Monitoring and Accessibility to the unprivileged TenmakuInput app. If holding a key does not work, use Codex or another client to choose End Protection in the menu or General settings, then authenticate with Touch ID.", "一般ユーザーの入力制御アプリ TenmakuInput に、入力監視とアクセシビリティを許可します。長押しが使えない場合は、Codex などからメニューか「一般」の「保護を解除…」で認証を要求し、本人が Touch ID に触れます。")
        case .helper:
            LegacyCopy.text("The helper needs this permission to capture the keyboard and mouse. Grant it to TenmakuHelper.", "ヘルパーがキーボードとマウスを取得するために必要です。許可の対象は TenmakuHelper です。")
        }
    }

    static var selected: Self {
        let status = SMAppService.daemon(plistName: LayerService.input.plistName).status
        return status == .enabled ? .helper : .eventTap
    }
}
