import SwiftUI

/// Accessibility permission page - dedicated page for Accessibility permissions
struct WizardAccessibilityPage: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let onRefresh: () async -> Void
    let onNavigateToPage: ((WizardPage) -> Void)?
    let onDismiss: (() -> Void)?
    let kanataManager: KanataManager

    var body: some View {
        VStack(spacing: WizardDesign.Spacing.sectionGap) {
            // Header
            WizardPageHeader(
                icon: !hasAccessibilityIssues ? "checkmark.circle.fill" : "accessibility",
                title: !hasAccessibilityIssues ? "Accessibility Granted" : "Accessibility Required",
                subtitle: !hasAccessibilityIssues
                    ? "KeyPath has the necessary Accessibility permission."
                    : "KeyPath needs Accessibility permission to monitor keyboard events and provide emergency stop functionality.",
                status: !hasAccessibilityIssues ? .success : .warning
            )

            // Main content area (taller like in template design)
            VStack(alignment: .leading, spacing: WizardDesign.Spacing.itemGap) {
                if hasAccessibilityIssues {
                    VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                        Text("KeyPath needs Accessibility permission to provide emergency stop functionality and monitor keyboard events safely.")
                            .font(WizardDesign.Typography.body)
                            .foregroundColor(.primary)

                        Text("Required Permissions:")
                            .font(WizardDesign.Typography.subsectionTitle)
                            .foregroundColor(.primary)
                            .padding(.top, WizardDesign.Spacing.itemGap)

                        VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                            HStack(spacing: 12) {
                                Image(systemName: keyPathAccessibilityStatus == .completed ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(keyPathAccessibilityStatus == .completed ? .green : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("KeyPath.app")
                                        .font(.headline)
                                    Text("Emergency stop detection and system monitoring")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            
                            HStack(spacing: 12) {
                                Image(systemName: kanataAccessibilityStatus == .completed ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(kanataAccessibilityStatus == .completed ? .green : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("kanata")
                                        .font(.headline)
                                    Text("Keyboard monitoring and remapping engine")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                        }

                        Text("The emergency stop sequence (Cmd+Opt+Ctrl+Shift+K) requires Accessibility permission to work reliably.")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.top, WizardDesign.Spacing.itemGap)
                    }
                } else {
                    Text("Accessibility permissions have been granted for both KeyPath and kanata. Emergency stop functionality and keyboard monitoring are enabled.")
                        .font(WizardDesign.Typography.body)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                
                Spacer(minLength: 120)
            }
            .frame(maxWidth: .infinity)
            .padding(WizardDesign.Spacing.cardPadding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, WizardDesign.Spacing.pageVertical)
            
            Spacer()
            
            // Centered action buttons at bottom following design system
            HStack(spacing: WizardDesign.Spacing.itemGap) {
                Button("Check Again") {
                    Task {
                        await onRefresh()
                    }
                }
                .buttonStyle(WizardDesign.Component.SecondaryButton())

                if hasAccessibilityIssues {
                    Button("Grant Permission") {
                        openAccessibilitySettings()
                    }
                    .buttonStyle(WizardDesign.Component.PrimaryButton())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, WizardDesign.Spacing.sectionGap)
        }
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

    private func openAccessibilitySettings() {
        AppLogger.shared.log(
            "🔐 [WizardAccessibilityPage] Opening Accessibility settings and dismissing wizard")

        // Open System Settings > Privacy & Security > Accessibility
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }

        // Simulate pressing Escape to close the wizard after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let escapeKeyEvent = NSEvent.keyEvent(
                with: .keyDown,
                location: NSPoint.zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "\u{1B}", // Escape character
                charactersIgnoringModifiers: "\u{1B}",
                isARepeat: false,
                keyCode: 53 // Escape key code
            )

            if let escapeEvent = escapeKeyEvent {
                NSApp.postEvent(escapeEvent, atStart: false)
            }

            // Fallback: call dismiss callback if available
            onDismiss?()
        }
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
