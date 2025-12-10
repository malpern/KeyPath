import AppKit
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import SwiftUI

/// Input Monitoring permission page with hybrid permission request approach
struct WizardInputMonitoringPage: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let allIssues: [WizardIssue]
    let stateInterpreter: WizardStateInterpreter
    let onRefresh: () async -> Void
    let onNavigateToPage: ((WizardPage) -> Void)?
    let onDismiss: (() -> Void)?
    let kanataManager: RuntimeCoordinator

    @State private var showingStaleEntryCleanup = false
    @State private var staleEntryDetails: [String] = []
    @State private var permissionPollingTask: Task<Void, Never>?

    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator

    var body: some View {
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
                    // NOTE: Only show KeyPath status. Kanata uses the Karabiner VirtualHIDDevice
                    // driver and runs as root, so it doesn't need TCC permissions.
                    HStack {
                        Spacer()
                        VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                HStack(spacing: 0) {
                                    Text("KeyPath.app")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                    Text(" - Has permission to capture keyboard events")
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
                    .buttonStyle(WizardDesign.Component.PrimaryButton())
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, WizardDesign.Spacing.sectionGap)
                }
                .heroSectionContainer()
                .frame(maxWidth: .infinity)
            } else {
                // Use hero design for error state too, with blue links below
                // NOTE: Only show KeyPath status. Kanata doesn't need TCC permissions.
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

                    // Component details for error state - only KeyPath needs TCC
                    VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                        HStack(spacing: 12) {
                            Image(
                                systemName: keyPathInputMonitoringStatus == .completed
                                    ? "checkmark.circle.fill" : "xmark.circle.fill"
                            )
                            .foregroundStyle(keyPathInputMonitoringStatus == .completed ? .green : Color.red)
                            HStack(spacing: 0) {
                                Text("KeyPath.app")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Text(" - Needs permission to capture keyboard events")
                                    .font(.headline)
                                    .fontWeight(.regular)
                            }
                            Spacer()
                            if keyPathInputMonitoringStatus != .completed {
                                Button("Fix") {
                                    openInputMonitoringSettings()
                                }
                                .buttonStyle(WizardDesign.Component.SecondaryButton())
                                .scaleEffect(0.8)
                            }
                        }
                        .help(keyPathInputMonitoringIssues.asTooltipText())
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

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WizardDesign.Colors.wizardBackground)
        .wizardDetailPage()
        .onAppear {
            checkForStaleEntries()
        }
        .onDisappear {
            permissionPollingTask?.cancel()
            permissionPollingTask = nil
        }
    }

    // MARK: - Computed Properties

    // NOTE: Only KeyPath needs Input Monitoring TCC permission.
    // Kanata uses the Karabiner VirtualHIDDevice driver and communicates via IPC,
    // so it doesn't need TCC entries (it runs as root via SMAppService/LaunchDaemon).
    private var hasInputMonitoringIssues: Bool {
        keyPathInputMonitoringStatus != .completed
    }

    private var nextStepButtonTitle: String {
        allIssues.isEmpty ? "Return to Summary" : "Next Issue"
    }

    private var keyPathInputMonitoringStatus: InstallationStatus {
        stateInterpreter.getPermissionStatus(.keyPathInputMonitoring, in: issues)
    }

    // Issue filtering for tooltips
    private var keyPathInputMonitoringIssues: [WizardIssue] {
        issues.filter { issue in
            if case let .permission(permissionType) = issue.identifier {
                return permissionType == .keyPathInputMonitoring
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
        Task {
            // Force a fresh validation snapshot so summary reflects the resolved permission
            await onRefresh()
            NotificationCenter.default.post(name: .kp_startupRevalidate, object: nil)

            if allIssues.isEmpty {
                navigationCoordinator.navigateToPage(.summary)
                return
            }

            if let nextPage = await navigationCoordinator.getNextPage(for: systemState, issues: allIssues),
               nextPage != navigationCoordinator.currentPage
            {
                navigationCoordinator.navigateToPage(nextPage)
            } else {
                navigationCoordinator.navigateToPage(.summary)
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
                        "🔐 [WizardInputMonitoringPage] Showing cleanup instructions for stale entries")
                } else {
                    // Always open settings manually - never auto-request
                    openInputMonitoringSettings()
                }
            }
        }
    }

    // Automatic prompt polling (Phase 1)
    // NOTE: Only poll for KeyPath permissions. Kanata doesn't need TCC entries because
    // it uses the Karabiner VirtualHIDDevice driver (communicates via IPC, runs as root).
    private func startPermissionPolling(for type: CoordinatorPermissionType) {
        permissionPollingTask?.cancel()
        permissionPollingTask = Task { [onRefresh] in
            var attempts = 0
            let maxAttempts = 20 // ~5s at 250ms intervals
            while attempts < maxAttempts {
                _ = await WizardSleep.ms(250)
                attempts += 1
                let snapshot = await PermissionOracle.shared.currentSnapshot()
                // Only check KeyPath permissions - Kanata doesn't need TCC
                let hasPermission: Bool =
                    switch type {
                    case .accessibility:
                        snapshot.keyPath.accessibility.isReady
                    case .inputMonitoring:
                        snapshot.keyPath.inputMonitoring.isReady
                    }
                if hasPermission {
                    await onRefresh()
                    return
                }
                if Task.isCancelled { return }
            }
        }
    }

    private func openInputMonitoringSettings() {
        AppLogger.shared.log(
            "🔧 [WizardInputMonitoringPage] Fix button clicked - permission flow starting")

        if FeatureFlags.useAutomaticPermissionPrompts {
            // Use automatic prompt via IOHIDRequestAccess()
            let alreadyGranted = PermissionRequestService.shared.requestInputMonitoringPermission(
                ignoreCooldown: true)
            if alreadyGranted {
                Task { await onRefresh() }
                return
            }

            // Poll for grant (KeyPath + Kanata) using Oracle snapshot
            startPermissionPolling(for: .inputMonitoring)

            // Fallback: if still not granted shortly after, open System Settings panel
            // NOTE: Only check KeyPath - Kanata doesn't need TCC permissions
            Task { @MainActor in
                for _ in 0 ..< 6 { // ~1.5s at 250ms
                    _ = await WizardSleep.ms(250)
                    let snapshot = await PermissionOracle.shared.currentSnapshot()
                    if snapshot.keyPath.inputMonitoring.isReady { return }
                }
                AppLogger.shared.info(
                    "ℹ️ [WizardInputMonitoringPage] Opening System Settings (fallback) for Input Monitoring")
                openInputMonitoringPreferencesPanel()
            }
        } else {
            // Fallback: manual System Settings flow
            // NOTE: Only KeyPath needs TCC. Kanata uses the Karabiner driver (runs as root).
            let instructions = """
            KeyPath will now close so you can grant permissions:

            1. Add KeyPath to Input Monitoring (use the '+' button)
            2. Make sure the checkbox is enabled
            3. Restart KeyPath when you're done

            KeyPath will automatically restart the keyboard service to pick up your new permissions.
            """

            PermissionGrantCoordinator.shared.initiatePermissionGrant(
                for: .inputMonitoring,
                instructions: instructions,
                onComplete: { onDismiss?() }
            )
        }
    }
}

