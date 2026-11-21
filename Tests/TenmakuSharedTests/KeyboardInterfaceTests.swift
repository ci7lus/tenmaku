import IOKit.hid
import Testing
@testable import TenmakuShared

struct KeyboardInterfaceTests {
    private func usage(_ page: Int, _ value: Int) -> [String: Int] {
        [kIOHIDDeviceUsagePageKey: page, kIOHIDDeviceUsageKey: value]
    }

    @Test func onlyKeyboardInterfacesCanBeOpenedExclusively() {
        let keyboard = usage(1, 6)
        let mouse = usage(1, 2)
        #expect(KeyboardInterface.canSeize(primaryPage: 1, primaryUsage: 6, usages: [keyboard]))
        #expect(KeyboardInterface.canSeize(primaryPage: 1, primaryUsage: 7, usages: [usage(1, 7)]))
        #expect(!KeyboardInterface.canSeize(primaryPage: 1, primaryUsage: 2, usages: [mouse, usage(1, 1)]))
        #expect(!KeyboardInterface.canSeize(primaryPage: 1, primaryUsage: 6, usages: [keyboard, mouse]))
        #expect(!KeyboardInterface.canSeize(primaryPage: 1, primaryUsage: 6, usages: [keyboard, usage(13, 5)]))
        #expect(!KeyboardInterface.canSeize(primaryPage: 1, primaryUsage: 6, usages: nil))
    }
}
