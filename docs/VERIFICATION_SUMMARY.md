# Verification Summary

We tested on physical hardware whether the requirements in the [specification](SPEC.md) could be met using only public APIs. The methods and measurements are in the [verification record](VERIFICATION.md).

## Conclusion

The following setup met the main requirements in the specification under the conditions tested.

- Gamma and covers excluded from screen capture formed two layers of protection for the physical displays. The displays showed no content when either layer failed separately or when the external display was disconnected and reconnected.
- A helper running with administrator privileges blocked physical input by seizing the keyboard and pointing devices. It blocked physical keystrokes to a secure field while Secure Event Input was active. Input from Codex and Claude reached the target.
- To unlock, a physical key received by the helper triggered Touch ID authentication. The test removed all layers after authentication succeeded.

Each item had few trials, and some conditions remain untested. These trials are insufficient to declare support for this setup.

## Environment

| Item | Details |
| --- | --- |
| Mac | MacBookPro18,3, macOS 27.2 (26B123), SDK 27.2 |
| Displays | Built-in display (up to 120 Hz) and external PHL 279E1 (60 Hz) in extended mode |
| Input devices | Built-in keyboard and trackpad, mouse connected via a USB receiver |
| Clients | Codex Desktop (Computer Use), Claude Code (native Computer Use) |
| Observing physical displays | iPhone built-in slow-motion recording and visual checks by the user |

## Setup

| Layer | Method | What removes it |
| --- | --- | --- |
| Gamma | Set all gamma tables to zero. Read them back every 20 ms and reapply them if any value is nonzero | Exit of the owning process, exit of another process that wrote gamma, or a display configuration change |
| Cover | Show black windows on all displays. Use `NSWindow.sharingType = .none`, 99.9% opacity (`isOpaque = false`), `ignoresMouseEvents = true`, and the `.screenSaver` level. A separate process owns the covers | Exit of the owning process |
| Input | A helper running with administrator privileges uses `kIOHIDOptionsTypeSeizeDevice` to seize physical keyboards and pointing devices. The helper is a daemon registered with `SMAppService.daemon` and requires Input Monitoring permission | Exit of the helper process |
| Unlock | A physical key received by the helper while protection is active triggers Touch ID through `LAContext` | — |

Gamma and the covers had different failure conditions, so one layer stayed in place when the other failed.

## Results by requirement

| Requirement | Result | Remaining work |
| --- | --- | --- |
| R1 Start and maintain the lock | Verified under limited conditions. The test applied gamma, showed the covers, and seized input devices in that order. The test considered protection active only after all three were in place | Failures during startup, denied permissions, status reporting in the product, and mirrored displays |
| R2 Obscure displays during normal operation | Verified under limited conditions. Gamma and the covers hid content on both displays. The pointer appeared above the covers, as the specification allows | Without covers, a gamma failure or display reconfiguration can expose content. The specification records this limitation |
| R3 Block physical input | Verified under limited conditions with the helper. Physical keystrokes and clicks reached neither the regular field nor the secure field. The key that triggered unlocking only started authentication and never reached the desktop | Keys other than Space, modifier keys, scrolling, and keys held across lock or unlock. Without a helper, physical keystrokes cannot be blocked while Secure Event Input is active |
| R4 Capture and interact | Verified under limited conditions. Claude and Codex captured the screen, entered text, and clicked while protection was active. The Codex preview kept updating | Claude video capture, video capture with both displays protected, scrolling, and modifier keys |
| R5 Unlock | Verified. Touch ID authentication succeeded while protection was active, and the test removed all layers | Password unlock and handling cases where Touch ID is unavailable |
| R6 Handle failures | Verified under limited conditions. The physical displays showed no content when another process that wrote gamma exited, when the gamma or cover process was force-quit separately, or when the external display was disconnected and reconnected | Faults that remove both layers at once, handling helper stoppage (physical input can pass when the helper stops), and wake from sleep |

## Methods ruled out

| Method | Reason |
| --- | --- |
| Obscure the displays with gamma alone | Gamma returned to its original values when the owning process exited, even after a normal exit. When another process that wrote gamma exited, gamma also reverted on the other display. Display reconfiguration reverted gamma too. Reapplying gamma after it reverts briefly exposes content |
| Obscure the displays with covers alone | When the owning process exited, the cover disappeared and exposed the content |
| Fully opaque covers | Whole-display capture paths (Claude Computer Use and `screencapture`) omitted the windows behind the cover and showed only the wallpaper |
| Block physical input with an event tap | While Secure Event Input was active, physical keystrokes bypassed the tap and reached the secure field |
| Local event suppression (`CGEventSource.setLocalEventsFilterDuringSuppressionState`) | Physical keystrokes still reached the regular field |
| Distinguish AI input from physical input by source PID | Some Claude clicks had a source PID of 0 and could not be distinguished from physical input |

## Limits and untested conditions

- Each item had one to a few trials.
- Capture and interaction were tested separately from unlocking.
- Keys other than Space, modifier keys, scrolling, dragging, and external keyboards remain untested.
- Password unlock, handling cases where Touch ID is unavailable, and handoff to the macOS session lock remain untested.
- Only undocumented keys indicated that the macOS session was locked. The keys changed before the lock screen appeared. Removing obscuration immediately after the keys changed exposed content. In one trial, waiting 1.5 seconds after both keys indicated the lock avoided visible exposure. Variation in the length of the lock screen fade-in remains untested.
- Helper registration and permissions in a notarized distribution build remain untested.
- Video capture with both displays protected and Claude video capture remain untested.
- Mirroring, HDR, wake from sleep, and turning the external display off and on remain untested.
- Apple documents `NSWindow.sharingType = .none` as legacy. A future macOS version could include those windows in screen capture.

## Materials

The tests used independently written programs that call only public APIs. They used no third-party code, assets, dependencies, or Apple sample code.
