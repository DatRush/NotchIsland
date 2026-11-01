#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
check_dir="$(mktemp -d /private/tmp/notch-artwork-check.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT
swiftc -module-cache-path "$check_dir/cache" "$root/Checks/RemoteArtwork/main.swift" "$root/Sources/NotchIsland/RemoteArtwork.swift" -o "$check_dir/check"
"$check_dir/check"
