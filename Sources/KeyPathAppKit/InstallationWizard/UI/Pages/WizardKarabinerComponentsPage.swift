import Combine
import Foundation
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

// MARK: - Constants

/// Maximum time to wait for state refresh to complete.
private let stateRefreshTimeoutSeconds: TimeInterval = 2

/// Karabiner driver and virtual HID components setup page
struct WizardKarabinerComponentsPage: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let isFixing: Bool
    let onAutoFix: (AutoFixAction, Bool) async -> Bool // (action, suppressToast)
    let onRefresh: () -> Void
    let kanataManager: RuntimeCoordinator
    let stateManager: WizardStateManager

    @State private var showAllItems = false
    @State private var isCombinedFixLoading = false
    @State private var actionStatus: WizardDesign.ActionStatus = .idle
    @State private var stepProgressCancellable: AnyCancellable?
    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator

    var body: some View {
        VStack(spacing: 0) {
            // Use experimental hero design when driver is installed
            if !hasKarabinerIssues {
                VStack(spacing: WizardDesign.Spacing.sectionGap) {
                    WizardHeroSection.success(
                        icon: "keyboard.macwindow",
                        title: "Karabiner Driver",
                        subtitle: "Virtual keyboard driver is installed & configured for input capture",
                        iconTapAction: {
                            showAllItems.toggle()
                            Task {
                                onRefresh()
                            }
                        }
                    )

                    // Inline action status (immediately after hero for visual consistency)
                    if actionStatus.isActive, let message = actionStatus.message {
                        InlineStatusView(status: actionStatus, message: message)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    // Component details card below the subheading - horizontally centered
                    HStack {
                        Spacer()
                        VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                            // Show Karabiner Driver only if showAllItems OR if it has issues (defensive)
                            if showAllItems {
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    HStack(spacing: 0) {
                                        Text("Karabiner Driver")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                        Text(" - Virtual keyboard driver for input capture")
                                            .font(.headline)
                                            .fontWeight(.regular)
                                    }
                                }
                            }

                            // Show Background Services only if showAllItems OR if it has issues
                            if showAllItems || componentStatus(for: .backgroundServices) != .completed {
                                HStack(spacing: 12) {
                                    Image(
                                        systemName: componentStatus(for: .backgroundServices) == .completed
                                            ? "checkmark.circle.fill" : "xmark.circle.fill"
                                    )
                                    .foregroundStyle(
                                        componentStatus(for: .backgroundServices) == .completed ? .green : Color.red)
                                    HStack(spacing: 0) {
                                        Text("Background Services")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                        Text(" - Karabiner services in Login Items for startup")
                                            .font(.headline)
                                            .fontWeight(.regular)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(WizardDesign.Spacing.cardPadding)
                        .background(Color.clear, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, WizardDesign.Spacing.pageVertical)
                        .padding(.top, WizardDesign.Spacing.sectionGap)
                    }

                    Button(nextStepButtonTitle) {
                        navigateToNextStep()
                    }
                    .buttonStyle(WizardDesign.Component.PrimaryButton())
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, WizardDesign.Spacing.sectionGap)
                }
                .animation(WizardDesign.Animation.statusTransition, value: actionStatus)
                .heroSectionContainer()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Simplified error state: hero + centered Fix button
                VStack(spacing: WizardDesign.Spacing.sectionGap) {
                    WizardHeroSection.error(
                        icon: "keyboard.macwindow",
                        title: "Karabiner Driver Required",
                        subtitle:
                        "Karabiner virtual keyboard driver needs to be installed & configured for input capture",
                        iconTapAction: {
                            Task {
                                onRefresh()
                            }
                        }
                    )

                    // Inline action status (immediately after hero for visual consistency)
                    if actionStatus.isActive, let message = actionStatus.message {
                        InlineStatusView(status: actionStatus, message: message)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    Button("Fix") {
                        handleCombinedFix()
                    }
                    .buttonStyle(WizardDesign.Component.PrimaryButton(isLoading: isCombinedFixLoading))
                    .keyboardShortcut(.defaultAction)
                    .disabled(isCombinedFixLoading)
                    .frame(minHeight: 44) // Prevent height change when loading spinner appears
                    .padding(.top, WizardDesign.Spacing.itemGap)
                }
                .animation(WizardDesign.Animation.statusTransition, value: actionStatus)
                .heroSectionContainer()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .background(WizardDesign.Colors.wizardBackground)
        .wizardDetailPage()
    }

    // MARK: - Helper Methods

    private var hasKarabinerIssues: Bool {
        // Use centralized evaluator (single source of truth)
        KarabinerComponentsStatusEvaluator.evaluate(
            systemState: systemState,
            issues: issues
        ) != .completed
    }

    private var nextStepButtonTitle: String {
        issues.isEmpty ? "Return to Summary" : "Next Issue"
    }

    private var karabinerRelatedIssues: [WizardIssue] {
        // Use centralized evaluator (single source of truth)
        KarabinerComponentsStatusEvaluator.getKarabinerRelatedIssues(from: issues)
    }

    private func componentStatus(for component: KarabinerComponent) -> InstallationStatus {
        // Use centralized evaluator for individual components (single source of truth)
        KarabinerComponentsStatusEvaluator.getIndividualComponentStatus(
            component,
            in: issues
        )
    }

    private var needsManualAction: Bool {
        componentStatus(for: .backgroundServices) == .failed
    }

    private func navigateToNextStep() {
        if issues.isEmpty {
            navigationCoordinator.navigateToPage(.summary)
            return
        }

        Task {
            if let nextPage = await navigationCoordinator.getNextPage(for: systemState, issues: issues),
               nextPage != navigationCoordinator.currentPage
            {
                navigationCoordinator.navigateToPage(nextPage)
            } else {
                navigationCoordinator.navigateToPage(.summary)
            }
        }
    }

    private func getComponentTitle(for issue: WizardIssue) -> String {
        switch issue.title {
        case "VirtualHIDDevice Manager Not Activated":
            "VirtualHIDDevice Manager"
        case "VirtualHIDDevice Daemon":
            "VirtualHIDDevice Daemon"
        case "VirtualHIDDevice Daemon Misconfigured":
            "VirtualHIDDevice Daemon Configuration"
        case "LaunchDaemon Services Not Installed":
            "LaunchDaemon Services"
        case "LaunchDaemon Services Failing":
            "LaunchDaemon Services"
        case "Karabiner Daemon Not Running":
            "Karabiner Daemon"
        case "Driver Extension Disabled":
            "Driver Extension"
        case "Background Services Disabled":
            "Login Items"
        default:
            issue.title
        }
    }

    private func getComponentDescription(for issue: WizardIssue) -> String {
        switch issue.title {
        case "VirtualHIDDevice Manager Not Activated":
            "The VirtualHIDDevice Manager needs to be activated for virtual HID functionality"
        case "VirtualHIDDevice Daemon":
            "Virtual keyboard driver daemon processes required for input capture"
        case "VirtualHIDDevice Daemon Misconfigured":
            "The installed LaunchDaemon points to a legacy path and needs updating"
        case "LaunchDaemon Services Not Installed":
            "System launch services for VirtualHIDDevice daemon and manager"
        case "LaunchDaemon Services Failing":
            "LaunchDaemon services are loaded but crashing or failing and need to be restarted"
        case "Karabiner Daemon Not Running":
            "The Karabiner Virtual HID Device Daemon needs to be running"
        case "Driver Extension Disabled":
            "Karabiner driver extension needs to be enabled in System Settings"
        case "Background Services Disabled":
            "Karabiner services need to be added to Login Items for automatic startup"
        default:
            issue.description
        }
    }

    private func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Smart Fix Handlers

    /// Smart handler for Karabiner Driver Fix button
    /// Detects if Karabiner is installed vs needs installation
    private func handleCombinedFix() {
        guard !isCombinedFixLoading else {
            AppLogger.shared.log("⚠️ [Karabiner Fix] handleCombinedFix() skipped - already loading")
            return
        }
        AppLogger.shared.log("🔧 [Karabiner Fix] handleCombinedFix() START")
        isCombinedFixLoading = true
        actionStatus = .inProgress(message: "Preparing...")

        // Subscribe to step progress updates from VHIDDeviceManager
        stepProgressCancellable = VHIDDeviceManager.stepProgress
            .receive(on: DispatchQueue.main)
            .sink { [self] step in
                actionStatus = .inProgress(message: step)
            }

        let isInstalled = kanataManager.isKarabinerDriverInstalled()
        AppLogger.shared.log("🔧 [Karabiner Fix] isKarabinerDriverInstalled=\(isInstalled)")

        Task { @MainActor in
            defer {
                stepProgressCancellable?.cancel()
                stepProgressCancellable = nil
                isCombinedFixLoading = false
                AppLogger.shared.log("🔧 [Karabiner Fix] handleCombinedFix() END - spinner released")
            }

            // 1) Driver install/repair (always if missing, repair if unhealthy)
            if isInstalled {
                AppLogger.shared.log(
                    "🔧 [Karabiner Fix] Driver installed but having issues - attempting repair")
                AppLogger.shared.log("🔧 [Karabiner Fix] Calling performAutomaticDriverRepair()...")
                _ = await performAutomaticDriverRepair()
                AppLogger.shared.log("🔧 [Karabiner Fix] performAutomaticDriverRepair() returned")
            } else {
                AppLogger.shared.log(
                    "🔧 [Karabiner Fix] Driver not installed - attempting automatic install via helper (up to 2 attempts)"
                )
                AppLogger.shared.log("🔧 [Karabiner Fix] Calling attemptAutoInstallDriver()...")
                let ok = await attemptAutoInstallDriver(maxAttempts: 2)
                AppLogger.shared.log("🔧 [Karabiner Fix] attemptAutoInstallDriver() returned \(ok)")
                if !ok {
                    actionStatus = .error(
                        message: "Driver installation failed. Check System Settings > Privacy & Security."
                    )
                    AppLogger.shared.log("🔧 [Karabiner Fix] Install failed - returning early")
                    return
                }
            }

            // 2) Services repair/install (only if driver succeeded or already healthy)
            let driverHealthy = componentStatus(for: .driver) == .completed
            AppLogger.shared.log("🔧 [Karabiner Fix] driverHealthy=\(driverHealthy), checking service repair...")
            if driverHealthy {
                AppLogger.shared.log("🔧 [Karabiner Fix] Calling performAutomaticServiceRepair()...")
                _ = await performAutomaticServiceRepair()
                AppLogger.shared.log("🔧 [Karabiner Fix] performAutomaticServiceRepair() returned")
            }
            AppLogger.shared.log("🔧 [Karabiner Fix] All fix steps complete, defer will release spinner")
            // Note: Both performAutomaticDriverRepair() and performAutomaticServiceRepair()
            // call refreshAndWait() internally, so we don't need to call it again here.
        }
    }

    /// Try helper-based driver installation up to N attempts before falling back to manual sheet
    @MainActor
    private func attemptAutoInstallDriver(maxAttempts: Int) async -> Bool {
        let attempts = max(1, maxAttempts)
        for i in 1 ... attempts {
            AppLogger.shared.log("🧪 [Karabiner Fix] Auto-install attempt #\(i)")
            let ok = await performAutoFix(.installCorrectVHIDDriver)
            if ok { return true }
            // Small delay before retry to allow systemextensionsctl to settle
            _ = await WizardSleep.ms(200)
        }

        // If installation failed but SMAppService is merely awaiting approval, prompt the user
        // instead of sending them to the manual Karabiner-Elements flow (which is for true install failures).
        let smState = await KanataDaemonManager.shared.refreshManagementState()
        if smState == .smappservicePending {
            AppLogger.shared.log(
                "💡 [Karabiner Fix] Auto-install blocked by SMAppService approval; prompting user instead of showing manual guide"
            )
            toastApprovalNeeded()
            return true // Do not treat as fatal failure
        }

        return false
    }

    private func toastApprovalNeeded() {
        if let nav = NSApplication.shared.keyWindow {
            nav.makeKeyAndOrderFront(nil)
        }
        Task { @MainActor in
            AppLogger.shared.log("💡 [Karabiner Fix] Showing approval-needed toast for Login Items")
            openLoginItemsSettings()
        }
    }

    // Smart handler for Background Services Fix button. Attempts repair first, falls back to system settings.
    // Legacy handlers removed in favor of combined flow.

    /// Attempts automatic repair of Karabiner driver issues
    private func performAutomaticDriverRepair() async -> Bool {
        // Fix Session envelope for traceability
        let session = UUID().uuidString
        let t0 = Date()
        AppLogger.shared.log("🧭 [FIX-VHID \(session)] START Karabiner driver repair")

        // Determine issues involved
        let vhidIssues = issues.filter(\.identifier.isVHIDRelated)
        AppLogger.shared.log(
            "🧭 [FIX-VHID \(session)] Issues: \(vhidIssues.map { String(describing: $0.identifier) }.joined(separator: ", "))"
        )

        var success = false

        // Always fix version mismatch and daemon misconfig first (structural), then perform a verified restart.
        if vhidIssues.contains(where: { $0.identifier == .component(.vhidDriverVersionMismatch) }) {
            AppLogger.shared.log("🧭 [FIX-VHID \(session)] Action: fixDriverVersionMismatch")
            success = await performAutoFix(.fixDriverVersionMismatch)
        } else if vhidIssues.contains(where: { $0.identifier == .component(.vhidDaemonMisconfigured) }) {
            AppLogger.shared.log("🧭 [FIX-VHID \(session)] Action: repairVHIDDaemonServices")
            success = await performAutoFix(.repairVHIDDaemonServices)
        } else if vhidIssues.contains(where: { $0.identifier == .component(.launchDaemonServices) }) {
            AppLogger.shared.log("🧭 [FIX-VHID \(session)] Action: installLaunchDaemonServices")
            success = await performAutoFix(.installLaunchDaemonServices)
        }

        // Always run a verified restart last to ensure single-owner state
        AppLogger.shared.log("🧭 [FIX-VHID \(session)] Action: restartVirtualHIDDaemon (verified)")
        let restartOk = await performAutoFix(.restartVirtualHIDDaemon)
        success = success || restartOk

        // Post-repair diagnostic
        let detail = await kanataManager.getVirtualHIDBreakageSummary()
        AppLogger.shared.log("🧭 [FIX-VHID \(session)] Diagnostic after repair:\n\(detail)")

        let elapsed = String(format: "%.3f", Date().timeIntervalSince(t0))
        AppLogger.shared.log("🧭 [FIX-VHID \(session)] END (success=\(success)) in \(elapsed)s")

        if success {
            // Run a fresh validation before leaving the page to avoid stale summary red states.
            await refreshAndWait(fixSucceeded: true)
            actionStatus = .success(message: "Driver repair succeeded")
            scheduleStatusClear()
        } else {
            actionStatus = .error(message: "Driver repair failed. Try restarting your Mac.")
        }
        return success
    }

    /// Auto-clear success status after 3 seconds
    private func scheduleStatusClear() {
        Task { @MainActor in
            _ = await WizardSleep.seconds(3)
            if case .success = actionStatus {
                actionStatus = .idle
            }
        }
    }

    /// Attempts automatic repair of background services
    private func performAutomaticServiceRepair() async -> Bool {
        AppLogger.shared.log("🔧 [Service Repair] Installing/repairing LaunchDaemon services")
        let success = await performAutoFix(.installLaunchDaemonServices)

        if success {
            AppLogger.shared.log("✅ [Service Repair] Service repair succeeded")
            await refreshAndWait(fixSucceeded: true)
            actionStatus = .success(message: "Service repair succeeded")
            scheduleStatusClear()
        } else {
            AppLogger.shared.log("❌ [Service Repair] Service repair failed - opening system settings")
            actionStatus = .error(message: "Service repair failed. Opening System Settings…")
            openLoginItemsSettings()
        }
        return success
    }

    /// Perform auto-fix using the wizard's auto-fix capability (suppresses toasts - uses inline status)
    private func performAutoFix(_ action: AutoFixAction) async -> Bool {
        await onAutoFix(action, true) // suppressToast=true, page handles inline status
    }

    /// Refresh wizard state and wait for completion before returning control to caller UI.
    /// - Parameter fixSucceeded: Whether the preceding fix operation succeeded. Service restart
    ///   is only attempted if this is true, to avoid masking failures.
    @MainActor
    private func refreshAndWait(fixSucceeded: Bool) async {
        let t0 = Date()
        AppLogger.shared.log("🔄 [Karabiner Fix] refreshAndWait() starting (fixSucceeded=\(fixSucceeded))")

        // Show verification status inline
        actionStatus = .inProgress(message: "Verifying installation...")

        // Trigger async state detection via the wizard's refresh callback.
        let versionBefore = stateManager.stateVersion
        onRefresh()

        // Wait for state detection to complete by polling stateVersion.
        // This is more deterministic than an arbitrary sleep.
        let refreshDeadline = Date().addingTimeInterval(stateRefreshTimeoutSeconds)
        while stateManager.stateVersion == versionBefore, Date() < refreshDeadline {
            await Task.yield()
            _ = await WizardSleep.ms(20) // 20ms polling interval
        }

        let refreshElapsed = String(format: "%.2f", Date().timeIntervalSince(t0))
        let refreshCompleted = stateManager.stateVersion != versionBefore
        AppLogger.shared.log("🔄 [Karabiner Fix] State refresh \(refreshCompleted ? "completed" : "timed out") after \(refreshElapsed)s")

        // Check if service is already running - if so, we're done.
        let serviceState = await kanataManager.currentServiceState()
        if serviceState.isRunning {
            let totalElapsed = String(format: "%.2f", Date().timeIntervalSince(t0))
            AppLogger.shared.log("🔄 [Karabiner Fix] refreshAndWait() completed - service already running (elapsed=\(totalElapsed)s)")
            return
        }

        // Only attempt restart if the preceding fix succeeded.
        // This avoids masking failures by trying to restart a broken installation.
        guard fixSucceeded else {
            let totalElapsed = String(format: "%.2f", Date().timeIntervalSince(t0))
            AppLogger.shared.log("🔄 [Karabiner Fix] refreshAndWait() skipping restart - fix did not succeed (elapsed=\(totalElapsed)s)")
            return
        }

        let totalElapsed = String(format: "%.2f", Date().timeIntervalSince(t0))
        AppLogger.shared.log("✅ [Karabiner Fix] refreshAndWait() completed (elapsed=\(totalElapsed)s)")
    }
}
