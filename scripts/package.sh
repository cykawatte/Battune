#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="$(cat VERSION)"
app=build/release/Battune.app
helper="$app/Contents/Library/HelperTools/BattuneHelper.app"
[[ -d "$app" ]] || { echo 'Run ./scripts/build.sh release universal first' >&2; exit 1; }
if [[ -n "${BATTUNE_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$BATTUNE_SIGNING_IDENTITY" --identifier org.battune.helper "$helper"
  codesign --force --options runtime --timestamp --sign "$BATTUNE_SIGNING_IDENTITY" --identifier org.battune.app "$app"
fi
codesign --verify --deep --strict "$app"
./scripts/build-helper-installer.sh release helper
./scripts/build-helper-installer.sh release full
folder="build/packages/Battune-$version"
mkdir -p "$folder"
cp "build/release/Battune-$version.pkg" "$folder/"
cp build/release/BattuneHelper.pkg "$folder/"
cp packaging/INSTALL.md "$folder/README.md"
cp scripts/uninstall-local-helper.sh "$folder/Uninstall-Helper.sh"
cp scripts/uninstall-battune.sh "$folder/Uninstall-Battune.sh"
ditto -c -k --keepParent "$folder" "build/packages/Battune-$version.zip"
cp "build/release/Battune-$version.pkg" build/packages/
cp build/release/BattuneHelper.pkg "build/packages/BattuneHelper-$version.pkg"
if [[ "${1:-}" == --dmg ]]; then
  hdiutil create -volname "Battune Beta" -srcfolder "$folder" -ov -format UDZO "build/packages/Battune-$version.dmg"
fi
(cd build/packages && shasum -a 256 "Battune-$version.pkg" "BattuneHelper-$version.pkg" "Battune-$version.zip" > SHA256SUMS.txt)
echo 'Beta artifacts prepared. Upload/notarization are separate explicit steps.'
