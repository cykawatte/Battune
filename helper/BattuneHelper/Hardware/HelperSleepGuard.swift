import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt

/// Restores adapter input before sleep and as soon as the lid closes or power
/// changes. Events replace polling: a closed lid with cut AC input can suspend a
/// docked Mac, so the reaction must not wait for the next watchdog tick.
final class HelperSleepGuard {
  private let adapter: AdapterBackend?
  private var port: IONotificationPortRef?
  private var root: io_connect_t = 0
  private var notifier: io_object_t = 0
  private var lidPort: IONotificationPortRef?
  private var lidNotification: io_object_t = 0
  private var powerSource: CFRunLoopSource?
  init(adapter: AdapterBackend?) { self.adapter = adapter }
  func start() {
    root = IORegisterForSystemPower(
      Unmanaged.passUnretained(self).toOpaque(), &port,
      { context, _, type, argument in
        guard let context else { return }
        let owner = Unmanaged<HelperSleepGuard>.fromOpaque(context).takeUnretainedValue()
        if type == 0xe000_0280 || type == 0xe000_0270 {
          if type == 0xe000_0280 { owner.adapter?.prepareForSleep() }
          IOAllowPowerChange(owner.root, Int(bitPattern: argument))
        }
      }, &notifier)
    if root != 0, let port,
      let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue()
    {
      CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
      adapter?.setSleepProtectionReady(true)
    }
    guard adapter != nil else { return }
    observeLid()
    let callback: IOPowerSourceCallbackType = { context in
      guard let context else { return }
      Unmanaged<HelperSleepGuard>.fromOpaque(context).takeUnretainedValue().adapter?.safetyCheck()
    }
    powerSource = IOPSNotificationCreateRunLoopSource(
      callback, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
    if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
  }
  private func observeLid() {
    let domain = IOServiceGetMatchingService(
      kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard domain != IO_OBJECT_NULL else { return }
    defer { IOObjectRelease(domain) }
    guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
    let callback: IOServiceInterestCallback = { context, _, message, _ in
      // kIOPMMessageClamshellStateChange
      guard let context, message == 0xe003_4100 else { return }
      Unmanaged<HelperSleepGuard>.fromOpaque(context).takeUnretainedValue().adapter?.safetyCheck()
    }
    let result = IOServiceAddInterestNotification(
      port, domain, kIOGeneralInterest, callback, Unmanaged.passUnretained(self).toOpaque(),
      &lidNotification)
    guard result == KERN_SUCCESS,
      let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue()
    else {
      IONotificationPortDestroy(port)
      return
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    lidPort = port
  }
}
