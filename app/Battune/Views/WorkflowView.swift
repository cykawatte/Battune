import BattuneSystem
import SwiftUI

struct WorkflowView: View {
  @ObservedObject var coordinator: ChargeCoordinator
  @ViewState private var target = 75
  @ViewState private var confirmingCalibration = false
  @ViewState private var confirmingDischarge = false
  var body: some View {
    Form {
      Section(localized("discharge")) {
        Text(localized("discharge_explanation"))
        SettingsSlider("target", value: $target, in: 20...100)
        Button(localized("start_discharge")) { confirmingDischarge = true }
          .disabled(
            !coordinator.capabilities.forceDischarge || coordinator.calibration.active
              || coordinator.busy)
        if let target = coordinator.dischargeTarget { Text("\(localized("target")): \(target)%") }
      }
      Section(localized("calibration")) {
        Text(localized("calibration_explanation"))
        Text("\(localized("status")): \(localized("phase.\(coordinator.calibration.phase)"))").font(
          .headline)
        Button(localized("start_calibration")) { confirmingCalibration = true }
          .disabled(
            !coordinator.capabilities.canCalibrate || coordinator.calibration.active
              || coordinator.busy)
        Button(localized("cancel_restore")) { coordinator.cancelWorkflow() }
          .disabled(!coordinator.calibration.active && coordinator.dischargeTarget == nil)
        if !coordinator.capabilities.canCalibrate {
          Text(localized("unsupported")).foregroundStyle(.secondary)
        }
      }
    }.formStyle(.grouped)
      .alert(localized("start_calibration"), isPresented: $confirmingCalibration) {
        Button(localized("cancel"), role: .cancel) {}
        Button(localized("start")) { coordinator.startCalibration() }
      } message: {
        Text(localized("calibration_explanation"))
      }
      .alert(localized("start_discharge"), isPresented: $confirmingDischarge) {
        Button(localized("cancel"), role: .cancel) {}
        Button(localized("start")) { coordinator.startDischarge(target: target) }
      } message: {
        Text(localized("discharge_explanation"))
      }
  }
}
