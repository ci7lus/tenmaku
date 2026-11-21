import Testing
@testable import Tenmaku

struct WalkthroughPermissionTests {
    private func snapshot(input: PermissionState = .granted, post: PermissionState = .granted) -> WalkthroughPermissions {
        WalkthroughPermissions(mode: .eventTap, helper: .missing, input: input, post: post)
    }

    @Test func completedSetupReopensAtTheFirstMissingPermission() {
        #expect(snapshot(input: .missing, post: .missing).initialStep(completed: true) == .inputMonitoring)
        #expect(snapshot(post: .missing).initialStep(completed: true) == .postEvent)
        #expect(snapshot().initialStep(completed: true) == .summary)
        #expect(snapshot().initialStep(completed: false) == .welcome)
    }

    @Test func liveGrantsAdvanceAndRevocationsReopenSetup() {
        let missing = snapshot(input: .missing, post: .missing)
        let needsPost = snapshot(post: .missing)
        let ready = snapshot()
        #expect(needsPost.updatedStep(.inputMonitoring, previous: missing) == .postEvent)
        #expect(ready.updatedStep(.postEvent, previous: needsPost) == .summary)
        #expect(missing.updatedStep(.summary, previous: ready) == .inputMonitoring)
        #expect(ready.updatedStep(.helper, previous: ready) == .helper)
        #expect(ready.updatedStep(.inputMonitoring, previous: ready) == .inputMonitoring)
    }

    @Test func helperApprovalUsesTheNewModesRequiredPermissions() {
        let pending = WalkthroughPermissions(mode: .eventTap, helper: .needsApproval, input: .granted, post: .granted)
        let approved = WalkthroughPermissions(mode: .helper, helper: .granted, input: .missing, post: .granted)
        #expect(approved.updatedStep(.helper, previous: pending) == .inputMonitoring)
    }

    @MainActor @Test func repeatingASnapshotPreservesManualNavigation() {
        let ready = snapshot()
        let setup = WalkthroughModel(permissions: ready, completed: true)
        setup.step = .helper
        setup.update(ready)
        #expect(setup.step == .helper)
        setup.step = .summary
        setup.update(snapshot(post: .missing))
        #expect(setup.step == .postEvent)
        setup.update(ready)
        #expect(setup.step == .summary)
    }

    @Test func anUnavailableAgentCannotCompleteSetup() {
        #expect(snapshot(input: .unavailable("XPC")).firstMissing == .inputMonitoring)
        #expect(snapshot(input: .needsApproval).firstMissing == .inputMonitoring)
    }
}
