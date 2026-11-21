# Implementation guide

This guide describes the prerequisites, architecture, and sequence for implementing the [specification](SPEC.md). The specification defines the requirements and acceptance criteria. If the documents conflict, follow the specification and report the discrepancy. See the [verification record](VERIFICATION.md) for the supporting observations.

A recommendation is a design proposal that verification has yet to confirm. The implementer may change it and record why.

## Scope of the first release

- The administrator-privileged helper is optional. On 2026-11-10, the user decided to add a configuration without the helper and document its limitations. See [input control without the helper](HELPERLESS_INPUT.md) for user-level input control, unlock, restoration, and known limitations.
- Use gamma alone for concealment during normal operation. Show opaque concealment windows automatically during display reconfiguration and gamma failures.
- Use Touch ID as the only unlock method. Password unlock (A17 to A19) is outside the scope of the first release.
- Support built-in displays and extended external displays. Start the lock only when mirroring is inactive.
- The newest API used determines the minimum supported macOS version. `SMAppService` and `NSXPCConnection.setCodeSigningRequirement` require macOS 13 or later.

## Protection layers and how they can fail

| Layer | Method | What causes loss |
| --- | --- | --- |
| Gamma | Set every entry in the gamma tables of all target displays to zero with `CGSetDisplayTransferByTable`. Read back every 20 ms and rewrite any table that contains a nonzero value. | The owning process exits, another process that changed gamma exits (which also restores gamma on other displays), or the displays reconfigure. |
| Concealment windows | Show a black window at 100% opacity on each display only during a failure. Use the `.screenSaver` level and display the windows in all Spaces and full-screen apps. Ignore mouse events. | The owning process exits. |
| Input | The helper uses `kIOHIDOptionsTypeSeizeDevice` on physical keyboard-only interfaces. The session agent filters pointing events without opening a mouse or trackpad. Exclude devices with a `Transport` of `Virtual` from keyboard acquisition. | The helper exits or the session tap stops filtering. |

While opaque windows are visible, screen captures may show the windows and control may stop.

If gamma briefly resets during reconfiguration, items stacked above the concealment windows become visible. In a resolution change test, the Touch ID confirmation dialog and mouse pointer appeared for about 140 ms. The concealment windows continued to hide the desktop.

## Processes

Separate the gamma and concealment window layers into different processes so one process failure cannot remove both layers. Keep all layers outside the UI process so they can survive a UI crash.

| Process | Runs as | Role |
| --- | --- | --- |
| UI (main app) | User | Starts the lock and shows its state. Authenticates with Touch ID through `LAContext`. Requests a session lock by posting Control-Command-Q with `CGEventPost`. Verifies the session lock with `CGSessionCopyCurrentDictionary`, `IOConsoleUsers`, and the `loginwindow` window. |
| Gamma | User's login session | Owns the gamma layer. |
| Concealment windows | User's login session | Owns the concealment window layer. |
| Helper | root (`SMAppService.daemon`) | Seizes only physical HID interfaces whose primary and advertised usages are keyboard or keypad. Preflight checks access without opening any device. Holds `kIOPMAssertPreventUserIdleDisplaySleep` for as long as it owns the layer. Signals an unlock request when it detects a physical key hold while locked. |
| User-level input control | User (`SMAppService.agent`) | Owns the session event tap in both configurations. With the helper, subscribes only to pointer events and lets the helper track key holds. Without the helper, also subscribes to keyboard events. Passes synthetic input with a positive PID and drops input it cannot distinguish from physical input. Detects key holds, waits for held inputs to be released, and prevents idle sleep. Secure Event Input and some AI operations have limitations. |

- Recommendation. Register gamma and concealment windows as agents with `SMAppService.agent` so they run independently of the UI process.
- Recommendation. Keep lock state in one place outside the UI, including start in progress, locked, unlock in progress, fault, and handoff to the session lock. Have the UI read the state each time it starts (A12 in the specification).
- Bundle the helper as a separate app inside the main app, for example at `Contents/Library/Helpers/TenmakuHelper.app`. In the daemon configuration file in `Contents/Library/LaunchDaemons/`, point `BundleProgram` to the embedded app's executable.
- Connect the processes over XPC. Check signing teams and peer signing identifiers with `setCodeSigningRequirement` and `setConnectionCodeSigningRequirement`. The helper accepts requests to start input blocking from the console user. While input blocking is active, it accepts operations and state queries only from connections matching the initiating user ID and audit session ID.
- The concealment process monitors the Quartz reconfiguration-start notification and gamma XPC disconnection directly. Prepare hidden black windows in advance for known displays and bring them to the front on notification. Track new displays through Quartz and AppKit configuration change notifications. The read-only gamma XPC service accepts connections from the concealment process and the main app. The gamma process reports how long all displays have been at all zero, based on its readings before rewriting the tables. The monitor polls about every 50 ms and shows the windows if replies stop while monitoring is active. To remove the windows, verify that they cover all displays in the same configuration and that every gamma table has remained all zero for 6 seconds. After an unexpected exit, keep the concealment windows in place and leave gamma reapplication to an explicit action.
- If an older LaunchAgent remains registered after an update, the app cannot connect to the read-only gamma monitoring service. Before darkening the displays, the main app checks for a response. If there is no response and it confirms that neither gamma nor the black windows are active, it registers the gamma LaunchAgent again.

## Installation and permissions

