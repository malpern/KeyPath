import SwiftUI

// MARK: - Summary Item View

struct SummaryItemView: View {
    let icon: String
    let title: String
    let status: InstallationStatus
    let onTap: (() -> Void)?

    init(icon: String, title: String, status: InstallationStatus, onTap: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.status = status
        self.onTap = onTap
    }

    var body: some View {
        HStack(spacing: WizardDesign.Spacing.iconGap) {
            Image(systemName: icon)
                .font(WizardDesign.Typography.subsectionTitle)
                .foregroundColor(iconColor)
                .frame(width: 30)

            Text(title)
                .font(WizardDesign.Typography.body)

            Spacer()

            statusIcon
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .background(Color.clear)
        .help(onTap != nil ? "Click to open settings" : "")
    }

    var iconColor: Color {
        switch status {
        case .completed: return WizardDesign.Colors.success
        case .inProgress: return WizardDesign.Colors.inProgress
        case .failed: return WizardDesign.Colors.error
        case .notStarted: return WizardDesign.Colors.secondaryText
        }
    }

    @ViewBuilder
    var statusIcon: some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(WizardDesign.Colors.success)
                .font(WizardDesign.Typography.subsectionTitle)
        case .inProgress:
            ProgressView()
                .scaleEffect(0.7)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(WizardDesign.Colors.error)
                .font(WizardDesign.Typography.subsectionTitle)
        case .notStarted:
            Image(systemName: "circle")
                .foregroundColor(WizardDesign.Colors.secondaryText.opacity(0.5))
                .font(WizardDesign.Typography.subsectionTitle)
        }
    }
}

// MARK: - Installation Item View

struct InstallationItemView: View {
    let title: String
    let description: String
    let status: InstallationStatus
    let autoFixButton: (() -> AnyView)?

    init(title: String, description: String, status: InstallationStatus, autoFixButton: (() -> AnyView)? = nil) {
        self.title = title
        self.description = description
        self.status = status
        self.autoFixButton = autoFixButton
    }

    var body: some View {
        HStack(spacing: WizardDesign.Spacing.itemGap) {
            statusIcon
                .frame(width: 24)

            VStack(alignment: .leading, spacing: WizardDesign.Spacing.labelGap / 2) {
                Text(title)
                    .font(WizardDesign.Typography.subsectionTitle)
                Text(description)
                    .font(WizardDesign.Typography.caption)
                    .foregroundColor(WizardDesign.Colors.secondaryText)
            }

            Spacer()

            // Fix button area - buttons now have fixed dimensions to prevent layout jumping
            if let autoFixButton = autoFixButton {
                autoFixButton()
            }
        }
        .wizardCard()
    }

    @ViewBuilder
    var statusIcon: some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(WizardDesign.Colors.success)
                .font(WizardDesign.Typography.sectionTitle)
        case .inProgress:
            ProgressView()
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(WizardDesign.Colors.error)
                .font(WizardDesign.Typography.sectionTitle)
        case .notStarted:
            Image(systemName: "circle.dashed")
                .foregroundColor(WizardDesign.Colors.secondaryText.opacity(0.5))
                .font(WizardDesign.Typography.sectionTitle)
        }
    }
}

// MARK: - Issue Card View

struct IssueCardView: View {
    let issue: WizardIssue
    let onAutoFix: (() -> Void)?
    let isFixing: Bool
    let kanataManager: KanataManager?

    @State private var showingBackgroundServicesHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
            HStack(spacing: WizardDesign.Spacing.iconGap) {
                Image(systemName: issue.severity.icon)
                    .font(.title2)
                    .foregroundColor(issue.severity.color)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: WizardDesign.Spacing.labelGap / 2) {
                    Text(issue.title)
                        .font(WizardDesign.Typography.subsectionTitle)
                        .foregroundColor(.primary)

                    Text(issue.description)
                        .font(WizardDesign.Typography.body)
                        .foregroundColor(WizardDesign.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            if issue.autoFixAction != nil, let onAutoFix = onAutoFix {
                HStack {
                    Spacer()

                    WizardButton(isFixing ? "Fixing..." : "Fix", style: .secondary, isLoading: isFixing) {
                        onAutoFix()
                    }
                }
            } else if let userAction = issue.userAction {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Action Required:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    HStack {
                        Text(userAction)
                            .font(.caption)
                            .foregroundColor(.blue)

                        Spacer()

                        // Add help button for Background Services issues
                        if issue.category == .backgroundServices {
                            Button("Help") {
                                showingBackgroundServicesHelp = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                }
            }
        }
        .wizardCard()
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1)
        )
        .sheet(isPresented: $showingBackgroundServicesHelp) {
            if let kanataManager = kanataManager {
                BackgroundServicesHelpSheet(kanataManager: kanataManager)
            }
        }
    }

    var backgroundColor: Color {
        switch issue.severity {
        case .info:
            return Color.blue.opacity(0.05)
        case .warning:
            return Color.orange.opacity(0.05)
        case .error, .critical:
            return Color.red.opacity(0.05)
        }
    }

    var borderColor: Color {
        switch issue.severity {
        case .info:
            return Color.blue.opacity(0.2)
        case .warning:
            return Color.orange.opacity(0.2)
        case .error, .critical:
            return Color.red.opacity(0.2)
        }
    }
}

// MARK: - Progress Indicator

struct WizardProgressView: View {
    let progress: Double
    let description: String

    var body: some View {
        VStack(spacing: WizardDesign.Spacing.labelGap) {
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle(tint: WizardDesign.Colors.primaryAction))
                .frame(height: 6)

            HStack {
                Text(description)
                    .font(WizardDesign.Typography.caption)
                    .foregroundColor(WizardDesign.Colors.secondaryText)

                Spacer()

                Text("\(Int(progress * 100))%")
                    .font(WizardDesign.Typography.caption)
                    .fontWeight(.medium)
                    .foregroundColor(WizardDesign.Colors.secondaryText)
            }
        }
    }
}

// MARK: - Page Dots Indicator

struct PageDotsIndicator: View {
    let currentPage: WizardPage
    let onPageSelected: (WizardPage) -> Void

    var body: some View {
        HStack(spacing: WizardDesign.Spacing.labelGap) {
            ForEach(WizardPage.allCases, id: \.self) { page in
                Circle()
                    .fill(currentPage == page ? WizardDesign.Colors.primaryAction : WizardDesign.Colors.secondaryText.opacity(0.4))
                    .frame(width: 8, height: 8)
                    .scaleEffect(currentPage == page ? 1.2 : 1.0)
                    .animation(WizardDesign.Animation.buttonFeedback, value: currentPage)
                    .onTapGesture {
                        onPageSelected(page)
                    }
                    .accessibilityLabel("Page \(pageIndex(page) + 1): \(page.rawValue)")
                    .accessibilityAddTraits(currentPage == page ? [.isSelected, .isButton] : .isButton)
                    .accessibilityHint("Tap to navigate to \(page.rawValue) page")
            }
        }
        .padding(.vertical, WizardDesign.Spacing.labelGap)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Setup progress: page \(pageIndex(currentPage) + 1) of \(WizardPage.allCases.count)")
    }

    private func pageIndex(_ page: WizardPage) -> Int {
        return WizardPage.allCases.firstIndex(of: page) ?? 0
    }
}
