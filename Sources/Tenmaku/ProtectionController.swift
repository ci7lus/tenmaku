import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import LocalAuthentication
import ServiceManagement
import TenmakuShared

/// Create the entry in System Settings and show the permission dialog.
func requestPostEventAccess() {
    _ = CGRequestPostEventAccess()
    _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
}

enum ProtectionState: Equatable {
    case idle
    case starting
    case shielded
    /// The user or macOS locked the session. Keep the layers active and clear the protected state.
    case interrupted
    /// Protection cannot continue. Waiting for the session lock to take effect.
    case handingOff(String)
    case failed(String)
}

private let replyTimeoutSeconds = 3.0
// The keys change before the lock screen is drawn.
private let lockSettleDuration = Duration.milliseconds(1500)
private let lockRetryDuration = Duration.seconds(5)
private let loginWindowFullScreenLayer = 2001

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
    /// True from the shielding request until release. A disconnect during this interval means the layer is lost.
    private var held = false
    var onLost: (() -> Void)?

    init(service: LayerService) {
        self.service = service
    }

    private func proxy(onError: @escaping @Sendable (Error) -> Void) -> ShieldLayer? {
        let connection = connection ?? {
            let new = NSXPCConnection(machServiceName: service.rawValue, options: service == .input ? .privileged : [])
            new.remoteObjectInterface = NSXPCInterface(with: ShieldLayer.self)
            new.setCodeSigningRequirement(sameTeamRequirement)
            let lost: @Sendable () -> Void = { [weak self] in
                Task { @MainActor in self?.connectionLost() }
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
    private func connectionLost() {
        guard let lost = connection else { return }
        connection = nil
        lost.invalidate()
        if held {
            held = false
            onLost?()
        }
    }

    /// Take over layers that are still active after the UI restarts.
    func adopt() {
        held = true
    }

    func preflight() async -> String? {
        await command { $0.preflight(reply: $1) }
    }

    func engage() async -> String? {
        held = true
        return await command { $0.engage(reply: $1) }
    }

    func release() async -> String? {
        guard held else { return nil }
        held = false
        return await command { $0.release(reply: $1) }
    }

    private func command(_ body: (ShieldLayer, @escaping @Sendable (String?) -> Void) -> Void) async -> String? {
        await withCheckedContinuation { continuation in
            let once = Once()
            let finish: @Sendable (String?) -> Void = { result in
                if once.claim() { continuation.resume(returning: result.map(LegacyCopy.error)) }
            }
            guard let proxy = proxy(onError: { finish(LegacyCopy.text("No response: \($0.localizedDescription)", "応答がありません: \($0.localizedDescription)")) }) else {
                finish(LegacyCopy.text("Could not connect.", "接続できませんでした"))
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + replyTimeoutSeconds) { finish(LegacyCopy.text("No response.", "応答がありません")) }
            body(proxy, finish)
        }
    }

    /// Return false if there is no response.
    func isEngaged() async -> Bool {
        await query { $0.isEngaged(reply: $1) }
    }

    func setUnlockHold(seconds: Int) async {
        _ = await command { $0.setUnlockHold(seconds: Double(seconds), reply: $1) }
    }

    func takeUnlockRequest() async -> Bool {
        await query { $0.takeUnlockRequest(reply: $1) }
    }

    func takeEscapeRequest() async -> Bool {
        await query { $0.takeEscapeRequest(reply: $1) }
    }

    var isHeld: Bool { held }

    func sessionIsLocked(uid: uid_t) async -> Bool {
        await query { $0.sessionIsLocked(uid: uid, reply: $1) }
    }

    private func query(_ body: (ShieldLayer, @escaping @Sendable (Bool) -> Void) -> Void) async -> Bool {
        await withCheckedContinuation { continuation in
            let once = Once()
            let finish: @Sendable (Bool) -> Void = { result in
                if once.claim() { continuation.resume(returning: result) }
            }
            guard let proxy = proxy(onError: { _ in finish(false) }) else {
                finish(false)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + replyTimeoutSeconds) { finish(false) }
            body(proxy, finish)
        }
    }
}

private let unlockTimeoutNanoseconds: UInt64 = 30_000_000_000

@MainActor
final class ProtectionController {
    private(set) var state: ProtectionState = .idle {
        didSet { onChange?(state) }
    }
    private(set) var unlockFailure: String?
    var onChange: ((ProtectionState) -> Void)?
    var onBeforeEngage: (() async -> Void)?

    private let gamma = LayerClient(service: .gamma)
    private let cover = LayerClient(service: .cover)
    private let input = LayerClient(service: .input)
    private var monitor: Task<Void, Never>?
    private var usesCover = true
    private var authentication: LAContext?
    // Give each request a unique number so stale or canceled attempts cannot unlock.
    private var unlockRequest = 0

    init() {
        gamma.onLost = { [weak self] in self?.reportDegraded(LegacyCopy.text("Gamma shielding was lost.", "ガンマが失われました")) }
        cover.onLost = { [weak self] in self?.reportDegraded(LegacyCopy.text("The display cover was lost.", "覆いが失われました")) }
        input.onLost = { [weak self] in self?.handOffToSessionLock(LegacyCopy.text("Input blocking was lost.", "入力の遮断が失われました")) }
    }

    /// Clear the protected state while preserving the remaining layers and the unlock signal.
    private func reportDegraded(_ reason: String) {
        guard monitor != nil else { return }
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
        var lockedAt: ContinuousClock.Instant?
        var lastRequest = ContinuousClock.now
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 50_000_000)
            let confirmed = await sessionConfirmedLocked()
            if Task.isCancelled { return }
            let now = ContinuousClock.now
            if confirmed {
                let since = lockedAt ?? now
                lockedAt = since
                if now - since >= lockSettleDuration, loginWindowIsOpaque {
                    stop()
                    return
                }
            } else if lockedAt != nil, input.isHeld {
                // The user returned before lock confirmation. Treat this as a return from the lock screen and start over with Touch ID.
                watch()
                return
            } else {
                lockedAt = nil
                if now - lastRequest >= lockRetryDuration {
                    requestSessionLock()
                    lastRequest = now
                }
            }
        }
    }

    private func sessionConfirmedLocked() async -> Bool {
        guard !testFlag("hide-lock"), currentSessionIsLocked() == true else { return false }
        let uid = testFlag("foreign-session") ? getuid() + 1 : getuid()
        if input.isHeld { return await input.sessionIsLocked(uid: uid) }
        return consoleSessionIsLocked(uid: uid) == true
    }

    private var loginWindowIsOpaque: Bool {
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return false }
        return windows.contains {
            $0[kCGWindowOwnerName as String] as? String == "loginwindow"
                && $0[kCGWindowLayer as String] as? Int == loginWindowFullScreenLayer
                && $0[kCGWindowAlpha as String] as? Double == 1
        }
    }

    /// After restarting the UI, read the active layers again. Startup leaves protection in place.
    func restoreIfEngaged() {
        let agents = LayerService.agents.map { SMAppService.agent(plistName: $0.plistName) }
        guard agents.allSatisfy({ $0.status == .enabled }) else { return }
        // Keep the launchd registration current if an app update moves the executable.
        agents.forEach { try? $0.register() }
        Task {
            let gammaEngaged = await gamma.isEngaged()
            let coverEngaged = await cover.isEngaged()
            let inputEngaged = await input.isEngaged()
            guard gammaEngaged || coverEngaged || inputEngaged else { return }
            if gammaEngaged { gamma.adopt() }
            if coverEngaged { cover.adopt() }
            if inputEngaged { input.adopt() }
            usesCover = coverEngaged
            state = currentSessionIsLocked() == true ? .interrupted : .shielded
            watch()
        }
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
            return LegacyCopy.text("Allow Tenmaku in Login Items in System Settings.", "システム設定の「ログイン項目」で Tenmaku を許可してください")
        }
        return failure.map { LegacyCopy.text("Could not register: \($0.localizedDescription)", "登録できませんでした: \($0.localizedDescription)") }
    }

    /// Report missing prerequisites that can be checked before changing the displays.
    private func preflightFailure() -> String? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return LegacyCopy.text("Could not determine the display configuration.", "画面の構成を確認できませんでした")
        }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else {
            return LegacyCopy.text("Could not determine the display configuration.", "画面の構成を確認できませんでした")
        }
        if displays.prefix(Int(count)).contains(where: { CGDisplayIsInMirrorSet($0) != 0 }) {
            return LegacyCopy.text("Cannot start while displays are mirrored.", "ミラー表示の間は開始できません")
        }
        for service in LayerService.agents {
            if let reason = registrationFailure(.agent(plistName: service.plistName)) { return reason }
        }
        if let reason = registrationFailure(.daemon(plistName: LayerService.input.plistName)) { return reason }
        guard CGPreflightPostEventAccess() else {
            requestPostEventAccess()
            return LegacyCopy.text("Grant Screen Lock permission.", "「画面ロックの操作」を許可してください")
        }
        return nil
    }

    func start() {
        guard monitor == nil, state == .idle || isFailed else { return }
        if let reason = preflightFailure() {
            state = .failed(reason)
            return
        }
        usesCover = UserDefaults.standard.string(forKey: DefaultsKey.shieldMode) != ShieldMode.gammaOnly.rawValue
        let unlockHoldSeconds = UserDefaults.standard.object(forKey: DefaultsKey.unlockHoldSeconds) as? Int ?? defaultUnlockHoldSeconds
        unlockFailure = nil
        state = .starting
        Task {
            if let reason = await input.preflight() {
                state = .failed(reason)
                return
            }
            // Wait for the startup animation before shielding the physical displays.
            await onBeforeEngage?()
            // Apply the remaining layers after a partial failure. Continue to the input layer so it can receive an unlock request.
            let gammaFailure = await gamma.engage()
            let coverFailure = usesCover ? await cover.engage() : nil
            await input.setUnlockHold(seconds: unlockHoldSeconds)
            let inputFailure = await input.engage()
            if let reason = gammaFailure ?? coverFailure ?? inputFailure {
                state = .failed(reason)
            } else {
                state = .shielded
            }
            watch()
        }
    }

    private func requestUnlock() {
        guard monitor != nil, authentication == nil else { return }
        // Play a sound when it is time to touch Touch ID because the prompt is hidden while shielding is active.
        NSSound(named: "Glass")?.play()
        unlockRequest += 1
        let request = unlockRequest
        let context = LAContext()
        context.localizedFallbackTitle = ""
        authentication = context
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: LegacyCopy.text("End Tenmaku protection", "Tenmaku の保護を解除します")) { [weak self] success, error in
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
        authentication = nil
        if success, !testFlag("biometry-lockout") {
            unlockFailure = nil
            stop()
        } else if testFlag("biometry-lockout") || code == .biometryLockout || code == .biometryNotAvailable || code == .biometryNotEnrolled {
            // Periodic Touch ID lockouts can occur. Leave the session running while the user is away.
            reportUnlockFailure(LegacyCopy.text("Touch ID is unavailable. Hold Esc for 10 seconds to switch to the lock screen.", "Touch ID を使えません。Esc を 10 秒長押しするとロック画面へ移ります"))
        } else {
            reportUnlockFailure(LegacyCopy.text("Authentication failed.", "認証されませんでした"))
        }
    }

    private func expireUnlock(request: Int) {
        guard request == unlockRequest, authentication != nil, monitor != nil else { return }
        cancelAuthentication()
        reportUnlockFailure(LegacyCopy.text("No response.", "応答がありませんでした"))
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

    func stop() {
        monitor?.cancel()
        monitor = nil
        cancelAuthentication()
        Task {
            let inputFailure = await input.release()
            clearStaleButtons()
            let coverFailure = usesCover ? await cover.release() : nil
            let gammaFailure = await gamma.release()
            if let reason = inputFailure ?? coverFailure ?? gammaFailure {
                state = .failed(reason)
            } else {
                state = .idle
            }
        }
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    private func watch() {
        monitor = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                let gammaEngaged = await gamma.isEngaged()
                let coverEngaged = usesCover ? await cover.isEngaged() : gammaEngaged
                let inputEngaged = await input.isEngaged()
                let locked = currentSessionIsLocked() == true && !testFlag("hide-lock")
                // Ignore key presses on the lock screen when checking for an unlock request.
                if await input.takeUnlockRequest(), !locked { requestUnlock() }
                if locked { cancelAuthentication() }
                // This fallback for unavailable Touch ID requires someone to hold Esc.
                if await input.takeEscapeRequest(), locked || unlockFailure != nil {
                    handOffToSessionLock(LegacyCopy.text("Esc was held.", "Esc の長押しを受けました"))
                    return
                }
                if Task.isCancelled { return }
                if !gammaEngaged && !coverEngaged && !inputEngaged {
                    monitor = nil
                    cancelAuthentication()
                    if !isFailed { state = .idle }
                    return
                }
                if !inputEngaged {
                    handOffToSessionLock(LegacyCopy.text("Input blocking was lost.", "入力の遮断が失われました"))
                    return
                }
                if locked {
                    if state != .interrupted { state = .interrupted }
                    continue
                }
                if let reason = degradation(gamma: gammaEngaged, cover: coverEngaged) {
                    if state != .failed(reason) { state = .failed(reason) }
                } else if state != .shielded {
                    state = .shielded
                }
            }
        }
    }

    private func degradation(gamma: Bool, cover: Bool) -> String? {
        if isMirrored { return LegacyCopy.text("Mirrored displays are unsupported.", "ミラー表示には対応していません") }
        if !gamma { return LegacyCopy.text("Gamma shielding was lost.", "ガンマが失われました") }
        if !cover { return LegacyCopy.text("The display cover was lost.", "覆いが失われました") }
        return nil
    }

    private var isMirrored: Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { CGDisplayIsInMirrorSet($0) != 0 }
    }
}
