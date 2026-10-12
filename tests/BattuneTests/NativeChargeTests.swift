import BattuneDomain
import BattuneSystem
import Foundation

final class FakeNativeTransport: NativeChargeTransport {
  var state = NativeChargeState(limit: 90, enabled: true, limits: [80, 85, 90, 95, 100])
  var writes: [Int] = []
  var readDelay: TimeInterval = 0
  var ignoreWrites = false
  var failWrites = false
  func read() throws -> NativeChargeState {
    if readDelay > 0 { Thread.sleep(forTimeInterval: readDelay) }
    return state
  }
  func setLimit(_ limit: Int) throws {
    writes.append(limit)
    if failWrites { throw BattuneError.hardwareError }
    if !ignoreWrites {
      state.limit = limit
      state.enabled = limit != 100
    }
  }
  func disable() throws { state.enabled = false }
}

@MainActor final class NativeChargeTests {
  private func fixture() -> (FakeNativeTransport, URL, NativeChargeSession) {
    let fake = FakeNativeTransport()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "Battune-native-tests-\(UUID().uuidString)/session.json")
    return (fake, url, NativeChargeSession(transport: fake, journalURL: url))
  }
  func testWriteReadbackAndRestore() throws {
    let (fake, url, session) = fixture()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try session.perform(.reset)
    expectTrue(fake.writes.isEmpty)
    try session.perform(.limit(80))
    expectEqual(try session.read().effectiveLimit, 80)
    try session.perform(.limit(85))
    try session.perform(.limit(85))
    expectEqual(fake.writes, [80, 85])
    try session.perform(.reset)
    expectEqual(fake.state.effectiveLimit, 90)
    expectFalse(FileManager.default.fileExists(atPath: url.path))
    try session.perform(.reset)
    expectEqual(fake.writes, [80, 85, 90])
  }
  func testUnsupportedAndReadbackFailure() throws {
    let (fake, url, session) = fixture()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    for command: HardwareCommand in [
      .limit(79), .limit(81), .limit(101), .charging(false), .discharge(true),
    ] {
      expectThrows(try session.perform(command))
    }
    expectTrue(fake.writes.isEmpty)
    fake.ignoreWrites = true
    expectThrows(try session.perform(.limit(80))) {
      expectEqual($0 as? BattuneError, .hardwareError)
    }
    expectEqual(fake.state.effectiveLimit, 90)
    expectFalse(FileManager.default.fileExists(atPath: url.path))
  }
  func testCrashRecoveryAndExternalChanges() throws {
    let (fake, url, session) = fixture()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try session.perform(.limit(80))
    let relaunched = NativeChargeSession(transport: fake, journalURL: url)
    try relaunched.perform(.reset)
    expectEqual(fake.state.effectiveLimit, 90)
    try relaunched.perform(.limit(80))
    fake.state.limit = 95  // The user changes System Settings outside Battune.
    try relaunched.perform(.reset)
    expectEqual(fake.state.effectiveLimit, 95)
    expectFalse(FileManager.default.fileExists(atPath: url.path))
  }
  func testFailedRecoveryAndCorruption() throws {
    let (fake, url, session) = fixture()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try session.perform(.limit(80))
    fake.failWrites = true
    expectThrows(try session.perform(.reset))
    expectTrue(FileManager.default.fileExists(atPath: url.path))
    fake.failWrites = false
    try session.perform(.reset)
    expectEqual(fake.state.limit, 90)
    try Data("broken".utf8).write(to: url)
    let count = fake.writes.count
    expectThrows(try session.perform(.limit(80))) {
      expectEqual($0 as? BattuneError, .corruptPersistence)
    }
    expectEqual(fake.writes.count, count)
  }
  func testDisabledBaseline() throws {
    let (fake, url, session) = fixture()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    fake.state.enabled = false
    try session.perform(.limit(80))
    try session.perform(.reset)
    expectEqual(fake.state.limit, 90)
    expectFalse(fake.state.enabled)
    expectEqual(fake.state.effectiveLimit, 100)
  }
  func testNativeCoordinator() async throws {
    let (fake, url, session) = fixture()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let suite = "Battune.native-tests.\(UUID().uuidString)"
    let defaults = try unwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = SettingsStore(defaults: defaults)
    let history = HistoryStore(
      url: url.deletingLastPathComponent().appendingPathComponent("history.json"))
    var settings = AppSettings()
    settings.onboardingComplete = true
    settings.controlEnabled = true
    // Defaults include thermal protection; native macOS protection must not be
    // mistaken for a missing custom temperature sensor that blocks all charging.
    let provider = MockBackend()
    provider.snapshot.temperature = nil
    provider.snapshot.pluggedIn = false
    let client = NativeChargeClient(session: session)
    let coordinator = ChargeCoordinator(
      settings: settings, store: store, history: history,
      provider: provider, client: client)
    coordinator.refresh()
    await settle(coordinator)
    expectEqual(coordinator.mode, .nativeLimit)
    expectEqual(coordinator.helper?.confirmedLimit, 80)
    expectFalse(coordinator.sensorMissing)
    expectFalse(coordinator.capabilities.canCalibrate)
    expectEqual(fake.state.effectiveLimit, 80)
    fake.state.limit = 95
    coordinator.refresh()
    await settle(coordinator)
    expectEqual(fake.state.limit, 80)
    settings.controlEnabled = false
    coordinator.updateSettings(settings)
    await settle(coordinator)
    expectEqual(fake.state.limit, 90)
    expectEqual(coordinator.mode, .system)
    settings.controlEnabled = true
    settings.charge.limit = 81
    coordinator.updateSettings(settings)
    await settle(coordinator)
    expectEqual(coordinator.mode, .unavailable)
    expectEqual(coordinator.lastError, .unsupported)
    expectEqual(fake.state.limit, 90)
    settings.charge.limit = 85
    coordinator.updateSettings(settings)
    await settle(coordinator)
    expectEqual(fake.state.limit, 85)
    await coordinator.shutdown()
    expectEqual(fake.state.limit, 90)
  }
  func testAdvancedModeKeepsNativeLimitAcrossSleep() async throws {
    let (fake, url, session) = fixture()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let suite = "Battune.routing-tests.\(UUID().uuidString)"
    let defaults = try unwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let helper = MockBackend()
    helper.supported.adapterControl = true
    let router = PlatformHardwareClient(
      native: NativeChargeClient(session: session), helper: helper)
    var settings = AppSettings()
    settings.onboardingComplete = true
    settings.controlEnabled = true
    settings.advancedControl = true
    let coordinator = ChargeCoordinator(
      settings: settings, store: SettingsStore(defaults: defaults),
      history: HistoryStore(url: url.deletingLastPathComponent().appendingPathComponent("history")),
      provider: helper, client: router)
    coordinator.refresh()
    await settle(coordinator)
    expectEqual(coordinator.mode, .nativeLimit)
    expectEqual(fake.state.limit, 80)
    expectTrue(helper.commands.isEmpty)  // Never cut AC merely because advanced is enabled.
    expectTrue(coordinator.capabilities.canCalibrate)
    expectTrue(coordinator.capabilities.forceDischarge)
    coordinator.willSleep()
    expectEqual(fake.state.limit, 80)
    expectEqual(fake.writes, [80])
    helper.disconnected = true  // Sleep revokes helper validation; native stays usable.
    coordinator.didWake()
    await settle(coordinator)
    expectEqual(coordinator.mode, .nativeLimit)
    expectEqual(fake.state.limit, 80)
    expectFalse(coordinator.capabilities.canCalibrate)
    helper.disconnected = false
    coordinator.refresh()
    await settle(coordinator)
    coordinator.startDischarge(target: 40)
    await settle(coordinator)
    expectTrue(helper.commands.contains(.discharge(true)))
    expectEqual(fake.state.limit, 100)
    coordinator.cancelWorkflow()
    await settle(coordinator)
    expectEqual(helper.commands.last, .reset)
    expectEqual(coordinator.mode, .nativeLimit)
    expectEqual(fake.state.limit, 80)
    coordinator.startCalibration()
    await settle(coordinator)
    expectTrue(coordinator.calibration.active)
    expectEqual(coordinator.mode, .calibration)
    coordinator.willSleep()
    expectEqual(coordinator.calibration.phase, 7)
    coordinator.didWake()
    await settle(coordinator)
    expectEqual(coordinator.mode, .nativeLimit)
    expectEqual(fake.state.limit, 80)
    settings.charge.limit = 77
    coordinator.updateSettings(settings)
    await settle(coordinator)
    expectTrue(coordinator.capabilities.adapterControl == true)
    expectEqual(fake.state.limit, 100)
    settings.charge.limit = 80
    coordinator.updateSettings(settings)
    await settle(coordinator)
    expectEqual(coordinator.mode, .nativeLimit)
    expectEqual(fake.state.limit, 80)
    await coordinator.shutdown()
    expectEqual(fake.state.limit, 90)
  }
  func testNativeTimeout() async throws {
    let (fake, url, session) = fixture()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    fake.readDelay = 0.15
    let client = NativeChargeClient(session: session, timeout: 0.01)
    do {
      _ = try await client.status()
      expectTrue(false)
    } catch { expectEqual(error as? BattuneError, .hardwareError) }
    // This write times out while queued behind the blocked read and must never run.
    do {
      try await client.perform(.limit(80))
      expectTrue(false)
    } catch { expectEqual(error as? BattuneError, .hardwareError) }
    try await Task.sleep(nanoseconds: 250_000_000)
    expectTrue(fake.writes.isEmpty)
  }
  private func settle(_ coordinator: ChargeCoordinator) async {
    for _ in 0..<500 {
      if !coordinator.busy { return }
      try? await Task.sleep(nanoseconds: 2_000_000)
    }
    expectFalse(coordinator.busy)
  }
}
