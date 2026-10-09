import BattuneDomain
import Foundation

/// Serial execution; acknowledge only successful replies. Caller serializes evaluation.
@MainActor public final class CommandExecutor {
  private let client: HardwareClient
  private var generation = 0
  private var confirmed: [String: HardwareCommand] = [:]
  public private(set) var lastAction: HardwareCommand?
  public init(client: HardwareClient) { self.client = client }
  public func invalidate() {
    generation += 1
    confirmed = [:]
  }
  public func apply(_ commands: [HardwareCommand]) async throws {
    let currentGeneration = generation
    for command in commands {
      guard currentGeneration == generation else { throw CancellationError() }
      let key: String
      switch command {
      case .limit: key = "limit"
      case .charging: key = "charging"
      case .discharge: key = "discharge"
      case .reset: key = "reset"
      }
      if confirmed[key] == command { continue }
      do { try await client.perform(command) } catch {
        invalidate()
        throw error
      }
      guard currentGeneration == generation else { throw CancellationError() }
      if command == .reset {
        confirmed = ["reset": .reset]
      } else {
        confirmed.removeValue(forKey: "reset")
        confirmed[key] = command
      }
      lastAction = command
    }
  }
}
