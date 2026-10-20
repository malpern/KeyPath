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
                VStack(spacing: 24) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 88, weight: .light))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                        .padding(.bottom, 8)

                    Text(AccessibilityPermissionPresentation.current.enableTitle)
                        .font(.largeTitle.weight(.semibold))
                        .multilineTextAlignment(.center)

                    Text("Let KeyPath apply your remaps and keyboard shortcuts.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 560)

                    if hasAccessibilityIssues {
                        Button("Open System Settings") {
                            openAccessibilityPermissionGrant()
                        }
                        .buttonStyle(WizardDesign.Component.PrimaryButton())
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("wizard-accessibility-keypath-turn-on")

                        Text(AccessibilityPermissionPresentation.current.turnOnInstruction)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        if !isRunningFromApplicationsFolder {
                            Text("Move KeyPath to Applications and reopen it before enabling access.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        // No KeyPath row after the request: offer the manual add (#933).
                        if keyPathAccessibilityGuidance == .manualFallback {
                            AccessibilityManualFallbackCard()
                                .frame(maxWidth: 560)
                        }
                    } else {
                        Label(AccessibilityPermissionPresentation.current.enabledTitle, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityIdentifier("wizard_accessibility_enabled")
                    }
                }
                .padding(.horizontal, 40)
                .heroSectionContainer()
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .background(WizardDesign.Colors.wizardBackground)
            .wizardDetailPage()
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

                    let accessibilityReady = snapshot.keyPath.accessibility.isReady
                    if accessibilityReady, !hasEverCelebrated {
                        hasEverCelebrated = true
                        _ = await WizardSleep.ms(1500)
                        await onRefresh()
                        guard !Task.isCancelled else { return }
                        navigateToNextStep()
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
        keyPathAccessibilityStatus != .completed
    }

    private var nextStepButtonTitle: String {
        "Continue"
    }

    private var isRunningFromApplicationsFolder: Bool {
        let appPath = Bundle.main.bundleURL.standardizedFileURL.path
        let userApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true).standardizedFileURL.path
        return appPath.hasPrefix("/Applications/") || appPath.hasPrefix(userApplications + "/")
    }

    private var keyPathAccessibilityStatus: InstallationStatus {
        guard let snapshot = permissionSnapshot else { return .inProgress }
        return installationStatus(for: snapshot.keyPath.accessibility)
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

    // MARK: - Actions

    private func openAccessibilityPermissionGrant() {
        AppLogger.shared.log("🔐 [WizardAccessibilityPage] Accessibility permission flow starting")

        // Ask macOS first (this adds KeyPath's row), and record the attempt so the
        // manual card appears if the grant never registers.
        if keyPathRequestAttemptedAt == nil { keyPathRequestAttemptedAt = Date() }
        Task { @MainActor in
            if let service = WizardDependencies.permissionRequestService {
                _ = await service.requestAccessibilityPermission(ignoreCooldown: true)
            }
            openAccessibilitySettings()
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
            let inputMonitoringGranted = snapshot.keyPath.inputMonitoring.isReady || snapshot.kanata.inputMonitoring.isReady

            if !inputMonitoringGranted {
                stateMachine.navigateToPage(.inputMonitoring)
                return
            }
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
