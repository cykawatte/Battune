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
- Native charge control: supported values, write/readback, baseline restoration,
  external changes, crash recovery, corrupt journal, failed recovery, timeout/expired queued requests and native
  coordinator behavior on battery power without temperature data. These use a
  fake OS transport and never write to the real charge service.
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
In this mode, Command-Shift-P opens the actual menu-bar panel for UI inspection.
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

## Menu-bar and slider regression checks

- Open the menu panel repeatedly; its title and padding must stay below the menu
  bar, with no clipped content. Check small displays and multiple display positions.
- Click the desktop, another app, and Battune settings; the panel must close.
  Also check Escape, application switching, and clicking the status item twice.
  Global mouse monitoring must not request Accessibility permission.
- Check the Battune B/slider template mark in light and dark menu bars.
- Drag charge, sailing, temperature, schedule, and workflow sliders. Values should
  update in whole units; sailing lower < upper and resume temperature < stop.
  Restore original values after testing.
- Confirm that the unavailable-control explanation explicitly says these settings
  do not yet affect charging.

2026-10-10 local QA: Debug popover header and full-width settings sliders inspected;
Escape and application switching verified. The vector logo was rendered and
visually inspected. Dragging 80% down to 58% clamped the
resume threshold from 75% to 57%. Test edits were discarded. The UI automation
uses background clicks in other applications, so physical outside-click and
menu-bar-icon checks remain manual checks on the user desktop.

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

## Native hardware check (explicit, outside CI)

On a supported Mac, record the existing system limit, then use Settings → Charging
and save enabled control at 80%. Check the macOS limit in Diagnostics and in System
Settings. Change to 85%; verify both again. Disable or quit Battune and check that
the original limit returns. Reopen to confirm the saved enabled setting applies.
A failed write must show an error and must never show an active limit.

2026-10-11: 15 Rust tests and 28 Swift/integration test groups passed. On the local
Mac16,12, UI writes at 80% and 85% were independently read back from the macOS
service; quitting restored 100%. No administrator privileges were used. This
validates real platform settings, not a complete physical AC charge cycle.

## Advanced-feature follow-up (2026-10-11)

Added nine Swift cases: validation preconditions, rollback, adapter composition
and crash recovery, reserve/sleep recovery, gate generation invalidation,
full coordinator arbitrary-limit/discharge/calibration workflow, backend switching,
exact-hash trust syntax and history CSV/backward-compatible preferences.
Totals: 15 Rust + 37 Swift tests. All hardware writes in these tests use test-only
transports; the live system test reads only.

German Setup, Diagnostics and Statistics inspected in the native app. Live
capacity/temperature/voltage/current/power displayed. CSV was saved using the
actual NSSavePanel and parsed. Administrator prompts and physical adapter writes
must not be counted until explicitly approved and executed.

Final universal Release built and opened on arm64. Installer payload matches the
embedded helper byte for byte; both architecture-specific app/helper CDHashes
match the manifest and satisfy their code requirements using codesign. The local
pkgbuild emits four `write: Permission denied` metadata warnings yet returns
success; expanded payload, root ownership/modes, scripts and signatures were
inspected. Actual installer execution remains an explicit approval/validation gate.
The CLT x86_64 compatibility archive and native-build deprecation warnings remain.

## Approved physical follow-up

Apple Installer successfully installed the prepared package on 2026-10-11.
Production exact-hash XPC and the root CHIE off/on/readback test succeeded.
Independent final reads confirmed adapter enabled and AC connected; macOS
reported charging. No owned recovery journal remained. This resolves installer
execution and the bounded switching test, not full-cycle or sleep/crash validation.
See HARDWARE_VALIDATION_2026-10-11.md for scope and evidence.
