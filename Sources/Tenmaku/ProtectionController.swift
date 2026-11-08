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
    case failed(String)
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
            body(proxy, finish)
        }
    }

    /// Return false if there is no response.
    func isEngaged() async -> Bool {
        await query { $0.isEngaged(reply: $1) }
    }

    func takeUnlockRequest() async -> Bool {
        await query { $0.takeUnlockRequest(reply: $1) }
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

    private let gamma = LayerClient(service: .gamma)
    private let cover = LayerClient(service: .cover)
    private let input = LayerClient(service: .input)
    private var monitor: Task<Void, Never>?
    private var usesCover = true
    private var authentication: LAContext?
    // Give each request a unique number so stale or canceled attempts cannot unlock.
    private var unlockRequest = 0

    init() {
        gamma.onLost = { [weak self] in self?.layerLost(LegacyCopy.text("Gamma shielding was lost.", "ガンマが失われました")) }
        cover.onLost = { [weak self] in self?.layerLost(LegacyCopy.text("The display cover was lost.", "覆いが失われました")) }
        input.onLost = { [weak self] in self?.layerLost(LegacyCopy.text("Input blocking was lost.", "入力の遮断が失われました"), locksSession: true) }
    }

    private func layerLost(_ reason: String, locksSession: Bool = false) {
        guard state == .shielded || state == .starting else { return }
        monitor?.cancel()
        monitor = nil
        cancelAuthentication()
        state = .failed(reason)
        if locksSession { requestSessionLock() }
    }

    /// Send Control-Command-Q. Stage 6 will wait for the lock to take effect before releasing the layers.
    private func requestSessionLock() {
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
        guard state == .idle || isFailed else { return }
        if let reason = preflightFailure() {
            state = .failed(reason)
            return
        }
        usesCover = UserDefaults.standard.string(forKey: DefaultsKey.shieldMode) != ShieldMode.gammaOnly.rawValue
        unlockFailure = nil
        state = .starting
        Task {
            if let reason = await input.preflight() {
                state = .failed(reason)
                return
            }
            guard state == .starting else { return }
            if let reason = await gamma.engage() {
                state = .failed(reason)
                return
            }
            guard state == .starting else { return }
            if usesCover, let reason = await cover.engage() {
                state = .failed(reason)
                return
            }
            guard state == .starting else { return }
            if let reason = await input.engage() {
                state = .failed(reason)
                return
            }
            guard state == .starting else { return }
            state = .shielded
            watch()
        }
    }

    private func requestUnlock() {
        guard state == .shielded, authentication == nil else { return }
        unlockRequest += 1
        let request = unlockRequest
        let context = LAContext()
        context.localizedFallbackTitle = ""
        authentication = context
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: LegacyCopy.text("End Tenmaku protection", "Tenmaku の保護を解除します")) { [weak self] success, error in
            let code = (error as? LAError)?.code
            Task { @MainActor in self?.finishUnlock(request: request, success: success, code: code) }
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: unlockTimeoutNanoseconds)
            self?.expireUnlock(request: request)
        }
    }

    private func finishUnlock(request: Int, success: Bool, code: LAError.Code?) {
        guard request == unlockRequest, authentication != nil, state == .shielded else { return }
        authentication = nil
        if success {
            unlockFailure = nil
            stop()
        } else if code == .biometryLockout || code == .biometryNotAvailable || code == .biometryNotEnrolled {
            // Stage 6 will wait for the lock to take effect before releasing the layers.
            layerLost(LegacyCopy.text("Touch ID is unavailable.", "Touch ID を使えません"), locksSession: true)
        } else {
            reportUnlockFailure(LegacyCopy.text("Authentication failed.", "認証されませんでした"))
        }
    }

    private func expireUnlock(request: Int) {
        guard request == unlockRequest, authentication != nil, state == .shielded else { return }
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
                if Task.isCancelled { return }
                if !gammaEngaged && !coverEngaged && !inputEngaged {
                    state = .idle
                    return
                }
                if await input.takeUnlockRequest() { requestUnlock() }
                if !inputEngaged && gammaEngaged && coverEngaged {
                    layerLost(LegacyCopy.text("Input blocking was lost.", "入力の遮断が失われました"), locksSession: true)
                    return
                }
                if !gammaEngaged || !coverEngaged {
                    state = .failed(gammaEngaged ? LegacyCopy.text("The display cover was lost.", "覆いが失われました") : LegacyCopy.text("Gamma shielding was lost.", "ガンマが失われました"))
                    return
                }
            }
        }
    }
}
