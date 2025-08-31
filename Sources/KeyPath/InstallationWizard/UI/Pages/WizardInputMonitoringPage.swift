import SwiftUI

/// Input Monitoring permission page with hybrid permission request approach
struct WizardInputMonitoringPage: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let onRefresh: () async -> Void
    let onNavigateToPage: ((WizardPage) -> Void)?
    let onDismiss: (() -> Void)?
    let kanataManager: KanataManager

    @State private var showingStaleEntryCleanup = false
    @State private var staleEntryDetails: [String] = []

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

            // Bottom buttons - primary action changes based on state
            HStack {
                Spacer()

                if hasInputMonitoringIssues {
                    // When permissions needed, Grant Permission is primary
                    Button("Grant Permission") {
                        openInputMonitoringSettings()
                    }
                    .buttonStyle(WizardDesign.Component.PrimaryButton())

                    Button("Continue Anyway") {
                        AppLogger.shared.log("ℹ️ [Wizard] User continuing from Input Monitoring page despite issues")
                        navigationCoordinator.userInteractionMode = true
                        navigateToNextPage()
                    }
                    .buttonStyle(WizardDesign.Component.SecondaryButton())
                } else {
                    // When permissions granted, Continue is primary
                    Button("Continue") {
                        AppLogger.shared.log("ℹ️ [Wizard] User continuing from Input Monitoring page")
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
        .onAppear {
            checkForStaleEntries()
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

    // MARK: - Computed Properties

    private var hasInputMonitoringIssues: Bool {
        keyPathInputMonitoringStatus != .completed || kanataInputMonitoringStatus != .completed
    }

    private var keyPathInputMonitoringStatus: InstallationStatus {
        let hasKeyPathIssue = issues.contains { issue in
            if case let .permission(permissionType) = issue.identifier {
                return permissionType == .keyPathInputMonitoring
            }
            return false
        }
        return hasKeyPathIssue ? .notStarted : .completed
    }

    private var kanataInputMonitoringStatus: InstallationStatus {
        let hasKanataIssue = issues.contains { issue in
            if case let .permission(permissionType) = issue.identifier {
                return permissionType == .kanataInputMonitoring
            }
            return false
        }
        return hasKanataIssue ? .notStarted : .completed
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

    private func openInputMonitoringSettings() {
        AppLogger.shared.log("🔧 [WizardInputMonitoringPage] Fix button clicked - entering permission grant mode")

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
            onComplete: {
                // Close wizard after user confirms the dialog
                onDismiss?()
            }
        )
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
        WizardInputMonitoringPage(
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
            onRefresh: {},
            onNavigateToPage: nil,
            onDismiss: nil,
            kanataManager: KanataManager()
        )
        .frame(width: WizardDesign.Layout.pageWidth, height: WizardDesign.Layout.pageHeight)
    }
}
