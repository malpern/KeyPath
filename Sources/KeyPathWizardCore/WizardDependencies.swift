import Foundation
import KeyPathCore
import SwiftUI

// MARK: - WizardDependencies

/// Static dependency container for wizard module types that can't be injected via init.
/// Configured at app launch by KeyPathAppKit before any wizard views appear.
///
/// Usage in KeyPathAppKit startup:
///     WizardDependencies.configure(
///         runtimeCoordinator: runtimeCoordinator,
///         ...
///     )
@MainActor
public enum WizardDependencies {
    // MARK: - Core Manager Protocols

    /// RuntimeCoordinator instance
    public static var runtimeCoordinator: (any RuntimeCoordinating)?

    // MARK: - Service Protocols

    /// SystemValidator instance
    public static var systemValidator: (any WizardSystemValidating)?

    /// PermissionRequestService instance
    public static var permissionRequestService: (any WizardPermissionRequesting)?

    // MARK: - Page View Factories (for pages implemented in KeyPathAppKit)

    /// Factory for the kanataMigration wizard page.
    /// Signature: (onMigrationComplete: (Bool) -> Void, onSkip: () -> Void) -> AnyView
    @MainActor public static var makeKanataMigrationPage: ((@escaping (Bool) -> Void, @escaping () -> Void) -> AnyView)?

    /// Factory for the karabinerImport wizard page.
    /// Signature: (onImportComplete: () -> Void, onSkip: () -> Void) -> AnyView
    @MainActor public static var makeKarabinerImportPage: ((@escaping () -> Void, @escaping () -> Void) -> AnyView)?

    // MARK: - Type-Erased Closures

    /// UninstallCoordinator factory (type-erased, creates new instance each call)
    public static var createUninstallCoordinator: (() -> any WizardUninstalling)?

    /// KeyPathAppKitResources bundle accessor
    public static var resourceBundle: Bundle?

    // MARK: - ExternalKanataService (static methods)

    /// Get info about externally-running Kanata process
    public static var getExternalKanataInfo: (() -> WizardSystemPaths.RunningKanataInfo?)?

    /// Stop an externally-running Kanata process
    public static var stopExternalKanata: ((WizardSystemPaths.RunningKanataInfo) async -> Result<Void, Error>)?

    /// Check if external Kanata is running
    public static var hasExternalKanataRunning: (() -> Bool)?

    // MARK: - Ad-hoc Signature Cache

    /// Whether the app is running ad-hoc signed (not notarized).
    /// Cached at startup by KeyPathAppKit to avoid blocking the main thread
    /// with a synchronous codesign subprocess call from SwiftUI views.
    public static var isRunningAdHoc: Bool = false

    // MARK: - Test Support

    /// Reset all dependencies to nil/false for test teardown.
    /// Call from KeyPathTestCase.tearDown() within `MainActor.assumeIsolated` or `MainActor.run`.
    public static func reset() {
        runtimeCoordinator = nil
        systemValidator = nil
        permissionRequestService = nil
        makeKanataMigrationPage = nil
        makeKarabinerImportPage = nil
        createUninstallCoordinator = nil
        resourceBundle = nil
        getExternalKanataInfo = nil
        stopExternalKanata = nil
        hasExternalKanataRunning = nil
        isRunningAdHoc = false
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
