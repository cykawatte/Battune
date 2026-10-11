import BattuneDomain
import BattuneHardware
import BattuneShared
import BattuneSystem
import Foundation
import Security

private final class TestAdapter: AdapterTransport {
  var privileged = true
  var enabled = true
  var writes: [Bool] = []
  var failNext = false
  var battery = BatterySnapshot(percentage: 70, pluggedIn: true, charging: true, temperature: 30)
  func isEnabled() throws -> Bool { enabled }
  func setEnabled(_ value: Bool) throws {
    writes.append(value)
    if failNext {
      failNext = false
      throw BattuneError.hardwareError
    }
    enabled = value
  }
  func snapshot() -> BatterySnapshot { battery }
}
private final class AdapterTestClient: HardwareClient, BatteryProviding {
  let backend: AdapterBackend
  init(_ backend: AdapterBackend) { self.backend = backend }
  func read() -> BatterySnapshot { backend.readBatterySnapshot() }
  func hardwareSnapshot() async throws -> BatterySnapshot? { read() }
  func configureAdvanced(_ enabled: Bool) async throws {}
  func perform(_ command: HardwareCommand) async throws { try backend.perform(command) }
  func status() async throws -> HelperStatus {
    HelperStatus(
      backend: backend.name, capabilities: backend.capabilities(),
      controlGeneration: backend.generation)
  }
  func renewLease() async throws {}
}
@MainActor final class AdapterTests {
  private func withAdapter(_ body: (AdapterBackend, TestAdapter, URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let transport = TestAdapter()
    let journal = directory.appendingPathComponent("adapter-owned")
    let backend = AdapterBackend(transport: transport, journal: journal)
    try body(backend, transport, journal)
    try backend.recover()
  }
  func testValidation() throws {
    try withAdapter { backend, transport, journal in
      expectFalse(backend.capabilities().canControl)
      expectThrows(try backend.validate())
      expectTrue(transport.writes.isEmpty)
      backend.setSleepProtectionReady(true)
      transport.privileged = false
      expectThrows(try backend.validate())
      transport.privileged = true
      transport.battery.pluggedIn = false
      expectThrows(try backend.validate())
      transport.battery.pluggedIn = true
      transport.battery.percentage = 29
      expectThrows(try backend.validate())
      transport.battery.percentage = 70
      transport.battery.temperature = 40
      expectThrows(try backend.validate())
      expectTrue(transport.writes.isEmpty)
      transport.battery.temperature = 30
      try backend.validate()
      expectEqual(transport.writes, [false, true])
      expectTrue(backend.capabilities().canCalibrate)
      expectFalse(FileManager.default.fileExists(atPath: journal.path))
    }
  }
  func testRollback() throws {
    try withAdapter { backend, transport, journal in
      backend.setSleepProtectionReady(true)
      transport.failNext = true
      expectThrows(try backend.validate())
      expectEqual(transport.writes, [false, true])
      expectTrue(transport.enabled)
      expectFalse(backend.capabilities().canControl)
      expectFalse(FileManager.default.fileExists(atPath: journal.path))
    }
  }
  func testCompositionAndRecovery() throws {
    try withAdapter { backend, transport, journal in
      backend.setSleepProtectionReady(true)
      try backend.validate()
      try backend.perform(.charging(false))
      expectFalse(transport.enabled)
      expectTrue(FileManager.default.fileExists(atPath: journal.path))
      try backend.perform(.discharge(true))
      try backend.perform(.charging(true))
      expectFalse(transport.enabled)
      try backend.perform(.discharge(false))
      expectTrue(transport.enabled)
      expectFalse(FileManager.default.fileExists(atPath: journal.path))
      expectThrows(try backend.perform(.limit(77)))
      try backend.perform(.charging(false))
      let recovered = AdapterBackend(transport: transport, journal: journal)
      try recovered.recover()
      expectTrue(transport.enabled)
      expectFalse(recovered.capabilities().canControl)
      expectFalse(FileManager.default.fileExists(atPath: journal.path))
      try backend.perform(.reset)
    }
  }
  func testSafetyAndSleep() throws {
    try withAdapter { backend, transport, _ in
      backend.setSleepProtectionReady(true)
      try backend.validate()
      try backend.perform(.charging(false))
      transport.battery.percentage = 20
      backend.safetyCheck()
      expectFalse(transport.enabled)
      transport.battery.percentage = 15
      backend.safetyCheck()
      expectTrue(transport.enabled)
      expectFalse(backend.capabilities().canControl)
      transport.battery.percentage = 70
      try backend.validate()
      try backend.perform(.charging(false))
      let generation = backend.generation
      backend.prepareForSleep()
      expectTrue(transport.enabled)
      expectTrue(backend.generation > generation)
      expectThrows(try backend.perform(.charging(false)))
      try backend.validate()
      transport.battery.temperature = nil
      expectThrows(try backend.perform(.charging(false)))
      expectTrue(transport.enabled)
    }
  }
  func testGateRecoveryInvalidatesCache() throws {
    try withAdapter { backend, transport, _ in
      backend.setSleepProtectionReady(true)
      let gate = HardwareGate(backend: backend)
      try gate.validateAdapter()
      try gate.perform(.charging(false))
      try backend.recover()
      expectTrue(transport.enabled)
      try gate.perform(.charging(false))
      expectFalse(transport.enabled)
      backend.prepareForSleep()
      // Reset must remain available after validation has been revoked.
      try gate.perform(.reset)
      expectTrue(transport.enabled)
    }
  }
  func testCoordinatorFullWorkflow() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let name = "BattuneTests.\(UUID().uuidString)"
    let defaults = try unwrap(UserDefaults(suiteName: name))
    defer {
      defaults.removePersistentDomain(forName: name)
      try? FileManager.default.removeItem(at: directory)
    }
    let transport = TestAdapter()
    let backend = AdapterBackend(
      transport: transport, journal: directory.appendingPathComponent("owned"))
    backend.setSleepProtectionReady(true)
    try backend.validate()
    let client = AdapterTestClient(backend)
    var settings = AppSettings()
    settings.onboardingComplete = true
    settings.controlEnabled = true
    settings.advancedControl = true
    settings.charge.limit = 77
    let coordinator = ChargeCoordinator(
      settings: settings, store: SettingsStore(defaults: defaults),
      history: HistoryStore(url: directory.appendingPathComponent("history")), provider: client,
      client: client)
    let integration = IntegrationTests()
    coordinator.refresh()
    await integration.settle(coordinator)
    expectTrue(transport.enabled)
    transport.battery.percentage = 77
    coordinator.refresh()
    await integration.settle(coordinator)
    expectFalse(transport.enabled)
    transport.battery.percentage = 74
    coordinator.refresh()
    await integration.settle(coordinator)
    expectFalse(transport.enabled)
    transport.battery.percentage = 72
    coordinator.refresh()
    await integration.settle(coordinator)
    expectTrue(transport.enabled)
    coordinator.startDischarge(target: 60)
    await integration.settle(coordinator)
    expectFalse(transport.enabled)
    transport.battery.percentage = 60
    coordinator.refresh()
    await integration.settle(coordinator)
    expectTrue(transport.enabled)
    expectEqual(coordinator.dischargeTarget, nil)
    coordinator.startCalibration()
    await integration.settle(coordinator)
    expectEqual(coordinator.calibration.phase, 1)
    transport.battery.percentage = 100
    coordinator.refresh()
    await integration.settle(coordinator)
    expectEqual(coordinator.calibration.phase, 2)
    expectTrue(transport.enabled)
    transport.battery.timestamp = transport.battery.timestamp.addingTimeInterval(1801)
    coordinator.refresh()
    await integration.settle(coordinator)
    expectEqual(coordinator.calibration.phase, 3)
    expectFalse(transport.enabled)
    transport.battery.percentage = 20
    coordinator.refresh()
    await integration.settle(coordinator)
    expectEqual(coordinator.calibration.phase, 4)
    expectTrue(transport.enabled)
    transport.battery.percentage = 100
    coordinator.refresh()
    await integration.settle(coordinator)
    expectEqual(coordinator.calibration.phase, 5)
    expectEqual(coordinator.mode, .holding)
    coordinator.startCalibration()
    await integration.settle(coordinator)
    coordinator.willSleep()
    try backend.perform(.charging(false))
    transport.failNext = true
    backend.prepareForSleep()
    expectEqual(coordinator.calibration.phase, 7)
    expectFalse(transport.enabled)
    coordinator.didWake()
    await integration.settle(coordinator)
    expectFalse(coordinator.capabilities.canControl)
    expectTrue(transport.enabled)
    await coordinator.shutdown()
  }
  func testRoutingRestoresControllers() async throws {
    let native = MockBackend()
    let helper = MockBackend()
    let router = PlatformHardwareClient(native: native, helper: helper)
    _ = try await router.status()
    try await router.perform(.limit(80))
    try await router.configureAdvanced(true)
    expectEqual(native.commands, [.limit(80), .reset])
    try await router.perform(.charging(false))
    expectEqual(native.commands.last, .limit(100))
    expectEqual(helper.commands.last, .charging(false))
    try await router.configureAdvanced(false)
    expectEqual(helper.commands.last, .reset)
    expectEqual(native.commands.last, .reset)
  }
  func testPinnedTrust() throws {
    let hash = String(repeating: "a", count: 40)
    let data = Data("{\"applicationHashes\":[\"\(hash)\"],\"helperHashes\":[\"\(hash)\"]}".utf8)
    let trust = try JSONDecoder().decode(LocalInstallationTrust.self, from: data)
    expectTrue(trust.valid)
    var requirement: SecRequirement?
    let text = LocalInstallationTrust.requirement(
      identifier: HelperIdentity.appIdentifier, hashes: [hash])
    expectEqual(SecRequirementCreateWithString(text as CFString, [], &requirement), errSecSuccess)
    let invalid = try JSONDecoder().decode(
      LocalInstallationTrust.self,
      from: Data("{\"applicationHashes\":[\"bad\"],\"helperHashes\":[]}".utf8))
    expectFalse(invalid.valid)
  }
  func testHistoryCSVAndCompatibility() throws {
    let history = HistoryStore(
      url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    var sample = BatterySnapshot(
      percentage: 70, pluggedIn: true, charging: false, temperature: 30, timestamp: date)
    sample.voltage = 12.5
    sample.current = -0.5
    sample.power = -6.25
    sample.maximumCapacity = 4710
    history.append(sample)
    history.append(sample)
    sample.timestamp = date.addingTimeInterval(300)
    history.append(sample)
    sample.timestamp = date.addingTimeInterval(-1)
    history.append(sample)
    expectEqual(history.samples.count, 2)
    let lines = history.exportCSV().split(separator: "\n")
    expectEqual(lines.count, 3)
    expectEqual(lines[1].split(separator: ",", omittingEmptySubsequences: false).count, 11)
    expectTrue(lines[1].contains("12.5,-0.5,-6.25,4710"))
    var json = try unwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as? [String: Any])
    json.removeValue(forKey: "advancedControl")
    json.removeValue(forKey: "setupComplete")
    let restored = try JSONDecoder().decode(
      AppSettings.self, from: JSONSerialization.data(withJSONObject: json))
    expectEqual(restored.advancedControl, nil)
  }
}
