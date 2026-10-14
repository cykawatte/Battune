import BattuneDomain
import BattuneSystem
import CNativeCharge
import Darwin
import Foundation
import IOKit.pwr_mgt

public protocol AdapterTransport: AnyObject {
  var privileged: Bool { get }
  var diagnostic: String? { get }
  var lidClosed: Bool? { get }
  func isEnabled() throws -> Bool
  func setEnabled(_ enabled: Bool) throws
  func snapshot() -> BatterySnapshot
}
extension AdapterTransport { public var diagnostic: String? { nil } }
public final class SMCAdapterTransport: AdapterTransport {
  private var lastWrite: String?
  private lazy var accessReport: String = {
    // Fixed, read-only probes in the actual root process; never infer root access
    // from the unprivileged GUI's result and never try writing unknown keys.
    let results = (0...8).map { index in
      let key = SMCProbe.read(index)
      return "\(key.key): \(key.result)"
    }
    return "SMC read-only probe (uid \(geteuid()))\n" + results.joined(separator: "\n")
  }()
  public var diagnostic: String? {
    [lastWrite, accessReport].compactMap { $0 }.joined(separator: "\n")
  }
  public init() {}
  public var privileged: Bool { geteuid() == 0 }
  public var lidClosed: Bool? {
    switch bt_clamshell_closed() {
    case 0: return false
    case 1: return true
    default: return nil
    }
  }
  public func isEnabled() throws -> Bool {
    let key = SMCProbe.read(1)
    guard key.readable, key.size == 1, let byte = key.bytes.first, byte == 0 || byte == 8 else {
      throw BattuneError.unsupported
    }
    return byte == 0
  }
  public func setEnabled(_ enabled: Bool) throws {
    guard privileged else { throw BattuneError.unauthorized }
    let result = bt_smc_adapter(enabled ? 1 : 0)
    lastWrite = String(
      format: "CHIE write %@: IOReturn 0x%08x (uid %d)", enabled ? "enable" : "disable", result,
      geteuid())
    guard result == 0 else {
      throw result == 0xe000_02c1 ? BattuneError.unauthorized : .hardwareError
    }
    guard try isEnabled() == enabled else { throw BattuneError.hardwareError }
  }
  public func snapshot() -> BatterySnapshot {
    var result = SystemBatteryProvider().read()
    // Physical cable detection must remain true while the adapter input is cut.
    result.pluggedIn = SMCProbe.physicallyPluggedIn
    return result
  }
}

