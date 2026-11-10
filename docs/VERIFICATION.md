# Verification Record

This record supports the [verification summary](VERIFICATION_SUMMARY.md) with methods, measurements, and limits for each property tested. See the summary for the test environment. The one-off test programs were written independently using only public APIs and are separate from the product code.

## Observing physical displays

A visual check alone cannot rule out a brief exposure. We recorded the physical displays with the iPhone's built-in slow-motion mode and first checked that it could capture brief flashes.

- For each of the two displays, we showed a full-screen red flash for 1, 2, or 4 frames, with five repeats at each duration. We randomized the order of the 30 flashes. For each video frame, we averaged the color in a 9-row by 16-column grid and calculated red − (green + blue) / 2 for the region of each display. We used the ratio of the signal intensities to discard reflections from the other display.
- The exported video received over AirDrop was a 30 fps file. During the main portion of the recording it contained about 120 frames per second of real time, or about 8.3 ms per frame.
- The method detected all 30 flashes, and the detection order matched the planned order.

| Display | Flash duration | Detected | Recorded intensity | Peak noise between flashes |
| --- | --- | --- | --- | --- |
| Built-in | 1 frame (8.3 ms) | 5/5 | 74–86 | 4.2 |
| Built-in | 2 or 4 frames | 10/10 | 42–188 | Same as above |
| External | 1 frame (16.7 ms) | 5/5 | 135–251 | 3.8 |
| External | 2 or 4 frames | 10/10 | About 252 | Same as above |

- On the built-in display, the number of frames in a flash did not correspond to the recorded intensity. The frame count in the test program does not give the actual time the display emitted light.
- In the same test using Continuity Camera, which ran at 30 fps, the camera missed 1 of 9 flashes lasting 4 frames (33 ms) on the built-in display. We excluded this method from our assessments.
- We did not measure how well the method detects brief exposures of only part of a display.

The physical display assessments below use this recording method and the user's visual observations.

## Gamma

### Conditions that restore gamma

| Condition | Result |
| --- | --- |
| The owning process exits normally without calling the restore routine | All 20 readbacks starting immediately after exit showed the original values |
| The owning process is force-quit | The original values returned, and red was visible |
| Two processes write the same all-zero table, then one is force-quit | The original values returned even while the other process stayed alive |
| Another process writes the gamma table for the **external display** and exits normally | The **built-in display** also returned to its original gamma values immediately after the process exited. The video captured red |
| Another process reads the gamma table and exits without writing | No change |
| The external display is disconnected and reconnected | The remaining display also returned to its original gamma values |

The results suggest that WindowServer restores the original color settings on all displays when any process that wrote gamma exits. Reapplying gamma after detecting its restoration still leaves a brief exposure, regardless of how fast the write is.

### Effect on capture

With all gamma values set to zero, ScreenCaptureKit, `screencapture`, Claude, and Codex captured the same content as before the display was obscured.

## Overlays that stay out of screen capture

### Physical displays and capture

We displayed a full-screen window with `NSWindow.sharingType = .none` and compared the physical display with each capture path.

| Check | Opaque overlay (100%) | Overlay at 99.9% opacity |
| --- | --- | --- |
| Physical display | The overlay was visible | The overlay was visible. The user could not see through it |
| `screencapture` (whole display) | The result showed **only the wallpaper**. The overlay, windows, menu bar, and Dock were absent | The overlay was absent. The difference from an image taken without the overlay was 0.1 |
| Claude Computer Use (whole display) | The result showed only the wallpaper | The result omitted the overlay and showed the windows behind it, the menu bar, and the Dock |
| Codex (per-window capture) | Capturing the overlay window returned a white image. Codex could capture the windows behind it | Codex could capture the windows behind it |

- We captured 7 images between 0.3 and 25 seconds after showing the opaque overlay. All 7 contained only the wallpaper in the area of the window. This suggests that compositing excludes windows fully hidden behind an opaque window.
- With a 99.9% overlay, only 0.1% of the content behind it passes through. The calculated contribution even from a white pixel is below one step at 8-bit color depth.
- The mouse pointer appeared above the overlay.

