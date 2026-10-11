import Foundation

public struct BatterySnapshot: Codable, Equatable, Sendable {
  public var percentage: Int?
  public var pluggedIn: Bool?
  public var charging: Bool?
  public var fullyCharged: Bool?
  public var powerSource: String?
  public var temperature: Double?
  public var cycleCount: Int?
  public var currentCapacity: Int?
  public var maximumCapacity: Int?
  public var designCapacity: Int?
  public var health: Double?
  public var voltage: Double?
  public var current: Double?
  public var power: Double?
  public var adapterWatts: Int?
  public var timestamp: Date
  public init(
    percentage: Int? = nil, pluggedIn: Bool? = nil, charging: Bool? = nil,
    temperature: Double? = nil, timestamp: Date = Date()
  ) {
    self.percentage = percentage
    self.pluggedIn = pluggedIn
    self.charging = charging
    self.temperature = temperature
    self.timestamp = timestamp
  }
}
public struct Capabilities: Codable, Equatable, Sendable {
  public var readBattery: Bool
  public var readTemperature: Bool
  public var setLimit: Bool
  public var toggleCharging: Bool
  public var forceDischarge: Bool
  public var reset: Bool
  /// Present only when macOS itself enforces the charge limit.
  public var nativeChargeLimits: [Int]?
  public var adapterControl: Bool?
  public init(
    readBattery: Bool = false, readTemperature: Bool = false, setLimit: Bool = false,
    toggleCharging: Bool = false, forceDischarge: Bool = false, reset: Bool = false,
    nativeChargeLimits: [Int]? = nil, adapterControl: Bool? = nil
  ) {
    self.readBattery = readBattery
    self.readTemperature = readTemperature
    self.setLimit = setLimit
    self.toggleCharging = toggleCharging
    self.forceDischarge = forceDischarge
    self.reset = reset
    self.nativeChargeLimits = nativeChargeLimits
    self.adapterControl = adapterControl
  }
  public var mask: Int32 {
    (setLimit ? 1 : 0) | (toggleCharging ? 2 : 0) | (forceDischarge ? 4 : 0) | (reset ? 8 : 0)
  }
  public var canControl: Bool { (setLimit || toggleCharging) && reset }
  public var canCalibrate: Bool { toggleCharging && forceDischarge && reset }
}
public enum BattuneError: Int, Error, Codable, Sendable {
  case invalidConfiguration = 1
  case invalidSnapshot, unsupported, notImplemented, hardwareError, helperUnavailable, unauthorized,
    rateLimited, corruptPersistence, protocolMismatch
}
public enum HardwareCommand: Equatable, Sendable {
  case limit(Int)
  case charging(Bool)
  case discharge(Bool)
  case reset
}
public struct HelperStatus: Codable, Sendable {
  public let version: String
  public let backend: String
  public let capabilities: Capabilities
  public let confirmedLimit: Int?
  public let controlGeneration: UInt64?
  public let hardwareDiagnostic: String?
  public init(
    version: String = "0.1.0-beta.1", backend: String, capabilities: Capabilities,
    confirmedLimit: Int? = nil, controlGeneration: UInt64? = nil, hardwareDiagnostic: String? = nil
  ) {
    self.version = version
    self.backend = backend
    self.capabilities = capabilities
    self.confirmedLimit = confirmedLimit
    self.controlGeneration = controlGeneration
    self.hardwareDiagnostic = hardwareDiagnostic
  }
}
