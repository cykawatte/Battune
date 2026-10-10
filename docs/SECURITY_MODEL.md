# Security model

## Trust boundary

The GUI runs as the logged-in user. Only the optional SMAppService LaunchDaemon
has root privileges. It accepts fixed charge-limit, charging-gate, discharge-gate,
reset, read/status and control-lease methods. No shell, command, path, file-write,
or arbitrary SMC key/value argument is exposed. The app bundle contains the helper
and launchd plist; registration is an explicit action requiring system approval.

Before resuming each connection, the helper configures macOS 13's
`NSXPCConnection.setCodeSigningRequirement`. The OS checks incoming messages against
an Apple-anchored signature, exact app identifier and the same Team ID found in the
helper's own validated signature. The client likewise authenticates the helper.
Unsigned/ad-hoc code has no Team ID and is rejected; root callers are rejected.
There is no development bypass, private audit-token access or PID-only lookup race.

## Threats and mitigations

| Threat | Boundary / mitigation | Remaining risk |
|---|---|---|
| Malicious local client | OS-enforced message signing requirement, exact identifiers and team | Compromised validly signed app can use allowed operations |
| Malformed XPC | Typed scalar arguments; limits validated at the helper; fixed bounded data replies | Framework/compiler bugs remain possible |
| Arbitrary SMC writes | No API for keys/bytes; production backends reject all mutations | A future backend needs independent audit |
| Privilege escalation | No shell, caller paths, file writing or configurable helper code loading | Signing/distribution and launchd lifecycle require physical review |
| Repeated commands | Serialized gate, confirmed-value deduplication, token bucket | Authenticated read traffic can still cause local load |
| Compromised UI | Allowed operations limited to battery controls and reset | Can request supported controls repeatedly within rate limits |
| Corrupt saved state | Schema and range validation; no hardware state trusted from preferences | Loss of unflushed history is possible |
| App crash / disconnection | Client timeout; fail-safe reset; 120-second expiring lease | A killed helper cannot run recovery; real backend must prove firmware-safe behavior |
| Stale work after sleep/settings changes | Coalesced evaluations, cancellation generation, fresh snapshot after wake | One already-submitted operation may finish before reset |

## Safety properties

Capabilities originate from the backend, not the UI. No real write capability is
advertised in this development version. Failed operations remain errors; reset
cannot return success for an unimplemented backend. Confirmations are cached only
after success. The backend contract requires real readback before acknowledging a
future mutation where technically possible. Unknown sensors do not become zero.
Diagnostics exclude names, paths, serial numbers and UUIDs.

The lease is a hardware safety mechanism, not charge policy. It is only armed
following a successful mutation and renewed following a successful evaluation.
No timer is active in the read-only helper. Expiry makes one reset attempt and
logs failure without a write loop. An anonymous, unprivileged XPC test listener is
compiled only in the standalone test executable, never in Battune.app.

## Verification and unresolved work

Tested: malformed values/replies, mock rate limits/deduplication, timeout-safe
completion design, expired lease reset, signing requirement syntax, unsigned
rejection, anonymous XPC serialization and controller recovery. No suitable
signing identity was available: real signed connection acceptance/rejection,
SMAppService registration and privileged launchd lifecycle remain manual gates.
The app is not notarized and must not be publicly distributed as validated control software.

## Primary references

- [Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Apple NSXPCConnection signing requirement](https://developer.apple.com/documentation/foundation/nsxpcconnection/setcodesigningrequirement(_:))
- [Apple code requirement language](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html)

The installed SDK's NSXPCConnection.h and Security headers were also consulted.
