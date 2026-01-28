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

    @EnvironmentObject var stateMachine: WizardStateMachine

    var body: some View {
        VStack(spacing: 0) {
            // Large centered hero section - Icon, Headline, and Supporting Copy
            VStack(spacing: WizardDesign.Spacing.sectionGap) {
                // Basic folder icon with appropriate overlay
                ZStack {
                    Image(systemName: hasFullDiskAccess ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                        .font(.system(size: 80, weight: .light))
                        .foregroundColor(
                            hasFullDiskAccess ? WizardDesign.Colors.success : WizardDesign.Colors.info
                        )
                        .symbolRenderingMode(.hierarchical)
                        .modifier(AvailabilitySymbolBounce())
                }

                // Larger headline
                Text(hasFullDiskAccess ? "Enhanced Diagnostics Enabled" : "Enhanced Diagnostics")
                    .font(.system(size: 23, weight: .semibold, design: .default))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                // Concise value proposition
                if hasFullDiskAccess {
                    Text("KeyPath can now verify all permissions")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    VStack(spacing: 12) {
                        Text("Helps KeyPath verify Kanata's permissions and diagnose issues.")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Text("Without this, some permission checks will show as \"unverified.\"")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.secondary.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: 420)

                    // Help link
                    Button("Learn more") {
                        showingDetails = true
                    }
                    .buttonStyle(.link)
                    .font(WizardDesign.Typography.caption)
                    .padding(.top, 4)
                }

                // Centered action buttons
                VStack(spacing: 12) {
                    Button(hasFullDiskAccess ? nextStepButtonTitle : "Enable") {
                        handlePrimaryButton()
                    }
                    .buttonStyle(WizardDesign.Component.PrimaryButton())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasFullDiskAccess && isChecking)

                    if !hasFullDiskAccess {
                        Button("Skip") {
                            skipFullDiskAccessPrompt()
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 14))
                    }
                }
                .padding(.top, WizardDesign.Spacing.sectionGap)
            }
            .heroSectionContainer()
            .frame(maxWidth: .infinity)
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Re-check FDA when app becomes active (user may have granted it in System Settings)
            if !hasFullDiskAccess {
                AppLogger.shared.log("🔐 [Wizard] App became active - re-checking FDA status")
                checkFullDiskAccess()
            }
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
                // Bounce dock icon to get user's attention back to KeyPath
                WizardWindowManager.shared.bounceDocIcon()
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
        // Mark FDA page as shown so navigation engine moves to next step
        stateMachine.navigationEngine.markFDAPageShown()

        Task {
            // Get the next page based on current state
            if let nextPage = await stateMachine.getNextPage(for: systemState, issues: issues),
               nextPage != stateMachine.currentPage,
               nextPage != .fullDiskAccess // Don't loop back to FDA
            {
                stateMachine.navigateToPage(nextPage)
            } else {
                // If no specific next page, go to summary
                stateMachine.navigateToPage(.summary)
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
           cachedFDAStatus
        {
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

        // Update shared cache so other parts of the app reflect FDA immediately.
        FullDiskAccessChecker.shared.updateCachedValue(hasFullDiskAccess)
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
            if NSWorkspace.shared.open(url) {
                WizardWindowManager.shared.markSystemSettingsOpened()
            }
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
                    FullDiskAccessChecker.shared.updateCachedValue(true)
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
                Text("About Enhanced Diagnostics")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(WizardDesign.Component.SecondaryButton())
            }

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("What it does", systemImage: "info.circle")
                        .font(.headline)

                    Text("Lets KeyPath read macOS permission databases to verify Kanata has the access it needs.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 8) {
                    Label("With it enabled", systemImage: "checkmark.circle")
                        .font(.headline)
                        .foregroundColor(.green)

                    Text("• Verify all permissions accurately\n• Better error messages when things break\n• Proactive issue detection")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08))
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Without it", systemImage: "questionmark.circle")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("• KeyPath still works normally\n• Some permissions show as \"unverified\"\n• May need to check System Settings manually if issues occur")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                Spacer()
            }
        }
        .padding()
        .frame(width: 420, height: 400)
    }
}
