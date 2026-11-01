#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
# Keep the build log visible while capturing the bundle path on its last line.
log="$(mktemp -d "${TMPDIR:-/tmp}/notchisland-dmg.XXXXXX")"
trap 'rm -rf "$log"' EXIT
bash Scripts/build-app.sh | tee "$log/build.log"
app="$(tail -n 1 "$log/build.log")"
codesign --verify --deep --strict "$app"

stage="$log/volume"
mkdir "$stage"
ditto "$app" "$stage/NotchIsland.app"
ln -s /Applications "$stage/Applications"
cp Packaging/FinderLayout.dsstore "$stage/.DS_Store"

hdiutil create -volname NotchIsland -fs HFS+ -format UDZO -srcfolder "$stage" "$log/NotchIsland.dmg"
hdiutil verify "$log/NotchIsland.dmg"
output="$(dirname "$app")/NotchIsland.dmg"
mv "$log/NotchIsland.dmg" "$output"
echo "$output"
