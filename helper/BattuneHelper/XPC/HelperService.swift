import Foundation
import OSLog
import BattuneDomain
import BattuneShared
public final class HardwareGate {
    private let backend: BatteryHardwareBackend
    private let lock = NSLock()
    private var lastRefill: TimeInterval = 0
    private var tokens = 12.0
    private var confirmed: [String: HardwareCommand] = [:]
    public init(backend: BatteryHardwareBackend) { self.backend = backend }
    public func perform(_ command: HardwareCommand, now: TimeInterval = ProcessInfo.processInfo.systemUptime) throws {
        lock.lock(); defer { lock.unlock() }
        let caps = backend.capabilities()
        let key: String
        switch command {
        case .limit(let percent):
            guard (20...100).contains(percent) else { throw BattuneError.invalidConfiguration }
            guard caps.setLimit else { throw BattuneError.unsupported }; key = "limit"
        case .charging:
            guard caps.toggleCharging else { throw BattuneError.unsupported }; key = "charging"
        case .discharge:
            guard caps.forceDischarge else { throw BattuneError.unsupported }; key = "discharge"
        case .reset:
            guard caps.reset else { throw BattuneError.unsupported }; key = "reset"
        }
        if confirmed[key] == command { return }
        // A burst admits a complete transaction; sustained writes refill at 12/minute.
        // Reset is admitted even after a failed transaction exhausts the bucket.
        tokens = min(12, tokens + max(0, now - lastRefill) / 5)
        lastRefill = now
        if command != .reset {
            guard tokens >= 1 else { throw BattuneError.rateLimited }
            tokens -= 1
        }
        do { try backend.perform(command) }
        catch { confirmed = [:]; throw error }
        if command == .reset { confirmed = ["reset": .reset] }
        else { confirmed.removeValue(forKey: "reset"); confirmed[key] = command }
    }
    public func resetAfterDisconnect() {
        guard backend.capabilities().reset else { return }
        try? perform(.reset)
    }
}
public final class HelperService: NSObject, BattuneHelperProtocol {
    private let backend: BatteryHardwareBackend
    private let gate: HardwareGate
    public init(backend: BatteryHardwareBackend, gate: HardwareGate) { self.backend = backend; self.gate = gate }
    public func getStatus(reply: @escaping (Data?, Int) -> Void) {
        respond(HelperStatus(backend: backend.name, capabilities: backend.capabilities()), reply: reply)
    }
    public func getBatterySnapshot(reply: @escaping (Data?, Int) -> Void) { respond(backend.readBatterySnapshot(), reply: reply) }
    private func respond<T: Encodable>(_ value: T, reply: (Data?, Int) -> Void) {
        do { reply(try JSONEncoder().encode(value), 0) } catch { reply(nil, BattuneError.hardwareError.rawValue) }
    }
    private func perform(_ command: HardwareCommand, reply: (Int) -> Void) {
        do { try gate.perform(command); reply(0) }
        catch { reply((error as? BattuneError ?? .hardwareError).rawValue) }
    }
    public func setChargeLimit(_ percent: Int, reply: @escaping (Int) -> Void) { perform(.limit(percent), reply: reply) }
    public func setChargingEnabled(_ enabled: Bool, reply: @escaping (Int) -> Void) { perform(.charging(enabled), reply: reply) }
    public func setDischargeEnabled(_ enabled: Bool, reply: @escaping (Int) -> Void) { perform(.discharge(enabled), reply: reply) }
    public func resetChargingState(reply: @escaping (Int) -> Void) { perform(.reset, reply: reply) }
}
public final class HelperListener: NSObject, NSXPCListenerDelegate {
    private let backend = BackendFactory.make()
    private lazy var gate = HardwareGate(backend: backend)
    private let authenticator = ClientAuthenticator()
    private let logger = Logger(subsystem: "org.battune.helper", category: "Security")
    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard authenticator.configure(connection) else { logger.error("Rejected unauthenticated connection"); return false }
        connection.exportedInterface = NSXPCInterface(with: BattuneHelperProtocol.self)
        connection.exportedObject = HelperService(backend: backend, gate: gate)
        connection.resume()
        return true
    }
    public static func run() {
        let delegate = HelperListener()
        let listener = NSXPCListener(machServiceName: HelperIdentity.machService)
        listener.delegate = delegate; listener.resume()
        withExtendedLifetime(delegate) { RunLoop.current.run() }
    }
}
