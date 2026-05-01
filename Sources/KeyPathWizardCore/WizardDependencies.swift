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
///         helperManager: HelperManager.shared,
///         daemonManager: KanataDaemonManager.shared,
///         ...
///     )
@MainActor
public enum WizardDependencies {
    // MARK: - Core Manager Protocols

    /// RuntimeCoordinator instance
    public static var runtimeCoordinator: (any RuntimeCoordinating)?

    /// HelperManager instance
    nonisolated(unsafe) public static var helperManager: (any WizardHelperManaging)?

    /// KanataDaemonManager instance
    public static var daemonManager: (any WizardDaemonManaging)?

    // MARK: - Service Protocols

    /// SystemValidator instance
    public static var systemValidator: (any WizardSystemValidating)?

    /// HelperMaintenance instance
    public static var helperMaintenance: (any WizardHelperMaintaining)?

    /// FullDiskAccessChecker instance
    nonisolated(unsafe) public static var fullDiskAccessChecker: (any WizardFullDiskAccessChecking)?

    /// PermissionRequestService instance
    nonisolated(unsafe) public static var permissionRequestService: (any WizardPermissionRequesting)?

    /// PrivilegedOperationsCoordinator instance
    public static var privilegedOperations: (any WizardPrivilegedOperating)?

    // MARK: - Page View Factories (for pages implemented in KeyPathAppKit)

    /// Factory for the kanataMigration wizard page.
    /// Signature: (onMigrationComplete: (Bool) -> Void, onSkip: () -> Void) -> AnyView
    @MainActor public static var makeKanataMigrationPage: ((@escaping (Bool) -> Void, @escaping () -> Void) -> AnyView)?

    /// Factory for the karabinerImport wizard page.
    /// Signature: (onImportComplete: () -> Void, onSkip: () -> Void) -> AnyView
    @MainActor public static var makeKarabinerImportPage: ((@escaping () -> Void, @escaping () -> Void) -> AnyView)?

    /// Factory for the communication wizard page.
    /// Signature: (onAutoFix: (AutoFixAction, Bool) async -> Bool) -> AnyView
    @MainActor public static var makeCommunicationPage: ((@escaping (AutoFixAction, Bool) async -> Bool) -> AnyView)?

    // MARK: - Type-Erased Closures

    /// SMAppService factory for helper plist (type-erased)
    nonisolated(unsafe) public static var smServiceFactory: ((String) -> Any)?

    /// UninstallCoordinator factory (type-erased, creates new instance each call)
    public static var createUninstallCoordinator: (() -> any WizardUninstalling)?

    /// AdminCommandExecutor - execute(batch:) for privileged commands
    nonisolated(unsafe) public static var executePrivilegedBatch: ((PrivilegedCommandRunner.Batch) async throws -> (exitCode: Int32, output: String))?

    /// KeyPathAppKitResources bundle accessor
    nonisolated(unsafe) public static var resourceBundle: Bundle?

    // MARK: - ExternalKanataService (static methods)

    /// Get info about externally-running Kanata process
    nonisolated(unsafe) public static var getExternalKanataInfo: (() -> WizardSystemPaths.RunningKanataInfo?)?

    /// Stop an externally-running Kanata process
    nonisolated(unsafe) public static var stopExternalKanata: ((WizardSystemPaths.RunningKanataInfo) async -> Result<Void, Error>)?

    /// Check if external Kanata is running
    nonisolated(unsafe) public static var hasExternalKanataRunning: (() -> Bool)?

    // MARK: - TCPProbe (static method)

    /// TCP connectivity probe
    nonisolated(unsafe) public static var tcpProbe: ((Int, Int) -> Bool)?

    // MARK: - NotificationObserverManager factory

    /// Factory to create notification observer managers
    nonisolated(unsafe) public static var createNotificationObserverManager: (() -> Any)?

    // MARK: - Ad-hoc Signature Cache

    /// Whether the app is running ad-hoc signed (not notarized).
    /// Cached at startup by KeyPathAppKit to avoid blocking the main thread
    /// with a synchronous codesign subprocess call from SwiftUI views.
    nonisolated(unsafe) public static var isRunningAdHoc: Bool = false

    // MARK: - Test Support

    /// Reset all dependencies to nil/false for test teardown.
    /// Call from KeyPathTestCase.tearDown() to prevent state leaking between tests.
    public static func reset() {
        runtimeCoordinator = nil
        helperManager = nil
        daemonManager = nil
        systemValidator = nil
        helperMaintenance = nil
        fullDiskAccessChecker = nil
        permissionRequestService = nil
        privilegedOperations = nil
        makeKanataMigrationPage = nil
        makeKarabinerImportPage = nil
        makeCommunicationPage = nil
        smServiceFactory = nil
        createUninstallCoordinator = nil
        executePrivilegedBatch = nil
        resourceBundle = nil
        getExternalKanataInfo = nil
        stopExternalKanata = nil
        hasExternalKanataRunning = nil
        tcpProbe = nil
        createNotificationObserverManager = nil
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
