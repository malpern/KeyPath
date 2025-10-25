import SwiftUI

/// Karabiner driver and virtual HID components setup page
struct WizardKarabinerComponentsPage: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let isFixing: Bool
    let onAutoFix: (AutoFixAction) async -> Bool
    let onRefresh: () -> Void
    let kanataManager: KanataManager

    // Track which specific issues are being fixed
    @State private var fixingIssues: Set<UUID> = []
    @State private var showingInstallationGuide = false
    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator

    var body: some View {
        VStack(spacing: 0) {
            // Use experimental hero design when driver is installed
            if !hasKarabinerIssues {
                VStack(spacing: 0) {
                    Spacer()

                    // Centered hero block with padding
                    VStack(spacing: WizardDesign.Spacing.sectionGap) {
                        // Green keyboard icon with green check overlay
                        ZStack {
                            Image(systemName: "keyboard.macwindow")
                                .font(.system(size: 115, weight: .light))
                                .foregroundColor(WizardDesign.Colors.success)
                                .symbolRenderingMode(.hierarchical)
                                .modifier(AvailabilitySymbolBounce())

                            // Green check overlay hanging off right edge
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 40, weight: .medium))
                                        .foregroundColor(WizardDesign.Colors.success)
                                        .background(WizardDesign.Colors.wizardBackground)
                                        .clipShape(Circle())
                                        .offset(x: 15, y: -5) // Hang off the right edge
                                }
                                Spacer()
                            }
                            .frame(width: 115, height: 115)
                        }

                        // Headline
                        Text("Karabiner Driver")
                            .font(.system(size: 23, weight: .semibold, design: .default))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        // Subtitle
                        Text("Virtual keyboard driver is installed & configured for input capture")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)

                        // Component details card below the subheading - horizontally centered
                        HStack {
                            Spacer()
                            VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
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

                                HStack(spacing: 12) {
                                    Image(systemName: componentStatus(for: .backgroundServices) == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(componentStatus(for: .backgroundServices) == .completed ? .green : .red)
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
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(WizardDesign.Spacing.cardPadding)
                        .background(Color.clear, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, WizardDesign.Spacing.pageVertical)
                        .padding(.top, WizardDesign.Spacing.sectionGap)
                    }
                    .padding(.vertical, WizardDesign.Spacing.pageVertical)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Use hero design for error state too, with blue links below
                VStack(spacing: 0) {
                    Spacer()

                    // Centered hero block with padding
                    VStack(spacing: WizardDesign.Spacing.sectionGap) {
                        // Orange keyboard icon with warning overlay
                        ZStack {
                            Image(systemName: "keyboard.macwindow")
                                .font(.system(size: 115, weight: .light))
                                .foregroundColor(WizardDesign.Colors.warning)
                                .symbolRenderingMode(.hierarchical)
                                .modifier(AvailabilitySymbolBounce())

                            // Warning overlay hanging off right edge
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 40, weight: .medium))
                                        .foregroundColor(WizardDesign.Colors.warning)
                                        .background(WizardDesign.Colors.wizardBackground)
                                        .clipShape(Circle())
                                        .offset(x: 15, y: -5) // Hang off the right edge
                                }
                                Spacer()
                            }
                            .frame(width: 115, height: 115)
                        }

                        // Headline
                        Text("Karabiner Driver Required")
                            .font(.system(size: 23, weight: .semibold, design: .default))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        // Subtitle
                        Text("Karabiner virtual keyboard driver needs to be installed & configured for input capture")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)

                        // Component details for error state
                        VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                            HStack(spacing: 12) {
                                HStack(spacing: 12) {
                                    Image(systemName: componentStatus(for: .driver) == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(componentStatus(for: .driver) == .completed ? .green : .red)
                                    HStack(spacing: 0) {
                                        Text("Karabiner Driver")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                        Text(" - Virtual keyboard driver")
                                            .font(.headline)
                                            .fontWeight(.regular)
                                    }
                                }
                                .contentShape(Rectangle())
                                .help(driverIssues.asTooltipText())

                                Spacer()
                                if componentStatus(for: .driver) != .completed {
                                    Button("Fix") {
                                        handleKarabinerDriverFix()
                                    }
                                    .buttonStyle(WizardDesign.Component.SecondaryButton())
                                    .scaleEffect(0.8)
                                }
                            }

                            HStack(spacing: 12) {
                                HStack(spacing: 12) {
                                    Image(systemName: componentStatus(for: .backgroundServices) == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(componentStatus(for: .backgroundServices) == .completed ? .green : .red)
                                    HStack(spacing: 0) {
                                        Text("Background Services")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                        Text(" - Login Items for automatic startup")
                                            .font(.headline)
                                            .fontWeight(.regular)
                                    }
                                }
                                .contentShape(Rectangle())
                                .help(backgroundServicesIssues.asTooltipText())

                                Spacer()
                                if componentStatus(for: .backgroundServices) != .completed {
                                    Button("Fix") {
                                        handleBackgroundServicesFix()
                                    }
                                    .buttonStyle(WizardDesign.Component.SecondaryButton())
                                    .scaleEffect(0.8)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(WizardDesign.Spacing.cardPadding)
                        .background(Color.clear, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, WizardDesign.Spacing.pageVertical)
                        .padding(.top, WizardDesign.Spacing.sectionGap)

                        // Check Status link
                        Button("Check Status") {
                            Task {
                                onRefresh()
                            }
                        }
                        .buttonStyle(.link)
                        .padding(.top, WizardDesign.Spacing.elementGap)
                    }
                    .padding(.vertical, WizardDesign.Spacing.pageVertical)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer()

            // Bottom buttons - primary action changes based on state
            HStack {
                Spacer()

                if hasKarabinerIssues {
                    // When issues exist, continue anyway as secondary
                    Button("Continue Anyway") {
                        AppLogger.shared.log("ℹ️ [Wizard] User continuing from Karabiner Components page despite issues")
                        navigateToNextPage()
                    }
                    .buttonStyle(WizardDesign.Component.SecondaryButton())
                } else {
                    // When all components are working, Continue is primary
                    Button("Continue") {
                        AppLogger.shared.log("ℹ️ [Wizard] User continuing from Karabiner Components page")
                        navigateToNextPage()
                    }
                    .buttonStyle(WizardDesign.Component.PrimaryButton())
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, WizardDesign.Spacing.sectionGap)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WizardDesign.Colors.wizardBackground)
        .sheet(isPresented: $showingInstallationGuide) {
            KarabinerInstallationGuideSheet(kanataManager: kanataManager)
        }
    }

    // MARK: - Helper Methods

    private var hasKarabinerIssues: Bool {
        // Use centralized evaluator (single source of truth)
        KarabinerComponentsStatusEvaluator.evaluate(
            systemState: systemState,
            issues: issues
        ) != .completed
    }

    private func navigateToNextPage() {
        let allPages = WizardPage.allCases
        guard let currentIndex = allPages.firstIndex(of: navigationCoordinator.currentPage),
              currentIndex < allPages.count - 1
        else { return }
        let nextPage = allPages[currentIndex + 1]
        navigationCoordinator.navigateToPage(nextPage)
        AppLogger.shared.log("➡️ [Karabiner Components] Navigated to next page: \(nextPage.displayName)")
    }

    private var karabinerRelatedIssues: [WizardIssue] {
        // Use centralized evaluator (single source of truth)
        return KarabinerComponentsStatusEvaluator.getKarabinerRelatedIssues(from: issues)
    }

    private var driverIssues: [WizardIssue] {
        // Filter for driver-related issues (VHID, driver extension, etc.)
        let filtered = issues.filter { issue in
            issue.category == .installation && issue.identifier.isVHIDRelated
        }

        // Debug logging to understand tooltip behavior
        if componentStatus(for: .driver) != .completed {
            AppLogger.shared.log("🔍 [Karabiner Page] Driver has failed status but driverIssues.count = \(filtered.count)")
            AppLogger.shared.log("🔍 [Karabiner Page] All issues: \(issues.map { "[\($0.category)] \($0.title)" }.joined(separator: ", "))")
        }

        return filtered
    }

    private var backgroundServicesIssues: [WizardIssue] {
        // Filter for background services issues
        return issues.filter { issue in
            issue.category == .backgroundServices
        }
    }

    private func componentStatus(for component: KarabinerComponent) -> InstallationStatus {
        // Use centralized evaluator for individual components (single source of truth)
        return KarabinerComponentsStatusEvaluator.getIndividualComponentStatus(
            component,
            in: issues
        )
    }

    private var needsManualAction: Bool {
        componentStatus(for: .backgroundServices) == .failed
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
    private func handleKarabinerDriverFix() {
        let isInstalled = kanataManager.isKarabinerDriverInstalled()

        if isInstalled {
            // Karabiner is installed but having issues - attempt automatic repair
            AppLogger.shared.log("🔧 [Karabiner Fix] Driver installed but having issues - attempting repair")
            performAutomaticDriverRepair()
        } else {
            // Karabiner not installed - use automated installation
            AppLogger.shared.log("🔧 [Karabiner Fix] Driver not installed - starting automated installation")
            performAutomaticDriverInstallation()
        }
    }
    
    /// Smart handler for Background Services Fix button  
    /// Attempts repair first, falls back to system settings
    private func handleBackgroundServicesFix() {
        let isInstalled = kanataManager.isKarabinerDriverInstalled()
        
        if isInstalled {
            // Try automatic repair first
            AppLogger.shared.log("🔧 [Background Services Fix] Attempting automatic service repair")
            performAutomaticServiceRepair()
        } else {
            // No driver installed - open system settings for manual configuration
            AppLogger.shared.log("💡 [Background Services Fix] No driver - opening Login Items settings")
            openLoginItemsSettings()
        }
    }
    
    /// Attempts automatic repair of Karabiner driver issues
    private func performAutomaticDriverRepair() {
        Task { @MainActor in
            // Use the wizard's auto-fix capability
            
            // Check what specific issues we need to fix
            let vhidIssues = issues.filter { issue in
                issue.identifier.isVHIDRelated
            }
            
            var success = false

            // ⭐ Check for driver version mismatch FIRST (root cause of other issues)
            if vhidIssues.contains(where: { $0.identifier == .component(.vhidDriverVersionMismatch) }) {
                // Fix driver version mismatch
                AppLogger.shared.log("🔧 [Driver Repair] Fixing driver version mismatch (v6 → v5)")
                success = await performAutoFix(.fixDriverVersionMismatch)
            } else if vhidIssues.contains(where: { $0.identifier == .component(.vhidDaemonMisconfigured) }) {
                // Fix misconfigured daemon plist
                AppLogger.shared.log("🔧 [Driver Repair] Repairing misconfigured VHID daemon services")
                success = await performAutoFix(.repairVHIDDaemonServices)
            } else if vhidIssues.contains(where: { $0.identifier == .component(.launchDaemonServices) }) {
                // Install missing services
                AppLogger.shared.log("🔧 [Driver Repair] Installing missing LaunchDaemon services")
                success = await performAutoFix(.installLaunchDaemonServices)
            } else {
                // General VHID issues - try restarting daemon
                AppLogger.shared.log("🔧 [Driver Repair] Restarting VirtualHID daemon")
                success = await performAutoFix(.restartVirtualHIDDaemon)
            }
            
            if success {
                AppLogger.shared.log("✅ [Driver Repair] Automatic repair succeeded - refreshing status")
                // Trigger status refresh
                onRefresh()
            } else {
                AppLogger.shared.log("❌ [Driver Repair] Automatic repair failed - showing installation guide")
                showingInstallationGuide = true
            }
        }
    }
    
    /// Attempts automatic repair of background services
    private func performAutomaticServiceRepair() {
        Task { @MainActor in
            // Use the wizard's auto-fix capability

            AppLogger.shared.log("🔧 [Service Repair] Installing/repairing LaunchDaemon services")
            let success = await performAutoFix(.installLaunchDaemonServices)

            if success {
                AppLogger.shared.log("✅ [Service Repair] Service repair succeeded - refreshing status")
                onRefresh()
            } else {
                AppLogger.shared.log("❌ [Service Repair] Service repair failed - opening system settings")
                openLoginItemsSettings()
            }
        }
    }

    /// Performs automated VirtualHID driver installation
    /// Downloads, installs, and activates the driver without user intervention
    private func performAutomaticDriverInstallation() {
        Task { @MainActor in
            AppLogger.shared.log("🔧 [Driver Installation] Starting automated VirtualHID driver installation")

            // Show confirmation dialog
            let alert = NSAlert()
            alert.messageText = "Install VirtualHID Driver"
            alert.informativeText = """
            KeyPath needs the Karabiner VirtualHIDDevice driver (v5.0.0) for keyboard remapping.

            This will:
            • Download the standalone driver (~2MB)
            • Install and activate it
            • Restart the keyboard remapping service

            You do NOT need to install Karabiner-Elements.
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Download & Install")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else {
                AppLogger.shared.log("ℹ️ [Driver Installation] User cancelled installation")
                return
            }

            // Use the existing auto-fix action for driver installation
            // (works for both version mismatch AND missing driver scenarios)
            let success = await performAutoFix(.fixDriverVersionMismatch)

            if success {
                AppLogger.shared.log("✅ [Driver Installation] Driver installed successfully - restarting Kanata")

                // Restart Kanata service to connect to the newly installed driver
                await kanataManager.restartKanata()

                // Give the service a moment to start
                try? await Task.sleep(nanoseconds: 2_000_000_000)

                // Refresh wizard status
                onRefresh()

                AppLogger.shared.log("✅ [Driver Installation] Complete - Kanata restarted")
            } else {
                AppLogger.shared.log("❌ [Driver Installation] Failed - showing manual installation guide")
                showingInstallationGuide = true
            }
        }
    }

    /// Perform auto-fix using the wizard's auto-fix capability
    private func performAutoFix(_ action: AutoFixAction) async -> Bool {
        return await onAutoFix(action)
    }
}
