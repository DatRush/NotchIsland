#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
mkdir -p build
output="$(mktemp -d "$PWD/build/local.XXXXXX")/NotchIsland.app"
contents="$output/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources" "$contents/Frameworks"
ditto "$binary_dir/Sparkle.framework" "$contents/Frameworks/Sparkle.framework"
cp "$binary_dir/NotchIsland" "$contents/MacOS/"
cp Packaging/Info.plist "$contents/"
cp -R Packaging/ru.lproj Packaging/en.lproj Packaging/Assets/AppIcon.icns LICENSE PRIVACY.md PRIVACY.en.md "$contents/Resources/"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$contents/Resources/Sparkle-LICENSE.txt"
vendor=Vendor/MediaRemoteAdapter
framework="$contents/Frameworks/MediaRemoteAdapter.framework"
version="$framework/Versions/A"
mkdir -p "$version/Resources"
cp "$vendor/bin/mediaremote-adapter.pl" "$contents/Resources/"
cp "$vendor/LICENSE" "$contents/Resources/MediaRemoteAdapter-LICENSE.txt"
clang -dynamiclib -fobjc-arc -mmacosx-version-min=13.0 -I"$vendor/include" -I"$vendor/src" \
    "$vendor"/src/{adapter,private,utility}/*.m -framework Foundation -framework AppKit \
    -framework UniformTypeIdentifiers -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
    -o "$version/MediaRemoteAdapter"
info="$version/Resources/Info.plist"
plutil -create xml1 "$info"
plutil -insert CFBundleIdentifier -string com.vandenbe.MediaRemoteAdapter "$info"
plutil -insert CFBundleExecutable -string MediaRemoteAdapter "$info"
plutil -insert CFBundlePackageType -string FMWK "$info"
plutil -insert CFBundleVersion -string 1 "$info"
ln -s A "$framework/Versions/Current"
ln -s Versions/Current/MediaRemoteAdapter "$framework/MediaRemoteAdapter"
ln -s Versions/Current/Resources "$framework/Resources"
codesign --force --sign - "$framework"
plutil -lint "$contents/Info.plist"
codesign --force --sign - "$output"
codesign --verify --deep --strict "$output"
bash Checks/UpdaterStartup/run.sh "$output"
echo "$output"
