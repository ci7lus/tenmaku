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
    public var signingRequirement: String { signingRequirementForBundle(rawValue) }
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

private let sameTeamRequirement = signingTeamRequirement ?? "never"

private func signingRequirementForBundle(_ identifier: String) -> String {
    #"\#(sameTeamRequirement) and identifier "\#(identifier)""#
}

private let appSigningRequirement = signingRequirementForBundle("jp.pronama.tenmaku")
public let gammaHealthMachService = LayerService.gamma.rawValue + ".health"

@objc public protocol GammaHealth {
    /// Return the active state and the system uptime when all gamma values reached zero. A negative value means unconfirmed.
    func sample(reply: @escaping @Sendable (Bool, Double) -> Void)
}

// Keep the displays recoverable in test builds that do not yet implement normal unlock.
public let testAutoReleaseSeconds = 300.0

public let requestInputMonitoringArgument = "--request-input-monitoring"
public let requestSessionInputAccessArgument = "--request-input-access"

public let defaultUnlockHoldSeconds = 5
public let defaultEscapeHoldSeconds = 10

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
    /// Input layers also check the hold durations and apply the same settings passed to engage.
    func preflight(unlockHoldSeconds: Double, escapeHoldSeconds: Double, reply: @escaping @Sendable (NSError?) -> Void)
    /// Return nil if application was confirmed, or a LayerFailure error otherwise.
    func engage(unlockHoldSeconds: Double, escapeHoldSeconds: Double, reply: @escaping @Sendable (NSError?) -> Void)
    /// Pass true for afterSessionLock only after confirming the lock screen is present.
    func release(afterSessionLock: Bool, reply: @escaping @Sendable (NSError?) -> Void)
    func isEngaged(reply: @escaping @Sendable (Bool) -> Void)
    /// Report an unlock request received since the last call. Only the input layer returns true.
    func takeUnlockRequest(reply: @escaping @Sendable (Bool) -> Void)
    /// Report whether Esc has been held long enough since the last call. Only the input layer returns true.
    func takeEscapeRequest(reply: @escaping @Sendable (Bool) -> Void)
    /// Report whether changes remain in place or input release is pending, even when protection cannot be confirmed.
    func hasProtection(reply: @escaping @Sendable (Bool) -> Void)
}

@objc public protocol InputControl: ShieldLayer {
    /// Read this service's privacy grants without installing a tap or opening a device.
    func hasInputPermissions(reply: @escaping @Sendable (Bool) -> Void)
    // Only the system daemon can report whether its keyboard interfaces are free across sessions.
    @objc optional func canUnregisterHelper(reply: @escaping @Sendable (Bool) -> Void)
    // Distinct selectors prevent a 0.1.x helper from seizing a pointer during an update.
    func preflight(unlockHoldSeconds: Double, escapeHoldSeconds: Double, unlockKeyUsage: Int, pointerOnly: Bool, reply: @escaping @Sendable (NSError?) -> Void)
    func engage(unlockHoldSeconds: Double, escapeHoldSeconds: Double, unlockKeyUsage: Int, pointerOnly: Bool, reply: @escaping @Sendable (NSError?) -> Void)
    func isEngaged(pointerOnly: Bool, reply: @escaping @Sendable (Bool) -> Void)
    func preflight(unlockHoldSeconds: Double, escapeHoldSeconds: Double, unlockKeyUsage: Int, reply: @escaping @Sendable (NSError?) -> Void)
    func engage(unlockHoldSeconds: Double, escapeHoldSeconds: Double, unlockKeyUsage: Int, reply: @escaping @Sendable (NSError?) -> Void)
}

@objc public protocol CoverControl: ShieldLayer {
    /// If protection is already active, resume gamma monitoring with the black windows visible.
    func restoreCover(reply: @escaping @Sendable (NSError?) -> Void)
    /// Keep the black windows visible until release is requested and report whether they cover all current displays.
    func holdForHandoff(reply: @escaping @Sendable (Bool) -> Void)
}

public final class LayerListener: NSObject, NSXPCListenerDelegate {
    private let listener: NSXPCListener
    private let interface: NSXPCInterface
    private let exportedObject: AnyObject

    public convenience init(service: LayerService, layer: ShieldLayer) {
        self.init(machService: service.rawValue, interface: NSXPCInterface(with: ShieldLayer.self),
                  object: layer as AnyObject, clientRequirement: appSigningRequirement)
    }

    public convenience init(cover: CoverControl) {
        self.init(machService: LayerService.cover.rawValue, interface: NSXPCInterface(with: CoverControl.self),
                  object: cover as AnyObject, clientRequirement: appSigningRequirement)
    }

    public convenience init(service: LayerService, input: InputControl) {
        self.init(machService: service.rawValue, interface: NSXPCInterface(with: InputControl.self),
                  object: input as AnyObject, clientRequirement: appSigningRequirement)
    }

    public convenience init(gammaHealth: GammaHealth) {
        let cover = LayerService.cover.signingRequirement
        self.init(machService: gammaHealthMachService, interface: NSXPCInterface(with: GammaHealth.self),
                  object: gammaHealth as AnyObject, clientRequirement: "(\(cover)) or (\(appSigningRequirement))")
    }

    private init(machService: String, interface: NSXPCInterface, object: AnyObject, clientRequirement: String) {
        listener = NSXPCListener(machServiceName: machService)
        self.interface = interface
        self.exportedObject = object
        super.init()
        listener.delegate = self
        listener.setConnectionCodeSigningRequirement(clientRequirement)
    }

    public func resume() {
        listener.resume()
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = interface
        connection.exportedObject = exportedObject
        connection.resume()
        return true
    }
}
