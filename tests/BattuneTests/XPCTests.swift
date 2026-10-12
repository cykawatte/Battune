import BattuneDomain
import BattuneHardware
import BattuneShared
import Foundation
import Security

// Deliberately test-only: anonymous unprivileged listener for wire-format tests.
private final class TestListener: NSObject, NSXPCListenerDelegate {
  let service: HelperService
  init(service: HelperService) { self.service = service }
  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection)
    -> Bool
  {
    connection.exportedInterface = NSXPCInterface(with: BattuneHelperProtocol.self)
    connection.exportedObject = service
    connection.resume()
    return true
  }
}
private final class XPCResult: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Int, Never>?
  init(_ continuation: CheckedContinuation<Int, Never>) { self.continuation = continuation }
  func finish(_ code: Int) {
    lock.lock()
    let pending = continuation
    continuation = nil
    lock.unlock()
    pending?.resume(returning: code)
  }
}
@MainActor final class XPCTests {
  func testProtocolRoundtrip() async throws {
    let mock = MockBackend()
    let service = HelperService(backend: mock, gate: HardwareGate(backend: mock))
    let delegate = TestListener(service: service)
    let listener = NSXPCListener.anonymous()
    listener.delegate = delegate
    listener.resume()
    defer {
      listener.invalidate()
      _ = delegate
    }
    let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
    connection.remoteObjectInterface = NSXPCInterface(with: BattuneHelperProtocol.self)
    connection.resume()
    defer { connection.invalidate() }
    let code = await withCheckedContinuation { continuation in
      let result = XPCResult(continuation)
      let timeout = DispatchWorkItem { result.finish(-1) }
      DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: timeout)
      guard
        let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
          result.finish(-2)
          timeout.cancel()
        }) as? BattuneHelperProtocol
      else {
        result.finish(-3)
        timeout.cancel()
        return
      }
      proxy.getStatus { data, code in
        do {
          let status = try HelperReply.decode(HelperStatus.self, data: data, code: code)
          guard status.backend == mock.name else {
            result.finish(-4)
            timeout.cancel()
            return
          }
          proxy.setChargeLimit(19) { validation in
            result.finish(validation)
            timeout.cancel()
          }
        } catch {
          result.finish(-5)
          timeout.cancel()
        }
      }
    }
    expectEqual(code, BattuneError.invalidConfiguration.rawValue)
    expectTrue(mock.commands.isEmpty)
  }
  func testLeaseExpiration() async throws {
    let mock = MockBackend()
    let gate = HardwareGate(backend: mock, leaseDuration: 0.02)
    try gate.perform(.charging(false))
    // Wait for the observable result, allowing CI timer scheduling latency.
    for _ in 0..<200 {
      if mock.commands.count == 2 { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    expectEqual(mock.commands, [.charging(false), .reset])
    try await Task.sleep(nanoseconds: 50_000_000)
    expectEqual(mock.commands.count, 2)
  }
  func testSigningRequirementSyntax() throws {
    let requirement = SigningIdentity.requirement(
      identifier: HelperIdentity.appIdentifier, team: "ABCDEFGHIJ")
    var parsed: SecRequirement?
    expectEqual(SecRequirementCreateWithString(requirement as CFString, [], &parsed), errSecSuccess)
    expectTrue(parsed != nil)
    if SigningIdentity.teamIdentifier() == nil {
      let listener = NSXPCListener.anonymous()
      let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
      expectFalse(ClientAuthenticator().configure(connection))
      connection.invalidate()
      listener.invalidate()
    }
  }
}
