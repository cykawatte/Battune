#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-debug}"
architecture="${2:-$(uname -m)}"
case "$configuration" in debug|release) ;; *) echo 'Usage: build.sh [debug|release] [arm64|x86_64|universal]' >&2; exit 2;; esac
case "$architecture" in arm64|x86_64) architectures=("$architecture");; universal) architectures=(arm64 x86_64);; *) exit 2;; esac
export BATTUNE_CONFIGURATION="$configuration"
for arch in "${architectures[@]}"; do
  export BATTUNE_ARCH="$arch"
  ./scripts/rust-build.sh "$configuration" "$arch"
  swift build --build-system native -c "$configuration" --arch "$arch" --product Battune
  swift build --build-system native -c "$configuration" --arch "$arch" --product BattuneHelper
  bin="$(swift build --build-system native -c "$configuration" --arch "$arch" --show-bin-path)"
  mkdir -p "build/bin/$arch/$configuration"
  cp "$bin/Battune" "$bin/BattuneHelper" "build/bin/$arch/$configuration/"
done
app="build/$configuration/Battune.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Library/LaunchDaemons" "$app/Contents/Library/HelperTools"
helperBundle="$app/Contents/Library/HelperTools/BattuneHelper.app"
mkdir -p "$helperBundle/Contents/MacOS" "$helperBundle/Contents/Resources"
# Remove the previous bare helper from this generated bundle on migration.
rm -f "$app/Contents/Library/HelperTools/BattuneHelper"
cp packaging/Helper-Info.plist "$helperBundle/Contents/Info.plist"
cp assets/BattuneHelper.icns "$helperBundle/Contents/Resources/"
cp assets/Battune.icns "$app/Contents/Resources/"
cp packaging/Info.plist "$app/Contents/Info.plist"
for notice in LICENSE THIRD_PARTY_NOTICES.md PRIVACY.md; do cp "$notice" "$app/Contents/Resources/"; done
cp packaging/org.battune.helper.plist "$app/Contents/Library/LaunchDaemons/"
# Embed localized resources in the standard signed resource directory.
rm -rf "$app/Contents/Resources/Battune_Battune.bundle"
cp -R "$bin/Battune_Battune.bundle" "$app/Contents/Resources/"
if [[ -L "$app/Battune_Battune.bundle" ]]; then rm "$app/Battune_Battune.bundle"; fi
if [[ "$architecture" == universal ]]; then
  lipo -create "build/bin/arm64/$configuration/Battune" "build/bin/x86_64/$configuration/Battune" -output "$app/Contents/MacOS/Battune"
  lipo -create "build/bin/arm64/$configuration/BattuneHelper" "build/bin/x86_64/$configuration/BattuneHelper" -output "$helperBundle/Contents/MacOS/BattuneHelper"
else
  cp "$bin/Battune" "$app/Contents/MacOS/"
  cp "$bin/BattuneHelper" "$helperBundle/Contents/MacOS/"
fi
# Local development signature only. Developer signing is an explicit packaging step.
codesign --force --sign - --identifier org.battune.helper "$helperBundle"
codesign --force --sign - --identifier org.battune.app "$app"
codesign --verify --deep --strict "$app"
echo "Built $app ($architecture, $configuration)"
