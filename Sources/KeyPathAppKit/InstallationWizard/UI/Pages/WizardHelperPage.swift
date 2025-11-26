import KeyPathCore
import KeyPathWizardCore
import ServiceManagement
import SwiftUI

/// Privileged Helper installation and validation page
struct WizardHelperPage: View {
    // MARK: - Properties (following wizard page pattern)

    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let isFixing: Bool
    let onAutoFix: (AutoFixAction) async -> Bool
    let onRefresh: () -> Void
    let kanataManager: RuntimeCoordinator

    // MARK: - State

    @State private var isWorking = false
    @State private var lastError: String?
    @State private var helperVersion: String?
    @State private var bundledVersion: String?
    @State private var duplicateCopies: [String] = []
    @State private var needsLoginItemsApproval = false
    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator
    @EnvironmentObject var toastManager: WizardToastManager

    /// Check if bundled helper is newer than installed helper
    private var hasUpdateAvailable: Bool {
        guard let installed = helperVersion, let bundled = bundledVersion else { return false }
        return bundled.compare(installed, options: .numeric) == .orderedDescending
    }

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
            bundledVersion = getBundledHelperVersion()
            // Check if Login Items approval is needed
            needsLoginItemsApproval = checkLoginItemsApprovalNeeded()
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
            // Show update link if newer version bundled
            if hasUpdateAvailable {
                Button("Update to v\(bundledVersion ?? "")") {
                    Task { await installOrRepairHelper() }
                }
                .buttonStyle(WizardDesign.Component.SecondaryButton())
                .disabled(isWorking)

                Text("New helper version available with additional features")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(nextStepButtonTitle) {
                navigateToNextStep()
            }
            .buttonStyle(WizardDesign.Component.PrimaryButton())
            .keyboardShortcut(.defaultAction)
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
                            .foregroundColor(
                                isInstalled ? WizardDesign.Colors.warning : WizardDesign.Colors.error
                            )
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
                Text(
                    "The privileged helper enables system operations without repeated admin password prompts."
                )
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            }

            // Show Login Items approval message if needed
            if needsLoginItemsApproval {
                VStack(spacing: 12) {
                    Text("Login Items approval required")
                        .font(.headline)
                        .foregroundColor(.orange)

                    Text("Enable KeyPath in System Settings → Login Items to allow the helper to run.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)

                    Button("Open Login Items Settings") {
                        openLoginItemsSettings()
                    }
                    .buttonStyle(WizardDesign.Component.PrimaryButton())
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.vertical, 8)
            } else {
                // Single idempotent action: install or repair (performs cleanup + install)
                Button(isInstalled ? "Repair Helper" : "Install Helper") {
                    Task { await installOrRepairHelper() }
                }
                .buttonStyle(WizardDesign.Component.PrimaryButton())
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking || isFixing)
            }

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
                    .foregroundColor(lastError.localizedCaseInsensitiveContains("success")
                        ? .green : .orange)
                    .padding(.horizontal, 40)
                    .multilineTextAlignment(.center)
                // If approval is required, offer a quick link to System Settings
                if lastError.localizedCaseInsensitiveContains("approval required") {
                    Button("Open System Settings → Login Items") {
                        openLoginItemsSettings()
                    }
                    .buttonStyle(WizardDesign.Component.SecondaryButton())
                }
            }
        }
        .padding(.horizontal, 60)
        .heroSectionContainer()
    }

    // MARK: - Actions

    private func installOrRepairHelper() async {
        await withWorking {
            let ok = await HelperMaintenance.shared.runCleanupAndRepair(useAppleScriptFallback: true)
            if ok {
                lastError = "Helper installed and responding"
                helperVersion = await HelperManager.shared.getHelperVersion()
            } else {
                // Surface the last maintenance log line as a hint
                let hint = HelperMaintenance.shared.logLines.last
                    ?? "Unknown error (helper XPC not reachable)"
                lastError = "Helper install/repair failed:\n\(hint)"
                toastManager.showError(lastError ?? "Helper install failed", duration: 6.0)
            }
            onRefresh()
        }
    }

    private func withWorking(_ body: @escaping () async -> Void) async {
        await MainActor.run {
            isWorking = true
            lastError = nil
        }
        defer { Task { await MainActor.run { isWorking = false } } }
        await body()
    }

    private func openSystemSettings() {
        // Best-effort: open System Settings; deep-linking to Login Items is OS-version dependent
        let url = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        NSWorkspace.shared.openApplication(
            at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil
        )
    }

    private func openLoginItemsSettings() {
        // Open System Settings directly to Login Items pane
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        } else {
            openSystemSettings()
        }
    }

    private func checkLoginItemsApprovalNeeded() -> Bool {
        let svc = ServiceManagement.SMAppService.daemon(plistName: HelperManager.helperPlistName)
        return svc.status == .requiresApproval
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

    /// Get the version of the helper bundled with this app
    private func getBundledHelperVersion() -> String? {
        guard let bundlePath = Bundle.main.bundlePath as String? else { return nil }
        let helperInfoPath = "\(bundlePath)/Contents/Library/HelperTools/KeyPathHelper"

        // Try to read version from the helper's Info.plist sibling or embedded
        // For simplicity, we'll use a hardcoded version that matches HelperService.swift
        // In production, this should read from the helper's Info.plist
        let plistPath = "\(bundlePath)/Contents/Library/LaunchDaemons/com.keypath.helper.plist"
        guard FileManager.default.fileExists(atPath: helperInfoPath) else { return nil }

        // Read version from helper's Info.plist in Sources
        // For now, return the known bundled version
        return "1.1.0"
    }
}
