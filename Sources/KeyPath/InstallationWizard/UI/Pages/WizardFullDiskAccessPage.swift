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
        VStack(spacing: 0) {
            // Header
            VStack(spacing: WizardDesign.Spacing.sectionGap) {
                WizardPageHeader(
                    icon: "folder.badge.gearshape",
                    title: hasFullDiskAccess ? "Full Disk Access Enabled" : "Enable Full Disk Access (optional)",
                    subtitle: "Enhance wizard capabilities for better diagnostics",
                    status: hasFullDiskAccess ? .success : .info
                )
                
                // Keep the padding space where status indicator was
                Spacer()
                    .frame(height: WizardDesign.Spacing.sectionGap)
            }
            .padding(.bottom, WizardDesign.Spacing.sectionGap)
            
            // Main content area (taller like in your requested image)
            VStack(alignment: .leading, spacing: WizardDesign.Spacing.itemGap) {
Text("Full Disk Access enhances KeyPath's ability to automatically detect and resolve issues during setup. This is completely optional – KeyPath works without it.")
                    .font(WizardDesign.Typography.body)
                    .foregroundColor(.primary)
                
                // Add significant height to match your requested image
                Spacer(minLength: 120)
            }
            .frame(maxWidth: .infinity)
            .padding(WizardDesign.Spacing.cardPadding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, WizardDesign.Spacing.pageVertical)
            
            // Fixed spacing between content area and button (smaller than content area height)
            Spacer()
                .frame(height: WizardDesign.Spacing.pageVertical * 2)

            // Action buttons (anchored to bottom)
            VStack(spacing: WizardDesign.Spacing.elementGap) {
                if hasFullDiskAccess {
                    // FDA already granted - centered continue button
                    HStack {
                        Spacer()
                        Button("Continue") {
                            AppLogger.shared.log("ℹ️ [Wizard] User continuing with FDA already granted")
                            navigationCoordinator.navigateToPage(.summary)
                        }
                        .buttonStyle(WizardDesign.Component.PrimaryButton())
                        Spacer()
                    }
                } else {
                    // FDA not granted - balanced skip/grant buttons
                    HStack(spacing: WizardDesign.Spacing.itemGap) {
                        Button("Skip This Step") {
                            AppLogger.shared.log("ℹ️ [Wizard] User skipped Full Disk Access step")
                            navigationCoordinator.navigateToPage(.summary)
                        }
                        .buttonStyle(WizardDesign.Component.SecondaryButton())

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
            .padding(.horizontal, WizardDesign.Spacing.pageVertical)
            .padding(.bottom, WizardDesign.Spacing.pageVertical)
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
                
                // Don't auto-navigate - let user navigate manually
                // User can use navigation buttons or close dialog
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

                        Text("A macOS security feature that allows KeyPath to read system permission databases for better diagnostics.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Benefits")
                            .font(.headline)

                        Text("• More accurate issue detection\n• Better automatic fixes\n• Clearer error messages")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Completely Optional")
                            .font(.headline)

                        Text("KeyPath works fine without this permission. You can skip this step and grant it later if needed.")
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
