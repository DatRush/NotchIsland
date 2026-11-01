#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
check_dir="$(mktemp -d /private/tmp/notch-compact-check.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT
swiftc -module-cache-path "$check_dir/cache" "$root/Checks/ChatGPTCompact/main.swift" "$root/Sources/NotchIsland/ChatGPTCompact.swift" "$root/Sources/NotchIsland/ChatGPTLayoutDiagnostics.swift" -o "$check_dir/check"
"$check_dir/check"