### Interaction through the overlay

We placed a test window behind a 99.9% overlay with `ignoresMouseEvents = true`.

- Claude delivered 6 key events and a click, entered text in the field, and activated the button. On several occasions, the first click reached the window as a mouse-down event without activating the button. The cause is unknown.
- Codex changed the field value and activated the button without delivering key or mouse events to the window. This suggests Codex used accessibility actions. In another test, Codex key events reached the window.
- An overlay with `ignoresMouseEvents` also lets physical clicks through. The design relies on the helper to block physical input.

### Conditions that remove this layer

With only the overlay in use, force-quitting its owning process exposed the content. The content was still visible when we reapplied gamma immediately after detecting the exit.

## Combining gamma and an overlay

We put gamma and the overlay in separate processes, displayed a full-screen red test window on the built-in display, and triggered faults. A separate coordinator read gamma without writing it. Every 20 ms, it logged gamma and whether the overlay was present.

| Fault | Gamma | Overlay | Red in video | Visual observation |
| --- | --- | --- | --- | --- |
| Another process writes gamma and exits normally | Restored. The owning process reapplied gamma about 9 ms later | Present | None | None |
| The gamma process is force-quit | Stayed at the original values for about 4 seconds | Present | None | None |
| The overlay process is force-quit | Stayed all zero | Disappeared | None | None |

Red in the video peaked at 18, below the detection threshold of 20. Full-screen red registers at about 180.

### Disconnecting and reconnecting the external display

The gamma process kept all gamma values at zero on every display. The overlay process showed an overlay as soon as a display appeared. We displayed a red test window on both displays, disconnected the external display cable, and reconnected it about 12 seconds later.

| Time | Observation |
| --- | --- |
| After disconnecting | The built-in display's gamma returned to its original values about 5.2 seconds after the removal notification. The gamma process reapplied the table about 0.06 seconds later. The overlay stayed in place throughout |
| Immediately after reconnecting | The overlay appeared on the external display about 0.25 seconds after the reconfiguration start notification and about 0.13 seconds after the addition notification |
| After reconnecting | Gamma returned to its original values on both displays about 5.2 seconds after the addition notification. The gamma process reapplied the tables about 0.05–0.07 seconds later. Both displays had overlays |

- Red in the video peaked at 13.2 on the external display and 5.4 on the built-in display, below the threshold of 20. The user also reported that the displays stayed black.
- We did not record the external display's gamma for about 0.13 seconds after reconnecting, before the overlay appeared. The lack of visible content in this interval could be because the gamma kept its previous values or because the overlay appeared before the monitor began showing an image.
- In another setup, gamma returned to its original values about 0.035 seconds after removal. The reason for the difference is unknown.
- The gamma process did not receive reconfiguration notifications when it ran without `NSApplication`. The product needs to receive these notifications.

## Physical input

### Event taps

We used an event tap at the HID location to discard physical Space key events. We switched between a regular field and a secure field (`NSSecureTextField`) while keeping the same tap in place.

- In the regular field, the tap discarded all physical Space key-down and key-up events. The field stayed at 0 characters.
- In the secure field, while Secure Event Input was active, the tap received no physical Space key events and all 9 key-down and key-up pairs reached the field. The tap stayed enabled and received no disable notification.
- A separate monitor for raw, non-exclusive HID input also received 0 events during that interval.

Physical keystrokes bypass the event tap while Secure Event Input is active. Stacking taps or immediately re-enabling a tap cannot block that path.

### Local event suppression

We configured an event source with `CGEventSource.setLocalEventsFilterDuringSuppressionState` to block keyboard input (mask 5, 0.5 seconds). It posted a `mouseMoved` event with zero displacement inside its own window every 0.1 seconds. A physical Space press reached the regular field 4–96 ms after posting for both the `.privateState` and `.hidSystemState` source types. We observed no suppression.

