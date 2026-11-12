import AppKit
import TenmakuShared

final class CoverLayer: NSObject, CoverControl, @unchecked Sendable {
    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var state: EmergencyCoverState?
    private var generation = 0
    private var topologyRevision = 0
    private var reconfiguring = false
    private var observesQuartz = false
    private var armReply: (@Sendable (NSError?) -> Void)?
    private var timer: DispatchSourceTimer?
    private var connection: NSXPCConnection?
    private var connectionGeneration = 0
    private var sampleNumber = 0
    private var pendingSample: (number: Int, startedAt: TimeInterval)?
    private var nextConnectionAttempt: TimeInterval = 0
    private var lastPollAt: TimeInterval?

    override init() {
        super.init()
        let result = CGDisplayRegisterReconfigurationCallback({ _, flags, context in
            guard let context else { return }
            let layer = Unmanaged<CoverLayer>.fromOpaque(context).takeUnretainedValue()
            let beginning = flags.contains(.beginConfigurationFlag)
            DispatchQueue.main.async { layer.configurationChanged(beginning: beginning) }
        }, Unmanaged.passUnretained(self).toOpaque())
        observesQuartz = result == .success

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.configurationChanged(beginning: nil) }
        }
    }

    func preflight(unlockHoldSeconds: Double, escapeHoldSeconds: Double, reply: @escaping @Sendable (NSError?) -> Void) {
        reply(observesQuartz ? nil : LayerFailure.coverFailed.error())
    }

    func engage(unlockHoldSeconds: Double, escapeHoldSeconds: Double, reply: @escaping @Sendable (NSError?) -> Void) {
        DispatchQueue.main.async { [self] in
            guard observesQuartz, armReply == nil else { return reply(LayerFailure.coverFailed.error()) }
            guard state == nil else { return reply(nil) }
            armReply = reply
            startMonitoring(.starting(deadline: ProcessInfo.processInfo.systemUptime + 3))
        }
    }

    func restoreCover(reply: @escaping @Sendable (NSError?) -> Void) {
        DispatchQueue.main.async { [self] in
            if state == nil {
                startMonitoring(.covering(verifiedSince: nil))
            } else {
                requireCover()
            }
            reply(nil)
        }
    }

    func holdForHandoff(reply: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.main.async { [self] in
            if state == nil {
                startMonitoring(.handoff)
            } else {
                state = .handoff
                reconcile()
            }
            reply(!reconfiguring && allCovered())
        }
    }

    @MainActor
    private func startMonitoring(_ state: EmergencyCoverState) {
        self.state = state
        reconcile()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.pollGamma() }
        }
        self.timer = timer
        timer.resume()

        generation += 1
        #if TENMAKU_TEST_BUILD
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + testAutoReleaseSeconds) { [self] in
            if current == generation { stop() }
        }
        #endif
    }

    func release(afterSessionLock: Bool, reply: @escaping @Sendable (NSError?) -> Void) {
        DispatchQueue.main.async { [self] in
            if afterSessionLock, LockedScreenLayout.confirmed() == nil {
                return reply(LayerFailure.sessionLockUnconfirmed.error())
            }
            stop()
            reply(nil)
        }
    }

    func isIdle() -> Bool {
        state == nil
    }

    func takeUnlockRequest(reply: @escaping @Sendable (Bool) -> Void) {
        reply(false)
    }

    func takeEscapeRequest(reply: @escaping @Sendable (Bool) -> Void) {
        reply(false)
    }

    func hasProtection(reply: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.main.async { [self] in reply(state != nil) }
    }

    func isEngaged(reply: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.main.async { [self] in reply(state?.isReady == true) }
    }

    @MainActor
    private func configurationChanged(beginning: Bool?) {
        if let beginning { reconfiguring = beginning }
        topologyRevision += 1
        requireCover()
    }

    @MainActor
    private func requireCover() {
        guard var state else { return }
        // Bring the windows for known displays to the front before reading the updated display list.
        if !state.needsCover { windows.values.forEach { $0.orderFrontRegardless() } }
        state.requireCover()
        self.state = state
        reconcile()
    }

    @MainActor
    private func connectToGamma() -> NSXPCConnection {
        let peer = NSXPCConnection(machServiceName: gammaHealthMachService)
        peer.remoteObjectInterface = NSXPCInterface(with: GammaHealth.self)
        peer.setCodeSigningRequirement(LayerService.gamma.signingRequirement)
        connectionGeneration += 1
        let generation = connectionGeneration
        let lost: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in self?.connectionLost(generation: generation) }
        }
        peer.interruptionHandler = lost
        peer.invalidationHandler = lost
        connection = peer
        peer.resume()
        return peer
    }

    @MainActor
    private func connectionLost(generation: Int) {
        guard generation == connectionGeneration, let connection else { return }
        if armReply != nil, state?.canAbortArming == true {
            stop()
            return
        }
        requireCover()
        self.connection = nil
        pendingSample = nil
        nextConnectionAttempt = ProcessInfo.processInfo.systemUptime + 0.25
        connection.invalidate()
        finishArming(LayerFailure.coverFailed.error())
    }

    @MainActor
    private func pollGamma() {
        guard let state else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let lastPollAt, now - lastPollAt > 0.25, state.isReady || state.needsCover {
            requireCover()
        } else if state.needsCover {
            reconcile()
        }
        lastPollAt = now
        if let pendingSample {
            let timeout = armReply == nil ? 0.25 : 2
            if now - pendingSample.startedAt >= timeout {
                connectionLost(generation: connectionGeneration)
            }
            return
        }
        guard now >= nextConnectionAttempt else { return }
        let peer = connection ?? connectToGamma()
        let generation = connectionGeneration
        let revision = topologyRevision
        sampleNumber += 1
        let number = sampleNumber
        pendingSample = (number, now)
        guard let health = peer.remoteObjectProxyWithErrorHandler({ [weak self] _ in
            Task { @MainActor in self?.connectionLost(generation: generation) }
        }) as? GammaHealth else {
            connectionLost(generation: generation)
            return
        }
        health.sample { [weak self] active, blackSince in
            Task { @MainActor in
                self?.receivedSample(active: active, blackSince: blackSince, number: number, revision: revision)
            }
        }
    }

    @MainActor
    private func receivedSample(active: Bool, blackSince: TimeInterval, number: Int, revision: Int) {
        guard let pendingSample, pendingSample.number == number else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let timeout = armReply == nil ? 0.25 : 2
        guard now - pendingSample.startedAt < timeout else {
            connectionLost(generation: connectionGeneration)
            return
        }
        self.pendingSample = nil
        finishArming(nil)
        guard observesQuartz, revision == topologyRevision, !reconfiguring, var state else { return }
        if case .handoff = state { return }
        let condition: GammaCondition
        if !active {
            condition = .idle
        } else if blackSince >= 0, blackSince <= now {
            condition = .black(since: blackSince)
        } else {
            condition = .unstable
        }
        let wasCovering = state.needsCover
        let covered = if case .black = condition, wasCovering { allCovered() } else { false }
        state.observe(condition, allCovered: covered, at: now)
        self.state = state
        if state.needsCover && !wasCovering {
            reconcile()
        } else if !state.needsCover && wasCovering {
            hideWindows()
        }
    }

    @MainActor
    private func allCovered() -> Bool {
        guard let displays = onlineDisplayIDs(),
              displays.allSatisfy({ CGDisplayIsInMirrorSet($0) == 0 }),
              let snapshots = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return displays.allSatisfy { display in
            let bounds = CGDisplayBounds(display)
            guard !bounds.isEmpty, !bounds.isInfinite, let window = windows[display], window.isVisible else { return false }
            return snapshots.contains { snapshot in
                guard snapshot[kCGWindowNumber as String] as? Int == window.windowNumber,
                      snapshot[kCGWindowAlpha as String] as? Double == 1,
                      let dictionary = snapshot[kCGWindowBounds as String] as? [String: Any],
                      let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { return false }
                return rect.contains(bounds)
            }
        } && displays == onlineDisplayIDs()
    }

    @MainActor
    private func stop() {
        generation += 1
        state = nil
        timer?.cancel()
        timer = nil
        pendingSample = nil
        lastPollAt = nil
        let peer = connection
        connection = nil
        peer?.invalidate()
        nextConnectionAttempt = 0
        hideWindows()
        windows.removeAll()
        finishArming(LayerFailure.coverFailed.error())
    }

    @MainActor
    private func finishArming(_ error: NSError?) {
        let reply = armReply
        armReply = nil
        reply?(error)
    }

    @MainActor
    private func hideWindows() {
        windows.values.forEach { $0.orderOut(nil) }
    }

    @MainActor
    private func reconcile() {
        guard let state else { return }
        var current: Set<CGDirectDisplayID> = []
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            current.insert(id)
            let window = windows[id] ?? makeWindow()
            windows[id] = window
            if window.frame != screen.frame { window.setFrame(screen.frame, display: true) }
            if state.needsCover, !window.isVisible { window.orderFrontRegardless() }
        }
        guard !reconfiguring, let online = onlineDisplayIDs() else { return }
        for (id, window) in windows where !current.contains(id) && !online.contains(id) {
            window.orderOut(nil)
            windows[id] = nil
        }
    }

    @MainActor
    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.isOpaque = true
        window.alphaValue = 1
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return window
    }
}

let layer = CoverLayer()
let listener = LayerListener(cover: layer)
listener.resume()
exitWhenIdle { [layer] in layer.isIdle() }
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
