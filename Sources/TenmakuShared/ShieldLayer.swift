import Foundation
import Security

public enum LayerService: String, Sendable {
    case gamma = "jp.pronama.tenmaku.gamma"
    case cover = "jp.pronama.tenmaku.cover"
    case input = "jp.pronama.tenmaku.helper"

    public static let agents: [LayerService] = [.gamma, .cover]

    public var plistName: String { rawValue + ".plist" }
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
public let testAutoReleaseSeconds = 60.0

public let requestInputMonitoringArgument = "--request-input-monitoring"

@objc public protocol ShieldLayer {
    /// Check whether this layer can be applied before changing the displays or input.
    func preflight(reply: @escaping @Sendable (String?) -> Void)
    /// Return nil if application was confirmed, or an error message if it failed.
    func engage(reply: @escaping @Sendable (String?) -> Void)
    func release(reply: @escaping @Sendable (String?) -> Void)
    func isEngaged(reply: @escaping @Sendable (Bool) -> Void)
    /// Report an unlock request received since the last call. Only the input layer returns true.
    func takeUnlockRequest(reply: @escaping @Sendable (Bool) -> Void)
    /// Report whether Esc has been held long enough since the last call. Only the input layer returns true.
    func takeEscapeRequest(reply: @escaping @Sendable (Bool) -> Void)
    /// Check whether the target user's session is locked via `IOConsoleUsers`. Only the input layer returns true.
    func sessionIsLocked(uid: UInt32, reply: @escaping @Sendable (Bool) -> Void)
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
