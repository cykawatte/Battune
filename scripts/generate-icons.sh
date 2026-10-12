#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/icons assets
xcrun swiftc -parse-as-library app/Battune/App/BattuneMark.swift scripts/icons/RenderIcons.swift -o build/icons/render
build/icons/render build/icons
for name in Battune BattuneHelper; do
  iconutil -c icns "build/icons/$name.iconset" -o "assets/$name.icns"
  cp "build/icons/$name.png" "assets/$name.png"
done
