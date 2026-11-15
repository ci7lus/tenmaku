# Tenmaku

Tenmaku is a lock app for macOS that prevents others from using your Mac while work is in progress.
Claude and Codex can continue to control your Mac through Computer Use.

![tenmaku usage image](https://github.com/user-attachments/assets/c27d23f0-f4b0-4e0a-8c90-b5f9b489b639)

## Minimum requirements

- macOS 13.0 Ventura or later. The app bundle includes executables for Apple silicon and Intel Macs.
- Touch ID set up and available to start shielding and unlock Tenmaku.
- A single display or multiple displays in extended mode.
- Accessibility permission for Tenmaku to request the macOS screen lock.
- If you use the optional privileged helper, approve it in Login Items and grant it Input Monitoring permission.
- Without the helper, grant TenmakuInput Accessibility and Input Monitoring permissions. Tenmaku can start shielding in this mode only while Secure Event Input is inactive.

Tenmaku may not work as expected outside the [tested environment](#tested-environment).

## Tested environment

The hardware trials used prototypes with the privileged helper and covered a subset of the acceptance tests.

| Item | Environment |
| --- | --- |
| Mac | MacBook Pro (`MacBookPro18,3`) |
| macOS | 27.2 (26B123) |
| Displays | Built-in display (up to 120 Hz) and external PHL 279E1 (60 Hz) in extended mode |
| Input devices | Built-in keyboard and trackpad, and a mouse connected via a USB receiver |
| Clients | Codex Desktop (Computer Use) and Claude Code (native Computer Use) |

## Build

```sh
scripts/build.sh # Build and sign build/Tenmaku.app
NOTARY_PROFILE=your-profile-name scripts/notarize.sh # Notarize, staple the ticket, and verify with spctl
```

| Location in the app bundle | Role |
| --- | --- |
| `Contents/MacOS/Tenmaku` | Menu bar UI and settings window |
| `Contents/Library/Helpers/TenmakuGamma.app` | Agent that manages gamma shielding (`jp.pronama.tenmaku.gamma`) |
| `Contents/Library/Helpers/TenmakuCover.app` | Agent that manages the shielding area (`jp.pronama.tenmaku.cover`) |
| `Contents/Library/Helpers/TenmakuHelper.app` | Root daemon that blocks physical input (`jp.pronama.tenmaku.helper`) |

## Documentation

| Document | Contents |
| --- | --- |
| [docs/SPEC.md](docs/SPEC.md) | Requirements and acceptance criteria |
| [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md) | Implementation assumptions, architecture, and sequence |
| [docs/VERIFICATION_SUMMARY.md](docs/VERIFICATION_SUMMARY.md) | Summary of verification results |
| [docs/VERIFICATION.md](docs/VERIFICATION.md) | Verification methods, measurements, and limitations |

## About the Pronama-chan Developer Support Program

This app is supported by the Pronama-chan Developer Support Program.
The program helps with app notarization and other procedures.

## License

[Mozilla Public License 2.0](LICENSE)
