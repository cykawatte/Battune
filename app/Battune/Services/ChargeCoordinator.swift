import BattuneDomain
import Combine
import Foundation
import OSLog

@MainActor public final class ChargeCoordinator: ObservableObject {
  @Published public private(set) var snapshot = BatterySnapshot()
  @Published public private(set) var capabilities = Capabilities()
  @Published public private(set) var helper: HelperStatus?
  @Published public private(set) var helperError: BattuneError?
  @Published public private(set) var mode = ControlMode.system
  @Published public private(set) var lastError: BattuneError?
  @Published public private(set) var calibration = CalibrationSession()
  @Published public private(set) var dischargeTarget: Int?
  @Published public private(set) var historyError = false
  @Published public private(set) var sensorMissing = false
  @Published public private(set) var busy = false
  public let executor: CommandExecutor
  private let provider: BatteryProviding
  private let client: HardwareClient
  private let store: SettingsStore
  private let history: HistoryStore
  private var settings: AppSettings
  private var state = ControlState()
  private var pending = false
  private var suspended = false
  private var sleeping = false
  private var needsReset = false
  private var revision = 0
  private let logger = Logger(subsystem: "org.battune.app", category: "Control")
  public init(
    settings: AppSettings, store: SettingsStore, history: HistoryStore,
    provider: BatteryProviding = SystemBatteryProvider(), client: HardwareClient = HelperClient()
  ) {
    self.settings = settings
    self.store = store
    self.history = history
    self.provider = provider
    self.client = client
    executor = CommandExecutor(client: client)
    do {
      calibration = try store.loadCalibration()
      needsReset = calibration.phase == 7
    } catch {
      lastError = .corruptPersistence
      suspended = true
    }
  }
  public func updateSettings(_ value: AppSettings) {
    do {
      try value.validate()
      settings = value
      revision += 1
      executor.invalidate()
      if !settings.controlEnabled {
        dischargeTarget = nil
        cancelCalibrationState()
        needsReset = true
      }
      refresh()
    } catch { lastError = .invalidConfiguration }
  }
  public func refresh() {
    guard !sleeping else { return }
    pending = true
    guard !busy else { return }
    busy = true
    Task { [weak self] in
      guard let self else { return }
      while self.pending && !self.sleeping {
        self.pending = false
        await self.evaluate()
      }
      self.busy = false
    }
  }
  private func evaluate() async {
    snapshot = provider.read()
    if settings.statisticsEnabled {
      history.append(snapshot)
      do {
        try history.flush()
        historyError = false
      } catch { historyError = true }
    }
    let currentRevision = revision
    do {
      let status = try await client.status()
      guard status.version == "0.1.0-dev" else { throw BattuneError.protocolMismatch }
      helper = status
      capabilities = status.capabilities
      helperError = nil
    } catch {
      helper = nil
      helperError = error as? BattuneError ?? .helperUnavailable
      capabilities = Capabilities(
        readBattery: snapshot.percentage != nil, readTemperature: snapshot.temperature != nil)
      executor.invalidate()
      if calibration.active || dischargeTarget != nil {
        cancelCalibrationState(interrupted: true)
        dischargeTarget = nil
        suspended = true
      }
    }
    guard currentRevision == revision, !sleeping else {
      pending = !sleeping
      return
    }
    guard settings.onboardingComplete else {
      mode = .system
      return
    }
    guard capabilities.canControl else {
      mode = settings.controlEnabled ? .unavailable : .system
      return
    }
    do {
      if needsReset {
        try await executor.apply([.reset])
        needsReset = false
      }
      guard !suspended else {
        mode = .unavailable
        return
      }
      var charge = settings.charge
      if let schedule = try ScheduleResolver.active(settings.schedules, at: snapshot.timestamp),
        !calibration.active
      {
        charge.limit = schedule.settings.limit
        charge.sailing = schedule.settings.sailing
        charge.lower = schedule.settings.lower
        let token = ScheduleResolver.activationToken(schedule, at: snapshot.timestamp)
        if token != store.scheduleToken {
          // Consume before issuing hardware commands, preventing replay after a crash.
          store.scheduleToken = token
          if settings.controlEnabled && capabilities.forceDischarge {
            dischargeTarget = schedule.dischargeTarget
          }
        }
      }
      if calibration.active {
        let safety = try CoreBridge.evaluate(
          settings: charge, enabled: true, target: nil, snapshot: snapshot, state: state,
          capabilities: capabilities)
        let old = calibration
        try calibration.update(
          snapshot: snapshot, blocked: safety.state.thermalHold || safety.sensorMissing)
        if old != calibration { try store.saveCalibration(calibration) }
        if !calibration.active {
          try await executor.apply([.reset])
          dischargeTarget = nil
          state = ControlState()
          pending = true
          return
        }
        charge.limit = 100
        charge.sailing = false
        dischargeTarget = calibration.phase == 3 ? calibration.low : nil
      }
      let plan = try CoreBridge.evaluate(
        settings: charge, enabled: settings.controlEnabled, target: dischargeTarget,
        snapshot: snapshot, state: state, capabilities: capabilities)
      try await executor.apply(plan.commands)
      if settings.controlEnabled && !plan.commands.contains(.reset) {
        try await client.renewLease()
      }
      state = plan.state
      sensorMissing = plan.sensorMissing
      mode = calibration.active && plan.mode != .thermalHold ? .calibration : plan.mode
      if plan.dischargeComplete { dischargeTarget = nil }
      lastError = nil
    } catch {
      if sleeping { return }
      if error is CancellationError {
        pending = true
        return
      }
      lastError = error as? BattuneError ?? .hardwareError
      suspended = true
      mode = .unavailable
      cancelCalibrationState(interrupted: true)
      dischargeTarget = nil
      // One bounded recovery attempt, no aggressive retries. A new user action is required.
      do { try await executor.apply([.reset]) } catch { logger.error("Hardware recovery failed") }
      logger.error("Control suspended after error")
    }
  }
  public func startDischarge(target: Int) {
    guard settings.controlEnabled, capabilities.forceDischarge, capabilities.reset,
      !calibration.active, !busy,
      (20...100).contains(target)
    else {
      lastError = .unsupported
      return
    }
    dischargeTarget = target
    suspended = false
    refresh()
  }
  public func startCalibration() {
    guard settings.controlEnabled, capabilities.canCalibrate, snapshot.pluggedIn == true, !busy
    else {
      lastError = .unsupported
      return
    }
    do {
      calibration = CalibrationSession()
      try calibration.update(snapshot: snapshot, command: 1, supported: true)
      try store.saveCalibration(calibration)
      suspended = false
      refresh()
    } catch { lastError = error as? BattuneError ?? .hardwareError }
  }
  private func cancelCalibrationState(interrupted: Bool = false) {
    guard calibration.active else { return }
    calibration.phase = interrupted ? 7 : 6
    do { try store.saveCalibration(calibration) } catch { lastError = .corruptPersistence }
  }
  public func cancelWorkflow() {
    cancelCalibrationState()
    dischargeTarget = nil
    needsReset = true
    revision += 1
    executor.invalidate()
    refresh()
  }
  public func reset() {
    guard capabilities.reset else {
      lastError = .unsupported
      return
    }
    cancelWorkflow()
    suspended = true
  }
  public func retry() {
    suspended = false
    lastError = nil
    executor.invalidate()
    refresh()
  }
  public func willSleep() {
    sleeping = true
    revision += 1
    executor.invalidate()
    do {
      try history.flush(force: true)
      try store.saveCalibration(calibration)
    } catch { lastError = .corruptPersistence }
  }
  public func didWake() {
    sleeping = false
    state = ControlState()
    executor.invalidate()
    refresh()
  }
  public func shutdown() async {
    sleeping = true
    revision += 1
    executor.invalidate()
    cancelCalibrationState(interrupted: true)
    // A pending XPC request has a five-second deadline; stop its remaining transaction.
    for _ in 0..<60 {
      if !busy { break }
      try? await Task.sleep(nanoseconds: 100_000_000)
    }
    if capabilities.reset {
      do { try await client.perform(.reset) } catch { logger.error("Reset on exit failed") }
    }
    do { try history.flush(force: true) } catch { logger.error("History flush failed") }
  }
}
