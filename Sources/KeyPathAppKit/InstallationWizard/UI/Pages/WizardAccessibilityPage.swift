import AppKit
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
    @State private var showSuccessBurst = false

    @EnvironmentObject var stateMachine: WizardStateMachine

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

    private func kanataSubtitle(for status: InstallationStatus) -> String {
        switch status {
        case .completed:
            " - Keyboard monitoring engine"
        case .warning, .unverified:
            " - Permission not verified"
        case .failed, .notStarted, .inProgress:
            " - Keyboard monitoring engine"
        }
    }

    /// State interpreter for consistent status computation
    private let stateInterpreter = WizardStateInterpreter()

    var body: some View {
        ZStack {
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
                                            reason: "Accessibility permission fix for KeyPath.app"
                                        )
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

            // Celebration overlay
            if showSuccessBurst {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .transition(.opacity)

                CheckmarkBurstView(isShowing: $showSuccessBurst)
            }
        }
        .onAppear {
            // Start passive polling to reflect manual changes in System Settings
            if permissionPollingTask == nil {
                permissionPollingTask = Task { @MainActor [onRefresh] in
                    var lastKeyPathGranted: Bool?
                    var lastKanataGranted: Bool?
                    var hasEverCelebrated = false
                    while !Task.isCancelled {
                        let snapshot = await PermissionOracle.shared.currentSnapshot()
                        let kpGranted = snapshot.keyPath.accessibility.isReady
                        let kaGranted = snapshot.kanata.accessibility.isReady
                        let bothGranted = kpGranted && kaGranted
                        if lastKeyPathGranted != kpGranted || lastKanataGranted != kaGranted {
                            AppLogger.shared.log(
                                "🔁 [WizardAccessibilityPage] Passive AX change detected - KeyPath: \(kpGranted), Kanata: \(kaGranted). Refreshing UI."
                            )
                            lastKeyPathGranted = kpGranted
                            lastKanataGranted = kaGranted

                            // Celebrate when both permissions are granted for the first time
                            if bothGranted, !hasEverCelebrated {
                                hasEverCelebrated = true
                                // Bounce dock icon to get user's attention back to KeyPath
                                WizardWindowManager.shared.bounceDocIcon()
                                withAnimation(.spring(response: 0.3)) {
                                    showSuccessBurst = true
                                }
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                showSuccessBurst = false
                            }
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

    /// Issue filtering for tooltips
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
            ignoreCooldown: true
        )
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
                    "ℹ️ [WizardAccessibilityPage] Opening System Settings (fallback) for Accessibility"
                )
                openAccessibilitySettings()
            }
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
            let snapshot = await PermissionOracle.shared.currentSnapshot()
            let inputMonitoringGranted = snapshot.keyPath.inputMonitoring.isReady
                && snapshot.kanata.inputMonitoring.isReady

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

    private func revealKanataInFinder() {
        let path = WizardSystemPaths.kanataSystemInstallPath
        let dir = (path as NSString).deletingLastPathComponent
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        WizardWindowManager.shared.markFinderWindowOpened(forPath: path)
        AppLogger.shared.log("📂 [WizardAccessibilityPage] Revealed kanata in Finder: \(path)")
        // If NSWorkspace.selectFile is preferred:
        _ = NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: dir)

        // Position windows side-by-side after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Self.positionSettingsAndFinderSideBySide()
        }
    }

    private func copyKanataPathToClipboard() {
        let path = WizardSystemPaths.kanataSystemInstallPath
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(path, forType: .string)
        AppLogger.shared.log("📋 [WizardAccessibilityPage] Copied kanata path to clipboard: \(path)")
    }

    /// Position System Settings and Finder windows side-by-side for easy drag-and-drop
    private static func positionSettingsAndFinderSideBySide() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        // Calculate side-by-side positions (Settings on left, Finder on right)
        let windowWidth = screenFrame.width / 2
        let windowHeight = screenFrame.height * 0.8
        let yPosition = screenFrame.minY + (screenFrame.height - windowHeight) / 2

        let settingsFrame = NSRect(
            x: screenFrame.minX,
            y: yPosition,
            width: windowWidth,
            height: windowHeight
        )
        let finderFrame = NSRect(
            x: screenFrame.minX + windowWidth,
            y: yPosition,
            width: windowWidth,
            height: windowHeight
        )

        // Find and position System Settings window
        if let settingsApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.systempreferences"
        ).first {
            let axApp = AXUIElementCreateApplication(settingsApp.processIdentifier)
            var windowsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
               let windows = windowsRef as? [AXUIElement], !windows.isEmpty
            {
                let axWindow = windows[0]
                var position = CGPoint(x: settingsFrame.minX, y: screen.frame.maxY - settingsFrame.maxY)
                var size = CGSize(width: settingsFrame.width, height: settingsFrame.height)
                let positionValue = AXValueCreate(.cgPoint, &position)!
                let sizeValue = AXValueCreate(.cgSize, &size)!
                AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, positionValue)
                AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
            }
        }

        // Find and position Finder window
        if let finderApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.finder"
        ).first {
            let axApp = AXUIElementCreateApplication(finderApp.processIdentifier)
            var windowsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
               let windows = windowsRef as? [AXUIElement], !windows.isEmpty
            {
                let axWindow = windows[0]
                var position = CGPoint(x: finderFrame.minX, y: screen.frame.maxY - finderFrame.maxY)
                var size = CGSize(width: finderFrame.width, height: finderFrame.height)
                let positionValue = AXValueCreate(.cgPoint, &position)!
                let sizeValue = AXValueCreate(.cgSize, &size)!
                AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, positionValue)
                AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
            }
        }

        AppLogger.shared.log("📐 [WizardAccessibilityPage] Positioned Settings and Finder side-by-side")
    }
}

