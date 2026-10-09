import SwiftUI
import BattuneSystem
struct WorkflowView: View {
    @ObservedObject var coordinator: ChargeCoordinator
    @ViewState private var target = 75
    @ViewState private var confirmingCalibration = false
    @ViewState private var confirmingDischarge = false
    var body: some View {
        Form {
            Section(L("discharge")) {
                Text(L("discharge_explanation"))
                Stepper("\(L("target")): \(target)%", value: $target, in: 20...100)
                Button(L("start_discharge")) { confirmingDischarge = true }
                    .disabled(!coordinator.capabilities.forceDischarge || coordinator.calibration.active || coordinator.busy)
                if let target = coordinator.dischargeTarget { Text("\(L("target")): \(target)%") }
            }
            Section(L("calibration")) {
                Text(L("calibration_explanation"))
                Text("\(L("status")): \(L("phase.\(coordinator.calibration.phase)"))").font(.headline)
                Button(L("start_calibration")) { confirmingCalibration = true }
                    .disabled(!coordinator.capabilities.canCalibrate || coordinator.calibration.active || coordinator.busy)
                Button(L("cancel_restore")) { coordinator.cancelWorkflow() }
                    .disabled(!coordinator.calibration.active && coordinator.dischargeTarget == nil)
                if !coordinator.capabilities.canCalibrate { Text(L("unsupported")).foregroundStyle(.secondary) }
            }
        }.formStyle(.grouped)
            .alert(L("start_calibration"), isPresented: $confirmingCalibration) {
                Button(L("cancel"), role: .cancel) {}; Button(L("start")) { coordinator.startCalibration() }
            } message: { Text(L("calibration_explanation")) }
            .alert(L("start_discharge"), isPresented: $confirmingDischarge) {
                Button(L("cancel"), role: .cancel) {}; Button(L("start")) { coordinator.startDischarge(target: target) }
            } message: { Text(L("discharge_explanation")) }
    }
}
