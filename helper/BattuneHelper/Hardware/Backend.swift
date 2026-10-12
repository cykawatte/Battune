import BattuneDomain
import BattuneSystem
import Foundation
import IOKit

public protocol BatteryHardwareBackend: AnyObject {
  var name: String { get }
  var generation: UInt64 { get }
  func capabilities() -> Capabilities
  func readBatterySnapshot() -> BatterySnapshot
  func perform(_ command: HardwareCommand) throws
}
extension BatteryHardwareBackend { public var generation: UInt64 { 0 } }
/// No unvalidated SMC keys are read or written. Service presence does not establish write support.
public class ReadOnlyBackend: BatteryHardwareBackend {
  public let name: String
  private let provider: BatteryProviding
  public init(name: String, provider: BatteryProviding = SystemBatteryProvider()) {
    self.name = name
    self.provider = provider
  }
  public func readBatterySnapshot() -> BatterySnapshot { provider.read() }
  public func capabilities() -> Capabilities {
    let snapshot = provider.read()
    return Capabilities(
      readBattery: snapshot.percentage != nil, readTemperature: snapshot.temperature != nil)
  }
  public func perform(_ command: HardwareCommand) throws {
    if case .limit(let limit) = command, !(20...100).contains(limit) {
      throw BattuneError.invalidConfiguration
    }
    throw BattuneError.unsupported
  }
}
public final class AppleSiliconBackend: ReadOnlyBackend {
  public init(provider: BatteryProviding = SystemBatteryProvider()) {
    super.init(name: "Apple Silicon / read-only / SMC unvalidated", provider: provider)
  }
}
public final class IntelBackend: ReadOnlyBackend {
  public init(provider: BatteryProviding = SystemBatteryProvider()) {
    super.init(name: "Intel / read-only / SMC unvalidated", provider: provider)
  }
}
public enum BackendFactory {
  public static func make() -> BatteryHardwareBackend {
    #if arch(arm64)
      return AdapterBackend()
    #else
      return IntelBackend()
    #endif
  }
}
