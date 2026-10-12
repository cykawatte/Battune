import BattuneDomain
import BattuneHardware
import BattuneSystem
import Foundation

final class MockBackend: BatteryHardwareBackend, HardwareClient, BatteryProviding {
  let name = "Test-only simulated hardware"
  var snapshot = BatterySnapshot(percentage: 50, pluggedIn: true, charging: true, temperature: 30)
  var supported = Capabilities(
    readBattery: true, readTemperature: true, setLimit: true, toggleCharging: true,
    forceDischarge: true, reset: true)
  private let commandLock = NSLock()
  private var recordedCommands: [HardwareCommand] = []
  var commands: [HardwareCommand] { commandLock.withLock { recordedCommands } }
  var failure: BattuneError?
  var disconnected = false
  var writeDelayNanoseconds: UInt64 = 0
  func capabilities() -> Capabilities { supported }
  func readBatterySnapshot() -> BatterySnapshot { snapshot }
  func read() -> BatterySnapshot { snapshot }
  func perform(_ command: HardwareCommand) throws {
    if let failure { throw failure }
    commandLock.withLock { recordedCommands.append(command) }
  }
  func renewLease() async throws { if disconnected { throw BattuneError.helperUnavailable } }
  func status() async throws -> HelperStatus {
    if disconnected { throw BattuneError.helperUnavailable }
    return HelperStatus(backend: name, capabilities: supported)
  }
  func perform(_ command: HardwareCommand) async throws {
    if writeDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: writeDelayNanoseconds) }
    if disconnected { throw BattuneError.helperUnavailable }
    if let failure { throw failure }
    commandLock.withLock { recordedCommands.append(command) }
  }
}
