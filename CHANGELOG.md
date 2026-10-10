# Changelog

## UI follow-up — 2026-10-10

- Measure the menu-bar popover before presentation so its header stays visible.
- Dismiss on outside mouse clicks, Escape, or application deactivation; release
  monitors and hosted content when closed.
- Use a monochrome vector Battune B/slider mark in the menu bar.
- Replace numeric steppers with full-width sliders and live values. Keep sailing
  and temperature thresholds consistent while dragging.
- Explain that charge control is not implemented in this development version;
  installing the helper alone does not enable it.

## 0.1.0-dev — 2026-10-09

First local development implementation. Native menu-bar UI with English/German
localization; deterministic Rust policy and C ABI; IOKit monitoring; validated
settings and bounded history; authenticated XPC helper; architecture-separated
read-only backends; schedules, sailing, thermal, discharge and calibration flows;
mock and integration tests; Debug/Release/universal build tooling; draft local
packaging and CI; architecture, security, hardware and performance documentation.

Real charge/discharge/reset writes are not supported or physically validated.
No public release, remote push, notarization or privileged installation performed.
