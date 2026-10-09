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
        Text("0.1.0-dev").font(.caption).foregroundStyle(.secondary)
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
        Label(localized("unsupported"), systemImage: "info.circle").font(.caption).foregroundStyle(
          .secondary)
      }
      Divider()
      HStack {
        Text(localized("charge_limit"))
        Spacer()
        Text("\(settings.value.charge.limit)%").monospacedDigit()
      }
      Slider(
        value: Binding(
          get: { Double(settings.value.charge.limit) },
          set: { settings.value.charge.limit = Int($0) }), in: 20...100, step: 1
      ) { editing in
        if !editing, settings.save() { coordinator.updateSettings(settings.value) }
      }.accessibilityLabel(localized("charge_limit"))
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
      if let error = coordinator.lastError ?? settings.error {
        Text(localized("error.\(error.rawValue)")).font(.caption).foregroundStyle(.red)
      }
      Divider()
      HStack {
        Button(localized("settings"), action: openSettings).keyboardShortcut(",")
        Spacer()
        Button(localized("quit")) { NSApp.terminate(nil) }.keyboardShortcut("q")
      }
    }.padding(20).frame(width: 320)
  }
}
