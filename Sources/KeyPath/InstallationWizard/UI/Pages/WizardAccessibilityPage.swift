import SwiftUI

/// Accessibility permission page - dedicated page for Accessibility permissions
struct WizardAccessibilityPage: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let onRefresh: () async -> Void
    let onNavigateToPage: ((WizardPage) -> Void)?
    let onDismiss: (() -> Void)?
    let kanataManager: KanataManager

    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator
    
    // Polling state for permission checking
    @State private var isPolling = false
    @State private var pollTimer: Timer?

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
                                .symbolEffect(.bounce, options: .nonRepeating)
                            
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
                                .symbolEffect(.bounce, options: .nonRepeating)
                            
                            // Warning overlay positioned at right edge
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 40, weight: .medium))
                                        .foregroundColor(WizardDesign.Colors.warning)
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
                        Text("KeyPath needs Accessibility permission for keyboard monitoring & safety controls")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                        
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
                                    Button("Fix") {
                                        requestAccessibilityPermission()
                                        startPolling()
                                    }
                                    .buttonStyle(WizardDesign.Component.SecondaryButton())
                                    .scaleEffect(0.8)
                                }
                            }

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
                                    Button("Fix") {
                                        requestAccessibilityPermission()
                                        startPolling()
                                    }
                                    .buttonStyle(WizardDesign.Component.SecondaryButton())
                                    .scaleEffect(0.8)
                                }
                            }
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

            // Bottom buttons - primary action changes based on state
            HStack {
                Spacer()
                
                if hasAccessibilityIssues {
                    // When permissions needed, Grant Permission is primary
                    Button("Grant Permission") {
                        requestAccessibilityPermission()
                        startPolling()
                    }
                    .buttonStyle(WizardDesign.Component.PrimaryButton())
                    
                    Button("Continue Anyway") {
                        AppLogger.shared.log("ℹ️ [Wizard] User continuing from Accessibility page despite issues")
                        navigateToNextPage()
                    }
                    .buttonStyle(WizardDesign.Component.SecondaryButton())
                } else {
                    // When permissions granted, Continue is primary
                    Button("Continue") {
                        AppLogger.shared.log("ℹ️ [Wizard] User continuing from Accessibility page")
                        navigateToNextPage()
                    }
                    .buttonStyle(WizardDesign.Component.PrimaryButton())
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, WizardDesign.Spacing.sectionGap)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WizardDesign.Colors.wizardBackground)
        .onDisappear {
            // Clean up polling timer when leaving the page
            stopPolling()
        }
        .onChange(of: hasAccessibilityIssues) { oldValue, newValue in
            // Stop polling when permissions are granted (no more issues)
            if oldValue && !newValue && isPolling {
                AppLogger.shared.log("✅ [WizardAccessibilityPage] Permissions granted! Stopping polling")
                stopPolling()
            }
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

    // MARK: - Computed Properties

    private var hasAccessibilityIssues: Bool {
        keyPathAccessibilityStatus != .completed || kanataAccessibilityStatus != .completed
    }

    private var keyPathAccessibilityStatus: InstallationStatus {
        let hasKeyPathIssue = issues.contains { issue in
            if case let .permission(permissionType) = issue.identifier {
                return permissionType == .keyPathAccessibility
            }
            return false
        }
        return hasKeyPathIssue ? .notStarted : .completed
    }

    private var kanataAccessibilityStatus: InstallationStatus {
        let hasKanataIssue = issues.contains { issue in
            if case let .permission(permissionType) = issue.identifier {
                return permissionType == .kanataAccessibility
            }
            return false
        }
        return hasKanataIssue ? .notStarted : .completed
    }

    // MARK: - Actions

    private func requestAccessibilityPermission() {
        AppLogger.shared.log(
            "🔐 [WizardAccessibilityPage] Requesting Accessibility permission via system dialog")

        // Use the system API to request accessibility permission
        // This shows a dialog where the user can enter their password to add KeyPath
        PermissionService.requestAccessibilityPermission()
        
        // Note: After the user grants permission via the dialog, KeyPath will be added
        // to the Accessibility list but may still need to be toggled ON.
        // The user should click "Check Again" after granting permission.
        
        // We don't dismiss the wizard here - let the user check again after granting
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
    
    // MARK: - Polling Methods
    
    private func startPolling() {
        // Don't start if already polling
        guard !isPolling else { return }
        
        AppLogger.shared.log("🔄 [WizardAccessibilityPage] Starting permission polling every 5 seconds")
        isPolling = true
        
        // Start timer that checks every 5 seconds
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor in
                // Refresh the page state by calling onRefresh
                await onRefresh()
                
                // The UI will automatically update based on the refreshed state
                // If permissions are granted, hasAccessibilityIssues will become false
                // and the timer will be cleaned up on the next UI update cycle
            }
        }
    }
    
    private func stopPolling() {
        guard isPolling else { return }
        
        AppLogger.shared.log("⏹️ [WizardAccessibilityPage] Stopping permission polling")
        isPolling = false
        pollTimer?.invalidate()
        pollTimer = nil
    }
    
}

// MARK: - Preview

struct WizardAccessibilityPage_Previews: PreviewProvider {
    static var previews: some View {
        WizardAccessibilityPage(
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
            kanataManager: KanataManager()
        )
        .frame(width: WizardDesign.Layout.pageWidth, height: WizardDesign.Layout.pageHeight)
    }
}
