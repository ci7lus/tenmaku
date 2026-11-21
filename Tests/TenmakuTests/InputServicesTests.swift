import Testing
import TenmakuShared
@testable import Tenmaku

struct InputServicesTests {
    @Test func helperModeRequiresTheKeyboardHelperAndPointerAgent() {
        #expect(InputProtectionMode.helper.requiredInputs == [.helper, .eventTap])
        #expect(InputProtectionMode.eventTap.requiredInputs == [.eventTap])
    }
}
