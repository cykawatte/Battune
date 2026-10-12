import AppKit
import IOKit.ps

@MainActor public final class PowerMonitor {
  private var source: CFRunLoopSource?
  private var timer: Timer?
  private var observers: [NSObjectProtocol] = []
  private let change: () -> Void
  private let sleep: () -> Void
  private let wake: () -> Void
  public init(change: @escaping () -> Void, sleep: @escaping () -> Void, wake: @escaping () -> Void)
  {
    self.change = change
    self.sleep = sleep
    self.wake = wake
  }
  public func start() {
    let callback: IOPowerSourceCallbackType = { context in
      guard let context else { return }
      let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
      // IOPS source is installed on the main run loop.
      MainActor.assumeIsolated { monitor.change() }
    }
    source = IOPSNotificationCreateRunLoopSource(
      callback, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
    if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
    startTimer()
    let center = NSWorkspace.shared.notificationCenter
    observers.append(
      center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
        [weak self] _ in
        MainActor.assumeIsolated {
          self?.timer?.invalidate()
          self?.timer = nil
          self?.sleep()
        }
      })
    observers.append(
      center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
        [weak self] _ in
        MainActor.assumeIsolated {
          self?.startTimer()
          self?.wake()
        }
      })
    for name in [
      NSNotification.Name.NSSystemTimeZoneDidChange, NSNotification.Name.NSSystemClockDidChange,
    ] {
      observers.append(
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
          [weak self] _ in
          MainActor.assumeIsolated { self?.change() }
        })
    }
  }
  private func startTimer() {
    timer?.invalidate()
    let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.change() }
    }
    timer.tolerance = 15
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }
  public func stop() {
    timer?.invalidate()
    timer = nil
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    source = nil
    for observer in observers {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      NotificationCenter.default.removeObserver(observer)
    }
    observers = []
  }
}
