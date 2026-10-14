import CBattuneCore
import Foundation

public struct ControlState: Equatable, Sendable {
  public var holding = false
  public var thermalHold = false
  public init() {}
}
public enum ControlMode: Int32, Sendable {
  case system = 0
  case charging, holding, thermalHold, discharging, calibration, unavailable, nativeLimit
  public var localizationKey: String { "mode.\(rawValue)" }
}
public struct ControlPlan: Sendable {
  public let mode: ControlMode
  public let state: ControlState
  public let commands: [HardwareCommand]
  public let dischargeComplete: Bool
  public let sensorMissing: Bool
}
public enum CoreBridge {
  public static func evaluate(
    settings: ChargeSettings, enabled: Bool, target: Int?, snapshot: BatterySnapshot,
    state: ControlState, capabilities: Capabilities
  ) throws -> ControlPlan {
    try settings.validate()
    guard battune_abi_version() == 2 else { throw BattuneError.protocolMismatch }
    guard target.map({ (20...100).contains($0) }) ?? true,
      snapshot.percentage.map({ (0...100).contains($0) }) ?? true,
      snapshot.temperature.map({ $0.isFinite && (-20...100).contains($0) }) ?? true
    else { throw BattuneError.invalidSnapshot }
    let input = BattuneInput(
      enabled: enabled ? 1 : 0, limit: Int32(settings.limit),
      lower: settings.sailing ? Int32(settings.lower) : -1,
      thermal_enabled: settings.thermal ? 1 : 0, resume: Int32(settings.resumeTemperature * 1000),
      stop: Int32(settings.stopTemperature * 1000),
      target: target.map(Int32.init) ?? -1, soc: snapshot.percentage.map(Int32.init) ?? -1,
      plugged: snapshot.pluggedIn.map { $0 ? 1 : 0 } ?? -1,
      temperature: snapshot.temperature.map { Int32($0 * 1000) } ?? Int32.min,
      holding: state.holding ? 1 : 0, thermal_hold: state.thermalHold ? 1 : 0,
      capabilities: capabilities.mask)
    let output = battune_evaluate(input)
    guard output.error == 0 else {
      throw BattuneError(rawValue: Int(output.error)) ?? .protocolMismatch
    }
    var next = ControlState()
    next.holding = output.holding == 1
    next.thermalHold = output.thermal_hold == 1
    var commands: [HardwareCommand] = []
    // Stop forced discharge before changing charge controls. Enable it last.
    if output.reset == 1 {
      commands = [.reset]
    } else {
      if output.discharge == 0 { commands.append(.discharge(false)) }
      if output.limit >= 0 { commands.append(.limit(Int(output.limit))) }
      if output.charging >= 0 { commands.append(.charging(output.charging == 1)) }
      if output.discharge == 1 { commands.append(.discharge(true)) }
    }
    return ControlPlan(
      mode: ControlMode(rawValue: output.mode) ?? .unavailable, state: next, commands: commands,
      dischargeComplete: output.discharge_complete == 1, sensorMissing: output.sensor_missing == 1)
  }
}
extension CoreBridge {
  /// Effective limit for an override; `complete` means the override has ended.
  public static func resolve(
    configured: Int, override value: ChargeOverride?, plugged: Bool?
  ) throws -> (limit: Int, complete: Bool) {
    guard battune_abi_version() == 2 else { throw BattuneError.protocolMismatch }
    guard let value else { return (configured, false) }
    let output = battune_override(
      BattuneOverride(
        configured: Int32(clamping: configured), kind: value.kind.rawValue,
        paused_at: value.pausedAt.map { Int32(clamping: $0) } ?? -1,
        plugged: plugged.map { $0 ? 1 : 0 } ?? -1, limit: 0, complete: 0, error: 0))
    guard output.error == 0 else {
      throw BattuneError(rawValue: Int(output.error)) ?? .protocolMismatch
    }
    return (Int(output.limit), output.complete == 1)
  }
  /// Smallest supported native limit at or above the request.
  public static func nativeCeiling(_ requested: Int, supported: [Int]) -> Int? {
    guard (20...100).contains(requested), supported.count <= 32 else { return nil }
    let values = supported.map { Int32(clamping: $0) }
    let result = values.withUnsafeBufferPointer {
      battune_native_ceiling(Int32(requested), $0.baseAddress, UInt32($0.count))
    }
    return result >= 0 ? Int(result) : nil
  }
  /// Fills the time estimates macOS leaves unknown (65535) from capacity and current.
  public static func estimate(_ snapshot: BatterySnapshot, target: Int) -> (
    toTarget: Int?, toEmpty: Int?
  ) {
    let capacity = { (value: Int?) -> Int32 in
      value.flatMap { Int32(exactly: $0) } ?? -1
    }
    let current = snapshot.current.flatMap { Int32(exactly: ($0 * 1000).rounded()) } ?? Int32.min
    let output = battune_estimate(
      BattuneEstimate(
        remaining: capacity(snapshot.currentCapacity), full: capacity(snapshot.maximumCapacity),
        current: current, target: Int32(clamping: min(100, max(1, target))), to_target: -1,
        to_empty: -1, error: 0))
    guard output.error == 0 else { return (nil, nil) }
    return (
      output.to_target >= 0 ? Int(output.to_target) : nil,
      output.to_empty >= 0 ? Int(output.to_empty) : nil
    )
  }
  /// MagSafe indicator value for the current state; nil for invalid input.
  public static func indicator(
    style: IndicatorStyle, mode: ControlMode, plugged: Bool?, charging: Bool?
  ) -> Int? {
    let value = battune_indicator(
      Int32(style.rawValue), mode.rawValue, plugged.map { $0 ? 1 : 0 } ?? -1,
      charging.map { $0 ? 1 : 0 } ?? -1)
    return value >= 0 ? Int(value) : nil
  }
}
public struct CalibrationSession: Codable, Equatable, Sendable {
  public var phase: Int32 = 0
  public var started: Int64 = 0
  public var phaseStarted: Int64 = 0
  public var low = 20
  public var settle: Int64 = 1800
  public init() {}
  public var active: Bool { (1...4).contains(phase) }
  public mutating func update(
    snapshot: BatterySnapshot, blocked: Bool = false, command: Int32 = 0, supported: Bool = false
  ) throws {
    guard (0...7).contains(phase), (20...50).contains(low), (0...7200).contains(settle),
      snapshot.percentage.map({ (0...100).contains($0) }) ?? true
    else { throw BattuneError.invalidConfiguration }
    let input = BattuneCalibration(
      phase: phase, low: Int32(low), settle: settle, started: started, phase_started: phaseStarted,
      now: Int64(snapshot.timestamp.timeIntervalSince1970),
      soc: snapshot.percentage.map(Int32.init) ?? -1,
      plugged: snapshot.pluggedIn.map { $0 ? 1 : 0 } ?? -1, blocked: blocked ? 1 : 0,
      command: command, supported: supported ? 1 : 0, error: 0)
    let output = battune_calibration(input)
    guard output.error == 0 else {
      throw BattuneError(rawValue: Int(output.error)) ?? .protocolMismatch
    }
    phase = output.phase
    started = output.started
    phaseStarted = output.phase_started
  }
}
