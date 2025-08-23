import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var kanataManager: KanataManager
    @EnvironmentObject var simpleKanataManager: SimpleKanataManager
    @Environment(\.preferencesService) private var preferences: PreferencesService
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
        settingsContent
    }
    
    private var settingsContent: some View {
        VStack(spacing: 0) {
            headerView
            mainContentView
        }
        .frame(width: 480, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            AppLogger.shared.log("🔍 [SettingsView] onAppear called")
            AppLogger.shared.log("🔍 [SettingsView] Using shared SimpleKanataManager - state: \(simpleKanataManager.currentState.rawValue)")
            AppLogger.shared.log("🔍 [SettingsView] Using shared SimpleKanataManager - showWizard: \(simpleKanataManager.showWizard)")

            if simpleKanataManager.showWizard {
                AppLogger.shared.log("🎭 [SettingsView] Triggering wizard from Settings - Kanata needs help")
                showingInstallationWizard = true
            }

            Task {
                await simpleKanataManager.forceRefreshStatus()
            }
        }
        .alert("Enter TCP Port", isPresented: $showingTCPPortAlert) {
            TextField("Port (1024-65535)", text: $tempTCPPort)

            Button("Cancel") {
                tempTCPPort = ""
            }

            Button("Apply") {
                if let port = Int(tempTCPPort), preferences.isValidTCPPort(port) {
                    preferences.tcpServerPort = port
                    AppLogger.shared.log("🔧 [SettingsView] TCP port changed to: \(port)")

                    if simpleKanataManager.currentState == .running {
                        AppLogger.shared.log("💡 [SettingsView] Suggesting service restart for TCP port change")
                    }

                    checkTCPServerStatus()
                }
                tempTCPPort = ""
            }
        } message: {
            Text("Enter a port number between 1024 and 65535. If Kanata is running, you'll need to restart the service for the change to take effect.")
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
        }
        .onChange(of: simpleKanataManager.showWizard) { shouldShow in
            AppLogger.shared.log("🔍 [SettingsView] showWizard changed to: \(shouldShow)")
            AppLogger.shared.log("🔍 [SettingsView] Current simpleKanataManager state: \(simpleKanataManager.currentState.rawValue)")
            showingInstallationWizard = shouldShow
        }
        .onChange(of: preferences.tcpServerEnabled) { _ in
            checkTCPServerStatus()
        }
        .onChange(of: simpleKanataManager.currentState) { _ in
            checkTCPServerStatus()
        }
        .alert("Reset Configuration?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetToDefaultConfig()
            }
        } message: {
            Text("This will reset your configuration to the default mapping (Caps Lock → Escape). Your current configuration will be lost.")
        }
    }
    
    private var headerView: some View {
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
    }
    
    private var mainContentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                statusSection
                Divider()
                serviceControlSection
                Divider()
                configurationSection
                Divider()
                diagnosticsSection
                Divider()
                tcpServerSection
                Divider()
                developerToolsSection
                Divider()
                startupSection
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var statusSection: some View {
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
    }
    
    private var serviceControlSection: some View {
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
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
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
                    title: "Stop Kanata Service",
                    systemImage: "stop.circle",
                    style: .destructive,
                    disabled: simpleKanataManager.currentState == .stopped,
                    accessibilityId: "stop-kanata-service-button", 
                    accessibilityHint: "Completely stop the Kanata service and prevent auto-reloading",
                    action: {
                        Task {
                            AppLogger.shared.log("🛑 [SettingsView] Stop Kanata Service clicked")
                            await stopKanataService()
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
    }
    
    private var configurationSection: some View {
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
    }
    
    private var diagnosticsSection: some View {
        SettingsSection(title: "Diagnostics") {
            VStack(spacing: 10) {
                SettingsButton(
                    title: "Show Diagnostics",
                    systemImage: "stethoscope",
                    accessibilityId: "show-diagnostics-button",
                    accessibilityHint: "View detailed system diagnostics and troubleshooting information",
                    action: {
                        showingDiagnostics = true
                    }
                )

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

                diagnosticSummaryView
            }
        }
    }
    
    private var tcpServerSection: some View {
        SettingsSection(title: "TCP Server") {
            VStack(spacing: 12) {
                HStack {
                    Toggle(
                        "Enable TCP Server",
                        isOn: Binding(
                            get: { preferences.tcpServerEnabled },
                            set: { preferences.tcpServerEnabled = $0 }
                        )
                    )
                    .help("Enable TCP server for config validation. Required for live config checking.")

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
    }
    
    private var developerToolsSection: some View {
        SettingsSection(title: "Developer Tools") {
            VStack(spacing: 10) {
                SettingsButton(
                    title: "Reset (Dev Only)",
                    systemImage: "arrow.clockwise.circle.fill",
                    accessibilityId: "reset-dev-button",
                    accessibilityHint: "Stop daemon, clear logs, restart - does not touch TCC permissions",
                    action: {
                        Task {
                            await performDevReset()
                        }
                    }
                )
                
                SettingsButton(
                    title: "Show Enhanced Diagnostics",
                    systemImage: "info.circle",
                    accessibilityId: "enhanced-diagnostics-button",
                    accessibilityHint: "View enhanced diagnostics with system status, signatures, and TCC probes",
                    action: {
                        showingDiagnostics = true
                    }
                )
            }
        }
    }
    
    private var startupSection: some View {
        SettingsSection(title: "Startup") {
            LaunchAgentSettingsView()
        }
    }
    
    
    /*
    private var oldFullSettingsContent: some View {
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
                                title: "Stop Kanata Service",
                                systemImage: "stop.circle",
                                style: .destructive,
                                disabled: simpleKanataManager.currentState == .stopped,
                                accessibilityId: "stop-kanata-service-button", 
                                accessibilityHint: "Completely stop the Kanata service and prevent auto-reloading",
                                action: {
                                    Task {
                                        AppLogger.shared.log("🛑 [SettingsView] Stop Kanata Service clicked")
                                        await stopKanataService()
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
                            diagnosticSummaryView
                        }
                    }

                    Divider()

                    // TCP Server Configuration
                    SettingsSection(title: "TCP Server") {
                        VStack(spacing: 12) {
                            HStack {
                                Toggle(
                                    "Enable TCP Server",
                                    isOn: Binding(
                                        get: { preferences.tcpServerEnabled },
                                        set: { preferences.tcpServerEnabled = $0 }
                                    )
                                )
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

                    // Developer Tools Section
                    SettingsSection(title: "Developer Tools") {
                        VStack(spacing: 10) {
                            SettingsButton(
                                title: "Reset (Dev Only)",
                                systemImage: "arrow.clockwise.circle.fill",
                                style: .bordered,
                                accessibilityId: "reset-dev-button",
                                accessibilityHint: "Stop daemon, clear logs, restart - does not touch TCC permissions",
                                action: {
                                    Task {
                                        await performDevReset()
                                    }
                                }
                            )
                            
                            SettingsButton(
                                title: "Show Enhanced Diagnostics",
                                systemImage: "info.circle",
                                accessibilityId: "enhanced-diagnostics-button",
                                accessibilityHint: "View enhanced diagnostics with system status, signatures, and TCC probes",
                                action: {
                                    showingDiagnostics = true
                                }
                            )
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
    */
    
    // MARK: - Computed Properties
    
    private var diagnosticSummaryView: some View {
        Group {
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
            } else {
                EmptyView()
            }
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
    
    /// Completely stop the Kanata service and prevent auto-reloading
    private func stopKanataService() async {
        AppLogger.shared.log("🛑 [SettingsView] ========== STOPPING KANATA SERVICE ==========")
        
        do {
            // Step 1: Use SimpleKanataManager to stop gracefully first
            AppLogger.shared.log("🛑 [SettingsView] Step 1: Stopping via SimpleKanataManager")
            await simpleKanataManager.manualStop()
            
            // Step 2: Force kill the launchd service
            AppLogger.shared.log("🛑 [SettingsView] Step 2: Force killing launchd service")
            let killProcess = Process()
            killProcess.launchPath = "/usr/bin/sudo"
            killProcess.arguments = ["launchctl", "kill", "TERM", "system/com.keypath.kanata"]
            
            try killProcess.run()
            killProcess.waitUntilExit()
            
            if killProcess.terminationStatus == 0 {
                AppLogger.shared.log("✅ [SettingsView] Successfully killed launchd service")
            } else {
                AppLogger.shared.log("⚠️ [SettingsView] launchctl kill returned status: \(killProcess.terminationStatus)")
            }
            
            // Step 3: Kill any remaining kanata processes
            AppLogger.shared.log("🛑 [SettingsView] Step 3: Killing any remaining kanata processes")
            let pkillProcess = Process()
            pkillProcess.launchPath = "/usr/bin/sudo"
            pkillProcess.arguments = ["pkill", "-f", "kanata"]
            
            try pkillProcess.run()
            pkillProcess.waitUntilExit()
            
            AppLogger.shared.log("✅ [SettingsView] Killed remaining kanata processes (if any)")
            
            // Step 4: Unload the service to prevent auto-reloading
            AppLogger.shared.log("🛑 [SettingsView] Step 4: Unloading service to prevent auto-reload")
            let unloadProcess = Process()
            unloadProcess.launchPath = "/usr/bin/sudo"
            unloadProcess.arguments = ["launchctl", "unload", "/Library/LaunchDaemons/com.keypath.kanata.plist"]
            
            try unloadProcess.run()
            unloadProcess.waitUntilExit()
            
            if unloadProcess.terminationStatus == 0 {
                AppLogger.shared.log("✅ [SettingsView] Successfully unloaded service")
            } else {
                AppLogger.shared.log("⚠️ [SettingsView] Service may not have been loaded (status: \(unloadProcess.terminationStatus))")
            }
            
            AppLogger.shared.log("🛑 [SettingsView] ========== KANATA SERVICE STOPPED ==========")
            
            // Refresh status to reflect changes
            await simpleKanataManager.forceRefreshStatus()
            
        } catch {
            AppLogger.shared.log("❌ [SettingsView] Error stopping Kanata service: \(error)")
        }
    }
    
    // MARK: - Developer Reset Function
    
    private func performDevReset() async {
        AppLogger.shared.log("🔧 [SettingsView] ========== DEV RESET STARTED ==========")
        
        // Step 1: Stop the daemon
        AppLogger.shared.log("🔧 [SettingsView] Step 1: Stopping daemon")
        do {
            let stopProcess = Process()
            stopProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            stopProcess.arguments = ["launchctl", "bootout", "system/com.keypath.kanata"]
            
            try stopProcess.run()
            stopProcess.waitUntilExit()
            
            AppLogger.shared.log("🔧 [SettingsView] Daemon stopped with status: \(stopProcess.terminationStatus)")
        } catch {
            AppLogger.shared.log("⚠️ [SettingsView] Error stopping daemon: \(error)")
        }
        
        // Step 2: Clear logs (does not touch TCC)
        AppLogger.shared.log("🔧 [SettingsView] Step 2: Clearing logs")
        do {
            let clearProcess = Process()
            clearProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            clearProcess.arguments = ["sh", "-c", "echo '' > /var/log/kanata.log"]
            
            try clearProcess.run()
            clearProcess.waitUntilExit()
            
            AppLogger.shared.log("🔧 [SettingsView] Logs cleared with status: \(clearProcess.terminationStatus)")
        } catch {
            AppLogger.shared.log("⚠️ [SettingsView] Error clearing logs: \(error)")
        }
        
        // Step 3: Wait 2 seconds
        AppLogger.shared.log("🔧 [SettingsView] Step 3: Waiting 2 seconds...")
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Step 4: Restart via SimpleKanataManager
        AppLogger.shared.log("🔧 [SettingsView] Step 4: Restarting via SimpleKanataManager")
        await simpleKanataManager.manualStart()
        
        // Step 5: Refresh status
        AppLogger.shared.log("🔧 [SettingsView] Step 5: Refreshing status")
        await simpleKanataManager.forceRefreshStatus()
        
        AppLogger.shared.log("🔧 [SettingsView] ========== DEV RESET COMPLETED ==========")
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
