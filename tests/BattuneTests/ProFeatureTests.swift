import BattuneDomain
import BattuneHardware
import BattuneSystem
import CBattuneCore
import Foundation

final class FakeAccessories: AccessoryTransport {
  var privileged = true
  var indicatorAvailable = true
  var indicator: [Int] = []
  var powerModes: [[Bool]] = []
  func setIndicator(_ value: Int) throws { indicator.append(value) }
  func setLowPowerMode(battery: Bool, charger: Bool) throws {
    powerModes.append([battery, charger])
  }
}

@MainActor final class ProFeatureTests {
  private let native = NativeChargeTests()
  private func environment(
    _ settings: AppSettings, helper: MockBackend, provider: MockBackend? = nil
  ) throws -> (FakeNativeTransport, ChargeCoordinator, () -> Void) {
    let (fake, url, session) = native.fixture()
    let suite = "Battune.pro-tests.\(UUID().uuidString)"
    let defaults = try unwrap(UserDefaults(suiteName: suite))
    let router = PlatformHardwareClient(
      native: NativeChargeClient(session: session), helper: helper)
    let coordinator = ChargeCoordinator(
      settings: settings, store: SettingsStore(defaults: defaults),
      history: HistoryStore(url: url.deletingLastPathComponent().appendingPathComponent("h.json")),
      provider: provider ?? helper, client: router)
    return (
      fake, coordinator,
      {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
      }
    )
  }
  private func enabled(limit: Int, advanced: Bool) -> AppSettings {
    var settings = AppSettings()
    settings.onboardingComplete = true
    settings.controlEnabled = true
    settings.advancedControl = advanced
    settings.charge.limit = limit
    settings.charge.lower = max(20, min(75, limit - 1))
    return settings
  }

  /// Regression for the reported "app breaks below 80%": with the lid closed every
  /// sub-80 limit keeps adapter input on and falls back to the native 80% ceiling.
  func testSubEightyLimitsWithClosedLid() async throws {
    for limit in 20...79 {
      let helper = MockBackend()
      helper.supported.adapterControl = true
      helper.supported.controlBlock = .lidClosed
      helper.snapshot.percentage = 85
      let (fake, coordinator, cleanup) = try environment(
        enabled(limit: limit, advanced: true), helper: helper)
      defer { cleanup() }
      coordinator.refresh()
      await native.settle(coordinator)
      expectTrue(helper.commands.isEmpty)
      expectEqual(fake.state.effectiveLimit, 80)
      expectEqual(coordinator.fallbackNativeLimit, 80)
      expectEqual(coordinator.helperError, .lidClosed)
      // Opening the lid hands the hold to the adapter, keeping the native ceiling.
      helper.supported.controlBlock = nil
      coordinator.retry()
      await native.settle(coordinator)
      expectTrue(helper.commands.contains(.charging(false)))
      expectEqual(fake.state.effectiveLimit, 80)
      // Closing it again never issues another adapter cut.
      let before = helper.commands.count
      helper.supported.controlBlock = .lidClosed
      coordinator.refresh()
      await native.settle(coordinator)
      expectEqual(helper.commands.count, before)
      expectEqual(fake.state.effectiveLimit, 80)
      await coordinator.shutdown()
      expectEqual(helper.commands.last, .reset)
    }
  }

  func testTopUpPauseAndKeepLimit() async throws {
    let helper = MockBackend()
    helper.snapshot.percentage = 83
    var settings = enabled(limit: 95, advanced: false)
    settings.charge.limit = 95
    let (fake, coordinator, cleanup) = try environment(settings, helper: helper)
    defer { cleanup() }
    coordinator.refresh()
    await native.settle(coordinator)
    expectEqual(fake.state.effectiveLimit, 95)
    coordinator.topUp()
    await native.settle(coordinator)
    expectEqual(fake.state.effectiveLimit, 100)
    expectEqual(coordinator.effectiveLimit, 100)
    expectEqual(coordinator.chargeOverride?.kind, .topUp)
    helper.snapshot.pluggedIn = false
    coordinator.refresh()
    await native.settle(coordinator)
    expectEqual(coordinator.chargeOverride, nil)
    expectEqual(fake.state.effectiveLimit, 95)
    helper.snapshot.pluggedIn = true
    coordinator.pauseCharging()
    await native.settle(coordinator)
    // 83% is not a native step: the pause rounds up to 85%, never down.
    expectEqual(coordinator.chargeOverride?.pausedAt, 83)
    expectEqual(fake.state.effectiveLimit, 85)
    coordinator.resumePlan()
    await native.settle(coordinator)
    expectEqual(fake.state.effectiveLimit, 95)
    await coordinator.shutdown()
    // Like System Settings, the native limit outlives the app by default.
    expectEqual(fake.state.effectiveLimit, 95)
  }

  func testOverridesRequireControlAndEndWithWorkflows() async throws {
    let helper = MockBackend()
    var settings = enabled(limit: 80, advanced: false)
    settings.controlEnabled = false
    let (fake, coordinator, cleanup) = try environment(settings, helper: helper)
    defer { cleanup() }
    coordinator.topUp()
    expectEqual(coordinator.lastError, .unsupported)
    expectEqual(coordinator.chargeOverride, nil)
    settings.controlEnabled = true
    coordinator.updateSettings(settings)
    await native.settle(coordinator)
    coordinator.topUp()
    await native.settle(coordinator)
    expectEqual(fake.state.effectiveLimit, 100)
    settings.controlEnabled = false
    coordinator.updateSettings(settings)
    await native.settle(coordinator)
    expectEqual(coordinator.chargeOverride, nil)
    expectEqual(fake.state.effectiveLimit, 90)
  }

