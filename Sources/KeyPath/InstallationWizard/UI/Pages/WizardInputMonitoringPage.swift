import SwiftUI

/// Input Monitoring permission page - dedicated page for Input Monitoring permissions
struct WizardInputMonitoringPage: View {
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
        icon: !hasInputMonitoringIssues ? "checkmark.circle.fill" : "eye",
        title: !hasInputMonitoringIssues ? "Input Monitoring Granted" : "Input Monitoring Required",
        subtitle: !hasInputMonitoringIssues ? "KeyPath has the necessary Input Monitoring permission." : "KeyPath needs Input Monitoring permission to capture keyboard events for remapping.",
        status: !hasInputMonitoringIssues ? .success : .warning
      )

      VStack(spacing: WizardDesign.Spacing.elementGap) {
          // KeyPath Input Monitoring Permission
          PermissionCard(
            appName: "KeyPath",
            appPath: "/Applications/KeyPath.app",
            status: keyPathInputMonitoringStatus,
            permissionType: "Input Monitoring",
            kanataManager: kanataManager
          )
          
          // Kanata Input Monitoring Permission
          PermissionCard(
            appName: "kanata",
            appPath: "/usr/local/bin/kanata",
            status: kanataInputMonitoringStatus,
            permissionType: "Input Monitoring", 
            kanataManager: kanataManager
          )

          if hasInputMonitoringIssues {
            VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
              Text("Why This Permission Is Needed")
                .font(.headline)
                .foregroundColor(.primary)

              VStack(alignment: .leading, spacing: 4) {
                Label("Capture keyboard events for remapping", systemImage: "keyboard")
                Label("Detect key combinations and shortcuts", systemImage: "command")
                Label("Process input for configuration testing", systemImage: "gear")
              }
              .font(.caption)
              .foregroundColor(.secondary)

              Text("Grant this permission in System Settings > Privacy & Security > Input Monitoring")
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
            
            // Open Input Monitoring Settings Button
            Button("Grant Permission") {
              openInputMonitoringSettings()
            }
            .buttonStyle(.borderedProminent)
          }
      }
    }
  }

  // MARK: - Computed Properties

  private var hasInputMonitoringIssues: Bool {
    keyPathInputMonitoringStatus != .completed || kanataInputMonitoringStatus != .completed
  }

  private var keyPathInputMonitoringStatus: InstallationStatus {
    let hasKeyPathIssue = issues.contains { issue in
      if case .permission(let permissionType) = issue.identifier {
        return permissionType == .keyPathInputMonitoring
      }
      return false
    }
    return hasKeyPathIssue ? .notStarted : .completed
  }

  private var kanataInputMonitoringStatus: InstallationStatus {
    let hasKanataIssue = issues.contains { issue in
      if case .permission(let permissionType) = issue.identifier {
        return permissionType == .kanataInputMonitoring
      }
      return false
    }
    return hasKanataIssue ? .notStarted : .completed
  }

  // MARK: - Actions

  private func openInputMonitoringSettings() {
    AppLogger.shared.log("🔐 [WizardInputMonitoringPage] Opening Input Monitoring settings and dismissing wizard")
    
    // Open System Settings > Privacy & Security > Input Monitoring
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
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

struct WizardInputMonitoringPage_Previews: PreviewProvider {
  static var previews: some View {
    WizardInputMonitoringPage(
      systemState: .missingPermissions(missing: [.keyPathInputMonitoring]),
      issues: [
        WizardIssue(
          identifier: .permission(.keyPathInputMonitoring),
          severity: .critical,
          category: .permissions,
          title: "Input Monitoring Required",
          description: "KeyPath needs Input Monitoring permission to capture keyboard events.",
          autoFixAction: nil,
          userAction: "Grant permission in System Settings > Privacy & Security > Input Monitoring"
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