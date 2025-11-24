import XCTest

@testable import KeyPathAppKit

/// Base test case class that provides common test seam setup for KeyPath tests.
///
/// **IMPORTANT**: Use this base class for any test that uses:
/// - `InstallerEngine`
/// - `RuntimeCoordinator`
/// - `SystemValidator`
/// - `VHIDDeviceManager`
///
/// This base class automatically sets up `VHIDDeviceManager.testPIDProvider` to avoid
/// spawning real `pgrep` subprocess calls, which can deadlock during parallel test execution.
///
/// ## Why This Matters
/// `VHIDDeviceManager.detectConnectionHealth()` spawns `pgrep` subprocesses with 3s timeouts.
/// When tests run in parallel and repeatedly call this code path, the subprocesses can deadlock,
/// causing tests to hang indefinitely.
///
/// ## Usage
/// ```swift
/// @MainActor
/// final class MyTests: KeyPathTestCase {
///     func testSomething() async {
///         let engine = InstallerEngine()
///         let context = await engine.inspectSystem() // Safe - uses mock
///     }
/// }
/// ```
///
/// If you need to override setUp/tearDown, call super:
/// ```swift
/// override func setUp() {
///     super.setUp()
///     // Your additional setup
/// }
/// ```
@MainActor
open class KeyPathTestCase: XCTestCase {
    override open func setUp() {
        super.setUp()
        // Set up test seam to avoid real pgrep calls which can hang after multiple rapid executions.
        // Without this, detectConnectionHealth() spawns pgrep subprocesses with 3s timeouts that
        // can deadlock when run repeatedly in quick succession.
        VHIDDeviceManager.testPIDProvider = { [] }
    }

    override open func tearDown() {
        VHIDDeviceManager.testPIDProvider = nil
        super.tearDown()
    }
}

/// Async variant for tests that use async setUp/tearDown.
///
/// Use this when your test class needs async setUp (e.g., `override func setUp() async throws`).
@MainActor
open class KeyPathAsyncTestCase: XCTestCase {
    override open func setUp() async throws {
        try await super.setUp()
        VHIDDeviceManager.testPIDProvider = { [] }
    }

    override open func tearDown() async throws {
        VHIDDeviceManager.testPIDProvider = nil
        try await super.tearDown()
    }
}
