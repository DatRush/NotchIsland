#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
check_dir="$(mktemp -d /private/tmp/notch-session-check.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT
sources=(Localization LocalizedRoot ChatGPTWeb ChatGPTText ChatGPTTextView ChatGPTNavigationError ChatGPTScreenshot ChatGPTCompact ChatGPTLayoutDiagnostics Clipboard)
files=()
for source in "${sources[@]}"; do files+=("$root/Sources/NotchIsland/$source.swift"); done
swiftc -module-cache-path "$check_dir/cache" "$root/Checks/ChatGPTSession/main.swift" "${files[@]}" -o "$check_dir/check"
"$check_dir/check"
