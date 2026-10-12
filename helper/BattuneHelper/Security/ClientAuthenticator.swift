import BattuneShared
import Foundation

public struct ClientAuthenticator {
  public init() {}
  public func configure(_ connection: NSXPCConnection) -> Bool {
    guard connection.effectiveUserIdentifier != 0,
      let requirement = LocalInstallationTrust.peerRequirement(forHelper: false)
    else { return false }
    // macOS 13+ authenticates every incoming message against its kernel-backed
    // XPC identity. This avoids PID lookup races and private audit-token APIs.
    connection.setCodeSigningRequirement(requirement)
    return true
  }
}
