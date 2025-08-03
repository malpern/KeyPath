import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject var kanataManager: KanataManager
  @State private var showingResetConfirmation = false
  @State private var isDaemonRunning = false
  @State private var isStartingDaemon = false
  @State private var actualKanataRunning = false
  @State private var showingDiagnostics = false

  private var kanataServiceStatus: String {
    if actualKanataRunning {
      return "Running"
    } else if kanataManager.isRunning {
      return "Starting..."
    } else {
      return "Stopped"
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Text("Settings")
          .font(.system(size: 20, weight: .semibold))
          .foregroundColor(.primary)

        Spacer()

        Button("Done") {
          dismiss()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
      }
      .padding(.horizontal, 24)
      .padding(.vertical, 20)
      .background(Color(NSColor.controlBackgroundColor))

      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          // Status Section
          SettingsSection(title: "Status") {
            StatusRow(
              label: "Kanata Service",
              status: kanataServiceStatus,
              isActive: kanataServiceStatus == "Running"
            )

            StatusRow(
              label: "Karabiner Daemon",
              status: isDaemonRunning ? "Running" : "Stopped",
              isActive: isDaemonRunning
            )

            StatusRow(
              label: "Installation",
              status: kanataManager.isCompletelyInstalled() ? "Installed" : "Not Installed",
              isActive: kanataManager.isCompletelyInstalled()
            )
          }

          Divider()

          // Service Control Section
          SettingsSection(title: "Service Control") {
            VStack(spacing: 10) {
              SettingsButton(
                title: kanataManager.isRunning ? "Stop Service" : "Start Service",
                systemImage: kanataManager.isRunning ? "stop.circle" : "play.circle",
                action: {
                  Task {
                    if kanataManager.isRunning {
                      await kanataManager.stopKanata()
                    } else {
                      await kanataManager.startKanata()
                    }
                  }
                }
              )

              if !isDaemonRunning {
                SettingsButton(
                  title: isStartingDaemon ? "Starting Daemon..." : "Start Karabiner Daemon",
                  systemImage: isStartingDaemon ? "gear" : "play.circle.fill",
                  disabled: isStartingDaemon,
                  action: {
                    startDaemon()
                  }
                )
              }

              SettingsButton(
                title: "Restart Service",
                systemImage: "arrow.clockwise.circle",
                disabled: !kanataManager.isRunning,
                action: {
                  Task {
                    await kanataManager.restartKanata()
                  }
                }
              )

              SettingsButton(
                title: "Refresh Status",
                systemImage: "arrow.clockwise",
                action: {
                  Task {
                    await refreshStatus()
                  }
                }
              )
            }
          }

          Divider()

          // Configuration Section
          SettingsSection(title: "Configuration") {
            VStack(spacing: 10) {
              SettingsButton(
                title: "Edit Configuration",
                systemImage: "doc.text",
                action: {
                  openConfigInZed()
                }
              )

              SettingsButton(
                title: "Reset to Default",
                systemImage: "arrow.counterclockwise",
                style: .destructive,
                action: {
                  showingResetConfirmation = true
                }
              )
            }
          }

          Divider()

          // Diagnostics Section
          SettingsSection(title: "Diagnostics") {
            VStack(spacing: 10) {
              SettingsButton(
                title: "Show Diagnostics",
                systemImage: "stethoscope",
                action: {
                  showingDiagnostics = true
                }
              )

              // Log access buttons
              HStack(spacing: 10) {
                SettingsButton(
                  title: "KeyPath Logs",
                  systemImage: "doc.text",
                  action: {
                    openKeyPathLogs()
                  }
                )

                SettingsButton(
                  title: "Kanata Logs",
                  systemImage: "terminal",
                  action: {
                    openKanataLogs()
                  }
                )
              }

              // Quick diagnostic summary
              if !kanataManager.diagnostics.isEmpty {
                let errorCount = kanataManager.diagnostics.filter {
                  $0.severity == .error || $0.severity == .critical
                }.count
                let warningCount = kanataManager.diagnostics.filter { $0.severity == .warning }
                  .count

                HStack(spacing: 12) {
                  if errorCount > 0 {
                    Label("\(errorCount)", systemImage: "exclamationmark.circle.fill")
                      .foregroundColor(.red)
                      .font(.caption)
                  }

                  if warningCount > 0 {
                    Label("\(warningCount)", systemImage: "exclamationmark.triangle.fill")
                      .foregroundColor(.orange)
                      .font(.caption)
                  }

                  if errorCount == 0 && warningCount == 0 {
                    Label("All good", systemImage: "checkmark.circle.fill")
                      .foregroundColor(.green)
                      .font(.caption)
                  }

                  Spacer()
                }
                .padding(.horizontal, 12)
              }
            }
          }

          Divider()

          // Advanced Section
          SettingsSection(title: "Advanced") {
            VStack(spacing: 10) {
              SettingsButton(
                title: "Emergency Stop",
                systemImage: "exclamationmark.triangle",
                style: .destructive,
                disabled: !kanataManager.isRunning,
                action: {
                  Task {
                    await kanataManager.stopKanata()
                  }
                }
              )
            }
          }

          // Issues section removed - diagnostics system provides better error reporting
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
      }
      .background(Color(NSColor.windowBackgroundColor))
    }
    .frame(width: 480, height: 520)
    .background(Color(NSColor.windowBackgroundColor))
    .onAppear {
      Task {
        await refreshStatus()
      }
    }
    .alert("Reset Configuration", isPresented: $showingResetConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Reset", role: .destructive) {
        resetToDefaultConfig()
      }
    } message: {
      Text(
        "This will reset your Kanata configuration to default with no custom mappings. All current key mappings will be lost. This action cannot be undone."
      )
    }
    .sheet(isPresented: $showingDiagnostics) {
      DiagnosticsView(kanataManager: kanataManager)
    }
  }

  private func openConfigInZed() {
    let configPath = kanataManager.configPath
    let process = Process()
    process.launchPath = "/usr/local/bin/zed"
    process.arguments = [configPath]

    do {
      try process.run()
    } catch {
      // If Zed isn't installed at the expected path, try the common Homebrew path
      let fallbackProcess = Process()
      fallbackProcess.launchPath = "/opt/homebrew/bin/zed"
      fallbackProcess.arguments = [configPath]

      do {
        try fallbackProcess.run()
      } catch {
        // If neither works, try using 'open' command with Zed
        let openProcess = Process()
        openProcess.launchPath = "/usr/bin/open"
        openProcess.arguments = ["-a", "Zed", configPath]

        do {
          try openProcess.run()
        } catch {
          AppLogger.shared.log("Failed to open config file in Zed: \(error)")
          // As a last resort, just open the file with default app
          NSWorkspace.shared.open(URL(fileURLWithPath: configPath))
        }
      }
    }
  }

  private func resetToDefaultConfig() {
    Task {
      do {
        try await kanataManager.resetToDefaultConfig()
        AppLogger.shared.log("✅ Successfully reset config to default")
      } catch {
        AppLogger.shared.log("❌ Failed to reset config: \(error)")
      }
    }
  }

  private func refreshStatus() async {
    await kanataManager.updateStatus()
    isDaemonRunning = kanataManager.isKarabinerDaemonRunning()

    // Actually check if Kanata process is running and functional
    actualKanataRunning = await checkKanataActuallyRunning()
  }

  private func checkKanataActuallyRunning() async -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-f", "kanata"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
      try task.run()
      task.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""
      let hasRunningProcess = !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

      // If process exists, verify it's actually functional by checking if it can validate config
      if hasRunningProcess {
        return await verifyKanataFunctional()
      }

      return false
    } catch {
      return false
    }
  }

  private func verifyKanataFunctional() async -> Bool {
    // Quick config validation test to ensure Kanata is functional
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/local/bin/kanata")
    task.arguments = ["--cfg", kanataManager.configPath, "--check"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
      try task.run()
      task.waitUntilExit()

      // If config validation succeeds, Kanata is functional
      return task.terminationStatus == 0
    } catch {
      return false
    }
  }

  private func startDaemon() {
    Task {
      isStartingDaemon = true
      let success = await kanataManager.startKarabinerDaemon()

      // Update status after attempting to start
      await refreshStatus()
      isStartingDaemon = false

      if success {
        AppLogger.shared.log("✅ Successfully started Karabiner daemon")
      } else {
        AppLogger.shared.log("❌ Failed to start Karabiner daemon")
      }
    }
  }

  private func openKeyPathLogs() {
    let logPath = "\(NSHomeDirectory())/Library/Logs/KeyPath/keypath-debug.log"

    // Try to open with Zed first
    let zedProcess = Process()
    zedProcess.launchPath = "/usr/local/bin/zed"
    zedProcess.arguments = [logPath]

    do {
      try zedProcess.run()
      AppLogger.shared.log("📋 Opened KeyPath logs in Zed")
      return
    } catch {
      // Try Homebrew path for Zed
      let homebrewZedProcess = Process()
      homebrewZedProcess.launchPath = "/opt/homebrew/bin/zed"
      homebrewZedProcess.arguments = [logPath]

      do {
        try homebrewZedProcess.run()
        AppLogger.shared.log("📋 Opened KeyPath logs in Zed (Homebrew)")
        return
      } catch {
        // Try using 'open' command with Zed
        let openZedProcess = Process()
        openZedProcess.launchPath = "/usr/bin/open"
        openZedProcess.arguments = ["-a", "Zed", logPath]

        do {
          try openZedProcess.run()
          AppLogger.shared.log("📋 Opened KeyPath logs in Zed (via open)")
          return
        } catch {
          // Fallback: Try to open with default text editor
          let fallbackProcess = Process()
          fallbackProcess.launchPath = "/usr/bin/open"
          fallbackProcess.arguments = ["-t", logPath]

          do {
            try fallbackProcess.run()
            AppLogger.shared.log("📋 Opened KeyPath logs in default text editor")
          } catch {
            // Last resort: Open containing folder
            let folderPath = "\(NSHomeDirectory())/Library/Logs/KeyPath"
            NSWorkspace.shared.open(URL(fileURLWithPath: folderPath))
            AppLogger.shared.log("📁 Opened KeyPath logs folder")
          }
        }
      }
    }
  }

  private func openKanataLogs() {
    let kanataLogPath = "\(NSHomeDirectory())/Library/Logs/KeyPath/kanata.log"

    // Check if Kanata log file exists
    if !FileManager.default.fileExists(atPath: kanataLogPath) {
      // Create empty log file so user can see the expected location
      try? "Kanata log file will appear here when Kanata runs.\n".write(
        toFile: kanataLogPath,
        atomically: true,
        encoding: .utf8
      )
    }

    // Try to open with Zed first
    let zedProcess = Process()
    zedProcess.launchPath = "/usr/local/bin/zed"
    zedProcess.arguments = [kanataLogPath]

    do {
      try zedProcess.run()
      AppLogger.shared.log("📋 Opened Kanata logs in Zed")
      return
    } catch {
      // Try Homebrew path for Zed
      let homebrewZedProcess = Process()
      homebrewZedProcess.launchPath = "/opt/homebrew/bin/zed"
      homebrewZedProcess.arguments = [kanataLogPath]

      do {
        try homebrewZedProcess.run()
        AppLogger.shared.log("📋 Opened Kanata logs in Zed (Homebrew)")
        return
      } catch {
        // Try using 'open' command with Zed
        let openZedProcess = Process()
        openZedProcess.launchPath = "/usr/bin/open"
        openZedProcess.arguments = ["-a", "Zed", kanataLogPath]

        do {
          try openZedProcess.run()
          AppLogger.shared.log("📋 Opened Kanata logs in Zed (via open)")
          return
        } catch {
          // Fallback: Try to open with default text editor
          let fallbackProcess = Process()
          fallbackProcess.launchPath = "/usr/bin/open"
          fallbackProcess.arguments = ["-t", kanataLogPath]

          do {
            try fallbackProcess.run()
            AppLogger.shared.log("📋 Opened Kanata logs in default text editor")
          } catch {
            // Last resort: Open containing folder
            let folderPath = "\(NSHomeDirectory())/Library/Logs/KeyPath"
            NSWorkspace.shared.open(URL(fileURLWithPath: folderPath))
            AppLogger.shared.log("📁 Opened KeyPath logs folder")
          }
        }
      }
    }
  }
}

