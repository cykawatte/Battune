import BattuneDomain
import Foundation
import IOKit
import IOKit.ps

public protocol BatteryProviding { func read() -> BatterySnapshot }
public struct SystemBatteryProvider: BatteryProviding {
  public init() {}
  public func read() -> BatterySnapshot {
    var result = BatterySnapshot()
    if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    {
      for source in sources {
        guard
          let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
            as? [String: Any],
          d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        else { continue }
        if let current = d[kIOPSCurrentCapacityKey] as? Int,
          let maximum = d[kIOPSMaxCapacityKey] as? Int, maximum > 0
        {
          result.percentage = min(
            100, max(0, Int((Double(current) / Double(maximum) * 100).rounded())))
        }
        result.powerSource = d[kIOPSPowerSourceStateKey] as? String
        result.pluggedIn = result.powerSource.map { $0 == kIOPSACPowerValue }
        result.charging = d[kIOPSIsChargingKey] as? Bool
        result.fullyCharged = d[kIOPSIsChargedKey] as? Bool
        // -1 means "still calculating"; macOS omits the key when not applicable.
        result.minutesToFull = (d[kIOPSTimeToFullChargeKey] as? Int).flatMap(Self.minutes)
        result.minutesToEmpty = (d[kIOPSTimeToEmptyKey] as? Int).flatMap(Self.minutes)
        break
      }
    }
    let service = IOServiceGetMatchingService(
      kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard service != IO_OBJECT_NULL else { return result }
    defer { IOObjectRelease(service) }
    var properties: Unmanaged<CFMutableDictionary>?
    guard
      IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
        == KERN_SUCCESS,
      let d = properties?.takeRetainedValue() as? [String: Any]
    else { return result }
    let battery = d["BatteryData"] as? [String: Any] ?? [:]
    result.cycleCount = nonnegative(d["CycleCount"])
    // Raw capacities are mAh. Do not confuse percentage-valued MaxCapacity on Apple Silicon with mAh.
    result.currentCapacity =
      nonnegative(d["AppleRawCurrentCapacity"]) ?? nonnegative(battery["RemainingCapacity"])
    result.maximumCapacity =
      nonnegative(d["AppleRawMaxCapacity"]) ?? nonnegative(battery["FullChargeCapacity"])
    result.designCapacity =
      nonnegative(d["DesignCapacity"]) ?? nonnegative(battery["DesignCapacity"])
    if let max = result.maximumCapacity, let design = result.designCapacity, design > 0 {
      result.health = Double(max) / Double(design) * 100
    }
    // AppleSmartBattery Temperature uses centi-Celsius; reject missing or implausible sensor data.
    if let raw = d["Temperature"] as? Double, raw > 0, raw <= 10_000 {
      result.temperature = raw / 100
    }
    #if arch(arm64)
      result.temperature = result.temperature ?? SMCProbe.batteryTemperature
    #endif
    result.voltage = (d["Voltage"] as? Double).map { $0 / 1000 }
    result.current = (d["InstantAmperage"] as? Double ?? d["Amperage"] as? Double).map { $0 / 1000 }
    if let voltage = result.voltage, let current = result.current {
      result.power = voltage * current
    }
    if let adapter = d["AdapterDetails"] as? [String: Any] {
      result.adapterWatts = nonnegative(adapter["Watts"])
    }
    // Power telemetry is reported in mW on Apple Silicon. Values are absent on
    // Intel and while the gauge restarts; never substitute an estimate for them.
    if let telemetry = d["PowerTelemetryData"] as? [String: Any] {
      result.systemLoad = nonnegative(telemetry["SystemLoad"]).map { Double($0) / 1000 }
      if result.pluggedIn == true {
        result.adapterInput = nonnegative(telemetry["SystemPowerIn"]).map { Double($0) / 1000 }
      }
    }
    return result
  }
  static func minutes(_ value: Int) -> Int? { (0..<6000).contains(value) ? value : nil }
  private func nonnegative(_ value: Any?) -> Int? {
    guard let v = value as? Int, v >= 0 else { return nil }
    return v
  }
}
