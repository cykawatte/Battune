import BattuneDomain
import BattuneShared
import Foundation
import OSLog

public final class HelperService: NSObject, BattuneHelperProtocol {
  private let backend: BatteryHardwareBackend
  private let gate: HardwareGate
  public init(backend: BatteryHardwareBackend, gate: HardwareGate) {
    self.backend = backend
    self.gate = gate
  }
  public func validateAdapterControl(reply: @escaping (Int) -> Void) {
    do {
      try gate.validateAdapter()
      reply(0)
    } catch { reply((error as? BattuneError ?? .hardwareError).rawValue) }
  }
  public func renewControlLease(reply: @escaping (Int) -> Void) {
    do {
      try gate.renewLease()
      reply(0)
    } catch { reply(BattuneError.hardwareError.rawValue) }
  }
  public func getStatus(reply: @escaping (Data?, Int) -> Void) {
    respond(
      HelperStatus(
        backend: backend.name, capabilities: gate.capabilities(),
        controlGeneration: backend.generation,
        hardwareDiagnostic: (backend as? AdapterBackend)?.diagnostic), reply: reply)
  }
  public func getBatterySnapshot(reply: @escaping (Data?, Int) -> Void) {
    respond(backend.readBatterySnapshot(), reply: reply)
  }
  private func respond<T: Encodable>(_ value: T, reply: (Data?, Int) -> Void) {
    do { reply(try JSONEncoder().encode(value), 0) } catch {
      reply(nil, BattuneError.hardwareError.rawValue)
    }
  }
  private func perform(_ command: HardwareCommand, reply: (Int) -> Void) {
    do {
      try gate.perform(command)
      reply(0)
    } catch { reply((error as? BattuneError ?? .hardwareError).rawValue) }
  }
  public func setChargeLimit(_ percent: Int, reply: @escaping (Int) -> Void) {
    perform(.limit(percent), reply: reply)
  }
  public func setChargingEnabled(_ enabled: Bool, reply: @escaping (Int) -> Void) {
    perform(.charging(enabled), reply: reply)
  }
  public func setDischargeEnabled(_ enabled: Bool, reply: @escaping (Int) -> Void) {
    perform(.discharge(enabled), reply: reply)
  }
  public func resetChargingState(reply: @escaping (Int) -> Void) { perform(.reset, reply: reply) }
  public func setIndicator(_ value: Int, reply: @escaping (Int) -> Void) {
    do {
      try gate.setIndicator(value)
      reply(0)
    } catch { reply((error as? BattuneError ?? .hardwareError).rawValue) }
  }
  public func setLowPowerMode(battery: Bool, charger: Bool, reply: @escaping (Int) -> Void) {
    do {
      try gate.setLowPowerMode(battery: battery, charger: charger)
      reply(0)
    } catch { reply((error as? BattuneError ?? .hardwareError).rawValue) }
  }
}
public final class HelperListener: NSObject, NSXPCListenerDelegate {
  private let backend = BackendFactory.make()
  private lazy var gate = HardwareGate(backend: backend)
  private let authenticator = ClientAuthenticator()
  private let logger = Logger(subsystem: "org.battune.helper", category: "Security")
  public func listener(
    _ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection
  ) -> Bool {
    guard authenticator.configure(connection) else {
      logger.error("Rejected unauthenticated connection")
      return false
    }
    connection.exportedInterface = NSXPCInterface(with: BattuneHelperProtocol.self)
    connection.exportedObject = HelperService(backend: backend, gate: gate)
    connection.resume()
    return true
  }
  public static func run() {
    let delegate = HelperListener()
    let sleep = HelperSleepGuard(adapter: delegate.backend as? AdapterBackend)
    try? (delegate.backend as? AdapterBackend)?.recover()
    sleep.start()
    let listener = NSXPCListener(machServiceName: HelperIdentity.machService)
    listener.delegate = delegate
    listener.resume()
    withExtendedLifetime((delegate, sleep)) { RunLoop.current.run() }
  }
}
