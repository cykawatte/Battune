# Battune 0.1.0-dev — final engineering report

Completed locally: 2026-10-10, Europe/Berlin.

## Release readiness

**DEVELOPMENT READY**, with a strict scope: native monitoring, deterministic
policy, mock hardware workflows, FFI/XPC integration and local build tooling.
**Not a publicly releasable or physically validated charge controller. Real
charging/discharging/reset writes are not implemented in production backends.**
Those backends deliberately return Unsupported; no success is simulated.

## Implemented

- AppKit menu-bar lifecycle and popover; SwiftUI settings with native controls,
  system appearance, accessible labels and keyboard shortcuts.
- English and German localization, short onboarding, configuration persistence,
  optional launch at login and opt-in notification authorization.
- Real IOKit internal-battery percentage, AC/charging state, cycle count and
  optional sensor/capacity fields. Missing readings stay unknown.
- Power-source notifications, coalescing, one tolerant 60-second fallback,
  sleep/wake and clock/timezone handling.
- Deterministic 20–100% charge policy, default 80%, sailing hysteresis, thermal
  hysteresis/missing-sensor handling and discharge-to-target decisions.
- Explicit cancellable calibration: full charge, stabilization, discharge,
  recharge and restoration. Persisted interruption recovery; no automatic restart.
- Weekly plans, conflict resolution, timezone/midnight/DST conversion, current
  plan on wake and one-shot scheduled discharge activation tokens.
- Serial command execution, success-only acknowledgement, deduplication, stale
  transaction cancellation, bounded error recovery and suspension after failure.
- Narrow XPC protocol, OS-enforced signing requirements in both directions,
  argument/reply validation and no unsigned privilege bypass.
- Helper-side serialization, rate limiting and a 120-second active-control lease
  that requests reset if the controller disappears.
- Separate Apple Silicon and Intel read-only backends; test-only MockBackend.
- Bounded atomic JSON history, normal five-minute sampling plus power transitions,
  batched writes, pruning, chart, health/capacity display and history deletion.
- Copyable non-sensitive diagnostics, visible reset control, helper registration
  controls, and an explicit Debug `--diagnostics` launch mode.
- Debug/Release app bundles, embedded helper/launchd plist, optional universal
  build, local ad-hoc signing, developer-signing-ready packaging scripts, ZIP/DMG
  preparation and an unpublished Homebrew template.
- Six ADRs, architecture/control/security/privacy/testing/performance/release
  documentation, MIT license, notices, contributing policy and macOS CI workflow.

## Architecture

Swift/AppKit/SwiftUI owns presentation, lifecycle, system reads and persistence.
The dependency-free Rust library owns deterministic charging, calibration and
schedule-priority policy. A fixed-width value C ABI links the two. Swift connects
to the privileged Swift daemon over a narrow authenticated XPC interface.

The helper exposes hardware operations only; no charge-policy decisions live
there. No arbitrary SMC key, shell execution, caller path or generic root API
exists. Production backends advertise only the operations they can actually
perform. Mocks are confined to the separate test executable and absent from app
and helper bundles. There are no external Swift packages or Rust crates.

## Tests

Final executed quality gates:

| Suite / check | Result |
|---|---|
| cargo fmt --check | Passed |
| cargo clippy --all-targets --all-features -- -D warnings | Passed |
| Rust unit/FFI tests | **15 passed, 0 failed** |
| Swift/native integration runner | **21 passed, 0 failed** |
| Swift formatting, shell syntax and plist lint | Passed |
| Debug build, including helper | Passed, arm64 |
| Release build, including helper | Passed, arm64 + x86_64 universal |
| Ad-hoc codesign --verify --deep --strict | Passed for Debug and Release |
| Universal executable slices, app and helper | Verified arm64 and x86_64 |
| Production placeholder/unsafe-pattern and tracked-artifact inspection | Passed |

Rust tests include exhaustive valid sailing boundaries, exact charge thresholds,
thermal priorities, unknown sensors, discharge, calibration and FFI layouts.
Swift tests include persistence corruption, history bounds, DST rollback/gap,
full mock controller transitions, hardware failure/recovery, helper loss,
sleep/wake, stale-command cancellation and success-only acknowledgement.
An actual anonymous unprivileged XPC connection verifies wire serialization and
argument rejection; other tests check signing syntax/unsigned rejection and
expired-lease reset. A read-only IOKit test runs against the local machine.

The installed Command Line Tools lack XCTest. The Swift test executable uses
explicit checks with a nonzero failure exit code, also valid under optimization.
No tests were silently skipped. Full signed privileged XPC, Xcode GUI and physical
write tests are explicitly outside the executed suites.

## Build and UI verification

Environment: Mac16,12, arm64, macOS 27.0.1 (26A434), SDK 27.0, Swift 6.4,
Rust 1.99.0. Rust was installed from the official rustup source without modifying
shell startup files. No developer code-signing identities were available.

Both app and helper compile. The universal Release contains both architectures;
only the arm64 slice was launched on this machine. The SDK warns that its Swift
compatibility-packs archive has no x86_64 slice. Linking succeeds, but Intel
runtime support remains unverified. SwiftPM native-build deprecation warnings
are also documented. No compiler errors or Rust clippy warnings remain.

