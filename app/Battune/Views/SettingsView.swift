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
  @ViewState private var showTutorial = false
  var body: some View {
    VStack(spacing: 0) {
      TabView(selection: $selected) {
        general.tabItem { Label(localized("general"), systemImage: "gearshape") }.tag(0)
        charging.tabItem { Label(localized("charging"), systemImage: "battery.75percent") }.tag(1)
        ScheduleView(settings: settings, coordinator: coordinator).tabItem {
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
        SetupView(settings: settings, coordinator: coordinator).tabItem {
          Label(localized("setup"), systemImage: "checkmark.shield")
        }.tag(6)
      }.padding(12)
      Divider()
      HStack {
        if let error = settings.error ?? coordinator.lastError ?? coordinator.helperError {
          Text(localized("error.\(error.rawValue)")).foregroundStyle(.red).font(.caption)
        }
        Spacer()
        Button(localized("save"), action: save).keyboardShortcut("s", modifiers: .command)
          .buttonStyle(
            .borderedProminent)
      }.padding(16)
    }.frame(minWidth: 620, minHeight: 540).onAppear {
      selected = initialTab == 5 ? 5 : (settings.value.setupComplete == true ? initialTab : 6)
      showTutorial = settings.value.tutorialVersion != 1
    }.sheet(isPresented: $showTutorial) {
      TutorialView { setup in
        settings.value.tutorialVersion = 1
        settings.value.onboardingComplete = true
        guard settings.save() else { return false }
        coordinator.updateSettings(settings.value)
        selected = setup ? 6 : 0
        showTutorial = false
        return true
      }
    }
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
      Button(localized("tour_replay")) { showTutorial = true }
      Text("Battune 0.1.0-beta.1").font(.caption).foregroundStyle(.secondary)
      Text(localized("privacy_note")).font(.callout).padding(.top)
    }.formStyle(.grouped)
  }
  private var charging: some View {
    Form {
      Section {
        if settings.value.advancedControl == true {
          Text(localized("automatic_limit_routing")).font(.callout).foregroundStyle(.secondary)
        }
        if coordinator.capabilities.adapterControl == true {
          Text(localized("adapter_limit_warning")).font(.callout).foregroundStyle(.orange)
        }
        Toggle(localized("enable_control"), isOn: $settings.value.controlEnabled)
          .disabled(!settings.value.onboardingComplete || !coordinator.capabilities.canControl)
        if !coordinator.capabilities.canControl {
          Text(localized("unsupported_detail")).foregroundStyle(.secondary)
        }
        SettingsSlider(
          "charge_limit", value: $settings.value.charge.limit,
          in: ((settings.value.advancedControl == true
            ? nil : coordinator.capabilities.nativeChargeLimits)?.min()
            ?? (settings.value.charge.sailing ? 21 : 20))...100,
          supportedValues: settings.value.advancedControl == true
            ? nil : coordinator.capabilities.nativeChargeLimits
        )
        .onChange(of: settings.value.charge.limit) { limit in
          settings.value.charge.lower = min(settings.value.charge.lower, max(20, limit - 1))
        }
        if coordinator.capabilities.nativeChargeLimits == nil {
          Toggle(localized("sailing"), isOn: $settings.value.charge.sailing)
            .disabled(settings.value.charge.limit <= 20)
          SettingsSlider(
            "lower_limit", value: $settings.value.charge.lower,
            in: 20...max(21, settings.value.charge.limit - 1)
          )
          .disabled(!settings.value.charge.sailing || settings.value.charge.limit <= 21)
        } else {
          Text(localized("native_control_detail")).font(.callout).foregroundStyle(.secondary)
          if let limit = coordinator.helper?.confirmedLimit {
            LabeledContent(localized("confirmed_limit"), value: "\(limit)%")
          }
        }
      }
      if coordinator.capabilities.nativeChargeLimits == nil {
        Section(localized("thermal")) {
          Toggle(localized("enable_thermal"), isOn: $settings.value.charge.thermal)
          SettingsSlider(
            "stop_temperature", value: $settings.value.charge.stopTemperature, in: 21...50
          )
          .onChange(of: settings.value.charge.stopTemperature) { stop in
            settings.value.charge.resumeTemperature = min(
              settings.value.charge.resumeTemperature, stop - 1)
          }
          SettingsSlider(
            "resume_temperature", value: $settings.value.charge.resumeTemperature,
            in: 20...max(21, settings.value.charge.stopTemperature - 1)
          )
          .disabled(settings.value.charge.stopTemperature <= 21)
          Text(localized("thermal_note")).font(.caption).foregroundStyle(.secondary)
        }
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
