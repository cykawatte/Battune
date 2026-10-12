# Contributing

Use native system frameworks and the Rust standard library before adding a dependency.
Keep policy deterministic, helper operations narrow, and unsupported features honest.
Do not copy proprietary code or import code without reviewing license compatibility.

Start from README's developer setup. Use a focused branch and Conventional Commits.
Before a significant commit run `scripts/lint.sh`, `scripts/test.sh` and relevant
Debug/Release builds. Inspect the diff for unrelated edits, machine paths, secrets,
generated artifacts and accidental hardware calls. Never run real charge writes
in CI. Add regression tests for safety transitions, not tests mirroring UI labels.

Swift source uses `swift format`. Package.swift excludes itself from formatting
because the tools-version directive must stay on the first line. Rust uses rustfmt
and warning-free clippy. Avoid force unwraps, forced casts and implicit global state.
Production Swift logging uses OSLog. Keep files cohesive and usually below 400 lines.

New hardware support needs a written capability/reset contract, physical readback
and failure evidence in HARDWARE_SUPPORT.md. Model names alone do not establish
capabilities. An unsupported operation must remain an explicit typed error.

Report ordinary bugs with sanitized diagnostics and reproducible steps. Use the
private channel in SECURITY.md for sensitive vulnerability details. Public release,
signing and publication are separate authorized actions; build scripts do not push.
