import Foundation
import IOKit.pwr_mgt

final class HelperSleepGuard {
  private let adapter: AdapterBackend?
  private var port: IONotificationPortRef?
  private var root: io_connect_t = 0
  private var notifier: io_object_t = 0
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
  }
}
