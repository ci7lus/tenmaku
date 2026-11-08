# tenmaku

tenmaku is a proposed macOS privacy app. When you step away from your Mac, it hides the desktop on the physical displays and blocks local keyboard and mouse input. Agents such as Codex and Claude can keep capturing and controlling the same desktop. The macOS session stays active, and the app uses Touch ID to unlock.

Implementation has reached stage 1 of the [implementation guide](docs/IMPLEMENTATION.md), which covers the bundle, signing, and notarization. Protection is still pending.

## Status

Testing on November 8, 2026 confirmed the following configuration.

- The physical displays use two layers in separate processes. One sets all gamma values to zero. The other draws a black cover excluded from capture (`NSWindow.sharingType = .none`, 99.9% opacity). The desktop stayed hidden on the physical displays when either layer failed and when an external display was unplugged and reconnected.
- A privileged helper seizes the keyboard and pointer to block physical input. During Secure Event Input in a password field, the helper blocked physical keystrokes while input from Codex and Claude still reached the desktop.
- The helper receives a physical key press during protection and starts Touch ID authentication. Successful authentication releases all layers.

Trials were limited and some conditions remain unverified. [Summary of verification results](docs/VERIFICATION_SUMMARY.md)

## Build

```sh
scripts/build.sh                                      # Build and sign build/Tenmaku.app
NOTARY_PROFILE=your-profile-name scripts/notarize.sh  # Notarize, staple the ticket, and verify with spctl
```

`NOTARY_PROFILE` identifies the Keychain credentials saved with `xcrun notarytool store-credentials your-profile-name`. Set `SIGN_IDENTITY` to your Developer ID Application signing identity.

| Location in the app bundle | Role |
| --- | --- |
| `Contents/MacOS/Tenmaku` | Menu bar UI and settings window |
| `Contents/MacOS/TenmakuGamma` | Agent that manages gamma shielding (`jp.pronama.tenmaku.gamma`) |
| `Contents/MacOS/TenmakuCover` | Agent that manages the cover (`jp.pronama.tenmaku.cover`) |
| `Contents/Library/Helpers/TenmakuHelper.app` | Root daemon that blocks physical input (`jp.pronama.tenmaku.helper`) |

## Documentation

| Document | Contents |
| --- | --- |
| [docs/SPEC.md](docs/SPEC.md) | Requirements and acceptance criteria |
| [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md) | Implementation assumptions, architecture, and sequence |
| [docs/VERIFICATION_SUMMARY.md](docs/VERIFICATION_SUMMARY.md) | Summary of verification results |
| [docs/VERIFICATION.md](docs/VERIFICATION.md) | Verification methods, measurements, and limitations |

Detailed verification records, test programs, and evidence are stored outside this repository.

## License

[Mozilla Public License 2.0](LICENSE)
