# Changelog

## 0.1.0-beta.1 — 2026-10-11

- First installable beta: universal app and matching privileged helper in one installer.
- Battune app icon, separate helper icon and branded installer.
- Short German/English first-run tutorial with privileged-mode setup and replay.
- Advanced 20–100% limits, discharge target, calibration, statistics and diagnostics.
- Exact app/helper signature pairing, upgrade recovery and package validation in CI.
- Beta remains ad-hoc signed; notarization, Intel runtime and full hardware cycles remain final-release gates.

## Native hardware control — 2026-10-11

- Real macOS charge-limit writes through the OS PowerUI service, without a root
  helper. Detect supported limits and verify every write by reading it back.
- Durable recovery journal restores the previous native limit on disable/quit;
  handles restarts, failures and external changes.
- Native mode for settings, popover and schedules; sliders snap to actual supported
  limits. Clearly distinguish native protection from unsupported direct controls.
- Seven additional test groups cover write/readback/restore and error recovery.
- Physical setting writes/readback verified on Mac16,12 / macOS 27.0.1.

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
