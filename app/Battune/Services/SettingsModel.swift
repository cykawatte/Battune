import BattuneDomain
import Combine
import Foundation
import ServiceManagement

@MainActor public final class SettingsModel: ObservableObject {
  @Published public var value: AppSettings
  @Published public private(set) var error: BattuneError?
  @Published public private(set) var loginEnabled = SMAppService.mainApp.status == .enabled
  public let store: SettingsStore
  /// Last value handed to the coordinator; avoids redundant re-evaluations.
  private var applied: AppSettings?
  public init(store: SettingsStore = SettingsStore()) {
    self.store = store
    do { value = try store.load() } catch {
      value = AppSettings()
      self.error = .corruptPersistence
    }
    applied = value
  }
  /// Saves and applies the current value. Returns false if validation failed.
  @discardableResult public func commit(to coordinator: ChargeCoordinator) -> Bool {
    guard save() else { return false }
    UserDefaults.standard.set(value.language, forKey: "ui.language")
    if applied != value {
      applied = value
      coordinator.updateSettings(value)
    }
    return true
  }
  @discardableResult public func save() -> Bool {
    do {
      try store.save(value)
      error = nil
      return true
    } catch {
      self.error = error as? BattuneError ?? .corruptPersistence
      return false
    }
  }
  public func setLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      loginEnabled = SMAppService.mainApp.status == .enabled
      error = nil
    } catch {
      self.error = .unauthorized
      loginEnabled = SMAppService.mainApp.status == .enabled
    }
  }
}
