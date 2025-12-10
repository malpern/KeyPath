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

    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator

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
                                    Text(" - Has permission for emergency stop and system monitoring")
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
                        icon: "accessibility",
                        title: "Accessibility",
                        subtitle: "Turn on KeyPath in Accessibility for emergency stop and system monitoring",
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
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, WizardDesign.Spacing.elementGap)
                    }

                    // Action link below the subheader
                    Button("Open Settings Manually") {
                        openAccessibilitySettings()
                    }
                    .buttonStyle(.link)
                    .padding(.top, WizardDesign.Spacing.elementGap)

                    // Component details for error state - only KeyPath needs TCC
                    VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                        HStack(spacing: 12) {
                            Image(
                                systemName: keyPathAccessibilityStatus == .completed
                                    ? "checkmark.circle.fill" : "xmark.circle.fill"
                            )
                            .foregroundStyle(keyPathAccessibilityStatus == .completed ? .green : Color.red)
                            HStack(spacing: 0) {
                                Text("KeyPath.app")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Text(" - Needs permission for emergency stop detection")
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
            // Start passive polling to reflect manual changes in System Settings
            // NOTE: Only poll for KeyPath - Kanata doesn't need TCC permissions
            if permissionPollingTask == nil {
                permissionPollingTask = Task { [onRefresh] in
                    var lastKeyPathGranted: Bool?
                    while !Task.isCancelled {
                        let snapshot = await PermissionOracle.shared.currentSnapshot()
                        let kpGranted = snapshot.keyPath.accessibility.isReady
                        if lastKeyPathGranted != kpGranted {
                            AppLogger.shared.log(
                                "🔁 [WizardAccessibilityPage] Passive AX change detected - KeyPath: \(kpGranted). Refreshing UI."
                            )
                            lastKeyPathGranted = kpGranted
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

    // NOTE: Only KeyPath needs Accessibility TCC permission.
    // Kanata uses the Karabiner VirtualHIDDevice driver and communicates via IPC,
    // so it doesn't need TCC entries (it runs as root via SMAppService/LaunchDaemon).
    private var hasAccessibilityIssues: Bool {
        keyPathAccessibilityStatus != .completed
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

    // Issue filtering for tooltips
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

        if FeatureFlags.useAutomaticPermissionPrompts {
            let alreadyGranted = PermissionRequestService.shared.requestAccessibilityPermission(
                ignoreCooldown: true)
            if alreadyGranted {
                Task { await onRefresh() }
                return
            }
            // Poll for grant (KeyPath only - Kanata doesn't need TCC)
            permissionPollingTask?.cancel()
            permissionPollingTask = Task { [onRefresh] in
                var attempts = 0
                let maxAttempts = 30
                var lastKeyPathGranted: Bool?
                while attempts < maxAttempts {
                    _ = await WizardSleep.ms(1000)
                    attempts += 1
                    let snapshot = await PermissionOracle.shared.currentSnapshot()
                    let kpGranted = snapshot.keyPath.accessibility.isReady

                    // Incremental refresh: update UI when status changes
                    if lastKeyPathGranted != kpGranted {
                        AppLogger.shared.log(
                            "🔁 [WizardAccessibilityPage] Detected permission change (AX) - KeyPath: \(kpGranted). Refreshing UI."
                        )
                        lastKeyPathGranted = kpGranted
                        await onRefresh()
                    }

                    if kpGranted {
                        // KeyPath ready – stop polling
                        return
                    }
                    if Task.isCancelled { return }
                }
            }
            // Fallback: if not granted shortly, open Accessibility settings so the user can toggle
            Task { @MainActor in
                _ = await WizardSleep.ms(1500) // 1.5s
                let snapshot = await PermissionOracle.shared.currentSnapshot()
                if !snapshot.keyPath.accessibility.isReady {
                    AppLogger.shared.info(
                        "ℹ️ [WizardAccessibilityPage] Opening System Settings (fallback) for Accessibility")
                    openAccessibilitySettings()
                }
            }
        } else {
            // Fallback: manual System Settings flow
            // NOTE: Only KeyPath needs TCC. Kanata uses the Karabiner driver (runs as root).
            let instructions = """
            KeyPath will now close so you can grant permissions:

            1. Add KeyPath to Accessibility (use the '+' button)
            2. Make sure the checkbox is enabled
            3. Restart KeyPath when you're done

            KeyPath will automatically restart the keyboard service to pick up your new permissions.
            """

            PermissionGrantCoordinator.shared.initiatePermissionGrant(
                for: .accessibility,
                instructions: instructions,
                onComplete: { onDismiss?() }
            )
        }
    }

    private func openAccessibilitySettings() {
        AppLogger.shared.log(
            "🔐 [WizardAccessibilityPage] Opening Accessibility settings manually")

        // Fallback: Open System Settings > Privacy & Security > Accessibility
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            NSWorkspace.shared.open(url)
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
