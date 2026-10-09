#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"
export BATTUNE_ARCH="$(uname -m)"
export BATTUNE_CONFIGURATION=debug
cargo test --locked --manifest-path core/Cargo.toml
./scripts/rust-build.sh debug "$BATTUNE_ARCH"
swift run --build-system native -c debug --arch "$BATTUNE_ARCH" BattuneTests
