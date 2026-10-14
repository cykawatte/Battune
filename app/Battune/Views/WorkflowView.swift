import BattuneSystem
import SwiftUI

struct WorkflowView: View {
  @ObservedObject var coordinator: ChargeCoordinator
  @ViewState private var target = 75
  @ViewState private var confirmingCalibration = false
  @ViewState private var confirmingDischarge = false
  var body: some View {
    Form {
      if !coordinator.capabilities.forceDischarge {
        Section {
          Label(localized("workflow_setup_required"), systemImage: "lock")
            .foregroundStyle(.secondary)
        }
      }
      Section(localized("discharge")) {
        Text(localized("discharge_explanation"))
        SettingsSlider("target", value: $target, in: 20...100)
        Button(localized("start_discharge")) { confirmingDischarge = true }
          .disabled(
            !coordinator.capabilities.forceDischarge || coordinator.calibration.active
              || coordinator.busy)
        if let target = coordinator.dischargeTarget {
          Label("\(localized("target")): \(target)%", systemImage: "arrow.down.circle.fill")
            .foregroundStyle(Palette.discharging)
          Button(localized("cancel_restore")) { coordinator.cancelWorkflow() }
        }
      }
      Section(localized("calibration")) {
        Text(localized("calibration_explanation"))
        if coordinator.calibration.active {
          ProgressView(value: Double(coordinator.calibration.phase), total: 4)
          Text(localized("calibration_progress_note")).font(.caption).foregroundStyle(.secondary)
        }
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
