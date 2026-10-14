import BattuneDomain
import BattuneShared
import Foundation
import OSLog

public final class HardwareGate {
  private let leaseDuration: TimeInterval
  private let backend: BatteryHardwareBackend
  private let accessories: AccessoryTransport
  private let lock = NSLock()
  private var generation: UInt64 = 0
  private var lastRefill: TimeInterval = 0
  private var tokens = 12.0
  private var lease: DispatchWorkItem?
  private var leaseGeneration = 0
  private let logger = Logger(subsystem: "org.battune.helper", category: "Recovery")
  private var confirmed: [String: HardwareCommand] = [:]
  public init(
    backend: BatteryHardwareBackend, accessories: AccessoryTransport = SystemAccessoryTransport(),
    leaseDuration: TimeInterval = 120
  ) {
    self.backend = backend
    self.accessories = accessories
    self.leaseDuration = max(0.01, leaseDuration)
  }
  public func validateAdapter() throws {
    try lock.withLock {
      guard let adapter = backend as? AdapterBackend else { throw BattuneError.unsupported }
      refill(now: ProcessInfo.processInfo.systemUptime)
      guard tokens >= 2 else { throw BattuneError.rateLimited }
      tokens -= 2
      try adapter.validate()
      confirmed = [:]
      lease?.cancel()
      lease = nil
      leaseGeneration += 1
    }
  }
  /// Charge capabilities plus the accessory operations this root process can perform.
  public func capabilities() -> Capabilities {
    var caps = backend.capabilities()
    caps.indicatorControl = accessories.privileged && accessories.indicatorAvailable
    caps.powerModeControl = accessories.privileged
    return caps
  }
  public func setIndicator(
    _ value: Int, now: TimeInterval = ProcessInfo.processInfo.systemUptime
  ) throws {
    guard [0, 1, 3, 4].contains(value) else { throw BattuneError.invalidConfiguration }
    try accessory(now: now) { try accessories.setIndicator(value) }
  }
  public func setLowPowerMode(
    battery: Bool, charger: Bool, now: TimeInterval = ProcessInfo.processInfo.systemUptime
  ) throws {
    try accessory(now: now) { try accessories.setLowPowerMode(battery: battery, charger: charger) }
  }
  /// Accessories share the command budget, so they cannot be used to flood the SMC.
  private func accessory(now: TimeInterval, _ body: () throws -> Void) throws {
    try lock.withLock {
      guard accessories.privileged else { throw BattuneError.unauthorized }
      refill(now: now)
      guard tokens >= 1 else { throw BattuneError.rateLimited }
      tokens -= 1
      try body()
    }
  }
  public func perform(
    _ command: HardwareCommand, now: TimeInterval = ProcessInfo.processInfo.systemUptime
  ) throws {
    lock.lock()
    defer { lock.unlock() }
    if generation != backend.generation {
      confirmed = [:]
      generation = backend.generation
    }
    let caps = backend.capabilities()
    if command != .reset, let block = caps.controlBlock { throw block }
    let key: String
    switch command {
    case .limit(let percent):
      guard (20...100).contains(percent) else { throw BattuneError.invalidConfiguration }
      guard caps.setLimit else { throw BattuneError.unsupported }
      key = "limit"
    case .charging:
      guard caps.toggleCharging else { throw BattuneError.unsupported }
      key = "charging"
    case .discharge:
      guard caps.forceDischarge else { throw BattuneError.unsupported }
      key = "discharge"
    case .reset:
      guard caps.reset else { throw BattuneError.unsupported }
      key = "reset"
    }
    guard command == .reset || caps.reset else { throw BattuneError.unsupported }
    if confirmed[key] == command { return }
    // A burst admits a complete transaction; sustained writes refill at 12/minute.
    // Reset is admitted even after a failed transaction exhausts the bucket.
    refill(now: now)
    if command != .reset {
      guard tokens >= 1 else { throw BattuneError.rateLimited }
      tokens -= 1
    }
    do { try backend.perform(command) } catch {
      confirmed = [:]
      throw error
    }
    generation = backend.generation
    if command == .reset {
      lease?.cancel()
      lease = nil
      leaseGeneration += 1
      confirmed = ["reset": .reset]
    } else {
      confirmed.removeValue(forKey: "reset")
      confirmed[key] = command
      armLease()
    }
  }
  private func refill(now: TimeInterval) {
    tokens = min(12, tokens + max(0, now - lastRefill) / 5)
    lastRefill = now
  }
  // Called with the gate lock held. No timer exists while hardware is untouched.
  private func armLease() {
    lease?.cancel()
    leaseGeneration += 1
    let generation = leaseGeneration
    let work = DispatchWorkItem { [weak self] in self?.expireLease(generation: generation) }
    lease = work
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + leaseDuration, execute: work)
  }
  public func renewLease() throws {
    lock.lock()
    defer { lock.unlock() }
    guard lease != nil else { return }
    armLease()
  }
  private func expireLease(generation: Int) {
    lock.lock()
    defer { lock.unlock() }
    guard generation == leaseGeneration, lease != nil else { return }
    lease = nil
    confirmed = [:]
    if let adapter = backend as? AdapterBackend {
      adapter.prepareForSleep()
    } else {
      do { try backend.perform(.reset) } catch {
        logger.error("Control lease expired; reset failed")
      }
    }
  }
}
