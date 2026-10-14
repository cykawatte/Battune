# Changelog

## 0.2.0-beta.1 — 2026-10-14

**AlDente Pro parity, closed-lid safety, energy efficiency and a redesigned UI.**

- Fix: limits below 80% no longer leave the battery unprotected when adapter
  mode is blocked (lid closed, helper not validated). Battune now falls back to
  the nearest native macOS ceiling (80%) without cutting adapter input. The
  helper restores adapter input on lid-close and power events immediately
  instead of waiting for its 5-second watchdog. Regression test sweeps 20–79%.
- Fix: the English `Localizable.strings` was malformed, so English systems saw
  raw keys. Lint now validates every strings file; the forbidden-pattern check
  no longer silently skips when ripgrep is missing.
- New: Top Up (100% until unplugged) and Pause (hold the current level), resolved
  in the Rust core; native mode rounds a pause up to the next macOS step.
- New: power flow (adapter → Mac → battery in watts), time to limit / remaining.
  macOS estimates time to 100%, Battune estimates to the active limit.
- New: keep the native macOS limit after quitting (default on), menu-bar detail
  (percentage, watts, temperature, time), MagSafe LED control and Low Power Mode
  profiles (battery/adapter) via fixed, rate-limited helper operations.
- New: `battune://` URL scheme for Shortcuts (limit, top-up, pause, resume).
  Battery-consuming workflows still require confirmation in the app.
- New: schedule templates (weekend full charge, Monday top-up), time picker.
- Efficiency: one cached PowerUI client instead of a new one per read; read-back
  only after an actual write; 5-minute fallback interval while macOS enforces the
  limit (60 s only for adapter workflows); exact one-shot wakeups for schedules;
  lid changes are events, not polls; helper accessory status cached.
- UI: new popover with charge ring, limit marker, power flow, native-step chips
  and quick actions; settings window with sidebar navigation and automatic
  saving; statistics tiles and gradient charts. Logo and menu-bar mark unchanged.
- Core ABI 2: `battune_override`, `battune_estimate`, `battune_native_ceiling`,
  `battune_indicator`. The helper protocol version is 0.2.0-beta.1: reinstall the
  matching helper after updating.

## 0.1.0-beta.1 — 2026-10-11

- Prefer native charge limits even with advanced mode unlocked; preserve them across sleep and after workflows.
- Report fixed-key SMC read access from the actual root helper.
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
