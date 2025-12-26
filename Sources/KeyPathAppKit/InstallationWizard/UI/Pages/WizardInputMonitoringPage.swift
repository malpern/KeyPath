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
                                    Text("kanata")
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
                            Image(
                                systemName: keyPathInputMonitoringStatus == .completed
                                    ? "checkmark.circle.fill" : "xmark.circle.fill"
                            )
                            .foregroundColor(keyPathInputMonitoringStatus == .completed ? .green : .red)
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
                                Button("Fix") {
                                    openInputMonitoringSettings()
                                }
                                .buttonStyle(WizardDesign.Component.SecondaryButton())
                                .scaleEffect(0.8)
                            }
                        }
                        .help(keyPathInputMonitoringIssues.asTooltipText())

                        HStack(spacing: 12) {
                            Image(
                                systemName: kanataInputMonitoringStatus == .completed
                                    ? "checkmark.circle.fill" : "xmark.circle.fill"
                            )
                            .foregroundColor(kanataInputMonitoringStatus == .completed ? .green : .red)
                            HStack(spacing: 0) {
                                Text("kanata")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Text(" - Remapping engine needs permission")
                                    .font(.headline)
                                    .fontWeight(.regular)
                            }
                            Spacer()
                            if kanataInputMonitoringStatus != .completed {
                                Button("Fix") {
                                    AppLogger.shared.log(
                                        "🔧 [WizardInputMonitoringPage] Kanata Fix clicked - opening System Settings and revealing kanata"
                                    )
                                    openInputMonitoringPreferencesPanel()
                                    revealKanataInFinder()
                                    startPermissionPolling(for: .inputMonitoring)
                                }
                                .buttonStyle(WizardDesign.Component.SecondaryButton())
                                .scaleEffect(0.8)
                            }
                        }
                        .help(kanataInputMonitoringIssues.asTooltipText())
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

    private var hasInputMonitoringIssues: Bool {
        keyPathInputMonitoringStatus != .completed || kanataInputMonitoringStatus != .completed
    }

    private var nextStepButtonTitle: String {
        allIssues.isEmpty ? "Return to Summary" : "Next Issue"
    }

    private var keyPathInputMonitoringStatus: InstallationStatus {
        stateInterpreter.getPermissionStatus(.keyPathInputMonitoring, in: issues)
    }

    private var kanataInputMonitoringStatus: InstallationStatus {
        stateInterpreter.getPermissionStatus(.kanataInputMonitoring, in: issues)
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
        if allIssues.isEmpty {
            navigationCoordinator.navigateToPage(.summary)
            return
        }

        Task {
            if let nextPage = await navigationCoordinator.getNextPage(for: systemState, issues: allIssues),
               nextPage != navigationCoordinator.currentPage {
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
    private func startPermissionPolling(for type: CoordinatorPermissionType) {
        permissionPollingTask?.cancel()
        permissionPollingTask = Task { [onRefresh] in
            var attempts = 0
            let maxAttempts = 20 // ~5s at 250ms intervals
            while attempts < maxAttempts {
                _ = await WizardSleep.ms(250)
                attempts += 1
                let snapshot = await PermissionOracle.shared.currentSnapshot()
                let hasPermission: Bool =
                    switch type {
                    case .accessibility:
                        snapshot.keyPath.accessibility.isReady && snapshot.kanata.accessibility.isReady
                    case .inputMonitoring:
                        snapshot.keyPath.inputMonitoring.isReady && snapshot.kanata.inputMonitoring.isReady
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
            Task { @MainActor in
                for _ in 0 ..< 6 { // ~1.5s at 250ms
                    _ = await WizardSleep.ms(250)
                    let snapshot = await PermissionOracle.shared.currentSnapshot()
                    let granted =
                        snapshot.keyPath.inputMonitoring.isReady && snapshot.kanata.inputMonitoring.isReady
                    if granted { return }
                }
                AppLogger.shared.info(
                    "ℹ️ [WizardInputMonitoringPage] Opening System Settings (fallback) for Input Monitoring")
                openInputMonitoringPreferencesPanel()
            }
        } else {
            // Fallback: manual System Settings flow
            let instructions = """
            KeyPath will now close so you can grant permissions:

            1. Add KeyPath and kanata to Input Monitoring (use the '+' button)
            2. Make sure both checkboxes are enabled
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
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Helpers for Kanata add flow

private func revealKanataInFinder() {
    let path = WizardSystemPaths.kanataSystemInstallPath
    let dir = (path as NSString).deletingLastPathComponent
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    _ = NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: dir)
    AppLogger.shared.log("📂 [WizardInputMonitoringPage] Revealed kanata in Finder: \(path)")
}

private func copyKanataPathToClipboard() {
    let path = WizardSystemPaths.kanataSystemInstallPath
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(path, forType: .string)
    AppLogger.shared.log("📋 [WizardInputMonitoringPage] Copied kanata path to clipboard: \(path)")
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
                .cornerRadius(8)
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
                CleanupStep(number: 6, text: "Also add 'kanata' if needed")
            }
            .padding()
            .background(Color.blue.opacity(0.05))
            .cornerRadius(8)

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

struct CleanupStep: View {
    let number: Int
    let text: String

    var body: some View {
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
