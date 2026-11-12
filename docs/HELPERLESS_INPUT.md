# Input Control Without the Helper

On 2026-11-10, the user chose to make the privileged helper optional and allow Tenmaku to start the app lock without it after explaining the limitations.

## Architecture and Decisions

- Run unprivileged input control in `TenmakuInput.app` under a dedicated LaunchAgent. A tap in the UI process would stop blocking input when the UI exits. Reusing the helper executable would show the helper's name in permission settings even when the user chose to proceed without it.
- The input layer implements the existing `ShieldLayer` protocol. Both modes share the display layers, Touch ID, state monitoring, and handoff to the system lock.
- Setup includes an optional Install button. Click Next without installing to skip the helper. Tenmaku uses the helper when it is installed and approved. In every other case it runs without the helper. General settings displays the current mode. The mode stays fixed for the duration of the app lock, and installation changes take effect at the next activation.
- When the UI restarts, check both input services for active protections independently of the setting. If more than one input layer remains active, keep them all until authentication succeeds.
- Use separate XPC calls to confirm the app lock and to check for remaining changes or pending input releases. Restore tracking when the tap has failed or an input release is pending. A missing reply leaves the state unknown.

## Input Handling and Limitations

Unprivileged input control uses a session-level event tap. Apple's documentation and SDK restrict HID-level taps to root. Accept synthetic events with a positive source PID and block events with a PID of zero or an invalid PID. Treat each input path as unverified until this distinction has been tested on hardware.

The known limitations come from the [verification record](VERIFICATION.md) and its [summary](VERIFICATION_SUMMARY.md).

- While Secure Event Input is active, Tenmaku cannot block physical keystrokes or detect the unlock hold or the Esc fallback. Tenmaku refuses to start in this state. If Secure Event Input becomes active during the app lock, keep shielding in place and hand off to the macOS lock screen unless Touch ID authentication is in progress. Codex and other clients can use the unlock command in the menu or General settings to request Touch ID authentication. The app lock stays active until authentication succeeds.
- Some Claude clicks have a PID of zero and are indistinguishable from physical input. Tenmaku blocks those clicks. Support for all Codex and Claude actions without the helper is unverified.
- Use hardware acceptance tests to assess system keys, dedicated gestures, pointer blocking at the session level, and actions from each client separately.

Measure each hold from the initial key press and ignore repeats. Esc has its own hold duration, which defaults to 10 seconds. Set it to 1–30 seconds in General settings. The new value takes effect at the next activation. After authentication, continue to discard blocked keys and buttons until they are released. If macOS disables the tap, clear the locked state and keep the remaining shielding in place during handoff to the system lock.

Secure Event Input can suppress a key-up event, leaving input marked as held. After authentication, unprivileged input control reports release success only after confirming that the controls are up. If it cannot confirm release within 2 seconds, keep shielding in place and hand off to the system lock. After confirming the lock screen, clear any remaining tracked controls during release so the user can authenticate with macOS. Keep blocking held input regardless of state tables that synthetic events can change.

## Implementation and Verification Sequence

1. Verify input classification, key holds, and waiting for held controls to be released using tests that leave OS input unchanged.
2. Implement the input agent, its bundle, XPC, and mode selection and restoration.
3. Add optional installation and skip instructions to Setup. Show permissions and limitations for each mode. Show the current mode and its limitations in General settings.
4. Check production and test builds, signing, and the UI. Run tests that darken physical displays separately, after the user confirms.

## References

Use this repository's specification and implementation, the verification records listed above, the macOS SDK headers `CGEvent.h`, `CGEventTypes.h` and `CGEventSource.h`, and Apple's public documentation. Third-party code and samples were excluded.

- Consulted the tap locations, permissions, and event mask for creation on 2026-11-10. [CGEventTapCreate](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:))
- Consulted the event's source process ID field on 2026-11-10. [eventSourceUnixProcessID](https://developer.apple.com/documentation/coregraphics/cgeventfield/eventsourceunixprocessid)

## Verification Results

On 2026-11-10, `swift test` passed 23 unit tests covering input classification, holds, waiting for release, and clearing tracked controls after lock confirmation. The tests create events without installing a tap or posting events.

Verification covered production and test builds, universal app packaging and signing, and the LaunchAgent configuration. A standalone probe that called the input agent's preflight could create a keyboard tap that passed input through. This used the probe process's permissions. The behavior and permission setup of the signed TenmakuInput app with the user's grants remain unverified.

In a preview with no-op lock and permission requests, verification exercised Setup's optional installation and the Next button's skip flow. It also checked each mode's explanation, the permission instructions and status, and the mode indicator and unlock button in General settings.

Hardware verification remains pending for helperless physical input blocking, pointer input, compatibility with actual clients, Touch ID, and maintaining protection during failures and UI restarts. Tests that darken physical displays require prior user confirmation. Unit test and build results do not satisfy these acceptance tests.
