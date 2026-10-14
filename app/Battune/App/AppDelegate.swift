import AppKit
import BattuneDomain
import BattuneSystem
import Combine
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private var statusItem: NSStatusItem?
  private let popover = MenuBarPopover()
  private var settingsWindow: NSWindow?
  private let navigation = SettingsNavigation(pane: .general)
  private var monitor: PowerMonitor?
  private let settings = SettingsModel()
  private let history = HistoryStore(url: HistoryStore.defaultURL)
  private var coordinator: ChargeCoordinator?
  private var subscriptions = Set<AnyCancellable>()
  private var diagnosticLaunch: Bool {
    #if DEBUG
      return CommandLine.arguments.contains("--diagnostics")
    #else
      return false
    #endif
  }
  func applicationDidFinishLaunching(_ notification: Notification) {
    do { try history.load() } catch {  // History failure is reported in the statistics window.
      historyLoadFailed = true
    }
    let mainMenu = NSMenu()
    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    let appMenu = NSMenu()
    appMenuItem.submenu = appMenu
    let preferences = NSMenuItem(
      title: localized("settings"), action: #selector(showSettings), keyEquivalent: ",")
    preferences.target = self
    appMenu.addItem(preferences)
    #if DEBUG
      if diagnosticLaunch {
        let preview = NSMenuItem(
          title: "Show Menu Bar Panel", action: #selector(togglePopover), keyEquivalent: "p")
        preview.keyEquivalentModifierMask = [.command, .shift]
        preview.target = self
        appMenu.addItem(preview)
      }
    #endif
    appMenu.addItem(.separator())
    let quit = NSMenuItem(
      title: localized("quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    quit.target = NSApp
    appMenu.addItem(quit)
    NSApp.mainMenu = mainMenu
    let coordinator = ChargeCoordinator(
      settings: settings.value, store: settings.store, history: history)
    self.coordinator = coordinator
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem = item
    item.button?.target = self
    item.button?.action = #selector(togglePopover)
    item.button?.image = BattuneMark.menuBarImage
    item.button?.imagePosition = .imageLeading
    coordinator.$snapshot.combineLatest(coordinator.$mode, settings.$value).sink {
      [weak self] snapshot, mode, value in
      let title = Self.menuBarText(snapshot, detail: value.effectiveMenuBarDetail)
      // Avoid relayout of the status item when nothing visible changed.
      if self?.statusItem?.button?.title != title { self?.statusItem?.button?.title = title }
      self?.statusItem?.button?.toolTip = "Battune · \(localized(mode.localizationKey))"
    }.store(in: &subscriptions)
    coordinator.$mode.removeDuplicates().dropFirst().sink { [weak self] mode in
      guard self?.settings.value.notificationsEnabled == true,
        mode == .thermalHold || mode == .unavailable
      else { return }
      let content = UNMutableNotificationContent()
      content.title = "Battune"
      content.body = localized(mode.localizationKey)
      UNUserNotificationCenter.current().add(
        UNNotificationRequest(identifier: "control-state", content: content, trigger: nil))
    }.store(in: &subscriptions)
    let monitor = PowerMonitor(
      change: { coordinator.refresh() }, sleep: { coordinator.willSleep() },
      wake: { coordinator.didWake() })
    self.monitor = monitor
    coordinator.timing = { [weak monitor] interval, next in
      monitor?.setInterval(interval)
      monitor?.wake(at: next)
    }
    monitor.start()
    coordinator.refresh()
    #if DEBUG
      if let index = CommandLine.arguments.firstIndex(of: "--render-ui"),
        CommandLine.arguments.indices.contains(index + 1)
      {
        renderInterface(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        return
      }
    #endif
    if !settings.value.onboardingComplete || settings.value.setupComplete != true
      || settings.value.tutorialVersion != 1 || diagnosticLaunch
    {
      navigation.pane = settings.value.setupComplete == true ? .general : .setup
      showSettings()
    }
  }
  private var historyLoadFailed = false
  #if DEBUG
    /// Developer aid: renders the popover and every settings pane with live data
    /// to PNG files (light and dark), then quits. Never compiled into Release.
    private func renderInterface(to directory: URL) {
      guard let coordinator else { return }
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
          let popover = PopoverView(settings: settings, coordinator: coordinator) { _ in }
          render(
            popover, width: 340, appearance: appearance, to: directory, name: "popover-\(name)")
          for pane in SettingsPane.allCases {
            navigation.pane = pane
            let view = SettingsView(
              settings: settings, coordinator: coordinator, navigation: navigation,
              history: history, historyLoadFailed: historyLoadFailed)
            render(
              view.frame(width: 820, height: 620), width: 820, appearance: appearance,
              to: directory, name: "settings-\(pane.titleKey)-\(name)")
          }
        }
        exit(0)
      }
    }
    private func render<V: View>(
      _ view: V, width: CGFloat, appearance: NSAppearance.Name, to directory: URL, name: String
    ) {
      let dark = appearance == .darkAqua
      let host = NSHostingView(
        rootView: view.environment(\.colorScheme, dark ? .dark : .light)
          .background(
            Color(nsColor: dark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.96, alpha: 1))))
      host.appearance = NSAppearance(named: appearance)
      let window = NSWindow(
        contentRect: NSRect(x: -5000, y: -5000, width: width, height: 100),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.appearance = NSAppearance(named: appearance)
      window.contentView = host
      let size = host.fittingSize
      window.setContentSize(NSSize(width: width, height: max(100, size.height)))
      window.orderFrontRegardless()
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.4))
      guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
      host.cacheDisplay(in: host.bounds, to: rep)
      window.orderOut(nil)
      if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: directory.appendingPathComponent("\(name).png"))
      }
    }
  #endif
  static func menuBarText(_ snapshot: BatterySnapshot, detail: MenuBarDetail) -> String {
    switch detail {
    case .none: return ""
    case .percentage: return " \(snapshot.percentage.map { "\($0)%" } ?? "—")"
    case .power:
      let watts = snapshot.pluggedIn == true ? snapshot.adapterInput : snapshot.power.map(abs)
      return " \(watts.map { String(format: "%.1f W", $0) } ?? "—")"
    case .temperature:
      return " \(snapshot.temperature.map { String(format: "%.0f°", $0) } ?? "—")"
    case .time:
      if snapshot.charging == true, let minutes = snapshot.minutesToFull {
        return " \(minutes / 60):\(String(format: "%02d", minutes % 60))"
      }
      if snapshot.pluggedIn == false, let minutes = snapshot.minutesToEmpty {
        return " \(minutes / 60):\(String(format: "%02d", minutes % 60))"
      }
      return " \(snapshot.percentage.map { "\($0)%" } ?? "—")"
    }
  }
  /// Shortcuts and scripts: battune://limit/80, battune://top-up, battune://pause,
  /// battune://resume, battune://settings. Workflows that use battery power
  /// (discharge, calibration) deliberately require a confirmation in the app.
  func application(_ application: NSApplication, open urls: [URL]) {
    guard let coordinator else { return }
    for url in urls where url.scheme?.lowercased() == "battune" {
      let action = (url.host ?? "").lowercased()
      switch action {
      case "limit":
        let value =
          Int(url.lastPathComponent)
          ?? URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
          .first(where: { $0.name == "value" })?.value.flatMap(Int.init)
        guard let limit = value, coordinator.accepts(limit: limit) else {
          notify(localized("automation_rejected"))
          continue
        }
        settings.value.charge.limit = limit
        settings.value.charge.lower = min(settings.value.charge.lower, max(20, limit - 1))
        coordinator.resumePlan()
        settings.commit(to: coordinator)
      case "top-up", "topup": coordinator.topUp()
      case "pause": coordinator.pauseCharging()
      case "resume": coordinator.resumePlan()
      case "settings": showSettings()
      default: notify(localized("automation_rejected"))
      }
    }
  }
  private func notify(_ body: String) {
    guard settings.value.notificationsEnabled else { return }
    let content = UNMutableNotificationContent()
    content.title = "Battune"
    content.body = body
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: "automation", content: content, trigger: nil))
  }
  @objc private func togglePopover() {
    guard let button = statusItem?.button, let coordinator else { return }
    popover.toggle(from: button) {
      PopoverView(
        settings: settings, coordinator: coordinator,
        openSettings: { [weak self] pane in
          self?.navigation.pane = pane
          self?.showSettings()
        })
    }
  }
  @objc private func showSettings() {
    popover.close()
    if settingsWindow == nil, let coordinator {
      if diagnosticLaunch { navigation.pane = .diagnostics }
      let root = SettingsView(
        settings: settings, coordinator: coordinator, navigation: navigation, history: history,
        historyLoadFailed: historyLoadFailed)
      let window = NSWindow(contentViewController: NSHostingController(rootView: root))
      window.title = "Battune"
      window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
      window.toolbarStyle = .unified
      window.setContentSize(NSSize(width: 820, height: 620))
      window.center()
      window.isReleasedWhenClosed = false
      window.delegate = self
      settingsWindow = window
    }
    NSApp.activate(ignoringOtherApps: true)
    settingsWindow?.makeKeyAndOrderFront(nil)
  }
  func windowWillClose(_ notification: Notification) {
    settingsWindow?.contentViewController = nil
    settingsWindow = nil
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    popover.close()
    monitor?.stop()
    Task {
      await coordinator?.shutdown()
      NSApp.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}