### Exclusive device access with administrator privileges

A helper running with administrator privileges seized the built-in keyboard and the keyboard interface of the USB receiver with `kIOHIDOptionsTypeSeizeDevice`. The helper counted Space key events from the seized devices. With standard user privileges, seizing the built-in keyboard failed with `kIOReturnNotPrivileged`.

| Stage | Physical Space pairs counted by helper | Space pairs received by window | Secure Event Input |
| --- | --- | --- | --- |
| Without seizure | 2 pairs | 2 pairs | Off |
| Seized, regular field | 2 pairs | 0 | Off |
| Seized, secure field | 2 pairs | **0** | On in all 60 samples |
| Seized, synthetic keys | — | All 4 synthetic pairs | Off |
| After release | 2 pairs | 2 pairs | Off |
| Helper crashes while devices are seized | 2 pairs | 0 | Off |
| After the crash | — | 2 pairs | Off |

- When the helper crashed, it lost exclusive access immediately and the keyboard became usable. Physical input can reach the desktop once the helper stops.
- The same HID device can match both the mouse and pointer criteria and appear twice. The second seizure fails with `kIOReturnExclusiveAccess`. Use the registry ID to treat the two matches as a single device.

### Helper installation

In the tests above, we ran the helper from Terminal with administrator privileges. To determine how to package the helper, we tested a daemon registered with `SMAppService.daemon` in a temporary app signed with Developer ID. The temporary app was built locally and was never notarized.

- On first registration, the user had to approve the daemon in **Login Items** in **System Settings**. Once approved, the daemon started as root. Registering a daemon with a different identifier from the same app did not prompt for approval.
- The app and daemon communicated over XPC. `NSXPCListener.setConnectionCodeSigningRequirement` and `NSXPCConnection.setCodeSigningRequirement` required the peer to be signed by the same team. The daemon accepted connections from the team-signed app and rejected connections from an ad hoc signed copy.
- Without Input Monitoring permission for the daemon, exclusive access failed with `kIOReturnNotPermitted`.
  - Calling `IOHIDRequestAccess` from the daemon produced neither a dialog nor an entry in **Input Monitoring**.
  - Adding the main app to **Input Monitoring** and granting it access did not allow the daemon to seize devices.
  - Manually adding the daemon executable to **Input Monitoring** and granting it access allowed it to seize devices.
- Packaging the helper as a separate app inside the main app let the system create the **Input Monitoring** entry automatically. The daemon launches the executable inside the helper app.
  - Launching the helper app with the user's privileges and calling `IOHIDRequestAccess` displayed a dialog and created an entry. Once the user granted access to that entry, the daemon that used the same executable could seize devices.
  - While devices were seized, the user observed that physical keystrokes, clicks, and pointer movements did not reach the desktop.
- The running daemon did not pick up changes to permissions. It could seize devices only after restarting with access granted.

### Client input while devices are seized

| Client | Key events received by window | Field | Button | Physical Space pairs counted by helper during the same interval | Physical Space pairs received by window |
| --- | --- | --- | --- | --- | --- |
| Claude | 6 key-down events (source was Claude Code) | Matched `claude` | Activated | 46 pairs | 0 |
| Codex | 5 key-down events and 5 key-up events (source was the Codex Computer Use service) | Matched `codex` | Activated | 67–68 pairs | 0 |

Blocking physical input at the device distinguished it from AI input without relying on the source PID. Some Claude clicks had a source PID of 0.

### Pointer

With the trackpad and USB mouse also seized, the helper counted 11–13 physical clicks and recorded pointer movement. The window received 0 physical clicks.

## Capture and interaction while locked

### Video capture

We obscured the built-in display with gamma and an overlay and opened a window whose color and number changed every second.

