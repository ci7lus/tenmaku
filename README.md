# Tenmaku

Tenmaku is a lock app for macOS that prevents others from using your Mac while work is in progress.
Claude and Codex can continue to control your Mac through Computer Use.

## Build

```sh
scripts/build.sh                                           # Build and sign build/Tenmaku.app
NOTARY_PROFILE=your-profile-name scripts/notarize.sh         # Notarize, staple the ticket, and verify with spctl
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