  func testAccessoriesApplyOnceAndRestore() async throws {
    let helper = MockBackend()
    helper.supported.indicatorControl = true
    helper.supported.powerModeControl = true
    helper.snapshot.charging = false
    var settings = enabled(limit: 80, advanced: false)
    settings.indicatorStyle = .chargeState
    settings.powerMode = .onBattery
    let (_, coordinator, cleanup) = try environment(settings, helper: helper)
    defer { cleanup() }
    for _ in 0..<3 {
      coordinator.refresh()
      await native.settle(coordinator)
    }
    expectEqual(helper.indicatorWrites, [3])
    expectEqual(helper.powerModeWrites, [[true, false]])
    helper.snapshot.charging = true
    coordinator.refresh()
    await native.settle(coordinator)
    expectEqual(helper.indicatorWrites, [3, 4])
    settings.indicatorStyle = .off
    coordinator.updateSettings(settings)
    await native.settle(coordinator)
    expectEqual(helper.indicatorWrites.last, 1)
    expectEqual(helper.powerModeWrites.count, 1)
    await coordinator.shutdown()
    expectEqual(helper.indicatorWrites.last, 0)
  }

  func testAccessoryGate() throws {
    let mock = MockBackend()
    let accessories = FakeAccessories()
    let gate = HardwareGate(backend: mock, accessories: accessories)
    expectTrue(gate.capabilities().indicatorControl == true)
    for value in [-1, 2, 5, 255] {
      expectThrows(try gate.setIndicator(value)) {
        expectEqual($0 as? BattuneError, .invalidConfiguration)
      }
    }
    try gate.setIndicator(3, now: 0)
    try gate.setLowPowerMode(battery: true, charger: false, now: 0)
    expectEqual(accessories.indicator, [3])
    expectEqual(accessories.powerModes, [[true, false]])
    for _ in 0..<10 { try gate.setIndicator(1, now: 0) }
    expectThrows(try gate.setIndicator(1, now: 0)) {
      expectEqual($0 as? BattuneError, .rateLimited)
    }
    accessories.privileged = false
    expectFalse(gate.capabilities().indicatorControl == true)
    expectThrows(try gate.setIndicator(0, now: 100)) {
      expectEqual($0 as? BattuneError, .unauthorized)
    }
  }

  func testCoreInsightsBridge() throws {
    let topUp = try CoreBridge.resolve(
      configured: 80, override: ChargeOverride(kind: .topUp), plugged: true)
    expectEqual(topUp.limit, 100)
    expectFalse(topUp.complete)
    expectTrue(
      try CoreBridge.resolve(
        configured: 80, override: ChargeOverride(kind: .topUp), plugged: false
      ).complete)
    let pause = try CoreBridge.resolve(
      configured: 80, override: ChargeOverride(kind: .pause, pausedAt: 95), plugged: true)
    expectEqual(pause.limit, 80)
    expectEqual(CoreBridge.nativeCeiling(77, supported: [80, 85, 90, 95, 100]), 80)
    expectEqual(CoreBridge.nativeCeiling(101, supported: [80]), nil)
    var snapshot = BatterySnapshot(percentage: 50, pluggedIn: true, charging: true)
    snapshot.currentCapacity = 2000
    snapshot.maximumCapacity = 4000
    snapshot.current = 2
    expectEqual(CoreBridge.estimate(snapshot, target: 80).toTarget, 36)
    snapshot.current = nil
    expectEqual(CoreBridge.estimate(snapshot, target: 80).toTarget, nil)
    expectEqual(
      CoreBridge.indicator(style: .chargeState, mode: .nativeLimit, plugged: true, charging: false),
      3)
    expectEqual(
      CoreBridge.indicator(style: .system, mode: .charging, plugged: true, charging: true), 0)
  }

  func testNextScheduleActivationAndSettingsMigration() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try unwrap(TimeZone(identifier: "Europe/Berlin"))
    // Sunday 2026-10-11 10:00 local time.
    let sunday = try unwrap(
      calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 10)))
    var monday = ChargeSchedule(id: 1)
    monday.days = 1
    monday.minute = 8 * 60
    let next = try unwrap(
      ScheduleResolver.nextActivation([monday], after: sunday, calendar: calendar))
    expectEqual(calendar.component(.weekday, from: next), 2)
    expectEqual(calendar.component(.hour, from: next), 8)
    monday.enabled = false
    expectEqual(ScheduleResolver.nextActivation([monday], after: sunday, calendar: calendar), nil)
    // Settings from 0.1 decode with the new optional fields at safe defaults.
    let legacy = Data(
      #"{"schema":1,"onboardingComplete":true,"controlEnabled":false,"showPercentage":false,"statisticsEnabled":true,"notificationsEnabled":false,"language":"system","charge":{"limit":80,"sailing":false,"lower":75,"thermal":true,"resumeTemperature":35,"stopTemperature":40},"schedules":[]}"#
        .utf8)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: legacy)
    expectTrue(decoded.keepsLimitOnQuit)
    expectEqual(decoded.effectiveMenuBarDetail, .none)
    expectEqual(decoded.indicatorStyle, nil)
    try decoded.validate()
  }
}
