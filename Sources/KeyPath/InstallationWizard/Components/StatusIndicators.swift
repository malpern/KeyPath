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
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 30)
            
            Text(title)
                .font(.body)
            
            Spacer()
            
            statusIcon
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .background(onTap != nil ? Color.clear : Color.clear)
        .help(onTap != nil ? "Click to open settings" : "")
    }
    
    var iconColor: Color {
        switch status {
        case .completed: return .green
        case .inProgress: return .blue
        case .failed: return .red
        case .notStarted: return .gray
        }
    }
    
    @ViewBuilder
    var statusIcon: some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title3)
        case .inProgress:
            ProgressView()
                .scaleEffect(0.7)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.title3)
        case .notStarted:
            Image(systemName: "circle")
                .foregroundColor(.gray.opacity(0.5))
                .font(.title3)
        }
    }
}

// MARK: - Installation Item View

struct InstallationItemView: View {
    let title: String
    let description: String
    let status: InstallationStatus
    
    var body: some View {
        HStack(spacing: 16) {
            statusIcon
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    var statusIcon: some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title2)
        case .inProgress:
            ProgressView()
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.title2)
        case .notStarted:
            Image(systemName: "circle.dashed")
                .foregroundColor(.gray.opacity(0.5))
                .font(.title2)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: issue.severity.icon)
                    .font(.title2)
                    .foregroundColor(issue.severity.color)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(issue.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(issue.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
            }
            
            if issue.autoFixAction != nil, let onAutoFix = onAutoFix {
                HStack {
                    Spacer()
                    
                    Button(action: onAutoFix) {
                        HStack(spacing: 6) {
                            if isFixing {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle())
                                Text("Fixing...")
                            } else {
                                Image(systemName: "wrench.and.screwdriver")
                                Text("Auto-Fix")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isFixing)
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
                        if issue.title.contains("Background Services") {
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
        .padding()
        .background(backgroundColor)
        .cornerRadius(12)
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
        VStack(spacing: 8) {
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                .frame(height: 6)
            
            HStack {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Page Dots Indicator

struct PageDotsIndicator: View {
    let currentPage: WizardPage
    let onPageSelected: (WizardPage) -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(WizardPage.allCases, id: \.self) { page in
                Circle()
                    .fill(currentPage == page ? Color.accentColor : Color.gray.opacity(0.4))
                    .frame(width: 8, height: 8)
                    .scaleEffect(currentPage == page ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: currentPage)
                    .onTapGesture {
                        onPageSelected(page)
                    }
            }
        }
        .padding(.vertical, 8)
    }
}