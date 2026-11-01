#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
mkdir -p build
output="$(mktemp -d "$PWD/build/local.XXXXXX")/NotchIsland.app"
contents="$output/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$binary_dir/NotchIsland" "$contents/MacOS/"
cp Packaging/Info.plist "$contents/"
cp -R Packaging/ru.lproj Packaging/en.lproj Packaging/Assets/AppIcon.icns LICENSE PRIVACY.md PRIVACY.en.md "$contents/Resources/"
plutil -lint "$contents/Info.plist"
codesign --force --sign - "$output"
codesign --verify --deep --strict "$output"
echo "$output"