| Permission | Applies to | How to request | Verification result |
| --- | --- | --- | --- |
| Background execution | Helper daemon | Call `SMAppService.daemon(...).register()`. The first request waits for approval. Open settings with `SMAppService.openSystemSettingsLoginItems()`. | The daemon started as root after approval. |
| Input Monitoring | Helper app | The main app launches the helper app as the user. The helper calls `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` and exits. | A dialog appeared and the list gained an entry automatically. Calling from the daemon produced no entry. |
| Event posting | Main app | Request event posting and Accessibility. Check Accessibility trust or HID event-posting access when refreshing the grant. | Unverified. The app needs it to request a session lock. |

- The running daemon did not pick up changes to Input Monitoring permission. Recommendation. If a helper starts without permission, have it report the missing permission over XPC and exit so the next connection can relaunch it.
- Check all permissions before starting. If any are missing, report why and leave the displays and input untouched. See [Start, Unlock, and Failure Handling](SPEC.md#start-unlock-and-failure-handling).

Setup registers the optional helper. General settings can remove an approved or pending registration. Serialize changes with lock startup, restoration, and release. Before unregistering an enabled daemon, confirm it has finished releasing any held keys. Switching modes leaves the login agents and macOS privacy decisions in place.

When opening settings or deciding whether to show Setup at launch, read the grants for the selected helper configuration and the main app. A saved Setup completion flag selects the summary only if the required grants are current. While settings are visible, recheck in sequence, including while System Settings is in front. Read each input service's permissions without starting input filtering. Verify operational readiness separately when starting shielding.

## Start and unlock sequence

Configure normal unlock and Esc hold durations independently. Both range from 1 to 30 seconds. Normal unlock defaults to 5 seconds and Esc to 10 seconds. Pass both durations in the preflight and apply XPC requests. The input layer adopts them on apply. Preflight leaves the active settings in place.

Read the custom unlock key in the registration dialog in settings. Convert a virtual key code that both input methods can match to a HID usage ID and save it. Pass the HID usage ID in the preflight and apply XPC requests only if a custom key is enabled and registered. Match the HID usage ID in the helper and the corresponding virtual key code in the event tap. Block and track presses and releases of other physical keys as well.

### Start

Verify the display configuration, Touch ID availability, and input readiness. In the configuration without the helper, start only if Secure Event Input is inactive. Save the current input method so it can be read after the main app exits. Start monitoring for concealment windows first, then apply gamma and block input in that order. If monitoring resumes for an active lock, show the black windows first. Keep visible windows in place if the first response is interrupted. When starting or restoring a lock, verify monitoring, gamma on all displays, and input blocking before reporting the locked state. Prevent normal quit of the main app while any protection remains.

### Unlock

1. While locked, the helper receives the physical key. Because it has seized the device, the key never reaches the desktop.
2. The helper signals the main app. With a fresh `LAContext` for the request, the main app requests `.deviceOwnerAuthenticationWithBiometrics`. Set `localizedFallbackTitle` to an empty string.
3. After verifying successful authentication for the current request, unblock input, stop monitoring and remove the concealment windows, then restore gamma. Verify that monitoring has stopped before restoring ColorSync settings with `CGDisplayRestoreColorSyncSettings`. This keeps black windows from appearing when gamma is restored during a normal unlock.

Without the helper, user-level input control makes the same unlock request. Secure Event Input prevents detection of key holds, so an authorized path such as Codex can also request Touch ID for the current unlock via **Unlock…** in the menu or General settings. Keep protections in place until the user authenticates.

## Handoff to the session lock

Hand off when the helper stops. If Touch ID is unavailable, such as during `biometryLockout`, handoff requires the user to hold Esc for its configured duration (10 seconds by default) after a failed unlock while the app is still locked, or during an interruption caused by a macOS session lock. See [Fallback to macOS Session Lock](SPEC.md#fallback-to-macos-session-lock).

1. Keep the remaining protections in place and send Control-Command-Q.
2. Wait for all three conditions.
   1. The main app sees `CGSSessionScreenIsLocked` report a lock in both `IOConsoleUsers` and the `CGSessionCopyCurrentDictionary` result. The app can read `IOConsoleUsers` as the user, independently of the helper's presence or response.
   2. The `loginwindow` window from `CGWindowListCopyWindowInfo` has opacity 1 and covers the bounds of every display. It was at layer 2001 during verification.
   3. Both conditions hold for 1.5 seconds in the same display configuration.
3. Verify that opaque black windows cover every display. If handoff is interrupted, keep the windows in place until an unlock request arrives.
4. Unblock input, restore gamma, and remove the concealment windows in that order. Recheck that the black windows are visible just before restoring gamma. The main app rechecks the macOS lock state and display configuration immediately before each request to remove a protection. Each concealment process also verifies the lock screen when it receives the request. Once all protections are removed, end the app lock. After the user authenticates with macOS, leave the app unlocked.
5. Keep the remaining protections in place while any verification condition is unmet.

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
- Keyboard seizure for keys other than Space, modifiers, and external keyboards. Session event filtering for scrolling and dragging. Whether an input held across the lock carries over.
- Variation in the lock screen fade-in duration and behavior on external displays.
- Codex and Claude video paths with both displays protected.
- Waking from sleep and HDR.

## Implementation rules

- Follow [Accepted Materials](SPEC.md#accepted-materials) before using third-party code, materials, dependencies, or Apple sample code.
- Exclude existing apps' implementations from your research. See [References and Independent Implementation](SPEC.md#references-and-independent-implementation).
- Use undocumented keys and window metadata only to verify the macOS session lock, as allowed by the specification. Keep concealment in place if you cannot read them.
