import Foundation
import BattuneDomain
import BattuneSystem
import BattuneHardware
final class MockBackend: BatteryHardwareBackend, HardwareClient, BatteryProviding {
    let name = "Test-only simulated hardware"
    var snapshot = BatterySnapshot(percentage: 50, pluggedIn: true, charging: true, temperature: 30)
    var supported = Capabilities(readBattery: true, readTemperature: true, setLimit: true, toggleCharging: true, forceDischarge: true, reset: true)
    var commands: [HardwareCommand] = []
    var failure: BattuneError?
    var disconnected = false
    func capabilities() -> Capabilities { supported }
    func readBatterySnapshot() -> BatterySnapshot { snapshot }
    func read() -> BatterySnapshot { snapshot }
    func perform(_ command: HardwareCommand) throws {
        if let failure { throw failure }
        commands.append(command)
    }
    func status() async throws -> HelperStatus {
        if disconnected { throw BattuneError.helperUnavailable }
        return HelperStatus(backend: name, capabilities: supported)
    }
    func perform(_ command: HardwareCommand) async throws {
        if disconnected { throw BattuneError.helperUnavailable }
        if let failure { throw failure }
        commands.append(command)
    }
}
