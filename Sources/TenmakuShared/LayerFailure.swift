import Foundation

/// Keep XPC errors language-independent so the app can display them in the user's language.
public enum LayerFailure: Int, CaseIterable, Sendable {
    case inputDevicesMissing = 1
    case inputMonitoringDenied = 2
    case inputDeviceSeizeFailed = 3
    case inputControlStopped = 4
    case inputControlsHeld = 5
    case inputPermissionsMissing = 6
    case inputControlStartFailed = 7
    case inputControlMonitorFailed = 8
    case inputReleaseUnconfirmed = 9
    case invalidUnlockHold = 10
    case inputAccessibilityDenied = 11
    case inputListenDenied = 12
    case gammaFailed = 13
    case coverFailed = 14
    case secureEventInput = 15
    case sessionLockUnconfirmed = 16
    case inputSessionMismatch = 17
    case invalidUnlockKey = 18

    public static let domain = "jp.pronama.tenmaku.layer"
    public static let statusKey = "status"

    public func error(status: Int32? = nil) -> NSError {
        var arguments: [String: Any] = [:]
        if let status { arguments[Self.statusKey] = NSNumber(value: status) }
        return NSError(domain: Self.domain, code: rawValue, userInfo: arguments)
    }
}
