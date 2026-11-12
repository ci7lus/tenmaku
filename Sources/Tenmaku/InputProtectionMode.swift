import ServiceManagement
import TenmakuShared

enum InputProtectionMode: String, CaseIterable, Codable {
    case eventTap
    case helper

    var title: String {
        switch self {
        case .eventTap: L10n.inputWithoutHelper()
        case .helper: L10n.inputWithHelper()
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

    var permissionTitle: String {
        self == .helper ? L10n.inputPermissionMonitoring() : L10n.inputPermissionControl()
    }

    var permissionMessage: String {
        switch self {
        case .eventTap:
            L10n.inputPermissionEventTapMessage()
        case .helper:
            L10n.inputPermissionHelperMessage()
        }
    }

    static var selected: Self {
        let status = SMAppService.daemon(plistName: LayerService.input.plistName).status
        return status == .enabled ? .helper : .eventTap
    }
}
