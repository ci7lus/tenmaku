import ServiceManagement
import TenmakuShared

enum HelperRegistration {
    static var service: SMAppService { .daemon(plistName: LayerService.input.plistName) }

    static func requested(_ status: SMAppService.Status) -> Bool {
        status == .enabled || status == .requiresApproval
    }
}

enum InputProtectionMode: String, CaseIterable, Codable {
    case eventTap
    case helper

    /// Both services must be healthy when the helper owns the keyboard.
    var requiredInputs: [Self] { self == .helper ? [.helper, .eventTap] : [.eventTap] }

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

    var permissionMessage: String {
        switch self {
        case .eventTap:
            L10n.inputPermissionEventTapMessage()
        case .helper:
            L10n.inputPermissionHelperMessage()
        }
    }

    init(helperStatus: SMAppService.Status) {
        self = helperStatus == .enabled ? .helper : .eventTap
    }

    static var selected: Self {
        Self(helperStatus: HelperRegistration.service.status)
    }
}
