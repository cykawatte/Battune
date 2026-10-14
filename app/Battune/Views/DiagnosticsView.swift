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
  @ViewState private var probes: [SMCProbe] = []
  @ViewState private var rootStatus: HelperStatus?
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          Text(localized("diagnostics_permissions")).font(.callout)
          Text(localized("diagnostics_entitlement")).font(.caption).foregroundStyle(.secondary)
          ForEach(probes) { probe in
            VStack(alignment: .leading, spacing: 2) {
              Text("\(probe.key) · \(probe.result)").font(.system(.caption, design: .monospaced))
              Text(
                localized(
                  probe.readable
                    ? "probe_readable"
                    : probe.ioResult == 0xe000_02c1 ? "probe_privileged" : "probe_absent")
              ).font(.caption).foregroundStyle(.secondary)
            }
          }
          Text(report).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
      Text(
        localized(
          coordinator.capabilities.nativeChargeLimits == nil
            ? "helper_signing_note" : "native_no_helper")
      ).font(.caption).foregroundStyle(.secondary)
      if helperOperationError { Text(localized("helper_registration_error")).foregroundStyle(.red) }
      HStack {
        Button(localized("copy_diagnostics")) {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(report, forType: .string)
        }
        Button(localized("refresh")) {
          coordinator.retry()
          Task { await scan() }
        }
        Button(localized("export_diagnostics")) { export() }
      }
      if coordinator.capabilities.nativeChargeLimits == nil {
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
          }.disabled(
            settings.value.controlEnabled || helperOperationBusy
              || SigningIdentity.teamIdentifier() == nil)
          Button(localized("login_settings")) { SMAppService.openSystemSettingsLoginItems() }
        }
      }
      Button(localized("reset_control")) { confirmReset = true }.disabled(
        !coordinator.capabilities.reset || coordinator.busy)
      #if DEBUG
        Text(localized("developer_mode")).font(.caption).foregroundStyle(.secondary)
      #endif
    }.padding(16).task { await scan() }
      .alert(localized("reset_control"), isPresented: $confirmReset) {
        Button(localized("cancel"), role: .cancel) {}
        Button(localized("reset_control")) {
          settings.value.controlEnabled = false
          if settings.commit(to: coordinator) { coordinator.reset() }
        }
      } message: {
        Text(localized("reset_explanation"))
      }
  }
  private func scan() async {
    probes = await Task.detached { SMCProbe.all() }.value
    rootStatus = try? await HelperClient().status()
  }
  private func export() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Battune-diagnostics.txt"
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      do { try report.write(to: url, atomically: true, encoding: .utf8) } catch {
        helperOperationError = true
      }
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
      Battune \(BattuneVersion.current)
      macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
      Architecture: \(architecture)
      Controller: \(coordinator.helper?.version ?? "unavailable")
      Helper registration: \(HelperClient.registrationStatus.rawValue)
      Helper error: \(coordinator.helperError.map { String(describing: $0) } ?? "none")
      Backend: \(coordinator.helper?.backend ?? "local IOKit read-only")
      Read battery: \(c.readBattery)
      Temperature sensor available: \(coordinator.snapshot.temperature != nil)
      Set limit: \(c.setLimit)
      Native supported limits: \(c.nativeChargeLimits?.map(String.init).joined(separator: ", ") ?? "none")
      Confirmed native limit: \(coordinator.helper?.confirmedLimit.map(String.init) ?? "unknown")
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
      Local helper trust: \(LocalInstallationTrust.peerRequirement(forHelper: true) != nil)
      Advanced mode requested: \(settings.value.advancedControl == true)
      Adapter control: \(c.adapterControl == true)
      Control blocked: \(coordinator.helperError.map { localized("error.\($0.rawValue)") } ?? "none")
      Effective limit: \(coordinator.effectiveLimit.map(String.init) ?? "none")
      Override: \(coordinator.chargeOverride.map { "\($0.kind)" } ?? "none")
      MagSafe indicator control: \(c.indicatorControl == true)
      Low Power Mode control: \(c.powerModeControl == true)
      Accessory error: \(coordinator.accessoryError.map { String(describing: $0) } ?? "none")
      System load: \(coordinator.snapshot.systemLoad.map { String(format: "%.2f W", $0) } ?? "unknown")
      Adapter input: \(coordinator.snapshot.adapterInput.map { String(format: "%.2f W", $0) } ?? "unknown")
      Retained native limit: \(coordinator.fallbackNativeLimit.map(String.init) ?? "none")
      Root helper: \(rootStatus?.backend ?? "not connected")
      Root hardware result: \(rootStatus?.hardwareDiagnostic ?? "not tested")
      SMC read-only probe:
      \(probes.map { "\($0.key): \($0.result)" }.joined(separator: "\n"))
      Telemetry: none
      """
  }
}
