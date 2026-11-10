import AppKit
import TenmakuShared

final class GammaLayer: NSObject, ShieldLayer, @unchecked Sendable {
    private var timer: DispatchSourceTimer?
    private var generation = 0

    func preflight(reply: @escaping @Sendable (String?) -> Void) {
        reply(nil)
    }

    func engage(reply: @escaping @Sendable (String?) -> Void) {
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
            let displays = onlineDisplays()
            reply(!displays.isEmpty && displays.allSatisfy(isBlack) ? nil : "Could not set gamma to zero on all displays.")
        }
    }

    func release(afterSessionLock: Bool, reply: @escaping @Sendable (String?) -> Void) {
        DispatchQueue.main.async { [self] in
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

    func setUnlockHold(seconds: Double, reply: @escaping @Sendable (String?) -> Void) {
        reply(nil)
    }

    func takeEscapeRequest(reply: @escaping @Sendable (Bool) -> Void) {
        reply(false)
    }

    func hasProtection(reply: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.main.async { [self] in reply(timer != nil) }
    }

    func isEngaged(reply: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.main.async { [self] in
            reply(timer != nil)
        }
    }

    private func stop() {
        generation += 1
        timer?.cancel()
        timer = nil
        CGDisplayRestoreColorSyncSettings()
    }

    private func onlineDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return [] }
        return Array(displays.prefix(Int(count)))
    }

    private func isBlack(_ display: CGDirectDisplayID) -> Bool {
        let capacity = CGDisplayGammaTableCapacity(display)
        var red = [CGGammaValue](repeating: 1, count: Int(capacity))
        var green = red
        var blue = red
        var sampleCount: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, capacity, &red, &green, &blue, &sampleCount) == .success,
              sampleCount > 0 else { return false }
        let samples = Int(sampleCount)
        return red.prefix(samples).allSatisfy { $0 == 0 }
            && green.prefix(samples).allSatisfy { $0 == 0 }
            && blue.prefix(samples).allSatisfy { $0 == 0 }
    }

    private func blackOutAll() {
        for display in onlineDisplays() where !isBlack(display) {
            let zeros = [CGGammaValue](repeating: 0, count: Int(CGDisplayGammaTableCapacity(display)))
            CGSetDisplayTransferByTable(display, UInt32(zeros.count), zeros, zeros, zeros)
        }
    }
}

let layer = GammaLayer()
let listener = LayerListener(service: .gamma, layer: layer)
listener.resume()
exitWhenIdle { [layer] in layer.isIdle() }
// Run NSApplication to receive display reconfiguration notifications.
NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.run()
