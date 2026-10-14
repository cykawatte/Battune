import Foundation

public struct ChargeSettings: Codable, Equatable, Sendable {
  public var limit = 80
  public var sailing = false
  public var lower = 75
  public var thermal = true
  public var resumeTemperature = 35.0
  public var stopTemperature = 40.0
  public init() {}
  public func validate() throws {
    guard (20...100).contains(limit), (20...99).contains(lower), !sailing || lower < limit,
      resumeTemperature.isFinite, stopTemperature.isFinite,
      resumeTemperature >= 20, stopTemperature <= 50, resumeTemperature < stopTemperature
    else { throw BattuneError.invalidConfiguration }
  }
}
public struct ChargeSchedule: Codable, Equatable, Identifiable, Sendable {
  public var id: UInt32
  public var days: UInt32 = 127
  public var minute = 480
  public var priority: Int32 = 0
  public var enabled = true
  public var settings = ChargeSettings()
  public var dischargeTarget: Int?
  public init(id: UInt32) { self.id = id }
  public func validate() throws {
    try settings.validate()
    guard days > 0, days <= 127, (0..<1440).contains(minute),
      dischargeTarget.map({ (20...100).contains($0) }) ?? true
    else { throw BattuneError.invalidConfiguration }
  }
}
/// What the menu bar shows next to the Battune mark.
public enum MenuBarDetail: Int, Codable, CaseIterable, Sendable {
  case none = 0
  case percentage, power, temperature, time
}
/// MagSafe indicator preference; raw values match the Rust core.
public enum IndicatorStyle: Int, Codable, CaseIterable, Sendable {
  case system = 0
  case off, chargeState
}
/// Low Power Mode management; raw values are persisted.
public enum PowerModePolicy: Int, Codable, CaseIterable, Sendable {
  case unmanaged = 0
  case never, always, onBattery, onAdapter
  /// pmset profiles: battery (-b) and charger (-c). nil leaves macOS unchanged.
  public var profiles: (battery: Bool, charger: Bool)? {
    switch self {
    case .unmanaged: return nil
    case .never: return (false, false)
    case .always: return (true, true)
    case .onBattery: return (true, false)
    case .onAdapter: return (false, true)
    }
  }
}
/// A temporary deviation from the configured limit, resolved by the Rust core.
public struct ChargeOverride: Codable, Equatable, Sendable {
  public enum Kind: Int32, Codable, Sendable {
    case topUp = 1
    case pause = 2
  }
  public var kind: Kind
  public var pausedAt: Int?
  public var started: Date
  public init(kind: Kind, pausedAt: Int? = nil, started: Date = Date()) {
    self.kind = kind
    self.pausedAt = pausedAt
    self.started = started
  }
}
public struct AppSettings: Codable, Equatable, Sendable {
  public var advancedControl: Bool?
  /// nil = true: the native macOS limit stays set after quitting Battune.
  public var keepLimitOnQuit: Bool?
  public var menuBarDetail: MenuBarDetail?
  public var indicatorStyle: IndicatorStyle?
  public var powerMode: PowerModePolicy?
  public var setupComplete: Bool?
  public var tutorialVersion: Int?
  public var schema = 1
  public var onboardingComplete = false
  public var controlEnabled = false
  public var showPercentage = true
  public var statisticsEnabled = true
  public var notificationsEnabled = false
  public var language = "system"
  public var charge = ChargeSettings()
  public var schedules: [ChargeSchedule] = []
  public init() {}
  public var keepsLimitOnQuit: Bool { keepLimitOnQuit ?? true }
  /// Migrates the original percentage toggle.
  public var effectiveMenuBarDetail: MenuBarDetail {
    menuBarDetail ?? (showPercentage ? .percentage : .none)
  }
  public func validate() throws {
    try charge.validate()
    guard schema == 1, schedules.count <= 32, Set(schedules.map(\.id)).count == schedules.count,
      ["system", "en", "de"].contains(language), !controlEnabled || onboardingComplete
    else { throw BattuneError.invalidConfiguration }
    for schedule in schedules { try schedule.validate() }
  }
}
