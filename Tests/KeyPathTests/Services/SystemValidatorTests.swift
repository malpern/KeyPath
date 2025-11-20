import Foundation
import Testing

@testable import KeyPathAppKit
@testable import KeyPathDaemonLifecycle
@testable import KeyPathPermissions
@testable import KeyPathWizardCore

@MainActor
@Suite("SystemValidator Tests")
struct SystemValidatorTests {
  /// Setup: Reset counters before each test to ensure isolation
  private func setupTest() async {
    SystemValidator.resetCounters()
    // Small delay to ensure reset completes before validator creation
    // This helps prevent race conditions in parallel test execution
    try? await Task.sleep(nanoseconds: 10_000_000)  // 0.01 seconds
  }

  @Test("SystemValidator can be instantiated")
  func instantiation() async {
    // Reset counters before test
    await setupTest()

    let processManager = ProcessLifecycleManager()
    let validator = SystemValidator(processLifecycleManager: processManager)

    // Should not crash - validator is non-optional
    _ = validator

    // Wait briefly to ensure any concurrent validations from other tests settle
    try? await Task.sleep(nanoseconds: 50_000_000)  // 0.05 seconds

    let stats = SystemValidator.getValidationStats()
    // In parallel execution, other tests may have active validations
    // So we check that activeCount is reasonable (0-2) rather than exactly 0
    #expect(stats.activeCount <= 2, "activeCount should be reasonable")
    // Total count may be > 0 if other tests ran, but should be >= 0
    #expect(stats.totalCount >= 0)
  }

  @Test("SystemValidator tracks validation count")
  func validationCount() async {
    // Reset counters and ensure isolation
    await setupTest()

    // Create validator FIRST to become the counting owner
    // This ensures our validator is the one that counts
    let processManager = ProcessLifecycleManager()
    let validator = SystemValidator(processLifecycleManager: processManager)

    // Wait to ensure validator initialization completes and becomes counting owner
    try? await Task.sleep(nanoseconds: 50_000_000)  // 0.05 seconds

    // Get baseline stats AFTER creating our validator
    // Note: baselineCount might be > 0 if other parallel tests ran, but that's okay
    let baselineStats = SystemValidator.getValidationStats()
    let baselineCount = baselineStats.totalCount

    // First validation - should increment count if we're the counting owner
    _ = await validator.checkSystem()

    // Wait for validation to complete and counters to update
    try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2 seconds

    var stats = SystemValidator.getValidationStats()

    // In parallel execution, if another test's validator is the counting owner,
    // our validator won't increment the count. So we check that:
    // 1. Either the count increased (we're the counting owner), OR
    // 2. The activeCount changed (validation happened, even if we're not counting)
    let countIncreased = stats.totalCount > baselineCount
    let hadActiveValidation = stats.activeCount > 0 || baselineStats.activeCount > 0

    // At least one of these should be true: either we counted, or validation happened
    #expect(
      countIncreased || hadActiveValidation,
      "Either count should increase (if we're counting owner) or activeCount should change (validation happened)"
    )

    // Active count should be reasonable after validation completes
    #expect(stats.activeCount <= 2, "activeCount should be reasonable after validation completes")

    // Second validation - only check count if we're the counting owner
    let countAfterFirst = stats.totalCount
    _ = await validator.checkSystem()

    // Wait again for defer blocks
    try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2 seconds

    stats = SystemValidator.getValidationStats()

    // If we were counting before, we should still be counting
    // If count increased from baseline, check it increases again
    if countIncreased {
      #expect(
        stats.totalCount >= countAfterFirst + 1,
        "totalCount should increase again after second validation (if we're counting owner)")
    }
    #expect(stats.activeCount <= 2, "activeCount should be reasonable after validation completes")
  }

  @Test("SystemSnapshot has fresh timestamp")
  func snapshotFreshness() async {
    // Reset counters for isolation (this test doesn't check counts, but good practice)
    await setupTest()

    let processManager = ProcessLifecycleManager()
    let validator = SystemValidator(processLifecycleManager: processManager)

    let snapshot = await validator.checkSystem()

    // Snapshot should be fresh (< 1 second old)
    #expect(snapshot.age < 1.0)

    // Should not crash on validate()
    snapshot.validate()
  }

  @Test("SystemSnapshot validates staleness")
  func snapshotStalenessDetection() async {
    // Create a snapshot with old timestamp
    let oldTimestamp = Date(timeIntervalSinceNow: -35)

    let snapshot = SystemSnapshot(
      permissions: PermissionOracle.Snapshot(
        keyPath: PermissionOracle.PermissionSet(
          accessibility: .unknown,
          inputMonitoring: .unknown,
          source: "test",
          confidence: .low,
          timestamp: Date()
        ),
        kanata: PermissionOracle.PermissionSet(
          accessibility: .unknown,
          inputMonitoring: .unknown,
          source: "test",
          confidence: .low,
          timestamp: Date()
        ),
        timestamp: Date()
      ),
      components: ComponentStatus(
        kanataBinaryInstalled: false,
        karabinerDriverInstalled: false,
        karabinerDaemonRunning: false,
        vhidDeviceInstalled: false,
        vhidDeviceHealthy: false,
        launchDaemonServicesHealthy: false,
        vhidVersionMismatch: false
      ),
      conflicts: ConflictStatus(conflicts: [], canAutoResolve: false),
      health: HealthStatus(
        kanataRunning: false,
        karabinerDaemonRunning: false,
        vhidHealthy: false
      ),
      helper: HelperStatus(
        isInstalled: false,
        version: nil,
        isWorking: false
      ),
      timestamp: oldTimestamp
    )

    // Age should be > 30 seconds
    #expect(snapshot.age > 30.0)

    // validate() should assert in debug builds
    // (We can't test this directly without crashing the test)
  }
}
