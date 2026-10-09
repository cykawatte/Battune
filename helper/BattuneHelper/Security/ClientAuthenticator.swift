import Foundation
import BattuneShared
public struct ClientAuthenticator {
    public init() {}
    public func configure(_ connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier != 0, let team = SigningIdentity.teamIdentifier() else { return false }
        // macOS 13+ authenticates every incoming message against its kernel-backed
        // XPC identity. This avoids PID lookup races and private audit-token APIs.
        connection.setCodeSigningRequirement(SigningIdentity.requirement(identifier: HelperIdentity.appIdentifier, team: team))
        return true
    }
}
