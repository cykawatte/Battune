# Local packaging and future release gates

This repository is not approved for a public release. Nothing has been pushed,
published, notarized or submitted to an app store by this implementation task.

`build.sh release [universal]` builds and ad-hoc signs a local bundle. `package.sh`
is prepared for ZIP and optional DMG creation using ditto/hdiutil. Packaging is
not automatically invoked by CI or by builds. Developer ID signing is opt-in via
BATTUNE_SIGNING_IDENTITY referring to an existing Keychain identity. No secrets or
certificate files are stored in the repository. The packaging script never
notarizes or uploads; future notarization should use a Keychain profile.

Before distributing:

1. Implement and physically validate real backends, including crash/reset behavior.
2. Validate signed helper registration/authentication on all supported OS versions.
3. Audit security and FFI. Verify no mock backend is linked into release artifacts.
4. Measure long idle sessions, wakeups, RAM, cold startup, disk and network activity.
5. Test Intel and Apple Silicon devices and Xcode workflow; complete accessibility/localization QA.
6. Set a release version, complete changelog, capture sanitized screenshots.
7. Sign nested helper then app, verify signatures and hardened runtime, notarize
   only with explicit authorization, staple and verify on a clean Mac.
8. Build ZIP/DMG, independently verify hash, then update the unpublished Homebrew
   draft with a real URL/hash only after publication is separately authorized.

Uninstall: disable Battune control, obtain confirmed reset on a supported backend,
then unregister helper from Diagnostics. Remove launch at login, quit, remove app.
Disable native control and verify restoration before uninstalling. The ownership
journal is at `~/Library/Application Support/Battune/native-charge-session.json`;
do not delete it before restoring an active session. The legacy read-only backend
has no custom hardware state to restore.
Delete local settings/history separately if desired. Never copy the launchd plist
manually into system directories; use ServiceManagement.
