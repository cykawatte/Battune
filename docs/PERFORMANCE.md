# Performance

Targets are engineering budgets, not claims. No benchmark numbers are simulated.

## Procedure and environment

Local measurements on 2026-10-09, Mac16,12, arm64, macOS 27.0.1 (26A434), SDK
27.0, Swift 6.4, Rust 1.99.0. Universal Release app, ad-hoc signed, running its
arm64 slice. No privileged helper; control unsupported. The settings window had
been opened and closed; app remained in the menu bar. Other desktop applications
were running, so these are coarse development measurements, not a controlled lab.

Run `./scripts/benchmark.sh PID` against the actual Battune process. It records
six `ps` samples ten seconds apart, RSS, cumulative process CPU time, app disk size
and a release-mode Rust microbenchmark. The timer interval is 60 seconds with
15 seconds tolerance. Re-run on AC and battery for longer periods before release.

## Measured results

Optimized measurement commit: `89f8873` (before the final cancellation/history
regression fix; those changes did not form part of this timed sample).

| Metric | Observed | Target / assessment |
|---|---|---|
| CPU, six sampled `ps` values | 0.0% in all six samples (rounded) | <0.1% target; short/coarse sampling does not establish sustained compliance |
| Cumulative CPU between first/last sample | 0.60 → 0.65 seconds over ~50 seconds | Approximately 0.10% of one core; longer Instruments measurement required |
| RSS | 95,552–95,680 KiB (~93.3–93.4 MiB) | Preferred <40 MB is **not met** |
| Universal Release bundle | 5,156 KiB (~5.0 MiB allocated) at measured commit | <15 MB preferred: met for this build |
| Rust policy microbenchmark | 1,000,000 evaluations in 12.291083 ms | Microbenchmark only; not app startup or hardware latency |
| Background wakeups | Not measured | <2/minute target not established |
| Cold app startup | Not measured | <500 ms preferred not established |
| Network packets / disk I/O / energy impact | Not instrumented | Source has no runtime network client; no measured traffic claim |

The first pre-optimization sample (settings closed but view trees retained) showed
RSS 97,552–107,312 KiB and occasional sampled CPU activity. Measured evidence led
to releasing hidden view trees and caching the immutable process signing identity.
The second sample above is the reported result, not a guarantee on other machines.
SwiftUI/AppKit caches may retain memory after windows close; memory remains a
known deviation, not an invented success.

## Structural controls

- IOPS notifications and a single coalescible fallback timer; no one-second poll.
- No periodic history timer; five-minute sampling plus meaningful power events.
- Batch history writes, skip unchanged readings, bounded retention, flush on sleep/exit.
- Serial, deduplicated hardware transactions and bounded recovery.
- No animations, web views, telemetry, update checker or runtime dependencies.
- No helper timer unless a real operation has armed a control lease.

## Required follow-up measurement

Use Instruments Time Profiler, Allocations and Energy Log with all windows closed
for at least 30 minutes, including a schedule boundary, sleep/wake, AC transitions
and a validated helper. Use fs_usage/network tracing without recording unrelated
private process data. Measure warm/cold startup separately. Record per-architecture,
OS, app/backend version and whether the window was ever opened. Verify idle write
and wakeup budgets rather than extrapolating from the Rust microbenchmark.

Physical charging-control energy/performance: **Not yet measured on real hardware.**
