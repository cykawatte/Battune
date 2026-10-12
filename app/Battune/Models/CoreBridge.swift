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
    guard battune_abi_version() == 1 else { throw BattuneError.protocolMismatch }
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
