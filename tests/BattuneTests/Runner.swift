import Foundation

// Standalone native test runner works with Command Line Tools (no XCTest framework).
// Assertions record failures even under Release optimization.
@MainActor enum TestResults {
  static var failures: [String] = []
  static var passed = 0
}
@MainActor func expectEqual<T: Equatable>(
  _ left: T, _ right: T, file: String = #fileID, line: Int = #line
) {
  if left != right { TestResults.failures.append("\(file):\(line): \(left) != \(right)") }
}
@MainActor func expectTrue(_ value: Bool, file: String = #fileID, line: Int = #line) {
  expectEqual(value, true, file: file, line: line)
}
@MainActor func expectFalse(_ value: Bool, file: String = #fileID, line: Int = #line) {
  expectEqual(value, false, file: file, line: line)
}
@MainActor func expectThrows(
  _ body: @autoclosure () throws -> Void, _ handler: (Error) -> Void = { _ in },
  file: String = #fileID, line: Int = #line
) {
  do {
    try body()
    TestResults.failures.append("\(file):\(line): expected failure")
  } catch { handler(error) }
}
func unwrap<T>(_ value: T?) throws -> T {
  guard let value else { throw TestFailure.missingValue }
  return value
}
enum TestFailure: Error { case missingValue }
@main struct TestRunner {
  @MainActor static func main() async {
    let domain = DomainTests()
    let integration = IntegrationTests()
    let xpc = XPCTests()
    let native = NativeChargeTests()
    let adapter = AdapterTests()
    let tests: [(String, () async throws -> Void)] = [
      ("Adapter validation and preconditions", { try adapter.testValidation() }),
      ("Adapter failure rollback", { try adapter.testRollback() }),
      ("Adapter composition and crash recovery", { try adapter.testCompositionAndRecovery() }),
      ("Adapter reserve and sleep recovery", { try adapter.testSafetyAndSleep() }),
      ("Adapter gate cache after recovery", { try adapter.testGateRecoveryInvalidatesCache() }),
      (
        "Adapter full coordinator calibration and arbitrary limit",
        { try await adapter.testCoordinatorFullWorkflow() }
      ),
      (
        "Controller switching restores both backends",
        { try await adapter.testRoutingRestoresControllers() }
      ),
      ("Local exact-signature trust", { try adapter.testPinnedTrust() }),
      ("CSV and backwards compatible settings", { try adapter.testHistoryCSVAndCompatibility() }),
      ("Native timeout and expired queued writes", { try await native.testNativeTimeout() }),
      ("Native charge write, readback and restore", { try native.testWriteReadbackAndRestore() }),
      (
        "Native unsupported commands and readback failure",
        { try native.testUnsupportedAndReadbackFailure() }
      ),
      (
        "Native crash recovery and external settings",
        { try native.testCrashRecoveryAndExternalChanges() }
      ),
      (
        "Native failed recovery and corrupt journal",
        { try native.testFailedRecoveryAndCorruption() }
      ),
      ("Native disabled baseline restoration", { try native.testDisabledBaseline() }),
      (
        "Advanced native routing, sleep and workflow recovery",
        { try await native.testAdvancedModeKeepsNativeLimitAcrossSleep() }
      ),
      ("Native coordinator and shutdown", { try await native.testNativeCoordinator() }),
      ("XPC wire roundtrip", { try await xpc.testProtocolRoundtrip() }),
      ("Expired control lease resets hardware", { try await xpc.testLeaseExpiration() }),
      ("Signing validation", { try xpc.testSigningRequirementSyntax() }),
      ("ABI and charge boundaries", { try domain.testABIAndChargeBoundaries() }),
      ("Persistence and validation", { try domain.testPersistenceAndValidation() }),
      ("Schedule bridge", { try domain.testScheduleBridge() }),
      ("Capabilities and replies", { try domain.testUnsupportedBackendAndReplyMapping() }),
      ("Calibration restart", { try domain.testCalibrationRestartInterrupted() }),
      ("Stale transaction cancellation", { try await integration.testStaleTransactionStops() }),
      ("Acknowledged writes", { try await integration.testExecutorAcknowledgement() }),
      (
        "Hardware validation and rate limits",
        { try integration.testHardwareGateAndInputValidation() }
      ),
      ("Malformed helper replies", { try integration.testMalformedReplies() }),
      ("Bounded history", { try integration.testHistoryBoundedAndPrivate() }),
      ("History deduplication", { try integration.testHistoryDeduplication() }),
      ("DST and timezone changes", { try integration.testDSTAndTimezone() }),
      ("Full coordinator transitions", { try await integration.testCoordinatorTransitions() }),
      ("Failures and recovery", { try await integration.testCoordinatorFailureAndRecovery() }),
      ("Discharge and cancellation", { try await integration.testDischargeAndCancel() }),
      ("Sleep and wake", { try await integration.testWakeRefreshesWithoutReplay() }),
      ("Configuration view model", { try integration.testConfigurationAndViewModelFailures() }),
      ("Live read-only IOKit snapshot", { try integration.testLiveReadOnlySnapshot() }),
    ]
    for (name, test) in tests {
      let before = TestResults.failures.count
      do { try await test() } catch { TestResults.failures.append("\(name): \(error)") }
      if before == TestResults.failures.count {
        TestResults.passed += 1
        Swift.print("PASS \(name)")
      }
    }
    for failure in TestResults.failures { Swift.print("FAIL \(failure)") }
    Swift.print("\(TestResults.passed) passed, \(TestResults.failures.count) failures")
    if !TestResults.failures.isEmpty { exit(1) }
  }
}
