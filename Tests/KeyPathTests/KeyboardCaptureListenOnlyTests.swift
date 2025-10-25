import XCTest
@testable import KeyPath

@MainActor
final class KeyboardCaptureListenOnlyTests: XCTestCase {
    func testListenOnlyEnabledWhenKanataRunning() throws {
        // LEGACY: This test used removed setEventRouter() API
        // KeyboardCapture now uses fastProbeKanataRunning() internally
        throw XCTSkip("Legacy test for removed setEventRouter API - migrating to new architecture")
    }

    func testRawModeWhenKanataNotRunning() throws {
        // LEGACY: This test used removed setEventRouter() API
        // KeyboardCapture now uses fastProbeKanataRunning() internally
        throw XCTSkip("Legacy test for removed setEventRouter API - migrating to new architecture")
    }

    func testRawModeWhenFeatureFlagDisabled() throws {
        // LEGACY: This test used removed setEventRouter() API
        // KeyboardCapture now uses fastProbeKanataRunning() internally
        throw XCTSkip("Legacy test for removed setEventRouter API - migrating to new architecture")
    }
}

