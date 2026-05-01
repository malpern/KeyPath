import AppKit
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import SwiftUI

/// Accessibility permission page - dedicated page for Accessibility permissions
public struct WizardAccessibilityPage: View {
    public let systemState: WizardSystemState
    public let issues: [WizardIssue]
    public let allIssues: [WizardIssue]
    public let onRefresh: () async -> Void
    public let onNavigateToPage: ((WizardPage) -> Void)?
    public let onDismiss: (() -> Void)?
    public let kanataManager: any RuntimeCoordinating
    @State private var permissionPollingTask: Task<Void, Never>?
    @State private var showSuccessBurst = false

    @Environment(WizardStateMachine.self) var stateMachine

    private func statusIcon(for status: InstallationStatus) -> (name: String, color: Color) {
        switch status {
        case .completed:
            ("checkmark.circle.fill", .green)
        case .warning:
            ("questionmark.circle.fill", .orange)
        case .failed:
            ("xmark.circle.fill", .red)
        case .unverified:
            ("questionmark.circle", .secondary)
        case .notStarted, .inProgress:
            ("ellipsis.circle", .secondary)
        }
    }

    private func kanataSubtitle(for status: InstallationStatus) -> String {
        switch status {
        case .completed:
            " - Keyboard monitoring engine"
        case .warning, .unverified:
            " - Not found — click Fix to re-check"
        case .failed, .notStarted, .inProgress:
            " - Keyboard monitoring engine"
        }
    }

    /// State interpreter for consistent status computation
    private let stateInterpreter = WizardStateInterpreter()

