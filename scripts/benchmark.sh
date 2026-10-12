#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"
echo 'Environment (no serial numbers or user identifiers):'
sw_vers
uname -m
sysctl -n hw.model
cargo run --locked --release --manifest-path core/Cargo.toml --example benchmark
if [[ -d build/release/Battune.app ]]; then du -sk build/release/Battune.app; fi
if [[ -n "${1:-}" ]]; then
  case "$1" in *[!0-9]*|'') exit 2;; esac
  echo 'Six 10-second samples: CPU percent / resident KB / cumulative CPU time'
  for sample in 1 2 3 4 5 6; do
    sleep 10
    ps -p "$1" -o pcpu=,rss=,time=
  done
fi
echo 'Wakeups, energy impact, cold startup and network/disk traces require Instruments; not measured by this script.'
