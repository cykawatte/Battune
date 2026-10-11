# Hardware support and validation matrix

Do not equate compilation, simulation and physical charging validation.

| Architecture | Device | macOS | Battery read | Charge limit | Forced discharge | Temperature | Test status |
|---|---|---|---|---|---|---|---|
| arm64 | Mac16,12 | 27.0.1 (26A434) | Percentage, cycles, mAh capacities, voltage/current/power observed | Native 80/85/90/95/100% | Implemented in adapter mode; privileged test pending | TB0T read observed | Real native writes, readback and restoration tested; full AC charge cycle pending |
| arm64 | Other models | 13+ | Capability detection implemented | Native runtime probe; untested | Unsupported | Detected when available | Untested physical hardware |
| x86_64 | Intel Macs | 13+ | Capability detection implemented | Native runtime probe; untested | Unsupported | Detected when available | Cross-build only; physical hardware untested |
| Host | Test-only MockBackend | N/A | Simulated | Simulated | Simulated | Simulated | Automated controller, helper gate and integration tests |

The native `NativeChargeClient` runs before the legacy helper backend. Its actual
limits are discovered through the macOS charge service. No root helper is needed.
Other Apple Silicon devices use the same capability probe, but have not been
physically tested. Intel support is not claimed.

The advanced arm64 helper now uses AdapterBackend and a fixed CHIE adapter gate.
Capabilities require explicit successful hardware validation. Local root installation
and physical CHIE writes are pending user approval. Intel remains read-only.
[Exact read results and permission gates](FEATURE_PERMISSIONS.md).

Actual mAh capacity is read from AppleRaw fields or nested BatteryData, never
from percentage-valued MaxCapacity. Temperature is obtained from TB0T when the
registry Temperature field is absent. Voltage, signed current and battery-side
power were displayed and exported on the host.

## Adding a real backend

1. Establish key/API semantics from authoritative material and controlled hardware
   experiments; record provenance and licensing if consulting reference code.
2. Validate readback, write privilege, idempotency, allowed values, firmware behavior,
   recovery and reset semantics on a device reserved for testing.
3. Verify helper crash, app crash, sleep/wake, unplug/replug, competing OS battery
   management and long unattended holds. Establish behavior when the helper is killed.
4. Enable only independently verified capabilities. Keep unknown devices read-only.
5. Record the exact model, OS/build, backend version, operations and evidence here.

No physical write testing is performed by CI or automatically by diagnostics.

The installed CLT SDK emits an x86_64 linker warning: its Swift compatibility-packs
archive has only ARM slices. The executables link and contain x86_64 slices, but
Intel runtime compatibility must be checked with full Xcode and real Intel hardware.

## Native control validation — 2026-10-11

On Mac16,12 / arm64 / macOS 27.0.1 (26A434), as the logged-in user without root:

- Read supported limits: 80, 85, 90, 95, 100.
- Changed the actual macOS setting from 100% to 80%, verified readback, restored
  the effective original 100%. macOS normalizes 100% to a disabled native limit.
- Through the Battune UI: enabled 80%, changed to 85%, independently read the
  same values from the OS service. Quitting restored the original effective 100%.
- Simulated tests cover readback failure, unsupported values, corrupted journals,
  failed recovery, relaunch restoration, external settings, and coordinator shutdown.
- Setting acceptance/readback does not prove a full battery charge cycle. AC
  enforcement and sleep/wake charging still require a longer physical run.

API research references (protocol facts only; no upstream implementation copied):

- [Apple native charge-limit behavior](https://support.apple.com/en-au/102338).
- [batt PowerUI interface research](https://github.com/charlie0129/batt/tree/master/pkg/powerui).

The optional private PowerUI API is not a public Apple SDK contract. Battune
validates method return/argument types before use and disables the path on an ABI
mismatch. System thermal protection remains active. macOS may occasionally charge
to 100% for battery calibration; Battune does not claim to override that behavior.
