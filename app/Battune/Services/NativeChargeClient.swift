import BattuneDomain
import CNativeCharge
import Darwin
import Foundation

public struct NativeChargeState: Codable, Equatable, Sendable {
  public var limit: Int
  public var enabled: Bool
  public var limits: [Int]
  public var effectiveLimit: Int { enabled ? limit : 100 }
  public init(limit: Int, enabled: Bool, limits: [Int]) {
    self.limit = limit
    self.enabled = enabled
    self.limits = limits
  }
}

public protocol NativeChargeTransport: AnyObject {
  func read() throws -> NativeChargeState
  func setLimit(_ limit: Int) throws
  func disable() throws
}

/// Only the Apple charge-limit API is exposed; no raw SMC or arbitrary IPC access.
public final class SystemNativeChargeTransport: NativeChargeTransport {
  public init() {}
  public func read() throws -> NativeChargeState {
    var limit: Int32 = 0
    var enabled: Int32 = 0
    var count: Int32 = 0
    var limits = [Int32](repeating: 0, count: 32)
    try check(bt_native_read(&limit, &enabled, &limits, 32, &count))
    guard (1...32).contains(count) else { throw BattuneError.protocolMismatch }
    return NativeChargeState(
      limit: Int(limit), enabled: enabled == 1,
      limits: Array(Set(limits.prefix(Int(count)).map(Int.init) + [100])).sorted())
  }
  public func setLimit(_ limit: Int) throws {
    guard (20...100).contains(limit) else { throw BattuneError.invalidConfiguration }
    try check(bt_native_set(Int32(limit)))
  }
  public func disable() throws { try check(bt_native_disable()) }
  private func check(_ code: Int32) throws {
    guard code == 0 else { throw BattuneError(rawValue: Int(code)) ?? .hardwareError }
  }
}

/// Durable ownership record: reset restores the user's previous macOS setting,
/// not an assumed 100%. It survives app crashes, and never restores unowned state.
public final class NativeChargeSession {
  private struct Journal: Codable {
    let original: NativeChargeState
    var expected: Int
  }
  private let transport: NativeChargeTransport
  private let journalURL: URL
  public static var defaultJournalURL: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Application Support/Battune/native-charge-session.json")
  }
  public init(
    transport: NativeChargeTransport = SystemNativeChargeTransport(),
    journalURL: URL = NativeChargeSession.defaultJournalURL
  ) {
    self.transport = transport
    self.journalURL = journalURL
  }
  public func read() throws -> NativeChargeState {
    let state = try transport.read()
    guard (20...100).contains(state.limit), !state.limits.isEmpty,
      state.limits.allSatisfy({ (20...100).contains($0) }), state.limits.contains(100)
    else { throw BattuneError.protocolMismatch }
    return state
  }
  public func perform(_ command: HardwareCommand) throws {
    try withFileLock {
      switch command {
      case .limit(let limit):
        let current = try read()
        guard current.limits.contains(limit) else { throw BattuneError.unsupported }
        let previous = try loadJournal()
        if current.effectiveLimit == limit { return }
        let journal = Journal(original: previous?.original ?? current, expected: limit)
        // Persist before the first mutation, including failure/termination windows.
        try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
        try FileManager.default.setAttributes(
          [.posixPermissions: 0o600], ofItemAtPath: journalURL.path)
        do {
          try transport.setLimit(limit)
          guard try read().effectiveLimit == limit else { throw BattuneError.hardwareError }
        } catch {
          // Keep the journal if recovery fails; the next explicit retry can restore it.
          try? restore(journal, onlyIfOwned: false)
          throw error
        }
      case .reset:
        if let journal = try loadJournal() { try restore(journal, onlyIfOwned: true) }
      case .charging, .discharge:
        throw BattuneError.unsupported
      }
    }
  }
  private func loadJournal() throws -> Journal? {
    guard FileManager.default.fileExists(atPath: journalURL.path) else { return nil }
    do {
      let value = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
      guard (20...100).contains(value.original.limit), (20...100).contains(value.expected) else {
        throw BattuneError.corruptPersistence
      }
      return value
    } catch { throw BattuneError.corruptPersistence }
  }
  private func restore(_ journal: Journal, onlyIfOwned: Bool) throws {
    let current = try read()
    if !onlyIfOwned || current.effectiveLimit == journal.expected {
      // 100% is normalized by macOS to a disabled limit.
      try transport.setLimit(journal.original.limit)
      if !journal.original.enabled { try transport.disable() }
      guard try read().effectiveLimit == journal.original.effectiveLimit else {
        throw BattuneError.hardwareError
      }
    }
    try FileManager.default.removeItem(at: journalURL)
  }
  private func withFileLock(_ body: () throws -> Void) throws {
    try FileManager.default.createDirectory(
      at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let fd = open(journalURL.path + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
    guard fd >= 0 else { throw BattuneError.corruptPersistence }
    defer { close(fd) }
    guard flock(fd, LOCK_EX) == 0 else { throw BattuneError.corruptPersistence }
    defer { _ = flock(fd, LOCK_UN) }
    try body()
  }
}

/// Uses Apple's own authenticated power service in the logged-in user session.
/// Synchronous platform calls execute off the main thread, in a serial queue.
public final class NativeChargeClient: HardwareClient {
  private let session: NativeChargeSession
  private let timeout: TimeInterval
  private let queue = DispatchQueue(label: "org.battune.native-charge", qos: .utility)
  public init(session: NativeChargeSession = NativeChargeSession(), timeout: TimeInterval = 5) {
    self.session = session
    self.timeout = max(0.01, timeout)
  }
  private func request<T>(_ body: @escaping () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
      let gate = ReplyGate(continuation)
      let deadline = DispatchWorkItem { gate.finish(.failure(BattuneError.hardwareError)) }
      gate.arm(deadline)
      DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: deadline)
      queue.async {
        guard gate.isPending else { return }
        gate.finish(Result { try body() })
      }
    }
  }
  public func status() async throws -> HelperStatus {
    try await request { [self] in
      let state = try session.read()
      return HelperStatus(
        backend: "macOS native charge limit / PowerUI",
        capabilities: Capabilities(
          readBattery: true, setLimit: true, reset: true, nativeChargeLimits: state.limits),
        confirmedLimit: state.effectiveLimit)
    }
  }
  public func perform(_ command: HardwareCommand) async throws {
    try await request { [self] in try session.perform(command) }
  }
  public func renewLease() async throws {
    // The firmware enforces the upper limit, including during sleep. It needs no
    // process heartbeat and never forces discharge or disables thermal protection.
  }
}

