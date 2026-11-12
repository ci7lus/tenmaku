import Foundation

public enum GammaCondition {
    case idle
    case unstable
    case black(since: TimeInterval)
}

public enum EmergencyCoverState {
    case starting(deadline: TimeInterval)
    case monitoring(blackSince: TimeInterval)
    case covering(verifiedSince: TimeInterval?)
    case handoff

    public var needsCover: Bool {
        switch self {
        case .covering, .handoff: true
        case .starting, .monitoring: false
        }
    }

    public var canAbortArming: Bool {
        if case .starting = self { return true }
        return false
    }

    public var isReady: Bool {
        if case .monitoring = self { return true }
        return false
    }

    public mutating func requireCover() {
        if case .handoff = self { return }
        self = .covering(verifiedSince: nil)
    }

    public mutating func observe(_ gamma: GammaCondition, allCovered: Bool, at now: TimeInterval) {
        if case .handoff = self { return }
        if case .starting(let deadline) = self, case .idle = gamma, now < deadline { return }
        guard case .black(let blackSince) = gamma else {
            requireCover()
            return
        }
        if case .monitoring(let previousBlackSince) = self, previousBlackSince != blackSince {
            requireCover()
            return
        }
        guard case .covering(let verifiedSince) = self else {
            self = .monitoring(blackSince: blackSince)
            return
        }
        guard allCovered else {
            requireCover()
            return
        }
        let since = verifiedSince ?? now
        if now - max(since, blackSince) >= 6 {
            self = .monitoring(blackSince: blackSince)
        } else {
            self = .covering(verifiedSince: since)
        }
    }
}

public struct GammaStability {
    public private(set) var blackSince: TimeInterval?
    private var lastSample: TimeInterval?

    public init() {}

    public mutating func record(allBlack: Bool, at now: TimeInterval) {
        if !allBlack {
            blackSince = nil
        } else if blackSince == nil || !isCurrent(at: now) {
            blackSince = now
        }
        lastSample = now
    }

    public func isCurrent(at now: TimeInterval) -> Bool {
        lastSample.map { now - $0 <= 0.25 } ?? false
    }
}
