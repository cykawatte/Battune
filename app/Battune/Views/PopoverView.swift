import AppKit
import BattuneDomain
import BattuneSystem
import SwiftUI

struct PopoverView: View {
  @ObservedObject var settings: SettingsModel
  @ObservedObject var coordinator: ChargeCoordinator
  let openSettings: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Battune").font(.headline)
        Spacer()
        Text("0.1.0-beta.1").font(.caption).foregroundStyle(.secondary)
      }
      HStack(alignment: .firstTextBaseline) {
        Text(coordinator.snapshot.percentage.map { "\($0)%" } ?? "—").font(
          .system(size: 40, weight: .medium, design: .rounded)
        ).monospacedDigit()
        Spacer()
        Label(
          localized(
            coordinator.snapshot.pluggedIn == true
              ? "ac_power" : coordinator.snapshot.pluggedIn == false ? "battery_power" : "unknown"),
          systemImage: coordinator.snapshot.pluggedIn == true ? "powerplug" : "battery.50percent"
        )
        .foregroundStyle(.secondary)
      }
      Text(localized(coordinator.mode.localizationKey)).font(.headline)
      if !coordinator.capabilities.canControl {
        Label(localized("control_unavailable"), systemImage: "info.circle").font(.caption)
          .foregroundStyle(
            .secondary)
      }
      if coordinator.capabilities.adapterControl == true {
        Text(localized("adapter_limit_warning")).font(.caption).foregroundStyle(.orange)
      }
      Divider()
      SettingsSlider(
        "charge_limit", value: $settings.value.charge.limit,
        in: ((settings.value.advancedControl == true
          ? nil : coordinator.capabilities.nativeChargeLimits)?.min()
          ?? (settings.value.charge.sailing ? 21 : 20))...100,
        supportedValues: settings.value.advancedControl == true
          ? nil : coordinator.capabilities.nativeChargeLimits
      ) { editing in
        if !editing, settings.save() { coordinator.updateSettings(settings.value) }
      }
      .onChange(of: settings.value.charge.limit) { limit in
        settings.value.charge.lower = min(settings.value.charge.lower, max(20, limit - 1))
      }
      if coordinator.capabilities.nativeChargeLimits == nil {
        HStack {
          Text(localized("sailing"))
          Spacer()
          Text(localized(settings.value.charge.sailing ? "on" : "off"))
        }
        HStack {
          Text(localized("thermal"))
          Spacer()
          Text(localized(settings.value.charge.thermal ? "on" : "off"))
        }
      } else {
        HStack {
          Text(localized("confirmed_limit"))
          Spacer()
          Text(coordinator.helper?.confirmedLimit.map { "\($0)%" } ?? "—")
        }
        Text(localized("native_short_detail")).font(.caption).foregroundStyle(.secondary)
      }
      if let error = coordinator.lastError ?? settings.error {
        Text(localized("error.\(error.rawValue)")).font(.caption).foregroundStyle(.red)
      }
      Divider()
      HStack {
        Button(localized("settings"), action: openSettings).keyboardShortcut(",")
        Spacer()
        Button(localized("quit")) { NSApp.terminate(nil) }.keyboardShortcut("q")
      }
    }.padding(20).frame(width: 340).fixedSize(horizontal: false, vertical: true)
  }
}
