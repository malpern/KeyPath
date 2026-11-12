import Foundation
import KeyPathCore
import SwiftUI

// MARK: - WizardDependencies

/// What `InstallerEngine` and the wizard reach that the app owns. Views get the
/// rest from `WizardHost` in the SwiftUI environment.
/// Configured at app launch by KeyPathAppKit before any wizard views appear.
///
/// KeyPathAppKit sets these in `configureWizardDependencies(runtimeCoordinator:)`.
@MainActor
public enum WizardDependencies {
    // MARK: - Core Manager Protocols

    /// RuntimeCoordinator instance
    public static var runtimeCoordinator: (any RuntimeCoordinating)?

    // MARK: - Service Protocols

    /// SystemValidator instance
    public static var systemValidator: (any WizardSystemValidating)?

    // MARK: - Type-Erased Closures

    /// UninstallCoordinator factory (type-erased, creates new instance each call)
    public static var createUninstallCoordinator: (() -> any WizardUninstalling)?

    // MARK: - Test Support

    /// Reset all dependencies to nil/false for test teardown.
    /// Call from KeyPathTestCase.tearDown() within `MainActor.assumeIsolated` or `MainActor.run`.
    public static func reset() {
        runtimeCoordinator = nil
        systemValidator = nil
        createUninstallCoordinator = nil
    }
}

// MARK: - Environment Keys

/// Environment key for RuntimeCoordinating, replacing @Environment(KanataViewModel.self)
private struct RuntimeCoordinatingKey: EnvironmentKey {
    static let defaultValue: (any RuntimeCoordinating)? = nil
}

public extension EnvironmentValues {
    var runtimeCoordinator: (any RuntimeCoordinating)? {
        get { self[RuntimeCoordinatingKey.self] }
        set { self[RuntimeCoordinatingKey.self] = newValue }
    }
}
