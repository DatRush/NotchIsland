#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir="$(mktemp -d /private/tmp/notch-weather-check.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT
swiftc -module-cache-path "$check_dir/cache" Sources/NotchIsland/Localization.swift Sources/NotchIsland/Weather.swift Checks/Weather/main.swift -o "$check_dir/check"
"$check_dir/check"
