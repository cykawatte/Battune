#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"
configuration="${1:-debug}"
arch="${2:-$(uname -m)}"
case "$arch" in arm64) target=aarch64-apple-darwin;; x86_64) target=x86_64-apple-darwin;; *) exit 2;; esac
if [[ "$configuration" == release ]]; then
  MACOSX_DEPLOYMENT_TARGET=13.0 cargo build --locked --manifest-path core/Cargo.toml --target "$target" --release
else
  MACOSX_DEPLOYMENT_TARGET=13.0 cargo build --locked --manifest-path core/Cargo.toml --target "$target"
fi
mkdir -p "build/rust/$arch/$configuration"
cp "core/target/$target/$configuration/libbattune_core.a" "build/rust/$arch/$configuration/"
