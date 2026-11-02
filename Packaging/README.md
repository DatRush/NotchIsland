# Local app bundle

Copy Info.plist to NotchIsland.app/Contents/Info.plist when packaging. It declares
both NSRemindersUsageDescription (macOS 13) and NSRemindersFullAccessUsageDescription
(macOS 14+) for EventKit access. It must be installed before signing the app.

Local builds currently use ad-hoc signing. Changing their executable can trigger
another macOS privacy prompt. Distribution requires a stable signing identity;
do not bypass or modify privacy permissions to suppress the prompt.

The legacy JSON is a migration source, not the current database. The active list
lives in Apple Reminders; iCloud sync depends on the selected account and OS settings.

## App icon

The shared vector master is `Sources/NotchIsland/BrandIcon.swift`.
Regenerate the app icon from the repository root:

```sh
swiftc Scripts/GenerateIcon/main.swift Sources/NotchIsland/BrandIcon.swift -o /private/tmp/notch-icon-generator
/private/tmp/notch-icon-generator /private/tmp/NotchIsland.iconset
iconutil -c icns /private/tmp/NotchIsland.iconset -o Packaging/Assets/AppIcon.icns
```

Copy `Packaging/Assets/AppIcon.icns` to `NotchIsland.app/Contents/Resources/AppIcon.icns`
and the packaging Info.plist before signing. The runtime About/menu images use the
same vector directly and do not require resource lookup.

## Interface languages and transparent logo

Copy `Packaging/en.lproj` and `Packaging/ru.lproj` into `Contents/Resources/`
before signing, along with the updated Info.plist. These contain localized system
permission descriptions; macOS controls their language. The app's Russian/English
selector is independent and uses `Localization.swift` with `LocalizedRoot.swift`.

The icon generator also writes `AboutLogo.png` next to the generated iconset.
Its source-controlled copy is `Packaging/Assets/AboutLogo.png`. The About window
renders the same transparent vector directly for sharpness and theme adaptation.

Copy `PRIVACY.md`, `PRIVACY.en.md` and `LICENSE` from the repository root into `Contents/Resources/` before signing. The About window previews the policy matching the selected interface language.

## Drag-to-install disk image

Run `bash Scripts/build-dmg.sh` from the repository root on macOS. It packages the Release bundle and an absolute symlink to `/Applications` in a compressed, read-only HFS+ image. `FinderLayout.dsstore` is a generated Finder metadata template for icon view, with NotchIsland at (125, 108) and Applications at (385, 108). Building the image requires no third-party DMG tools.

## Publishing a Sparkle update

Set a new user-facing version in CFBundleShortVersionString (for example 0.1.1) and increment the integer CFBundleVersion. Keep the bundle identifier and public signing key stable. Build the DMG on the release Mac with `bash Scripts/build-dmg.sh`. Run `bash Scripts/prepare-update.sh <path-to-DMG>` on the resulting image. The signing tool uses the NotchIsland-Updates entry in the release maintainer’s Keychain. The script checks the feed and archive against the public key embedded in the bundle.

Publish the versioned DMG from the output folder as an asset of a GitHub Release tagged v<version>. Once the asset is downloadable, copy the signed appcast.xml from the output folder to updates/appcast.xml on main and push it without editing its bytes. Verify the downloaded archive and feed with the same public-key verifier. Keep the private update key in the maintainer’s Keychain and a secure backup under their control.

This feed serves arm64 builds for macOS 13 and newer. The embedded Sparkle dependency is pinned by Package.resolved. Signed updates and the initial Gatekeeper launch are separate steps. This release still uses the project’s local ad-hoc code signature.
