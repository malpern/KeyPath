import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import SwiftUI

/// Accessibility permission page - dedicated page for Accessibility permissions
struct WizardAccessibilityPage: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let allIssues: [WizardIssue]
    let onRefresh: () async -> Void
    let onNavigateToPage: ((WizardPage) -> Void)?
    let onDismiss: (() -> Void)?
    let kanataManager: RuntimeCoordinator
    @State private var permissionPollingTask: Task<Void, Never>?

    @EnvironmentObject var stateMachine: WizardStateMachine

    private func statusIcon(for status: InstallationStatus) -> (name: String, color: Color) {
        switch status {
        case .completed:
            ("checkmark.circle.fill", .green)
        case .warning:
            ("questionmark.circle.fill", .orange)
        case .failed:
            ("xmark.circle.fill", .red)
        case .notStarted, .inProgress:
            ("ellipsis.circle", .secondary)
        }
    }

    private func kanataSubtitle(for status: InstallationStatus) -> String {
        switch status {
        case .completed:
            " - Keyboard monitoring engine"
        case .warning:
            " - Permission not verified"
        case .failed, .notStarted, .inProgress:
            " - Keyboard monitoring engine"
        }
    }

    // State interpreter for consistent status computation
    private let stateInterpreter = WizardStateInterpreter()

    var body: some View {
        VStack(spacing: 0) {
            // Use experimental hero design when permissions are granted
            if !hasAccessibilityIssues {
                VStack(spacing: WizardDesign.Spacing.sectionGap) {
                    WizardHeroSection.success(
                        icon: "accessibility",
                        title: "Accessibility",
                        subtitle: "KeyPath has system-level access for keyboard monitoring & safety controls",
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
                                    Text("kanata")
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
                        icon: "accessibility",
                        title: "Accessibility",
                        subtitle: "Turn on KeyPath in Accessibility, then add and turn on kanata",
                        iconTapAction: {
                            Task {
                                await onRefresh()
                            }
                        }
                    )

                    // Guard: recommend running from /Applications for stable permissions
                    if !isRunningFromApplicationsFolder {
                        Text("For the smoothest setup, move KeyPath to /Applications and relaunch.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, WizardDesign.Spacing.elementGap)
                    }

                    // Action link below the subheader
                    Button("Open Settings Manually") {
                        openAccessibilitySettings()
                    }
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
                                        reason: "Accessibility permission fix for KeyPath.app")
                                    openAccessibilityPermissionGrant()
                                }
                                .buttonStyle(WizardDesign.Component.SecondaryButton())
                                .scaleEffect(0.8)
                            }
                        }
                        .help(keyPathAccessibilityIssues.asTooltipText())

                        HStack(spacing: 12) {
                            let icon = statusIcon(for: kanataAccessibilityStatus)
                            Image(systemName: icon.name)
                                .foregroundColor(icon.color)
                            HStack(spacing: 0) {
                                Text("kanata")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Text(kanataSubtitle(for: kanataAccessibilityStatus))
                                    .font(.headline)
                                    .fontWeight(.regular)
                            }
                            Spacer()
                            if kanataAccessibilityStatus != .completed {
                                Button("Fix") {
                                    AppLogger.shared.log(
                                        "🔘 [WizardAccessibilityPage] Fix clicked for kanata - opening System Settings and revealing kanata"
                                    )
                                    let path = WizardSystemPaths.kanataSystemInstallPath
                                    if !FileManager.default.fileExists(atPath: path) {
                                        AppLogger.shared.warn(
                                            "⚠️ [WizardAccessibilityPage] Kanata system binary missing at \(path) - routing to Kanata Components"
                                        )
                                        stateMachine.navigateToPage(.kanataComponents)
                                        return
                                    }
                                    openAccessibilitySettings()
                                    revealKanataInFinder()
                                }
                                .buttonStyle(WizardDesign.Component.SecondaryButton())
                                .scaleEffect(0.8)
                            }
                        }
                        .help(kanataAccessibilityIssues.asTooltipText())
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
        .background(WizardDesign.Colors.wizardBackground)
        .wizardDetailPage()
        .onAppear {
            // Start passive polling to reflect manual changes in System Settings
            if permissionPollingTask == nil {
                permissionPollingTask = Task { [onRefresh] in
                    var lastKeyPathGranted: Bool?
                    var lastKanataGranted: Bool?
                    while !Task.isCancelled {
                        let snapshot = await PermissionOracle.shared.currentSnapshot()
                        let kpGranted = snapshot.keyPath.accessibility.isReady
                        let kaGranted = snapshot.kanata.accessibility.isReady
                        if lastKeyPathGranted != kpGranted || lastKanataGranted != kaGranted {
                            AppLogger.shared.log(
                                "🔁 [WizardAccessibilityPage] Passive AX change detected - KeyPath: \(kpGranted), Kanata: \(kaGranted). Refreshing UI."
                            )
                            lastKeyPathGranted = kpGranted
                            lastKanataGranted = kaGranted
                            await onRefresh()
                        }
                        // Poll every 250ms up to 1s to reflect changes promptly without long sleeps
                        _ = await WizardSleep.ms(250)
                    }
                }
            }
        }
        .onDisappear {
            permissionPollingTask?.cancel()
            permissionPollingTask = nil
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
        stateInterpreter.getPermissionStatus(.keyPathAccessibility, in: issues)
    }

    private var kanataAccessibilityStatus: InstallationStatus {
        let status = stateInterpreter.getPermissionStatus(.kanataAccessibility, in: issues)
        AppLogger.shared.log("🔍 [WizardAccessibilityPage] kanataAccessibilityStatus: \(status)")
        return status
    }

    // Issue filtering for tooltips
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

        let alreadyGranted = PermissionRequestService.shared.requestAccessibilityPermission(
            ignoreCooldown: true)
        if alreadyGranted {
            Task { await onRefresh() }
            return
        }
        // Poll for grant (KeyPath + Kanata) using Oracle snapshot
        permissionPollingTask?.cancel()
        permissionPollingTask = Task { [onRefresh] in
            var attempts = 0
            let maxAttempts = 30
            var lastKeyPathGranted: Bool?
            var lastKanataGranted: Bool?
            while attempts < maxAttempts {
                _ = await WizardSleep.ms(1000)
                attempts += 1
                let snapshot = await PermissionOracle.shared.currentSnapshot()
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
        Task { @MainActor in
            _ = await WizardSleep.ms(1500) // 1.5s
            let snapshot = await PermissionOracle.shared.currentSnapshot()
            let granted =
                snapshot.keyPath.accessibility.isReady && snapshot.kanata.accessibility.isReady
            if !granted {
                AppLogger.shared.info(
                    "ℹ️ [WizardAccessibilityPage] Opening System Settings (fallback) for Accessibility")
                openAccessibilitySettings()
            }
        }
    }

    private func openAccessibilitySettings() {
        AppLogger.shared.log(
            "🔐 [WizardAccessibilityPage] Opening Accessibility settings manually")

        // Fallback: Open System Settings > Privacy & Security > Accessibility
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            let ok = NSWorkspace.shared.open(url)
            if !ok {
                // Fallback: open System Settings app if deep-link fails
                _ = NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
            }
        }
    }

    private func navigateToNextStep() {
        if allIssues.isEmpty {
            stateMachine.navigateToPage(.summary)
            return
        }

        Task {
            if let nextPage = await stateMachine.getNextPage(for: systemState, issues: allIssues),
               nextPage != stateMachine.currentPage {
                stateMachine.navigateToPage(nextPage)
            } else {
                stateMachine.navigateToPage(.summary)
            }
        }
    }

    private func revealKanataInFinder() {
        let path = WizardSystemPaths.kanataSystemInstallPath
        let dir = (path as NSString).deletingLastPathComponent
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        AppLogger.shared.log("📂 [WizardAccessibilityPage] Revealed kanata in Finder: \(path)")
        // If NSWorkspace.selectFile is preferred:
        _ = NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: dir)
    }

    private func copyKanataPathToClipboard() {
        let path = WizardSystemPaths.kanataSystemInstallPath
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(path, forType: .string)
        AppLogger.shared.log("📋 [WizardAccessibilityPage] Copied kanata path to clipboard: \(path)")
    }
}

// MARK: - Preview

struct WizardAccessibilityPage_Previews: PreviewProvider {
    static var previews: some View {
        let manager = RuntimeCoordinator()
        let viewModel = KanataViewModel(manager: manager)

        return WizardAccessibilityPage(
            systemState: .missingPermissions(missing: [.keyPathAccessibility]),
            issues: [
                WizardIssue(
                    identifier: .permission(.keyPathAccessibility),
                    severity: .critical,
                    category: .permissions,
                    title: "Accessibility Required",
                    description: "KeyPath needs Accessibility permission to monitor keyboard events.",
                    autoFixAction: nil,
                    userAction: "Grant permission in System Settings > Privacy & Security > Accessibility"
                )
            ],
            allIssues: [],
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
