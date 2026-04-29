import Foundation
import KeyPathCore
import KeyPathPermissions

extension RuntimeCoordinator {
    /// Type alias preserving backward compatibility for callers that reference
    /// `RuntimeCoordinator.RuntimeStatus`.
    typealias RuntimeStatus = ServiceLifecycleCoordinator.RuntimeStatus

    /// Starts Kanata with VirtualHID connection validation
    func startKanataWithValidation() async {
        await serviceLifecycleCoordinator.startKanataWithValidation()
    }

    // MARK: - Service Management Helpers

    @discardableResult
    public func startKanata(reason: String = "Manual start") async -> Bool {
        await serviceLifecycleCoordinator.startKanata(reason: reason)
    }

    @discardableResult
    public func stopKanata(reason: String = "Manual stop") async -> Bool {
        await serviceLifecycleCoordinator.stopKanata(reason: reason)
    }

    @discardableResult
    public func restartKanata(reason: String = "Manual restart") async -> Bool {
        await serviceLifecycleCoordinator.restartKanata(reason: reason)
    }

    func currentRuntimeStatusInternal() async -> RuntimeStatus {
        await serviceLifecycleCoordinator.currentRuntimeStatus()
    }

    /// Check if permission issues should trigger the wizard
    func shouldShowWizardForPermissions() async -> Bool {
        await serviceLifecycleCoordinator.shouldShowWizardForPermissions()
    }

    // MARK: - UI-Focused Lifecycle Methods (from SimpleRuntimeCoordinator)

    /// Check if this is a fresh install (no Kanata binary or config)
    func isFirstTimeInstall() -> Bool {
        installationCoordinator.isFirstTimeInstall(configPath: KeyPathConstants.Config.mainConfigPath)
    }
}
