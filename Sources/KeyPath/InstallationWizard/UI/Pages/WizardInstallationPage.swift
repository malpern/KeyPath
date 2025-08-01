import SwiftUI

struct WizardInstallationPage: View {
    let issues: [WizardIssue]
    let isFixing: Bool
    let onAutoFix: () -> Void
    let onRefresh: () async -> Void
    let kanataManager: KanataManager
    
    var body: some View {
        VStack(spacing: WizardDesign.Spacing.sectionGap) {
            // Header using design system
            WizardPageHeader(
                icon: "arrow.down.circle.fill",
                title: "Install Components",
                subtitle: "Set up required system components",
                status: .info
            )
            
            // Installation Status
            VStack(spacing: WizardDesign.Spacing.itemGap) {
                InstallationItemView(
                    title: "Kanata Binary",
                    description: "Core keyboard remapping engine",
                    status: componentStatus(for: "Kanata Binary")
                )
                
                InstallationItemView(
                    title: "Kanata Service",
                    description: "Direct kanata execution with --watch support",
                    status: .completed // Always available
                )
                
                InstallationItemView(
                    title: "Karabiner Driver",
                    description: "Virtual keyboard driver for input capture",
                    status: componentStatus(for: "Karabiner Driver")
                )
            }
            .padding(.horizontal, 40)
            
            // Issues (if any)
            if !issues.isEmpty {
                VStack(spacing: 12) {
                    ForEach(issues) { issue in
                        IssueCardView(
                            issue: issue,
                            onAutoFix: issue.autoFixAction != nil ? onAutoFix : nil,
                            isFixing: isFixing,
                            kanataManager: kanataManager
                        )
                    }
                }
                .padding(.horizontal, 40)
            }
            
            Spacer()
            
            // Action Buttons
            if isFixing {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Installing components...")
                        .foregroundColor(.secondary)
                }
            } else if allComponentsInstalled {
                VStack(spacing: WizardDesign.Spacing.elementGap) {
                    HStack(spacing: WizardDesign.Spacing.labelGap) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(WizardDesign.Colors.success)
                            .font(WizardDesign.Typography.body)
                        Text("Components installed")
                            .font(WizardDesign.Typography.status)
                    }
                    .foregroundColor(WizardDesign.Colors.secondaryText)
                }
            } else {
                VStack(spacing: WizardDesign.Spacing.elementGap) {
                    Button("Install Components") {
                        onAutoFix()
                    }
                    .buttonStyle(WizardDesign.Component.PrimaryButton(isLoading: isFixing))
                    .disabled(isFixing)
                    
                    Text("Administrator password required")
                        .font(WizardDesign.Typography.caption)
                        .foregroundColor(WizardDesign.Colors.secondaryText)
                }
            }
        }
        .frame(width: WizardDesign.Layout.pageWidth, height: WizardDesign.Layout.pageHeight)
        .background(WizardDesign.Colors.wizardBackground)
    }
    
    // MARK: - Helper Methods
    
    private func componentStatus(for componentName: String) -> InstallationStatus {
        // Check if there's an issue for this component
        let hasIssue = issues.contains { issue in
            issue.category == .installation && issue.title.contains(componentName)
        }
        
        return hasIssue ? .failed : .completed
    }
    
    private var allComponentsInstalled: Bool {
        // No installation issues means all components are installed
        !issues.contains { $0.category == .installation }
    }
}