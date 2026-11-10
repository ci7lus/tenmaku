import Foundation
import TenmakuShared

/// Display errors from the root helper in the UI process's language.
func localizedLayerError(_ error: NSError, bundle: Bundle = .main, locale: Locale = .current) -> String {
    guard error.domain == LayerFailure.domain, let failure = LayerFailure(rawValue: error.code) else {
        return L10n.errorUnknown(bundle: bundle, locale: locale)
    }
    switch failure {
    case .inputDevicesMissing:
        return L10n.errorInputDevicesMissing(bundle: bundle, locale: locale)
    case .inputMonitoringDenied:
        if let status = error.userInfo[LayerFailure.statusKey] as? NSNumber {
            return L10n.errorInputMonitoringStatus(String(format: "0x%08x", status.int32Value), bundle: bundle, locale: locale)
        }
        return L10n.errorInputMonitoringDenied(bundle: bundle, locale: locale)
    case .inputDeviceSeizeFailed:
        return L10n.errorInputDeviceSeizeFailed(bundle: bundle, locale: locale)
    case .inputControlStopped:
        return L10n.errorInputControlStopped(bundle: bundle, locale: locale)
    case .inputControlsHeld:
        return L10n.errorInputControlsHeld(bundle: bundle, locale: locale)
    case .inputPermissionsMissing:
        return L10n.errorInputPermissionsMissing(bundle: bundle, locale: locale)
    case .inputControlStartFailed:
        return L10n.errorInputControlStartFailed(bundle: bundle, locale: locale)
    case .inputControlMonitorFailed:
        return L10n.errorInputControlMonitorFailed(bundle: bundle, locale: locale)
    case .inputReleaseUnconfirmed:
        return L10n.errorInputReleaseUnconfirmed(bundle: bundle, locale: locale)
    case .invalidUnlockHold:
        return L10n.errorInvalidUnlockHold(bundle: bundle, locale: locale)
    case .inputAccessibilityDenied:
        return L10n.errorInputAccessibilityDenied(bundle: bundle, locale: locale)
    case .inputListenDenied:
        return L10n.errorInputListenDenied(bundle: bundle, locale: locale)
    case .gammaFailed:
        return L10n.errorGammaFailed(bundle: bundle, locale: locale)
    case .coverFailed:
        return L10n.errorCoverFailed(bundle: bundle, locale: locale)
    }
}
