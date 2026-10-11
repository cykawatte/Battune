# Approved local helper installation and adapter test

Date: 2026-10-11, Europe/Berlin. Device: Mac16,12, arm64, macOS 27.0.1 (26A434).
Code build: commit `66ec7b5`, universal Release. User explicitly approved
administrator installation and a short adapter off/on test, with AC connected.

## Executed evidence

1. Opened the matching BattuneHelper.pkg through Battune Setup and Apple's Installer.
   The system authentication was completed by the user. Installer reported
   successful installation at about 12:34 local time; package receipt is
   `org.battune.helper.local`, version 0.1.0.
2. launchd reports `system/org.battune.helper` running. The executable runs as
   root. Installed helper and identity manifest are root-owned with modes 755
   and 644 respectively. App and helper authenticated successfully over the
   production XPC interface using administrator-installed exact signature pins.
3. Before validation: battery 73%, physical AC-W byte 02, CHIE byte 00,
   temperature approximately 26°C. macOS reports AC Power and charging.
4. Executed the approved Hardware Access Test through the actual Release UI.
   AdapterBackend.validate completed CHIE disable then enable with matching
   readback for both operations. UI reports `Apple Silicon / CHIE adapter / verified`
   and `CHIE write enable: IOReturn 0x00000000 (uid 0)`.
5. Independent unprivileged read after the test: CHIE=00, AC-W=02. macOS again
   reports AC Power and charging at 73%. No adapter-owned recovery journal remains.

The four pkgbuild permission messages did not prevent successful installation.
Payload verification was followed by an actual successful Installer/launchd/XPC run.
No SIP, entitlement, security-policy or global power-setting changes were made.

## Scope of conclusion

Root access is sufficient for Battune's fixed CHIE adapter gate on this device
and firmware. This is evidence of real write/readback and restoration, not a
measurement of a sustained discharge or an entire calibration cycle.

Direct-charge keys bfF0/bfD0/bfE0/CH0J still return NotPrivileged to the user-process
probe. They were not read or written by the root helper, so their root/private
entitlement requirements remain unknown. Battune does not need them for adapter mode.

The advanced-mode switch remains off after this specifically approved test. The
existing native charge-control settings are preserved. The user may enable the
now-available advanced switch in Setup to use arbitrary limits and workflows.
No long discharge, calibration, deliberate sleep or daemon-kill test was started.
Those physical validations and long-term cycle behavior remain unmeasured.
