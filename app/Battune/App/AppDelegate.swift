import AppKit
import SwiftUI
import Combine
import UserNotifications
import BattuneDomain
import BattuneSystem
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var monitor: PowerMonitor?
    private let settings = SettingsModel()
    private let history = HistoryStore(url: HistoryStore.defaultURL)
    private var coordinator: ChargeCoordinator?
    private var subscriptions = Set<AnyCancellable>()
    func applicationDidFinishLaunching(_ notification: Notification) {
        do { try history.load() } catch { /* History failure is reported in the statistics window through load status. */ historyLoadFailed = true }
        let coordinator = ChargeCoordinator(settings: settings.value, store: settings.store, history: history)
        self.coordinator = coordinator
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.target = self; item.button?.action = #selector(togglePopover)
        item.button?.image = NSImage(systemSymbolName: "battery.100percent", accessibilityDescription: "Battune")
        item.button?.imagePosition = .imageLeading
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(settings: settings, coordinator: coordinator, openSettings: { [weak self] in self?.showSettings() }))
        coordinator.$snapshot.combineLatest(settings.$value).sink { [weak self] snapshot, value in
            self?.statusItem?.button?.title = value.showPercentage ? " \(snapshot.percentage.map { "\($0)%" } ?? "—")" : ""
            self?.statusItem?.button?.toolTip = "Battune · \(L(coordinator.mode.localizationKey))"
        }.store(in: &subscriptions)
        coordinator.$mode.removeDuplicates().dropFirst().sink { [weak self] mode in
            guard self?.settings.value.notificationsEnabled == true, mode == .thermalHold || mode == .unavailable else { return }
            let content = UNMutableNotificationContent(); content.title = "Battune"; content.body = L(mode.localizationKey)
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "control-state", content: content, trigger: nil))
        }.store(in: &subscriptions)
        monitor = PowerMonitor(change: { coordinator.refresh() }, sleep: { coordinator.willSleep() }, wake: { coordinator.didWake() })
        monitor?.start(); coordinator.refresh()
        if !settings.value.onboardingComplete { showSettings() }
    }
    private var historyLoadFailed = false
    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = statusItem?.button { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }
    private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil, let coordinator {
            let root = SettingsView(settings: settings, coordinator: coordinator, history: history, historyLoadFailed: historyLoadFailed)
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = "Battune — \(L("settings"))"; window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 680, height: 600)); window.center(); window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        monitor?.stop()
        Task { await coordinator?.shutdown(); NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
