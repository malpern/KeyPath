import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import SwiftUI

/// Input Monitoring permission page with hybrid permission request approach
struct WizardInputMonitoringPage: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let stateInterpreter: WizardStateInterpreter
    let onRefresh: () async -> Void
    let onNavigateToPage: ((WizardPage) -> Void)?
    let onDismiss: (() -> Void)?
    let kanataManager: KanataManager

    @State private var showingStaleEntryCleanup = false
    @State private var staleEntryDetails: [String] = []
    @State private var permissionPollingTask: Task<Void, Never>?

    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator

    var body: some View {
        VStack(spacing: 0) {
            // Use experimental hero design when permissions are granted
            if !hasInputMonitoringIssues {
                VStack(spacing: 0) {
                    Spacer()

                    // Centered hero block with padding
                    VStack(spacing: WizardDesign.Spacing.sectionGap) {
                        // Green eye icon with green check overlay
                        ZStack {
                            Image(systemName: "eye")
                                .font(.system(size: 115, weight: .light))
                                .foregroundColor(WizardDesign.Colors.success)
                                .symbolRenderingMode(.hierarchical)
                                .modifier(AvailabilitySymbolBounce())

                            // Green check overlay in top right
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 40, weight: .medium))
                                        .foregroundColor(WizardDesign.Colors.success)
                                        .background(WizardDesign.Colors.wizardBackground)
                                        .clipShape(Circle())
                                }
                                Spacer()
                            }
                            .frame(width: 115, height: 115)
                        }

                        // Headline
                        Text("Input Monitoring")
                            .font(.system(size: 23, weight: .semibold, design: .default))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        // Subtitle
                        Text("KeyPath has permission to capture keyboard events")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

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
                        // Orange eye icon with warning overlay
                        ZStack {
                            Image(systemName: "eye")
                                .font(.system(size: 115, weight: .light))
                                .foregroundColor(WizardDesign.Colors.warning)
                                .symbolRenderingMode(.hierarchical)
                                .modifier(AvailabilitySymbolBounce())

                            // Warning overlay in top right
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 40, weight: .medium))
                                        .foregroundColor(WizardDesign.Colors.warning)
                                        .background(WizardDesign.Colors.wizardBackground)
                                        .clipShape(Circle())
                                }
                                Spacer()
                            }
                            .frame(width: 115, height: 115)
                        }

                        // Headline
                        Text("Input Monitoring Required")
                            .font(.system(size: 23, weight: .semibold, design: .default))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        // Subtitle
                        Text("KeyPath needs Input Monitoring permission to capture keyboard events for remapping")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        // Component details for error state
                        VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                            HStack(spacing: 12) {
                                Image(systemName: keyPathInputMonitoringStatus == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
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
                                Image(systemName: kanataInputMonitoringStatus == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
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
                                        openInputMonitoringSettings()
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
                        .padding(.top, WizardDesign.Spacing.sectionGap)

                        // Check Again link
                        Button("Check Again") {
                            Task {
                                await onRefresh()

                                // Oracle handles permission state - no manual marking needed
                                AppLogger.shared.log("🔮 [WizardInputMonitoringPage] Oracle will detect permission changes automatically")
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

            // Bottom buttons - HIG compliant button order
            if hasInputMonitoringIssues {
                // When permissions needed: Cancel (left) | Continue Anyway (middle) | Grant Permission (right, primary)
                WizardButtonBar(
                    cancel: WizardButtonBar.CancelButton(title: "Back", action: navigateToPreviousPage),
                    secondary: WizardButtonBar.SecondaryButton(title: "Continue Anyway") {
                        AppLogger.shared.log("ℹ️ [Wizard] User continuing from Input Monitoring page despite issues")
                        navigationCoordinator.userInteractionMode = true
                        navigateToNextPage()
                    },
                    primary: WizardButtonBar.PrimaryButton(title: "Grant Permission", action: openInputMonitoringSettings)
                )
            } else {
                // When permissions granted: Cancel (left) | Continue (right, primary)
                WizardButtonBar(
                    cancel: WizardButtonBar.CancelButton(title: "Back", action: navigateToPreviousPage),
                    primary: WizardButtonBar.PrimaryButton(title: "Continue") {
                        AppLogger.shared.log("ℹ️ [Wizard] User continuing from Input Monitoring page")
                        navigateToNextPage()
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WizardDesign.Colors.wizardBackground)
        .onAppear {
            checkForStaleEntries()
        }
        .onDisappear {
            permissionPollingTask?.cancel()
            permissionPollingTask = nil
        }
    }

    // MARK: - Helper Methods

    private func navigateToNextPage() {
        if let next = navigationCoordinator.getNextPage(for: systemState, issues: issues) {
            navigationCoordinator.userInteractionMode = true // respect user choice
            navigationCoordinator.navigateToPage(next)
            AppLogger.shared.log("➡️ [Input Monitoring] Navigated to next page: \(next.displayName)")
        } else {
            AppLogger.shared.log("ℹ️ [Input Monitoring] No next page determined by NavigationEngine")
            onDismiss?()
        }
    }

    private func navigateToPreviousPage() {
        let allPages = WizardPage.allCases
        guard let currentIndex = allPages.firstIndex(of: navigationCoordinator.currentPage),
              currentIndex > 0
        else { return }
        let previousPage = allPages[currentIndex - 1]
        navigationCoordinator.navigateToPage(previousPage)
        AppLogger.shared.log("⬅️ [Input Monitoring] Navigated to previous page: \(previousPage.displayName)")
    }

    // MARK: - Computed Properties

    private var hasInputMonitoringIssues: Bool {
        keyPathInputMonitoringStatus != .completed || kanataInputMonitoringStatus != .completed
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
            let maxAttempts = 30 // 30 seconds
            while attempts < maxAttempts {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                attempts += 1
                let snapshot = await PermissionOracle.shared.currentSnapshot()
                let hasPermission: Bool = {
                    switch type {
                    case .accessibility:
                        return snapshot.keyPath.accessibility.isReady && snapshot.kanata.accessibility.isReady
                    case .inputMonitoring:
                        return snapshot.keyPath.inputMonitoring.isReady && snapshot.kanata.inputMonitoring.isReady
                    }
                }()
                if hasPermission {
                    await onRefresh()
                    return
                }
                if Task.isCancelled { return }
            }
        }
    }

    private func openInputMonitoringSettings() {
        AppLogger.shared.log("🔧 [WizardInputMonitoringPage] Fix button clicked - permission flow starting")

        if FeatureFlags.useAutomaticPermissionPrompts {
            // Use automatic prompt via IOHIDRequestAccess()
            let alreadyGranted = PermissionRequestService.shared.requestInputMonitoringPermission()
            if alreadyGranted {
                Task { await onRefresh() }
                return
            }

            // Poll for grant (KeyPath + Kanata) using Oracle snapshot
            startPermissionPolling(for: .inputMonitoring)
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
        let manager = KanataManager()
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
            stateInterpreter: WizardStateInterpreter(),
            onRefresh: {},
            onNavigateToPage: nil,
            onDismiss: nil,
            kanataManager: manager
        )
        .frame(width: WizardDesign.Layout.pageWidth, height: WizardDesign.Layout.pageHeight)
        .environmentObject(viewModel)
    }
}
