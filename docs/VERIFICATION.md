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

#### Locking macOS at the start of reconfiguration with gamma alone

Codex took measurements on 2026-11-12 while the user handled the cable and watched the physical displays. The MacBookPro18,3 ran macOS 27.2 (26B123) with the built-in display and a PHL 279E1 in extended mode. We tested disconnecting and reconnecting the external display once each.

A temporary app displayed a red test pattern and used gamma alone to obscure it. A 20 ms timer continued to read back and reapply gamma. On the first Quartz reconfiguration start notification, the app began sending Control-Command-Q with `CGEventPost`. It used an existing Accessibility permission to send events. Times are relative to the first reconfiguration start notification in each trial. The logs recorded both lock-state indicators and the presence of opaque `loginwindow` windows covering all online displays. This trial covered display behavior only. [Quartz display reconfiguration callback](https://developer.apple.com/documentation/coregraphics/cgdisplayreconfigurationcallback)

| Operation | Log | Visual observation and assessment |
| --- | --- | --- |
| Disconnect | The removal notification arrived about 0.08 seconds later. At about 1.90 seconds, the log confirmed the lock screen covered the built-in display. All gamma readbacks on the built-in display were zero up to that point. | The user noticed no exposed content. The trial was inconclusive for brief exposures. |
| Reconnect | The addition notification arrived about 0.01 seconds later. The log confirmed the macOS lock state after about 0.18 seconds. Gamma became nonzero about 0.78 seconds after the start on the built-in display and 0.79 seconds after the start on the external display. The log confirmed the lock screen covered both displays after about 1.62 seconds. | The user saw content on the built-in display before the lock screen appeared. The trial failed to prevent exposure. |

In both trials, the app began sending events less than 1 ms after the first notification. The interval between the observed gamma change and the confirmed lock screen in the reconnect trial does not establish how long the physical display showed content. We did not record with an external camera.

#### Restoring ColorSync with a black vcgt assigned

Codex took measurements on 2026-11-13 on a MacBookPro18,3 running macOS 27.2 (26B123). The built-in display and the PHL 279E1 stayed connected in extended mode. We copied the external display's default ICC profile and replaced its `vcgt` with a formula whose minimum and maximum outputs were both zero for each RGB channel. We assigned that ICC profile only to the external display with `ColorSyncDeviceSetCustomProfiles`. After confirming that the profile had taken effect, we called `CGDisplayRestoreColorSyncSettings()`. The trial used no API that writes gamma tables directly.

In the final trial, gamma on the external display remained all zero in all 198 readbacks over about 5 seconds after the restore call (1,024 points per RGB channel). All readbacks on the built-in display matched their pre-test values. The user saw the external display stay black and then return to its original image.

The recovery process skipped display API initialization on the first run. We corrected the initialization and reran recovery. In the two trials after the fix, a separate process automatically removed the custom assignment and restored ColorSync after the test process exited. The ICC profiles and gamma on both displays matched their pre-test values.

The display configuration stayed fixed, and we did not record the physical displays. Disconnect and reconnect behavior and brief exposures below the threshold of visual detection remain unverified.

#### Reconnecting the external display with black vcgt assigned to both displays

On 2026-11-13, we tested the same MacBookPro18,3 running macOS 27.2 (26B123) with the built-in display and the PHL 279E1 in extended mode. We created an ICC profile with a black `vcgt` from each display's default ICC profile, assigned them, and confirmed that all gamma values were zero. We did not write gamma directly or explicitly restore ColorSync while observing the displays. Following a spoken cue, the user disconnected and reconnected the video cable once while watching the physical displays.

| Operation | Gamma readback | Visual observation |
| --- | --- | --- |
| Disconnect | About 5.2 seconds after the first readback without the external display in the online list, 3,069 of 3,072 points on the built-in display became nonzero. | The user saw content on the built-in display before reconnecting the cable. |
| Reconnect | Gamma on the built-in display remained nonzero through the end of the trial. Gamma on the external display was all zero in 402 readbacks over about 7 seconds after rediscovery. | Only the built-in display showed content. |

Both displays still had ICC profiles with a black `vcgt` assigned immediately before the end of the trial. In this setup, assigning a black ICC profile alone failed to prevent exposure on the built-in display. The read that first detected the reconnected external display took about 0.23 seconds. We did not record the physical displays. A brief exposure missed by readbacks and visual checks would go undetected.

After the test process exited, a separate process removed the test assignments automatically, starting with the built-in display and then the external display. Readback confirmed that the ICC profiles and gamma on both displays matched their pre-test values.

#### Test Black Windows During Display Reconfiguration

Codex took measurements on 2026-11-13 on the same MacBookPro18,3 running macOS 27.2 (26B123). With the built-in display and the PHL 279E1 in extended mode, the user disconnected and reconnected the external display cable once each. The prototype displayed a red test pattern and used both gamma and black windows at 99.9% opacity. The trial covered display behavior. Input blocking and client interaction were outside its scope.

On the Quartz reconfiguration start notification, the prototype set the windows on connected displays to 100% opacity. It also showed a 100% opaque window on each newly detected display. It checked opacity and bounds using WindowServer information and read back gamma from every display on a 20 ms timer. When gamma readbacks on all displays stayed at zero for 6 seconds with the same display configuration, the prototype restored window opacity to 99.9%.

| Operation | Log | Visual observation |
| --- | --- | --- |
| Disconnect | The prototype requested full opacity about 95 ms after the start notification. Gamma on the built-in display became nonzero about 0.35 seconds after the notification. After reapplying gamma, the prototype confirmed all-zero gamma for 6 seconds. | No content was visible on the built-in display. |
| Reconnect | WindowServer information confirmed opaque windows on both displays about 40 ms after the addition notification. Gamma on both displays became nonzero about 5.4 seconds after the start notification, while the black windows were still present. After reapplying gamma, the prototype restarted the 6-second all-zero check. | No content was visible on either display. |

The trial did not record the reconnected display as it first lit up. Visual checks could miss brief exposures. The A14 result for exposure prevention was inconclusive. After the trial, gamma readbacks confirmed that both displays had returned to nonzero gamma.

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

### Built-in trackpad stopped responding after unlock

On 2026-11-21, Codex collected diagnostics from a MacBookPro18,3 running macOS 27.2 (26B123) and Tenmaku 0.1.0 (build 4) with the privileged helper. The user reported that the display returned after a Touch ID unlock. The built-in trackpad gave haptic feedback, but cursor movement, clicks, and two-finger scrolling had no effect. Chrome Remote Desktop still controlled the session.

| Time (JST) | Observation |
| --- | --- |
| 03:39:32.750 | The built-in trackpad's HID event service recorded its last event. |
| 03:39:33.051 | The Tenmaku helper started its XPC listener. |
| 18:17:58.010 | The kernel logged a close for the trackpad's HID transport device (`0x100000abd`). The close entry carries option `0x1`. |
| 18:18:03.439 | launchd logged that the helper became inactive. The helper exited with code 0. |
| 18:31:35 and 18:32:35 | The trackpad's HID event service still reported 2,244,823 pointer events and 371,429 scroll events. The built-in keyboard service recorded events after unlock. |

IORegistry still showed the trackpad and its WindowServer client. The driver reported a later `LastReportTime` on consecutive reads, and the trackpad's HID event totals stayed fixed. No pointer event tap was enabled at the time of inspection. The HID diagnostic output showed that Mouse Keys and the options to ignore the built-in trackpad were off.

The observed unlock failed the input restoration criterion of A09. The diagnostics establish that the trackpad service stopped producing events and stayed in that state after the kernel logged the close and the helper exited. Tenmaku 0.1.0 did not record the return value of `IOHIDDeviceClose`. The condition that prevented the event service from resuming remains unknown. The investigation used the existing incident and did not start another shielding session.

At 18:50 JST, Codex used System Settings to turn on Mouse Keys with the option to ignore the built-in trackpad. Codex then restored both settings to off. The trackpad service reported the same event totals in all 12 samples between 18:51:19 and 18:52:06 JST. The user then confirmed that movement, clicking, and scrolling still had no effect. The event totals were unchanged at 18:55:46 JST.

At 18:57:04 JST, Codex requested system sleep with `pmset sleepnow`. The power log recorded that the display turned off and that HID activity restored full wake at 18:57:28 JST. The trackpad kept the same registry ID. Its event totals and last event were unchanged in all 12 samples between 18:58:04 and 18:58:51 JST. The user reported that movement, clicking, and scrolling still had no effect after wake. A further sample at 19:00:52 JST matched the earlier samples.

At 19:04:57 JST, the same service still reported 2,244,823 pointer events and 371,429 scroll events. On inspection, all three `IOHIDLibUserClient` entries under `Trackpad / Boot` reported `ClientOpened=Yes`, `ClientOptions=0`, `ClientSeized=No` and `ClientSuspended=No`. Their creators were WindowServer, Discord and a Discord helper. The Tenmaku helper's launchd job had exited with code 0. Its absence and the later probe's successful exclusive open are separate evidence against an ongoing grab by Tenmaku. The per-client `ClientSeized` flags alone do not establish device-wide ownership.

The user also tried closing and reopening the lid. The power log recorded clamshell sleep at 20:52:01 JST and full wake at 20:52:09 JST. The user reported that the trackpad still did not work. At 20:52:47 JST, the same trackpad service still reported the 03:39:32 last event and the same pointer and scroll totals.

With the user's approval, a temporary probe running as the current user opened only the built-in SPI trackpad interface (`Trackpad / Boot`, registry ID `0x100000abd`) once with `kIOHIDOptionsTypeSeizeDevice` and immediately closed it with `kIOHIDOptionsTypeNone`. Both calls returned `kIOReturnSuccess`. The kernel recorded both operations at 21:48:06.957 JST. The probe did not open the keyboard or start shielding. By 21:48:43 JST the trackpad service still showed the same event counts and the same last event as before the probe.

The user then tested one-finger movement, a physical click, and two-finger scrolling. None responded. At 21:50:25 JST the service still reported 3,930,546 digitizer events, 2,244,823 pointer events, and 371,429 scroll events. Its last event was still at 03:39:32. The single exclusive open and immediate close did not restore input in this incident.

In a separate test approved by the user, a probe opened only the same trackpad interface nonexclusively and counted incoming HID reports without examining their contents. The user left the trackpad untouched, moved one finger back and forth, then lifted it. The pointer did not move. The cumulative count was zero through 21:53:25 JST, rose to 1,193 between 21:53:26 and 21:53:38, and stayed there through 21:53:54. The probe closed successfully. At 21:54:07 the multitouch event service still showed the same digitizer, pointer and scroll counts and the 03:39:32 last event. The raw interface delivered reports during the trial while the event service showed no new events. The test did not establish whether the reports contained valid contact data or where processing stopped.

A second nonexclusive probe used Japanese voice prompts to distinguish horizontal and vertical movement. The HID interface exposed relative X and Y elements on report ID 2. The probe summed the absolute values delivered for each axis during each 12-second measurement window. The idle and rest windows received no reports. No raw payload or finger trajectory was saved.

| Prompt | Input reports | Sum of absolute X deltas | Sum of absolute Y deltas |
| --- | ---: | ---: | ---: |
| Move left and right | 1,455 | 50,025 | 1,934 |
| Move up and down | 1,454 | 1,083 | 23,557 |

All reports received during those windows were eight bytes long and had ID 2. The relative motion matched the prompted axis. The probe closed successfully. At 21:58:22 JST, the multitouch event service still reported the same event counts and the 03:39:32 last event. These measurements confirm directional motion at the raw interface. They do not identify the device's active mode or establish whether valid multitouch contacts were available. The log entries examined around the original unlock recorded the device close but did not identify a mode transition.

The same Mac retained event-generation statistics from before shielding. In the last interval starting at 03:39:28 JST, the multitouch processor recorded 778 digitizer events and 526 pointer events. No later interval appeared when checked after 22:09 JST. These are processor statistics. A healthy raw HID report capture was unavailable for comparison. The service reported that it was ready, its touch parser was enabled and pointing was enabled. A gesture override was recorded at 03:39:30; neither its writer nor its effect was established. The kernel returned `kIOReturnUnsupported` to an `IOServiceRequestProbe` request directed only at the trackpad HID endpoint. No request was sent to its shared SPI bus.

With an external USB pointing device connected, Codex toggled the setting to ignore the built-in trackpad when a mouse is present. The input service recorded the change at 22:06:51 JST and restoration at 22:07:09. A temporary AppKit window accepted indirect touches under the pointer while a nonexclusive probe counted the same trackpad's HID reports. One-finger movement produced 1,091 raw reports. Two-finger vertical scrolling produced 1,165. All were eight-byte ID 2 reports. The window received no touch, mouse movement or scroll events during either movement window. At 22:09:03 the device's last event was still at 03:39:32. Reapplying Force Click through System Settings also failed to restore physical operation. The service recorded restoration of its original force settings at 22:12:06, and the user confirmed the trackpad was still unresponsive.

#### Recovery without logging out

The user disconnected power, closed the lid on battery and reopened it after about three minutes. The power log recorded entry into `Sleep` at 22:15:03 JST and wake from Deep Idle at 22:18:05 (182 seconds). Both earlier AC trials had entered `DarkWake` and returned to full wake with the same multitouch service. On battery wake, the kernel started a new `AppleMultitouchDevice` (`0x10052d4b9`) and stopped the old one (`0x1002a66d9`). The same WindowServer process created a plugin for the new service and logged pointer movement at 22:18:07. The raw trackpad interface and its parent HID event driver's registry IDs stayed the same. The user confirmed recovery without logging out or rebooting.

| Measurement on the same trackpad HID interface | During failure | After battery sleep |
| --- | --- | --- |
| One-finger motion | ID 2, 8 bytes, with relative X/Y movement | ID 2, 76 bytes in the movement window; AppKit delivered mouse movement |
| Two-finger scrolling | ID 2, 8 bytes; no touch or scroll events in the test window | ID 2, 76–136 bytes; AppKit delivered indirect touch and 486 scroll callbacks |

By 22:20:14 the new service had counted 6,153 digitizer, 3,631 pointer and 1,101 scroll events. Button events also appeared in its generation statistics; the test window did not independently capture a full click. The gesture override recorded at 03:39:30 had the same value after recovery. The observations show a difference in the reports delivered at the raw interface as well as a restart of the multitouch service. They support a failure to resume normal multitouch reporting after the exclusive open. The exact device mode, the component responsible for selecting it, and the conditions necessary for recovery were not established. The duration and power source describe one successful trial, not a minimum or a universal requirement.

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

### Session tap click trial for 0.2.0

On 2026-11-21 a test app installed an active session event tap for left-button down and up. The filter applied to the two buttons in its own key window. It dropped events with a source PID of zero or less and passed positive PIDs. It did not open any HID devices or change the displays.

- The user tried the Physical button with the built-in trackpad and external mouse. The tap logged five down/up pairs with nonpositive PIDs and dropped all five. The Physical button recorded no activation. The tap did not identify individual devices.
- Codex Computer Use selected the button labeled Claude once. The app recorded one activation, its status changed to `Received: Claude`, and the tap logged no additional button event. The label identifies the target button; the client was Codex. This result covers that Computer Use action.
- The production agent uses the same session tap location and PID rule. This trial did not exercise full shielding, Secure Event Input, system-wide cursor movement, scrolling, dragging, or Claude Computer Use. The earlier results with both device types seized do not establish those outcomes for 0.2.0.

We then built and signed 0.2.0 with the repository's test flag (five-minute automatic release). We started shielding through the General settings and confirmed the normal pre-lock guide. The first attempt stopped before shielding because the session input agent lacked Accessibility permission. After the user enabled Accessibility for TenmakuInput, preflight succeeded with only TenmakuHelper visible in the Input Monitoring list.

The app reported shielding active. This second trial used a target window with no event tap of its own. Codex Computer Use clicked the Claude-labeled button once and the target recorded exactly one activation. We placed the pointer over the Physical button and the user tried the built-in trackpad and external mouse. The target recorded no Physical activation. The pointer stayed over the same point in the samples taken while shielding was active. The user held the configured left Shift key, authenticated with Touch ID, and confirmed that movement, clicking and scrolling worked immediately after unlock. Tenmaku returned to its idle state. This trial exercised one lock cycle. Secure Event Input during shielding, Claude, third-party mice beyond the connected receiver, and repeated cycles were not tested.

### Switching the 0.2.0 helper from General settings

On 2026-11-21 we opened General settings in a signed universal 0.2.0 build with shielding off. Selecting Without Helper removed the system job `jp.pronama.tenmaku.helper`. The gamma, cover and session input jobs remained registered in the user's launchd domain. Selecting With Helper registered the system job again. Selecting Without Helper a second time removed it. This Mac had previously approved the helper. The test did not exercise first-time system approval or change the physical displays.

After quitting Tenmaku, a separate test cleanup reset macOS privacy decisions with bundle-scoped `tccutil reset All` for the main app and its four bundled services. The settings switch itself does not reset privacy permissions.

### Setup after a permission change

On 2026-11-21 the Mac retained the completed-setup preference and the input agent was authorized in helperless mode. We reset Accessibility and PostEvent only for the main Tenmaku bundle. The signed 0.2.0 app opened Setup directly at the screen-lock permission step. The page showed permission missing, and Next was disabled.

An initial build polled CoreGraphics posting preflight and continued to show the earlier denial after the user enabled Accessibility. In the revised build the main app checked accessibility trust and HID posting authorization. After the user enabled Tenmaku in System Settings, Setup advanced to its summary with both required permissions marked granted. The main app PID was 69230 before and after the grant. This trial did not start shielding.
