import AppKit
import BattuneDomain
import BattuneSystem
import SwiftUI

struct PopoverView: View {
  @ObservedObject var settings: SettingsModel
  @ObservedObject var coordinator: ChargeCoordinator
  let openSettings: (SettingsPane) -> Void
  private var snapshot: BatterySnapshot { coordinator.snapshot }
  private var status: StatusStyle {
    .of(
      coordinator.mode, snapshot: snapshot, override: coordinator.chargeOverride,
      fallback: coordinator.fallbackNativeLimit)
  }
  private var nativeSteps: [Int]? {
    settings.value.advancedControl == true ? nil : coordinator.capabilities.nativeChargeLimits
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      hero
      if snapshot.systemLoad != nil || snapshot.power != nil {
        Card(padding: 10) { PowerFlow(snapshot: snapshot) }
      }
      limitCard
      actions
      notices
      footer
    }
    .padding(16)
    .frame(width: 340)
    .fixedSize(horizontal: false, vertical: true)
  }

  private var header: some View {
    HStack(spacing: 8) {
      Image(nsImage: BattuneMark.menuBarImage).renderingMode(.template)
        .foregroundStyle(.primary).accessibilityHidden(true)
      Text("Battune").font(.system(size: 14, weight: .semibold))
      Spacer()
      Button {
        openSettings(.general)
      } label: {
        Image(systemName: "gearshape").font(.system(size: 13, weight: .medium))
      }
      .buttonStyle(.plain).foregroundStyle(.secondary)
      .keyboardShortcut(",")
      .help(localized("settings"))
      .accessibilityLabel(localized("settings"))
    }
  }

  private var hero: some View {
    HStack(spacing: 16) {
      ChargeRing(
        percentage: snapshot.percentage,
        limit: coordinator.effectiveLimit ?? coordinator.fallbackNativeLimit, color: status.color
      )
      .frame(width: 92, height: 92)
      VStack(alignment: .leading, spacing: 6) {
        Label(status.title, systemImage: status.symbol)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(status.color)
          .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        if let limit = coordinator.effectiveLimit {
          detail("target", "\(localized("limit_short")) \(limit)%")
        }
        if let source = powerSource { detail(sourceSymbol, source) }
        if let time = timeText { detail("clock", time) }
      }
      Spacer(minLength: 0)
    }
  }

  private func detail(_ symbol: String, _ text: String) -> some View {
    Label(text, systemImage: symbol)
      .font(.system(size: 11)).foregroundStyle(.secondary)
      .labelStyle(DetailLabelStyle())
  }

  private var sourceSymbol: String {
    snapshot.pluggedIn == true ? "powerplug" : "battery.50percent"
  }
  private var powerSource: String? {
    switch snapshot.pluggedIn {
    case true?:
      return snapshot.adapterWatts.map { "\(localized("ac_power")) · \($0) W" }
        ?? localized("ac_power")
    case false?: return localized("battery_power")
    case nil: return nil
    }
  }
  private var timeText: String? {
    if snapshot.charging == true, let minutes = snapshot.minutesToFull {
      return String(format: localized("time_to_limit"), Format.duration(minutes: minutes))
    }
    if snapshot.pluggedIn == false, let minutes = snapshot.minutesToEmpty {
      return String(format: localized("time_remaining"), Format.duration(minutes: minutes))
    }
    return nil
  }

  private var limitCard: some View {
    Card {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text(localized("charge_limit")).font(.system(size: 12, weight: .semibold))
          Spacer()
          Text("\(settings.value.charge.limit)%")
            .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
            .foregroundStyle(.secondary)
        }
        LimitPicker(
          limit: $settings.value.charge.limit, supported: nativeSteps,
          range: (settings.value.charge.sailing ? 21 : 20)...100
        ) {
          settings.value.charge.lower = min(
            settings.value.charge.lower, max(20, settings.value.charge.limit - 1))
          if settings.save() { coordinator.updateSettings(settings.value) }
        }
        .disabled(!settings.value.controlEnabled)
        if !settings.value.controlEnabled {
          Button {
            openSettings(.charging)
          } label: {
            Label(localized("enable_control_hint"), systemImage: "power")
              .font(.system(size: 11))
          }
          .buttonStyle(.link)
        } else if coordinator.capabilities.adapterControl == true {
          Text(localized("adapter_limit_warning")).font(.system(size: 10))
            .foregroundStyle(Palette.discharging).fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private var actions: some View {
    let override = coordinator.chargeOverride
    let control = settings.value.controlEnabled
    return HStack(spacing: 8) {
      ActionTile(
        symbol: "bolt.fill", title: localized("top_up"), active: override?.kind == .topUp,
        tint: Palette.charging
      ) {
        override?.kind == .topUp ? coordinator.resumePlan() : coordinator.topUp()
      }
      .disabled(!control || coordinator.calibration.active)
      .help(localized("top_up_help"))
      ActionTile(
        symbol: override?.kind == .pause ? "play.fill" : "pause.fill",
        title: localized(override?.kind == .pause ? "resume" : "pause"),
        active: override?.kind == .pause, tint: Palette.holding
      ) {
        override?.kind == .pause ? coordinator.resumePlan() : coordinator.pauseCharging()
      }
      .disabled(!control || coordinator.calibration.active || snapshot.pluggedIn != true)
      .help(localized("pause_help"))
      ActionTile(
        symbol: "arrow.down.circle", title: localized("discharge_short"),
        active: coordinator.dischargeTarget != nil, tint: Palette.discharging
      ) {
        coordinator.dischargeTarget != nil ? coordinator.cancelWorkflow() : openSettings(.tools)
      }
      .disabled(!coordinator.capabilities.forceDischarge && coordinator.dischargeTarget == nil)
      .help(localized("discharge_help"))
      ActionTile(
        symbol: "arrow.triangle.2.circlepath", title: localized("calibrate_short"),
        active: coordinator.calibration.active, tint: Palette.discharging
      ) { openSettings(.tools) }
      .disabled(!coordinator.capabilities.canCalibrate && !coordinator.calibration.active)
      .help(localized("calibration_help"))
    }
  }

  @ViewBuilder private var notices: some View {
    if let error = coordinator.lastError ?? settings.error {
      notice("exclamationmark.triangle.fill", localized("error.\(error.rawValue)"), Palette.thermal)
    } else if !coordinator.capabilities.canControl, settings.value.controlEnabled {
      notice(
        "info.circle",
        localized(coordinator.helperError.map { "error.\($0.rawValue)" } ?? "control_unavailable"),
        .secondary)
    }
  }
  private func notice(_ symbol: String, _ text: String, _ color: Color) -> some View {
    Label(text, systemImage: symbol)
      .font(.system(size: 11)).foregroundStyle(color)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var footer: some View {
    HStack(spacing: 12) {
      stat("heart", snapshot.health.map { String(format: "%.0f%%", $0) })
        .help(localized("health"))
      stat("arrow.triangle.2.circlepath", snapshot.cycleCount.map(String.init))
        .help(localized("cycles"))
      stat("thermometer.medium", snapshot.temperature.map { String(format: "%.1f °C", $0) })
        .help(localized("temperature"))
      Spacer()
      Button(localized("quit_short")) { NSApp.terminate(nil) }
        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
        .keyboardShortcut("q")
    }
    .padding(.top, 2)
  }
  private func stat(_ symbol: String, _ value: String?) -> some View {
    Label(value ?? "—", systemImage: symbol)
      .font(.system(size: 11, design: .rounded)).monospacedDigit()
      .foregroundStyle(.secondary)
      .labelStyle(DetailLabelStyle())
  }
}

private struct DetailLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 4) {
      configuration.icon.frame(width: 14)
      configuration.title
    }
  }
}
