# Beta installation and native AC control validation

Device: Mac16,12, macOS 27.0.1. Date: 2026-10-11 (Europe/Berlin).
Build: `4a65abc`, beta 0.1.0-beta.1, bundle build 3 / package 0.1.0.3.

- User completed the system administrator authentication. The complete installer
  successfully updated `/Applications/Battune.app` and the root helper bundle.
- Installed app executable matches the packaged executable; deep/strict code
  signature verification succeeds. The package receipt reports 0.1.0.3 and the
  daemon runs from `/Library/PrivilegedHelperTools/BattuneHelper.app` as root.
- All three tutorial pages were visually inspected in the installed app. Logo,
  text, page indicators and navigation fit without truncation.
- With control enabled, advanced mode enabled and the requested limit at 80%,
  the app confirms a native macOS limit of 80%. The helper is not yet revalidated
  after installation; this does not prevent native control.
- Independent IOKit read: ExternalConnected=true, IsCharging=false,
  CurrentCapacity=80, InstantAmperage=0, Amperage=0. `pmset -g batt` reports
  AC Power, 80%, AC attached, not charging. This is an instantaneous observation
  of wall-power operation without battery charging/discharging, not an electrical
  isolation measurement or a long-term guarantee.
- The production XPC helper reports its fixed-key read-only probe from uid 0:
  CHTE/CH0B/CH0C/CH0I: SMC result 0x84, no readable value;
  CHIE: successful one-byte read;
  bfF0/bfD0/bfE0/CH0J: IOReturn 0xE00002C1 (NotPrivileged).
  Administrator access therefore does not grant these direct-charge reads on
  this firmware. No writes to those keys or system-security changes were attempted.

53 automated tests/groups pass locally (15 Rust, 38 Swift). New coverage checks
native preference despite advanced-mode opt-in, sleep/wake preservation, helper
unavailability, explicit workflows, cancellation, sleep interruption and return
from non-native limits. Package verification checks both architectures, signatures,
identity pins, icons, installation paths, recovery scripts and SHA-256 checksums.

## Physical sleep check and next-day observation

The user explicitly selected Sleep on 2026-10-11. `pmset` records AC power at 80%
when entering Software Sleep at 17:59:49, a short DarkWake, Maintenance Sleep
from 18:00:06 to 18:04:10 (244 seconds), then user wake still on AC at 80%.
This confirms a real short sleep/wake cycle without an observed increase in charge.
Simply closing the lid previously did not trigger sleep in this docked setup
(`AppleClamshellCausesSleep=No`); that was not counted as a sleep test.

On 2026-10-12 at 18:49 Europe/Berlin, independent IOKit/pmset reads again show
AC connected, 80%, not charging and 0 mA battery current. This next-day snapshot
is not a continuous 24-hour measurement. No later sleep cycle appears in the
inspected power log; a physical overnight standby run remains unverified.

 Apple can occasionally
exceed its native charge limit for gauge calibration:
https://support.apple.com/en-us/102338 . Non-native adapter limits still consume
battery during holds and do not apply while asleep. Direct-charge entitlement
restrictions on this firmware have also been independently reported:
https://github.com/charlie0129/batt/pull/154 . That report does not establish that
ordinary user consent could grant Apple's private entitlement.
