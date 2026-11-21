import ServiceManagement
import SwiftUI
import TenmakuShared

struct WalkthroughPermissions: Equatable {
    let mode: InputProtectionMode
    let helper: PermissionState
    let input: PermissionState
    let post: PermissionState

    subscript(step: WalkthroughStep) -> PermissionState? {
        switch step {
        case .helper: helper
        case .inputMonitoring: input
        case .postEvent: post
        case .welcome, .summary: nil
        }
    }

    var firstMissing: WalkthroughStep? {
        if input != .granted { return .inputMonitoring }
        if post != .granted { return .postEvent }
        return nil
    }

    func initialStep(completed: Bool) -> WalkthroughStep {
        completed ? firstMissing ?? .summary : .welcome
    }

    func updatedStep(_ step: WalkthroughStep, previous: Self) -> WalkthroughStep {
        if let firstMissing, step.rawValue > firstMissing.rawValue { return firstMissing }
        if step == .helper || step == .inputMonitoring || step == .postEvent,
           previous[step] != .granted, self[step] == .granted {
            return firstMissing ?? .summary
        }
        return step
    }

    @MainActor
    static func read() async -> Self {
        let helperStatus = HelperRegistration.service.status
        let mode = InputProtectionMode(helperStatus: helperStatus)
        let helper: PermissionState = switch helperStatus {
        case .enabled: .granted
        case .requiresApproval: .needsApproval
        case .notRegistered, .notFound: .missing
        @unknown default: .unavailable(L10n.permissionUnknown())
        }
        let agent = SMAppService.agent(plistName: LayerService.sessionInput.plistName)
        var input: PermissionState
        switch agent.status {
        case .enabled:
            input = .granted
            for required in mode.requiredInputs {
                let client = LayerClient(service: required.service)
                let allowed = await client.hasInputPermissions()
                client.resetIdleConnection()
                guard allowed == true else {
                    input = allowed == nil ? .unavailable(L10n.permissionUnknown()) : .missing
                    break
                }
            }
        case .requiresApproval: input = .needsApproval
        default: input = .missing
        }
        return Self(mode: mode, helper: helper, input: input, post: hasPostEventAccess() ? .granted : .missing)
    }
}

@MainActor
final class WalkthroughModel: ObservableObject {
    @Published private(set) var permissions: WalkthroughPermissions
    @Published var step: WalkthroughStep

    init(permissions: WalkthroughPermissions, completed: Bool) {
        self.permissions = permissions
        step = permissions.initialStep(completed: completed)
    }

    func update(_ next: WalkthroughPermissions) {
        guard next != permissions else { return }
        step = next.updatedStep(step, previous: permissions)
        permissions = next
    }
}