private func openInputMonitoringPreferencesPanel() {
    if let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    {
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Stale Entry Cleanup Instructions View

struct StaleEntryCleanupInstructions: View {
    let staleEntryDetails: [String]
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Old KeyPath Entries Detected", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)

                Text(
                    "We've detected possible old or duplicate KeyPath entries that need to be cleaned up before granting new permissions."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
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
                                .foregroundStyle(.orange)
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                    .foregroundStyle(.yellow)
                Text("Tip: Entries with warning icons are from old or moved installations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

struct CleanupStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.blue)
                .frame(width: 20, alignment: .leading)

            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Preview

struct WizardInputMonitoringPage_Previews: PreviewProvider {
    static var previews: some View {
        let manager = RuntimeCoordinator()
        let viewModel = KanataViewModel(manager: manager)

        return WizardInputMonitoringPage(
            systemState: .missingPermissions(missing: [.keyPathInputMonitoring]),
            issues: [
                WizardIssue(
                    identifier: .permission(.keyPathInputMonitoring),
                    severity: .critical,
                    category: .permissions,
                    title: "Input Monitoring Required",
                    description: "KeyPath needs Input Monitoring permission to capture keyboard events.",
                    autoFixAction: nil,
                    userAction: "Grant permission in System Settings > Privacy & Security > Input Monitoring"
                )
            ],
            allIssues: [],
            stateInterpreter: WizardStateInterpreter(),
            onRefresh: {},
            onNavigateToPage: nil,
            onDismiss: nil,
            kanataManager: manager
        )
        .frame(width: WizardDesign.Layout.pageWidth)
        .fixedSize(horizontal: false, vertical: true)
        .environmentObject(viewModel)
    }
}
