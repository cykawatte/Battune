# Third-party notices

No external Swift packages or Rust crates are used. There is no web UI, database
package, SMC library, copied AlDente source, telemetry SDK or network SDK.

| Component | Version tested | Purpose | License / distribution |
|---|---|---|---|
| Rust standard library and compiler support | Rust 1.99.0 | Statically linked Rust core support | MIT OR Apache-2.0; notices below |
| Swift compiler/runtime | Swift 6.4 | Native code and concurrency | Apache-2.0 with Runtime Library Exception; platform/toolchain supplied |
| AppKit, SwiftUI, Foundation, IOKit, Security, ServiceManagement, Charts, UserNotifications | SDK 27.0; target macOS 13+ | macOS functionality | Apple system frameworks; not redistributed as libraries |
| actions/checkout | v4, pinned commit 11d5960a326750d5838078e36cf38b85af677262 | CI checkout only | MIT; not part of app |
| Cargo, rustfmt, clippy, swift-format, native macOS command-line tools | Installed toolchain | Development only | Respective upstream toolchain licenses; not app dependencies |

SwiftPM/Cargo manifests and lockfile are authoritative. The compiler and system
SDK determine exact platform runtime versions. No third-party source was copied
into Battune. Review static compiler-support notices again before distribution.

## Native charge-control research

The optional PowerUI framework is supplied by macOS and is not redistributed.
Native charge-interface selector names, ABI encodings and expected behavior were
checked against the running system and the public
[batt interface research](https://github.com/charlie0129/batt/tree/master/pkg/powerui)
(GPL-2.0 project). Battune’s small runtime-checked Objective-C bridge and Swift
transaction/journal implementation were independently written; no upstream source
or binary is included. Apple documents the user-facing native limit behavior at
[Apple Support](https://support.apple.com/en-au/102338).

## AppleSMC protocol research

Fixed key meanings, type metadata and the 80-byte user-client wire ABI were
cross-checked against the running device, installed IOKit headers,
[batt SMC research](https://github.com/charlie0129/batt/tree/master/pkg/smc) and
[gosmc](https://github.com/charlie0129/gosmc). These repositories are research
references only, not bundled dependencies. The C bridge, fixed-operation checks,
Swift ownership journal, watchdog and permission flow are independently written.
No upstream code or binary is redistributed.

## Rust standard library (MIT option)

Copyright (c) The Rust Project Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in the
Software without restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the
Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

[Rust licensing](https://github.com/rust-lang/rust/blob/master/LICENSE-MIT)
· [Swift licensing](https://github.com/swiftlang/swift/blob/main/LICENSE.txt)
