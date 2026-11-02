#!/bin/bash
# Run from the repository root after building a release with build-dmg.sh.
set -euo pipefail
image="${1:?Usage: bash Scripts/prepare-update.sh path/to/NotchIsland.dmg}"
app="$(dirname "$image")/NotchIsland.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build" =~ ^[0-9]+$ ]]
[[ "$(lipo -archs "$app/Contents/MacOS/NotchIsland")" = arm64 ]]
tools=.build/artifacts/sparkle/Sparkle/bin
out="$(mktemp -d "$PWD/build/update.XXXXXX")"
asset="NotchIsland-$version-arm64.dmg"
cp "$image" "$out/$asset"
"$tools/generate_appcast" --account NotchIsland-Updates --maximum-deltas 0 \
    --download-url-prefix "https://github.com/DatRush/NotchIsland/releases/download/v$version/" "$out"
swiftc Scripts/VerifyUpdate.swift -framework CryptoKit -o build/verify-update
build/verify-update "$app/Contents/Info.plist" "$out/appcast.xml" "$out/$asset"
echo "$out"
