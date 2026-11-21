import IOKit.hid

public enum KeyboardInterface {
    /// IOHIDDeviceOpen affects the entire interface, including all its top-level collections.
    public static func canSeize(primaryPage: Int?, primaryUsage: Int?, usages: [[String: Int]]?) -> Bool {
        let keys = [kHIDUsage_GD_Keyboard, kHIDUsage_GD_Keypad]
        guard primaryPage == kHIDPage_GenericDesktop, let primaryUsage, keys.contains(primaryUsage),
              let usages, !usages.isEmpty else { return false }
        return usages.allSatisfy { pair in
            guard let page = pair[kIOHIDDeviceUsagePageKey], let usage = pair[kIOHIDDeviceUsageKey] else { return false }
            return page == kHIDPage_GenericDesktop && keys.contains(usage)
        }
    }
}
