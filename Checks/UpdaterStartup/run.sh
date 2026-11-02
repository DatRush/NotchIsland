#!/bin/bash
set -euo pipefail
bundle="$(cd "${1:?Pass the packaged .app}" && pwd)"
frameworks="$bundle/Contents/Frameworks"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
swiftc "$(dirname "$0")/main.swift" -F "$frameworks" -framework Sparkle -Xlinker -rpath -Xlinker "$frameworks" -o "$dir/check"
"$dir/check" "$bundle"
