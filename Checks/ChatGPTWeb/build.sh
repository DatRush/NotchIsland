#!/bin/bash
set -euo pipefail
probe_source="$(cd "$(dirname "$0")" && pwd)"
probe_app="/private/tmp/notch-chatgpt-probe/ChatGPTProbe.app"
mkdir -p "$probe_app/Contents/MacOS"
swiftc -module-cache-path "${TMPDIR:-/tmp}/notch-chatgpt-module-cache" "$probe_source/main.swift" -o "$probe_app/Contents/MacOS/ChatGPTProbe"
cat > "$probe_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.NotchIsland.ChatGPTProbe</string>
<key>CFBundleName</key><string>ChatGPTProbe</string>
<key>CFBundleExecutable</key><string>ChatGPTProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# iCloud/Finder can attach metadata to generated bundles in Documents.
xattr -cr "$probe_app"
codesign --force --sign - "$probe_app"
codesign --verify --strict "$probe_app"
