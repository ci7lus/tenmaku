import ServiceManagement
import Testing
@testable import Tenmaku

@MainActor
struct HelperRegistrationTests {
    @Test func onlyAnApprovedDaemonSelectsHelperMode() {
        #expect(InputProtectionMode(helperStatus: .enabled) == .helper)
        for status in [SMAppService.Status.requiresApproval, .notRegistered, .notFound] {
            #expect(InputProtectionMode(helperStatus: status) == .eventTap)
        }
    }

    @Test func pendingApprovalCanBeCancelled() {
        #expect(HelperRegistration.requested(.requiresApproval))
        #expect(HelperRegistration.requested(.enabled))
        #expect(!HelperRegistration.requested(.notRegistered))
        #expect(!HelperRegistration.requested(.notFound))
    }

    @Test func onlyIdleOrFailedWithoutActiveProtectionCanChangeHelper() {
        #expect(ProtectionState.idle.allowsConfiguration)
        #expect(ProtectionState.failed("preflight").allowsConfiguration)
        for state in [ProtectionState.starting, .shielded, .interrupted, .handingOff("handoff")] {
            #expect(!state.allowsConfiguration)
        }
    }
}
