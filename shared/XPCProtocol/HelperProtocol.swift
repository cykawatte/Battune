import BattuneDomain
import Foundation

@objc public protocol BattuneHelperProtocol {
  func validateAdapterControl(reply: @escaping (Int) -> Void)
  func renewControlLease(reply: @escaping (Int) -> Void)
  func getStatus(reply: @escaping (Data?, Int) -> Void)
  func getBatterySnapshot(reply: @escaping (Data?, Int) -> Void)
  func setChargeLimit(_ percent: Int, reply: @escaping (Int) -> Void)
  func setChargingEnabled(_ enabled: Bool, reply: @escaping (Int) -> Void)
  func setDischargeEnabled(_ enabled: Bool, reply: @escaping (Int) -> Void)
  func resetChargingState(reply: @escaping (Int) -> Void)
}
public enum HelperIdentity {
  public static let machService = "org.battune.helper"
  public static let appIdentifier = "org.battune.app"
  public static let daemonPlist = "org.battune.helper.plist"
}
public enum HelperReply {
  public static func decode<T: Decodable>(_ type: T.Type, data: Data?, code: Int) throws -> T {
    guard code == 0 else { throw BattuneError(rawValue: code) ?? .hardwareError }
    guard let data, data.count <= 65_536 else { throw BattuneError.protocolMismatch }
    do { return try JSONDecoder().decode(type, from: data) } catch {
      throw BattuneError.protocolMismatch
    }
  }
}
