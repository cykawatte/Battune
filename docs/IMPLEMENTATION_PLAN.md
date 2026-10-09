# Development implementation plan

1. Record architecture, safety invariants and environment.
2. Implement dependency-free Rust policy, calibration and weekly schedules with tests.
3. Expose a value-based C ABI; integrate with Swift Package Manager and native build scripts.
4. Implement IOKit reads, event monitoring, bounded history and validated persistence.
5. Implement authenticated XPC service, capability-driven backends and helper registration.
6. Connect native menu bar, settings, workflows and diagnostics to the same controller.
7. Exercise mock failures, integration, Debug/Release builds; document hardware boundaries.
8. Add CI, local packaging and an honest final engineering report.

No remote publication, privileged installation or hardware writes during development.

## Discovery (2026-10-09)

Existing repository: one initial commit, no application code. Host arm64, macOS
27.0.1 (26A434), Command Line Tools, SDK 27.0, Swift 6.4. Full Xcode and
code-signing identities absent. Rust absent initially; install stable via rustup.
The app will build with CLT through SwiftPM and bundle scripts; an Xcode wrapper
will invoke the same reproducible pipeline. Physical charging experiments are
out of scope without a validated hardware backend.
