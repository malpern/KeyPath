import AppKit
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import SwiftUI

/// Accessibility permission page - dedicated page for Accessibility permissions
public struct WizardAccessibilityPage: View {
    public let onRefresh: () async -> Void
    public let onNavigateToPage: ((WizardPage) -> Void)?
    public let onDismiss: (() -> Void)?
    public let kanataManager: any RuntimeCoordinating
    @State private var permissionPollingTask: Task<Void, Never>?
    @State private var showSuccessBurst = false
    @State private var permissionSnapshot: PermissionOracle.Snapshot?
    /// When the automatic Accessibility prompt for KeyPath.app was last triggered.
    /// Drives escalation to the drag-to-authorize helper if the grant never
    /// registers, mirroring the Input Monitoring page (#933).
    @State private var keyPathRequestAttemptedAt: Date?

    @Environment(WizardStateMachine.self) private var stateMachine

    private var systemState: WizardSystemState {
        stateMachine.wizardState
    }

    private var issues: [WizardIssue] {
        stateMachine.wizardIssues.filter { $0.category == .permissions }
    }

    private var allIssues: [WizardIssue] {
        stateMachine.wizardIssues
    }

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
            " - Not yet added — add in System Settings"
        case .failed, .notStarted, .inProgress:
            " - Keyboard monitoring engine"
        }
    }

    public init(
        onRefresh: @escaping () async -> Void,
        onNavigateToPage: ((WizardPage) -> Void)?,
        onDismiss: (() -> Void)?,
        kanataManager: any RuntimeCoordinating
    ) {
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
                        WizardHeroSection.setup(
                            icon: "accessibility",
                            title: "Enable Keyboard Control",
                            subtitle: "Allow KeyPath to monitor safety shortcuts and let Kanata Engine apply your remaps.",
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
                                    .accessibilityIdentifier("wizard-accessibility-keypath-turn-on")
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
                                    Button("Add in Settings") {
                                        Task {
                                            let snapshot = await SystemStateProvider.shared.refreshPermissionSnapshot()
                                            if snapshot.kanata.accessibility.isReady {
                                                AppLogger.shared.log("🔘 [WizardAccessibilityPage] Fix clicked — permission already granted, navigating to summary")
                                                await onRefresh()
                                                onNavigateToPage?(.summary)
                                                return
                                            }
                                            AppLogger.shared.log("🔘 [WizardAccessibilityPage] Fix clicked — presenting drag-to-authorize overlay")
                                            DragToAuthorizeController.shared.present(for: .accessibility)
                                        }
                                    }
                                    .buttonStyle(WizardDesign.Component.SecondaryButton())
                                    .scaleEffect(0.8)
                                    .accessibilityIdentifier("wizard-accessibility-kanata-add-settings")
                                }
                            }
                            .help(kanataAccessibilityIssues.asTooltipText())

                            // Escalation: if the automatic prompt for KeyPath.app never
                            // registered a grant, offer the drag-to-authorize helper
                            // instead of leaving the user at a "Turn On" button (#933).
                            if keyPathAccessibilityGuidance == .manualFallback {
                                AccessibilityManualFallbackCard()
                            }
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
        .task {
            // Set initial snapshot immediately so the page renders correct state
            // before the polling loop's first 500ms tick.
            permissionSnapshot = await SystemStateProvider.shared.refreshPermissionSnapshot()
        }
        .onAppear {
            // Always restart polling on appear — SwiftUI may have cancelled
            // the previous task during a view rebuild triggered by onRefresh().
            permissionPollingTask?.cancel()
            permissionPollingTask = Task { @MainActor [onRefresh] in
                var hasEverCelebrated = false
                while !Task.isCancelled {
                    _ = await WizardSleep.ms(1000)
                    let snapshot = await SystemStateProvider.shared.refreshPermissionSnapshot()
                    permissionSnapshot = snapshot

                    let bothGranted = snapshot.keyPath.accessibility.isReady
                        && snapshot.kanata.accessibility.isReady
                    if bothGranted, !hasEverCelebrated {
                        hasEverCelebrated = true
                        WizardWindowManager.shared.bounceDocIcon()
                        withAnimation(.spring(response: 0.3)) {
                            showSuccessBurst = true
                        }
                        _ = await WizardSleep.ms(1500)
                        showSuccessBurst = false
                        await onRefresh()
                        return
                    }
                }
            }
        }
        .onDisappear {
            permissionPollingTask?.cancel()
            permissionPollingTask = nil
            DragToAuthorizeController.shared.dismiss(animated: false)
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
        guard let snapshot = permissionSnapshot else { return .inProgress }
        return installationStatus(for: snapshot.keyPath.accessibility)
    }

    private var kanataAccessibilityStatus: InstallationStatus {
        guard let snapshot = permissionSnapshot else { return .inProgress }
        return installationStatus(for: snapshot.kanata.accessibility)
    }

    /// Escalation state for KeyPath.app's own Accessibility grant. Uses the shared
    /// permission-agnostic `AutomaticPromptGuidance` resolver: once the automatic-prompt
    /// wait window elapses without a grant, the drag-to-authorize fallback appears
    /// instead of stranding the user at "Turn On" (#933).
    private var keyPathAccessibilityGuidance: AutomaticPromptGuidance {
        resolveAutomaticPromptGuidance(
            AutomaticPromptGuidanceInput(
                keyPathReady: permissionSnapshot?.keyPath.accessibility.isReady ?? false,
                requestAttempted: keyPathRequestAttemptedAt != nil,
                secondsSinceRequest: keyPathRequestAttemptedAt.map { Date().timeIntervalSince($0) }
            )
        )
    }

    private func installationStatus(for status: PermissionOracle.Status) -> InstallationStatus {
        switch status {
        case .granted: .completed
        case .denied, .error: .failed
        case .unknown: .warning
        }
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

        // Record the attempt so guidance escalates to the drag-to-authorize helper
        // if the automatic prompt never registers a grant (#933). Set only after the
        // guard so the escalation clock never starts on a path with no real request.
        keyPathRequestAttemptedAt = Date()

        Task { @MainActor in
            let alreadyGranted = await permissionRequestService.requestAccessibilityPermission(
                ignoreCooldown: true
            )
            if alreadyGranted {
                await onRefresh()
                return
            }
            // Poll for grant (KeyPath + Kanata) using the shared system-state facade.
            permissionPollingTask?.cancel()
            permissionPollingTask = Task { @MainActor [onRefresh] in
                var attempts = 0
                let maxAttempts = 30
                var lastKeyPathGranted: Bool?
                var lastKanataGranted: Bool?
                while attempts < maxAttempts {
                    _ = await WizardSleep.ms(1000)
                    attempts += 1
                    let snapshot = await SystemStateProvider.shared.refreshPermissionSnapshot()
                    // Keep the snapshot fresh each tick so the page re-renders and the
                    // #933 escalation card can appear once the wait window elapses.
                    permissionSnapshot = snapshot
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
            _ = await WizardSleep.ms(1500) // 1.5s
            let snapshot = await SystemStateProvider.shared.refreshPermissionSnapshot()
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
            let snapshot = await SystemStateProvider.shared.refreshPermissionSnapshot()
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

// MARK: - Manual fallback guidance (#933)

/// Shown when the automatic Accessibility prompt for KeyPath.app never registers a
/// grant. Offers the drag-to-authorize helper — opens System Settings and floats a
/// tile the user drags KeyPath into — instead of leaving them at a "Turn On" button
/// that appeared to do nothing. Mirrors the Input Monitoring fallback card.
private struct AccessibilityManualFallbackCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Didn't see a permission prompt?", systemImage: "hand.raised.circle")
                .font(.headline)

            Text(
                "On some macOS versions the automatic prompt doesn't appear. You can add KeyPath to Accessibility yourself:"
            )
            .font(.callout)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Button("Add KeyPath to Accessibility") {
                DragToAuthorizeController.shared.present(for: .accessibility, subject: .keyPath)
            }
            .buttonStyle(WizardDesign.Component.SecondaryButton())
            .accessibilityIdentifier("wizard_accessibility_manual_fallback")
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WizardDesign.Spacing.cardPadding)
        .background(
            WizardDesign.Colors.warning.opacity(0.06),
            in: RoundedRectangle(cornerRadius: WizardDesign.Layout.cornerRadius)
        )
    }
}
