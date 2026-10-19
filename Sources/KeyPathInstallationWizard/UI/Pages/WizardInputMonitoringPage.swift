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

    public var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "keyboard")
                .font(.system(size: 88, weight: .light))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
                .padding(.bottom, 8)

            Text("Enable Input Monitoring")
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("Let KeyPath read keyboard events to run your shortcuts. Your keystrokes stay on your Mac.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)

            if hasInputMonitoringIssues {
                Button(keyPathActionTitle) {
                    handleKeyPathInputMonitoringAction()
                }
                .buttonStyle(WizardDesign.Component.PrimaryButton())
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("wizard_input_monitoring_fix_keypath")

                Text(sessionInputNeedsVerification
                    ? "KeyPath checks access by starting remapping."
                    : "Turn on KeyPath under Input Monitoring.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // The automatic prompt can fail to register on macOS 26/27, leaving
                // no KeyPath row to turn on (#931). Escalate to manual steps.
                if keyPathGuidance == .manualFallback {
                    InputMonitoringManualFallbackCard()
                        .frame(maxWidth: 560)
                }
            } else {
                Label("Input Monitoring enabled", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("wizard_input_monitoring_enabled")
            }
        }
        .padding(.horizontal, 40)
        .heroSectionContainer()
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .background(WizardDesign.Colors.wizardBackground)
        .wizardDetailPage()
        .task {
            permissionSnapshot = await SystemStateProvider.shared.refreshPermissionSnapshot()
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
        keyPathInputMonitoringStatus != .completed
    }

    private var nextStepButtonTitle: String {
        allIssues.isEmpty ? "Return to Summary" : "Continue"
    }

    private var keyPathInputMonitoringStatus: InstallationStatus {
        guard let snapshot = permissionSnapshot else { return .inProgress }
        return installationStatus(for: snapshot.keyPath.inputMonitoring.isReady ? .granted : snapshot.kanata.inputMonitoring)
    }

    private var sessionInputNeedsVerification: Bool {
        guard let snapshot = permissionSnapshot else { return true }
        if case .unknown = snapshot.kanata.inputMonitoring { return true }
        return false
    }

    private var keyPathSubtitle: String {
        if sessionInputNeedsVerification { return " - Verify keyboard access by starting the session" }
        return switch keyPathGuidance {
        case .granted:
            " - Session can capture keyboard input"
        case .offerAutomatic:
            " - Main application needs permission"
        case .awaitingGrant:
            " - Waiting for macOS to register permission"
        case .manualFallback:
            " - Not yet added — add in System Settings"
        }
    }

    private var keyPathActionTitle: String {
        if sessionInputNeedsVerification { return "Check Access" }
        return switch keyPathGuidance {
        case .manualFallback:
            "Add in Settings"
        case .granted:
            "Done"
        case .offerAutomatic, .awaitingGrant:
            "Turn On"
        }
    }

    /// Escalation state for the session tap's effective input access. Recomputed
    /// on every render (the 1s poll updates `permissionSnapshot`), so once the
    /// automatic-prompt wait window elapses without a grant the manual-add card
    /// appears instead of leaving the user stranded at the "Turn On" button (#931).
    private var keyPathGuidance: AutomaticPromptGuidance {
        resolveAutomaticPromptGuidance(
            AutomaticPromptGuidanceInput(
                keyPathReady: permissionSnapshot?.kanata.inputMonitoring.isReady ?? false,
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
    private var keyPathInputMonitoringIssues: [WizardIssue] {
        issues.filter { issue in
            if case let .permission(permissionType) = issue.identifier {
                return permissionType == .keyPathInputMonitoring || permissionType == .kanataInputMonitoring
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
                let snapshot = await SystemStateProvider.shared.refreshPermissionSnapshot()
                permissionSnapshot = snapshot

                let inputReady = snapshot.keyPath.inputMonitoring.isReady || snapshot.kanata.inputMonitoring.isReady
                if inputReady, !hasEverCelebrated {
                    hasEverCelebrated = true
                    _ = await WizardSleep.ms(1500)
                    guard !Task.isCancelled else { return }
                    await onRefresh()
                    guard !Task.isCancelled else { return }
                    navigateToNextStep()
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
                let snapshot = await SystemStateProvider.shared.refreshPermissionSnapshot()
                permissionSnapshot = snapshot
                let hasPermission: Bool =
                    switch type {
                    case .accessibility:
                        snapshot.keyPath.accessibility.isReady
                    case .inputMonitoring:
                        snapshot.kanata.inputMonitoring.isReady
                    }
                if hasPermission {
                    // Bounce dock icon to get user's attention back to KeyPath
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

    private func verifySessionInputAccess() {
        Task { @MainActor in
            _ = await kanataManager.startKanata(reason: "Wizard verifying session input access")
            permissionSnapshot = await SystemStateProvider.shared.refreshPermissionSnapshot()
            await onRefresh()
        }
    }

    /// Ask macOS for access (which adds KeyPath's row to the list), then open the
    /// pane. Recording the attempt lets `keyPathGuidance` escalate to the manual
    /// card if the grant never registers (#931).
    private func openInputMonitoringSettings() {
        if keyPathRequestAttemptedAt == nil { keyPathRequestAttemptedAt = Date() }
        Task { @MainActor in
            if let service = WizardDependencies.permissionRequestService {
                _ = await service.requestInputMonitoringPermission(ignoreCooldown: true)
            }
            openInputMonitoringPreferencesPanel()
        }
    }

    private func handleKeyPathInputMonitoringAction() {
        if sessionInputNeedsVerification {
            verifySessionInputAccess()
            return
        }
        switch keyPathGuidance {
        case .manualFallback:
            AppLogger.shared.log("🔧 [WizardInputMonitoringPage] KeyPath manual-add clicked")
            DragToAuthorizeController.shared.present(for: .inputMonitoring, subject: .keyPath)
        case .granted:
            break
        case .offerAutomatic, .awaitingGrant:
            openInputMonitoringSettings()
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
