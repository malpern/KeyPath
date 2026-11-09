import Foundation
import KeyPathCore

/// Coordinates recording pause/resume and diagnostic auto-fix
@MainActor
final class RecoveryCoordinator {
    // MARK: - Dependencies

    /// Handler to kill all Kanata processes
    private var killAllKanataProcesses: () async throws -> Void

    /// Handler to restart Kanata service
    private var restartService: (String) async -> Bool

    // MARK: - Initialization

    init() {
        // Initialize with no-ops, will be configured after RuntimeCoordinator is fully initialized
        killAllKanataProcesses = { throw KeyPathError.process(.notRunning) }
        restartService = { _ in false }
    }

    /// Configure recovery handlers (called after RuntimeCoordinator initialization)
    func configure(
        killAllKanataProcesses: @escaping () async throws -> Void,
        restartService: @escaping (String) async -> Bool
    ) {
        self.killAllKanataProcesses = killAllKanataProcesses
        self.restartService = restartService
    }

    // MARK: - Auto-Fix Logic

    /// Determine if a diagnostic can be auto-fixed
    func canAutoFix(_ diagnostic: KanataDiagnostic) -> Bool {
        diagnostic.canAutoFix
    }

    /// Determine the auto-fix action type
    func autoFixActionType(_ diagnostic: KanataDiagnostic) -> AutoFixActionType? {
        guard diagnostic.canAutoFix else { return nil }

        switch diagnostic.category {
        case .configuration:
            return .resetConfig

        case .process:
            if diagnostic.title == "Process Terminated" {
                return .restartService
            }
            return nil

        default:
            return nil
        }
    }

    /// Log auto-fix result
    func logAutoFixResult(_ action: AutoFixActionType, success: Bool) {
        switch action {
        case .resetConfig:
            if success {
                AppLogger.shared.log("🔧 [RecoveryCoordinator] Reset configuration to default")
            } else {
                AppLogger.shared.error("❌ [RecoveryCoordinator] Failed to reset config")
            }

        case .restartService:
            AppLogger.shared.log("🔧 [RecoveryCoordinator] Attempted to restart Kanata (success=\(success))")
        }
    }

    // MARK: - Pause/Resume Mappings

    /// Temporarily pause mappings (for raw key capture during recording)
    func pauseMappings() async -> Bool {
        AppLogger.shared.log("⏸️ [Mappings] Attempting to pause mappings for recording...")

        do {
            try await killAllKanataProcesses()
            // Small settle to ensure processes exit
            try? await Task.sleep(for: .milliseconds(100)) // 100ms
            AppLogger.shared.log("🛑 [Mappings] Paused by killing Kanata processes")
            return true
        } catch {
            AppLogger.shared.warnUnlessQuietTest("⚠️ [Mappings] Failed to pause mappings: \(error)")
            return false
        }
    }

    /// Resume mappings after recording
    func resumeMappings() async -> Bool {
        AppLogger.shared.log("▶️ [Mappings] Attempting to resume mappings after recording...")

        let success = await restartService("Resume after recording")
        if success {
            // Give it a brief moment to come up
            try? await Task.sleep(for: .milliseconds(200))
            AppLogger.shared.info("🚀 [Mappings] Resumed by restarting service")
        } else {
            AppLogger.shared.warnUnlessQuietTest("⚠️ [Mappings] Failed to resume mappings")
        }
        return success
    }
}

/// Types of auto-fix actions
enum AutoFixActionType {
    case resetConfig
    case restartService
}
