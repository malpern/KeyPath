import Foundation
import KeyPathCore

/// Coordinates recovery operations for keyboard and VirtualHID issues
@MainActor
final class RecoveryCoordinator {
    // MARK: - Dependencies

    /// Handler to kill all Kanata processes
    private var killAllKanataProcesses: () async throws -> Void

    /// Handler to restart Karabiner daemon
    private var restartKarabinerDaemon: () async -> Bool

    /// Handler to restart Kanata service
    private var restartService: (String) async -> Bool

    // MARK: - Initialization

    init() {
        // Initialize with no-ops, will be configured after RuntimeCoordinator is fully initialized
        killAllKanataProcesses = { throw KeyPathError.process(.notRunning) }
        restartKarabinerDaemon = { false }
        restartService = { _ in false }
    }

    /// Configure recovery handlers (called after RuntimeCoordinator initialization)
    func configure(
        killAllKanataProcesses: @escaping () async throws -> Void,
        restartKarabinerDaemon: @escaping () async -> Bool,
        restartService: @escaping (String) async -> Bool
    ) {
        self.killAllKanataProcesses = killAllKanataProcesses
        self.restartKarabinerDaemon = restartKarabinerDaemon
        self.restartService = restartService
    }

    // MARK: - Keyboard Recovery

    /// Perform full keyboard recovery sequence
    ///
    /// This executes a 5-step recovery process:
    /// 1. Kill all Kanata processes
    /// 2. Wait for keyboard release
    /// 3. Restart Karabiner daemon
    /// 4. Wait before retry
    /// 5. Restart Kanata service
    func attemptKeyboardRecovery() async {
        AppLogger.shared.log("🔧 [Recovery] Starting keyboard recovery process...")

        // Step 1: Ensure all Kanata processes are killed
        AppLogger.shared.log("🔧 [Recovery] Step 1: Killing any remaining Kanata processes")
        do {
            try await killAllKanataProcesses()
            AppLogger.shared.log("🔧 [Recovery] Killed Kanata processes")
        } catch {
            AppLogger.shared.warn("⚠️ [Recovery] Failed to kill Kanata processes: \(error)")
        }

        // Step 2: Wait for system to release keyboard control
        AppLogger.shared.log("🔧 [Recovery] Step 2: Waiting 2 seconds for keyboard release...")
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Step 3: Restart VirtualHID daemon
        AppLogger.shared.log("🔧 [Recovery] Step 3: Attempting to restart Karabiner daemon...")
        let restartSuccess = await restartKarabinerDaemon()
        if restartSuccess {
            AppLogger.shared.info("✅ [Recovery] Karabiner daemon restart verified")
        } else {
            AppLogger.shared.warn("⚠️ [Recovery] Karabiner daemon restart failed or not verified")
        }

        // Step 4: Wait before retry
        AppLogger.shared.log("🔧 [Recovery] Step 4: Waiting 3 seconds before retry...")
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

        // Step 5: Try restarting Kanata service
        AppLogger.shared.log(
            "🔧 [Recovery] Step 5: Attempting to restart Kanata with VirtualHID validation...")
        _ = await restartService("Keyboard recovery")

        AppLogger.shared.log("🔧 [Recovery] Keyboard recovery process complete")
    }

    // MARK: - VirtualHID Recovery

    /// Start Kanata with VirtualHID connection validation
    ///
    /// - Parameters:
    ///   - isKarabinerDaemonRunning: Check if Karabiner daemon is running
    ///   - startKanata: Handler to start Kanata service
    ///   - onError: Callback to set error state
    func startKanataWithValidation(
        isKarabinerDaemonRunning: () -> Bool,
        startKanata: () async -> Bool,
        onError: (String) -> Void
    ) async {
        // Check if VirtualHID daemon is running first
        if !isKarabinerDaemonRunning() {
            AppLogger.shared.warn("⚠️ [Recovery] Karabiner daemon not running - recovery failed")
            onError("Recovery failed: Karabiner daemon not available")
            return
        }

        // Try starting Kanata normally via KanataService
        let started = await startKanata()
        if !started {
            AppLogger.shared.error("❌ [Recovery] Failed to start Kanata during validation")
        }
    }

    /// Trigger VirtualHID recovery when connection failures are detected
    ///
    /// - Parameters:
    ///   - addDiagnostic: Handler to add diagnostic to system
    ///   - attemptRecovery: Handler to perform recovery
    func triggerVirtualHIDRecovery(
        addDiagnostic: (KanataDiagnostic) -> Void,
        attemptRecovery: () async -> Void
    ) async {
        let diagnostic = createVirtualHIDFailureDiagnostic()
        addDiagnostic(diagnostic)
        await attemptRecovery()
    }

    /// Create a VirtualHID failure diagnostic
    func createVirtualHIDFailureDiagnostic() -> KanataDiagnostic {
        AppLogger.shared.log("🚨 [RecoveryCoordinator] VirtualHID connection failure detected in real-time")

        return KanataDiagnostic(
            timestamp: Date(),
            severity: .error,
            category: .conflict,
            title: "VirtualHID Connection Failed",
            description:
            "Real-time monitoring detected repeated VirtualHID connection failures. Keyboard remapping is not functioning.",
            technicalDetails:
            "Detected multiple consecutive asio.system connection failures",
            suggestedAction:
            "KeyPath will attempt automatic recovery. If issues persist, restart the application.",
            canAutoFix: true
        )
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
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            AppLogger.shared.log("🛑 [Mappings] Paused by killing Kanata processes")
            return true
        } catch {
            AppLogger.shared.warn("⚠️ [Mappings] Failed to pause mappings: \(error)")
            return false
        }
    }

    /// Resume mappings after recording
    func resumeMappings() async -> Bool {
        AppLogger.shared.log("▶️ [Mappings] Attempting to resume mappings after recording...")

        let success = await restartService("Resume after recording")
        if success {
            // Give it a brief moment to come up
            try? await Task.sleep(nanoseconds: 200_000_000)
            AppLogger.shared.info("🚀 [Mappings] Resumed by restarting service")
        } else {
            AppLogger.shared.warn("⚠️ [Mappings] Failed to resume mappings")
        }
        return success
    }

    // MARK: - Failure Diagnosis

    /// Diagnose Kanata failure and trigger recovery if needed
    ///
    /// - Parameters:
    ///   - exitCode: Process exit code
    ///   - output: Process output/stderr
    ///   - diagnostics: Diagnostics from DiagnosticsManager
    ///   - addDiagnostic: Handler to add diagnostic to system
    ///   - attemptRecovery: Handler to attempt recovery (must be @escaping for Task)
    func diagnoseKanataFailure(
        exitCode: Int32,
        output: String,
        diagnostics: [KanataDiagnostic],
        addDiagnostic: (KanataDiagnostic) -> Void,
        attemptRecovery: @escaping () async -> Void
    ) {
        // Check for zombie keyboard capture bug (exit code 6 with VirtualHID connection failure)
        if exitCode == 6,
           output.contains("connect_failed asio.system:61")
           || output.contains("connect_failed asio.system:2") {
            // This is the "zombie keyboard capture" bug - automatically attempt recovery
            Task {
                AppLogger.shared.log(
                    "🚨 [Recovery] Detected zombie keyboard capture - attempting automatic recovery")
                await attemptRecovery()
            }
        }

        // Add all diagnostics
        for diagnostic in diagnostics {
            addDiagnostic(diagnostic)
        }
    }
}

/// Types of auto-fix actions
enum AutoFixActionType {
    case resetConfig
    case restartService
}
