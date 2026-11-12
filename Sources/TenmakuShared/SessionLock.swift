import CoreGraphics
import Foundation
import IOKit

public func onlineDisplayIDs() -> Set<CGDirectDisplayID>? {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &ids, &count) == .success, count > 0, count <= ids.count else { return nil }
    return Set(ids.prefix(Int(count)))
}

// This key is undocumented. If a future macOS version makes it unreadable, keep shielding in place because the lock cannot be confirmed.
private let screenIsLockedKey = "CGSSessionScreenIsLocked"

/// Read the lock state of the user's console session from `IOConsoleUsers`. Return nil if the session is missing.
public func consoleSessionIsLocked(uid: uid_t) -> Bool? {
    let root = IORegistryGetRootEntry(kIOMainPortDefault)
    defer { IOObjectRelease(root) }
    guard let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue() as? [[String: Any]] else { return nil }
    let session = users.first {
        ($0["kCGSSessionUserIDKey"] as? NSNumber)?.uint32Value == uid && $0["kCGSSessionOnConsoleKey"] as? Bool == true
    }
    return session.map { $0[screenIsLockedKey] as? Bool ?? false }
}

/// Read whether the current process's session is locked. Return nil if the state cannot be read.
public func currentSessionIsLocked() -> Bool? {
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
    return session[screenIsLockedKey] as? Bool ?? false
}

public func sessionLockIsConfirmed() -> Bool {
    currentSessionIsLocked() == true && consoleSessionIsLocked(uid: getuid()) == true
}

public struct LockedScreenLayout: Equatable, Sendable {
    private let displays: [CGDirectDisplayID: CGRect]

    public static func confirmed() -> Self? {
        guard sessionLockIsConfirmed(), let displays = onlineDisplayBounds(),
              let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]],
              coversDisplays(windows: windows, displays: Array(displays.values)),
              onlineDisplayBounds() == displays, sessionLockIsConfirmed() else { return nil }
        return Self(displays: displays)
    }

    static func coversDisplays(windows: [[String: Any]], displays: [CGRect]) -> Bool {
        let lockWindows = windows.compactMap { window -> CGRect? in
            // Testing identified the loginwindow window at layer 2001. Keep shielding in place until all criteria are met.
            guard window[kCGWindowOwnerName as String] as? String == "loginwindow",
                  window[kCGWindowLayer as String] as? Int == 2001,
                  window[kCGWindowAlpha as String] as? Double == 1,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  validBounds(rect) else { return nil }
            return rect
        }
        return !displays.isEmpty && displays.allSatisfy { display in
            validBounds(display) && lockWindows.contains { $0.contains(display) }
        }
    }

    private static func onlineDisplayBounds() -> [CGDirectDisplayID: CGRect]? {
        guard let ids = onlineDisplayIDs() else { return nil }
        var bounds: [CGDirectDisplayID: CGRect] = [:]
        for id in ids {
            let rect = CGDisplayBounds(id)
            guard validBounds(rect) else { return nil }
            bounds[id] = rect
        }
        return bounds
    }

    private static func validBounds(_ rect: CGRect) -> Bool {
        !rect.isEmpty && !rect.isInfinite && [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy(\.isFinite)
    }
}
