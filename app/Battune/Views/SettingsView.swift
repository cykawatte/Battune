import SwiftUI
import ServiceManagement
import UserNotifications
import BattuneDomain
import BattuneSystem
struct SettingsView: View {
    @ObservedObject var settings: SettingsModel
    @ObservedObject var coordinator: ChargeCoordinator
    let history: HistoryStore
    let historyLoadFailed: Bool
    @ViewState private var selected = 0
    @ViewState private var notificationError = false
    var body: some View {
        VStack(spacing: 0) {
            if !settings.value.onboardingComplete {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("welcome")).font(.title2.bold())
                    Text(L("onboarding_body"))
                    Button(L("start_monitoring")) { settings.value.onboardingComplete = true; save() }.buttonStyle(.borderedProminent)
                }.padding(24)
                Divider()
            }
            TabView(selection: $selected) {
                general.tabItem { Label(L("general"), systemImage: "gearshape") }.tag(0)
                charging.tabItem { Label(L("charging"), systemImage: "battery.75percent") }.tag(1)
                ScheduleView(settings: settings).tabItem { Label(L("schedules"), systemImage: "calendar") }.tag(2)
                WorkflowView(coordinator: coordinator).tabItem { Label(L("calibration"), systemImage: "arrow.triangle.2.circlepath") }.tag(3)
                StatisticsView(coordinator: coordinator, history: history, loadFailed: historyLoadFailed).tabItem { Label(L("statistics"), systemImage: "chart.xyaxis.line") }.tag(4)
                DiagnosticsView(coordinator: coordinator, settings: settings).tabItem { Label(L("diagnostics"), systemImage: "stethoscope") }.tag(5)
            }.padding(12)
            Divider()
            HStack {
                if let error = settings.error ?? coordinator.lastError { Text(L("error.\(error.rawValue)")).foregroundStyle(.red).font(.caption) }
                Spacer()
                Button(L("save"), action: save).keyboardShortcut("s", modifiers: .command).buttonStyle(.borderedProminent)
            }.padding(16)
        }.frame(minWidth: 620, minHeight: 540)
    }
    private var general: some View {
        Form {
            Toggle(L("launch_login"), isOn: Binding(get: { settings.loginEnabled }, set: { settings.setLogin($0) }))
            Toggle(L("show_percentage"), isOn: $settings.value.showPercentage)
            Toggle(L("record_history"), isOn: $settings.value.statisticsEnabled)
            Toggle(L("notifications"), isOn: $settings.value.notificationsEnabled).onChange(of: settings.value.notificationsEnabled) { enabled in
                if enabled {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
                        Task { @MainActor in if !granted { settings.value.notificationsEnabled = false; notificationError = true } }
                    }
                }
            }
            if notificationError { Text(L("notification_denied")).foregroundStyle(.secondary) }
            Picker(L("language"), selection: $settings.value.language) {
                Text(L("system_language")).tag("system"); Text("English").tag("en"); Text("Deutsch").tag("de")
            }
            Text(L("language_restart")).font(.caption).foregroundStyle(.secondary)
            Text(L("privacy_note")).font(.callout).padding(.top)
        }.formStyle(.grouped)
    }
    private var charging: some View {
        Form {
            Section {
                Toggle(L("enable_control"), isOn: $settings.value.controlEnabled)
                    .disabled(!settings.value.onboardingComplete || !coordinator.capabilities.canControl)
                if !coordinator.capabilities.canControl { Text(L("unsupported_detail")).foregroundStyle(.secondary) }
                Stepper("\(L("charge_limit")): \(settings.value.charge.limit)%", value: $settings.value.charge.limit, in: 20...100)
                Toggle(L("sailing"), isOn: $settings.value.charge.sailing)
                Stepper("\(L("lower_limit")): \(settings.value.charge.lower)%", value: $settings.value.charge.lower, in: 20...99).disabled(!settings.value.charge.sailing)
            }
            Section(L("thermal")) {
                Toggle(L("enable_thermal"), isOn: $settings.value.charge.thermal)
                Stepper("\(L("stop_temperature")): \(Int(settings.value.charge.stopTemperature)) °C", value: $settings.value.charge.stopTemperature, in: 21...50)
                Stepper("\(L("resume_temperature")): \(Int(settings.value.charge.resumeTemperature)) °C", value: $settings.value.charge.resumeTemperature, in: 20...49)
                Text(L("thermal_note")).font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private func save() {
        if settings.save() { UserDefaults.standard.set(settings.value.language, forKey: "ui.language"); coordinator.updateSettings(settings.value) }
    }
}
