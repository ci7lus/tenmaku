public struct InputHoldDurations: Equatable, Sendable {
    public static let standard = InputHoldDurations()

    public let unlockSeconds: Double
    public let escapeSeconds: Double

    private init() {
        unlockSeconds = Double(defaultUnlockHoldSeconds)
        escapeSeconds = Double(defaultEscapeHoldSeconds)
    }

    public init?(unlockSeconds: Double, escapeSeconds: Double) {
        guard (1...30).contains(unlockSeconds), (1...30).contains(escapeSeconds) else { return nil }
        self.unlockSeconds = unlockSeconds
        self.escapeSeconds = escapeSeconds
    }

    public func seconds(isEscape: Bool) -> Double {
        isEscape ? escapeSeconds : unlockSeconds
    }
}