- The Codex preview continued updating by visual observation. Codex read 41 and 74 about 30 seconds apart, consistent with a display that increments by 1 per second.
- A separate ScreenCaptureKit stream received 294 frames in about 88 seconds and captured 89 color changes. In a different trial, frames stopped after about 21 seconds without an error notification. The cause is unknown.
- Claude Computer Use returned still images. Two captures taken 5 seconds apart showed 23 and 28. These results cover still capture only.

### Interaction with all layers in place

We used gamma, an overlay, and exclusive access to the keyboard and pointing devices at the same time. Claude entered text and activated the button (7 key events and 5 mouse events). The button activated at a time consistent with the Codex action. The window received 0 physical input events during the same interval.

### Requirements for client testing

- Bundle the test window as an app. Neither Codex nor Claude Computer Use could target a window from an unbundled executable.
- Codex pauses for permission the first time it interacts with a window. Grant permission before locking.

## Unlocking

With gamma, an overlay, and exclusive access to the keyboard and pointing devices active, a physical Space event received by the helper triggered `LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)`. We did not offer a password fallback.

- Touch ID authentication succeeded in 1.88 seconds. We released the devices, removed the overlay, and restored gamma in that order. Both displays then had their original gamma values.
- The helper counted the key-down and key-up events for the Space press that triggered authentication. Neither event reached the window.
- Touch ID succeeded. The overlay appeared to hide the authentication window.
- Touch ID authentication also succeeded when only the keyboard was seized (1.76 seconds). It took 1.78 seconds without seizure.

## macOS session lock

We tested how to request and verify a macOS session lock for a possible handoff after a fault.

- Sending Control-Command-Q with `CGEventPost` displayed the lock screen by visual observation.
- `NSWorkspaceSessionDidResignActiveNotification` did not arrive when the session locked. A standard user could not create an Endpoint Security client. The call returned `ERR_NOT_PRIVILEGED`. The project does not request the Endpoint Security entitlement.
- We found an undocumented key whose value changed only while locked. The following results use reads taken every 0.1 seconds.

| Source | Reader | Lock | Unlock |
| --- | --- | --- | --- |
| `CGSSessionScreenIsLocked` in `IOConsoleUsers` at the IORegistry root | Helper (root) | Changed to 1 at +0 seconds | Key disappeared at +12.86 seconds |
| `CGSSessionScreenIsLocked` from `CGSessionCopyCurrentDictionary` | App | Changed to 1 at +0 seconds | Key disappeared at +12.93 seconds |
| Distributed notifications `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked` | App | Arrived at +0.19 seconds | Arrived at +12.83 seconds |

  Times are relative to when the key changed on lock. The time of unlock depends on when the user unlocks the session.

  All the functions used were public APIs. The key and notification names are undocumented. The headers list dictionary keys such as `kCGSessionOnConsoleKey` and `kCGSessionLoginDoneKey` and omit a key for lock state.
- We recorded the built-in display with the iPhone's slow-motion mode to check whether content appeared when we removed obscuration after confirming the lock. The content was a full-screen red window hidden by gamma and an overlay. We requested the lock by sending Control-Command-Q with `CGEventPost`. The test obscured the built-in display only.

| Trial | When obscuration was removed | Built-in display |
| --- | --- | --- |
| 1 | As soon as both keys indicated the lock (0.27 seconds after the request) | **The recording clearly showed red for about 0.6 seconds.** The lock screen then faded in |
| 2 | 1.5 seconds after both keys indicated the lock (1.68 seconds after the request) | The dark display transitioned to the lock screen. The recording showed no red |

  In trial 2, we used `CGWindowListCopyWindowInfo` to log `loginwindow` windows every 5 ms. At 0.08 seconds after the request, the keys changed and a full-screen window (layer 2001) appeared with opacity 0. At 0.27 seconds, the lock screen windows (layers 2003 and 2004) appeared. At 0.75 seconds, the opacity of the layer 2001 window reached 1. We ran each trial once.
- We did not test handoff to the macOS session lock when the helper stops or Touch ID is unavailable.
