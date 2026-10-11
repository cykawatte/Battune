# Security model

The GUI runs as the logged-in user. Native charging loads Apple's PowerUI from
a fixed system path, checks its runtime ABI, accepts only reported limits, and
verifies writes. A user-owned journal restores the original setting only while
Battune still owns it. It is never interpreted by the root helper.

## Privileged boundary

The advanced Apple Silicon backend is a root LaunchDaemon. Its only hardware
write is the fixed one-byte CHIE adapter gate: 0 enables, 8 disables. Metadata,
allowed previous values and readback are checked. There is no shell, arbitrary
key/value, caller-supplied path or general root API. Intel remains read-only.

Both XPC peers set an OS-enforced code signing requirement before resuming:

- Apple-signed distribution builds: exact bundle identifiers and matching validated Team ID.
- Local ad-hoc builds: an administrator-installed, root-owned manifest pins the
  exact app/helper CDHashes. Both identifier and hash must match. The process also
  checks its own hash. Unknown hashes and unsigned callers cannot connect.
- Manifest and parent paths must be root-owned, not group/world writable and not
  symlinks. Bounded reads use O_NOFOLLOW and fstat. Hashes are validated before
  entering the requirement language. Root GUI callers are rejected.

The local package is generated beside, not inside, the signed app. Installing a
new binary requires a matching package and fresh administrator approval. Package
creation itself changes no system state. Publishing, notarization and credentials
are outside this local workflow.

## Hardware safety

Capabilities remain disabled until a user-confirmed off/on/readback validation
succeeds with a physical cable attached, SOC >=30%, temperature <40°C and a
registered system sleep callback. This check is serialized and rate limited in
the same gate as other writes. Reset remains available after validation is revoked.

A root journal is committed before disabling the adapter. Recovery enables only
an adapter state owned by this journal. Startup recovers before accepting XPC.
The native limit is temporarily released to 100% for advanced control, then
restored when advanced mode is disabled or reset.

- Policy: independent charge hysteresis, thermal thresholds, discharge target and calibration.
- Helper safety: 120-second renewable control lease and a five-second watchdog
  while adapter ownership exists. Reserve <=15%, missing/unsafe sensor, physical
  disconnect or revoked validation triggers recovery. Failed recovery remains
  journaled and is retried by the watchdog.
- Sleep: restore before acknowledging the power transition; revoke validation.
  No sleep suppression or global power-setting changes. Calibration interrupts.
- App/helper crash: launchd restarts a killed helper and startup attempts recovery.
  If launchd is stopped or hardware stops accepting commands, software cannot
  guarantee recovery; battery firmware protections remain the final boundary.
- Command confirmations cache only successful results. Backend generations
  invalidate stale caches after out-of-band recovery.

The fixed scalar XPC interface validates input and bounds replies. Gate writes
have a burst budget of 12 and refill at 12/minute; reset bypasses exhaustion.
Explicit validation consumes two tokens. Test mocks and the anonymous XPC test
listener are separate from the shipping binaries.

## Evidence and remaining gates

Automated tests cover validation preconditions, failure rollback, journal crash
recovery, reserve/sleep handling, restored-state cache invalidation, full simulated
calibration, exact-hash requirement syntax, controller routing and existing
native/XPC/policy safety. The app's diagnostic probe is read-only.

Privileged installation, real authenticated local-pinned XPC, real CHIE off/on,
physical charging/discharge, helper kill/restart and sleep restoration await
user approval and hardware validation. Neither compilation nor mocked success
is advertised as that evidence. No public-release readiness is claimed.

References: [Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice),
[NSXPCConnection signing requirements](https://developer.apple.com/documentation/foundation/nsxpcconnection/setcodesigningrequirement(_:)),
[Apple requirement language](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html).
