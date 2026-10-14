import Foundation

public final class SettingsStore {
  private let defaults: UserDefaults
  public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
  public func load() throws -> AppSettings {
    guard let data = defaults.data(forKey: "settings.v1") else { return AppSettings() }
    do {
      let value = try JSONDecoder().decode(AppSettings.self, from: data)
      try value.validate()
      return value
    } catch { throw BattuneError.corruptPersistence }
  }
  public func save(_ value: AppSettings) throws {
    try value.validate()
    let data = try JSONEncoder().encode(value)
    if defaults.data(forKey: "settings.v1") != data { defaults.set(data, forKey: "settings.v1") }
  }
  public func loadCalibration() throws -> CalibrationSession {
    guard let data = defaults.data(forKey: "calibration.v1") else { return CalibrationSession() }
    do {
      var value = try JSONDecoder().decode(CalibrationSession.self, from: data)
      guard (0...7).contains(value.phase), (20...50).contains(value.low),
        (0...7200).contains(value.settle)
      else { throw BattuneError.corruptPersistence }
      // Never resume a potentially dangerous workflow automatically after a crash.
      if value.active { value.phase = 7 }
      return value
    } catch { throw BattuneError.corruptPersistence }
  }
  public func saveCalibration(_ value: CalibrationSession) throws {
    defaults.set(try JSONEncoder().encode(value), forKey: "calibration.v1")
  }
  public func loadOverride() -> ChargeOverride? {
    guard let data = defaults.data(forKey: "override.v1") else { return nil }
    // A corrupt override is dropped: the configured limit is always the safe default.
    guard let value = try? JSONDecoder().decode(ChargeOverride.self, from: data),
      value.pausedAt.map({ (0...100).contains($0) }) ?? true
    else {
      defaults.removeObject(forKey: "override.v1")
      return nil
    }
    return value
  }
  public func saveOverride(_ value: ChargeOverride?) {
    guard let value, let data = try? JSONEncoder().encode(value) else {
      defaults.removeObject(forKey: "override.v1")
      return
    }
    defaults.set(data, forKey: "override.v1")
  }
  public var scheduleToken: String? {
    get { defaults.string(forKey: "schedule.activation") }
    set { if scheduleToken != newValue { defaults.set(newValue, forKey: "schedule.activation") } }
  }
}
