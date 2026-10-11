# Architecture

## Boundaries

`BattuneDomain` contains immutable snapshots, validated settings, the C ABI adapter,
schedule-time conversion and persistence. `BattuneSystem` owns IOKit reads,
notifications, the settings view model, coordinator and hardware command executor.
The `Battune` executable owns AppKit lifecycle, separate SwiftUI views and localization.
`BattuneShared` defines the fixed XPC protocol, bounded reply decoding and signing
requirements. `BattuneHardware` implements helper authentication, serialized hardware
operations and separate architecture-specific read-only backends. `BattuneHelper`
is the daemon entry point. Test mocks live exclusively in the test executable.

The Rust `model`, `controller`, `calibration`, `schedule` and `ffi` modules contain
no platform calls, I/O or mutable globals. Evaluation returns desired values; it
never performs hardware operations. Swift owns confirmed operation state. Failed
commands invalidate that state and trigger one bounded reset attempt.

## Native charge-limit path

`CNativeCharge` dynamically loads the OS-owned PowerUI framework and verifies the
Objective-C signatures of a fixed set of charge-limit methods. It exports only
read, set-limit and disable operations. `NativeChargeClient` serializes these
calls off the main thread with a five-second response deadline. Queued requests
that expire are not executed. An OS call already in progress cannot be cancelled;
its durable journal remains available for recovery if the service stalls. It requires no Battune LaunchDaemon: Apple's service
performs the actual privileged hardware operation.

`PlatformHardwareClient` selects native control when available and only probes the
legacy helper when native control reports unsupported. It never silently changes
controllers after selecting one. Native mode bypasses the direct-gate Rust policy
because macOS itself owns hysteresis, thermal protection and sleeping behavior.
The coordinator applies the scheduled upper limit and publishes success only
after a matching readback. Unknown/unaccepted values are errors, never rounded in
hardware commands. Sliders snap to supported values visibly before saving.

`NativeChargeSession` writes an atomic ownership journal before mutation, retains
the original effective macOS setting across successive changes, and verifies
restoration. A process lock serializes journal transactions. Failed restoration
keeps recovery data. Reset preserves a different setting changed outside Battune.
A crash leaves a bounded native charge limit, not disabled charging or forced
discharge. The next launch can restore the journal, or resume the saved limit.

## ABI and ownership

ABI v1 uses explicit Int32/UInt32/Int64 fields and a maintained C header. SOC and
optional target/lower flags use -1 for unknown; temperature uses INT32_MIN. No Rust
heap object crosses the boundary. Schedule input is borrowed for the call, limited
to 32 entries. The Rust slice conversion is documented; the native Objective-C bridge separately
checks runtime method ABIs before calling the private platform interface. Layout assertions and Swift-to-Rust tests check sizes and behavior.
Inputs are validated before narrowing integer conversions.

## Events and scheduling

An IOPS run-loop source drives fresh reads. Workspace sleep/wake events suspend
and recreate the single 60-second fallback timer (15-second tolerance). System
clock/timezone changes also evaluate immediately. Evaluation coalesces incoming
events rather than queueing snapshots. Cancellation generations prevent the rest
of a stale hardware transaction from running after sleep or settings changes.

Calendar resolves actual local activation instants. Spring gaps move to the next
valid time; autumn repeated times use the first occurrence. Rust selects the
latest activation with deterministic priority and stable-ID ties. There is no
wake alarm and no replay of missed scheduled transitions.

## Persistence

UserDefaults stores versioned Codable preferences, a calibration journal and the
last consumed schedule activation token. Invalid configuration leaves control
disabled and presents an error. Settings only write on explicit save or workflow
changes. Calibration does not overwrite ordinary preferences; normal policy is
restored on completion/cancellation. Active journals become interrupted on restart.

History is a separate atomic JSON file in Application Support/Battune, bounded to
8,640 samples and approximately 30 days. Periodic sampling is five minutes apart; power/charging transitions are recorded immediately;
unchanged readings do not create samples. Twelve changes are batched before a
write; sleep/exit flushes remaining changes. A crash may lose the last batch.
Loading rejects files above 8 MB. No additional statistics timer exists.

## Build decisions and trade-offs

SwiftPM provides compilable module boundaries without requiring a full Xcode
installation. The Xcode project invokes the same native scripts, including Rust
builds; Cargo performs incremental recompilation. Separate Debug/Release Rust
library search paths prevent accidentally linking the wrong configuration.

The tested SDK 27 declares a SwiftUI State macro whose plugin is not shipped in
CLT. `ViewState` explicitly aliases the longstanding State property wrapper and
retains macOS 13 compatibility. `--build-system native` provides stable resource
bundling under CLT; its deprecation warning in Swift 6.4 is known. Adopt the newer
SwiftPM build engine after testing bundle-resource behavior on full Xcode and CLT.

See ADRs 0001–0006 for alternatives and consequences.
