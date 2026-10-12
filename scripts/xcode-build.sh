#!/bin/bash
set -euo pipefail
cd "${SRCROOT:?}"
case "${CONFIGURATION:-Debug}" in Release) configuration=release;; *) configuration=debug;; esac
./scripts/build.sh "$configuration" "${BATTUNE_BUILD_ARCH:-$(uname -m)}"
mkdir -p "${TARGET_BUILD_DIR:?}"
ditto "build/$configuration/Battune.app" "$TARGET_BUILD_DIR/Battune.app"
