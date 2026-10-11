import BattuneDomain
import BattuneShared
import Foundation
import ServiceManagement

public protocol HardwareClient: AnyObject {
  func renewLease() async throws
  func configureAdvanced(_ enabled: Bool) async throws
  func validateAdvanced() async throws
  func hardwareSnapshot() async throws -> BatterySnapshot?
  func status() async throws -> HelperStatus
  func perform(_ command: HardwareCommand) async throws
}
extension HardwareClient {
  public func configureAdvanced(_ enabled: Bool) async throws {
    if enabled { throw BattuneError.unsupported }
  }
  public func validateAdvanced() async throws { throw BattuneError.unsupported }
  public func hardwareSnapshot() async throws -> BatterySnapshot? { nil }
}
/// One-shot completion gate protects against timeout/error/reply races.
final class ReplyGate<T>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<T, Error>?
  private var timeout: DispatchWorkItem?
  var isPending: Bool {
    lock.lock()
    defer { lock.unlock() }
    return continuation != nil
  }
  func arm(_ item: DispatchWorkItem) {
    lock.lock()
    defer { lock.unlock() }
    if continuation == nil { item.cancel() } else { timeout = item }
  }
  init(_ continuation: CheckedContinuation<T, Error>) { self.continuation = continuation }
  func finish(_ result: Result<T, Error>) {
    lock.lock()
    let pending = continuation
    continuation = nil
    timeout?.cancel()
    timeout = nil
    lock.unlock()
    pending?.resume(with: result)
  }
}
public final class HelperClient: HardwareClient {
  public init() {}
  private func request<T>(
    _ body: @escaping (BattuneHelperProtocol, @escaping (Result<T, Error>) -> Void) -> Void
  ) async throws -> T {
    guard let requirement = LocalInstallationTrust.peerRequirement(forHelper: true) else {
      throw BattuneError.unauthorized
    }
    return try await withCheckedThrowingContinuation { continuation in
      let gate = ReplyGate(continuation)
      let connection = NSXPCConnection(
        machServiceName: HelperIdentity.machService, options: .privileged)
      connection.remoteObjectInterface = NSXPCInterface(with: BattuneHelperProtocol.self)
      connection.setCodeSigningRequirement(requirement)
      connection.invalidationHandler = { gate.finish(.failure(BattuneError.helperUnavailable)) }
      connection.interruptionHandler = {
        gate.finish(.failure(BattuneError.helperUnavailable))
        connection.invalidate()
      }
      connection.resume()
      guard
        let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
          gate.finish(.failure(BattuneError.helperUnavailable))
          connection.invalidate()
        }) as? BattuneHelperProtocol
      else {
        gate.finish(.failure(BattuneError.protocolMismatch))
        connection.invalidate()
        return
      }
      body(proxy) { result in
        gate.finish(result)
        connection.invalidate()
      }
      let timeout = DispatchWorkItem {
        gate.finish(.failure(BattuneError.helperUnavailable))
        connection.invalidate()
      }
      gate.arm(timeout)
      DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: timeout)
    }
  }
  public func renewLease() async throws {
    try await request { proxy, finish in
      proxy.renewControlLease { code in
        finish(code == 0 ? .success(()) : .failure(BattuneError(rawValue: code) ?? .hardwareError))
      }
    }
  }
  public func status() async throws -> HelperStatus {
    try await request { proxy, finish in
      proxy.getStatus { data, code in
        finish(Result { try HelperReply.decode(HelperStatus.self, data: data, code: code) })
      }
    }
  }
  public func perform(_ command: HardwareCommand) async throws {
    try await request { proxy, finish in
      let reply: (Int) -> Void = { code in
        finish(code == 0 ? .success(()) : .failure(BattuneError(rawValue: code) ?? .hardwareError))
      }
      switch command {
      case .limit(let percent): proxy.setChargeLimit(percent, reply: reply)
      case .charging(let enabled): proxy.setChargingEnabled(enabled, reply: reply)
      case .discharge(let enabled): proxy.setDischargeEnabled(enabled, reply: reply)
      case .reset: proxy.resetChargingState(reply: reply)
      }
    }
  }
  public func validateAdvanced() async throws {
    try await request { proxy, finish in
      proxy.validateAdapterControl { code in
        finish(code == 0 ? .success(()) : .failure(BattuneError(rawValue: code) ?? .hardwareError))
      }
    }
  }
  public func hardwareSnapshot() async throws -> BatterySnapshot? {
    try await request { proxy, finish in
      proxy.getBatterySnapshot { data, code in
        finish(Result { try HelperReply.decode(BatterySnapshot.self, data: data, code: code) })
      }
    }
  }
  public static func register() throws {
    try SMAppService.daemon(plistName: HelperIdentity.daemonPlist).register()
  }
  public static func unregister() async throws {
    try await SMAppService.daemon(plistName: HelperIdentity.daemonPlist).unregister()
  }
  public static var registrationStatus: SMAppService.Status {
    SMAppService.daemon(plistName: HelperIdentity.daemonPlist).status
  }
}
