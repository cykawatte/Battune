import AppKit
import IOKit
import IOKit.ps

/// Event-driven power observation. Power-source, lid, sleep and clock changes wake
/// the coordinator immediately; the periodic timer is only a coarse fallback whose
/// interval the coordinator adapts to the active control path.
@MainActor public final class PowerMonitor {
  private var source: CFRunLoopSource?
  private var timer: Timer?
  private var deadline: Timer?
  private var interval: TimeInterval = 60
  private var observers: [NSObjectProtocol] = []
  private var notificationPort: IONotificationPortRef?
  private var lidNotification: io_object_t = 0
  private var asleep = false
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
    observeLid()
    startTimer()
    let center = NSWorkspace.shared.notificationCenter
    observers.append(
      center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
        [weak self] _ in
        MainActor.assumeIsolated {
          self?.asleep = true
          self?.timer?.invalidate()
          self?.timer = nil
          self?.deadline?.invalidate()
          self?.deadline = nil
          self?.sleep()
        }
      })
    observers.append(
      center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
        [weak self] _ in
        MainActor.assumeIsolated {
          self?.asleep = false
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
  /// Changes the fallback interval. Tolerance lets macOS coalesce wakeups.
  public func setInterval(_ value: TimeInterval) {
    let value = min(900, max(30, value))
    guard value != interval else { return }
    interval = value
    if timer != nil { startTimer() }
  }
  /// One extra wakeup at an exact time, e.g. the next schedule activation.
  public func wake(at date: Date?) {
    deadline?.invalidate()
    deadline = nil
    guard let date, !asleep, date.timeIntervalSinceNow < interval else { return }
    let timer = Timer(fire: max(date, Date().addingTimeInterval(1)), interval: 0, repeats: false) {
      [weak self] _ in
      MainActor.assumeIsolated {
        self?.deadline = nil
        self?.change()
      }
    }
    timer.tolerance = 1
    RunLoop.main.add(timer, forMode: .common)
    deadline = timer
  }
  private func startTimer() {
    timer?.invalidate()
    let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.change() }
    }
    timer.tolerance = interval / 4
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }
  /// IOPMrootDomain announces lid changes without polling or extra privileges.
  private func observeLid() {
    let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard root != IO_OBJECT_NULL else { return }
    defer { IOObjectRelease(root) }
    guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
    let callback: IOServiceInterestCallback = { context, _, message, _ in
      // kIOPMMessageClamshellStateChange
      guard let context, message == 0xe003_4100 else { return }
      let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
      MainActor.assumeIsolated { monitor.change() }
    }
    let result = IOServiceAddInterestNotification(
      port, root, kIOGeneralInterest, callback, Unmanaged.passUnretained(self).toOpaque(),
      &lidNotification)
    guard result == KERN_SUCCESS,
      let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue()
    else {
      IONotificationPortDestroy(port)
      return
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    notificationPort = port
  }
  public func stop() {
    timer?.invalidate()
    timer = nil
    deadline?.invalidate()
    deadline = nil
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    source = nil
    if lidNotification != 0 {
      IOObjectRelease(lidNotification)
      lidNotification = 0
    }
    if let notificationPort { IONotificationPortDestroy(notificationPort) }
    notificationPort = nil
    for observer in observers {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      NotificationCenter.default.removeObserver(observer)
    }
    observers = []
  }
}
