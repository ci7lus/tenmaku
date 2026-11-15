# English and Japanese Localization

The display language follows macOS language preferences. Users can also choose an app-specific language under Language & Region in System Settings. Restart Tenmaku to apply changes. Tenmaku supports English and Japanese. It falls back to English when none of the preferred languages are supported.

## Edit Display Copy

`Bundle/Localizable.xcstrings` is the source of truth. English is the source language, and every entry must have a Japanese translation. Edit the catalog in Xcode's String Catalog editor or as JSON.

- Use keys that describe the meaning, such as `settings.general`. Keep keys stable when editing wording.
- Use `comment` to record where a string appears and what the translation must preserve.
- Translate complete messages. Use the actual tab and button labels when referring to controls.
- Use `%@` for strings and `%lld` for integers. Keep parameter types and order consistent across languages. Use the `one` and `other` plural forms for durations in English.
- Generate `Sources/Tenmaku/Strings.swift` with the script below.

After editing the catalog, run both commands.

```sh
python3 scripts/generate-strings.py
scripts/check-localization.sh
```

The generator creates typed `L10n` accessors from localization keys and parameter types. Display copy comes from the bundled localization resources. In SwiftUI and AppKit, use the localized `String` returned by these accessors. When adding a key, update its call sites. Run the generator before using `swift build` or `swift test` directly.

`check-localization.sh` verifies translation coverage, parameter consistency, and the generated file. It then compiles the catalog into a temporary `.app` and runs a probe targeting macOS 13. The probe covers English and Japanese language selection, English fallback for unsupported languages, plurals, interpolated arguments, helper errors, and startup refusal when a required resource is missing. The probe leaves the displays and input unchanged.

## Build Integration

`scripts/build.sh` generates the accessors before building Swift. It uses `xcstringstool compile` to write translations to `Contents/Resources/ja.lproj` and `en.lproj` in the main app, then signs it. Python 3 is required only to generate the accessors.

The app requires `Localizable.strings` for both languages and the English `Localizable.stringsdict` for plurals. If a required file is unreadable, the app logs the filename and exits. Use the app packaged by `scripts/build.sh` for display checks because `swift run` has no bundled localization resources.

## Errors from Other Processes

`ShieldLayer` returns failures as `NSError?`. `nil` indicates success. Failures use the `LayerFailure` domain and stable numeric codes. Include the numeric IOKit status in `userInfo[LayerFailure.statusKey]`. Translated error messages live in the main app.

The app translates errors from the catalog using `localizedLayerError`. Unknown domains and codes produce a generic error. When macOS supplies an error description to the app, insert it as provided. The sleep assertion uses the fixed diagnostic name `Tenmaku lock`.

`LayerFailureTests` covers secure archiving and receiving codes and arguments over an anonymous XPC connection.

## References

On 2026-11-10, the project consulted Xcode 27.2's `xcstringstool` help and the public Foundation declarations in the macOS SDK. The generator and verification code were written independently for Tenmaku. The project used Apple's public String Catalog documentation and excluded third-party implementations and Apple's sample code. [String Catalog documentation](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog)
