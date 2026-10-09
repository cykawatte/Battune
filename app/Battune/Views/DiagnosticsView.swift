import AppKit
import SwiftUI
import ServiceManagement
import BattuneDomain
import BattuneShared
import BattuneSystem
struct DiagnosticsView: View {
    @ObservedObject var coordinator: ChargeCoordinator
    @ObservedObject var settings: SettingsModel
    @ViewState private var helperOperationError = false
    @ViewState private var helperOperationBusy = false
    @ViewState private var confirmReset = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView { Text(report).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            Text(L("helper_signing_note")).font(.caption).foregroundStyle(.secondary)
            if helperOperationError { Text(L("helper_registration_error")).foregroundStyle(.red) }
            HStack {
                Button(L("copy_diagnostics")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(report, forType: .string) }
                Button(L("refresh")) { coordinator.retry() }
            }
            HStack {
                Button(L("register_helper")) {
                    do { try HelperClient.register(); helperOperationError = false; coordinator.retry() }
                    catch { helperOperationError = true }
                }.disabled(SigningIdentity.teamIdentifier() == nil || helperOperationBusy)
                Button(L("remove_helper")) {
                    helperOperationBusy = true
                    Task {
                        do { try await HelperClient.unregister(); helperOperationError = false }
                        catch { helperOperationError = true }
                        helperOperationBusy = false; coordinator.retry()
                    }
                }.disabled(settings.value.controlEnabled || helperOperationBusy)
                Button(L("login_settings")) { SMAppService.openSystemSettingsLoginItems() }
            }
            Button(L("reset_control")) { confirmReset = true }.disabled(!coordinator.capabilities.reset || coordinator.busy)
            #if DEBUG
            Text(L("developer_mode")).font(.caption).foregroundStyle(.secondary)
            #endif
        }.padding(16)
            .alert(L("reset_control"), isPresented: $confirmReset) {
                Button(L("cancel"), role: .cancel) {}
                Button(L("reset_control")) {
                    settings.value.controlEnabled = false
                    if settings.save() { coordinator.updateSettings(settings.value); coordinator.reset() }
                }
            } message: { Text(L("reset_explanation")) }
    }
    private var report: String {
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        let c = coordinator.capabilities
        return """
        Battune 0.1.0-dev
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Architecture: \(architecture)
        Helper: \(coordinator.helper?.version ?? "unavailable")
        Helper registration: \(HelperClient.registrationStatus.rawValue)
        Helper error: \(coordinator.helperError.map { String(describing: $0) } ?? "none")
        Backend: \(coordinator.helper?.backend ?? "local IOKit read-only")
        Read battery: \(c.readBattery)
        Read temperature: \(c.readTemperature)
        Set limit: \(c.setLimit)
        Toggle charging: \(c.toggleCharging)
        Force discharge: \(c.forceDischarge)
        Reset: \(c.reset)
        Battery: \(coordinator.snapshot.percentage.map { "\($0)%" } ?? "unknown")
        Charging: \(coordinator.snapshot.charging.map(String.init) ?? "unknown")
        Active mode: \(coordinator.mode)
        Calibration phase: \(coordinator.calibration.phase)
        Last confirmed action: \(coordinator.executor.lastAction.map { String(describing: $0) } ?? "none")
        Last error: \(coordinator.lastError.map { String(describing: $0) } ?? "none")
        Missing safety sensor: \(coordinator.sensorMissing)
        Telemetry: none
        """
    }
}
