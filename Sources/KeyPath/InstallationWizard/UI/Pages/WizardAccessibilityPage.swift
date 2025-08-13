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
                subtitle: !hasAccessibilityIssues ? "KeyPath has the necessary Accessibility permission." : "KeyPath needs Accessibility permission to monitor keyboard events and provide emergency stop functionality.",
                status: !hasAccessibilityIssues ? .success : .warning
            )

            VStack(spacing: WizardDesign.Spacing.elementGap) {
                // KeyPath Accessibility Permission
                PermissionCard(
                    appName: "KeyPath",
                    appPath: "/Applications/KeyPath.app",
                    status: keyPathAccessibilityStatus,
                    permissionType: "Accessibility",
                    kanataManager: kanataManager
                )

                // Kanata Accessibility Permission
                PermissionCard(
                    appName: "kanata",
                    appPath: "/usr/local/bin/kanata",
                    status: kanataAccessibilityStatus,
                    permissionType: "Accessibility",
                    kanataManager: kanataManager
                )

                if hasAccessibilityIssues {
                    VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                        Text("Why This Permission Is Needed")
                            .font(.headline)
                            .foregroundColor(.primary)

                        VStack(alignment: .leading, spacing: 4) {
                            Label("Emergency stop sequence detection (Cmd+Opt+Ctrl+Shift+K)", systemImage: "exclamationmark.triangle")
                            Label("Monitor system keyboard events", systemImage: "keyboard")
                            Label("Provide safe fallback when Kanata encounters issues", systemImage: "shield")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)

                        Text("Grant this permission in System Settings > Privacy & Security > Accessibility")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.top, 4)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(WizardDesign.Layout.cornerRadius)
                }

                Spacer()

                // Action Buttons
                HStack(spacing: 12) {
                    // Manual Refresh Button (no auto-refresh to prevent invasive checks)
                    Button("Check Again") {
                        Task {
                            await onRefresh()
                        }
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    // Open Accessibility Settings Button
                    Button("Grant Permission") {
                        openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
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
        AppLogger.shared.log("🔐 [WizardAccessibilityPage] Opening Accessibility settings and dismissing wizard")

        // Open System Settings > Privacy & Security > Accessibility
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
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
                ),
            ],
            onRefresh: {},
            onNavigateToPage: nil,
            onDismiss: nil,
            kanataManager: KanataManager()
        )
        .frame(width: WizardDesign.Layout.pageWidth, height: WizardDesign.Layout.pageHeight)
    }
}
