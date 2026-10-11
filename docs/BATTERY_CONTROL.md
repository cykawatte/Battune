# Battery-control semantics

The native backend writes and verifies the macOS charge limit on supported Apple
Silicon Macs. It uses only runtime-reported limits (80/85/90/95/100 on the tested
host). Apple owns hysteresis, thermal protection and sleep enforcement; Battune
does not send direct charging or discharge commands through this backend.

Disabling control or quitting restores the prior macOS setting. After a crash,
the OS retains the safe upper limit; the journal allows restoration on next
launch. Native limits remain configured on battery power and during sleep.
Schedules change the native upper limit while the app runs. Custom sailing,
thermal thresholds and forced discharge are not applied in native mode.

The legacy policy below is implemented and mock-tested only. Battery health
features provided by macOS remain
under the operating system's control.

## Priority

1. No authorization/onboarding, unsupported capabilities or suspended control:
   no new mutation. A previously active interrupted workflow requests reset.
2. Disabled control, missing SOC/AC data, or unplug: request reset if supported.
3. Thermal hold (including missing temperature when protection is enabled): stop
   charging and stop forced discharge; only a charging gate can provide this hold.
4. Calibration, with the same thermal safety rules and bounded overall duration.
5. Explicit or newly activated scheduled discharge.
6. Current schedule's limit/sailing policy, otherwise the user's base policy.
7. Normal charge/hold decision with hysteresis.

These are desired states. UI control state advances only after successful helper
responses; read-only and failed hardware never produce fictitious success.

## Charge and sailing

The default upper limit is 80%; valid limits are 20–100%. SOC >= upper holds.
Without sailing, SOC <= upper-1 resumes. With sailing, require
20 <= lower < upper <= 100; the open interval preserves the previous stable state.
On a fresh state inside the band, allow charging until the upper limit.
Prefer direct hardware limits; toggle charging when available for safety and sailing.

## Thermal guard

Defaults are resume 35 °C, stop 40 °C, configurable within 20–50 °C with resume
strictly below stop. These are policy examples, not Apple-approved thermal limits.
They are not a replacement for firmware protection. A hot or missing sensor holds
charging while protection is enabled. Unknown temperature is never silently zero.
A direct-limit-only backend cannot guarantee thermal inhibition; it must not
claim thermal support. Temperature semantics need per-device validation.

## Discharge and calibration

Discharge requires an explicit UI action or a saved schedule activation and a
validated force-discharge capability. Stop forced discharge at/below the target,
on unplug, cancellation or error. Resume normal charge policy after completion.

Calibration: charge to 100%, stabilize 30 minutes, discharge to 20%, recharge to
100%, reset and restore ordinary policy. Cancellation resets and returns to normal
policy. Unplug, clock rollback or an overall duration above 48 hours interrupts.
Thermal protection pauses progression. A restart converts any active persisted
journal to Interrupted; it never silently resumes a deep discharge. The UI
explains the full cycle before activation. Calibration is not recommended as
routine battery care; this implementation does not claim health improvement.

## Schedules

Up to 32 schedules: day mask Monday–Sunday, minute of day, charge/sailing values,
optional discharge target and priority. Latest actual weekly activation wins;
ties use higher priority then lower stable ID. A plan remains active until the
next activation. Global thermal settings are always retained.

Missing spring times activate at the next valid time. Repeated autumn times use
the first occurrence; later repeated minutes do not roll back to an older plan.
Recompute for the current timezone after changes and wake. Discharge activation
is recorded before mutation, preventing crash/restart replay. If the app was
not controlling at that activation, it is consumed without later surprise discharge.

## Hardware confirmation and recovery

Executor applies discharge-off, limit, charging gate, discharge-on in that order.
Only confirmed values deduplicate. An interrupted transaction invalidates its
confirmation cache. Hardware errors suspend control, cancel dangerous workflows
and try reset once; the user must request retry. Helper enforces a 12-write burst
and 12/minute refill; identical confirmed operations are free. Reset retains a
recovery path. A 120-second lease requests reset if an active controller disappears.
A killed helper cannot execute a timer: independent firmware/readback validation
is still a prerequisite for enabling any real backend.
