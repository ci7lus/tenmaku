import TenmakuShared

struct UnlockKeyPreference {
    let savedKey: UnlockKey
    let customEnabled: Bool?

    var isCustom: Bool { customEnabled ?? (savedKey != .any) }
    var effectiveKey: UnlockKey { isCustom ? savedKey : .any }
}
