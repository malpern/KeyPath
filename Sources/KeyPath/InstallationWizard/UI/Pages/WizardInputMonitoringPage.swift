import SwiftUI

/// Input Monitoring permission page with hybrid permission request approach
struct WizardInputMonitoringPage: View {
  let systemState: WizardSystemState
  let issues: [WizardIssue]
  let onRefresh: () async -> Void
  let onNavigateToPage: ((WizardPage) -> Void)?
  let onDismiss: (() -> Void)?
  let kanataManager: KanataManager
  
  @State private var showingStaleEntryCleanup = false
  @State private var staleEntryDetails: [String] = []
  @State private var attemptingProgrammaticRequest = false
  @State private var programmaticRequestFailed = false

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
        // Show cleanup instructions if stale entries detected
        if showingStaleEntryCleanup {
          StaleEntryCleanupInstructions(
            staleEntryDetails: staleEntryDetails,
            onContinue: {
              showingStaleEntryCleanup = false
              openInputMonitoringSettings()
            }
          )
        } else {
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
              
              if programmaticRequestFailed {
                Text("⚠️ Automatic permission request was denied. Please grant permission manually in System Settings.")
                  .font(.caption)
                  .foregroundColor(.orange)
                  .padding(.top, 4)
              } else {
                Text("Click 'Grant Permission' to enable Input Monitoring")
                  .font(.caption)
                  .foregroundColor(.orange)
                  .padding(.top, 4)
              }
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(WizardDesign.Layout.cornerRadius)
          }

          Spacer()

          // Action Buttons
          HStack(spacing: 12) {
            // Manual Refresh Button
            Button("Check Again") {
              Task {
                programmaticRequestFailed = false
                await onRefresh()
              }
            }
            .buttonStyle(.bordered)
            .disabled(attemptingProgrammaticRequest)
            
            Spacer()
            
            // Smart Grant Permission Button
            Button(action: handleGrantPermission) {
              if attemptingProgrammaticRequest {
                ProgressView()
                  .scaleEffect(0.8)
                  .frame(width: 16, height: 16)
              } else {
                Text(programmaticRequestFailed ? "Open Settings" : "Grant Permission")
              }
            }
            .buttonStyle(.borderedProminent)
            .disabled(attemptingProgrammaticRequest)
          }
        }
      }
    }
    .onAppear {
      checkForStaleEntries()
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
  
  private func checkForStaleEntries() {
    let detection = PermissionService.detectPossibleStaleEntries()
    if detection.hasStaleEntries {
      staleEntryDetails = detection.details
      AppLogger.shared.log("🔐 [WizardInputMonitoringPage] Stale entries detected: \(detection.details.joined(separator: ", "))")
    }
  }
  
  private func handleGrantPermission() {
    // First check for stale entries
    let detection = PermissionService.detectPossibleStaleEntries()
    
    if detection.hasStaleEntries {
      // Show cleanup instructions first
      staleEntryDetails = detection.details
      showingStaleEntryCleanup = true
      AppLogger.shared.log("🔐 [WizardInputMonitoringPage] Showing cleanup instructions for stale entries")
    } else {
      // Try programmatic request for clean installs
      if #available(macOS 10.15, *), !programmaticRequestFailed {
        attemptProgrammaticRequest()
      } else {
        // Fall back to manual process
        openInputMonitoringSettings()
      }
    }
  }
  
  @available(macOS 10.15, *)
  private func attemptProgrammaticRequest() {
    AppLogger.shared.log("🔐 [WizardInputMonitoringPage] Attempting programmatic permission request")
    attemptingProgrammaticRequest = true
    
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      let granted = PermissionService.requestInputMonitoringPermission()
      attemptingProgrammaticRequest = false
      
      if granted {
        AppLogger.shared.log("🔐 [WizardInputMonitoringPage] Permission granted programmatically!")
        Task {
          await onRefresh()
        }
      } else {
        AppLogger.shared.log("🔐 [WizardInputMonitoringPage] Programmatic request denied, falling back to manual")
        programmaticRequestFailed = true
        // Give user a moment to see the status change before opening settings
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
          openInputMonitoringSettings()
        }
      }
    }
  }

  private func openInputMonitoringSettings() {
    AppLogger.shared.log("🔐 [WizardInputMonitoringPage] Opening Input Monitoring settings")
    
    PermissionService.openInputMonitoringSettings()
    
    // Dismiss wizard after opening settings for better UX
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      onDismiss?()
    }
  }
}

// MARK: - Stale Entry Cleanup Instructions View

struct StaleEntryCleanupInstructions: View {
  let staleEntryDetails: [String]
  let onContinue: () -> Void
  
  var body: some View {
    VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
      VStack(alignment: .leading, spacing: 8) {
        Label("Old KeyPath Entries Detected", systemImage: "exclamationmark.triangle.fill")
          .font(.headline)
          .foregroundColor(.orange)
        
        Text("We've detected possible old or duplicate KeyPath entries that need to be cleaned up before granting new permissions.")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      
      // Show detected issues
      if !staleEntryDetails.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("Detected Issues:")
            .font(.caption)
            .fontWeight(.semibold)
          
          ForEach(staleEntryDetails, id: \.self) { detail in
            HStack(alignment: .top, spacing: 6) {
              Text("•")
                .foregroundColor(.orange)
              Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
        .padding()
        .background(Color.orange.opacity(0.05))
        .cornerRadius(8)
      }
      
      // Cleanup Instructions
      VStack(alignment: .leading, spacing: 12) {
        Text("How to Clean Up:")
          .font(.headline)
        
        CleanupStep(number: 1, text: "Click 'Open Settings' below")
        CleanupStep(number: 2, text: "Find ALL KeyPath entries in the list")
        CleanupStep(number: 3, text: "Remove entries with ⚠️ warning icons by clicking the '-' button")
        CleanupStep(number: 4, text: "Remove any duplicate KeyPath entries")
        CleanupStep(number: 5, text: "Add the current KeyPath using the '+' button")
        CleanupStep(number: 6, text: "Also add 'kanata' if needed")
      }
      .padding()
      .background(Color.blue.opacity(0.05))
      .cornerRadius(8)
      
      // Visual hint
      HStack {
        Image(systemName: "lightbulb.fill")
          .foregroundColor(.yellow)
        Text("Tip: Entries with warning icons are from old or moved installations")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      .padding(.horizontal)
      
      Spacer()
      
      // Continue button
      Button("Open Settings") {
        onContinue()
      }
      .buttonStyle(.borderedProminent)
      .frame(maxWidth: .infinity)
    }
    .padding()
  }
}

struct CleanupStep: View {
  let number: Int
  let text: String
  
  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Text("\(number).")
        .font(.caption)
        .fontWeight(.bold)
        .foregroundColor(.blue)
        .frame(width: 20, alignment: .leading)
      
      Text(text)
        .font(.caption)
        .foregroundColor(.primary)
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