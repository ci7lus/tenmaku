import AppKit
import TenmakuShared

final class GammaLayer: NSObject, ShieldLayer, GammaHealth, @unchecked Sendable {
    private var timer: DispatchSourceTimer?
    private var generation = 0
    private var stability = GammaStability()
    private var sampledDisplays: Set<CGDirectDisplayID> = []

    func preflight(unlockHoldSeconds: Double, escapeHoldSeconds: Double, reply: @escaping @Sendable (NSError?) -> Void) {
        reply(nil)
    }

    func engage(unlockHoldSeconds: Double, escapeHoldSeconds: Double, reply: @escaping @Sendable (NSError?) -> Void) {
        DispatchQueue.main.async { [self] in
            blackOutAll()
            if timer == nil {
                let timer = DispatchSource.makeTimerSource(queue: .main)
                timer.schedule(deadline: .now(), repeating: .milliseconds(20))
                timer.setEventHandler { [weak self] in self?.blackOutAll() }
                timer.resume()
                self.timer = timer
            }
            generation += 1
            #if TENMAKU_TEST_BUILD
            let current = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + testAutoReleaseSeconds) { [self] in
                if current == generation { stop() }
            }
            #endif
            let black = allDisplaysBlack()
            stability.record(allBlack: black, at: ProcessInfo.processInfo.systemUptime)
            reply(black ? nil : LayerFailure.gammaFailed.error())
        }
    }

    func release(afterSessionLock: Bool, reply: @escaping @Sendable (NSError?) -> Void) {
        DispatchQueue.main.async { [self] in
            guard timer != nil else { return reply(nil) }
            if afterSessionLock, LockedScreenLayout.confirmed() == nil {
                return reply(LayerFailure.sessionLockUnconfirmed.error())
            }
            stop()
            reply(nil)
        }
    }

    func isIdle() -> Bool {
        timer == nil
    }

    func takeUnlockRequest(reply: @escaping @Sendable (Bool) -> Void) {
        reply(false)
    }

    func takeEscapeRequest(reply: @escaping @Sendable (Bool) -> Void) {
        reply(false)
    }

    func hasProtection(reply: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.main.async { [self] in reply(timer != nil) }
    }

    func isEngaged(reply: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.main.async { [self] in
            reply(timer != nil && allDisplaysBlack())
        }
    }

    func sample(reply: @escaping @Sendable (Bool, Double) -> Void) {
        DispatchQueue.main.async { [self] in
            let now = ProcessInfo.processInfo.systemUptime
            reply(timer != nil, stability.isCurrent(at: now) ? stability.blackSince ?? -1 : -1)
        }
    }

    private func allDisplaysBlack() -> Bool {
        guard let displays = onlineDisplayIDs() else { return false }
        return displays.allSatisfy(isBlack) && displays == onlineDisplayIDs()
    }

    private func stop() {
        generation += 1
        timer?.cancel()
        timer = nil
        stability = GammaStability()
        sampledDisplays = []
        CGDisplayRestoreColorSyncSettings()
    }

    private func isBlack(_ display: CGDirectDisplayID) -> Bool {
        let capacity = CGDisplayGammaTableCapacity(display)
        var red = [CGGammaValue](repeating: 1, count: Int(capacity))
        var green = red
        var blue = red
        var sampleCount: UInt32 = 0
        guard capacity > 0,
              CGGetDisplayTransferByTable(display, capacity, &red, &green, &blue, &sampleCount) == .success,
              sampleCount > 0, sampleCount <= capacity else { return false }
        let samples = Int(sampleCount)
        return red.prefix(samples).allSatisfy { $0 == 0 }
            && green.prefix(samples).allSatisfy { $0 == 0 }
            && blue.prefix(samples).allSatisfy { $0 == 0 }
    }

    private func blackOutAll() {
        let displays = onlineDisplayIDs() ?? []
        if sampledDisplays != displays {
            sampledDisplays = displays
            stability = GammaStability()
        }
        // Record the readings for every display before reapplying gamma can erase evidence of nonzero values.
        let unverified = displays.filter { !isBlack($0) }
        stability.record(allBlack: !displays.isEmpty && unverified.isEmpty && displays == onlineDisplayIDs(),
                         at: ProcessInfo.processInfo.systemUptime)
        for display in unverified {
            let capacity = CGDisplayGammaTableCapacity(display)
            guard capacity > 0 else { continue }
            let zeros = [CGGammaValue](repeating: 0, count: Int(capacity))
            CGSetDisplayTransferByTable(display, capacity, zeros, zeros, zeros)
        }
    }
}

let layer = GammaLayer()
let listener = LayerListener(service: .gamma, layer: layer)
let healthListener = LayerListener(gammaHealth: layer)
listener.resume()
healthListener.resume()
exitWhenIdle { [layer] in layer.isIdle() }
// Run NSApplication to receive display reconfiguration notifications.
NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.run()
