import AppKit
import SwiftUI

/// Owns transient presentation and installs mouse monitors only while visible.
@MainActor final class MenuBarPopover: NSObject, NSPopoverDelegate {
  private let popover = NSPopover()
  private weak var anchor: NSView?
  private var localMonitor: Any?
  private var globalMonitor: Any?
  private var resignationObserver: NSObjectProtocol?

  override init() {
    super.init()
    popover.behavior = .transient
    popover.animates = false
    popover.delegate = self
  }

  func toggle<Content: View>(from button: NSView, content: () -> Content) {
    if popover.isShown {
      close()
      return
    }
    anchor = button
    let hosting = NSHostingController(rootView: content())
    // Measure before anchoring. A hosting view's initial frame can be much taller
    // than its eventual SwiftUI content, pushing the header behind the menu bar.
    hosting.sizingOptions = [.preferredContentSize]
    let measured = hosting.sizeThatFits(in: NSSize(width: 340, height: 800))
    let size = NSSize(width: ceil(measured.width), height: ceil(measured.height))
    hosting.preferredContentSize = size
    hosting.view.setFrameSize(size)
    hosting.view.layoutSubtreeIfNeeded()
    popover.contentViewController = hosting
    popover.contentSize = size
    NSApp.activate(ignoringOtherApps: true)
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    hosting.view.window?.makeKey()
    monitorDismissal()
  }

  func close() {
    removeMonitors()
    popover.performClose(nil)
  }

  private func monitorDismissal() {
    removeMonitors()
    // Mouse events need no Accessibility permission. Do not observe global keys.
    let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
      MainActor.assumeIsolated { self?.close() }
    }
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown)) {
      [weak self] event in
      let consume = MainActor.assumeIsolated {
        guard let self else { return false }
        if event.type == .keyDown {
          if event.keyCode == 53 {
            self.close()
            return true
          }
        } else if event.window !== self.popover.contentViewController?.view.window,
          event.window !== self.anchor?.window
        {
          self.close()
        }
        return false
      }
      return consume ? nil : event
    }
    resignationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.close() }
    }
  }

  private func removeMonitors() {
    if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    if let resignationObserver { NotificationCenter.default.removeObserver(resignationObserver) }
    localMonitor = nil
    globalMonitor = nil
    resignationObserver = nil
  }

  func popoverDidClose(_ notification: Notification) {
    removeMonitors()
    popover.contentViewController = nil
    anchor = nil
  }
}
