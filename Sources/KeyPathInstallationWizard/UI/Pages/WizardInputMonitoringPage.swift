import AppKit
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import SwiftUI

/// Input Monitoring permission page with hybrid permission request approach
public struct WizardInputMonitoringPage: View {
    public let onRefresh: () async -> Void
    public let onNavigateToPage: ((WizardPage) -> Void)?
    public let onDismiss: (() -> Void)?
    public let kanataManager: any RuntimeCoordinating

    @State private var showingStaleEntryCleanup = false
    @State private var staleEntryDetails: [String] = []
    @State private var permissionPollingTask: Task<Void, Never>?
    @State private var showSuccessBurst = false
    @State private var permissionSnapshot: PermissionOracle.Snapshot?
    /// When the automatic `IOHIDRequestAccess` prompt for KeyPath.app was last
    /// triggered. Drives the escalation to manual guidance when the grant never
    /// registers (macOS 26/27 dead-end, #931).
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
            " - Remapping engine processes keyboard events"
        case .warning, .unverified:
            " - Not yet added — add in System Settings"
        case .failed, .notStarted, .inProgress:
            " - Remapping engine needs permission"
        }
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Use experimental hero design when permissions are granted
                if !hasInputMonitoringIssues {
                    VStack(spacing: WizardDesign.Spacing.sectionGap) {
                        WizardHeroSection.success(
                            icon: "eye",
                            title: "Input Monitoring",
                            subtitle: "KeyPath has permission to capture keyboard events",
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
                                        Text(" - Main application captures keyboard input")
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
                                        Text(" - Remapping engine processes keyboard events")
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
                        .accessibilityIdentifier("wizard_input_monitoring_next")
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
                            icon: "eye",
                            title: "Input Monitoring Required",
                            subtitle:
                            "KeyPath needs Input Monitoring permission to capture keyboard events for remapping",
                            iconTapAction: {
                                Task {
                                    await onRefresh()
                                }
                            }
                        )

                        // Component details for error state
                        VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                            HStack(spacing: 12) {
                                let icon = statusIcon(for: keyPathInputMonitoringStatus)
                                Image(systemName: icon.name)
                                    .foregroundColor(icon.color)
                                HStack(spacing: 0) {
                                    Text("KeyPath.app")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                    Text(" - Main application needs permission")
                                        .font(.headline)
                                        .fontWeight(.regular)
                                }
                                Spacer()
                                if keyPathInputMonitoringStatus != .completed {
                                    Button("Turn On") {
                                        openInputMonitoringSettings()
                                    }
                                    .accessibilityIdentifier("wizard_input_monitoring_fix_keypath")
                                    .buttonStyle(WizardDesign.Component.SecondaryButton())
                                    .scaleEffect(0.8)
                                }
                            }
                            .help(keyPathInputMonitoringIssues.asTooltipText())

                            HStack(spacing: 12) {
                                let icon = statusIcon(for: kanataInputMonitoringStatus)
                                Image(systemName: icon.name)
                                    .foregroundColor(icon.color)
                                HStack(spacing: 0) {
                                    Text("kanata-launcher")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                    Text(kanataSubtitle(for: kanataInputMonitoringStatus))
                                        .font(.headline)
                                        .fontWeight(.regular)
                                }
                                Spacer()
                                if kanataInputMonitoringStatus != .completed {
                                    Button("Add in Settings") {
                                        Task {
                                            let snapshot = await PermissionOracle.shared.forceRefresh()
                                            if snapshot.kanata.inputMonitoring.isReady {
                                                AppLogger.shared.log("🔧 [WizardInputMonitoringPage] Fix clicked — permission already granted, navigating to summary")
                                                await onRefresh()
                                                onNavigateToPage?(.summary)
                                                return
                                            }
                                            AppLogger.shared.log("🔧 [WizardInputMonitoringPage] Kanata Fix clicked — presenting drag-to-authorize overlay")
                                            DragToAuthorizeController.shared.present(for: .inputMonitoring)
                                        }
                                    }
                                    .buttonStyle(WizardDesign.Component.SecondaryButton())
                                    .scaleEffect(0.8)
                                    .accessibilityIdentifier("wizard-input-monitoring-kanata-add-settings")
                                }
                            }
                            .help(kanataInputMonitoringIssues.asTooltipText())

                            // Escalation: if the automatic prompt for KeyPath.app
                            // never registered a grant, augment the "Turn On" retry
                            // (whose deep-linked Settings row may not exist on macOS
                            // 26/27) with accurate manual "+"-to-add steps (#931).
                            if keyPathGuidance == .manualFallback {
                                InputMonitoringManualFallbackCard()
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
            permissionSnapshot = await PermissionOracle.shared.forceRefresh()
        }
        .onAppear {
            checkForStaleEntries()
            startBackgroundPermissionPolling()
        }
        .onDisappear {
            permissionPollingTask?.cancel()
            permissionPollingTask = nil
            DragToAuthorizeController.shared.dismiss(animated: false)
        }
    }

    // MARK: - Computed Properties

    private var hasInputMonitoringIssues: Bool {
        keyPathInputMonitoringStatus != .completed || kanataInputMonitoringStatus != .completed
    }

    private var nextStepButtonTitle: String {
        allIssues.isEmpty ? "Return to Summary" : "Next Issue"
    }

    private var keyPathInputMonitoringStatus: InstallationStatus {
        guard let snapshot = permissionSnapshot else { return .inProgress }
        return installationStatus(for: snapshot.keyPath.inputMonitoring)
    }

    /// Escalation state for KeyPath.app's own Input Monitoring grant. Recomputed
    /// on every render (the 1s poll updates `permissionSnapshot`), so once the
    /// automatic-prompt wait window elapses without a grant the manual-add card
    /// appears instead of leaving the user stranded at the "Turn On" button (#931).
    private var keyPathGuidance: InputMonitoringGuidance {
        resolveInputMonitoringGuidance(
            InputMonitoringGuidanceInput(
                keyPathReady: permissionSnapshot?.keyPath.inputMonitoring.isReady ?? false,
                requestAttempted: keyPathRequestAttemptedAt != nil,
                secondsSinceRequest: keyPathRequestAttemptedAt.map { Date().timeIntervalSince($0) }
            )
        )
    }

    private var kanataInputMonitoringStatus: InstallationStatus {
        guard let snapshot = permissionSnapshot else { return .inProgress }
        return installationStatus(for: snapshot.kanata.inputMonitoring)
    }

    private func installationStatus(for status: PermissionOracle.Status) -> InstallationStatus {
        switch status {
        case .granted: .completed
        case .denied, .error: .failed
        case .unknown: .warning
        }
    }

    /// Issue filtering for tooltips
    private var keyPathInputMonitoringIssues: [WizardIssue] {
        issues.filter { issue in
            if case let .permission(permissionType) = issue.identifier {
                return permissionType == .keyPathInputMonitoring
            }
            return false
        }
    }

    private var kanataInputMonitoringIssues: [WizardIssue] {
        issues.filter { issue in
            if case let .permission(permissionType) = issue.identifier {
                return permissionType == .kanataInputMonitoring
            }
            return false
        }
    }

    // MARK: - Actions

    private func checkForStaleEntries() {
        Task {
            // Oracle system - no stale entry detection needed
            let detection = (hasStaleEntries: false, details: [String]())
            await MainActor.run {
                if detection.hasStaleEntries {
                    staleEntryDetails = detection.details
                    AppLogger.shared.log(
                        "🔐 [WizardInputMonitoringPage] Stale entries detected: \(detection.details.joined(separator: ", "))"
                    )
                }
            }
        }
    }

    private func navigateToNextStep() {
        // Input Monitoring is the last permission step that uses System Settings.
        // Clean up any windows we opened (System Settings, Finder) and focus KeyPath.
        WizardWindowManager.shared.performFullCleanup()

        if allIssues.isEmpty {
            stateMachine.navigateToPage(.summary)
            return
        }

        Task {
            if let nextPage = await stateMachine.getNextPage(for: systemState, issues: allIssues),
               nextPage != stateMachine.currentPage
            {
                stateMachine.navigateToPage(nextPage)
            } else {
                stateMachine.navigateToPage(.summary)
            }
        }
    }

    private func handleHelpWithPermission() {
        Task {
            // First check for stale entries
            // Oracle system - no stale entry detection needed
            let detection = (hasStaleEntries: false, details: [String]())

            await MainActor.run {
                if detection.hasStaleEntries {
                    // Show cleanup instructions first
                    staleEntryDetails = detection.details
                    showingStaleEntryCleanup = true
                    AppLogger.shared.log(
                        "🔐 [WizardInputMonitoringPage] Showing cleanup instructions for stale entries"
                    )
                } else {
                    // Always open settings manually - never auto-request
                    openInputMonitoringSettings()
                }
            }
        }
    }

    /// Durable 1s permission poll for the lifetime of the page. It is the single
    /// writer of `permissionSnapshot` after first load, so it drives both grant
    /// detection (celebrate + advance) AND time-based re-renders that let
    /// `keyPathGuidance` escalate to the manual-fallback card (#931). It must keep
    /// running whenever the page is visible and not fully granted — the automatic
    /// "Turn On" flow resumes it after its fast poll exhausts.
    private func startBackgroundPermissionPolling() {
        permissionPollingTask?.cancel()
        permissionPollingTask = Task { @MainActor [onRefresh] in
            var hasEverCelebrated = false
            while !Task.isCancelled {
                _ = await WizardSleep.ms(1000)
                if Task.isCancelled { return }
                let snapshot = await PermissionOracle.shared.forceRefresh()
                permissionSnapshot = snapshot

                let bothGranted = snapshot.keyPath.inputMonitoring.isReady
                    && snapshot.kanata.inputMonitoring.isReady
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

    /// Fast (250ms) poll used immediately after the automatic prompt for snappy
    /// grant detection. It also keeps `permissionSnapshot` fresh so the page
    /// re-renders, and — critically — hands back to the durable 1s poll when it
    /// exhausts without a grant, so re-renders and grant detection continue and
    /// the #931 manual-fallback escalation can still fire.
    private func startPermissionPolling(for type: CoordinatorPermissionType) {
        permissionPollingTask?.cancel()
        permissionPollingTask = Task { @MainActor [onRefresh] in
            var attempts = 0
            let maxAttempts = 20 // ~5s at 250ms intervals
            while attempts < maxAttempts {
                _ = await WizardSleep.ms(250)
                if Task.isCancelled { return }
                attempts += 1
                let snapshot = await PermissionOracle.shared.forceRefresh()
                permissionSnapshot = snapshot
                let hasPermission: Bool =
                    switch type {
                    case .accessibility:
                        snapshot.keyPath.accessibility.isReady && snapshot.kanata.accessibility.isReady
                    case .inputMonitoring:
                        snapshot.keyPath.inputMonitoring.isReady && snapshot.kanata.inputMonitoring.isReady
                    }
                if hasPermission {
                    // Bounce dock icon to get user's attention back to KeyPath
                    WizardWindowManager.shared.bounceDocIcon()
                    // Celebrate!
                    withAnimation(.spring(response: 0.3)) {
                        showSuccessBurst = true
                    }
                    // Wait for celebration, then refresh
                    _ = await WizardSleep.ms(1500)
                    showSuccessBurst = false
                    await onRefresh()
                    return
                }
            }
            // Grant did not arrive in the fast window: resume the durable poll so
            // the page keeps refreshing (drives the #931 manual-fallback card and
            // still detects a later manual grant). Without this the page would go
            // static and the escalation could never appear.
            //
            // Note: startBackgroundPermissionPolling() begins by cancelling
            // `permissionPollingTask`, which still points at THIS fast-poll task —
            // an intentional self-cancel. It is harmless: cancellation only flips
            // `Task.isCancelled`, and there is no further code or await point in
            // this closure after the call. Do not "simplify" it away.
            startBackgroundPermissionPolling()
        }
    }

    private func openInputMonitoringSettings() {
        AppLogger.shared.log(
            "🔧 [WizardInputMonitoringPage] Fix button clicked - permission flow starting"
        )

        // Use automatic prompt via IOHIDRequestAccess()
        guard let permissionRequestService = WizardDependencies.permissionRequestService else {
            AppLogger.shared.log("⚠️ [WizardInputMonitoringPage] permissionRequestService not configured")
            return
        }

        // Record the attempt so guidance escalates to manual steps if the
        // automatic prompt never registers a grant (macOS 26/27 dead-end, #931).
        // Set only after the guard so the escalation clock never starts on a path
        // where no request was actually made.
        keyPathRequestAttemptedAt = Date()

        Task { @MainActor in
            let alreadyGranted = await permissionRequestService.requestInputMonitoringPermission(
                ignoreCooldown: true
            )
            if alreadyGranted {
                await onRefresh()
                return
            }

            // Poll for grant (KeyPath + Kanata) using Oracle snapshot
            startPermissionPolling(for: .inputMonitoring)

            // Fallback: if still not granted shortly after, open System Settings panel
            for _ in 0 ..< 6 { // ~1.5s at 250ms
                _ = await WizardSleep.ms(250)
                let snapshot = await PermissionOracle.shared.forceRefresh()
                let granted =
                    snapshot.keyPath.inputMonitoring.isReady && snapshot.kanata.inputMonitoring.isReady
                if granted { return }
            }
            AppLogger.shared.info(
                "ℹ️ [WizardInputMonitoringPage] Opening System Settings (fallback) for Input Monitoring"
            )
            openInputMonitoringPreferencesPanel()
        }
    }
}

@MainActor
private func openInputMonitoringPreferencesPanel() {
    if let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
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

// MARK: - Manual fallback guidance (#931)

/// Shown when the automatic Input Monitoring prompt for KeyPath.app never
/// registers a grant. Gives accurate manual steps instead of leaving the user at
/// a "Turn On" button that deep-links to a Settings row which may not exist on
/// macOS 26/27.
private struct InputMonitoringManualFallbackCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Didn't see a permission prompt?", systemImage: "hand.raised.circle")
                .font(.headline)

            Text(
                "On some macOS versions the automatic prompt doesn't appear. Add KeyPath to Input Monitoring below — or do it manually."
            )
            .font(.callout)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            // Primary: opens Settings and floats a helper you drag KeyPath from,
            // straight into the Input Monitoring list (#933).
            Button("Add KeyPath to Input Monitoring") {
                DragToAuthorizeController.shared.present(for: .inputMonitoring, subject: .keyPath)
            }
            .buttonStyle(WizardDesign.Component.SecondaryButton())
            .accessibilityIdentifier("wizard_input_monitoring_manual_fallback")
            .padding(.top, 4)

            // Manual alternative for anyone who would rather not drag.
            VStack(alignment: .leading, spacing: 6) {
                CleanupStep(number: 1, text: "Open System Settings → Privacy & Security → Input Monitoring.")
                CleanupStep(number: 2, text: "Click the \"+\" button below the list.")
                CleanupStep(number: 3, text: "Choose KeyPath.app from your Applications folder, then turn its switch on.")
            }
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

// MARK: - Helpers for Kanata add flow

@MainActor
private func revealKanataInFinder() {
    WizardPermissionFinderHelper.revealKanataLauncher()
}

@MainActor
private func copyKanataEngineAppPathToClipboard() {
    WizardPermissionFinderHelper.copyPathToClipboard()
}

// MARK: - Stale Entry Cleanup Instructions View

public struct StaleEntryCleanupInstructions: View {
    public let staleEntryDetails: [String]
    public let onContinue: () -> Void

    public init(staleEntryDetails: [String], onContinue: @escaping () -> Void) {
        self.staleEntryDetails = staleEntryDetails
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Old KeyPath Entries Detected", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundColor(.orange)

                Text(
                    "We've detected possible old or duplicate KeyPath entries that need to be cleaned up before granting new permissions."
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }

            // Show detected issues
            if !staleEntryDetails.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Detected Issues:")
                        .font(.caption)
                        .fontWeight(.semibold)

                    ForEach(staleEntryDetails, id: \.self) { detail in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .foregroundColor(.orange)
                            Text(detail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.05))
                .clipShape(.rect(cornerRadius: 8))
            }

            // Cleanup Instructions
            VStack(alignment: .leading, spacing: 12) {
                Text("How to Clean Up:")
                    .font(.headline)

                CleanupStep(number: 1, text: "Click 'Open Settings' below")
                CleanupStep(number: 2, text: "Find ALL KeyPath entries in the list")
                CleanupStep(
                    number: 3, text: "Remove entries with ⚠️ warning icons by clicking the '-' button"
                )
                CleanupStep(number: 4, text: "Remove any duplicate KeyPath entries")
                CleanupStep(number: 5, text: "Add the current KeyPath using the '+' button")
                CleanupStep(number: 6, text: "Also add 'kanata-launcher' if needed")
            }
            .padding()
            .background(Color.blue.opacity(0.05))
            .clipShape(.rect(cornerRadius: 8))

            // Visual hint
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Tip: Entries with warning icons are from old or moved installations")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            Spacer()

            // Continue button
            Button("Open Settings") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding()
    }
}

public struct CleanupStep: View {
    public let number: Int
    public let text: String

    public init(number: Int, text: String) {
        self.number = number
        self.text = text
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.blue)
                .frame(width: 20, alignment: .leading)

            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
        }
    }
}
