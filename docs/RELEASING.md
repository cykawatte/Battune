# Beta packaging and release

The current milestone is **0.1.0-beta.1**, a GitHub prerelease. Repository visibility
remains private; testers need access. It is not a final production release.

## Reproduce the download

Install the toolchains described in README, then run from a clean checkout:

```sh
rustup target add aarch64-apple-darwin x86_64-apple-darwin
./scripts/lint.sh
./scripts/test.sh
./scripts/build.sh release universal
./scripts/package.sh
./scripts/verify-package.sh
```

Outputs in `build/packages`: complete installer, helper-only repair installer,
ZIP (installers, instructions and uninstaller), SHA256SUMS.txt. Both executables
contain arm64 and x86_64 slices. CI checks the package payload, code signatures,
exact-hash identity pairing, icons, recovery scripts and fixed installation paths.
Building or packaging never installs privileged software.

The full installer places the app in `/Applications/Battune.app`, the helper in
`/Library/PrivilegedHelperTools/BattuneHelper.app`, its daemon in
`/Library/LaunchDaemons/org.battune.helper.plist` and the root-owned identity
manifest in `/Library/Application Support/BattuneHelper/identity.json`.
The embedded helper and installed helper must match. Quit Battune normally before
updating; the installer refuses to replace a running app, restores the previous
helper's journaled state, then installs and starts the matching daemon.

## Publish a beta

1. Set VERSION, bundle build version, app/helper protocol version and Rust version.
2. Update changelog, release notes and install instructions; run all checks above.
3. Inspect the tutorial and installer; check helper authentication on a local Mac.
4. Merge the reviewed branch to main only after GitHub CI succeeds.
5. Create `v0.1.0-beta.1` from the merged commit as a **prerelease**, with the four
   artifacts from `build/packages`. Verify uploaded checksums. Keep the repository
   visibility unchanged. Packaging scripts do not publish on their own.

The current download is ad-hoc signed and **not notarized**. Developer ID signing
is optional through BATTUNE_SIGNING_IDENTITY using a local Keychain identity;
no credentials belong in source control. Rebuild the exact-hash manifest after
any signing change. The Homebrew cask remains an unpublished draft.

## Final-release gates

- Developer ID application/installer signing, notarization, stapling and clean-Mac install.
- Intel and supported macOS runtime validation; signature-based ServiceManagement flow.
- Complete physical charge/discharge/calibration cycles and sleep/crash recovery.
- Long-running performance measurements and broader accessibility/localization QA.
- Further review of private PowerUI/SMC compatibility and hardware fail-safe behavior.

See [installation and uninstall](../packaging/INSTALL.md),
[hardware support](HARDWARE_SUPPORT.md) and [permission evidence](FEATURE_PERMISSIONS.md).
