#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app=build/release/Battune.app
[[ -d "$app" ]] || { echo 'Run ./scripts/build.sh release first' >&2; exit 1; }
if [[ -n "${BATTUNE_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$BATTUNE_SIGNING_IDENTITY" --identifier org.battune.helper "$app/Contents/Library/HelperTools/BattuneHelper"
  codesign --force --options runtime --timestamp --sign "$BATTUNE_SIGNING_IDENTITY" --identifier org.battune.app "$app"
fi
codesign --verify --deep --strict "$app"
mkdir -p build/packages
ditto -c -k --sequesterRsrc --keepParent "$app" build/packages/Battune-0.1.0-dev.zip
if [[ "${1:-}" == --dmg ]]; then
  hdiutil create -volname Battune -srcfolder "$app" -ov -format UDZO build/packages/Battune-0.1.0-dev.dmg
fi
echo 'Local development package created. Not published or notarized.'
