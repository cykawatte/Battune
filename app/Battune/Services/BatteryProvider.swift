import Foundation
import IOKit
import IOKit.ps
import BattuneDomain
public protocol BatteryProviding { func read() -> BatterySnapshot }
public struct SystemBatteryProvider: BatteryProviding {
    public init() {}
    public func read() -> BatterySnapshot {
        var result = BatterySnapshot()
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                      d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
                if let current = d[kIOPSCurrentCapacityKey] as? Int, let maximum = d[kIOPSMaxCapacityKey] as? Int, maximum > 0 {
                    result.percentage = min(100, max(0, Int((Double(current) / Double(maximum) * 100).rounded())))
                }
                result.powerSource = d[kIOPSPowerSourceStateKey] as? String
                result.pluggedIn = result.powerSource.map { $0 == kIOPSACPowerValue }
                result.charging = d[kIOPSIsChargingKey] as? Bool
                result.fullyCharged = d[kIOPSIsChargedKey] as? Bool
                break
            }
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return result }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = properties?.takeRetainedValue() as? [String: Any] else { return result }
        result.cycleCount = nonnegative(d["CycleCount"])
        // Raw capacities are mAh. Do not confuse percentage-valued MaxCapacity on Apple Silicon with mAh.
        result.currentCapacity = nonnegative(d["AppleRawCurrentCapacity"])
        result.maximumCapacity = nonnegative(d["AppleRawMaxCapacity"])
        result.designCapacity = nonnegative(d["DesignCapacity"])
        if let max = result.maximumCapacity, let design = result.designCapacity, design > 0 {
            result.health = Double(max) / Double(design) * 100
        }
        // AppleSmartBattery Temperature uses centi-Celsius; reject missing or implausible sensor data.
        if let raw = d["Temperature"] as? Double, raw > 0, raw <= 10_000 { result.temperature = raw / 100 }
        if let adapter = d["AdapterDetails"] as? [String: Any] { result.adapterWatts = nonnegative(adapter["Watts"]) }
        return result
    }
    private func nonnegative(_ value: Any?) -> Int? { guard let v = value as? Int, v >= 0 else { return nil }; return v }
}
