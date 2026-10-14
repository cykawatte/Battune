import BattuneDomain
import BattuneSystem
import ServiceManagement
import SwiftUI
import UserNotifications

enum SettingsPane: Int, CaseIterable, Identifiable {
  case general, charging, schedules, tools, energy, statistics, diagnostics, setup
  var id: Int { rawValue }
  var titleKey: String {
    switch self {
    case .general: return "general"
    case .charging: return "charging"
    case .schedules: return "schedules"
    case .tools: return "tools"
    case .energy: return "energy"
    case .statistics: return "statistics"
    case .diagnostics: return "diagnostics"
    case .setup: return "setup"
    }
  }
  var symbol: String {
    switch self {
    case .general: return "gearshape"
    case .charging: return "battery.75percent"
    case .schedules: return "calendar"
    case .tools: return "wrench.and.screwdriver"
    case .energy: return "leaf"
    case .statistics: return "chart.xyaxis.line"
    case .diagnostics: return "stethoscope"
    case .setup: return "checkmark.shield"
    }
  }
}

/// Settings apply automatically after a short pause; there is no separate save step.
struct SettingsView: View {
  @ObservedObject var settings: SettingsModel
  @ObservedObject var coordinator: ChargeCoordinator
  @ObservedObject var navigation: SettingsNavigation
  let history: HistoryStore
  let historyLoadFailed: Bool
  @ViewState private var notificationError = false
  @ViewState private var showTutorial = false
  @ViewState private var pendingSave: Task<Void, Never>?
  var body: some View {
    NavigationSplitView {
      List(SettingsPane.allCases, selection: selection) { pane in
        Label(localized(pane.titleKey), systemImage: pane.symbol).tag(pane)
      }
      .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
    } detail: {
      VStack(spacing: 0) {
        detail(navigation.pane)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        statusBar
      }
      .navigationTitle(localized(navigation.pane.titleKey))
    }
    .frame(minWidth: 760, minHeight: 560)
    .onAppear { showTutorial = settings.value.tutorialVersion != 1 }
    .onChange(of: settings.value) { _ in scheduleSave() }
    .sheet(isPresented: $showTutorial) {
      TutorialView { setup in
        settings.value.tutorialVersion = 1
        settings.value.onboardingComplete = true
        guard settings.commit(to: coordinator) else { return false }
        navigation.pane = setup ? .setup : .general
        showTutorial = false
        return true
      }
    }
  }
  private var selection: Binding<SettingsPane?> {
    Binding(get: { navigation.pane }, set: { if let value = $0 { navigation.pane = value } })
  }
  @ViewBuilder private func detail(_ pane: SettingsPane) -> some View {
    switch pane {
    case .general: general
    case .charging: charging
    case .schedules: ScheduleView(settings: settings, coordinator: coordinator)
    case .tools: WorkflowView(coordinator: coordinator)
    case .energy: EnergyView(settings: settings, coordinator: coordinator)
    case .statistics:
      StatisticsView(coordinator: coordinator, history: history, loadFailed: historyLoadFailed)
    case .diagnostics: DiagnosticsView(coordinator: coordinator, settings: settings)
    case .setup: SetupView(settings: settings, coordinator: coordinator)
    }
  }
  private var statusBar: some View {
    HStack(spacing: 6) {
      if let error = settings.error ?? coordinator.lastError ?? coordinator.helperError {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.thermal)
        Text(localized("error.\(error.rawValue)")).foregroundStyle(Palette.thermal)
      } else {
        Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
        Text(localized("autosave_note")).foregroundStyle(.secondary)
      }
      Spacer()
      Text("Battune \(BattuneVersion.current)").foregroundStyle(.tertiary)
    }
    .font(.caption)
    .padding(.horizontal, 16).padding(.vertical, 8)
    .background(.bar)
  }
  private func scheduleSave() {
    pendingSave?.cancel()
    pendingSave = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 600_000_000)
      guard !Task.isCancelled else { return }
      settings.commit(to: coordinator)
    }
  }
  private var general: some View {
    Form {
      Section(localized("menu_bar")) {
        Picker(
          localized("menu_bar_detail"),
          selection: Binding(
            get: { settings.value.effectiveMenuBarDetail },
            set: {
              settings.value.menuBarDetail = $0
              settings.value.showPercentage = $0 == .percentage
            })
        ) {
          ForEach(MenuBarDetail.allCases, id: \.self) { detail in
            Text(localized("menu_detail.\(detail.rawValue)")).tag(detail)
          }
        }
        Toggle(
          localized("launch_login"),
          isOn: Binding(get: { settings.loginEnabled }, set: { settings.setLogin($0) }))
      }
      Section(localized("notifications_section")) {
        Toggle(localized("notifications"), isOn: $settings.value.notificationsEnabled).onChange(
          of: settings.value.notificationsEnabled
        ) { enabled in
          guard enabled else { return }
          UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
            Task { @MainActor in
              if !granted {
                settings.value.notificationsEnabled = false
                notificationError = true
              }
            }
          }
        }
        if notificationError {
          Text(localized("notification_denied")).font(.caption).foregroundStyle(.secondary)
        }
        Toggle(localized("record_history"), isOn: $settings.value.statisticsEnabled)
      }
      Section(localized("language")) {
        Picker(localized("language"), selection: $settings.value.language) {
          Text(localized("system_language")).tag("system")
          Text("English").tag("en")
          Text("Deutsch").tag("de")
        }
        Text(localized("language_restart")).font(.caption).foregroundStyle(.secondary)
      }
      Section {
        Button(localized("tour_replay")) { showTutorial = true }
        Text(localized("privacy_note")).font(.callout).foregroundStyle(.secondary)
        Text(localized("automation_note")).font(.caption).foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
    }.formStyle(.grouped)
  }
  private var nativeSteps: [Int]? {
    settings.value.advancedControl == true ? nil : coordinator.capabilities.nativeChargeLimits
  }
  private var charging: some View {
    Form {
      Section {
        Toggle(localized("enable_control"), isOn: $settings.value.controlEnabled)
          .disabled(!settings.value.onboardingComplete || !coordinator.capabilities.canControl)
        if !coordinator.capabilities.canControl {
          Text(localized("unsupported_detail")).font(.callout).foregroundStyle(.secondary)
        }
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Text(localized("charge_limit"))
            Spacer()
            Text("\(settings.value.charge.limit)%").monospacedDigit().foregroundStyle(.secondary)
          }
          LimitPicker(
            limit: $settings.value.charge.limit, supported: nativeSteps,
            range: (settings.value.charge.sailing ? 21 : 20)...100
          ) {}
        }
        .onChange(of: settings.value.charge.limit) { limit in
          settings.value.charge.lower = min(settings.value.charge.lower, max(20, limit - 1))
        }
        Toggle(
          localized("keep_limit_on_quit"),
          isOn: Binding(
            get: { settings.value.keepsLimitOnQuit },
            set: { settings.value.keepLimitOnQuit = $0 }))
        if let limit = coordinator.helper?.confirmedLimit,
          coordinator.capabilities.nativeChargeLimits != nil
        {
          LabeledContent(localized("confirmed_limit"), value: "\(limit)%")
        }
      } footer: {
        Text(
          localized(
            settings.value.advancedControl == true
              ? "automatic_limit_routing" : "native_control_detail")
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      if coordinator.capabilities.adapterControl == true
        || coordinator.capabilities.nativeChargeLimits == nil
      {
        Section(localized("sailing")) {
          Toggle(localized("sailing"), isOn: $settings.value.charge.sailing)
            .disabled(settings.value.charge.limit <= 20)
          SettingsSlider(
            "lower_limit", value: $settings.value.charge.lower,
            in: 20...max(21, settings.value.charge.limit - 1)
          )
          .disabled(!settings.value.charge.sailing || settings.value.charge.limit <= 21)
          Text(localized("sailing_note")).font(.caption).foregroundStyle(.secondary)
        }
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
      if coordinator.capabilities.adapterControl == true {
        Section {
          Label(localized("adapter_limit_warning"), systemImage: "exclamationmark.triangle")
            .font(.callout).foregroundStyle(Palette.discharging)
        }
      }
    }.formStyle(.grouped)
  }
}

/// Shared navigation state so the popover can open a specific pane.
@MainActor final class SettingsNavigation: ObservableObject {
  @Published var pane: SettingsPane
  init(pane: SettingsPane) { self.pane = pane }
}
