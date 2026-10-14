# Adapter-mode interruption, 2026-10-12

## Findings

On Mac16,12 / macOS 27.0.1, the user reported a login screen after
selecting a limit below 80%. Read-only IORegistry inspection showed
`AppleClamshellState=Yes`. The existing CHIE backend cuts adapter input to
hold a non-native limit. This can interrupt closed-lid external-display
operation. loginwindow recorded screen locking/unlocking around 19:44;
WindowServer and loginwindow retained their process IDs. No corresponding
WindowServer crash report was found. This supports a lock/sleep interruption,
not a full user logout; the causal chain was not deliberately replayed.

The old router also restored the working native setting before establishing
that the replacement helper was usable. After sleep invalidated the helper's
hardware validation, it exposed only a generic unavailable message.

## Build 4 changes

- Read lid state from IOPMrootDomain. Reject adapter validation and adapter cuts
  with a closed or unreadable lid, including a final check in the C write gate.
  Restoring power remains permitted. The watchdog restores an owned cut if lid
  state becomes closed/unknown; existing system-sleep recovery remains enabled.
- Validate helper readiness before switching away from a working native limit.
  Failed switches preserve that native setting and report its readback in the UI.
- Show separate localized reasons for a closed lid, missing lid information and
  hardware validation required after sleep/restart. Setup explains how to recover.
- Preserve the next supported native ceiling during ordinary adapter operation
  (69% requested -> native 80% fallback), instead of always lifting it to 100%.
  Explicit discharge/calibration workflows may still require 100% temporarily.
- Disabling control and quitting can restore a retained native session after a
  rejected adapter switch.

## Scope and verification

20–100% adapter limits remain supported with an open lid and validated helper.
They consume battery during holds. Closed-lid sub-80 operation and a native
sub-80 standby ceiling are **not implemented/claimed** on this firmware. Direct
charge keys previously returned NotPrivileged even in the root helper; another
administrator confirmation cannot supply Apple's private entitlement. No
sleep/security override or undocumented target-SoC write was added.

Automated checks cover closed/unknown lid with zero adapter cuts, opening the
lid and using adapter control, restoration when the lid closes, rejected routing
without altering the native ceiling, and a lid change between routing and write.
The existing simulated 77% hold/recharge/discharge/calibration workflow remains.
Physical sub-80 validation with the updated helper and an open lid is pending.

Validation completed: 15 Rust tests and 40 Swift test groups pass. Lint,
universal ARM/Intel release builds, package signatures, pinned app/helper hashes
and package checksums pass. The new read-only C lid query reports closed (1) on
the host. Independent native readback remains 80%, enabled; pmset reports AC
attached and not charging. Build 4 installer is prepared but not installed yet.
