# NotchIsland

NotchIsland is a free macOS utility that puts your clipboard history, a temporary file shelf, screenshots, a timer, reminders, and music controls in a small panel next to your MacBook’s camera. The interface is available in English and Russian.

## Install on Apple Silicon

1. Download the DMG from [GitHub Releases](https://github.com/DatRush/NotchIsland/releases).
2. Open the DMG and drag **NotchIsland** onto the **Applications** folder.
3. Eject the disk image and open NotchIsland from Applications. You can find its settings in the NotchIsland menu in the macOS menu bar.

The app requires macOS 13 or later. The current release uses an ad hoc signature and is not notarized by Apple. If macOS blocks it on first launch, see [Apple’s guide to opening downloaded apps](https://support.apple.com/en-us/102445).

## Updates

Choose **Check for Updates…** from the NotchIsland menu. Background checks are off by default; choose **Automatically Check for Updates** to enable them.

**Upgrading from 0.1.0?** The updater cannot start in that version. Install version 0.1.1 or later from the DMG once, replacing the old app in Applications. After that, use the menu to check for updates.

## Features

- Reuse items from your clipboard history or keep temporary copies of files on the shelf.
- Capture a selected area of the screen. In the ChatGPT tab, you can attach a screenshot to a draft. The upload may begin as soon as you attach it, before you send the message.
- Run a timer and view tasks from a list you choose in Apple Reminders.
- Control playback in Apple Music and Yandex Music. YouTube support is experimental, and downloading YouTube artwork is off by default.

## Build from source

On a Mac running macOS 13 or later, install Apple’s developer tools with Swift 5.9 or later. From the repository root, run:

```sh
bash Scripts/build-app.sh
```

The script builds the release app, bundles its icon, permission descriptions, and documentation, and signs it locally. The last line prints the path to `NotchIsland.app`. Replacing a locally signed build may cause macOS to ask for permissions again.

To create a drag-and-drop disk image for your Mac’s architecture, run:

```sh
bash Scripts/build-dmg.sh
```

The script prints the path to `NotchIsland.dmg`.

## Privacy, license, and support

Read the privacy policy in [English](PRIVACY.en.md) or [Russian](PRIVACY.md) for details about data, permissions, and how to remove the app and its data. The policy is also available offline in the app’s About window. For privacy questions, email [tair@kuanyshbayev.com](mailto:tair@kuanyshbayev.com).

NotchIsland is available under the [MIT License](LICENSE). If you’d like to support development, you can [donate on Boosty](https://boosty.to/taykwn/donate).
