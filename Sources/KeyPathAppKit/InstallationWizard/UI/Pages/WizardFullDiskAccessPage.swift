import KeyPathCore
import KeyPathWizardCore
import os
import SwiftUI

// Thread-safe counter for detection attempts
final class DetectionCounter: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)

    func increment() -> Int {
        lock.withLock { state in
            state += 1
            return state
        }
    }
}

/// Wizard page for requesting Full Disk Access permission
/// This is optional but helps with better diagnostics and automatic problem resolution
struct WizardFullDiskAccessPage: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    @Environment(\.dismiss) private var dismiss
    @State private var showingDetails = false
    @State private var hasCheckedPermission = false
    @State private var hasFullDiskAccess = false
    @State private var isChecking = false
    @State private var showSuccessAnimation = false
    @State private var detectionTimer: Timer?

    // Modal states for System Settings flow
    @State private var showingSystemSettingsWait = false
    @State private var showingRestartRequired = false
    @State private var systemSettingsDetectionAttempts = 0
    private let maxDetectionAttempts = 4 // 8 seconds total (2 sec intervals)

    // Cache FDA status to avoid repeated checks
    @State private var lastFDACheckTime: Date?
    @State private var cachedFDAStatus: Bool = false
    private let cacheValidityDuration: TimeInterval = 10.0 // Cache for 10 seconds

    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator

    var body: some View {
        VStack(spacing: 0) {
            // Large centered hero section - Icon, Headline, and Supporting Copy
            VStack(spacing: WizardDesign.Spacing.sectionGap) {
                // Basic folder icon with appropriate overlay
                ZStack {
                    Image(systemName: "folder")
                        .font(.system(size: 115, weight: .light))
                        .foregroundColor(
                            hasFullDiskAccess ? WizardDesign.Colors.success : WizardDesign.Colors.info
                        )
                        .symbolRenderingMode(.hierarchical)
                        .modifier(AvailabilitySymbolBounce())

                    // Overlay hanging off right side based on FDA status
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: hasFullDiskAccess ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 40, weight: .medium))
                                .foregroundColor(
                                    hasFullDiskAccess
                                        ? WizardDesign.Colors.success : WizardDesign.Colors.secondaryText
                                )
                                .background(WizardDesign.Colors.wizardBackground)
                                .clipShape(Circle())
                                .offset(x: 25, y: -5) // Hang further off the right side
                                .contentTransition(.symbolEffect(.replace))
                        }
                        Spacer()
                    }
                    .frame(width: 115, height: 115)
                }

                // Larger headline (19pt + 20% = 23pt)
                Text(hasFullDiskAccess ? "Full Disk Access" : "Enable Full Disk Access (optional)")
                    .font(.system(size: 23, weight: .semibold, design: .default))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                // Supporting copy - more descriptive since no content card
                Text(
                    hasFullDiskAccess
                        ? "Enhanced diagnostics and automatic issue resolution"
                        : "Optional: Enhanced diagnostics and automatic issue resolution"
                )
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

                // Help link below subheader (only when FDA not granted)
                if !hasFullDiskAccess {
                    Button("Why is this safe?") {
                        showingDetails = true
                    }
                    .buttonStyle(.link)
                    .font(WizardDesign.Typography.caption)
                    .padding(.top, WizardDesign.Spacing.elementGap)
                }
            }
            .heroSectionContainer()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Spacer()

            WizardButtonBar(
                secondary: hasFullDiskAccess
                    ? nil
                    : WizardButtonBar.SecondaryButton(
                        title: "Skip for Now",
                        action: skipFullDiskAccessPrompt
                    ),
                primary: WizardButtonBar.PrimaryButton(
                    title: hasFullDiskAccess ? nextStepButtonTitle : "Open System Settings",
                    action: handlePrimaryButton,
                    isEnabled: hasFullDiskAccess || !isChecking,
                    isLoading: !hasFullDiskAccess && isChecking
                )
            )
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .background(WizardDesign.Colors.wizardBackground)
        .wizardDetailPage()
        .onAppear {
            // Check status when page appears
            checkFullDiskAccess()
            startAutoDetection()
        }
        .onDisappear {
            stopAutoDetection()
        }
        .sheet(isPresented: $showingDetails) {
            FullDiskAccessDetailsSheet()
        }
        .sheet(isPresented: $showingSystemSettingsWait) {
            SystemSettingsWaitingView(
                detectionAttempts: $systemSettingsDetectionAttempts,
                maxAttempts: maxDetectionAttempts,
                onDetected: {
                    // FDA was detected!
                    showingSystemSettingsWait = false
                    hasFullDiskAccess = true
                    showSuccessAnimation = true
                    AppLogger.shared.log("✅ [Wizard] FDA detected during System Settings wait")
                },
                onTimeout: {
                    // Couldn't detect after 8 seconds - FDA requires app restart
                    showingSystemSettingsWait = false
                    AppLogger.shared.log("⏱️ [Wizard] FDA detection timed out - showing restart prompt")
                    // Show restart required modal after a brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showingRestartRequired = true
                    }
                },
                onCancel: {
                    // User cancelled the wait
                    showingSystemSettingsWait = false
                    systemSettingsDetectionAttempts = 0
                    AppLogger.shared.log("❌ [Wizard] User cancelled FDA detection wait")
                }
            )
        }
        .onChange(of: hasFullDiskAccess) { _, newValue in
            if newValue, !showSuccessAnimation {
                // Permission was just granted!
                showSuccessAnimation = true
                AppLogger.shared.log("✅ [Wizard] Full Disk Access granted - showing success animation")

                // Don't auto-navigate - let user navigate manually
                // User can use navigation buttons or close dialog
            }
        }
        .onChange(of: showingSystemSettingsWait) { _, newValue in
            if !newValue {
                isChecking = false
            }
        }
        .sheet(isPresented: $showingRestartRequired) {
            RestartRequiredView(
                onRestart: {
                    AppLogger.shared.log("🔄 [Wizard] User requested restart for FDA")
                    AppRestarter.restartForWizard(at: "fullDiskAccess")
                },
                onCancel: {
                    showingRestartRequired = false
                    AppLogger.shared.log("❌ [Wizard] User cancelled FDA restart")
                }
            )
        }
    }

    // MARK: - Helper Methods

    private func handlePrimaryButton() {
        if hasFullDiskAccess {
            navigateToNextStep()
        } else {
            openSystemSettingsCTA()
        }
    }

    private func skipFullDiskAccessPrompt() {
        navigateToNextStep()
    }

    private func navigateToNextStep() {
        if issues.isEmpty {
            navigationCoordinator.navigateToPage(.summary)
            return
        }

        Task {
            if let nextPage = await navigationCoordinator.getNextPage(for: systemState, issues: issues),
               nextPage != navigationCoordinator.currentPage {
                navigationCoordinator.navigateToPage(nextPage)
            } else {
                navigationCoordinator.navigateToPage(.summary)
            }
        }
    }

    private func openSystemSettingsCTA() {
        guard !isChecking else { return }
        isChecking = true
        openFullDiskAccessSettingsWithDetection()
    }

    private func checkFullDiskAccess() {
        // Check cache first
        if let lastCheckTime = lastFDACheckTime,
           Date().timeIntervalSince(lastCheckTime) < cacheValidityDuration,
           cachedFDAStatus {
            // Use cached positive result (don't cache negative to allow quick detection)
            hasFullDiskAccess = cachedFDAStatus
            hasCheckedPermission = true
            AppLogger.shared.log("🔐 [Wizard] Using cached FDA status: \(cachedFDAStatus)")
            return
        }

        hasCheckedPermission = true

        // Check immediately without delay or loading state
        let previousValue = hasFullDiskAccess
        let hasAccess = performFDACheck()

        hasFullDiskAccess = hasAccess

        // Update cache
        if hasAccess {
            cachedFDAStatus = true
            lastFDACheckTime = Date()
        } else {
            // Don't cache negative results to allow quick re-detection
            cachedFDAStatus = false
            lastFDACheckTime = nil
        }

        AppLogger.shared.log(
            "🔐 [Wizard] Full Disk Access check: \(hasFullDiskAccess) (was: \(previousValue))")

        // Update the static flag so other parts of the app know
        PermissionService.lastTCCAuthorizationDenied = !hasFullDiskAccess
    }

    private var nextStepButtonTitle: String {
        issues.isEmpty ? "Return to Summary" : "Next Issue"
    }

    private func performFDACheck() -> Bool {
        // Check if we can read the system TCC database (requires Full Disk Access)
        // This is the most accurate test for Full Disk Access permission
        //
        // NOTE: The previous check tested ~/Library/Preferences/com.apple.finder.plist
        // which doesn't require FDA (it's the user's own file), causing false positives

        let systemTCCPath = "/Library/Application Support/com.apple.TCC/TCC.db"

        AppLogger.shared.log("🔐 [Wizard] FDA check: Testing system TCC database access")

        // Try to read the system TCC database
        if FileManager.default.isReadableFile(atPath: systemTCCPath) {
            // Try a very light read operation
            if let data = try? Data(
                contentsOf: URL(fileURLWithPath: systemTCCPath), options: .mappedIfSafe
            ) {
                if data.count > 0 {
                    AppLogger.shared.log(
                        "✅ [Wizard] FDA granted - can read system TCC database (\(data.count) bytes)")
                    return true
                }
            }
        }

        AppLogger.shared.log("❌ [Wizard] FDA not granted - cannot read system TCC database")
        return false
    }

    private func startAutoDetection() {
        // DISABLED: This timer was potentially causing invasive file system checks
        // that could trigger automatic addition to System Preferences
        // Only check once on page load, not continuously

        AppLogger.shared.log(
            "🔐 [WizardFullDiskAccessPage] Auto-detection timer DISABLED to prevent invasive checks")
    }

    private func stopAutoDetection() {
        detectionTimer?.invalidate()
        detectionTimer = nil
    }

    private func openFullDiskAccessSettings() {
        if let url = URL(string: WizardSystemPaths.fullDiskAccessSettings) {
            NSWorkspace.shared.open(url)
            AppLogger.shared.log("🔗 [Wizard] Opened Full Disk Access settings")
        }
    }

    private func openFullDiskAccessSettingsWithDetection() {
        // Open System Settings
        openFullDiskAccessSettings()

        // Show modal and start detection
        showingSystemSettingsWait = true
        systemSettingsDetectionAttempts = 0

        // Start enhanced detection timer
        // Use a thread-safe counter for detection attempts
        let detectionCounter = DetectionCounter()

        detectionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            // Use synchronous MainActor.assumeIsolated to avoid data race
            MainActor.assumeIsolated {
                let currentCount = detectionCounter.increment()
                systemSettingsDetectionAttempts = currentCount

                let shouldStop: Bool
                if performFDACheck() {
                    shouldStop = true
                    cachedFDAStatus = true
                    lastFDACheckTime = Date()
                    hasFullDiskAccess = true
                    if showingSystemSettingsWait {
                        showingSystemSettingsWait = false
                        showSuccessAnimation = true
                    }
                } else if currentCount >= maxDetectionAttempts {
                    shouldStop = true
                    if showingSystemSettingsWait {
                        showingSystemSettingsWait = false
                    }
                } else {
                    shouldStop = false
                }

                if shouldStop {
                    detectionTimer?.invalidate()
                    detectionTimer = nil
                }
            }
        }
    }
}

// Remove this old saveWizardStateAndRestart function as we don't need it anymore

// MARK: - Benefit Row Component

private struct BenefitRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Details Sheet

private struct FullDiskAccessDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("About Full Disk Access")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(WizardDesign.Component.SecondaryButton())
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What is Full Disk Access?")
                            .font(.headline)

                        Text(
                            "A macOS security feature that allows KeyPath to read system permission databases for better diagnostics."
                        )
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Benefits")
                            .font(.headline)

                        Text(
                            "• More accurate issue detection\n• Better automatic fixes\n• Clearer error messages"
                        )
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Completely Optional")
                            .font(.headline)

                        Text(
                            "KeyPath works fine without this permission. You can skip this step and grant it later if needed."
                        )
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.08))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .frame(width: 500, height: 600)
    }
}
