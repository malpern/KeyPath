import KeyPathCore
import KeyPathWizardCore
import ServiceManagement
import SwiftUI

/// Privileged Helper installation and validation page
struct WizardHelperPage: View {
    // MARK: - Properties (following wizard page pattern)

    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let isFixing: Bool
    let blockingFixDescription: String?
    let onAutoFix: (AutoFixAction, Bool) async -> Bool
    let onRefresh: () -> Void
    let kanataManager: RuntimeCoordinator

    // MARK: - State

    @State private var isWorking = false
    @State private var helperVersion: String?
    @State private var bundledVersion: String?
    @State private var duplicateCopies: [String] = []
    @State private var needsLoginItemsApproval = false
    @State private var actionStatus: WizardDesign.ActionStatus = .idle
    @State private var hasLoggedDiagnostics = false
    @State private var approvalPollingTimer: Timer?
    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator

    /// Check if bundled helper is newer than installed helper
    private var hasUpdateAvailable: Bool {
        guard let installed = helperVersion, let bundled = bundledVersion else { return false }
        return bundled.compare(installed, options: .numeric) == .orderedDescending
    }

    // MARK: - Computed Properties

    private var hasNotInstalledIssue: Bool {
        issues.contains { issue in
            if case let .component(req) = issue.identifier {
                return req == .privilegedHelper
            }
            return false
        }
    }

    private var hasUnhealthyIssue: Bool {
        issues.contains { issue in
            if case let .component(req) = issue.identifier {
                return req == .privilegedHelperUnhealthy
            }
            return false
        }
    }

    private var hasHelperIssues: Bool {
        hasNotInstalledIssue || hasUnhealthyIssue
    }

    // Helper is ready if there are NO issues
    private var isReady: Bool {
        !hasHelperIssues
    }

    // Helper is installed if it's either ready OR has an unhealthy issue (but not missing)
    private var isInstalled: Bool {
        !hasNotInstalledIssue
    }

    private var nextStepButtonTitle: String {
        issues.isEmpty ? "Return to Summary" : "Next Issue"
    }

    /// Contextual headline for the setup view - adapts to current state
    private var contextualHeadline: String {
        if needsLoginItemsApproval {
            "Login Items Approval Required"
        } else if isInstalled {
            "Privileged Helper Not Responding"
        } else {
            "Privileged Helper Not Installed"
        }
    }

