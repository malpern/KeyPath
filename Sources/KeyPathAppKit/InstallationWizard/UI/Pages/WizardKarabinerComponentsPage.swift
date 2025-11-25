import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Karabiner driver and virtual HID components setup page
struct WizardKarabinerComponentsPage: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let isFixing: Bool
    let onAutoFix: (AutoFixAction) async -> Bool
    let onRefresh: () -> Void
    let kanataManager: RuntimeCoordinator

    // Track which specific issues are being fixed
    @State private var fixingIssues: Set<UUID> = []
    @State private var lastDriverFixNote: String?
    @State private var lastServiceFixNote: String?
    @State private var showAllItems = false
    @State private var isCombinedFixLoading = false
    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator
    @EnvironmentObject var toastManager: WizardToastManager

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

                    // Component details card below the subheading - horizontally centered
                    HStack {
                        Spacer()
                        VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                            // Show Karabiner Driver only if showAllItems OR if it has issues (defensive)
                            if showAllItems {
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
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
                                    .foregroundColor(
                                        componentStatus(for: .backgroundServices) == .completed ? .green : .red)
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
                    .padding(.top, WizardDesign.Spacing.sectionGap)
                }
                .heroSectionContainer()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Use hero design for error state too, with blue links below
                VStack(spacing: WizardDesign.Spacing.sectionGap) {
                    WizardHeroSection.warning(
                        icon: "keyboard.macwindow",
                        title: "Karabiner Driver Required",
                        subtitle:
                        "Karabiner virtual keyboard driver needs to be installed & configured for input capture",
                        iconTapAction: {
                            showAllItems.toggle()
                            Task {
                                onRefresh()
                            }
                        }
                    )

                    // Component details for error state
                    VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                        // Combined row for Driver + Services
                        if showAllItems || componentStatus(for: .driver) != .completed
                            || componentStatus(for: .backgroundServices) != .completed
                        {
                            HStack(spacing: 12) {
                                Image(
                                    systemName: combinedStatus == .completed
                                        ? "checkmark.circle.fill" : "xmark.circle.fill"
                                )
                                .foregroundColor(combinedStatus == .completed ? .green : .red)
                                HStack(spacing: 0) {
                                    Text("Karabiner Driver & Services")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                    Text(" - Virtual keyboard driver and Login Items")
                                        .font(.headline)
                                        .fontWeight(.regular)
                                }
                                Spacer()
                                if combinedStatus != .completed {
                                    Button("Fix") {
                                        handleCombinedFix()
                                    }
                                    .buttonStyle(
                                        WizardDesign.Component.SecondaryButton(isLoading: isCombinedFixLoading))
                                    .scaleEffect(0.8)
                                    .disabled(isCombinedFixLoading)
                                }
                            }
                            .help(combinedTooltipText)

                            if let note = combinedNote, combinedStatus != .completed {
                                Text("Last fix: \(note)")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 28)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(WizardDesign.Spacing.cardPadding)
                    .background(Color.clear, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, WizardDesign.Spacing.pageVertical)
                    .padding(.top, WizardDesign.Spacing.sectionGap)
                }
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

    private var driverIssues: [WizardIssue] {
        issues.filter { issue in
            issue.category == .installation && issue.identifier.isVHIDRelated
        }
    }

    private var backgroundServicesIssues: [WizardIssue] {
        issues.filter { issue in
            issue.category == .backgroundServices
        }
    }

    private var combinedStatus: InstallationStatus {
        // If either driver or services failed, show failed; else if any incomplete, show pending
        let driverStatus = componentStatus(for: .driver)
        let serviceStatus = componentStatus(for: .backgroundServices)

        if driverStatus == .failed || serviceStatus == .failed {
            return .failed
        }
        if driverStatus == .completed, serviceStatus == .completed {
            return .completed
        }
        return .inProgress
    }

    private var combinedNote: String? {
        // Prefer latest note (services > driver)
        lastServiceFixNote ?? lastDriverFixNote
    }

    private var combinedTooltipText: String {
        var parts: [String] = []
        if !driverIssues.isEmpty {
            parts.append("Driver: \(driverIssues.asTooltipText())")
        }
        if !backgroundServicesIssues.isEmpty {
            parts.append("Services: \(backgroundServicesIssues.asTooltipText())")
        }
        return parts.isEmpty ? "No issues detected" : parts.joined(separator: "\n")
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

        if let nextPage = navigationCoordinator.getNextPage(for: systemState, issues: issues),
           nextPage != navigationCoordinator.currentPage
        {
            navigationCoordinator.navigateToPage(nextPage)
        } else {
            navigationCoordinator.navigateToPage(.summary)
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
        guard !isCombinedFixLoading else { return }
        isCombinedFixLoading = true
        let isInstalled = kanataManager.isKarabinerDriverInstalled()

        Task { @MainActor in
            defer { isCombinedFixLoading = false }

            // 1) Driver install/repair (always if missing, repair if unhealthy)
            if isInstalled {
                AppLogger.shared.log(
                    "🔧 [Karabiner Fix] Driver installed but having issues - attempting repair")
                let ok = await performAutomaticDriverRepair()
                if ok {
                    lastDriverFixNote = formattedStatus(success: true)
                } else {
                    lastDriverFixNote = formattedStatus(success: false)
                }
            } else {
                AppLogger.shared.log(
                    "🔧 [Karabiner Fix] Driver not installed - attempting automatic install via helper (up to 2 attempts)"
                )
                let ok = await attemptAutoInstallDriver(maxAttempts: 2)
                lastDriverFixNote = formattedStatus(success: ok)
                if !ok {
                    toastManager.showError(
                        "Driver installation failed. Check System Settings > Privacy & Security."
                    )
                    return
                }
            }

            // 2) Services repair/install (only if driver succeeded or already healthy)
            let driverHealthy = componentStatus(for: .driver) == .completed
            if driverHealthy {
                let serviceOk = await performAutomaticServiceRepair()
                lastServiceFixNote = formattedStatus(success: serviceOk)
            } else {
                lastServiceFixNote = formattedStatus(success: false)
            }

            await refreshAndWait()
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
            try? await Task.sleep(nanoseconds: 400_000_000)
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

    private func formattedStatus(success: Bool) -> String {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        return success ? "succeeded at \(ts)" : "failed at \(ts) — see Logs"
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
        let detail = kanataManager.getVirtualHIDBreakageSummary()
        AppLogger.shared.log("🧭 [FIX-VHID \(session)] Diagnostic after repair:\n\(detail)")

        let elapsed = String(format: "%.3f", Date().timeIntervalSince(t0))
        AppLogger.shared.log("🧭 [FIX-VHID \(session)] END (success=\(success)) in \(elapsed)s")

        if success {
            // Run a fresh validation synchronously before leaving the page to avoid stale summary red states.
            Task {
                await refreshAndWait()
            }
        } else {
            toastManager.showError(
                "Driver repair failed. Try restarting your Mac."
            )
        }
        return success
    }

    /// Attempts automatic repair of background services
    private func performAutomaticServiceRepair() async -> Bool {
        AppLogger.shared.log("🔧 [Service Repair] Installing/repairing LaunchDaemon services")
        let success = await performAutoFix(.installLaunchDaemonServices)

        if success {
            AppLogger.shared.log("✅ [Service Repair] Service repair succeeded")
            await refreshAndWait()
        } else {
            AppLogger.shared.log("❌ [Service Repair] Service repair failed - opening system settings")
            openLoginItemsSettings()
        }
        return success
    }

    /// Perform auto-fix using the wizard's auto-fix capability
    private func performAutoFix(_ action: AutoFixAction) async -> Bool {
        await onAutoFix(action)
    }

    /// Refresh wizard state and wait for completion before returning control to caller UI.
    @MainActor
    private func refreshAndWait() async {
        // Bridge the existing synchronous callback into an async confirmation by invoking and then
        // yielding to the runloop briefly. The underlying refresh path updates wizard state via
        // WizardStateManager → InstallerEngine → SystemValidator.
        onRefresh()
        // Give the refresh task a short window to complete before the user is bounced to summary.
        // This avoids showing stale red items when the fix actually succeeded.
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms

        // If everything else is healthy but the service isn’t running yet, try to start it now so
        // the summary doesn’t bounce back with a “Start Kanata Service” error.
        let serviceState = await kanataManager.currentServiceState()
        guard !serviceState.isRunning else {
            return
        }

        AppLogger.shared.log("🔄 [Karabiner Fix] Post-fix: Kanata not running, attempting restart via KanataService")
        let restarted = await kanataManager.restartServiceWithFallback(reason: "Wizard driver/service repair follow-up")

        if !restarted {
            AppLogger.shared.warn("⚠️ [Karabiner Fix] Post-fix restart failed - service may still be inactive")
        }
    }
}
