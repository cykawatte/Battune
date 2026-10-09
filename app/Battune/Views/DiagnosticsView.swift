import AppKit
import BattuneDomain
import BattuneShared
import BattuneSystem
import ServiceManagement
import SwiftUI

struct DiagnosticsView: View {
  @ObservedObject var coordinator: ChargeCoordinator
  @ObservedObject var settings: SettingsModel
  @ViewState private var helperOperationError = false
  @ViewState private var helperOperationBusy = false
  @ViewState private var confirmReset = false
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ScrollView {
        Text(report).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(
          maxWidth: .infinity, alignment: .leading)
      }
      Text(localized("helper_signing_note")).font(.caption).foregroundStyle(.secondary)
      if helperOperationError { Text(localized("helper_registration_error")).foregroundStyle(.red) }
      HStack {
        Button(localized("copy_diagnostics")) {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(report, forType: .string)
        }
        Button(localized("refresh")) { coordinator.retry() }
      }
      HStack {
        Button(localized("register_helper")) {
          do {
            try HelperClient.register()
            helperOperationError = false
            coordinator.retry()
          } catch { helperOperationError = true }
        }.disabled(SigningIdentity.teamIdentifier() == nil || helperOperationBusy)
        Button(localized("remove_helper")) {
          helperOperationBusy = true
          Task {
            do {
              try await HelperClient.unregister()
              helperOperationError = false
            } catch { helperOperationError = true }
            helperOperationBusy = false
            coordinator.retry()
          }
        }.disabled(settings.value.controlEnabled || helperOperationBusy)
        Button(localized("login_settings")) { SMAppService.openSystemSettingsLoginItems() }
      }
      Button(localized("reset_control")) { confirmReset = true }.disabled(
        !coordinator.capabilities.reset || coordinator.busy)
      #if DEBUG
        Text(localized("developer_mode")).font(.caption).foregroundStyle(.secondary)
      #endif
    }.padding(16)
      .alert(localized("reset_control"), isPresented: $confirmReset) {
        Button(localized("cancel"), role: .cancel) {}
        Button(localized("reset_control")) {
          settings.value.controlEnabled = false
          if settings.save() {
            coordinator.updateSettings(settings.value)
            coordinator.reset()
          }
        }
      } message: {
        Text(localized("reset_explanation"))
      }
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
