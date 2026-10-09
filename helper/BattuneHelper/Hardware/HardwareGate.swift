import BattuneDomain
import BattuneShared
import Foundation
import OSLog

public final class HardwareGate {
  private let leaseDuration: TimeInterval
  private let backend: BatteryHardwareBackend
  private let lock = NSLock()
  private var lastRefill: TimeInterval = 0
  private var tokens = 12.0
  private var lease: DispatchWorkItem?
  private var leaseGeneration = 0
  private let logger = Logger(subsystem: "org.battune.helper", category: "Recovery")
  private var confirmed: [String: HardwareCommand] = [:]
  public init(backend: BatteryHardwareBackend, leaseDuration: TimeInterval = 120) {
    self.backend = backend
    self.leaseDuration = max(0.01, leaseDuration)
  }
  public func perform(
    _ command: HardwareCommand, now: TimeInterval = ProcessInfo.processInfo.systemUptime
  ) throws {
    lock.lock()
    defer { lock.unlock() }
    let caps = backend.capabilities()
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
    tokens = min(12, tokens + max(0, now - lastRefill) / 5)
    lastRefill = now
    if command != .reset {
      guard tokens >= 1 else { throw BattuneError.rateLimited }
      tokens -= 1
    }
    do { try backend.perform(command) } catch {
      confirmed = [:]
      throw error
    }
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
    do { try backend.perform(.reset) } catch { logger.error("Control lease expired; reset failed") }
  }
}