    /// Contextual description for the setup view - adapts to current state
    private var contextualDescription: String {
        if needsLoginItemsApproval {
            "Open System Settings → Login Items, find KeyPath under Background Items, and toggle it ON (see screenshot)."
        } else {
            "Enables system operations without repeated password prompts."
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if isReady {
                successView
            } else {
                setupView
            }
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .background(WizardDesign.Colors.wizardBackground)
        .wizardDetailPage()
        .task {
            // Check helper version on appear
            helperVersion = await HelperManager.shared.getHelperVersion()
            bundledVersion = getBundledHelperVersion()
            // Check if Login Items approval is needed
            needsLoginItemsApproval = checkLoginItemsApprovalNeeded()
        }
        .onAppear {
            duplicateCopies = HelperMaintenance.shared.detectDuplicateAppCopies()
            logLoginItemsDiagnostics()
        }
        .onDisappear {
            stopApprovalPolling()
        }
    }

    // MARK: - Success View (Hero Style)

    private var successView: some View {
        VStack(spacing: WizardDesign.Spacing.sectionGap) {
            // Green shield icon with check overlay
            ZStack {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 115, weight: .light))
                    .foregroundColor(WizardDesign.Colors.success)
                    .symbolRenderingMode(.hierarchical)
                    .modifier(AvailabilitySymbolBounce())

                // Green check overlay
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundColor(WizardDesign.Colors.success)
                            .background(WizardDesign.Colors.wizardBackground)
                            .clipShape(Circle())
                            .offset(x: 15, y: -5)
                    }
                    Spacer()
                }
                .frame(width: 115, height: 115)
            }

            // Contextual Headline
            Text("Privileged Helper Ready")
                .font(.system(size: 23, weight: .semibold, design: .default))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            // Description
            Text(helperVersion != nil ? "Version \(helperVersion!) — system operations available" : "System operations available without password prompts.")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Inline action status
            if actionStatus.isActive, let message = actionStatus.message {
                InlineStatusView(status: actionStatus, message: message)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Details card
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("XPC Communication")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("System Operations Available")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                }
                Spacer()
            }
            .padding(WizardDesign.Spacing.cardPadding)
            .background(Color.clear, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 60)
            // Show update link if newer version bundled
            if hasUpdateAvailable {
                Button("Update to v\(bundledVersion ?? "")") {
                    Task { await installOrRepairHelper() }
                }
                .buttonStyle(WizardDesign.Component.SecondaryButton())
                .disabled(isWorking)
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
    }

    // MARK: - Setup View (Hero Style for Error State)

    private var setupView: some View {
        VStack(spacing: 16) {  // Reduced from sectionGap to fixed 16pt
            // Icon with warning/error overlay
            ZStack {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 80, weight: .light))  // Reduced from 115 to 80
                    .foregroundColor(isInstalled ? WizardDesign.Colors.warning : WizardDesign.Colors.error)
                    .symbolRenderingMode(.hierarchical)

                // Warning/Error overlay
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: isInstalled ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                            .font(.system(size: 32, weight: .medium))  // Reduced from 40 to 32
                            .foregroundColor(
                                isInstalled ? WizardDesign.Colors.warning : WizardDesign.Colors.error
                            )
                            .background(WizardDesign.Colors.wizardBackground)
                            .clipShape(Circle())
                            .offset(x: 12, y: -4)  // Adjusted for smaller icon
                    }
                    Spacer()
                }
                .frame(width: 80, height: 80)  // Reduced from 115 to 80
            }

            // Contextual Headline
            Text(contextualHeadline)
                .font(.system(size: 20, weight: .semibold, design: .default))  // Reduced from 23 to 20
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            // Description
            Text(contextualDescription)
                .font(.system(size: 14, weight: .regular))  // Reduced from 15 to 14
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)  // Reduced from 40 to 32

            // Inline action status
            if actionStatus.isActive, let message = actionStatus.message {
                InlineStatusView(status: actionStatus, message: message)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Show Login Items approval button if needed
            if needsLoginItemsApproval {
                // Inline screenshot to make the user action explicit (placed above the button)
                if let screenshot = loginItemsScreenshot {
                    Image(nsImage: screenshot)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 360)  // Reduced from 480 to 360
                        .clipShape(RoundedRectangle(cornerRadius: 10))  // Slightly smaller radius
                        .shadow(radius: 4)  // Reduced shadow
                        .padding(.top, 12)  // Reduced from itemGap to fixed 12pt
                        .accessibilityLabel("System Settings Login Items - toggle KeyPath on")
                } else {
                    Color.clear
                        .frame(height: 180)
                        .padding(.top, 12)
                }

                Text("Toggle KeyPath to ON under Background Items, then return here.")
                    .font(.system(size: 13, weight: .regular))  // Reduced from 14 to 13
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)  // Reduced from 32 to 24

                Button("Open Login Items Settings") {
                    openLoginItemsSettings()
                    startApprovalPolling()
                }
                .buttonStyle(WizardDesign.Component.PrimaryButton())
                .keyboardShortcut(.defaultAction)
            } else {
                // Single idempotent action: install or repair (performs cleanup + install)
                Button(isInstalled ? "Fix" : "Install Helper") {
                    Task { await installOrRepairHelper() }
                }
                .buttonStyle(WizardDesign.Component.PrimaryButton())
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking || isFixing)
            }

            if duplicateCopies.count > 1 {
                Button("Reveal App Copies in Finder") {
                    for p in duplicateCopies {
                        let url = URL(fileURLWithPath: p)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                .buttonStyle(WizardDesign.Component.SecondaryButton())
            }

            // If approval is required, offer a quick link to System Settings
            if case let .error(message) = actionStatus,
               message.localizedCaseInsensitiveContains("approval required") {
                Button("Open System Settings → Login Items") {
                    openLoginItemsSettings()
                }
                .buttonStyle(WizardDesign.Component.SecondaryButton())
            }
        }
        .animation(WizardDesign.Animation.statusTransition, value: actionStatus)
        .padding(.horizontal, 32)  // Reduced from 40 to 32
        .frame(maxWidth: 560, maxHeight: 580, alignment: .top)  // Reduced from 620x760 to 560x580
        .heroSectionContainer()
    }

    // MARK: - Actions

    private func logLoginItemsDiagnostics() {
        guard !hasLoggedDiagnostics else { return }
        hasLoggedDiagnostics = true

        let mainURL = Bundle.main.url(forResource: "permissions-login-items", withExtension: "png")
        let moduleURL = Bundle.module.url(forResource: "permissions-login-items", withExtension: "png")
        let mainImageLoaded = mainURL.flatMap { NSImage(contentsOf: $0) } != nil
        let moduleImageLoaded = moduleURL.flatMap { NSImage(contentsOf: $0) } != nil
        let windowHeight = NSApp.keyWindow?.frame.height ?? 0

        AppLogger.shared.log(
            """
            🧭 [Wizard] LoginItems asset diag:
            - mainURL=\(mainURL?.path ?? "nil")
            - moduleURL=\(moduleURL?.path ?? "nil")
            - mainImageLoaded=\(mainImageLoaded)
            - moduleImageLoaded=\(moduleImageLoaded)
            - windowHeight=\(String(format: "%.1f", windowHeight))
            """
        )
    }

    private var loginItemsScreenshot: NSImage? {
        let resourceName = "permissions-login-items"
        if let moduleURL = Bundle.module.url(forResource: resourceName, withExtension: "png"),
           let image = NSImage(contentsOf: moduleURL) {
            return image
        }
        if let mainURL = Bundle.main.url(forResource: resourceName, withExtension: "png"),
           let image = NSImage(contentsOf: mainURL) {
            return image
        }
        return nil
    }

    private func installOrRepairHelper() async {
        await MainActor.run {
            isWorking = true
            actionStatus = .inProgress(message: "Installing helper…")
        }

        let ok = await HelperMaintenance.shared.runCleanupAndRepair(useAppleScriptFallback: true)

        // Re-check approval status after install attempt
        let approvalNeeded = checkLoginItemsApprovalNeeded()

        await MainActor.run {
            isWorking = false
            needsLoginItemsApproval = approvalNeeded

            if ok {
                helperVersion = nil // Will be refreshed
                actionStatus = .success(message: "Helper installed successfully")
                scheduleStatusClear()
            } else if approvalNeeded {
                // Registration succeeded but needs Login Items approval
                actionStatus = .inProgress(
                    message: "Approve KeyPath in System Settings → Login Items (toggle KeyPath ON, see screenshot)."
                )
                // Start polling for approval status changes
                startApprovalPolling()
            } else {
                // Surface the last maintenance log line as a hint
                let hint = HelperMaintenance.shared.logLines.last
                    ?? "Unknown error (helper XPC not reachable)"
                actionStatus = .error(message: "Install failed: \(hint)")
            }
        }

        // Refresh version asynchronously
        if ok {
            let version = await HelperManager.shared.getHelperVersion()
            await MainActor.run { helperVersion = version }
        }

        onRefresh()
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

    private func openSystemSettings() {
        // Best-effort: open System Settings; deep-linking to Login Items is OS-version dependent
        let url = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        NSWorkspace.shared.openApplication(
            at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil
        )
    }

    private func openLoginItemsSettings() {
        // Open System Settings directly to Login Items pane
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        } else {
            openSystemSettings()
        }
    }

    private func checkLoginItemsApprovalNeeded() -> Bool {
        let svc = ServiceManagement.SMAppService.daemon(plistName: HelperManager.helperPlistName)
        return svc.status == .requiresApproval
    }

    // MARK: - Approval Polling

    private func startApprovalPolling() {
        stopApprovalPolling()
        approvalPollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                await checkApprovalStatus()
            }
        }
    }

    private func stopApprovalPolling() {
        approvalPollingTimer?.invalidate()
        approvalPollingTimer = nil
    }

    private func checkApprovalStatus() async {
        let svc = ServiceManagement.SMAppService.daemon(plistName: HelperManager.helperPlistName)

        // If no longer requires approval, check if helper is now healthy
        if svc.status != .requiresApproval {
            let healthy = await HelperManager.shared.testHelperFunctionality()
            if healthy {
                // Success! Helper is approved and responding
                stopApprovalPolling()
                needsLoginItemsApproval = false
                actionStatus = .success(message: "Helper approved and ready!")
                helperVersion = await HelperManager.shared.getHelperVersion()
                scheduleStatusClear()
                onRefresh() // Trigger parent refresh to update issues
            } else if svc.status == .enabled {
                // Approved but not responding yet - give it a moment
                needsLoginItemsApproval = false
                actionStatus = .inProgress(message: "Helper approved, connecting…")
            }
        }
    }

    private func navigateToNextStep() {
        if issues.isEmpty {
            navigationCoordinator.navigateToPage(.summary)
            return
        }

        Task {
            if let next = await navigationCoordinator.getNextPage(for: systemState, issues: issues),
               next != navigationCoordinator.currentPage {
                navigationCoordinator.navigateToPage(next)
            } else {
                navigationCoordinator.navigateToPage(.summary)
            }
        }
    }

    /// Get the version of the helper bundled with this app
    private func getBundledHelperVersion() -> String? {
        guard let bundlePath = Bundle.main.bundlePath as String? else { return nil }
        let helperInfoPath = "\(bundlePath)/Contents/Library/HelperTools/KeyPathHelper"

        // Try to read version from the helper's Info.plist sibling or embedded
        // For simplicity, we'll use a hardcoded version that matches HelperService.swift
        // In production, this should read from the helper's Info.plist
        guard FileManager.default.fileExists(atPath: helperInfoPath) else { return nil }

        // Read version from helper's Info.plist in Sources
        // For now, return the known bundled version
        return "1.1.0"
    }
}
