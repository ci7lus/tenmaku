import Foundation
import Testing
import TenmakuShared
@testable import Tenmaku

@Suite
@MainActor
struct UnlockGuideTests {
    private let domain = "jp.pronama.tenmaku.unlock-guide-test.\(UUID().uuidString)"

    @Test
    func customWithoutCapturedKeyUsesAnyKey() {
        let preference = UnlockKeyPreference(savedKey: .any, customEnabled: true)
        #expect(preference.isCustom)
        #expect(preference.effectiveKey == .any)
    }

    @Test
    func capturedKeyIsAppliedOnlyInCustomMode() {
        #expect(UnlockKeyPreference(savedKey: .space, customEnabled: true).effectiveKey == .space)
        #expect(UnlockKeyPreference(savedKey: .space, customEnabled: false).effectiveKey == .any)
        #expect(UnlockKeyPreference(savedKey: .space, customEnabled: nil).effectiveKey == .space)
    }

    @Test
    func presentsAgainWhenSuppressionIsOff() throws {
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let durations = try #require(InputHoldDurations(unlockSeconds: 7, escapeSeconds: 3))

        var presentations = 0
        let cancelled = UnlockGuide.confirmIfNeeded(holdDurations: durations, inputMode: .helper, defaults: defaults) { presented in
            presentations += 1
            #expect(presented == durations)
            return (false, false)
        }
        #expect(!cancelled)

        for _ in 0..<2 {
            let confirmed = UnlockGuide.confirmIfNeeded(holdDurations: durations, inputMode: .helper, defaults: defaults) { _ in
                presentations += 1
                return (true, false)
            }
            #expect(confirmed)
        }
        #expect(presentations == 3)
    }

    @Test(arguments: [false, true])
    func persistsSuppressionAfterConfirmationOrCancellation(startLock: Bool) throws {
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }

        let decision = UnlockGuide.confirmIfNeeded(holdDurations: .standard, inputMode: .helper, defaults: defaults) { _ in
            (startLock, true)
        }
        #expect(decision == startLock)

        let reloaded = try #require(UserDefaults(suiteName: domain))
        let skipped = UnlockGuide.confirmIfNeeded(holdDurations: .standard, inputMode: .helper, defaults: reloaded) { _ in
            Issue.record("The unlock guide was shown after opting out.")
            return (false, false)
        }
        #expect(skipped)
    }
}
