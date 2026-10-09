import Foundation
import CBattuneCore
import BattuneDomain
import BattuneSystem
import BattuneShared
import BattuneHardware
@MainActor final class DomainTests {
    func testABIAndChargeBoundaries() throws {
        expectEqual(battune_abi_version(), 1)
        expectEqual(MemoryLayout<BattuneInput>.size, 52)
        expectEqual(MemoryLayout<BattuneOutput>.size, 40)
        expectEqual(MemoryLayout<BattuneCalibration>.size, 64)
        var settings = ChargeSettings(); settings.thermal = false
        let caps = Capabilities(setLimit: true, toggleCharging: true, forceDischarge: true, reset: true)
        let result = try CoreBridge.evaluate(settings: settings, enabled: true, target: nil, snapshot: BatterySnapshot(percentage: 80, pluggedIn: true), state: ControlState(), capabilities: caps)
        expectEqual(result.mode, .holding)
        expectTrue(result.commands.contains(.charging(false)))
    }
    func testPersistenceAndValidation() throws {
        let name = "BattuneTests.\(UUID().uuidString)"
        let defaults = try unwrap(UserDefaults(suiteName: name)); defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        var settings = AppSettings(); settings.charge.limit = 85
        try store.save(settings); expectEqual(try store.load(), settings)
        settings.charge.limit = 19; expectThrows(try store.save(settings))
        defaults.set(Data("broken".utf8), forKey: "settings.v1")
        expectThrows(try { _ = try store.load() }())
    }
    func testScheduleBridge() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = try unwrap(TimeZone(identifier: "Europe/Berlin"))
        let date = try unwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 8)))
        var a = ChargeSchedule(id: 1); a.days = 1; a.minute = 480
        var b = a; b.id = 2; b.priority = 1
        expectEqual(try ScheduleResolver.active([a,b], at: date, calendar: calendar)?.id, 2)
    }
    func testUnsupportedBackendAndReplyMapping() throws {
        let backend = AppleSiliconBackend(provider: TestProvider())
        expectTrue(backend.capabilities().readBattery)
        expectFalse(backend.capabilities().setLimit)
        expectThrows(try backend.perform(.limit(80))) { expectEqual($0 as? BattuneError, .unsupported) }
        expectThrows(try { _ = try HelperReply.decode(HelperStatus.self, data: nil, code: 6) }()) { expectEqual($0 as? BattuneError, .helperUnavailable) }
    }
    func testCalibrationRestartInterrupted() throws {
        let name = "BattuneTests.\(UUID().uuidString)"
        let defaults = try unwrap(UserDefaults(suiteName: name)); defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        var c = CalibrationSession(); try c.update(snapshot: BatterySnapshot(percentage: 80, pluggedIn: true), command: 1, supported: true)
        try store.saveCalibration(c); expectEqual(try store.loadCalibration().phase, 7)
    }
}
struct TestProvider: BatteryProviding { func read() -> BatterySnapshot { BatterySnapshot(percentage: 80, pluggedIn: true) } }
