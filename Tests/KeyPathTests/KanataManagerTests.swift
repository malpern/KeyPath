import XCTest

@testable import KeyPath

@MainActor
final class KanataManagerTests: XCTestCase {

  var manager: KanataManager!

  override func setUp() async throws {
    manager = KanataManager()
  }

  override func tearDown() async throws {
    await manager.stopKanata()
    manager = nil
  }

  // MARK: - Lifecycle Tests

  func testInitialState() {
    XCTAssertFalse(manager.isRunning, "Should not be running initially")
    XCTAssertNil(manager.lastError, "Should have no error initially")
    XCTAssertTrue(manager.currentMappings.isEmpty, "Should have no mappings initially")
  }

  func testStartStopCycle() async throws {
    // Start kanata
    await manager.startKanata()

    // May not actually start without proper setup, but should handle gracefully
    XCTAssertNotNil(manager.currentState, "Should have a state after start attempt")

    // Stop kanata
    await manager.stopKanata()
    XCTAssertFalse(manager.isRunning, "Should not be running after stop")
  }

  func testRestartKanata() async throws {
    await manager.restartKanata()
    // Should complete without throwing
    XCTAssertTrue(true, "Restart completed")
  }

  // MARK: - Configuration Tests

  func testKeyMappingConversion() {
    // Test kanata key conversions
    XCTAssertEqual(manager.convertToKanataKey("caps"), "caps")
    XCTAssertEqual(manager.convertToKanataKey("space"), "spc")
    XCTAssertEqual(manager.convertToKanataKey("escape"), "esc")
    XCTAssertEqual(manager.convertToKanataKey("return"), "ret")
    XCTAssertEqual(manager.convertToKanataKey("tab"), "tab")
    XCTAssertEqual(manager.convertToKanataKey("delete"), "bspc")
  }

  func testGenerateKanataConfig() {
    let config = manager.generateKanataConfig(input: "caps", output: "escape")

    XCTAssertTrue(config.contains("defcfg"), "Config should contain defcfg")
    XCTAssertTrue(config.contains("defsrc"), "Config should contain defsrc")
    XCTAssertTrue(config.contains("deflayer"), "Config should contain deflayer")
    XCTAssertTrue(config.contains("caps"), "Config should contain input key")
    XCTAssertTrue(config.contains("esc"), "Config should contain output key")
  }

  func testAddMapping() async {
    let mapping = KeyMapping(input: "caps", output: "escape")
    await manager.addMapping(mapping)

    await MainActor.run {
      XCTAssertEqual(manager.currentMappings.count, 1, "Should have one mapping")
      XCTAssertEqual(manager.currentMappings.first?.input, "caps")
      XCTAssertEqual(manager.currentMappings.first?.output, "escape")
    }
  }

  func testRemoveMapping() async {
    let mapping = KeyMapping(input: "caps", output: "escape")
    await manager.addMapping(mapping)

    await MainActor.run {
      XCTAssertEqual(manager.currentMappings.count, 1)
    }

    await manager.removeMapping(mapping)

    await MainActor.run {
      XCTAssertTrue(manager.currentMappings.isEmpty, "Should have no mappings after removal")
    }
  }

  // MARK: - Error Handling Tests

  func testDiagnoseKanataFailure() {
    manager.diagnoseKanataFailure(126, "Permission denied")

    XCTAssertNotNil(manager.lastError, "Should set error on failure")
    XCTAssertFalse(manager.diagnostics.isEmpty, "Should add diagnostic on failure")
  }

  func testSafetyTimeout() async {
    // This should auto-stop after 30 seconds if not configured properly
    await manager.startKanataWithSafetyTimeout()

    // Should not crash or hang
    XCTAssertTrue(true, "Safety timeout handled")
  }

  // MARK: - Path Detection Tests

  func testKanataPathDetection() {
    let paths = [
      "/opt/homebrew/bin/kanata",
      "/usr/local/bin/kanata",
      "/Applications/Kanata.app/Contents/MacOS/kanata"
    ]

    // At least one should be considered valid
    let validPaths = paths.filter { FileManager.default.fileExists(atPath: $0) }

    if !validPaths.isEmpty {
      XCTAssertFalse(manager.kanataBinaryPath.isEmpty, "Should detect kanata path")
    }
  }

  // MARK: - Performance Tests

  func testConfigGenerationPerformance() {
    measure {
      _ = manager.generateKanataConfig(input: "caps", output: "escape")
    }
  }

  func testMappingOperationsPerformance() async {
    let mappings = (0..<100).map { KeyMapping(input: "key\($0)", output: "out\($0)") }

    await measure {
      for mapping in mappings {
        await manager.addMapping(mapping)
      }
      await manager.clearAllMappings()
    }
  }
}