/// The only advanced production write is CHIE (adapter enabled/disabled).
/// Charging is implemented by the policy loop, not a fabricated firmware limit.
public final class AdapterBackend: BatteryHardwareBackend {
  public var name: String {
    lock.withLock {
      validated
        ? "Apple Silicon / CHIE adapter / verified"
        : "Apple Silicon / CHIE adapter / validation required"
    }
  }
  private var revision: UInt64 = 0
  private var lastFailure: String?
  public var diagnostic: String? {
    lock.withLock {
      [
        lastFailure, "Lid closed: \(transport.lidClosed.map(String.init) ?? "unknown")",
        "Adapter validation: \(validated)", transport.diagnostic,
      ]
      .compactMap { $0 }.joined(separator: "\n")
    }
  }
  public var generation: UInt64 { lock.withLock { revision } }
  private let transport: AdapterTransport
  private let journal: URL
  private let lock = NSRecursiveLock()
  private var validated = false
  private var sleepProtectionReady = false
  public func setSleepProtectionReady(_ ready: Bool) {
    lock.withLock { sleepProtectionReady = ready }
  }
  private var chargingAllowed = true
  private var discharge = false
  private var watchdog: DispatchSourceTimer?
  public init(
    transport: AdapterTransport = SMCAdapterTransport(),
    journal: URL = URL(fileURLWithPath: "/Library/Application Support/BattuneHelper/adapter-owned")
  ) {
    self.transport = transport
    self.journal = journal
  }
  public func readBatterySnapshot() -> BatterySnapshot { lock.withLock { transport.snapshot() } }
  public func capabilities() -> Capabilities {
    lock.withLock {
      let snapshot = transport.snapshot()
      let block = controlBlock
      let ready = block == nil && (try? transport.isEnabled()) != nil
      return Capabilities(
        readBattery: snapshot.percentage != nil,
        readTemperature: snapshot.temperature != nil, toggleCharging: ready,
        forceDischarge: ready, reset: transport.privileged, adapterControl: true,
        controlBlock: block)
    }
  }
  private var controlBlock: BattuneError? {
    guard transport.privileged else { return .unauthorized }
    guard let closed = transport.lidClosed else { return .lidStateUnknown }
    guard !closed else { return .lidClosed }
    guard validated else { return .adapterValidationRequired }
    return nil
  }
  private func requireOpenLid() throws {
    guard let closed = transport.lidClosed else { throw BattuneError.lidStateUnknown }
    guard !closed else { throw BattuneError.lidClosed }
  }
  /// Explicit, short off/on roundtrip, reachable only through authenticated XPC.
  public func validate() throws {
    try lock.withLock {
      guard transport.privileged else { throw BattuneError.unauthorized }
      guard sleepProtectionReady else { throw BattuneError.hardwareError }
      try recover()
      try requireOpenLid()
      let battery = transport.snapshot()
      guard battery.pluggedIn == true, let percentage = battery.percentage, percentage >= 30,
        let temperature = battery.temperature, temperature < 40
      else { throw BattuneError.invalidSnapshot }
      lastFailure = nil
      try recover()
      guard try transport.isEnabled() else { throw BattuneError.hardwareError }
      try claim()
      do {
        try transport.setEnabled(false)
        try transport.setEnabled(true)
        try releaseOwnership()
        validated = true
      } catch {
        lastFailure = transport.diagnostic ?? String(describing: error)
        validated = false
        try? recover()
        throw error
      }
    }
  }
  public func perform(_ command: HardwareCommand) throws {
    try lock.withLock {
      if command == .reset {
        try recover()
        return
      }
      guard validated, transport.privileged else { throw BattuneError.unauthorized }
      switch command {
      case .charging(let enabled): chargingAllowed = enabled
      case .discharge(let enabled): discharge = enabled
      case .limit: throw BattuneError.unsupported
      case .reset: break
      }
      let enabled = chargingAllowed && !discharge
      if !enabled {
        do { try requireOpenLid() } catch {
          try recover()
          throw error
        }
        let snapshot = transport.snapshot()
        guard snapshot.pluggedIn == true, let percentage = snapshot.percentage, percentage > 15,
          let temperature = snapshot.temperature, temperature < 50
        else {
          try recover()
          throw BattuneError.invalidSnapshot
        }
        try claim()
      }
      do {
        let wasEnabled = try transport.isEnabled()
        try transport.setEnabled(enabled)
        if enabled != wasEnabled { revision &+= 1 }
        if enabled { try releaseOwnership() } else { startWatchdog() }
      } catch {
        lastFailure = transport.diagnostic ?? String(describing: error)
        validated = false
        try? recover()
        throw error
      }
    }
  }
  private func claim() throws {
    if FileManager.default.fileExists(atPath: journal.path) { return }
    guard try transport.isEnabled() else { throw BattuneError.hardwareError }
    try FileManager.default.createDirectory(
      at: journal.deletingLastPathComponent(),
      withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
    try Data("Battune adapter recovery v1\n".utf8).write(to: journal, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journal.path)
  }
  private func releaseOwnership() throws {
    watchdog?.cancel()
    watchdog = nil
    if FileManager.default.fileExists(atPath: journal.path) {
      try FileManager.default.removeItem(at: journal)
    }
  }
  public func recover() throws {
    try lock.withLock {
      if FileManager.default.fileExists(atPath: journal.path) {
        do {
          try transport.setEnabled(true)
          revision &+= 1
          try releaseOwnership()
        } catch {
          validated = false
          startWatchdog()
          throw error
        }
      }
      chargingAllowed = true
      discharge = false
    }
  }
  /// Called before acknowledging system sleep; never suppresses lid-close sleep.
  public func prepareForSleep() {
    lock.withLock {
      validated = false
      try? recover()
    }
  }
  public func safetyCheck() {
    lock.withLock {
      guard FileManager.default.fileExists(atPath: journal.path) else { return }
      let snapshot = transport.snapshot()
      if !validated || transport.lidClosed != false || snapshot.pluggedIn != true
        || (snapshot.percentage ?? 0) <= 15
        || snapshot.temperature == nil || (snapshot.temperature ?? 100) >= 50
      {
        validated = false
        try? recover()
      }
    }
  }
  private func startWatchdog() {
    guard watchdog == nil else { return }
    let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
    // Lid and power events trigger safetyCheck immediately; this fallback only
    // covers slow reserve and temperature changes.
    timer.schedule(deadline: .now() + 10, repeating: 10, leeway: .seconds(2))
    timer.setEventHandler { [weak self] in self?.safetyCheck() }
    watchdog = timer
    timer.resume()
  }
}
