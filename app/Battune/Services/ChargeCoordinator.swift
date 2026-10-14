import BattuneDomain
import Combine
import Foundation
import OSLog

@MainActor public final class ChargeCoordinator: ObservableObject {
  @Published public private(set) var snapshot = BatterySnapshot()
  @Published public private(set) var capabilities = Capabilities()
  @Published public private(set) var helper: HelperStatus?
  @Published public private(set) var helperError: BattuneError?
  @Published public private(set) var fallbackNativeLimit: Int?
  @Published public private(set) var mode = ControlMode.system
  @Published public private(set) var lastError: BattuneError?
  @Published public private(set) var calibration = CalibrationSession()
  @Published public private(set) var dischargeTarget: Int?
  @Published public private(set) var historyError = false
  @Published public private(set) var sensorMissing = false
  @Published public private(set) var busy = false
  /// Active top-up or pause; resolved against the configured limit by the core.
  @Published public private(set) var chargeOverride: ChargeOverride?
  /// The limit currently being enforced, including schedules and overrides.
  @Published public private(set) var effectiveLimit: Int?
  @Published public private(set) var accessoryError: BattuneError?
  /// Fallback polling interval and next exact wakeup for the power monitor.
  public var timing: ((TimeInterval, Date?) -> Void)?
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
  private var appliedIndicator: Int?
  private var appliedPowerMode: PowerModePolicy?
  private let logger = Logger(subsystem: "org.battune.app", category: "Control")
  public init(
    settings: AppSettings, store: SettingsStore, history: HistoryStore,
    provider: BatteryProviding = SystemBatteryProvider(),
    client: HardwareClient = PlatformHardwareClient()
  ) {
    self.settings = settings
    self.store = store
    self.history = history
    self.provider = provider
    self.client = client
    executor = CommandExecutor(client: client)
    chargeOverride = store.loadOverride()
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
      suspended = false
      revision += 1
      executor.invalidate()
      if !settings.controlEnabled {
        dischargeTarget = nil
        cancelCalibrationState()
        setOverride(nil)
        needsReset = true
      }
      if settings.powerMode != appliedPowerMode { appliedPowerMode = nil }
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
      if !self.sleeping { await self.applyAccessories() }
      self.reportTiming()
      self.busy = false
    }
  }
  private func evaluate() async {
    snapshot = provider.read()
    let currentRevision = revision
    let schedule = try? ScheduleResolver.active(settings.schedules, at: snapshot.timestamp)
    let baseLimit =
      calibration.active
      ? settings.charge.limit : (schedule?.settings.limit ?? settings.charge.limit)
    var requestedLimit = baseLimit
    var overrideLimit: Int?
    if let active = chargeOverride {
      if calibration.active || dischargeTarget != nil || !settings.controlEnabled {
        setOverride(nil)
      } else if let resolved = try? CoreBridge.resolve(
        configured: baseLimit, override: active, plugged: snapshot.pluggedIn), !resolved.complete
      {
        overrideLimit = resolved.limit
        requestedLimit = resolved.limit
      } else {
        // Top-up ends on unplug; a pause ends with the session. Return to the plan.
        setOverride(nil)
      }
    }
    fillEstimates(target: requestedLimit)
    do {
      try await client.configureControl(
        advanced: settings.controlEnabled && settings.advancedControl == true,
        limit: requestedLimit,
        workflow: calibration.active || dischargeTarget != nil)
      let status = try await client.status()
      guard status.version == BattuneVersion.current else { throw BattuneError.protocolMismatch }
      if status.controlGeneration != helper?.controlGeneration || status.backend != helper?.backend
      {
        executor.invalidate()
      }
      helper = status
      fallbackNativeLimit = nil
      capabilities = status.capabilities
      helperError = nil
      if let hardware = try await client.hardwareSnapshot() {
        snapshot = hardware
        fillEstimates(target: requestedLimit)
      }
    } catch {
      helper = nil
      helperError = error as? BattuneError ?? .helperUnavailable
      capabilities = Capabilities(
        readBattery: snapshot.percentage != nil, readTemperature: snapshot.temperature != nil)
      // Read back the controller that remains selected after a rejected switch.
      // This is an actual confirmed ceiling, not the requested slider value.
      fallbackNativeLimit = nil
      if let retained = try? await client.status(), retained.capabilities.nativeChargeLimits != nil
      {
        fallbackNativeLimit = retained.confirmedLimit
      }
      executor.invalidate()
      if calibration.active || dischargeTarget != nil {
        cancelCalibrationState(interrupted: true)
        dischargeTarget = nil
        suspended = true
      }
    }
    if settings.statisticsEnabled {
      history.append(snapshot)
      do {
        try history.flush()
        historyError = false
      } catch { historyError = true }
    }
    guard currentRevision == revision, !sleeping else {
      pending = !sleeping
      return
    }
    guard settings.onboardingComplete else {
      mode = .system
      return
    }
    do {
      // Recovery remains reachable even after advanced validation is revoked.
      if needsReset, capabilities.reset {
        try await executor.apply([.reset])
        needsReset = false
      }
      guard capabilities.canControl else {
        cancelCalibrationState(interrupted: true)
        dischargeTarget = nil
        mode = settings.controlEnabled ? .unavailable : .system
        return
      }
      guard !suspended else {
        mode = .unavailable
        return
      }
      var charge = settings.charge
      if let schedule,
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
            if dischargeTarget != nil {
              // Re-route before issuing any command for the scheduled workflow.
              pending = true
              return
            }
          }
        }
      }
      if let overrideLimit {
        charge.limit = overrideLimit
        charge.sailing = false
        charge.lower = min(charge.lower, max(20, overrideLimit - 1))
      }
      if capabilities.adapterControl == true, !charge.sailing {
        charge.sailing = true
        charge.lower = max(20, charge.limit - 5)
        if charge.limit == 20 { charge.sailing = false }
      }
      if let limits = capabilities.nativeChargeLimits {
        // Native firmware owns charging hysteresis, thermal protection and sleep.
        // Keep the limit configured on battery power as well as on AC.
        if settings.controlEnabled {
          // Overrides may request any percentage; macOS only offers fixed steps.
          if overrideLimit != nil, !limits.contains(charge.limit),
            let ceiling = CoreBridge.nativeCeiling(charge.limit, supported: limits)
          {
            charge.limit = ceiling
          }
          guard limits.contains(charge.limit), dischargeTarget == nil, !calibration.active else {
            throw BattuneError.unsupported
          }
          if helper?.confirmedLimit != charge.limit { executor.invalidate() }
          // Read back only after an actual write; the status above is current.
          if try await executor.apply([.limit(charge.limit)]) {
            let verified = try await client.status()
            guard verified.confirmedLimit == charge.limit else {
              throw BattuneError.hardwareError
            }
            helper = verified
          }
          mode = .nativeLimit
          effectiveLimit = charge.limit
        } else {
          if try await executor.apply([.reset]) { helper = try await client.status() }
          mode = .system
          effectiveLimit = nil
        }
        sensorMissing = false
        lastError = nil
        return
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
      let commands: [HardwareCommand] =
        calibration.phase == 2 && capabilities.adapterControl == true
          && !plan.sensorMissing && !plan.state.thermalHold
        ? [.discharge(false), .charging(true)] : plan.commands
      try await executor.apply(commands)
      if settings.controlEnabled && !plan.commands.contains(.reset) {
        try await client.renewLease()
      }
      state = plan.state
      sensorMissing = plan.sensorMissing
      effectiveLimit = settings.controlEnabled ? charge.limit : nil
      mode = calibration.active && plan.mode != .thermalHold ? .calibration : plan.mode
      if plan.dischargeComplete {
        dischargeTarget = nil
        pending = true
      }
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
  /// Charge to 100% once; ends automatically when the adapter is disconnected.
  public func topUp() {
    guard settings.controlEnabled, !calibration.active, dischargeTarget == nil else {
      lastError = .unsupported
      return
    }
    setOverride(ChargeOverride(kind: .topUp))
    restart()
  }
  /// Hold the current percentage (rounded up to a native step where required).
  public func pauseCharging() {
    guard settings.controlEnabled, !calibration.active, dischargeTarget == nil,
      let percentage = snapshot.percentage
    else {
      lastError = .unsupported
      return
    }
    setOverride(ChargeOverride(kind: .pause, pausedAt: max(20, percentage)))
    restart()
  }
  public func resumePlan() {
    setOverride(nil)
    restart()
  }
  /// Whether automation may select this limit on the current control path.
  public func accepts(limit: Int) -> Bool {
    guard settings.controlEnabled, (20...100).contains(limit) else { return false }
    if settings.advancedControl == true { return capabilities.canControl }
    return capabilities.nativeChargeLimits?.contains(limit) ?? capabilities.canControl
  }
  private func restart() {
    revision += 1
    executor.invalidate()
    suspended = false
    lastError = nil
    refresh()
  }
  private func setOverride(_ value: ChargeOverride?) {
    guard value != chargeOverride else { return }
    chargeOverride = value
    store.saveOverride(value)
  }
  /// macOS reports time to 100%; Battune stops earlier, so estimate to the limit.
  private func fillEstimates(target: Int) {
    let estimate = CoreBridge.estimate(snapshot, target: target)
    if snapshot.charging == true {
      snapshot.minutesToFull = estimate.toTarget
    }
    if snapshot.pluggedIn == false, snapshot.minutesToEmpty == nil {
      snapshot.minutesToEmpty = estimate.toEmpty
    }
  }
  /// MagSafe indicator and Low Power Mode never influence charge control; a
  /// failure is reported once and not retried until settings change.
  private func applyAccessories() async {
    let style = settings.indicatorStyle ?? .system
    if capabilities.indicatorControl == true || appliedIndicator != nil,
      let wanted = CoreBridge.indicator(
        style: style, mode: mode, plugged: snapshot.pluggedIn, charging: snapshot.charging),
      wanted != appliedIndicator, !(wanted == 0 && appliedIndicator == nil)
    {
      do {
        try await client.setIndicator(wanted)
        appliedIndicator = wanted == 0 ? nil : wanted
        accessoryError = nil
      } catch {
        accessoryError = error as? BattuneError ?? .hardwareError
      }
    }
    let policy = settings.powerMode ?? .unmanaged
    if policy != appliedPowerMode {
      if let profiles = policy.profiles, capabilities.powerModeControl == true {
        do {
          try await client.setLowPowerMode(battery: profiles.battery, charger: profiles.charger)
          accessoryError = nil
        } catch {
          accessoryError = error as? BattuneError ?? .hardwareError
        }
        appliedPowerMode = policy
      } else if policy == .unmanaged {
        appliedPowerMode = policy
      }
    }
  }
  /// When macOS enforces the limit itself, Battune only needs occasional samples.
  private func reportTiming() {
    let passive =
      (mode == .nativeLimit || mode == .system) && chargeOverride == nil
      && dischargeTarget == nil && !calibration.active && capabilities.adapterControl != true
    let next = ScheduleResolver.nextActivation(settings.schedules, after: Date())
    timing?(passive ? 300 : 60, next)
  }
  public func validateAdvanced() async {
    do {
      try await client.validateAdvanced()
      retry()
    } catch { lastError = error as? BattuneError ?? .hardwareError }
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
    if capabilities.adapterControl == true {
      cancelCalibrationState(interrupted: true)
      dischargeTarget = nil
      needsReset = true
    }
    do {
      try history.flush(force: true)
      try store.saveCalibration(calibration)
    } catch { lastError = .corruptPersistence }
  }
  public func didWake() {
    sleeping = false
    appliedIndicator = nil
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
    if appliedIndicator != nil { try? await client.setIndicator(0) }
    // Like System Settings, a native limit may outlive the app. It is a macOS
    // setting enforced by firmware, so keeping it costs no CPU after quitting.
    let configured = settings.charge.limit
    let keep =
      settings.keepsLimitOnQuit && settings.controlEnabled && mode == .nativeLimit
      && fallbackNativeLimit == nil
      && capabilities.nativeChargeLimits?.contains(configured) == true
    if keep {
      if effectiveLimit != configured {
        do { try await client.perform(.limit(configured)) } catch {
          logger.error("Restoring the configured limit on exit failed")
        }
      }
    } else if capabilities.reset || fallbackNativeLimit != nil || settings.controlEnabled {
      // Reset is idempotent: it only restores state that Battune still owns.
      do { try await client.perform(.reset) } catch { logger.error("Reset on exit failed") }
    }
    do { try history.flush(force: true) } catch { logger.error("History flush failed") }
  }
}
