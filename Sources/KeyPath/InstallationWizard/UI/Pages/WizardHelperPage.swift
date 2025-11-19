import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Privileged Helper installation and validation page
struct WizardHelperPage: View {
    // MARK: - Properties (following wizard page pattern)

    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let isFixing: Bool
    let onAutoFix: (AutoFixAction) async -> Bool
    let onRefresh: () -> Void
    let kanataManager: KanataManager

    // MARK: - State

    @State private var isWorking = false
    @State private var lastError: String?
    @State private var helperVersion: String?
    @State private var duplicateCopies: [String] = []
    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator

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

    private var versionText: String {
        if let helperVersion {
            "Helper is installed and working (v\(helperVersion))"
        } else {
            "Helper is installed and working"
        }
    }

    private var nextStepButtonTitle: String {
        issues.isEmpty ? "Return to Summary" : "Next Issue"
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
        }
        .onAppear {
            duplicateCopies = HelperMaintenance.shared.detectDuplicateAppCopies()
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

            // Headline
            Text("Privileged Helper")
                .font(.system(size: 23, weight: .semibold, design: .default))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            // Subtitle
            Text(versionText)
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

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
            Button(nextStepButtonTitle) {
                navigateToNextStep()
            }
            .buttonStyle(WizardDesign.Component.PrimaryButton())
            .padding(.top, WizardDesign.Spacing.sectionGap)
        }
        .heroSectionContainer()
    }

    // MARK: - Setup View (Hero Style for Error State)

    private var setupView: some View {
        VStack(spacing: WizardDesign.Spacing.sectionGap) {
            // Icon with warning/error overlay
            ZStack {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 115, weight: .light))
                    .foregroundColor(isInstalled ? WizardDesign.Colors.warning : WizardDesign.Colors.error)
                    .symbolRenderingMode(.hierarchical)

                // Warning/Error overlay
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: isInstalled ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundColor(isInstalled ? WizardDesign.Colors.warning : WizardDesign.Colors.error)
                            .background(WizardDesign.Colors.wizardBackground)
                            .clipShape(Circle())
                            .offset(x: 15, y: -5)
                    }
                    Spacer()
                }
                .frame(width: 115, height: 115)
            }

            // Headline
            Text("Privileged Helper")
                .font(.system(size: 23, weight: .semibold, design: .default))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            // Subtitle
            Text(isInstalled ? "Helper is installed but not responding" : "Helper is not installed")
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Description (show only when not installed; suppress for 'installed but not responding')
            if !isInstalled {
                Text("The privileged helper enables system operations without repeated admin password prompts.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Install/Reinstall button
            if !isInstalled {
                Button("Install Helper") {
                    Task { await installHelper() }
                }
                .buttonStyle(WizardDesign.Component.PrimaryButton())
                .disabled(isWorking || isFixing)
            } else {
                Button("Reinstall Helper") {
                    Task { await reinstallHelper() }
                }
                .buttonStyle(WizardDesign.Component.PrimaryButton())
                .disabled(isWorking || isFixing)
            }

            // Cleanup & Repair CTA
            Button("Cleanup & Repair…") {
                Task { await cleanupAndRepair() }
            }
            .buttonStyle(WizardDesign.Component.SecondaryButton())
            .disabled(isWorking || isFixing)

            if duplicateCopies.count > 1 {
                Button("Reveal App Copies in Finder") {
                    for p in duplicateCopies {
                        let url = URL(fileURLWithPath: p)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                .buttonStyle(WizardDesign.Component.SecondaryButton())
            }

            // Error message if present
            if let lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundColor(lastError.contains("successfully") ? .green : .orange)
                    .padding(.horizontal, 40)
                    .multilineTextAlignment(.center)
                // If approval is required, offer a quick link to System Settings
                if lastError.localizedCaseInsensitiveContains("approval required") {
                    Button("Open System Settings → Login Items") {
                        openSystemSettings()
                    }
                    .buttonStyle(WizardDesign.Component.SecondaryButton())
                }
            }
        }
        .padding(.horizontal, 60)
        .heroSectionContainer()
    }

    // MARK: - Actions

    private func installHelper() async {
        await withWorking {
            let success = await onAutoFix(.installPrivilegedHelper)
            if success {
                lastError = "Helper installed successfully"
                // Refresh version
                helperVersion = await HelperManager.shared.getHelperVersion()
            } else {
                lastError = "Failed to install helper"
            }
            onRefresh()
        }
    }

    private func reinstallHelper() async {
        await withWorking {
            let success = await onAutoFix(.reinstallPrivilegedHelper)
            if success {
                lastError = "Helper reinstalled successfully"
                // Refresh version
                helperVersion = await HelperManager.shared.getHelperVersion()
            } else {
                lastError = "Failed to reinstall helper"
            }
            onRefresh()
        }
    }

    private func cleanupAndRepair() async {
        await withWorking {
            let ok = await HelperMaintenance.shared.runCleanupAndRepair(useAppleScriptFallback: true)
            if ok {
                lastError = "Cleanup complete - helper is responding"
                helperVersion = await HelperManager.shared.getHelperVersion()
            } else {
                lastError = "Cleanup attempted, but helper is still not responding"
            }
            onRefresh()
        }
    }

    private func withWorking(_ body: @escaping () async -> Void) async {
        await MainActor.run { isWorking = true; lastError = nil }
        defer { Task { await MainActor.run { isWorking = false } } }
        await body()
    }

    private func openSystemSettings() {
        // Best-effort: open System Settings; deep-linking to Login Items is OS-version dependent
        let url = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    private func navigateToNextStep() {
        if issues.isEmpty {
            navigationCoordinator.navigateToPage(.summary)
            return
        }

        if let next = navigationCoordinator.getNextPage(for: systemState, issues: issues),
           next != navigationCoordinator.currentPage {
            navigationCoordinator.navigateToPage(next)
        } else {
            navigationCoordinator.navigateToPage(.summary)
        }
    }
}
