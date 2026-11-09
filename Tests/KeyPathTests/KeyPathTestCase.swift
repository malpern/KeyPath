@testable import KeyPathAppKit
@testable import KeyPathInstallationWizard
import KeyPathWizardCore
@preconcurrency import XCTest

/// Base test case class that provides common test seam setup for KeyPath tests.
///
/// Use this base class for any test that uses `InstallerEngine`,
/// `RuntimeCoordinator`, or `SystemValidator`. It resets shared singletons and
/// installs a `SystemValidator` in `WizardDependencies`.
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
        MainActor.assumeIsolated {
            TestSingletonReset.resetAll()
            if WizardDependencies.systemValidator == nil {
                WizardDependencies.systemValidator = SystemValidator()
            }
        }
    }

    override open func tearDown() {
        MainActor.assumeIsolated {
            WizardDependencies.reset()
            TestSingletonReset.resetAll()
        }
        super.tearDown()
    }
}

/// Async variant for tests that use async setUp/tearDown.
@MainActor
open class KeyPathAsyncTestCase: XCTestCase {
    override open func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            TestSingletonReset.resetAll()
            if WizardDependencies.systemValidator == nil {
                WizardDependencies.systemValidator = SystemValidator()
            }
        }
    }

    override open func tearDown() async throws {
        await MainActor.run {
            WizardDependencies.reset()
            TestSingletonReset.resetAll()
        }
        try await super.tearDown()
    }
}