/// Controller transitions are explicit and restore the previous controller first.
public actor PlatformHardwareClient: HardwareClient {
  private let native: HardwareClient
  private let helper: HardwareClient
  private var selected: HardwareClient?
  private var advanced = false
  public init(
    native: HardwareClient = NativeChargeClient(), helper: HardwareClient = HelperClient()
  ) {
    self.native = native
    self.helper = helper
  }
  public func configureAdvanced(_ enabled: Bool) async throws {
    guard enabled != advanced else { return }
    if let selected { try await selected.perform(.reset) }
    if advanced { try await native.perform(.reset) }
    advanced = enabled
    selected = enabled ? helper : native
  }
  public func validateAdvanced() async throws { try await helper.validateAdvanced() }
  public func hardwareSnapshot() async throws -> BatterySnapshot? {
    guard advanced else { return nil }
    return try await helper.hardwareSnapshot()
  }
  public func status() async throws -> HelperStatus {
    if let selected { return try await selected.status() }
    do {
      let status = try await native.status()
      selected = native
      return status
    } catch BattuneError.unsupported {
      let status = try await helper.status()
      selected = helper
      return status
    }
  }
  public func perform(_ command: HardwareCommand) async throws {
    guard let selected else { throw BattuneError.helperUnavailable }
    if advanced, command != .reset {
      // Native limits must not prevent the recharge phase. Preserve them in the
      // native ownership journal and restore when leaving advanced mode.
      do { try await native.perform(.limit(100)) } catch BattuneError.unsupported {
        // Older macOS versions have no native limit to release. Permission,
        // corruption and communication errors still abort the transition.
      }
    }
    try await selected.perform(command)
    if advanced, command == .reset { try await native.perform(.reset) }
  }
  public func renewLease() async throws {
    guard let selected else { throw BattuneError.helperUnavailable }
    try await selected.renewLease()
  }
}
