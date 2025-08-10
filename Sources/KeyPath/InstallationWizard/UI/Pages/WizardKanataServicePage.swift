import SwiftUI

struct WizardKanataServicePage: View {
  @ObservedObject var kanataManager: KanataManager
  @State private var isPerformingAction = false
  @State private var lastError: String?
  @State private var serviceStatus: ServiceStatus = .unknown
  @State private var refreshTimer: Timer?

  // Integration with SimpleKanataManager for better error context
  @State private var simpleKanataManager: SimpleKanataManager?

  enum ServiceStatus: Equatable {
    case unknown
    case running
    case stopped
    case crashed(error: String)
    case starting
    case stopping

    var color: Color {
      switch self {
      case .running: return .green
      case .stopped: return .orange
      case .crashed: return .red
      case .starting, .stopping: return .blue
      case .unknown: return .gray
      }
    }

    var icon: String {
      switch self {
      case .running: return "checkmark.circle.fill"
      case .stopped: return "stop.circle.fill"
      case .crashed: return "exclamationmark.triangle.fill"
      case .starting, .stopping: return "arrow.clockwise.circle.fill"
      case .unknown: return "questionmark.circle.fill"
      }
    }

    var description: String {
      switch self {
      case .running: return "Service is running"
      case .stopped: return "Service is stopped"
      case let .crashed(error): return "Service crashed: \(error)"
      case .starting: return "Service is starting..."
      case .stopping: return "Service is stopping..."
      case .unknown: return "Checking service status..."
      }
    }
  }

