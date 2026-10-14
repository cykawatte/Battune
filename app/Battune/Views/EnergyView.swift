import BattuneDomain
import BattuneSystem
import Combine
import SwiftUI

/// Accessories that never change charging: MagSafe indicator and Low Power Mode.
struct EnergyView: View {
  @ObservedObject var settings: SettingsModel
  @ObservedObject var coordinator: ChargeCoordinator
  @ViewState private var lowPowerActive = ProcessInfo.processInfo.isLowPowerModeEnabled
  var body: some View {
    Form {
      Section {
        Picker(
          localized("magsafe_led"),
          selection: Binding(
            get: { settings.value.indicatorStyle ?? .system },
            set: { settings.value.indicatorStyle = $0 })
        ) {
          ForEach(IndicatorStyle.allCases, id: \.self) { style in
            Text(localized("led.\(style.rawValue)")).tag(style)
          }
        }
        .disabled(coordinator.capabilities.indicatorControl != true)
      } header: {
        Text(localized("magsafe"))
      } footer: {
        Text(
          localized(
            coordinator.capabilities.indicatorControl == true ? "magsafe_note" : "helper_needed")
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Section {
        Picker(
          localized("low_power_mode"),
          selection: Binding(
            get: { settings.value.powerMode ?? .unmanaged },
            set: { settings.value.powerMode = $0 })
        ) {
          ForEach(PowerModePolicy.allCases, id: \.self) { policy in
            Text(localized("lpm.\(policy.rawValue)")).tag(policy)
          }
        }
        .disabled(coordinator.capabilities.powerModeControl != true)
        LabeledContent(
          localized("lpm_current"), value: localized(lowPowerActive ? "on" : "off"))
      } header: {
        Text(localized("low_power_mode"))
      } footer: {
        Text(
          localized(
            coordinator.capabilities.powerModeControl == true ? "lpm_note" : "helper_needed")
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      if let error = coordinator.accessoryError {
        Section {
          Label(localized("error.\(error.rawValue)"), systemImage: "exclamationmark.triangle")
            .foregroundStyle(Palette.thermal)
        }
      }
      Section(localized("efficiency")) {
        Text(localized("efficiency_note")).font(.callout).foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .onReceive(
      NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
        .receive(on: DispatchQueue.main)
    ) { _ in lowPowerActive = ProcessInfo.processInfo.isLowPowerModeEnabled }
  }
}
