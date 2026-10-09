import Foundation
import ServiceManagement
import BattuneDomain
import BattuneShared

public protocol HardwareClient: AnyObject {
    func status() async throws -> HelperStatus
    func perform(_ command: HardwareCommand) async throws
}
/// One-shot completion gate protects against timeout/error/reply races.
private final class ReplyGate<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var timeout: DispatchWorkItem?
    func arm(_ item: DispatchWorkItem) {
        lock.lock(); defer { lock.unlock() }
        if continuation == nil { item.cancel() } else { timeout = item }
    }
    init(_ continuation: CheckedContinuation<T, Error>) { self.continuation = continuation }
    func finish(_ result: Result<T, Error>) {
        lock.lock(); let pending = continuation; continuation = nil; timeout?.cancel(); timeout = nil; lock.unlock()
        pending?.resume(with: result)
    }
}
public final class HelperClient: HardwareClient {
    public init() {}
    private func request<T>(_ body: @escaping (BattuneHelperProtocol, @escaping (Result<T, Error>) -> Void) -> Void) async throws -> T {
        guard let team = SigningIdentity.teamIdentifier() else { throw BattuneError.unauthorized }
        return try await withCheckedThrowingContinuation { continuation in
            let gate = ReplyGate(continuation)
            let connection = NSXPCConnection(machServiceName: HelperIdentity.machService, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: BattuneHelperProtocol.self)
            connection.setCodeSigningRequirement(SigningIdentity.requirement(identifier: HelperIdentity.machService, team: team))
            connection.invalidationHandler = { gate.finish(.failure(BattuneError.helperUnavailable)) }
            connection.interruptionHandler = { gate.finish(.failure(BattuneError.helperUnavailable)); connection.invalidate() }
            connection.resume()
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in gate.finish(.failure(BattuneError.helperUnavailable)); connection.invalidate() }) as? BattuneHelperProtocol else {
                gate.finish(.failure(BattuneError.protocolMismatch)); connection.invalidate(); return
            }
            body(proxy) { result in gate.finish(result); connection.invalidate() }
            let timeout = DispatchWorkItem {
                gate.finish(.failure(BattuneError.helperUnavailable)); connection.invalidate()
            }
            gate.arm(timeout)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: timeout)
        }
    }
    public func status() async throws -> HelperStatus {
        try await request { proxy, finish in
            proxy.getStatus { data, code in finish(Result { try HelperReply.decode(HelperStatus.self, data: data, code: code) }) }
        }
    }
    public func perform(_ command: HardwareCommand) async throws {
        try await request { proxy, finish in
            let reply: (Int) -> Void = { code in finish(code == 0 ? .success(()) : .failure(BattuneError(rawValue: code) ?? .hardwareError)) }
            switch command {
            case .limit(let percent): proxy.setChargeLimit(percent, reply: reply)
            case .charging(let enabled): proxy.setChargingEnabled(enabled, reply: reply)
            case .discharge(let enabled): proxy.setDischargeEnabled(enabled, reply: reply)
            case .reset: proxy.resetChargingState(reply: reply)
            }
        }
    }
    public static func register() throws { try SMAppService.daemon(plistName: HelperIdentity.daemonPlist).register() }
    public static func unregister() async throws { try await SMAppService.daemon(plistName: HelperIdentity.daemonPlist).unregister() }
    public static var registrationStatus: SMAppService.Status { SMAppService.daemon(plistName: HelperIdentity.daemonPlist).status }
}
