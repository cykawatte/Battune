# Pro parity, closed-lid safety and efficiency — 2026-10-14

Battune 0.2.0-beta.1. Host: Mac16,12, macOS 27.0.1 (26A434), AlDente installed
from `/Applications/AlDente.app` (arm64 slice SHA-256
`bf645423f02f9a9f93f67fd55d213ccb5b043e0286f1bfd3c11b9269f52c80db`).

## Method

AlDente was examined only as a shipped artifact, read-only, to learn *which*
features exist and *which* hardware interfaces are involved. No AlDente code,
assets or text were copied. Tools: REA 6.4.0 `inspect-macho` (Evidence
`ev_3b0ab0315953b80ab4679c30ccc0b698baaa8982c7458f800cc7447103443685`),
`Info.plist`, compiled string tables, the helper's exported selectors, and
AlDente's own preferences domain. No decompiler (Ghidra/IDA/Hopper) was
available, so no control flow was reconstructed; statements about AlDente's
behaviour below are **inferences** from strings and settings, not observations.

## Observations

| Evidence | Finding |
| --- | --- |
| `NSUserActivityTypes` | Intents: calibrate, discharge, start/stop charging, set/get limit, percentage, temperature, state, Low/High Power Mode, MagSafe LED. |
| Helper selectors | Generic `setSMCByte…`/`readSMC…`, `disableSleepWhenClosed…`, `setLowPowerMode…`, `sleepNow`. |
| Key strings | `CHTE`, `CH0B/CH0C/CH0I`, `CHIE`, `ACLC`, `MSLD`, `BCLM`, `CHWA`, `PSTR`, `CHSC/CHCC/CHNC/CHDB`. |
| Preferences | `useTahoeNativeLimit = 1`, `allowChargeLimitsBelow80 = 0`, `sailingMode`, `heatProtectMode`, `completelyDisableSleep`, `exitInhibitCharge`. |
| UI text | "The currently available charge control method does not support lower limits." |
| Read-only SMC probe on this Mac | `CHTE`, `CH0B`, `CH0C`, `CHWA`, `BCLM` absent (SMC 0x84). `CHIE` (1 byte), `ACLC` (ui8), `PSTR` (flt), `CHSC/CHCC` (ui8) present. |

Inference: on this firmware neither app has a charge-inhibit key. AlDente uses
the same native macOS limit as Battune and gates sub-80% limits; it keeps the
Mac awake during clamshell discharge. Battune never suppresses lid-close sleep.

## The reported problem below 80%

No Battune crash report or abnormal exit exists in the retained logs (the last
session on 14 Oct ended with a normal `replyToApplicationShouldTerminate:YES`).
The earlier report matches the documented 12 Oct finding: holding a sub-80%
limit cuts adapter input (`CHIE`), which can lock or suspend a docked Mac when
the lid closes. Build 4 (commit `95b4ea9`) already refused adapter cuts with a
closed lid; it was **not installed** on this Mac (installed app: build 3).

0.2 closes the remaining gaps:

1. With adapter mode blocked (lid closed, helper validation pending or helper
   missing) Battune previously left the previous macOS limit in place (often
   100%). It now sets the nearest native ceiling (80%) and shows
   "Protected by the macOS limit".
2. The helper restores adapter input on `kIOPMMessageClamshellStateChange` and
   power-source events immediately; the watchdog is only a 10 s fallback.
3. The app observes the same lid event and re-routes at once.
4. A regression test sweeps every limit 20–79% with a closed lid: zero adapter
   cuts, native 80% ceiling, cut on open lid, no new cut after closing again.

Physical validation of 1–3 requires installing the 0.2 app **and** helper.

## Feature matrix

| AlDente Pro | Battune 0.2 | Notes |
| --- | --- | --- |
| Charge limiter | ✓ | native 80–100% steps; 20–100% with helper |
| Sailing, heat protection | ✓ | adapter mode; macOS handles both natively |
| Discharge, calibration | ✓ | helper; explicit confirmation |
| Top up | ✓ new | ends on unplug (Rust core) |
| Pause charging | ✓ new | native: rounded up to next step |
| Schedules + templates | ✓ new templates | weekly, DST-safe, priority |
| Power flow, time estimates | ✓ new | PowerTelemetryData; estimate to limit |
| MagSafe LED | ✓ new | fixed values 0/1/3/4, read-back |
| Low Power Mode profiles | ✓ new | fixed `pmset -b/-c lowpowermode` |
| Menu bar stats | ✓ new | %, W, °C, time |
| Stop charging when app closed | ✓ new | native limit kept after quit (default) |
| Shortcuts | ✓ URL scheme | App Intents need an Xcode build; not yet |
| Disable sleep until limit | ✗ by design | would keep a closed Mac awake |
| High Power Mode | ✗ | not available on this hardware |
| Apps using significant energy | ✗ | not a charging feature |

## Efficiency changes

| Before | After |
| --- | --- |
| New `PowerUISmartChargeClient` (and daemon connection) per read, 3–4 per tick | one validated, cached client |
| Read-back after every evaluation | only after an actual write |
| 60 s timer always | 300 s while macOS enforces the limit, 60 s for adapter workflows, ¼ tolerance |
| Schedules noticed up to 60 s late | exact one-shot timer at the next activation |
| Lid state polled every 5 s by the helper | lid and power events, 10 s fallback |
| Helper status every tick | accessory capability cached 10 min unless advanced |

Long-duration CPU/energy figures were **not** measured in this iteration; see
`docs/PERFORMANCE.md` for the measurement procedure.

## Verification

- `./scripts/lint.sh`, `./scripts/test.sh` (22 Rust + 47 Swift groups),
  `./scripts/build.sh release universal`: pass.
- UI rendered with live data in light and dark appearance via the Debug-only
  `--render-ui <dir>` mode (excluded from Release builds).
- Not verified on hardware: MagSafe `ACLC` writes, Low Power Mode via helper,
  event-driven lid restore. These need the 0.2 helper installed with approval.
