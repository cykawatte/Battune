import AppKit
import BattuneDomain
import BattuneSystem
import Combine
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
  private var statusItem: NSStatusItem?
  private let popover = NSPopover()
  private var settingsWindow: NSWindow?
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
    item.button?.image = NSImage(
      systemSymbolName: "battery.100percent", accessibilityDescription: "Battune")
    item.button?.imagePosition = .imageLeading
    popover.behavior = .transient
    popover.delegate = self
    coordinator.$snapshot.combineLatest(coordinator.$mode, settings.$value).sink {
      [weak self] snapshot, mode, value in
      self?.statusItem?.button?.title =
        value.showPercentage ? " \(snapshot.percentage.map { "\($0)%" } ?? "—")" : ""
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
    monitor = PowerMonitor(
      change: { coordinator.refresh() }, sleep: { coordinator.willSleep() },
      wake: { coordinator.didWake() })
    monitor?.start()
    coordinator.refresh()
    if !settings.value.onboardingComplete || diagnosticLaunch { showSettings() }
  }
  private var historyLoadFailed = false
  @objc private func togglePopover() {
    if popover.isShown {
      popover.performClose(nil)
    } else if let button = statusItem?.button, let coordinator {
      popover.contentViewController = NSHostingController(
        rootView: PopoverView(
          settings: settings, coordinator: coordinator,
          openSettings: { [weak self] in self?.showSettings() }))
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
  }
  @objc private func showSettings() {
    popover.performClose(nil)
    if settingsWindow == nil, let coordinator {
      let root = SettingsView(
        settings: settings, coordinator: coordinator, history: history,
        historyLoadFailed: historyLoadFailed, initialTab: diagnosticLaunch ? 5 : 0)
      let window = NSWindow(contentViewController: NSHostingController(rootView: root))
      window.title = "Battune — \(localized("settings"))"
      window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
      window.setContentSize(NSSize(width: 680, height: 600))
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
  func popoverDidClose(_ notification: Notification) { popover.contentViewController = nil }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    monitor?.stop()
    Task {
      await coordinator?.shutdown()
      NSApp.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}
