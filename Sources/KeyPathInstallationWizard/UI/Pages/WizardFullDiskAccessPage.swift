import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Wizard page for requesting Full Disk Access permission
/// This is optional but helps with better diagnostics and automatic problem resolution
public struct WizardFullDiskAccessPage: View {
    public let systemState: WizardSystemState
    public let issues: [WizardIssue]
    @Environment(\.dismiss) private var dismiss
    @State private var showingDetails = false
    @State private var hasCheckedPermission = false
    @State private var hasFullDiskAccess = false
    @State private var isChecking = false
    @State private var showSuccessAnimation = false

    // Cache FDA status to avoid repeated checks
    @State private var lastFDACheckTime: Date?
    @State private var cachedFDAStatus: Bool = false
    private let cacheValidityDuration: TimeInterval = 10.0 // Cache for 10 seconds

    @Environment(WizardStateMachine.self) var stateMachine

    public init(systemState: WizardSystemState, issues: [WizardIssue]) {
        self.systemState = systemState
        self.issues = issues
    }

    public var body: some View {
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
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                // Concise value proposition
                if hasFullDiskAccess {
                    Text("KeyPath can now verify all permissions")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    VStack(spacing: 12) {
                        Text("Helps KeyPath verify Kanata's permissions and diagnose issues.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Text("Without this, some permission checks will show as \"unverified.\"")
                            .font(.subheadline)
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
                        .font(.body)
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
            checkFullDiskAccess()
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
               nextPage != .fullDiskAccess
            { // Don't loop back to FDA
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
        openFullDiskAccessSettings()
        // Detection happens automatically via didBecomeActiveNotification when user returns
        isChecking = false
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
            "🔐 [Wizard] Full Disk Access check: \(hasFullDiskAccess) (was: \(previousValue))"
        )

        // Update shared cache so other parts of the app reflect FDA immediately.
        WizardDependencies.fullDiskAccessChecker!.updateCachedValue(hasFullDiskAccess)
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
        if Foundation.FileManager().isReadableFile(atPath: systemTCCPath) {
            // Try a very light read operation
            if let data = try? Data(
                contentsOf: URL(fileURLWithPath: systemTCCPath), options: .mappedIfSafe
            ) {
                if data.count > 0 {
                    AppLogger.shared.log(
                        "✅ [Wizard] FDA granted - can read system TCC database (\(data.count) bytes)"
                    )
                    return true
                }
            }
        }

        AppLogger.shared.log("❌ [Wizard] FDA not granted - cannot read system TCC database")
        return false
    }

    private func openFullDiskAccessSettings() {
        if let url = URL(string: WizardSystemPaths.fullDiskAccessSettings) {
            if NSWorkspace.shared.open(url) {
                WizardWindowManager.shared.markSystemSettingsOpened()
            }
            AppLogger.shared.log("🔗 [Wizard] Opened Full Disk Access settings")
        }
    }
}

// MARK: - Benefit Row Component

private struct BenefitRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)

                Text(description)
                    .font(.footnote)
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
                .clipShape(.rect(cornerRadius: 8))

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
                .clipShape(.rect(cornerRadius: 8))

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
                .clipShape(.rect(cornerRadius: 8))

                Spacer()
            }
        }
        .padding()
        .frame(width: 420, height: 400)
    }
}