  var body: some View {
    VStack(spacing: WizardDesign.Spacing.sectionGap) {
      // Header
      WizardPageHeader(
        icon: "keyboard.chevron.compact.down.fill",
        title: "Kanata Service",
        subtitle: "Monitor and control the keyboard remapping service",
        status: statusForHeader
      )

      // Service Status Card
      VStack(spacing: 20) {
        // Status Indicator
        HStack(spacing: 16) {
          Image(systemName: serviceStatus.icon)
            .font(.system(size: 48))
            .foregroundColor(serviceStatus.color)
            .animation(.easeInOut(duration: 0.3), value: serviceStatus.icon)

          VStack(alignment: .leading, spacing: 4) {
            Text(statusTitle)
              .font(.title2)
              .fontWeight(.semibold)

            Text(serviceStatus.description)
              .font(.body)
              .foregroundColor(.secondary)
          }

          Spacer()
        }
        .padding(24)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)

        // Service Details
        VStack(alignment: .leading, spacing: 12) {
          DetailRow(label: "Process ID", value: pidValue)
          DetailRow(label: "Config File", value: configPath)
          DetailRow(label: "Log File", value: WizardSystemPaths.kanataLogFile)
          DetailRow(label: "Uptime", value: uptimeValue)

          if let error = lastError {
            VStack(alignment: .leading, spacing: 8) {
              Label("Last Error", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundColor(.red)

              Text(error)
                .font(.system(.body, design: .monospaced))
                .padding(12)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .textSelection(.enabled)
            }
            .padding(.top, 8)
          }
        }
        .padding(.horizontal, 24)

        // Control Buttons
        HStack(spacing: 16) {
          Button(action: startService) {
            Label("Start", systemImage: "play.fill")
              .frame(width: WizardDesign.Layout.buttonWidthSmall)
          }
          .buttonStyle(WizardDesign.Component.SecondaryButton())
          .disabled(isPerformingAction || serviceStatus == .running)

          Button(action: restartService) {
            Label("Restart", systemImage: "arrow.clockwise")
              .frame(width: WizardDesign.Layout.buttonWidthSmall)
          }
          .buttonStyle(WizardDesign.Component.SecondaryButton())
          .disabled(isPerformingAction)

          Button(action: stopService) {
            Label("Stop", systemImage: "stop.fill")
              .frame(width: WizardDesign.Layout.buttonWidthSmall)
          }
          .buttonStyle(WizardDesign.Component.SecondaryButton())
          .disabled(isPerformingAction || serviceStatus == .stopped)

          Spacer()

          Button(action: refreshStatus) {
            Label("Refresh", systemImage: "arrow.clockwise")
          }
          .buttonStyle(WizardDesign.Component.SecondaryButton())
          .disabled(isPerformingAction)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
      }
      .padding(.horizontal, 40)

      Spacer()

      // Help Text
      VStack(spacing: 8) {
        Text("The Kanata service handles keyboard remapping in the background.")
          .font(.caption)
          .foregroundColor(.secondary)

        if case .crashed = serviceStatus {
          Text("If the service keeps crashing, check the log file for details.")
            .font(.caption)
            .foregroundColor(.orange)
        }
      }
      .padding(.horizontal, 40)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(WizardDesign.Colors.wizardBackground)
    .onAppear {
      startAutoRefresh()
      refreshStatus()
    }
    .onDisappear {
      stopAutoRefresh()
    }
  }

  // MARK: - Computed Properties

  private var statusForHeader: WizardPageHeader.HeaderStatus {
    switch serviceStatus {
    case .running: return .success
    case .stopped, .unknown: return .info
    case .crashed: return .error
    case .starting, .stopping: return .warning
    }
  }

  private var statusTitle: String {
    switch serviceStatus {
    case .running: return "Service Running"
    case .stopped: return "Service Stopped"
    case .crashed: return "Service Crashed"
    case .starting: return "Starting Service"
    case .stopping: return "Stopping Service"
    case .unknown: return "Unknown Status"
    }
  }

  private var pidValue: String {
    if kanataManager.isRunning {
      // Get PID from kanataManager if available
      return "Active"
    } else {
      return "Not running"
    }
  }

  private var configPath: String {
    if WizardSystemPaths.userConfigExists {
      return WizardSystemPaths.displayPath(for: WizardSystemPaths.userConfigPath)
    } else {
      return "Not found"
    }
  }

  private var uptimeValue: String {
    // This would need to track service start time
    if kanataManager.isRunning {
      return "Active"
    } else {
      return "—"
    }
  }

  // MARK: - Actions

  private func startService() {
    isPerformingAction = true
    serviceStatus = .starting
    lastError = nil

    Task {
      await kanataManager.startKanataWithSafetyTimeout()

      await MainActor.run {
        isPerformingAction = false
        refreshStatus()
      }
    }
  }

  private func restartService() {
    isPerformingAction = true
    serviceStatus = .stopping
    lastError = nil

    Task {
      await kanataManager.stopKanata()
      try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second

      await MainActor.run {
        serviceStatus = .starting
      }

      await kanataManager.startKanataWithSafetyTimeout()

      await MainActor.run {
        isPerformingAction = false
        refreshStatus()
      }
    }
  }

  private func stopService() {
    isPerformingAction = true
    serviceStatus = .stopping

    Task {
      await kanataManager.stopKanata()

      // Give it a moment to stop
      try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second

      await MainActor.run {
        isPerformingAction = false
        refreshStatus()
      }
    }
  }

  private func refreshStatus() {
    // Check if service is running
    if kanataManager.isRunning {
      serviceStatus = .running
      lastError = nil
    } else {
      // Check if it crashed by looking for recent errors
      checkForCrash()
    }
  }

  private func checkForCrash() {
    // Check log file for recent crash indicators
    let logPath = WizardSystemPaths.kanataLogFile

    if let logData = try? String(contentsOfFile: logPath, encoding: .utf8) {
      let lines = logData.components(separatedBy: .newlines)
      let recentLines = lines.suffix(20)  // Check last 20 lines

      for line in recentLines.reversed() {
        if line.contains("ERROR") || line.contains("FATAL") || line.contains("panic") {
          serviceStatus = .crashed(error: extractErrorMessage(from: line))
          lastError = line
          return
        }
      }
    }

    // No crash detected, just stopped
    serviceStatus = .stopped
  }

  private func extractErrorMessage(from logLine: String) -> String {
    // Extract meaningful error message from log line
    if logLine.contains("Permission denied") {
      return "Permission denied - check Input Monitoring settings"
    } else if logLine.contains("Config error") {
      return "Configuration error - check your keypath.kbd file"
    } else if logLine.contains("Device not found") {
      return "Keyboard device not found"
    } else {
      return "Check log file for details"
    }
  }

  // MARK: - Auto Refresh

  private func startAutoRefresh() {
    // DISABLED: This timer calls refreshStatus() which may trigger invasive permission checks
    // that cause KeyPath to auto-add to Input Monitoring system preferences
    
    AppLogger.shared.log("🔄 [WizardKanataServicePage] Auto-refresh timer DISABLED to prevent invasive permission checks")
  }

  private func stopAutoRefresh() {
    refreshTimer?.invalidate()
    refreshTimer = nil
  }
}

// MARK: - Supporting Views

struct DetailRow: View {
  let label: String
  let value: String

  var body: some View {
    HStack {
      Text(label)
        .foregroundColor(.secondary)
        .frame(width: 120, alignment: .leading)

      Text(value)
        .fontWeight(.medium)
        .textSelection(.enabled)

      Spacer()
    }
  }
}

// MARK: - Preview

struct WizardKanataServicePage_Previews: PreviewProvider {
  static var previews: some View {
    WizardKanataServicePage(kanataManager: KanataManager())
  }
}
