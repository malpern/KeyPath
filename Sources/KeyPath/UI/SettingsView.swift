import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var kanataManager: KanataManager
    @EnvironmentObject var simpleKanataManager: SimpleKanataManager
    @ObservedObject private var preferences = PreferencesService.shared
    @State private var showingResetConfirmation = false
    @State private var showingDiagnostics = false
    @State private var showingInstallationWizard = false
    @State private var showingTCPPortAlert = false
    @State private var tempTCPPort = ""
    // Timer removed - now handled by SimpleKanataManager centrally

    private var kanataServiceStatus: String {
        switch simpleKanataManager.currentState {
        case .running:
            "Running"
        case .starting:
            "Starting..."
        case .needsHelp:
            "Needs Help"
        case .stopped:
            "Stopped"
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
                .accessibilityIdentifier("settings-done-button")
                .accessibilityLabel("Close Settings")
                .accessibilityHint("Close the settings window")
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
                                title: "Restart Service",
                                systemImage: "arrow.clockwise.circle",
                                accessibilityId: "restart-service-button",
                                accessibilityHint: "Stop and restart the Kanata keyboard service",
                                action: {
                                    Task {
                                        AppLogger.shared.log("🔄 [SettingsView] Restart Service clicked")
                                        await simpleKanataManager.manualStop()
                                        try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
                                        await simpleKanataManager.manualStart()
                                    }
                                }
                            )

                            SettingsButton(
                                title: "Refresh Status",
                                systemImage: "arrow.clockwise",
                                accessibilityId: "refresh-status-button",
                                accessibilityHint: "Check the current status of the Kanata service",
                                action: {
                                    Task {
                                        AppLogger.shared.log("🔄 [SettingsView] Refresh Status clicked")
                                        await simpleKanataManager.forceRefreshStatus()
                                    }
                                }
                            )

                            SettingsButton(
                                title: "Run Installation Wizard",
                                systemImage: "wrench.and.screwdriver",
                                accessibilityId: "run-installation-wizard-button",
                                accessibilityHint: "Launch the installation wizard to configure KeyPath",
                                action: {
                                    AppLogger.shared.log("🎭 [SettingsView] Manual wizard trigger")
                                    showingInstallationWizard = true
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
                                accessibilityId: "edit-configuration-button",
                                accessibilityHint: "Open the Kanata configuration file in an editor",
                                action: {
                                    openConfigInZed()
                                }
                            )

                            SettingsButton(
                                title: "Reset to Default",
                                systemImage: "arrow.counterclockwise",
                                style: .destructive,
                                accessibilityId: "reset-to-default-button",
                                accessibilityHint: "Reset all keyboard mappings to default configuration",
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
                                accessibilityId: "show-diagnostics-button",
                                accessibilityHint:
                                "View detailed system diagnostics and troubleshooting information",
                                action: {
                                    showingDiagnostics = true
                                }
                            )

                            // Log access buttons
                            HStack(spacing: 10) {
                                SettingsButton(
                                    title: "KeyPath Logs",
                                    systemImage: "doc.text",
                                    accessibilityId: "keypath-logs-button",
                                    accessibilityHint: "Open KeyPath application log files",
                                    action: {
                                        openKeyPathLogs()
                                    }
                                )

                                SettingsButton(
                                    title: "Kanata Logs",
                                    systemImage: "terminal",
                                    accessibilityId: "kanata-logs-button",
                                    accessibilityHint: "Open Kanata service log files",
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

                                    if errorCount == 0, warningCount == 0 {
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

                    // TCP Server Configuration
                    SettingsSection(title: "TCP Server") {
                        VStack(spacing: 12) {
                            HStack {
                                Toggle("Enable TCP Server", isOn: $preferences.tcpServerEnabled)
                                    .help(
                                        "Enable TCP server for config validation. Required for live config checking.")

                                Spacer()
                            }

                            if preferences.tcpServerEnabled {
                                HStack {
                                    Text("Port:")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)

                                    Button("\(preferences.tcpServerPort)") {
                                        tempTCPPort = String(preferences.tcpServerPort)
                                        showingTCPPortAlert = true
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help("Click to change TCP port (1024-65535)")

                                    Spacer()

                                    Text("Status: \(getTCPServerStatus())")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }

                            Text("TCP server enables real-time config validation without restarting Kanata.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                    }

                    Divider()

                    // Startup Settings (LaunchAgent)
                    SettingsSection(title: "Startup") {
                        LaunchAgentSettingsView()
                    }

                    Divider()

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
            AppLogger.shared.log("🔍 [SettingsView] onAppear called")

            AppLogger.shared.log(
                "🔍 [SettingsView] Using shared SimpleKanataManager - state: \(simpleKanataManager.currentState.rawValue)"
            )
            AppLogger.shared.log(
                "🔍 [SettingsView] Using shared SimpleKanataManager - showWizard: \(simpleKanataManager.showWizard)"
            )

            // Check if wizard should be shown immediately
            if simpleKanataManager.showWizard {
                AppLogger.shared.log("🎭 [SettingsView] Triggering wizard from Settings - Kanata needs help")
                showingInstallationWizard = true
            }

            // Status monitoring now handled centrally by SimpleKanataManager
            // Just do an initial status refresh
            Task {
                await simpleKanataManager.forceRefreshStatus()
            }

            // Check TCP server status
            checkTCPServerStatus()
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
        .alert("Change TCP Port", isPresented: $showingTCPPortAlert) {
            TextField("Port (1024-65535)", text: $tempTCPPort)
                .textFieldStyle(.roundedBorder)

            Button("Cancel", role: .cancel) {
                tempTCPPort = ""
            }

            Button("Apply") {
                if let port = Int(tempTCPPort), preferences.isValidTCPPort(port) {
                    preferences.tcpServerPort = port
                    AppLogger.shared.log("🔧 [SettingsView] TCP port changed to: \(port)")

                    // Suggest service restart if Kanata is running
                    if simpleKanataManager.currentState == .running {
                        AppLogger.shared.log("💡 [SettingsView] Suggesting service restart for TCP port change")
                    }

                    // Refresh TCP status
                    checkTCPServerStatus()
                }
                tempTCPPort = ""
            }
        } message: {
            Text(
                "Enter a port number between 1024 and 65535. If Kanata is running, you'll need to restart the service for the change to take effect."
            )
        }
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsView(kanataManager: kanataManager)
        }
        .sheet(isPresented: $showingInstallationWizard) {
            InstallationWizardView()
                .onAppear {
                    AppLogger.shared.log("🔍 [SettingsView] Installation wizard sheet is being presented")
                }
                .onDisappear {
                    AppLogger.shared.log("🔍 [SettingsView] Installation wizard closed - triggering retry")
                    Task {
                        await simpleKanataManager.onWizardClosed()
                    }
                }
                .environmentObject(kanataManager)
        }
        .onDisappear {
            AppLogger.shared.log("🔍 [SettingsView] onDisappear - status monitoring handled centrally")
            // Status monitoring handled centrally - no cleanup needed
        }
        .onChange(of: simpleKanataManager.showWizard) { shouldShow in
            AppLogger.shared.log("🔍 [SettingsView] showWizard changed to: \(shouldShow)")
            AppLogger.shared.log(
                "🔍 [SettingsView] Current simpleKanataManager state: \(simpleKanataManager.currentState.rawValue)"
            )
            showingInstallationWizard = shouldShow
        }
        .onChange(of: preferences.tcpServerEnabled) { _ in
            // Refresh TCP status when enabled/disabled
            checkTCPServerStatus()
        }
        .onChange(of: simpleKanataManager.currentState) { _ in
            // Refresh TCP status when Kanata state changes
            checkTCPServerStatus()
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

    // Status monitoring functions removed - now handled centrally by SimpleKanataManager

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

    @State private var tcpServerStatus = "Unknown"

    private func getTCPServerStatus() -> String {
        if !preferences.tcpServerEnabled {
            return "Disabled"
        }

        return tcpServerStatus
    }

    private func checkTCPServerStatus() {
        Task {
            if preferences.tcpServerEnabled, simpleKanataManager.currentState == .running {
                let client = KanataTCPClient(port: preferences.tcpServerPort)
                let isAvailable = await client.checkServerStatus()

                await MainActor.run {
                    tcpServerStatus = isAvailable ? "Connected" : "Not Connected"
                }
            } else {
                await MainActor.run {
                    tcpServerStatus = "Not Running"
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
    var accessibilityId: String?
    var accessibilityHint: String?
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
        .accessibilityIdentifier(
            accessibilityId ?? title.lowercased().replacingOccurrences(of: " ", with: "-")
        )
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint ?? "Tap to \(title.lowercased())")
    }
}

#Preview {
    SettingsView()
        .environmentObject(KanataManager())
}
