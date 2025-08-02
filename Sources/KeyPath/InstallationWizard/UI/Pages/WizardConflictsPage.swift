import SwiftUI

struct WizardConflictsPage: View {
    let issues: [WizardIssue]
    let isFixing: Bool
    let onAutoFix: () -> Void
    let onRefresh: () async -> Void
    let kanataManager: KanataManager

    @State private var isScanning = false
    @State private var isDisablingPermanently = false

    // Check if there are Karabiner-related conflicts
    private var hasKarabinerConflict: Bool {
        issues.contains { issue in
            issue.description.lowercased().contains("karabiner")
        }
    }

    var body: some View {
        VStack(spacing: WizardDesign.Spacing.sectionGap) {
            // Header using design system
            WizardPageHeader(
                icon: issues.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                title: issues.isEmpty ? "No Conflicts Detected" : "Conflicting Processes",
                subtitle: issues.isEmpty ?
                    "No conflicting keyboard remapping processes found. You're ready to proceed!" :
                    "Conflicting keyboard remapping processes must be stopped before continuing",
                status: issues.isEmpty ? .success : .warning
            )

            // Issues List
            if !issues.isEmpty {
                VStack(spacing: WizardDesign.Spacing.itemGap) {
                    ForEach(issues) { issue in
                        IssueCardView(
                            issue: issue,
                            onAutoFix: issue.autoFixAction != nil ? onAutoFix : nil,
                            isFixing: isFixing,
                            kanataManager: kanataManager
                        )
                    }
                }
                .wizardPagePadding()
            }

            // Explanation using design system
            VStack(alignment: .leading, spacing: WizardDesign.Spacing.itemGap) {
                if issues.isEmpty {
                    VStack(spacing: WizardDesign.Spacing.itemGap) {
                        HStack(spacing: WizardDesign.Spacing.labelGap) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(WizardDesign.Colors.success)
                                .font(WizardDesign.Typography.body)
                            Text("System Status: Clean")
                                .font(WizardDesign.Typography.status)
                        }
                        .foregroundColor(WizardDesign.Colors.success)

                        Text("KeyPath checked for conflicts and found none. The system is ready for keyboard remapping.")
                            .font(WizardDesign.Typography.body)
                            .foregroundColor(WizardDesign.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    Text("Common conflicting processes:")
                        .font(WizardDesign.Typography.subsectionTitle)
                        .foregroundColor(WizardDesign.Colors.secondaryText)

                    VStack(alignment: .leading, spacing: WizardDesign.Spacing.labelGap) {
                        Label("Karabiner-Elements (conflicts with Kanata)", systemImage: "keyboard")
                        Label("Other Kanata instances running with root privileges", systemImage: "terminal")
                        Label("Previous KeyPath processes that didn't shut down properly", systemImage: "xmark.app")
                        Label("Manual Kanata installations running in the background", systemImage: "gearshape.2")
                    }
                    .font(WizardDesign.Typography.caption)
                    .padding(.leading, WizardDesign.Spacing.indentation)
                }
            }
            .wizardPagePadding()

            Spacer()

            // Action Buttons using design system
            VStack(spacing: WizardDesign.Spacing.elementGap) {
                if !issues.isEmpty && issues.first?.autoFixAction != nil {
                    Button("Terminate Conflicting Processes") {
                        onAutoFix()
                    }
                    .buttonStyle(WizardDesign.Component.PrimaryButton(isLoading: isFixing))
                    .disabled(isFixing)

                    // Add permanent disable option for Karabiner Elements
                    if hasKarabinerConflict {
                        Button(action: {
                            Task {
                                isDisablingPermanently = true
                                let success = await kanataManager.disableKarabinerElementsPermanently()
                                if success {
                                    await onRefresh()
                                }
                                isDisablingPermanently = false
                            }
                        }) {
                            Text(isDisablingPermanently ? "Disabling..." : "Permanently Disable Conflicting Services")
                        }
                        .buttonStyle(WizardDesign.Component.DestructiveButton(isLoading: isDisablingPermanently))
                        .disabled(isDisablingPermanently || isFixing)
                    }
                }

                Button(action: {
                    Task {
                        isScanning = true
                        await onRefresh()
                        // Keep spinner visible for a moment so user sees the action
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        isScanning = false
                    }
                }) {
                    Text(isScanning ? "Scanning..." : (issues.isEmpty ? "Re-scan for Conflicts" : "Check Again"))
                }
                .buttonStyle(WizardDesign.Component.SecondaryButton(isLoading: isScanning))
                .disabled(isFixing || isScanning)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WizardDesign.Colors.wizardBackground)
    }
}
