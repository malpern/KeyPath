import Foundation
import KeyPathCore

extension RuntimeCoordinator {
    // MARK: - Diagnostics

    func addDiagnostic(_ diagnostic: KanataDiagnostic) {
        diagnosticsManager.addDiagnostic(diagnostic)
        // Update local diagnostics array for UI state
        diagnostics = diagnosticsManager.getDiagnostics()
    }

    func clearDiagnostics() {
        diagnosticsManager.clearDiagnostics()
        diagnostics = []
    }

    func diagnoseKanataFailure(_ exitCode: Int32, _ output: String) {
        let diagnostics = diagnosticsManager.diagnoseFailure(exitCode: exitCode, output: output)

        recoveryCoordinator.diagnoseKanataFailure(
            exitCode: exitCode,
            output: output,
            diagnostics: diagnostics,
            addDiagnostic: { [weak self] diagnostic in
                self?.addDiagnostic(diagnostic)
            },
            attemptRecovery: { [weak self] in
                await self?.attemptKeyboardRecovery()
            }
        )
    }

    // MARK: - Auto-Fix Capabilities

    func autoFixDiagnostic(_ diagnostic: KanataDiagnostic) async -> Bool {
        guard let action = recoveryCoordinator.autoFixActionType(diagnostic) else {
            return false
        }

        var success = false
        switch action {
        case .resetConfig:
            do {
                try await resetToDefaultConfig()
                success = true
            } catch {
                success = false
            }

        case .restartService:
            success = await restartServiceWithFallback(
                reason: "AutoFix diagnostic: \(diagnostic.title)"
            )
        }

        recoveryCoordinator.logAutoFixResult(action, success: success)
        return success
    }

    func getSystemDiagnostics() async -> [KanataDiagnostic] {
        await diagnosticsManager.getSystemDiagnostics(engineClient: engineClient)
    }
}
