import BattuneDomain
import BattuneSystem
import CNativeCharge
import Darwin
import Foundation

/// Fixed accessory operations that never influence charging: the MagSafe
/// indicator and macOS Low Power Mode profiles. No arbitrary keys or arguments.
public protocol AccessoryTransport: AnyObject {
  var privileged: Bool { get }
  var indicatorAvailable: Bool { get }
  func setIndicator(_ value: Int) throws
  func setLowPowerMode(battery: Bool, charger: Bool) throws
}

public final class SystemAccessoryTransport: AccessoryTransport {
  public init() {}
  public var privileged: Bool { geteuid() == 0 }
  public var indicatorAvailable: Bool { SMCProbe.indicatorAvailable }
  public func setIndicator(_ value: Int) throws {
    guard privileged else { throw BattuneError.unauthorized }
    let result = bt_smc_indicator(Int32(value))
    guard result == 0 else {
      throw result == 0xe000_02c7 ? BattuneError.unsupported : BattuneError.hardwareError
    }
  }
  public func setLowPowerMode(battery: Bool, charger: Bool) throws {
    guard privileged else { throw BattuneError.unauthorized }
    try pmset(["-b", "lowpowermode", battery ? "1" : "0"])
    try pmset(["-c", "lowpowermode", charger ? "1" : "0"])
  }
  /// Absolute path, fixed arguments, empty environment and a five-second deadline.
  private func pmset(_ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = arguments
    process.environment = [:]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    do { try process.run() } catch { throw BattuneError.hardwareError }
    if finished.wait(timeout: .now() + 5) == .timedOut {
      process.terminate()
      throw BattuneError.hardwareError
    }
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
      throw BattuneError.hardwareError
    }
  }
}
