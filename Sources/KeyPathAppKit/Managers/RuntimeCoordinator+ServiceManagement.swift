import Foundation
import KeyPathCore
import KeyPathPermissions

extension RuntimeCoordinator {
    /// Type alias preserving backward compatibility for callers that reference
    /// `RuntimeCoordinator.RuntimeStatus`.
    typealias RuntimeStatus = ServiceLifecycleCoordinator.RuntimeStatus

    func currentSplitRuntimeDecision() async -> KanataRuntimePathDecision {
        await serviceLifecycleCoordinator.currentSplitRuntimeDecision()
    }

    func shouldUseSplitRuntimeHost() async -> Bool {
        await serviceLifecycleCoordinator.shouldUseSplitRuntimeHost()
    }

    /// Starts Kanata with VirtualHID connection validation
    func startKanataWithValidation() async {
        await serviceLifecycleCoordinator.startKanataWithValidation()
    }

    // MARK: - Service Management Helpers

    @discardableResult
    func startKanata(reason: String = "Manual start", precomputedDecision: KanataRuntimePathDecision? = nil) async -> Bool {
        await serviceLifecycleCoordinator.startKanata(reason: reason, precomputedDecision: precomputedDecision)
    }

    @discardableResult
    func stopKanata(reason: String = "Manual stop") async -> Bool {
        await serviceLifecycleCoordinator.stopKanata(reason: reason)
    }

    @discardableResult
    func restartKanata(reason: String = "Manual restart") async -> Bool {
        await serviceLifecycleCoordinator.restartKanata(reason: reason)
    }

    func currentRuntimeStatus() async -> RuntimeStatus {
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
