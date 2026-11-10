import Foundation
import TenmakuShared

@main
@MainActor
struct UnlockGuideCheck {
    static func main() {
        let domain = "jp.pronama.tenmaku.unlock-guide-check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }

        let durations = InputHoldDurations(unlockSeconds: 7, escapeSeconds: 3)!
        var presentations = 0
        let cancelled = UnlockGuide.confirmIfNeeded(holdDurations: durations, defaults: defaults) { seconds in
            presentations += 1
            precondition(seconds.unlockSeconds == 7 && seconds.escapeSeconds == 3)
            return (false, false)
        }
        precondition(!cancelled)

        for _ in 0..<2 {
            let confirmed = UnlockGuide.confirmIfNeeded(holdDurations: durations, defaults: defaults) { _ in
                presentations += 1
                return (true, false)
            }
            precondition(confirmed)
        }
        precondition(presentations == 3, "The guide should appear every time while the checkbox is cleared")

        let confirmed = UnlockGuide.confirmIfNeeded(holdDurations: durations, defaults: defaults) { _ in
            presentations += 1
            return (true, true)
        }
        precondition(confirmed)
        let reloaded = UserDefaults(suiteName: domain)!
        precondition(UnlockGuide.confirmIfNeeded(holdDurations: durations, defaults: reloaded) { _ in
            fatalError("The guide should be skipped after selecting the checkbox")
        })
        precondition(presentations == 4)

        defaults.removePersistentDomain(forName: domain)
        precondition(!UnlockGuide.confirmIfNeeded(holdDurations: durations, defaults: defaults) { _ in (false, true) })
        precondition(UnlockGuide.confirmIfNeeded(holdDurations: durations, defaults: defaults) { _ in
            fatalError("The checkbox selection should be saved even when canceled")
        })
        print("Unlock guide passed cancellation, confirmation, redisplay, skipping, and saving the selection")
    }
}
