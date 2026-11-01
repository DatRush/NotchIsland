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
