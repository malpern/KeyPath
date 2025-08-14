import SwiftUI

/// Wizard page for requesting Full Disk Access permission
/// This is optional but helps with better diagnostics and automatic problem resolution
struct WizardFullDiskAccessPage: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingDetails = false
    @State private var hasCheckedPermission = false
    @State private var hasFullDiskAccess = false
    @State private var isChecking = false
    @State private var showSuccessAnimation = false
    @State private var detectionTimer: Timer?

    // Modal states for System Settings flow
    @State private var showingSystemSettingsWait = false
    @State private var systemSettingsDetectionAttempts = 0
    private let maxDetectionAttempts = 4 // 8 seconds total (2 sec intervals)

    // Cache FDA status to avoid repeated checks
    @State private var lastFDACheckTime: Date?
    @State private var cachedFDAStatus: Bool = false
    private let cacheValidityDuration: TimeInterval = 10.0 // Cache for 10 seconds

    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator

    var body: some View {
        VStack(spacing: WizardDesign.Spacing.sectionGap) {
            // Header
            WizardPageHeader(
                icon: "folder.badge.gearshape",
                title: "Full Disk Access (Optional)",
                subtitle: "Enhance wizard capabilities for better diagnostics",
                status: hasFullDiskAccess ? .success : .info
            )

            // Main content
            VStack(spacing: WizardDesign.Spacing.sectionGap) {
                // Explanation card
                VStack(alignment: .leading, spacing: WizardDesign.Spacing.itemGap) {
                    Label("Why Full Disk Access?", systemImage: "questionmark.circle")
                        .font(WizardDesign.Typography.body)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 12) {
                        BenefitRow(
                            icon: "magnifyingglass",
                            title: "Better Diagnostics",
                            description: "Accurately detect which permissions are granted"
                        )

                        BenefitRow(
                            icon: "wrench.and.screwdriver",
                            title: "Automatic Resolution",
                            description: "Fix more issues automatically without manual intervention"
                        )

                        BenefitRow(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "Progress Tracking",
                            description: "Monitor installation progress more precisely"
                        )

                        BenefitRow(
                            icon: "shield.checkered",
                            title: "Enhanced Security Checks",
                            description: "Verify system integrity and detect conflicts"
                        )
                    }

                    Text(
                        "Note: This is completely optional. The wizard will work without it, but some automatic fixes may not be available."
                    )
                    .font(WizardDesign.Typography.caption)
                    .foregroundColor(WizardDesign.Colors.secondaryText)
                    .padding(.top, 8)
                }
                .wizardCard()

                // Current status with animation
                if hasCheckedPermission {
                    HStack(spacing: WizardDesign.Spacing.labelGap) {
                        if showSuccessAnimation {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(WizardDesign.Colors.success)
                                .font(WizardDesign.Typography.body)
                                .scaleEffect(showSuccessAnimation ? 1.2 : 1.0)
                                .animation(
                                    .spring(response: 0.3, dampingFraction: 0.6), value: showSuccessAnimation
                                )
                        } else {
                            Image(systemName: hasFullDiskAccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(
                                    hasFullDiskAccess ? WizardDesign.Colors.success : WizardDesign.Colors.warning
                                )
                                .font(WizardDesign.Typography.body)
                        }

                        Text(
                            hasFullDiskAccess
                                ? "Full Disk Access granted - enhanced features enabled"
                                : "Full Disk Access not granted - basic features only"
                        )
                        .font(WizardDesign.Typography.status)
                        .foregroundColor(WizardDesign.Colors.secondaryText)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                hasFullDiskAccess
                                    ? WizardDesign.Colors.success.opacity(0.1)
                                    : WizardDesign.Colors.warning.opacity(0.1))
                    )
                    .animation(.easeInOut(duration: 0.3), value: hasFullDiskAccess)
                }
            }
            .wizardPagePadding()

            Spacer()

            // Action buttons
            VStack(spacing: WizardDesign.Spacing.elementGap) {
                HStack(spacing: WizardDesign.Spacing.itemGap) {
                    // Skip button (always available)
                    Button("Skip This Step") {
                        // User chose to skip - that's fine
                        AppLogger.shared.log("ℹ️ [Wizard] User skipped Full Disk Access step")
                        // Navigate to next page
                        navigationCoordinator.navigateToPage(.summary)
                    }
                    .buttonStyle(WizardDesign.Component.SecondaryButton())

                    // Grant permission button
                    if !hasFullDiskAccess {
                        Button("Grant Full Disk Access") {
                            AppLogger.shared.log("🔒 [FDA Page] Grant Full Disk Access button clicked")

                            // Open System Settings for Full Disk Access
                            openFullDiskAccessSettings()

                            // Close Settings windows if they're open
                            for window in NSApplication.shared.windows {
                                let windowTitle = window.title
                                if windowTitle.contains("Settings") {
                                    AppLogger.shared.log("🔒 [FDA Page] Closing Settings window: '\(windowTitle)'")
                                    window.close()
                                }
                            }

                            // Dismiss the wizard using SwiftUI's dismiss action
                            AppLogger.shared.log("🔒 [FDA Page] Dismissing wizard")
                            dismiss()
                        }
                        .buttonStyle(WizardDesign.Component.PrimaryButton())
                    }
                }

                // Help link
                Button("Why is this safe?") {
                    showingDetails = true
                }
                .buttonStyle(.link)
                .font(WizardDesign.Typography.caption)
            }
            .padding(.bottom, WizardDesign.Spacing.pageVertical * 2) // More space from bottom
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WizardDesign.Colors.wizardBackground)
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
                    // Couldn't detect after 8 seconds, just close the modal
                    showingSystemSettingsWait = false
                    AppLogger.shared.log("⏱️ [Wizard] FDA detection timed out")
                },
                onCancel: {
                    // User cancelled the wait
                    showingSystemSettingsWait = false
                    systemSettingsDetectionAttempts = 0
                    AppLogger.shared.log("❌ [Wizard] User cancelled FDA detection wait")
                }
            )
        }
        .onChange(of: hasFullDiskAccess) { newValue in
            if newValue, !showSuccessAnimation {
                // Permission was just granted!
                showSuccessAnimation = true
                AppLogger.shared.log("✅ [Wizard] Full Disk Access granted - showing success animation")

                // Auto-navigate after a short delay to show success
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    // Navigate to next logical page (summary)
                    navigationCoordinator.navigateToPage(.summary)
                }
            }
        }
    }

    // MARK: - Helper Methods

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

    private func performFDACheck() -> Bool {
        // Use a completely non-invasive approach - just check if we're already in the FDA list
        // This avoids triggering automatic addition to System Preferences

        // We'll assume FDA is not granted unless the user explicitly grants it
        // This prevents the invasive file operations that cause auto-addition

        AppLogger.shared.log("🔐 [Wizard] FDA check: Using non-invasive detection")

        // For now, we'll only return true if the user has manually granted it
        // and we can detect it through less invasive means

        // Check if we can access a commonly available but protected file without writing
        // Only try a single, less sensitive location
        let testPath = "\(NSHomeDirectory())/Library/Preferences/com.apple.finder.plist"

        if FileManager.default.isReadableFile(atPath: testPath) {
            // Try a very light read operation
            if let data = try? Data(contentsOf: URL(fileURLWithPath: testPath), options: .mappedIfSafe) {
                if data.count > 0 {
                    AppLogger.shared.log("✅ [Wizard] FDA detected via non-invasive check")
                    return true
                }
            }
        }

        AppLogger.shared.log("❌ [Wizard] FDA not detected (non-invasive check)")
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
        var detectionCount = 0
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
            detectionCount += 1
            systemSettingsDetectionAttempts = detectionCount

            // Check for FDA
            if performFDACheck() {
                // Success! FDA detected
                timer.invalidate()
                hasFullDiskAccess = true
                cachedFDAStatus = true
                lastFDACheckTime = Date()

                if showingSystemSettingsWait {
                    // Trigger the onDetected callback
                    showingSystemSettingsWait = false
                    showSuccessAnimation = true
                }
            } else if detectionCount >= maxDetectionAttempts {
                // Timeout - show restart option
                timer.invalidate()

                if showingSystemSettingsWait {
                    showingSystemSettingsWait = false
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
                            """
                            Full Disk Access is a macOS security feature that controls which apps can access protected areas of your system. This includes system databases that track permissions.
                            """
                        )
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Why does KeyPath request it?")
                            .font(.headline)

                        Text(
                            """
                            When granted, KeyPath can:
                            • Check the exact permission status of the kanata binary
                            • Detect and resolve conflicts more accurately
                            • Provide better error messages
                            • Automatically fix more types of issues

                            Without it, KeyPath still works but relies on less precise detection methods.
                            """
                        )
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Is it safe?")
                            .font(.headline)

                        Text(
                            """
                            Yes! KeyPath only uses this permission to:
                            • Read permission databases (not modify them)
                            • Check system status
                            • Improve diagnostics

                            KeyPath is open source and you can verify exactly what it does with this permission.
                            """
                        )
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Can I skip this?")
                            .font(.headline)

                        Text(
                            """
                            Absolutely! Full Disk Access is completely optional. The wizard will work without it, using alternative detection methods. You can always grant it later if you change your mind.
                            """
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
