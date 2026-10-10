import BattuneDomain
import BattuneSystem
import ServiceManagement
import SwiftUI
import UserNotifications

struct SettingsView: View {
  @ObservedObject var settings: SettingsModel
  @ObservedObject var coordinator: ChargeCoordinator
  let history: HistoryStore
  let historyLoadFailed: Bool
  var initialTab = 0
  @ViewState private var selected = 0
  @ViewState private var notificationError = false
  var body: some View {
    VStack(spacing: 0) {
      if !settings.value.onboardingComplete {
        VStack(alignment: .leading, spacing: 12) {
          Text(localized("welcome")).font(.title2.bold())
          Text(localized("onboarding_body"))
          Button(localized("start_monitoring")) {
            settings.value.onboardingComplete = true
            save()
          }.buttonStyle(.borderedProminent)
        }.padding(24)
        Divider()
      }
      TabView(selection: $selected) {
        general.tabItem { Label(localized("general"), systemImage: "gearshape") }.tag(0)
        charging.tabItem { Label(localized("charging"), systemImage: "battery.75percent") }.tag(1)
        ScheduleView(settings: settings).tabItem {
          Label(localized("schedules"), systemImage: "calendar")
        }
        .tag(2)
        WorkflowView(coordinator: coordinator).tabItem {
          Label(localized("calibration"), systemImage: "arrow.triangle.2.circlepath")
        }.tag(3)
        StatisticsView(coordinator: coordinator, history: history, loadFailed: historyLoadFailed)
          .tabItem { Label(localized("statistics"), systemImage: "chart.xyaxis.line") }.tag(4)
        DiagnosticsView(coordinator: coordinator, settings: settings).tabItem {
          Label(localized("diagnostics"), systemImage: "stethoscope")
        }.tag(5)
      }.padding(12)
      Divider()
      HStack {
        if let error = settings.error ?? coordinator.lastError {
          Text(localized("error.\(error.rawValue)")).foregroundStyle(.red).font(.caption)
        }
        Spacer()
        Button(localized("save"), action: save).keyboardShortcut("s", modifiers: .command)
          .buttonStyle(
            .borderedProminent)
      }.padding(16)
    }.frame(minWidth: 620, minHeight: 540).onAppear { selected = initialTab }
  }
  private var general: some View {
    Form {
      Toggle(
        localized("launch_login"),
        isOn: Binding(get: { settings.loginEnabled }, set: { settings.setLogin($0) }))
      Toggle(localized("show_percentage"), isOn: $settings.value.showPercentage)
      Toggle(localized("record_history"), isOn: $settings.value.statisticsEnabled)
      Toggle(localized("notifications"), isOn: $settings.value.notificationsEnabled).onChange(
        of: settings.value.notificationsEnabled
      ) { enabled in
        if enabled {
          UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
            Task { @MainActor in
              if !granted {
                settings.value.notificationsEnabled = false
                notificationError = true
              }
            }
          }
        }
      }
      if notificationError { Text(localized("notification_denied")).foregroundStyle(.secondary) }
      Picker(localized("language"), selection: $settings.value.language) {
        Text(localized("system_language")).tag("system")
        Text("English").tag("en")
        Text("Deutsch").tag("de")
      }
      Text(localized("language_restart")).font(.caption).foregroundStyle(.secondary)
      Text(localized("privacy_note")).font(.callout).padding(.top)
    }.formStyle(.grouped)
  }
  private var charging: some View {
    Form {
      Section {
        Toggle(localized("enable_control"), isOn: $settings.value.controlEnabled)
          .disabled(!settings.value.onboardingComplete || !coordinator.capabilities.canControl)
        if !coordinator.capabilities.canControl {
          Text(localized("unsupported_detail")).foregroundStyle(.secondary)
        }
        Stepper(
          "\(localized("charge_limit")): \(settings.value.charge.limit)%",
          value: $settings.value.charge.limit, in: 20...100)
        Toggle(localized("sailing"), isOn: $settings.value.charge.sailing)
        Stepper(
          "\(localized("lower_limit")): \(settings.value.charge.lower)%",
          value: $settings.value.charge.lower, in: 20...99
        ).disabled(!settings.value.charge.sailing)
      }
      Section(localized("thermal")) {
        Toggle(localized("enable_thermal"), isOn: $settings.value.charge.thermal)
        Stepper(
          "\(localized("stop_temperature")): \(Int(settings.value.charge.stopTemperature)) °C",
          value: $settings.value.charge.stopTemperature, in: 21...50)
        Stepper(
          "\(localized("resume_temperature")): \(Int(settings.value.charge.resumeTemperature)) °C",
          value: $settings.value.charge.resumeTemperature, in: 20...49)
        Text(localized("thermal_note")).font(.caption).foregroundStyle(.secondary)
      }
    }.formStyle(.grouped)
  }
  private func save() {
    if settings.save() {
      UserDefaults.standard.set(settings.value.language, forKey: "ui.language")
      coordinator.updateSettings(settings.value)
    }
  }
}
