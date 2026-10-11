import AppKit
import BattuneShared
import BattuneSystem
import ServiceManagement
import SwiftUI
import UserNotifications

struct SetupView: View {
  @ObservedObject var settings: SettingsModel
  @ObservedObject var coordinator: ChargeCoordinator
  @ViewState private var confirmInstall = false
  @ViewState private var confirmTest = false
  @ViewState private var helperReady = false
  @ViewState private var working = false
  @ViewState private var statusMessage = ""
  var body: some View {
    Form {
      Section(localized("setup_native")) {
        Text(localized("setup_native_detail"))
      }
      Section(localized("setup_advanced")) {
        Text(localized("setup_advanced_detail"))
        Text(localized("setup_restrictions")).font(.callout).foregroundStyle(.secondary)
        HStack {
          Button(localized("install_helper")) { confirmInstall = true }
          Button(localized("test_adapter")) { confirmTest = true }
            .disabled(working || LocalInstallationTrust.peerRequirement(forHelper: true) == nil)
          Button(localized("refresh")) { Task { await refresh() } }.disabled(working)
        }
        Toggle(
          localized("use_advanced"),
          isOn: Binding(
            get: { settings.value.advancedControl == true },
            set: { enabled in
              guard !enabled || helperReady else { return }
              settings.value.advancedControl = enabled
              if settings.save() { coordinator.updateSettings(settings.value) }
            })
        )
        .disabled(!helperReady && settings.value.advancedControl != true)
        Text(localized(helperReady ? "adapter_ready" : "adapter_pending")).foregroundStyle(
          .secondary)
        if !statusMessage.isEmpty { Text(statusMessage).font(.caption).foregroundStyle(.secondary) }
      }
      Section(localized("setup_optional")) {
        Toggle(localized("record_history"), isOn: $settings.value.statisticsEnabled)
        Button(localized("request_notifications")) {
          UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
            Task { @MainActor in
              settings.value.notificationsEnabled = granted
              _ = settings.save()
            }
          }
        }
        Toggle(
          localized("launch_login"),
          isOn: Binding(get: { settings.loginEnabled }, set: { settings.setLogin($0) }))
      }
      Button(localized("complete_setup")) {
        settings.value.setupComplete = true
        settings.value.onboardingComplete = true
        if settings.save() { coordinator.updateSettings(settings.value) }
      }.buttonStyle(.borderedProminent)
    }.formStyle(.grouped)
      .task { await refresh() }
      .alert(localized("install_helper"), isPresented: $confirmInstall) {
        Button(localized("cancel"), role: .cancel) {}
        Button(localized("open_installer")) { install() }
      } message: {
        Text(localized("install_consent"))
      }
      .alert(localized("test_adapter"), isPresented: $confirmTest) {
        Button(localized("cancel"), role: .cancel) {}
        Button(localized("approve_test")) {
          working = true
          Task {
            await coordinator.validateAdvanced()
            await refresh()
            working = false
          }
        }
      } message: {
        Text(localized("adapter_test_consent"))
      }
  }
  private func refresh() async {
    do {
      let value = try await HelperClient().status()
      helperReady = value.capabilities.adapterControl == true && value.capabilities.canControl
      statusMessage = [value.backend, value.hardwareDiagnostic].compactMap { $0 }.joined(
        separator: "\n")
      if let error = coordinator.lastError {
        statusMessage += "\n" + localized("error.\(error.rawValue)")
      }
    } catch {
      helperReady = false
      statusMessage = localized("helper_setup_missing")
    }
  }
  private func install() {
    if SigningIdentity.teamIdentifier() != nil {
      do {
        try HelperClient.register()
        SMAppService.openSystemSettingsLoginItems()
      } catch { statusMessage = localized("helper_registration_error") }
    } else {
      let package = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(
        "BattuneHelper.pkg")
      guard FileManager.default.fileExists(atPath: package.path) else {
        statusMessage = localized("installer_missing")
        return
      }
      NSWorkspace.shared.open(package)
    }
  }
}
