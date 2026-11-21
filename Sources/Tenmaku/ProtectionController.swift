import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Combine
import Foundation
import IOKit.hid
import LocalAuthentication
import OSLog
import ServiceManagement
import TenmakuShared

/// Accessibility grants event posting as well. CoreGraphics preflight can keep returning
/// its initial denial after the user grants Accessibility to this running process.
func hasPostEventAccess() -> Bool {
    AXIsProcessTrusted() || IOHIDCheckAccess(kIOHIDRequestTypePostEvent) == kIOHIDAccessTypeGranted
}

/// Create the entry in System Settings and show the permission dialog.
func requestPostEventAccess() {
    _ = CGRequestPostEventAccess()
    _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
}

enum ProtectionState: Equatable {
    case idle
    case starting
    case shielded
    /// The user or macOS locked the session. Keep the layers active and clear the locked state.
    case interrupted
    /// The app lock cannot continue. Waiting for the session lock to take effect.
    case handingOff(String)
    case failed(String)

    var allowsConfiguration: Bool {
        switch self {
        case .idle, .failed: true
        case .starting, .shielded, .interrupted, .handingOff: false
        }
    }
}

private struct ActiveLockConfiguration: Codable {
    let inputMode: InputProtectionMode
    let splitInput: Bool?
}

private let replyTimeoutSeconds = 3.0
private let serviceLog = Logger(subsystem: "jp.pronama.tenmaku", category: "registration")
// The keys change before the lock screen is drawn.
private let lockSettleDuration = Duration.milliseconds(1500)
private let lockRetryDuration = Duration.seconds(5)