// MARK: - Preview

struct WizardAccessibilityPage_Previews: PreviewProvider {
    static var previews: some View {
        let manager = RuntimeCoordinator()
        let viewModel = KanataViewModel(manager: manager)
        let stateMachine = WizardStateMachine()

        return Group {
            WizardAccessibilityPage(
                systemState: .missingPermissions(missing: [.keyPathAccessibility, .kanataAccessibility]),
                issues: [
                    PreviewFixtures.permissionIssue(
                        .keyPathAccessibility,
                        title: "KeyPath Accessibility Required",
                        description: "KeyPath needs Accessibility permission to monitor keyboard events."
                    ),
                    PreviewFixtures.permissionIssue(
                        .kanataAccessibility,
                        title: "kanata Accessibility Required",
                        description: "kanata also needs Accessibility permission for remapping."
                    )
                ],
                allIssues: [],
                onRefresh: {},
                onNavigateToPage: nil,
                onDismiss: nil,
                kanataManager: manager
            )
            .previewDisplayName("Accessibility - Missing")

            WizardAccessibilityPage(
                systemState: .missingPermissions(missing: [.kanataAccessibility]),
                issues: [
                    PreviewFixtures.permissionIssue(
                        .kanataAccessibility,
                        title: "kanata Accessibility Required",
                        description: "Enable kanata in Accessibility."
                    )
                ],
                allIssues: [],
                onRefresh: {},
                onNavigateToPage: nil,
                onDismiss: nil,
                kanataManager: manager
            )
            .previewDisplayName("Accessibility - Partial")

            WizardAccessibilityPage(
                systemState: .ready,
                issues: PreviewFixtures.noIssues,
                allIssues: [],
                onRefresh: {},
                onNavigateToPage: nil,
                onDismiss: nil,
                kanataManager: manager
            )
            .previewDisplayName("Accessibility - Ready")
        }
        .frame(width: WizardDesign.Layout.pageWidth)
        .fixedSize(horizontal: false, vertical: true)
        .environmentObject(viewModel)
        .environmentObject(stateMachine)
    }
}
