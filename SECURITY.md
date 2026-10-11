# Security policy

Battune 0.1.0-dev is development software, not a validated public release.
Native macOS charge-limit writes and restoration are implemented with readback
verification. Direct SMC, forced-discharge and charging-gate mutations remain
unsupported. The private OS interface is checked at runtime and may change.

Do not post signing material, exploit credentials, serial numbers or private logs
in public issues. Once a public repository enables GitHub private vulnerability
reporting, use its Security → Report a vulnerability flow. Until a private reporting
channel is established, contact the maintainer privately through a previously
verified channel; no reporting address is invented by this repository.

Reports should describe the version, trust boundary, safe reproduction and likely
impact. Avoid real battery manipulation to demonstrate an issue. The helper's
narrow protocol, signature checks and unresolved validation work are documented in
[SECURITY_MODEL.md](docs/SECURITY_MODEL.md). No response-time or support guarantee is
claimed before public maintenance arrangements exist.
