import Foundation
import Security

public enum LayerService: String, Sendable {
    case gamma = "jp.pronama.tenmaku.gamma"
    case cover = "jp.pronama.tenmaku.cover"
    case input = "jp.pronama.tenmaku.helper"
    case sessionInput = "jp.pronama.tenmaku.input"

    public static let agents: [LayerService] = [.gamma, .cover]

    public var plistName: String { rawValue + ".plist" }

    public var isPrivileged: Bool { self == .input }
}

private let signingTeamRequirement: String? = {
    var process: SecCode?
    var code: SecStaticCode?
    var information: CFDictionary?
    guard SecCodeCopySelf([], &process) == errSecSuccess, let process,
          SecCodeCopyStaticCode(process, [], &code) == errSecSuccess, let code,
          SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
          let team = (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String,
          team.wholeMatch(of: /[A-Z0-9]{10}/) != nil else { return nil }
    let expression = #"anchor apple generic and certificate leaf[subject.OU] = "\#(team)""#
    var requirement: SecRequirement?
    // Confirm that the team read from disk matches the running process.
    guard SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess,
          let requirement,
          SecCodeCheckValidity(process, [], requirement) == errSecSuccess else { return nil }
    return expression
}()

public let sameTeamRequirement = signingTeamRequirement ?? "never"

// Keep the displays recoverable in test builds that do not yet implement normal unlock.
public let testAutoReleaseSeconds = 300.0

public let requestInputMonitoringArgument = "--request-input-monitoring"
public let requestSessionInputAccessArgument = "--request-input-access"

public let defaultUnlockHoldSeconds = 5

private let idleExitInterval = DispatchTimeInterval.seconds(30)
nonisolated(unsafe) private var idleExitTimer: DispatchSourceTimer?

/// Exit when shielding is inactive so launchd starts the latest executable on the next connection.
public func exitWhenIdle(_ isIdle: @escaping @Sendable () -> Bool) {
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + idleExitInterval, repeating: idleExitInterval)
    timer.setEventHandler { if isIdle() { exit(0) } }
    timer.resume()
    idleExitTimer = timer
}

@objc public protocol ShieldLayer {
    /// Check whether this layer can be applied before changing the displays or input.
    func preflight(reply: @escaping @Sendable (String?) -> Void)
    /// Return nil if application was confirmed, or an error message if it failed.
    func engage(reply: @escaping @Sendable (String?) -> Void)
    /// Pass true for afterSessionLock only after confirming the lock screen is present.
    func release(afterSessionLock: Bool, reply: @escaping @Sendable (String?) -> Void)
    func isEngaged(reply: @escaping @Sendable (Bool) -> Void)
    /// Set the key hold duration for unlock. Only the input layer uses this value.
    func setUnlockHold(seconds: Double, reply: @escaping @Sendable (String?) -> Void)
    /// Report an unlock request received since the last call. Only the input layer returns true.
    func takeUnlockRequest(reply: @escaping @Sendable (Bool) -> Void)
    /// Report whether Esc has been held long enough since the last call. Only the input layer returns true.
    func takeEscapeRequest(reply: @escaping @Sendable (Bool) -> Void)
    /// Report whether changes remain in place or input release is pending, even when protection cannot be confirmed.
    func hasProtection(reply: @escaping @Sendable (Bool) -> Void)
}

public final class LayerListener: NSObject, NSXPCListenerDelegate {
    private let listener: NSXPCListener
    private let layer: ShieldLayer

    public init(service: LayerService, layer: ShieldLayer) {
        listener = NSXPCListener(machServiceName: service.rawValue)
        self.layer = layer
        super.init()
        listener.delegate = self
        listener.setConnectionCodeSigningRequirement(sameTeamRequirement)
    }

    public func resume() {
        listener.resume()
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: ShieldLayer.self)
        connection.exportedObject = layer
        connection.resume()
        return true
    }
}