The app was launched, German onboarding/settings/charging/statistics/diagnostics
were inspected, real readings were visible, and unsupported actions were disabled.
The explicit Debug diagnostic launch opened the correct tab. Command-Q exited the
app through its lifecycle handler. Light-mode, VoiceOver, login/notification
permissions, physical AC/sleep events and macOS 13 remain manual checks.

Full Xcode is not installed. The supplied Xcode wrapper was syntax-checked;
`xcodebuild` execution is deferred to an environment with full Xcode. CI is
prepared locally and has not been run on GitHub.

## Performance

Measured optimized Release commit `89f8873`, six ten-second samples after closing
the settings window:

- `ps` CPU readings: 0.0% in all six samples, rounded.
- Cumulative CPU: +0.05 seconds over approximately 50 seconds, roughly 0.10% of
  one core. This is not proof of sustained <0.1% idle CPU.
- RSS: 95,552–95,680 KiB, about 93.3–93.4 MiB. The preferred <40 MB budget is unmet.
- Rust microbenchmark: 1,000,000 evaluations in 12.291083 ms.
- Final universal app bundle: 5,196 KiB allocated, approximately 5.1 MiB.
- Wakeups, cold startup, network/disk traces and long-run energy: not measured.

No numbers are inferred for real charging. Physical control performance:
**Not yet measured on real hardware.** See docs/PERFORMANCE.md for procedure,
measurement scope and the initial pre-optimization comparison.

## Hardware validation

| Level | Evidence |
|---|---|
| Implemented | Policy, UI, system reads, helper boundary and capability handling |
| Compiled | Debug arm64; Release arm64/x86_64; app, core and helper |
| Unit / mock tested | Charging, sailing, thermal, discharge, calibration, recovery |
| Integration tested | Swift/Rust, coordinator/mock, unprivileged XPC wire format |
| Real hardware read | Battery percentage, AC/charging state and cycle count on Mac16,12 |
| Real charge/discharge/reset writes | **Not implemented / not tested** |

The host did not expose reliable temperature or raw mAh capacities through the
selected properties. The UI shows unknown. No SMC experiment, privileged helper
registration or automatic battery manipulation was performed.

## Known limitations and security

A safely validated charge-control API/backend is still required before this app
can change charging on a physical Mac. Historical keys are not guessed. A real
backend must establish key semantics, readback, reset and firmware behavior,
including helper termination. A dead helper cannot execute a software lease timer.

Unsigned/ad-hoc code cannot authenticate to the production helper. An Apple-issued
matching Team ID and bundle identity are required. A compromised validly signed
GUI is limited to the allowed battery operations but remains a trust risk.
Sensitive diagnostics and arbitrary root operations are excluded. Settings are
validated and corrupt state disables control. No telemetry or runtime network
client is included. No credentials, build artifacts or local paths are committed.

Further limitations: memory budget unmet; minimum-OS/Intel runtime and signed
ServiceManagement lifecycle untested; calibration interrupts rather than resumes
after restart; last history batch can be lost on crash; packaging is prepared but
not executed or published; no notarization or public-release claims.

## Manual validation required before publishing

1. Implement/review real per-capability backends, then validate physical write,
   readback and reset behavior on designated devices.
2. Test signed helper registration, approval denial, wrong-team/identifier rejection,
   crash/reconnect, lease expiry and forced daemon termination.
3. Validate actual charge/sailing/thermal/discharge/calibration workflows,
   cancellation at every phase, AC changes, sleep/wake and competing OS management.
4. Test macOS 13 and later versions, real Intel machines and the Xcode workflow.
5. Complete accessibility, English/light-mode, login and notification QA.
6. Run long-duration CPU/RAM/wakeup/startup/energy and I/O measurements; address
   the memory deviation and verify all claimed budgets.
7. Review source/licenses/security, version the public build, sign/notarize only
   with explicit authorization and test reset/uninstall on a clean system.

## Git

Branch: `codex/battune-development`. No remote push, PR, public release or upload.
The implementation adds **10 commits** including the enclosing final documentation
commit (**11 total**, including the original bootstrap). Its exact hash is obtained
with `git rev-parse --short HEAD`; it cannot be embedded in its own content hash.
The final response reports that hash after commit. Working tree is checked clean
at handoff; generated local builds and logs remain ignored.

History immediately before this final report commit:

```text
cb607ba feat: add diagnostic launch mode and embed distribution notices
1125a85 fix: cancel stale workflow commands and capture power transitions
89f8873 perf: release hidden views and cache immutable signing identity
42dba91 build: add Debug, Release and universal app bundles with local packaging
9a1b850 fix: harden recovery, DST scheduling and XPC integration tests
72095ab feat(macos): connect native UI, battery monitoring and authenticated helper
104524e feat(ffi): expose validated value ABI for charging, schedules and calibration
2b7a59d feat(core): implement deterministic charging, calibration and schedules
716b413 docs: define architecture, safety boundaries and implementation plan
af39409 Initialize Battune project
```

## Start locally

```sh
cd /path/to/Battune
./scripts/build.sh
open build/debug/Battune.app
```

Or launch the already-built universal Release with
`open build/release/Battune.app`. Quit any running instance before switching builds.
To validate again, run `./scripts/lint.sh` and `./scripts/test.sh`.
