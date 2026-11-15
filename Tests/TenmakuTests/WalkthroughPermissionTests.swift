import Testing
@testable import Tenmaku

struct WalkthroughPermissionTests {
    @Test(arguments: [InputProtectionMode.eventTap, .helper])
    func recheckingKeepsThePreviousResultForTheSameMode(mode: InputProtectionMode) {
        #expect(PermissionState.inputMonitoringDuringRefresh(
            mode: mode, isRegistered: true, previousMode: mode, previous: .granted
        ) == .granted)
        #expect(PermissionState.inputMonitoringDuringRefresh(
            mode: mode, isRegistered: true, previousMode: mode, previous: .missing
        ) == .missing)
    }

    @Test
    func waitsForAResultOnInitialCheckOrWhenChangingMode() {
        #expect(PermissionState.inputMonitoringDuringRefresh(
            mode: .eventTap, isRegistered: true, previousMode: .eventTap, previous: nil
        ) == nil)
        #expect(PermissionState.inputMonitoringDuringRefresh(
            mode: .eventTap, isRegistered: true, previousMode: .helper, previous: .granted
        ) == nil)
    }

    @Test
    func showsMissingWhenThePreviouslyGrantedAgentIsNoLongerRegistered() {
        #expect(PermissionState.inputMonitoringDuringRefresh(
            mode: .eventTap, isRegistered: false, previousMode: .eventTap, previous: .granted
        ) == .missing)
    }
}