    public init(
        systemState: WizardSystemState,
        issues: [WizardIssue],
        allIssues: [WizardIssue],
        onRefresh: @escaping () async -> Void,
        onNavigateToPage: ((WizardPage) -> Void)?,
        onDismiss: (() -> Void)?,
        kanataManager: any RuntimeCoordinating
    ) {
        self.systemState = systemState
        self.issues = issues
        self.allIssues = allIssues
        self.onRefresh = onRefresh
        self.onNavigateToPage = onNavigateToPage
        self.onDismiss = onDismiss
        self.kanataManager = kanataManager
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Use experimental hero design when permissions are granted
                if !hasAccessibilityIssues {
                    VStack(spacing: WizardDesign.Spacing.sectionGap) {
                        WizardHeroSection.success(
                            icon: "accessibility",
                            title: "Accessibility",
                            subtitle: "KeyPath has system-level access for keyboard monitoring & safety controls",
                            animated: false,
                            iconTapAction: {
                                Task {
                                    await onRefresh()
                                }
                            }
                        )

                        // Component details card below the subheading - horizontally centered
                        HStack {
                            Spacer()
                            VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    HStack(spacing: 0) {
                                        Text("KeyPath.app")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                        Text(" - Emergency stop detection and system monitoring")
                                            .font(.headline)
                                            .fontWeight(.regular)
                                    }
                                }

                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    HStack(spacing: 0) {
                                        Text("kanata-launcher")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                        Text(" - Keyboard monitoring and remapping engine")
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
                        .padding(.top, WizardDesign.Spacing.pageVertical)

                        Button(nextStepButtonTitle) {
                            navigateToNextStep()
                        }
                        .accessibilityIdentifier("wizard_accessibility_next")
                        .buttonStyle(WizardDesign.Component.PrimaryButton())
                        .keyboardShortcut(.defaultAction)
                        .padding(.top, WizardDesign.Spacing.sectionGap)
                    }
                    .heroSectionContainer()
                    .frame(maxWidth: .infinity)
                } else {
                    // Use hero design for error state too, with blue links below
                    VStack(spacing: WizardDesign.Spacing.sectionGap) {
                        WizardHeroSection.warning(
                            icon: "accessibility",
                            title: "Accessibility",
                            subtitle: "Turn on KeyPath in Accessibility, then add and turn on kanata-launcher",
                            iconTapAction: {
                                Task {
                                    await onRefresh()
                                }
                            }
                        )

                        // Guard: recommend running from /Applications for stable permissions
                        if !isRunningFromApplicationsFolder {
                            Text("For the smoothest setup, move KeyPath to /Applications and relaunch.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, WizardDesign.Spacing.elementGap)
                        }

                        // Action link below the subheader
                        Button("Open Settings Manually") {
                            openAccessibilitySettings()
                        }
                        .accessibilityIdentifier("wizard_accessibility_open_settings_manually")
                        .buttonStyle(.link)
                        .padding(.top, WizardDesign.Spacing.elementGap)

                        // Component details for error state
                        VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                            HStack(spacing: 12) {
                                let icon = statusIcon(for: keyPathAccessibilityStatus)
                                Image(systemName: icon.name)
                                    .foregroundColor(icon.color)
                                HStack(spacing: 0) {
                                    Text("KeyPath.app")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                    Text(" - Emergency stop detection")
                                        .font(.headline)
                                        .fontWeight(.regular)
                                }
                                Spacer()
                                if keyPathAccessibilityStatus != .completed {
                                    Button("Turn On") {
                                        // Set service bounce flag before showing permission grant
                                        PermissionGrantCoordinator.shared.setServiceBounceNeeded(
                                            reason: "Accessibility permission fix for KeyPath.app"
                                        )
                                        openAccessibilityPermissionGrant()
                                    }
                                    .buttonStyle(WizardDesign.Component.SecondaryButton())
                                    .scaleEffect(0.8)
                                }
                            }
                            .help(keyPathAccessibilityIssues.asTooltipText())

                            HStack(spacing: 12) {
                                let icon = statusIcon(for: kanataAccessibilityStatus)
                                Image(systemName: icon.name)
                                    .foregroundColor(icon.color)
                                HStack(spacing: 0) {
                                    Text("kanata-launcher")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                    Text(kanataSubtitle(for: kanataAccessibilityStatus))
                                        .font(.headline)
                                        .fontWeight(.regular)
                                }
                                Spacer()
                                if kanataAccessibilityStatus != .completed {
                                    Button("Fix") {
                                        Task {
                                            let snapshot = await PermissionOracle.shared.forceRefresh()
                                            if snapshot.kanata.accessibility.isReady {
                                                AppLogger.shared.log("🔘 [WizardAccessibilityPage] Fix clicked — permission already granted after re-check")
                                                await onRefresh()
                                                return
                                            }
                                            AppLogger.shared.log("🔘 [WizardAccessibilityPage] Fix clicked — opening System Settings and revealing kanata")
                                            openAccessibilitySettings()
                                            revealKanataInFinder()
                                        }
                                    }
                                    .buttonStyle(WizardDesign.Component.SecondaryButton())
                                    .scaleEffect(0.8)
                                }
                            }
                            .help(kanataAccessibilityIssues.asTooltipText())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(WizardDesign.Spacing.cardPadding)
                        .background(Color.clear, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, WizardDesign.Spacing.pageVertical)
                        .padding(.top, WizardDesign.Spacing.pageVertical)
                    }
                    .heroSectionContainer()
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .background(WizardDesign.Colors.wizardBackground)
            .wizardDetailPage()

            // Celebration overlay
            if showSuccessBurst {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .transition(.opacity)

                CheckmarkBurstView(isShowing: $showSuccessBurst)
            }
        }
        .onAppear {
            // Start passive polling to reflect manual changes in System Settings
            if permissionPollingTask == nil {
                permissionPollingTask = Task { @MainActor [onRefresh] in
                    var lastKeyPathGranted: Bool?
                    var lastKanataGranted: Bool?
                    var hasEverCelebrated = false
                    while !Task.isCancelled {
                        let snapshot = await PermissionOracle.shared.currentSnapshot()
                        let kpGranted = snapshot.keyPath.accessibility.isReady
                        let kaGranted = snapshot.kanata.accessibility.isReady
                        let bothGranted = kpGranted && kaGranted
                        if lastKeyPathGranted != kpGranted || lastKanataGranted != kaGranted {
                            AppLogger.shared.log(
                                "🔁 [WizardAccessibilityPage] Passive AX change detected - KeyPath: \(kpGranted), Kanata: \(kaGranted). Refreshing UI."
                            )
                            lastKeyPathGranted = kpGranted
                            lastKanataGranted = kaGranted

                            // Celebrate when both permissions are granted for the first time
                            if bothGranted, !hasEverCelebrated {
                                hasEverCelebrated = true
                                // Bounce dock icon to get user's attention back to KeyPath
                                WizardWindowManager.shared.bounceDocIcon()
                                withAnimation(.spring(response: 0.3)) {
                                    showSuccessBurst = true
                                }
                                _ = await WizardSleep.ms(1500)
                                showSuccessBurst = false
                            }
                            await onRefresh()
                        }
                        // Poll every 250ms up to 1s to reflect changes promptly without long sleeps
                        _ = await WizardSleep.ms(250)
                    }
                }
            }
        }
        .onDisappear {
            permissionPollingTask?.cancel()
            permissionPollingTask = nil
        }
    }

    // MARK: - Computed Properties

    private var hasAccessibilityIssues: Bool {
        keyPathAccessibilityStatus != .completed || kanataAccessibilityStatus != .completed
    }

    private var nextStepButtonTitle: String {
        allIssues.isEmpty ? "Return to Summary" : "Next Issue"
    }

    private var isRunningFromApplicationsFolder: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    private var keyPathAccessibilityStatus: InstallationStatus {
        stateInterpreter.getPermissionStatus(.keyPathAccessibility, in: issues)
    }

    private var kanataAccessibilityStatus: InstallationStatus {
        let status = stateInterpreter.getPermissionStatus(.kanataAccessibility, in: issues)
        AppLogger.shared.log("🔍 [WizardAccessibilityPage] kanataAccessibilityStatus: \(status)")
        return status
    }

    /// Issue filtering for tooltips
    private var keyPathAccessibilityIssues: [WizardIssue] {
        issues.filter { issue in
            if case let .permission(permissionType) = issue.identifier {
                return permissionType == .keyPathAccessibility
            }
            return false
        }
    }

    private var kanataAccessibilityIssues: [WizardIssue] {
        issues.filter { issue in
            if case let .permission(permissionType) = issue.identifier {
                return permissionType == .kanataAccessibility
            }
            return false
        }
    }

    // MARK: - Actions

    private func openAccessibilityPermissionGrant() {
        AppLogger.shared.log("🔐 [WizardAccessibilityPage] Accessibility permission flow starting")

        guard let permissionRequestService = WizardDependencies.permissionRequestService else {
            AppLogger.shared.log("⚠️ [WizardAccessibilityPage] permissionRequestService not configured")
            return
        }
        let alreadyGranted = permissionRequestService.requestAccessibilityPermission(
            ignoreCooldown: true
        )
        if alreadyGranted {
            Task { await onRefresh() }
            return
        }
        // Poll for grant (KeyPath + Kanata) using Oracle snapshot
        permissionPollingTask?.cancel()
        permissionPollingTask = Task { [onRefresh] in
            var attempts = 0
            let maxAttempts = 30
            var lastKeyPathGranted: Bool?
            var lastKanataGranted: Bool?
            while attempts < maxAttempts {
                _ = await WizardSleep.ms(1000)
                attempts += 1
                let snapshot = await PermissionOracle.shared.currentSnapshot()
                let kpGranted = snapshot.keyPath.accessibility.isReady
                let kaGranted = snapshot.kanata.accessibility.isReady

                // Incremental refresh: update UI when either flips, not only when both are ready
                if lastKeyPathGranted != kpGranted || lastKanataGranted != kaGranted {
                    AppLogger.shared.log(
                        "🔁 [WizardAccessibilityPage] Detected permission change (AX) - KeyPath: \(kpGranted), Kanata: \(kaGranted). Refreshing UI."
                    )
                    lastKeyPathGranted = kpGranted
                    lastKanataGranted = kaGranted
                    await onRefresh()
                }

                if kpGranted, kaGranted {
                    // Both ready – stop polling
                    return
                }
                if Task.isCancelled { return }
            }
        }
        // Fallback: if not granted shortly, open Accessibility settings so the user can toggle
        Task { @MainActor in
            _ = await WizardSleep.ms(1500) // 1.5s
            let snapshot = await PermissionOracle.shared.currentSnapshot()
            let granted =
                snapshot.keyPath.accessibility.isReady && snapshot.kanata.accessibility.isReady
            if !granted {
                AppLogger.shared.info(
                    "ℹ️ [WizardAccessibilityPage] Opening System Settings (fallback) for Accessibility"
                )
                openAccessibilitySettings()
            }
        }
    }

    private func openAccessibilitySettings() {
        AppLogger.shared.log(
            "🔐 [WizardAccessibilityPage] Opening Accessibility settings manually"
        )

        // Fallback: Open System Settings > Privacy & Security > Accessibility
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
            let ok = NSWorkspace.shared.open(url)
            if ok {
                WizardWindowManager.shared.markSystemSettingsOpened()
            } else {
                // Fallback: open System Settings app if deep-link fails
                if NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")) {
                    WizardWindowManager.shared.markSystemSettingsOpened()
                }
            }
        }
    }

