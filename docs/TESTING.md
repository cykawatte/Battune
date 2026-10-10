# Testing

```sh
./scripts/lint.sh
./scripts/test.sh
./scripts/build.sh
./scripts/build.sh release
```

Lint checks Rust formatting/clippy, Swift formatting, shell syntax, plist syntax,
forbidden production placeholders and whitespace errors. Tests need no privileged
helper, real charge writes, network connection or Apple development certificate.

## Layers

- Rust: charge boundaries including 20/100, all valid sailing combinations,
  thermal hysteresis/missing sensor, discharge target/unplug, disabled reset,
  unsupported capabilities, calibration progression/cancellation/timeouts,
  weekly schedule priorities, malformed FFI flags/pointers and ABI layouts.
- Swift: settings validation and corrupt persistence, calibration restart journal,
  capabilities/error decoding, view-model errors, history retention/deduplication,
  local-time schedule bridge including spring/fall DST and timezone changes.
- Integration: real Swift-to-Rust ABI; mock hardware lifecycle through coordinator;
  success-only acknowledgement, failures, helper loss, sleep/wake, cancellation.
- XPC: actual anonymous unprivileged connection; status serialization and rejected
  charge-limit argument; code requirement parsing and unsigned client rejection;
  mock control-lease expiry requests reset exactly once.
- IOKit: a read-only smoke test accepts explicit unknowns on hosts without batteries.

The Swift tests are a small standalone executable with throwing checks and a
nonzero failure exit code. Unlike `assert`, checks survive optimized builds. This
avoids XCTest, which is absent from the available CLT environment. Run tests via
`test.sh`, not `swift test`. Mocks are confined to this test target and are not
linked into the application/helper or copied into app bundles.

## Explicit developer diagnostics

Quit an existing instance, then run:

```sh
open build/debug/Battune.app --args --diagnostics
```

Debug opens the diagnostics tab directly. It reads snapshot/capability/backend
information and exposes the same explicit, validated reset and workflow controls.
It performs no automatic write or helper installation. Release ignores this flag
and excludes the developer diagnostic label; normal user diagnostics remain available.

## Manual development checks

1. Launch the Debug app. Read onboarding; leave charge control disabled.
2. Check menu-bar percentage, popover, keyboard shortcuts and settings tabs.
3. Check light/dark modes, VoiceOver, German/English and language restart.
4. Save a charge limit; relaunch and verify persistence. Invalid sailing/thermal
   settings must be rejected. No helper installation should occur automatically.
5. Connect/disconnect AC and sleep/wake. Verify fresh displayed state without a
   burst of timer events. Unknown temperature/capacity should stay unknown.
6. Check diagnostics are copyable and contain no private identifiers.
7. Check unsupported discharge/calibration/reset buttons are disabled and explained.
8. Enable/disable history and test deletion only with disposable test history.
9. Launch at login and notification permission require explicit user choices.

## Hardware validation gate

Only after adding a reviewed real backend, on a designated test machine:

- Sign app/helper with matching Team ID. Test successful registration, user denial,
  missing helper, crash, wrong identifier/team and unsigned attacker connections.
- Verify readback for every allowed operation and reset, including invalid limits.
- Hold at each boundary; test sailing, hot/missing sensors, discharge completion
  and cancellation. Keep thermal limits conservative and firmware safeguards active.
- Run calibration end to end, cancellation in every phase, restart interruption,
  AC removal, helper kill and lease expiration.
- Test weekly conflicts, midnight, both DST transitions, timezone changes and wake
  after missed activations. Scheduled discharge must not replay after restart.
- Verify reset before unregister/uninstall; record exactly what it restored.

Never run charge-control operations in CI. A successful mock test is not evidence
that an SMC key is safe. Full Xcode, macOS 13 runtime, real Intel hardware, signed
helper lifecycle and physical power events remain separately recorded manual gates.
