# Hardware support and validation matrix

Do not equate compilation, simulation and physical charging validation.

| Architecture | Device | macOS | Battery read | Charge limit | Forced discharge | Temperature | Test status |
|---|---|---|---|---|---|---|---|
| arm64 | Mac16,12 | 27.0.1 (26A434) | Percentage, AC/charging state and cycle count observed | Unsupported | Unsupported | Unknown from selected properties | Local read-only IOKit and UI tested; no charging writes |
| arm64 | Other models | 13+ | Capability detection implemented | Unsupported | Unsupported | Detected when available | Untested physical hardware |
| x86_64 | Intel Macs | 13+ | Capability detection implemented | Unsupported | Unsupported | Detected when available | Cross-build only; physical hardware untested |
| Host | Test-only MockBackend | N/A | Simulated | Simulated | Simulated | Simulated | Automated controller, helper gate and integration tests |

AppleSiliconBackend and IntelBackend intentionally expose no write/reset
capabilities. A historical SMC key or the existence of an AppleSMC service is not
proof that writing it is safe or that reset is understood. There is no arbitrary
key reader/writer in this version. Existing proprietary code was not used.

The tested host exposes CurrentCapacity=percentage, MaxCapacity=100 and CycleCount.
Raw mAh capacity, design capacity and temperature are absent through the selected
properties. The app correctly displays unknown rather than inventing health or
mistaking 100% for 100 mAh.

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