    private func navigateToNextStep() {
        // Check if Input Monitoring is already granted - if so, we can close System Settings early
        // since the user won't need to visit it again for permissions
        Task { @MainActor in
            let snapshot = await PermissionOracle.shared.currentSnapshot()
            let inputMonitoringGranted = snapshot.keyPath.inputMonitoring.isReady
                && snapshot.kanata.inputMonitoring.isReady

            if inputMonitoringGranted {
                // User already has Input Monitoring - clean up now since they won't need Settings again
                AppLogger.shared.log(
                    "🧹 [WizardAccessibilityPage] Input Monitoring already granted - cleaning up early"
                )
                WizardWindowManager.shared.performFullCleanup()
            }

            if allIssues.isEmpty {
                stateMachine.navigateToPage(.summary)
                return
            }

            if let nextPage = await stateMachine.getNextPage(for: systemState, issues: allIssues),
               nextPage != stateMachine.currentPage
            {
                stateMachine.navigateToPage(nextPage)
            } else {
                stateMachine.navigateToPage(.summary)
            }
        }
    }

    private func revealKanataInFinder() {
        WizardPermissionFinderHelper.revealKanataLauncher()
    }

    private func copyKanataEngineAppPathToClipboard() {
        WizardPermissionFinderHelper.copyPathToClipboard()
    }
}

// MARK: - Preview

#if false
    struct WizardAccessibilityPage_Previews: PreviewProvider {
        static var previews: some View {
            EmptyView()
        }
    }
#endif
