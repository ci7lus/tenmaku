# Implementation guide

This guide describes the prerequisites, architecture, and sequence for implementing the [specification](SPEC.md). The specification defines the requirements and acceptance criteria. If the documents conflict, follow the specification and report the discrepancy. See the [verification record](VERIFICATION.md) for the supporting observations.

A recommendation is a design proposal that verification has yet to confirm. The implementer may change it and record why.

## Scope of the first release

- Use the helper in the first release. Defer the configuration without the helper to a later release until unlock signaling and session lock verification are defined. See [Configurations and limitations](SPEC.md#configurations-and-limitations).
- Provide settings for gamma with concealment windows and gamma alone. Default to using both.
- Use Touch ID as the only unlock method. Password unlock (A17 to A19) is outside the scope of the first release.
- Support built-in displays and extended external displays. Start the lock only when mirroring is inactive.
- The newest API used determines the minimum supported macOS version. `SMAppService` and `NSXPCConnection.setCodeSigningRequirement` require macOS 13 or later.

## Protection layers and how they can fail

| Layer | Method | What causes loss |
| --- | --- | --- |
| Gamma | Set every entry in the gamma tables of all target displays to zero with `CGSetDisplayTransferByTable`. Read back every 20 ms and rewrite any table that contains a nonzero value. | The owning process exits, another process that changed gamma exits (which also restores gamma on other displays), or the displays reconfigure. |
| Concealment windows | Show a full-display black window on each display. Set `sharingType = .none`, opacity to 99.9% (`isOpaque = false`), `ignoresMouseEvents = true`, the level to `.screenSaver`, and the collection behaviors to `.canJoinAllSpaces` and `.fullScreenAuxiliary`. | The owning process exits. |
| Input | The helper seizes physical keyboards and pointing devices with `kIOHIDOptionsTypeSeizeDevice`. Use the registry ID to identify devices that match several criteria as the same device. Exclude devices with a `Transport` of `Virtual`. | The helper exits. |

Keep concealment windows nonopaque. With `isOpaque = true`, windows under the concealment windows disappeared from full-display captures.

If gamma briefly resets during reconfiguration, items stacked above the concealment windows become visible. In a resolution change test, the Touch ID confirmation dialog and mouse pointer appeared for about 140 ms. The concealment windows continued to hide the desktop.

## Processes

Separate the gamma and concealment window layers into different processes so one process failure cannot remove both layers. Keep all layers outside the UI process so they can survive a UI crash.

| Process | Runs as | Role |
| --- | --- | --- |
| UI (main app) | User | Starts the lock and shows its state. Authenticates with Touch ID through `LAContext`. Requests a session lock by posting Control-Command-Q with `CGEventPost`. Checks `CGSessionCopyCurrentDictionary` and the `loginwindow` window to help verify the lock. |
| Gamma | User's login session | Owns the gamma layer. |
| Concealment windows | User's login session | Owns the concealment window layer. |
| Helper | root (`SMAppService.daemon`) | Owns the input layer. Signals an unlock request when it receives a physical key while locked. Reads `CGSSessionScreenIsLocked` in `IOConsoleUsers`. |

- Recommendation. Register gamma and concealment windows as agents with `SMAppService.agent` so they run independently of the UI process.
- Recommendation. Keep lock state in one place outside the UI, including start in progress, locked, unlock in progress, fault, and handoff to the session lock. Have the UI read the state each time it starts (A12 in the specification).
- Bundle the helper as a separate app inside the main app, for example at `Contents/Library/Helpers/TenmakuHelper.app`. In the daemon configuration file in `Contents/Library/LaunchDaemons/`, point `BundleProgram` to the embedded app's executable.
- Connect the processes over XPC. Accept signatures only from the same team using `setCodeSigningRequirement` and `setConnectionCodeSigningRequirement`.

## Installation and permissions

| Permission | Applies to | How to request | Verification result |
| --- | --- | --- | --- |
| Background execution | Helper daemon | Call `SMAppService.daemon(...).register()`. The first request waits for approval. Open settings with `SMAppService.openSystemSettingsLoginItems()`. | The daemon started as root after approval. |
| Input Monitoring | Helper app | The main app launches the helper app as the user. The helper calls `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` and exits. | A dialog appeared and the list gained an entry automatically. Calling from the daemon produced no entry. |
| Event posting | Main app | Use `CGPreflightPostEventAccess` and `CGRequestPostEventAccess`. | Unverified. The app needs it to request a session lock. |

- The running daemon did not pick up changes to Input Monitoring permission. Recommendation. If a helper starts without permission, have it report the missing permission over XPC and exit so the next connection can relaunch it.
- Check all permissions before starting. If any are missing, report why and leave the displays and input untouched. See [Start, Unlock, and Failure Handling](SPEC.md#start-unlock-and-failure-handling).

## Start and unlock sequence

### Start

Check the display configuration and stop if mirroring is active. Then apply gamma, show concealment windows if enabled, and seize input devices in that order. Verify that all layers are in place before reporting the locked state.

### Unlock

1. While locked, the helper receives the physical key. Because it has seized the device, the key never reaches the desktop.
2. The helper signals the main app. With a fresh `LAContext` for the request, the main app requests `.deviceOwnerAuthenticationWithBiometrics`. Set `localizedFallbackTitle` to an empty string.
3. After verifying successful authentication for the current request, unblock input, remove the concealment windows, then restore gamma to ColorSync settings with `CGDisplayRestoreColorSyncSettings`.

## Handoff to the session lock

Hand off when the helper stops. If Touch ID is unavailable, such as during `biometryLockout`, handoff requires the user to hold Esc for 10 seconds after a failed unlock while the app is still locked, or during an interruption caused by a macOS session lock. See [Fallback to macOS Session Lock](SPEC.md#fallback-to-macos-session-lock).

1. Keep the remaining protections in place and send Control-Command-Q.
2. Wait for all three conditions.
   1. Both `CGSSessionScreenIsLocked` values report a lock. The helper reads the value in `IOConsoleUsers` and the main app reads it in `CGSessionCopyCurrentDictionary`. If the helper has stopped, the main app reads `IOConsoleUsers` directly. Verification showed that it can do so as the user.
   2. The full-display `loginwindow` window found through `CGWindowListCopyWindowInfo` has opacity 1. It was at layer 2001 during verification.
   3. At least 1.5 seconds have passed since condition 1 was met.
3. Once all three conditions hold, remove gamma and the concealment windows and end the app lock. After the user authenticates with macOS, leave the app unlocked.
4. Keep the protections in place while any condition is unmet.

The lock screen became visible after gamma was restored while the session was locked. Whether the app can read the `loginwindow` window owner's name and opacity without Screen Recording permission remains unverified.

## Implementation order and tests

At the end of each stage, run the corresponding acceptance tests from the specification before continuing. Observe physical displays under the conditions in [Acceptance Tests](SPEC.md#acceptance-tests). Record at about 120 frames per real-time second or faster and use a known flash to check detection on each trial.

| Stage | Implementation | Test |
| --- | --- | --- |
| 1 | Project skeleton. Write rerunnable scripts for bundle layout, signing with Developer ID and Hardened Runtime, and notarization. | Get the app notarized and check it with `spctl`. |
| 2 | Gamma and concealment window processes, start and normal shutdown, and restoration to ColorSync settings. | A06, A13 |
| 3 | Helper registration, Input Monitoring permission, device seizure, and XPC. | A07, A11 |
| 4 | Unlock, including the helper signal and Touch ID. | A09, A10 |
| 5 | Failures and reconfiguration. Test UI exit, exit of each layer's process, display connection and disconnection, and switching to mirroring. | A08, A12, A14 |
| 6 | Handoff to the session lock and return after the user unlocks the session. | A15, A16 |
| 7 | Capture and control with real clients. | A01 to A05 |

## Questions to check early

These unverified points could change the design.

- Whether the notarized distribution build follows the same daemon registration and Input Monitoring approval steps as the verification build.
- Device seizure for keys other than Space, modifiers, scrolling, dragging, and external keyboards. Whether an input held across the lock carries over.
- Variation in the lock screen fade-in duration and behavior on external displays.
- Codex and Claude video paths with both displays protected.
- Waking from sleep and HDR.

## Implementation rules

- Follow [Accepted Materials](SPEC.md#accepted-materials) before using third-party code, materials, dependencies, or Apple sample code.
- Exclude existing apps' implementations from your research. See [References and Independent Implementation](SPEC.md#references-and-independent-implementation).
- Use undocumented keys and window metadata only to verify the macOS session lock, as allowed by the specification. Keep concealment in place if you cannot read them.
