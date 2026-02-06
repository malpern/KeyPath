import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

extension InstallationWizardView {
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

            // Check if Login Items approval is pending
            let smState = await KanataDaemonManager.shared.refreshManagementState()
            if smState == .smappservicePending {
                await MainActor.run {
                    toastManager.showError(
                        "Enable KeyPath in System Settings → Login Items before running Fix.",
                        duration: 6.0
                    )
                }
                return
            }

            // Run full repair via InstallerEngine (it handles all cases efficiently)
            let report = await kanataManager.runFullRepair(reason: "Wizard Fix button")

            // Show result toast
            await MainActor.run {
                if report.success {
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
            AppLogger.shared.log("🔧 [Wizard] Repair completed - success: \(report.success), recipes: \(report.executedRecipes.count)")
            if let failureReason = report.failureReason {
                AppLogger.shared.log("❌ [Wizard] Failure reason: \(failureReason)")
            }

            // Refresh state after repair
            refreshSystemState()

            // Notify main screen to refresh
            NotificationCenter.default.post(name: .kp_startupRevalidate, object: nil)
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

        // Short-circuit service installs when Login Items approval is pending
        if action == .installLaunchDaemonServices || action == .restartUnhealthyServices,
           await KanataDaemonManager.shared.refreshManagementState() == .smappservicePending
        {
            if !suppressToast {
                await MainActor.run {
                    toastManager.showError(
                        "KeyPath background service needs approval in System Settings → Login Items. Enable 'KeyPath' then click Fix again.",
                        duration: 7.0
                    )
                }
            }
            return false
        }
        // Give VHID/launch-service operations more time
        let timeoutSeconds = switch action {
        case .restartVirtualHIDDaemon, .installCorrectVHIDDriver, .repairVHIDDaemonServices,
             .installLaunchDaemonServices:
            30.0
        default:
            12.0
        }
        let actionDescription = getAutoFixActionDescription(action)

        let smState = await KanataDaemonManager.shared.refreshManagementState()

        let deferToastActions: Set<AutoFixAction> = [
            .restartVirtualHIDDaemon, .installCorrectVHIDDriver, .repairVHIDDaemonServices,
            .installLaunchDaemonServices
        ]
        let deferSuccessToast = deferToastActions.contains(action)
        var successToastPending = false

        let success: Bool
        do {
            success = try await runWithTimeout(seconds: timeoutSeconds) {
                await autoFixer.performAutoFix(action)
            }
        } catch {
            let stateSummary = await describeServiceState()
            if !suppressToast {
                await MainActor.run {
                    toastManager.showError(
                        "Fix timed out after \(Int(timeoutSeconds))s. \(stateSummary)", duration: 7.0
                    )
                }
            }
            AppLogger.shared.log("⚠️ [Wizard] Auto-fix timed out for action: \(action)")
            return false
        }

        let errorMessage = success ? "" : await getDetailedErrorMessage(for: action, actionDescription: actionDescription)

        if !suppressToast {
            await MainActor.run {
                if success {
                    if deferSuccessToast {
                        successToastPending = true
                        toastManager.showInfo("Verifying…", duration: 3.0)
                    } else {
                        toastManager.showSuccess("\(actionDescription) completed successfully", duration: 5.0)
                    }
                } else {
                    let message = (!success && smState == .smappservicePending) ?
                        "KeyPath background service needs approval in System Settings → Login Items. Enable 'KeyPath' and click Fix again."
                        : errorMessage
                    toastManager.showError(message, duration: 7.0)
                }
            }
        }

        AppLogger.shared.log("🔧 [Wizard] Single-action fix completed - success: \(success)")

        // Refresh system state after auto-fix
        Task {
            // Shorter delay - we have warm-up window to handle startup
            _ = await WizardSleep.seconds(1) // allow services to start
            refreshSystemState()

            // Notify StartupValidator to refresh main screen status
            NotificationCenter.default.post(name: .kp_startupRevalidate, object: nil)
            AppLogger.shared.log(
                "🔄 [Wizard] Triggered StartupValidator refresh after successful auto-fix"
            )

            // Schedule a follow-up health check; if still red, show a diagnostic error toast
            Task {
                _ = await WizardSleep.seconds(2) // allow additional settle time
                let latestResult = await stateMachine.detectCurrentState()
                let filteredIssues = sanitizedIssues(from: latestResult.issues, for: latestResult.state)
                await MainActor.run {
                    stateMachine.wizardState = latestResult.state
                    stateMachine.wizardIssues = filteredIssues
                }
                let karabinerStatus = KarabinerComponentsStatusEvaluator.evaluate(
                    systemState: latestResult.state,
                    issues: filteredIssues
                )
                AppLogger.shared.log("🔍 [Wizard] Post-fix health check: karabinerStatus=\(karabinerStatus)")
                if action == .restartVirtualHIDDaemon || action == .startKarabinerDaemon ||
                    action == .installCorrectVHIDDriver || action == .repairVHIDDaemonServices
                {
                    let smStatePost = await KanataDaemonManager.shared.refreshManagementState()
                    // IMPORTANT: Run off MainActor to avoid blocking UI - detectConnectionHealth spawns pgrep subprocesses
                    let vhidHealthy = await Task.detached {
                        await VHIDDeviceManager().detectConnectionHealth()
                    }.value

                    if karabinerStatus == .completed || vhidHealthy {
                        if successToastPending, !suppressToast {
                            await MainActor.run {
                                toastManager.showSuccess(
                                    "\(actionDescription) completed successfully", duration: 5.0
                                )
                            }
                        }
                    } else if !suppressToast {
                        let detail = await kanataManager.getVirtualHIDBreakageSummary()
                        AppLogger.shared.log(
                            "❌ [Wizard] Post-fix health check failed; will show diagnostic toast"
                        )
                        await MainActor.run {
                            if smStatePost == .smappservicePending {
                                toastManager.showError(
                                    "KeyPath background service needs approval in System Settings → Login Items. Enable 'KeyPath' and click Fix again.",
                                    duration: 7.0
                                )
                            } else {
                                toastManager.showError(
                                    "Karabiner driver is still not healthy.\n\n\(detail)", duration: 7.0
                                )
                            }
                        }
                    }
                }
            }
        }

        return success
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
}