// MARK: - Components

struct SettingsSection<Content: View>: View {
  let title: String
  let content: Content

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.primary)

      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct StatusRow: View {
  let label: String
  let status: String
  let isActive: Bool

  var body: some View {
    HStack {
      Text(label)
        .font(.system(size: 13))
        .foregroundColor(.primary)

      Spacer()

      HStack(spacing: 6) {
        Circle()
          .fill(isActive ? Color.green : Color.orange)
          .frame(width: 8, height: 8)

        Text(status)
          .font(.system(size: 13))
          .foregroundColor(.secondary)
      }
    }
    .padding(.vertical, 4)
  }
}

struct SettingsButton: View {
  let title: String
  let systemImage: String
  var style: ButtonStyle = .standard
  var disabled: Bool = false
  let action: () -> Void

  enum ButtonStyle {
    case standard, destructive
  }

  var body: some View {
    Button(action: action) {
      HStack {
        Image(systemName: systemImage)
          .font(.system(size: 14))
          .frame(width: 20)

        Text(title)
          .font(.system(size: 13))

        Spacer()
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(Color(NSColor.controlBackgroundColor))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
      )
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .opacity(disabled ? 0.5 : 1.0)
    .foregroundColor(style == .destructive ? .red : .primary)
  }
}

#Preview {
  SettingsView()
    .environmentObject(KanataManager())
}
