import BattuneDomain
import CNativeCharge
import Foundation

public struct SMCProbe: Codable, Identifiable, Sendable {
  public let id: Int
  public let key: String
  public let ioResult: UInt32
  public let smcResult: UInt8
  public let size: UInt32
  public let type: UInt32
  public let bytes: [UInt8]
  public var readable: Bool { ioResult == 0 && smcResult == 0 && size > 0 && size <= 32 }
  public var result: String {
    String(format: "IO=0x%08X SMC=0x%02X size=%u", ioResult, smcResult, size)
  }
  public static func read(_ id: Int) -> SMCProbe {
    var value = bt_smc_probe(Int32(id))
    let bytes = withUnsafeBytes(of: &value.bytes) { Array($0.prefix(Int(min(32, value.size)))) }
    return SMCProbe(
      id: id, key: String(cString: bt_smc_key_name(Int32(id))),
      ioResult: value.io_result, smcResult: value.smc_result, size: value.size,
      type: value.type, bytes: bytes)
  }
  public static func all() -> [SMCProbe] { (0..<13).map(read) }
  public static var batteryTemperature: Double? {
    let value = read(10)
    guard value.readable, value.size == 4, value.type == 0x666c_7420 else { return nil }
    let bits = value.bytes.enumerated().reduce(UInt32(0)) {
      $0 | UInt32($1.element) << ($1.offset * 8)
    }
    let temperature = Double(Float(bitPattern: bits))
    return temperature.isFinite && (-20...100).contains(temperature) ? temperature : nil
  }
  public static var physicallyPluggedIn: Bool? {
    let value = read(9)
    guard value.readable, value.size == 1, let byte = value.bytes.first else { return nil }
    return Int8(bitPattern: byte) > 0
  }
}
