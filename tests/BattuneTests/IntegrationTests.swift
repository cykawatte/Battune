import Foundation
import BattuneDomain
import BattuneSystem
import BattuneShared
import BattuneHardware
@MainActor final class IntegrationTests {
    func testExecutorAcknowledgement() async throws {
        let mock = MockBackend(); let executor = CommandExecutor(client: mock)
        try await executor.apply([.limit(80), .charging(false)])
        try await executor.apply([.limit(80), .charging(false)])
        expectEqual(mock.commands.count, 2)
        mock.failure = .hardwareError
        do { try await executor.apply([.limit(90)]); expectTrue(false) } catch { expectEqual(error as? BattuneError, .hardwareError) }
        mock.failure = nil
        try await executor.apply([.limit(90)])
        expectEqual(mock.commands.last, .limit(90))
    }
    func testHardwareGateAndInputValidation() throws {
        let mock = MockBackend(); let gate = HardwareGate(backend: mock)
        expectThrows(try gate.perform(.limit(19), now: 100)) { expectEqual($0 as? BattuneError, .invalidConfiguration) }
        try gate.perform(.limit(80), now: 100); try gate.perform(.limit(80), now: 100)
        expectEqual(mock.commands.count, 1)
        for index in 0..<11 { try gate.perform(.limit(81 + index), now: 100) }
        expectThrows(try gate.perform(.limit(95), now: 100)) { expectEqual($0 as? BattuneError, .rateLimited) }
        try gate.perform(.reset, now: 100)
        expectEqual(mock.commands.last, .reset)
        mock.supported.forceDischarge = false
        expectThrows(try gate.perform(.discharge(true), now: 200)) { expectEqual($0 as? BattuneError, .unsupported) }
    }
    func testMalformedReplies() throws {
        for data in [Data("{}".utf8), Data(repeating: 0, count: 65_537)] {
            expectThrows(try { _ = try HelperReply.decode(HelperStatus.self, data: data, code: 0) }()) { expectEqual($0 as? BattuneError, .protocolMismatch) }
        }
    }
    func testHistoryBoundedAndPrivate() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HistoryStore(url: folder.appendingPathComponent("history.json"))
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for n in 0..<9000 { store.append(BatterySnapshot(percentage: n % 100, pluggedIn: true, timestamp: start.addingTimeInterval(Double(n * 301)))) }
        expectTrue(store.samples.count <= 8640)
        try store.flush(force: true)
        let reload = HistoryStore(url: folder.appendingPathComponent("history.json")); try reload.load(now: start.addingTimeInterval(8999 * 301))
        expectEqual(reload.samples, store.samples)
        try reload.clear(); expectTrue(reload.samples.isEmpty)
    }
    func testHistoryDeduplication() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = HistoryStore(url: url)
        let date = Date()
        store.append(BatterySnapshot(percentage: 80, pluggedIn: true, timestamp: date))
        store.append(BatterySnapshot(percentage: 80, pluggedIn: true, timestamp: date.addingTimeInterval(600)))
        expectEqual(store.samples.count, 1)
        expectFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testDSTAndTimezone() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = try unwrap(TimeZone(identifier: "Europe/Berlin"))
        let iso = ISO8601DateFormatter()
        var schedule = ChargeSchedule(id: 1); schedule.days = 64; schedule.minute = 150
        let before = try unwrap(iso.date(from: "2026-10-25T00:45:00Z"))
        let after = try unwrap(iso.date(from: "2026-10-25T01:45:00Z"))
        expectEqual(ScheduleResolver.activationToken(schedule, at: before, calendar: calendar), ScheduleResolver.activationToken(schedule, at: after, calendar: calendar))
        let spring = try unwrap(iso.date(from: "2026-03-29T01:10:00Z"))
        expectEqual(try ScheduleResolver.active([schedule], at: spring, calendar: calendar)?.id, 1)
        var utc = calendar; utc.timeZone = try unwrap(TimeZone(secondsFromGMT: 0))
        var second = ChargeSchedule(id: 2); second.days = 64; second.minute = 60
        expectEqual(try ScheduleResolver.active([schedule, second], at: spring, calendar: utc)?.id, 2)
    }
    func testCoordinatorTransitions() async throws {
        try await withCoordinator { coordinator, mock in
            coordinator.refresh(); await self.settle(coordinator)
            expectEqual(coordinator.mode, .charging)
            mock.snapshot.percentage = 80; coordinator.refresh(); await self.settle(coordinator)
            expectEqual(coordinator.mode, .holding)
            let count = mock.commands.count; coordinator.refresh(); await self.settle(coordinator)
            expectEqual(mock.commands.count, count)
            mock.snapshot.temperature = 41; coordinator.refresh(); await self.settle(coordinator)
            expectEqual(coordinator.mode, .thermalHold)
            mock.snapshot.temperature = nil; coordinator.refresh(); await self.settle(coordinator)
            expectTrue(coordinator.sensorMissing)
            mock.snapshot.pluggedIn = false; coordinator.refresh(); await self.settle(coordinator)
            expectEqual(mock.commands.last, .reset)
        }
    }
    func testCoordinatorFailureAndRecovery() async throws {
        try await withCoordinator { coordinator, mock in
            coordinator.refresh(); await self.settle(coordinator)
            mock.failure = .hardwareError; mock.snapshot.percentage = 90
            coordinator.refresh(); await self.settle(coordinator)
            expectEqual(coordinator.mode, .unavailable)
            let count = mock.commands.count
            coordinator.refresh(); await self.settle(coordinator); expectEqual(mock.commands.count, count)
            mock.failure = nil; coordinator.retry(); await self.settle(coordinator)
            expectEqual(coordinator.mode, .holding)
            mock.disconnected = true; coordinator.refresh(); await self.settle(coordinator)
            expectEqual(coordinator.helperError, .helperUnavailable)
            expectFalse(coordinator.capabilities.canControl)
        }
    }
    func testDischargeAndCancel() async throws {
        try await withCoordinator { coordinator, mock in
            coordinator.refresh(); await self.settle(coordinator)
            mock.snapshot.percentage = 96
            coordinator.startDischarge(target: 75); await self.settle(coordinator)
            expectEqual(coordinator.mode, .discharging)
            mock.snapshot.percentage = 75; coordinator.refresh(); await self.settle(coordinator)
            expectEqual(coordinator.dischargeTarget, nil)
            expectTrue(mock.commands.contains(.discharge(false)))
            coordinator.startCalibration(); await self.settle(coordinator)
            expectTrue(coordinator.calibration.active)
            coordinator.cancelWorkflow(); await self.settle(coordinator)
            expectEqual(coordinator.calibration.phase, 6)
            expectTrue(mock.commands.contains(.reset))
        }
    }
    func testWakeRefreshesWithoutReplay() async throws {
        try await withCoordinator { coordinator, mock in
            coordinator.refresh(); await self.settle(coordinator)
            coordinator.willSleep(); let count = mock.commands.count
            mock.snapshot.percentage = 100; coordinator.refresh(); await self.settle(coordinator)
            expectEqual(mock.commands.count, count)
            coordinator.didWake(); await self.settle(coordinator)
            expectEqual(coordinator.mode, .holding)
        }
    }
    func testConfigurationAndViewModelFailures() throws {
        let name = "BattuneTests.\(UUID().uuidString)"; let defaults = try unwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("corrupt".utf8), forKey: "settings.v1")
        let model = SettingsModel(store: SettingsStore(defaults: defaults))
        expectEqual(model.error, .corruptPersistence); expectFalse(model.value.controlEnabled)
        model.value.charge.sailing = true; model.value.charge.lower = 90
        expectFalse(model.save()); expectEqual(model.error, .invalidConfiguration)
        model.value.charge.lower = 75; expectTrue(model.save())
    }
    func testLiveReadOnlySnapshot() throws {
        let snapshot = SystemBatteryProvider().read()
        expectTrue(snapshot.percentage.map { (0...100).contains($0) } ?? true)
        expectTrue(snapshot.temperature.map { (-20...100).contains($0) } ?? true)
    }
    func settle(_ coordinator: ChargeCoordinator) async {
        for _ in 0..<200 {
            if !coordinator.busy { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        expectFalse(coordinator.busy)
    }
    private func withCoordinator(_ body: (ChargeCoordinator, MockBackend) async throws -> Void) async throws {
        let name = "BattuneTests.\(UUID().uuidString)"; let defaults = try unwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        var settings = AppSettings(); settings.onboardingComplete = true; settings.controlEnabled = true; settings.statisticsEnabled = false
        let mock = MockBackend(); let history = HistoryStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let coordinator = ChargeCoordinator(settings: settings, store: store, history: history, provider: mock, client: mock)
        try await body(coordinator, mock)
    }
}
