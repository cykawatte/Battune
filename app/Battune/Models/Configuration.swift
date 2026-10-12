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
public struct AppSettings: Codable, Equatable, Sendable {
  public var advancedControl: Bool?
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
  public func validate() throws {
    try charge.validate()
    guard schema == 1, schedules.count <= 32, Set(schedules.map(\.id)).count == schedules.count,
      ["system", "en", "de"].contains(language), !controlEnabled || onboardingComplete
    else { throw BattuneError.invalidConfiguration }
    for schedule in schedules { try schedule.validate() }
  }
}
