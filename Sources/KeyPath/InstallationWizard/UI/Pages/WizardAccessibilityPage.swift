import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import SwiftUI

/// Accessibility permission page - dedicated page for Accessibility permissions
struct WizardAccessibilityPage: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let onRefresh: () async -> Void
    let onNavigateToPage: ((WizardPage) -> Void)?
    let onDismiss: (() -> Void)?
    let kanataManager: KanataManager
    @State private var permissionPollingTask: Task<Void, Never>?

    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator

    // State interpreter for consistent status computation
    private let stateInterpreter = WizardStateInterpreter()

    var body: some View {
        VStack(spacing: 0) {
            // Use experimental hero design when permissions are granted
            if !hasAccessibilityIssues {
                VStack(spacing: 0) {
                    Spacer()

                    // Centered hero block with padding
                    VStack(spacing: WizardDesign.Spacing.sectionGap) {
                        // Green accessibility icon with green check overlay
                        ZStack {
                            Image(systemName: "accessibility")
                                .font(.system(size: 115, weight: .light))
                                .foregroundColor(WizardDesign.Colors.success)
                                .symbolRenderingMode(.hierarchical)
                                .modifier(AvailabilitySymbolBounce())

                            // Green check overlay positioned at right edge
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 40, weight: .medium))
                                        .foregroundColor(WizardDesign.Colors.success)
                                        .background(WizardDesign.Colors.wizardBackground)
                                        .clipShape(Circle())
                                        .offset(x: 15, y: -5) // Move further right and slightly up
                                }
                                Spacer()
                            }
                            .frame(width: 140, height: 115)
                        }

                        // Headline
                        Text("Accessibility")
                            .font(.system(size: 23, weight: .semibold, design: .default))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        // Subtitle
                        Text("KeyPath has system-level access for keyboard monitoring & safety controls")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)

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
                        // Orange accessibility icon with warning overlay
                        ZStack {
                            Image(systemName: "accessibility")
                                .font(.system(size: 115, weight: .light))
                                .foregroundColor(WizardDesign.Colors.warning)
                                .symbolRenderingMode(.hierarchical)
                                .modifier(AvailabilitySymbolBounce())

                            // Warning overlay positioned at right edge
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 40, weight: .medium))
                                        .foregroundColor(WizardDesign.Colors.warning)
                                        .offset(x: 15, y: -5) // Move further right and slightly up
                                }
                                Spacer()
                            }
                            .frame(width: 155, height: 115)
                        }

                        // Headline
                        Text("Accessibility")
                            .font(.system(size: 23, weight: .semibold, design: .default))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        // Subtitle
                        Text("Turn on KeyPath in Accessibility, then add and turn on kanata")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                        // Guard: recommend running from /Applications for stable permissions
                        if !isRunningFromApplicationsFolder {
                            Text("For the smoothest setup, move KeyPath to /Applications and relaunch.")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        // Action links below the subheader
                        HStack(spacing: WizardDesign.Spacing.itemGap) {
                            Button("Check Again") {
                                Task {
                                    await onRefresh()
                                }
                            }
                            .buttonStyle(.link)

                            Text("•")
                                .foregroundColor(.secondary)

                            Button("Open Settings Manually") {
                                openAccessibilitySettings()
                            }
                            .buttonStyle(.link)
                        }
                        .padding(.top, WizardDesign.Spacing.elementGap)

                        // Component details for error state
                        VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                            HStack(spacing: 12) {
                                Image(systemName: keyPathAccessibilityStatus == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(keyPathAccessibilityStatus == .completed ? .green : .red)
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
                                        PermissionGrantCoordinator.shared.setServiceBounceNeeded(reason: "Accessibility permission fix for KeyPath.app")
                                        openAccessibilityPermissionGrant()
                                    }
                                    .buttonStyle(WizardDesign.Component.SecondaryButton())
                                    .scaleEffect(0.8)
                                }
                            }
                            .help(keyPathAccessibilityIssues.asTooltipText())

                            HStack(spacing: 12) {
                                Image(systemName: kanataAccessibilityStatus == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(kanataAccessibilityStatus == .completed ? .green : .red)
                                HStack(spacing: 0) {
                                    Text("kanata")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                    Text(" - Keyboard monitoring engine")
                                        .font(.headline)
                                        .fontWeight(.regular)
                                }
                                Spacer()
                                if kanataAccessibilityStatus != .completed {
                                    Button("Add + Turn On") {
                                        AppLogger.shared.log("🔘 [WizardAccessibilityPage] Add + Turn On clicked for kanata")
                                        // Consolidated helper flow: open Settings, reveal, copy path, then run prompt/polling
                                        openAccessibilitySettings()
                                        copyKanataPathToClipboard()
                                        revealKanataInFinder()
                                        // Set service bounce flag before showing permission grant
                                        PermissionGrantCoordinator.shared.setServiceBounceNeeded(reason: "Accessibility permission fix for kanata binary")
                                        openAccessibilityPermissionGrant()
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
                        .padding(.top, WizardDesign.Spacing.sectionGap)
                    }
                    .padding(.vertical, WizardDesign.Spacing.pageVertical)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer()

            // Bottom buttons - HIG compliant button order
            if hasAccessibilityIssues {
                // When permissions needed: Cancel (left) | Continue Anyway (middle) | Grant Permission (right, primary)
                WizardButtonBar(
                    cancel: WizardButtonBar.CancelButton(title: "Back", action: navigateToPreviousPage),
                    secondary: WizardButtonBar.SecondaryButton(title: "Continue Anyway") {
                        AppLogger.shared.log("ℹ️ [Wizard] User continuing from Accessibility page despite issues")
                        navigateToNextPage()
                    },
                    primary: WizardButtonBar.PrimaryButton(title: "Grant Permission") {
                        // Set service bounce flag before showing permission grant
                        PermissionGrantCoordinator.shared.setServiceBounceNeeded(reason: "Accessibility permission grant via primary button")
                        openAccessibilityPermissionGrant()
                    }
                )
            } else {
                // When permissions granted: Cancel (left) | Continue (right, primary)
                WizardButtonBar(
                    cancel: WizardButtonBar.CancelButton(title: "Back", action: navigateToPreviousPage),
                    primary: WizardButtonBar.PrimaryButton(title: "Continue") {
                        AppLogger.shared.log("ℹ️ [Wizard] User continuing from Accessibility page")
                        navigateToNextPage()
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WizardDesign.Colors.wizardBackground)
        .overlay(alignment: .topTrailing) {
            Button {
                navigationCoordinator.navigateToPage(.summary)
                AppLogger.shared.log("✖️ [Accessibility] Close pressed — navigating to summary")
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .opacity(0.7)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.trailing, 8)
        }
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
                            AppLogger.shared.log("🔁 [WizardAccessibilityPage] Passive AX change detected - KeyPath: \(kpGranted), Kanata: \(kaGranted). Refreshing UI.")
                            lastKeyPathGranted = kpGranted
                            lastKanataGranted = kaGranted
                            await onRefresh()
                        }
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                }
            }
        }
        .onDisappear {
            permissionPollingTask?.cancel()
            permissionPollingTask = nil
        }
    }

    // MARK: - Helper Methods

    private func navigateToNextPage() {
        let allPages = WizardPage.allCases
        guard let currentIndex = allPages.firstIndex(of: navigationCoordinator.currentPage),
              currentIndex < allPages.count - 1
        else { return }
        let nextPage = allPages[currentIndex + 1]
        navigationCoordinator.navigateToPage(nextPage)
        AppLogger.shared.log("➡️ [Accessibility] Navigated to next page: \(nextPage.displayName)")
    }

    private func navigateToPreviousPage() {
        let allPages = WizardPage.allCases
        guard let currentIndex = allPages.firstIndex(of: navigationCoordinator.currentPage),
              currentIndex > 0
        else { return }
        let previousPage = allPages[currentIndex - 1]
        navigationCoordinator.navigateToPage(previousPage)
        AppLogger.shared.log("⬅️ [Accessibility] Navigated to previous page: \(previousPage.displayName)")
    }

    // MARK: - Computed Properties

    private var hasAccessibilityIssues: Bool {
        keyPathAccessibilityStatus != .completed || kanataAccessibilityStatus != .completed
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

        if FeatureFlags.useAutomaticPermissionPrompts {
            let alreadyGranted = PermissionRequestService.shared.requestAccessibilityPermission(ignoreCooldown: true)
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
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    attempts += 1
                    let snapshot = await PermissionOracle.shared.currentSnapshot()
                    let kpGranted = snapshot.keyPath.accessibility.isReady
                    let kaGranted = snapshot.kanata.accessibility.isReady

                    // Incremental refresh: update UI when either flips, not only when both are ready
                    if lastKeyPathGranted != kpGranted || lastKanataGranted != kaGranted {
                        AppLogger.shared.log("🔁 [WizardAccessibilityPage] Detected permission change (AX) - KeyPath: \(kpGranted), Kanata: \(kaGranted). Refreshing UI.")
                        lastKeyPathGranted = kpGranted
                        lastKanataGranted = kaGranted
                        await onRefresh()
                    }

                    if kpGranted && kaGranted {
                        // Both ready – stop polling
                        return
                    }
                    if Task.isCancelled { return }
                }
            }
            // Fallback: if not granted shortly, open Accessibility settings so the user can toggle
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
                let snapshot = await PermissionOracle.shared.currentSnapshot()
                let granted = snapshot.keyPath.accessibility.isReady && snapshot.kanata.accessibility.isReady
                if !granted {
                    AppLogger.shared.info("ℹ️ [WizardAccessibilityPage] Opening System Settings (fallback) for Accessibility")
                    openAccessibilitySettings()
                }
            }
        } else {
            let instructions = """
            KeyPath will now close so you can grant permissions:

            1. Add KeyPath and kanata to Accessibility (use the '+' button)
            2. Make sure both checkboxes are enabled
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
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func revealKanataInFinder() {
        let path = "\(Bundle.main.bundlePath)/Contents/Library/KeyPath/kanata"
        let dir = (path as NSString).deletingLastPathComponent
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        AppLogger.shared.log("📂 [WizardAccessibilityPage] Revealed kanata in Finder: \(path)")
        // If NSWorkspace.selectFile is preferred:
        _ = NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: dir)
    }

    private func copyKanataPathToClipboard() {
        let path = "\(Bundle.main.bundlePath)/Contents/Library/KeyPath/kanata"
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(path, forType: .string)
        AppLogger.shared.log("📋 [WizardAccessibilityPage] Copied kanata path to clipboard: \(path)")
    }
}

// MARK: - Preview

struct WizardAccessibilityPage_Previews: PreviewProvider {
    static var previews: some View {
        let manager = KanataManager()
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
            onRefresh: {},
            onNavigateToPage: nil,
            onDismiss: nil,
            kanataManager: manager
        )
        .frame(width: WizardDesign.Layout.pageWidth, height: WizardDesign.Layout.pageHeight)
        .environmentObject(viewModel)
    }
}
