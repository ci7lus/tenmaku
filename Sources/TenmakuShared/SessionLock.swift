import CoreGraphics
import Foundation
import IOKit

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
