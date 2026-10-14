#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"
cargo fmt --manifest-path core/Cargo.toml --check
cargo clippy --locked --manifest-path core/Cargo.toml --all-targets --all-features -- -D warnings
swift format lint --strict --recursive Package.swift app helper shared tests scripts/icons
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -fsyntax-only \
  -I shared/NativeCharge/include shared/NativeCharge/NativeCharge.m
xcrun clang -Wall -Wextra -Werror -fsyntax-only -I shared/NativeCharge/include shared/NativeCharge/BattuneSMC.c
for script in scripts/*.sh; do bash -n "$script"; done
# A malformed .strings file silently shows raw keys for that language.
plutil -lint app/Battune/Localization/*.lproj/Localizable.strings
plutil -lint packaging/Info.plist packaging/Helper-Info.plist packaging/org.battune.helper.plist Battune.xcodeproj/project.pbxproj
# grep is always available; ripgrep is optional on contributor machines.
if grep -rnE 'try!|as!|fatalError\(|TODO|FIXME' app helper shared core/src; then
  echo 'Forbidden production pattern found' >&2; exit 1
fi
git diff --check
