import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

public extension InstallationWizardView {
    // MARK: - Actions

    /// Main "Fix All" handler - delegates to InstallerEngine which handles all repair logic
    func performAutoFix() {
        AppLogger.shared.log("🔧 [Wizard] Fix button clicked - delegating to InstallerEngine")

        Task {
            // Guard against double-execution
            guard !fixInFlight else {
                await MainActor.run {
                    toastManager.showInfo("Another fix is already running…", duration: 3.0)
                }
                return
            }
            await MainActor.run { fixInFlight = true }
            defer { Task { @MainActor in fixInFlight = false } }

            let report = await InstallerEngine().run(intent: .repair, using: PrivilegeBroker())
            let evidenceApplied = applyOwnedRunResult(report)

            // Show result toast
            await MainActor.run {
                if report.success, !evidenceApplied {
                    toastManager.showError(
                        "Repair finished, but KeyPath could not verify the final system state. Close and reopen the wizard before retrying.",
                        duration: 8.0
                    )
                } else if report.completionState == .awaitingApproval {
                    toastManager.showInfo(
                        "Repair completed. Approve KeyPath in System Settings → Login Items to continue.",
                        duration: 7.0
                    )
                } else if report.success {
                    let successCount = report.executedRecipes.filter(\.success).count
                    let totalCount = report.executedRecipes.count
                    if totalCount > 0 {
                        toastManager.showSuccess(
                            "Repaired \(successCount) of \(totalCount) issue(s)",
                            duration: 5.0
                        )
                    } else {
                        toastManager.showInfo("No issues found to repair", duration: 3.0)
                    }
                } else {
                    let failureReason = report.failureReason ?? "Unknown error"
                    toastManager.showError("Repair failed: \(failureReason)", duration: 7.0)
                }
            }

            // Log report details
            AppLogger.shared.log(
                "🔧 [Wizard] Repair completed - state: \(report.completionState.rawValue), recipes: \(report.executedRecipes.count), run: \(report.runID)"
            )
            if let failureReason = report.failureReason {
                AppLogger.shared.log("❌ [Wizard] Failure reason: \(failureReason)")
            }
        }
    }

    /// Single-action fix handler for individual "Fix" buttons on pages
    func performAutoFix(_ action: AutoFixAction, suppressToast: Bool = false) async -> Bool {
        // Single-flight guard for Fix buttons
        if inFlightFixActions.contains(action) {
            if !suppressToast {
                await MainActor.run {
                    toastManager.showInfo("Fix already running…", duration: 3.0)
                }
            }
            return false
        }
        if fixInFlight {
            if !suppressToast {
                await MainActor.run {
                    toastManager.showInfo("Another fix is already running…", duration: 3.0)
                }
            }
            return false
        }
        inFlightFixActions.insert(action)
        currentFixAction = action
        fixInFlight = true
        defer {
            inFlightFixActions.remove(action)
            currentFixAction = nil
            fixInFlight = false
        }

        AppLogger.shared.log("🔧 [Wizard] Auto-fix for specific action: \(action)")

        // Give VHID/launch-service operations more time
        let timeoutSeconds = switch action {
        case .restartVirtualHIDDaemon, .installCorrectVHIDDriver, .repairVHIDDaemonServices,
             .installRequiredRuntimeServices:
            30.0
        default:
            12.0
        }
        let actionDescription = getAutoFixActionDescription(action)

        let report: InstallerReport
        do {
            report = try await runWithTimeout(seconds: timeoutSeconds) {
                await InstallerEngine().runSingleAction(action, using: PrivilegeBroker())
            }
        } catch {
            if !suppressToast {
                await MainActor.run {
                    toastManager.showError(
                        "Fix timed out after \(Int(timeoutSeconds))s.", duration: 7.0
                    )
                }
            }
            AppLogger.shared.log("⚠️ [Wizard] Auto-fix timed out for action: \(action)")
            return false
        }

        let evidenceApplied = applyOwnedRunResult(report)

        if !suppressToast {
            await MainActor.run {
                if report.success, !evidenceApplied {
                    toastManager.showError(
                        "\(actionDescription) finished, but KeyPath could not verify the final system state. Close and reopen the wizard before retrying.",
                        duration: 8.0
                    )
                } else if report.completionState == .awaitingApproval {
                    toastManager.showInfo(
                        "\(actionDescription) completed. Approve KeyPath in System Settings → Login Items to continue.",
                        duration: 7.0
                    )
                } else if report.success {
                    toastManager.showSuccess("\(actionDescription) completed successfully", duration: 5.0)
                } else {
                    let message = report.failureReason ?? "\(actionDescription) failed"
                    toastManager.showError(message, duration: 7.0)
                }
            }
        }

        AppLogger.shared.log(
            "🔧 [Wizard] Single-action fix completed - state: \(report.completionState.rawValue), run: \(report.runID)"
        )

        return report.success && evidenceApplied && report.completionState != .awaitingApproval
    }

    /// UI-only descriptions for auto-fix actions (delegated to AutoFixActionDescriptions)
    func describeAutoFixActionForUI(_ action: AutoFixAction) -> String {
        AutoFixActionDescriptions.describe(action)
    }

    /// Get user-friendly description for auto-fix actions
    func getAutoFixActionDescription(_ action: AutoFixAction) -> String {
        AppLogger.shared.log("🔍 [ActionDescription] getAutoFixActionDescription called for: \(action)")
        let description = AutoFixActionDescriptions.describe(action)
        AppLogger.shared.log("🔍 [ActionDescription] Returning description: \(description)")
        return description
    }

    @MainActor
    private func applyOwnedRunResult(_ report: InstallerReport) -> Bool {
        guard let finalContext = report.finalContext else {
            AppLogger.shared.log(
                "⚠️ [Wizard] Run \(report.runID) returned without final system evidence"
            )
            return false
        }
        _ = applySystemStateResult(SystemStateResult.projecting(finalContext))
        return true
    }
}