private func testFlag(_ name: String) -> Bool {
    #if TENMAKU_TEST_BUILD
    FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Library/Caches/jp.pronama.tenmaku.test-" + name)
    #else
    false
    #endif
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

@MainActor
final class LayerClient {
    private let service: LayerService
    private var connection: NSXPCConnection?
    private var connectionGeneration = 0
    /// True from the shielding request until release. A disconnect during this interval means the layer is lost.
    private var held = false
    var pointerOnly: Bool?
    var onLost: (() -> Void)?

    init(service: LayerService) {
        self.service = service
    }

    private func proxy(onError: @escaping @Sendable (Error) -> Void) -> ShieldLayer? {
        let connection = connection ?? {
            let new = NSXPCConnection(machServiceName: service.rawValue, options: service.isPrivileged ? .privileged : [])
            switch service {
            case .gamma: new.remoteObjectInterface = NSXPCInterface(with: ShieldLayer.self)
            case .cover: new.remoteObjectInterface = NSXPCInterface(with: CoverControl.self)
            case .input, .sessionInput: new.remoteObjectInterface = NSXPCInterface(with: InputControl.self)
            }
            new.setCodeSigningRequirement(service.signingRequirement)
            connectionGeneration += 1
            let generation = connectionGeneration
            let lost: @Sendable () -> Void = { [weak self] in
                Task { @MainActor in self?.connectionLost(generation: generation) }
            }
            new.interruptionHandler = lost
            new.invalidationHandler = lost
            new.resume()
            self.connection = new
            return new
        }()
        return connection.remoteObjectProxyWithErrorHandler(onError) as? ShieldLayer
    }

    // Use the disconnect to detect a peer exit because the next call can block until launchd restarts it.
    private func connectionLost(generation: Int) {
        guard generation == connectionGeneration, let lost = connection else { return }
        connection = nil
        lost.invalidate()
        // A disconnect alone does not prove the peer released protection.
        if held { onLost?() }
    }

    /// Take over layers that are still active after the UI restarts.
    func adopt() {
        held = true
    }

    func resetIdleConnection() {
        guard !held else { return }
        connectionLost(generation: connectionGeneration)
    }

    func preflight(holdDurations: InputHoldDurations = .standard, unlockKey: UnlockKey = .any) async -> String? {
        await command { layer, reply in
            if let pointerOnly {
                guard let input = layer as? InputControl else { return reply(LayerFailure.inputControlStartFailed.error()) }
                input.preflight(unlockHoldSeconds: holdDurations.unlockSeconds, escapeHoldSeconds: holdDurations.escapeSeconds,
                                unlockKeyUsage: unlockKey.rawValue, pointerOnly: pointerOnly, reply: reply)
            } else {
                layer.preflight(unlockHoldSeconds: holdDurations.unlockSeconds, escapeHoldSeconds: holdDurations.escapeSeconds, reply: reply)
            }
        }
    }

    func engage(holdDurations: InputHoldDurations = .standard, unlockKey: UnlockKey = .any) async -> String? {
        held = true
        return await command { layer, reply in
            if let pointerOnly {
                guard let input = layer as? InputControl else { return reply(LayerFailure.inputControlStartFailed.error()) }
                input.engage(unlockHoldSeconds: holdDurations.unlockSeconds, escapeHoldSeconds: holdDurations.escapeSeconds,
                                unlockKeyUsage: unlockKey.rawValue, pointerOnly: pointerOnly, reply: reply)
            } else {
                layer.engage(unlockHoldSeconds: holdDurations.unlockSeconds, escapeHoldSeconds: holdDurations.escapeSeconds, reply: reply)
            }
        }
    }

    func restoreCover() async -> String? {
        held = true
        return await command { layer, reply in
            guard let cover = layer as? CoverControl else { return reply(LayerFailure.coverFailed.error()) }
            cover.restoreCover(reply: reply)
        }
    }

    func holdForHandoff() async -> Bool? {
        held = true
        return await query { layer, reply in
            guard let cover = layer as? CoverControl else { return reply(false) }
            cover.holdForHandoff(reply: reply)
        }
    }

    func release(afterSessionLock: Bool = false) async -> String? {
        guard held else { return nil }
        let failure = await command { $0.release(afterSessionLock: afterSessionLock, reply: $1) }
        if failure == nil { held = false }
        return failure
    }

    private func command(_ body: (ShieldLayer, @escaping @Sendable (NSError?) -> Void) -> Void) async -> String? {
        await withCheckedContinuation { continuation in
            let once = Once()
            let finish: @Sendable (String?) -> Void = { result in
                if once.claim() { continuation.resume(returning: result) }
            }
            guard let proxy = proxy(onError: { finish(L10n.connectionNoResponse($0.localizedDescription)) }) else {
                finish(L10n.connectionFailed())
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + replyTimeoutSeconds) { finish(L10n.connectionTimeout()) }
            body(proxy) { error in finish(error.map { localizedLayerError($0) }) }
        }
    }

    /// Treat a missing reply as unknown.
    func isEngaged() async -> Bool? {
        await query { layer, reply in
            if let pointerOnly {
                guard let input = layer as? InputControl else { return reply(false) }
                input.isEngaged(pointerOnly: pointerOnly, reply: reply)
            } else {
                layer.isEngaged(reply: reply)
            }
        }
    }

    func takeUnlockRequest() async -> Bool {
        await query { $0.takeUnlockRequest(reply: $1) } ?? false
    }

    func takeEscapeRequest() async -> Bool {
        await query { $0.takeEscapeRequest(reply: $1) } ?? false
    }

    var isHeld: Bool { held }

    func hasInputPermissions() async -> Bool? {
        await query { layer, reply in
            guard let input = layer as? InputControl else { return reply(false) }
            input.hasInputPermissions(reply: reply)
        }
    }

    func canUnregisterHelper() async -> Bool {
        await query { layer, reply in
            guard let input = layer as? InputControl, let check = input.canUnregisterHelper else { return reply(false) }
            check(reply)
        } == true
    }

    func hasProtection() async -> Bool? {
        let remaining = await query { $0.hasProtection(reply: $1) }
        if remaining == false { held = false }
        return remaining
    }

    private func query(_ body: (ShieldLayer, @escaping @Sendable (Bool) -> Void) -> Void) async -> Bool? {
        await withCheckedContinuation { continuation in
            let once = Once()
            let finish: @Sendable (Bool?) -> Void = { result in
                if once.claim() { continuation.resume(returning: result) }
            }
            guard let proxy = proxy(onError: { _ in finish(nil) }) else {
                finish(nil)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + replyTimeoutSeconds) { finish(nil) }
            body(proxy) { finish($0) }
        }
    }
}

private let unlockTimeoutNanoseconds: UInt64 = 30_000_000_000

@MainActor
final class ProtectionController: ObservableObject {
    @Published private(set) var state: ProtectionState = .idle {
        didSet { onChange?(state) }
    }
    @Published private(set) var helperStatus = HelperRegistration.service.status
    @Published private(set) var helperChangeFailure: String?
    @Published private var changingHelper = false
    private(set) var unlockFailure: String?
    var onChange: ((ProtectionState) -> Void)?
    var onBeforeEngage: (() async -> Void)?

    private let gamma = LayerClient(service: .gamma)
    private let cover = LayerClient(service: .cover)
    private let inputs = [
        InputProtectionMode.helper: LayerClient(service: .input),
        InputProtectionMode.eventTap: LayerClient(service: .sessionInput),
    ]
    private var activeInputs: [LayerClient] = []
    @Published private var monitor: Task<Void, Never>?
    @Published private var restoring = false
    @Published private var stopping = false
    @Published private var showingUnlockGuide = false
    private let lockRecordURL: URL
    private var layerRevision = 0
    private var authentication: LAContext?
    // Give each request a unique number so stale or canceled attempts cannot unlock.
    private var unlockRequest = 0

    init(lockRecordURL: URL = URL.applicationSupportDirectory
        .appendingPathComponent("jp.pronama.tenmaku/active-lock.json")) {
        self.lockRecordURL = lockRecordURL
        gamma.onLost = { [weak self] in self?.reportDegraded(L10n.protectionGammaLost()) }
        cover.onLost = { [weak self] in self?.reportDegraded(L10n.protectionCoverLost()) }
        for input in inputs.values {
            input.onLost = { [weak self] in
                guard let self else { return }
                layerRevision += 1
                handOffToSessionLock(L10n.protectionInputLost())
            }
        }
    }

    /// Clear the locked state while preserving the remaining layers and the unlock signal.
    private func reportDegraded(_ reason: String) {
        layerRevision += 1
        guard monitor != nil else { return }
        if case .handingOff = state { return }
        state = .failed(reason)
    }

    /// Keep the remaining layers in place while locking the session, then release them after confirming the lock.
    private func handOffToSessionLock(_ reason: String) {
        guard monitor != nil else { return }
        monitor?.cancel()
        cancelAuthentication()
        state = .handingOff(reason)
        requestSessionLock()
        monitor = Task { await waitForSessionLock() }
    }

    private func waitForSessionLock() async {
        var sawLockedSession = false
        var coveredSince: (layout: LockedScreenLayout, time: ContinuousClock.Instant)?
        var lastRequest = ContinuousClock.now
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if Task.isCancelled { return }
            let now = ContinuousClock.now
            if canConfirmSessionLock {
                sawLockedSession = true
                if let layout = LockedScreenLayout.confirmed() {
                    if let coveredSince, coveredSince.layout == layout {
                        if now - coveredSince.time >= lockSettleDuration {
                            stop(handingOff: layout)
                            return
                        }
                    } else {
                        coveredSince = (layout, now)
                    }
                } else {
                    coveredSince = nil
                }
            } else if sawLockedSession, currentSessionIsLocked() == false, activeInputs.contains(where: \.isHeld) {
                // The user returned before lock confirmation. Treat this as a return from the lock screen and start over with Touch ID.
                watch()
                return
            } else {
                coveredSince = nil
                if now - lastRequest >= lockRetryDuration {
                    requestSessionLock()
                    lastRequest = now
                }
            }
        }
    }

    private var canConfirmSessionLock: Bool {
        !testFlag("hide-lock") && !testFlag("foreign-session") && sessionLockIsConfirmed()
    }

    /// After restarting the UI, read the active layers again. Startup leaves protection in place.
    func restoreIfEngaged() {
        guard !changingHelper, !restoring, monitor == nil, state == .idle else { return }
        restoring = true
        let configuration = (try? Data(contentsOf: lockRecordURL))
            .flatMap { try? JSONDecoder().decode(ActiveLockConfiguration.self, from: $0) }
        let agents = (LayerService.agents + [.sessionInput]).map { SMAppService.agent(plistName: $0.plistName) }
        // Keep the launchd registration current if an app update moves the executable.
        agents.filter { $0.status == .enabled }.forEach { try? $0.register() }
        let registeredInputs = InputProtectionMode.allCases.filter { inputService($0).status == .enabled }
        let gammaRegistered = SMAppService.agent(plistName: LayerService.gamma.plistName).status == .enabled
        let coverRegistered = SMAppService.agent(plistName: LayerService.cover.plistName).status == .enabled
        Task {
            defer { restoring = false }
            let revision = layerRevision
            if gammaRegistered { gamma.adopt() }
            if coverRegistered { cover.adopt() }
            let gammaEngaged = gammaRegistered ? await gamma.isEngaged() : false
            var coverEngaged = coverRegistered ? await cover.isEngaged() : false
            let gammaHeld = gammaRegistered ? await gamma.hasProtection() : false
            let coverHeld = coverRegistered ? await cover.hasProtection() : false
            var inputUnknown = false
            var inputUnhealthy = false
            let split = configuration?.splitInput == true
            for mode in registeredInputs {
                let input = inputs[mode]!
                input.pointerOnly = split ? (mode == .eventTap && configuration?.inputMode == .helper) : nil
                input.adopt()
                let engaged = await input.isEngaged()
                let held = await input.hasProtection()
                if held != false || engaged != false {
                    input.adopt()
                    activeInputs.append(input)
                }
                if engaged == nil || held == nil { inputUnknown = true }
                if held == true && engaged != true { inputUnhealthy = true }
            }
            guard gammaHeld != false || coverHeld != false || !activeInputs.isEmpty || revision != layerRevision else {
                clearLockRecord()
                if gammaRegistered, coverRegistered {
                    _ = await prepareGammaService()
                }
                return
            }
            if coverRegistered, coverHeld == false {
                if await cover.restoreCover() == nil { coverEngaged = await cover.isEngaged() }
            }
            if let mode = configuration?.inputMode {
                for required in split ? mode.requiredInputs : [mode] {
                    let expected = inputs[required]!
                    if !activeInputs.contains(where: { $0 === expected }) {
                        activeInputs.append(expected)
                        inputUnhealthy = true
                    }
                }
            }
            if configuration == nil {
                // Without the record the UI cannot verify which services or tap mask the lock required.
                state = .failed(L10n.protectionStateUnknown())
                watch()
                handOffToSessionLock(L10n.protectionStateUnknown())
                return
            }
            if revision != layerRevision || inputUnknown || gammaEngaged == nil || coverEngaged == nil || gammaHeld == nil || coverHeld == nil {
                state = .failed(L10n.protectionStateUnknown())
            } else if currentSessionIsLocked() != false {
                state = .interrupted
            } else if activeInputs.isEmpty || inputUnhealthy {
                state = .failed(L10n.protectionInputLost())
            } else if let reason = degradation(gamma: gammaEngaged == true, cover: coverEngaged == true) {
                state = .failed(reason)
            } else {
                state = .shielded
            }
            watch()
        }
    }

    private func saveLockRecord(_ configuration: ActiveLockConfiguration) throws {
        try FileManager.default.createDirectory(at: lockRecordURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(configuration).write(to: lockRecordURL, options: .atomic)
    }

    private func clearLockRecord() {
        try? FileManager.default.removeItem(at: lockRecordURL)
    }

    private func inputService(_ mode: InputProtectionMode) -> SMAppService {
        mode.service.isPrivileged ? .daemon(plistName: mode.service.plistName) : .agent(plistName: mode.service.plistName)
    }

    /// Send Control-Command-Q.
    private func requestSessionLock() {
        guard !testFlag("ignore-lock-request") else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 12, keyDown: keyDown)
            event?.flags = [.maskControl, .maskCommand]
            event?.post(tap: .cghidEventTap)
        }
    }

    // macOS can see a button as stuck down if it was pressed before the device was seized and released while it was seized.
    private func clearStaleButtons() {
        let source = CGEventSource(stateID: .hidSystemState)
        let location = CGEvent(source: nil)?.location ?? .zero
        let buttons: [(CGMouseButton, CGEventType)] = [(.left, .leftMouseUp), (.right, .rightMouseUp), (.center, .otherMouseUp)]
        for (button, type) in buttons where CGEventSource.buttonState(.hidSystemState, button: button) {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: button)?.post(tap: .cghidEventTap)
        }
    }

    private func registrationFailure(_ service: SMAppService) -> String? {
        var failure: Error?
        if service.status != .enabled {
            // Check the status first because register throws when approval is still pending.
            do { try service.register() } catch { failure = error }
        }
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return L10n.protectionLoginItemsRequired()
        }
        return failure.map { L10n.protectionRegistrationFailed($0.localizedDescription) }
    }

    private func gammaHealthAvailable() async -> Bool {
        let connection = NSXPCConnection(machServiceName: gammaHealthMachService)
        connection.remoteObjectInterface = NSXPCInterface(with: GammaHealth.self)
        connection.setCodeSigningRequirement(LayerService.gamma.signingRequirement)
        connection.resume()
        let available = await withCheckedContinuation { continuation in
            let once = Once()
            let finish: @Sendable (Bool) -> Void = { available in
                if once.claim() { continuation.resume(returning: available) }
            }
            guard let health = connection.remoteObjectProxyWithErrorHandler({ _ in finish(false) }) as? GammaHealth else {
                finish(false)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + replyTimeoutSeconds) { finish(false) }
            health.sample { _, _ in finish(true) }
        }
        connection.invalidate()
        return available
    }

    private func prepareGammaService() async -> String? {
        if await gammaHealthAvailable() { return nil }
        // Unregistering stops the process. Update the registration only after confirming that no layer is shielding the displays.
        guard await gamma.hasProtection() == false, await cover.hasProtection() == false else {
            return L10n.errorCoverFailed()
        }
        let service = SMAppService.agent(plistName: LayerService.gamma.plistName)
        if service.status == .enabled {
            gamma.resetIdleConnection()
            do {
                try await service.unregister()
            } catch {
                return L10n.protectionRegistrationFailed(error.localizedDescription)
            }
        }
        if let reason = registrationFailure(service) { return reason }
        guard await gammaHealthAvailable() else { return L10n.errorCoverFailed() }
        serviceLog.notice("Refreshed the gamma agent registration and verified its health service")
        return nil
    }

    /// Report missing prerequisites that can be checked before changing the displays.
    private func preflightFailure(inputMode: InputProtectionMode) -> String? {
        if let reason = recoveryPreflightFailure(inputMode: inputMode) { return reason }
        guard let isMirrored else { return L10n.protectionDisplaysUnknown() }
        if isMirrored { return L10n.protectionMirroredStart() }
        for service in LayerService.agents {
            if let reason = registrationFailure(.agent(plistName: service.plistName)) { return reason }
        }
        for required in inputMode.requiredInputs {
            if let reason = registrationFailure(inputService(required)) { return reason }
        }
        guard hasPostEventAccess() else {
            requestPostEventAccess()
            return L10n.protectionLockPermissionRequired()
        }
        return nil
    }

    private func recoveryPreflightFailure(inputMode: InputProtectionMode) -> String? {
        guard LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return L10n.protectionTouchIdRequired()
        }
        if inputMode == .eventTap, IsSecureEventInputEnabled() {
            return L10n.errorSecureEventInput()
        }
        return nil
    }

    var canQuit: Bool {
        state.allowsConfiguration && !restoring && !stopping && !showingUnlockGuide && monitor == nil && !changingHelper
    }

    func refreshHelperStatus() {
        let status = HelperRegistration.service.status
        if helperStatus != status { helperStatus = status }
    }

    func setHelperEnabled(_ enabled: Bool) async {
        guard canQuit else { return }
        changingHelper = true
        defer {
            refreshHelperStatus()
            changingHelper = false
        }
        helperChangeFailure = nil
        let helper = HelperRegistration.service
        do {
            if enabled {
                if !HelperRegistration.requested(helper.status) { try helper.register() }
                if helper.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                } else if helper.status != .enabled {
                    helperChangeFailure = L10n.permissionNotInstalled()
                }
            } else if HelperRegistration.requested(helper.status) {
                // The daemon can still be draining held keys after the UI has finished unlocking.
                if helper.status == .enabled {
                    guard let input = inputs[.helper], await input.canUnregisterHelper() else {
                        helperChangeFailure = L10n.settingsHelperBusy()
                        return
                    }
                    input.resetIdleConnection()
                }
                try await helper.unregister()
                if HelperRegistration.requested(helper.status) {
                    helperChangeFailure = L10n.settingsHelperStillRegistered()
                }
            }
        } catch {
            helperChangeFailure = L10n.protectionRegistrationFailed(error.localizedDescription)
        }
    }

    private var canStart: Bool {
        canQuit
    }

    func start() {
        guard canStart else { return }
        showingUnlockGuide = true
        // Let the menu or SwiftUI action return before opening the modal.
        DispatchQueue.main.async { [self] in
            showingUnlockGuide = false
            confirmAndStart()
        }
    }

    private func confirmAndStart() {
        guard canStart else { return }
        let unlockHoldSeconds = UserDefaults.standard.object(forKey: DefaultsKey.unlockHoldSeconds) as? Int ?? defaultUnlockHoldSeconds
        let escapeHoldSeconds = UserDefaults.standard.object(forKey: DefaultsKey.escapeHoldSeconds) as? Int ?? defaultEscapeHoldSeconds
        let savedKey = UnlockKey(rawValue: UserDefaults.standard.integer(forKey: DefaultsKey.unlockKey)) ?? .any
        let customEnabled = UserDefaults.standard.object(forKey: DefaultsKey.customUnlockKeyEnabled) as? Bool
        let unlockKey = UnlockKeyPreference(savedKey: savedKey, customEnabled: customEnabled).effectiveKey
        guard let holdDurations = InputHoldDurations(unlockSeconds: Double(unlockHoldSeconds), escapeSeconds: Double(escapeHoldSeconds)) else {
            state = .failed(L10n.errorInvalidUnlockHold())
            return
        }
        let mode = InputProtectionMode.selected
        showingUnlockGuide = true
        let confirmed = UnlockGuide.confirmIfNeeded(holdDurations: holdDurations, inputMode: mode, unlockKey: unlockKey)
        showingUnlockGuide = false
        // State can change asynchronously while the modal is open, for example during restoration.
        guard confirmed, canStart else { return }
        if let reason = preflightFailure(inputMode: mode) {
            state = .failed(reason)
            return
        }
        unlockFailure = nil
        activeInputs = mode.requiredInputs.map { required in
            let input = inputs[required]!
            input.pointerOnly = mode == .helper && required == .eventTap
            return input
        }
        state = .starting
        Task {
            if let reason = await prepareGammaService() {
                activeInputs = []
                state = .failed(reason)
                return
            }
            for input in activeInputs {
                if let reason = await input.preflight(holdDurations: holdDurations, unlockKey: unlockKey) {
                    activeInputs = []
                    state = .failed(reason)
                    return
                }
            }
            @MainActor func engageInputs() async -> String? {
                var firstFailure: String?
                for input in activeInputs {
                    let failure = await input.engage(holdDurations: holdDurations, unlockKey: unlockKey)
                    firstFailure = firstFailure ?? failure
                }
                return firstFailure
            }
            // Wait for the startup animation before shielding the physical displays.
            await onBeforeEngage?()
            if let reason = recoveryPreflightFailure(inputMode: mode) {
                activeInputs = []
                state = .failed(reason)
                return
            }
            do {
                try saveLockRecord(ActiveLockConfiguration(inputMode: mode, splitInput: true))
            } catch {
                state = .failed(L10n.protectionStateUnknown())
                activeInputs = []
                return
            }
            let revision = layerRevision
            // Wait for the monitor to respond before changing gamma or input.
            if let reason = await cover.engage() {
                if await cover.hasProtection() == false {
                    activeInputs = []
                    clearLockRecord()
                    state = .failed(reason)
                } else {
                    // Let the user hold a key to request authentication even if the black windows are already visible.
                    _ = await engageInputs()
                    state = .failed(reason)
                    watch()
                }
                return
            }
            // Continue to the input layer if gamma fails so the user can request unlock while the black windows are visible.
            let gammaFailure = await gamma.engage()
            let inputFailure = await engageInputs()
            var inputEngaged = true
            for input in activeInputs where await input.isEngaged() != true { inputEngaged = false }
            let gammaEngaged = await gamma.isEngaged()
            let coverEngaged = await cover.isEngaged()
            if let reason = gammaFailure ?? inputFailure {
                state = .failed(reason)
            } else if inputEngaged != true {
                state = .failed(L10n.protectionInputLost())
            } else if let reason = degradation(gamma: gammaEngaged == true, cover: coverEngaged == true) {
                state = .failed(reason)
            } else if revision != layerRevision {
                state = .failed(L10n.protectionStateUnknown())
            } else if currentSessionIsLocked() != false {
                state = .interrupted
            } else {
                state = .shielded
            }
            watch()
        }
    }

    var canRequestUnlock: Bool {
        monitor != nil && !stopping && (state == .shielded || isFailed) && currentSessionIsLocked() == false
    }

    func requestUnlock() {
        guard canRequestUnlock, authentication == nil else { return }
        // Play a sound when it is time to touch Touch ID because the prompt is hidden while shielding is active.
        NSSound(named: "Glass")?.play()
        unlockRequest += 1
        let request = unlockRequest
        let context = LAContext()
        context.localizedFallbackTitle = ""
        authentication = context
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: L10n.protectionUnlockReason()) { [weak self] success, error in
            let code = (error as? LAError)?.code
            Task { @MainActor in
                #if TENMAKU_TEST_BUILD
                let caches = NSHomeDirectory() + "/Library/Caches/jp.pronama.tenmaku.test-"
                if FileManager.default.fileExists(atPath: caches + "delay-auth") {
                    FileManager.default.createFile(atPath: caches + "auth-returned", contents: nil)
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                }
                #endif
                self?.finishUnlock(request: request, success: success, code: code)
            }
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: unlockTimeoutNanoseconds)
            self?.expireUnlock(request: request)
        }
    }

    private func finishUnlock(request: Int, success: Bool, code: LAError.Code?) {
        guard request == unlockRequest, authentication != nil, monitor != nil else { return }
        guard currentSessionIsLocked() == false else {
            cancelAuthentication()
            state = .interrupted
            return
        }
        authentication = nil
        if success, !testFlag("biometry-lockout") {
            unlockFailure = nil
            stop()
        } else if testFlag("biometry-lockout") || code == .biometryLockout || code == .biometryNotAvailable || code == .biometryNotEnrolled {
            // Periodic Touch ID lockouts can occur. Leave the session running while the user is away.
            reportUnlockFailure(L10n.protectionTouchIdUnavailable())
        } else {
            reportUnlockFailure(L10n.protectionAuthenticationFailed())
        }
    }

    private func expireUnlock(request: Int) {
        guard request == unlockRequest, authentication != nil, monitor != nil else { return }
        cancelAuthentication()
        reportUnlockFailure(L10n.protectionAuthenticationTimeout())
    }

    private func reportUnlockFailure(_ reason: String) {
        unlockFailure = reason
        onChange?(state)
    }

    private func cancelAuthentication() {
        unlockRequest += 1
        authentication?.invalidate()
        authentication = nil
    }

    func stop(handingOff layout: LockedScreenLayout? = nil) {
        guard !stopping else { return }
        stopping = true
        monitor?.cancel()
        monitor = nil
        cancelAuthentication()
        Task {
            let failure = await releaseProtection(handingOff: layout)
            stopping = false
            if let reason = failure {
                state = .failed(reason)
                watch()
            } else {
                activeInputs = []
                clearLockRecord()
                state = .idle
            }
        }
    }

    private func releaseProtection(handingOff layout: LockedScreenLayout?) async -> String? {
        if let layout {
            if let failure = await confirmHandoffCover(layout) { return failure }
            for layer in activeInputs + [gamma, cover] where layer.isHeld {
                if layer === gamma, let failure = await confirmHandoffCover(layout) { return failure }
                guard canConfirmSessionLock, LockedScreenLayout.confirmed() == layout else {
                    return L10n.errorSessionLockUnconfirmed()
                }
                if let failure = await layer.release(afterSessionLock: true) { return failure }
            }
            return nil
        }

        for input in activeInputs {
            if let failure = await input.release() { return failure }
        }
        guard currentSessionIsLocked() == false else { return L10n.errorSessionLockUnconfirmed() }
        // The split pointer tap starts with all buttons up and drains its own releases.
        if !activeInputs.contains(where: { $0.pointerOnly == true }) {
            clearStaleButtons()
        }
        if let failure = await cover.release() { return failure }
        if let failure = await gamma.release(), await gamma.hasProtection() != false {
            // Resume monitoring the emergency cover until gamma restoration can be confirmed.
            _ = await cover.restoreCover()
            return failure
        }
        return nil
    }

    private func confirmHandoffCover(_ layout: LockedScreenLayout) async -> String? {
        let deadline = ContinuousClock.now + .seconds(1)
        while canConfirmSessionLock, LockedScreenLayout.confirmed() == layout {
            let covered = await cover.holdForHandoff()
            guard canConfirmSessionLock, LockedScreenLayout.confirmed() == layout else { break }
            if covered == true { return nil }
            if covered == nil || ContinuousClock.now >= deadline { return L10n.protectionCoverLost() }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return L10n.errorSessionLockUnconfirmed()
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    private func watch() {
        monitor = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if Task.isCancelled { return }
                let revision = layerRevision
                let gammaEngaged = await gamma.isEngaged()
                let coverEngaged = await cover.isEngaged()
                var inputStates: [Bool?] = []
                for input in activeInputs { inputStates.append(await input.isEngaged()) }
                if Task.isCancelled { return }
                if revision != layerRevision { continue }
                if gammaEngaged == false && coverEngaged == false && inputStates.allSatisfy({ $0 == false }) {
                    let gammaHeld = await gamma.hasProtection()
                    let coverHeld = await cover.hasProtection()
                    var inputHeld: [Bool?] = []
                    for input in activeInputs { inputHeld.append(await input.hasProtection()) }
                    if Task.isCancelled { return }
                    if revision != layerRevision { continue }
                    if gammaHeld == false && coverHeld == false && inputHeld.allSatisfy({ $0 == false }) {
                        monitor = nil
                        cancelAuthentication()
                        clearLockRecord()
                        if isFailed { onChange?(state) } else { state = .idle }
                        return
                    }
                }
                if inputStates.isEmpty || inputStates.contains(where: { $0 != true }) {
                    handOffToSessionLock(L10n.protectionInputLost())
                    return
                }
                let locked = currentSessionIsLocked() != false && !testFlag("hide-lock")
                if locked {
                    cancelAuthentication()
                    if state != .interrupted { state = .interrupted }
                } else if authentication == nil, let sessionInput = inputs[.eventTap],
                          sessionInput.pointerOnly != true, activeInputs.contains(where: { $0 === sessionInput }), IsSecureEventInputEnabled() {
                    handOffToSessionLock(L10n.errorSecureEventInput())
                    return
                } else if let reason = degradation(gamma: gammaEngaged == true, cover: coverEngaged == true) {
                    if state != .failed(reason) { state = .failed(reason) }
                } else if state != .shielded {
                    state = .shielded
                }
                for input in activeInputs {
                    let unlock = await input.takeUnlockRequest()
                    if Task.isCancelled { return }
                    if unlock, !locked { requestUnlock() }

                    let escape = await input.takeEscapeRequest()
                    if Task.isCancelled { return }
                    if escape, locked || unlockFailure != nil {
                        handOffToSessionLock(L10n.protectionEscapeHeld())
                        return
                    }
                }
            }
        }
        onChange?(state)
    }

    private func degradation(gamma: Bool, cover: Bool) -> String? {
        guard let isMirrored else { return L10n.protectionDisplaysUnknown() }
        if isMirrored { return L10n.protectionMirrored() }
        if !gamma { return L10n.protectionGammaLost() }
        if !cover { return L10n.protectionCoverLost() }
        return nil
    }

    private var isMirrored: Bool? {
        onlineDisplayIDs()?.contains { CGDisplayIsInMirrorSet($0) != 0 }
    }
}
