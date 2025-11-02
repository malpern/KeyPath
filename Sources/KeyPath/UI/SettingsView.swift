import ServiceManagement
import SwiftUI

// MARK: - File Navigation (1,352 lines)

//
// This file is organized into clear sections. Use CMD+F to jump to:
//
// Main Sections:
//   - statusSection           Service and installation status
//   - serviceControlSection   Start/stop/restart buttons, wizard trigger
//   - configurationSection    Edit, reset, backup config
//   - diagnosticsSection      Enhanced diagnostics
//   - notificationsSection    Notification preferences
//   - communicationSection    TCP settings and configuration
//   - developerToolsSection   Dev reset and diagnostics
//   - startupSection          Launch agent settings
//
// Helper Methods:
//   - stopKanataService()     Stop daemon logic
//   - openConfigInZed()       Open config in editor
//   - performDevReset()       Developer reset flow
//   - performFullReset()      Complete system reset

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var kanataManager: KanataViewModel // Phase 4: MVVM
    @Environment(\.preferencesService) private var preferences: PreferencesService
    @State private var showingResetConfirmation = false
    @State private var showingDevResetConfirmation = false
    @State private var showingDiagnostics = false
    @State private var showingInstallationWizard = false
    @State private var showingTCPPortAlert = false
    @State private var tempTCPPort = ""
    @State private var showingTCPTokenAlert = false
    @State private var tempTCPToken = ""
    @State private var showingTCPTimeoutAlert = false
    @State private var tempTCPTimeout = ""
    // Timer removed - now handled by SimpleKanataManager centrally

    // Minimal Helper tools (installation via Wizard). Provides: Test XPC, Diagnostics, Uninstall, Logs.
    @State private var helperInstalled: Bool = HelperManager.shared.isHelperInstalled()
    @State private var helperVersion: String?
    @State private var helperInProgress = false
    @State private var helperMessage: String?
    @State private var showingHelperDiagnostics = false
    @State private var helperDiagnosticsText: String = ""
    @State private var showingHelperUninstallConfirm = false
    @State private var showingHelperLogs = false
    @State private var helperLogLines: [String] = []
    @State private var disableGrabberInProgress = false

    // Toasts
    @State private var settingsToastManager = WizardToastManager()

    private var kanataServiceStatus: String {
        switch kanataManager.currentState {
        case .running:
            "Running"
        case .starting:
            "Starting..."
        case .needsHelp:
            "Needs Help"
        case .stopped:
            "Stopped"
        case .pausedLowPower:
            if let level = formattedBatteryLevel(kanataManager.batteryLevel) {
                return "Paused (Low Power, \(level))"
            }
            return "Paused (Low Power)"
        }
    }

    private func formattedBatteryLevel(_ level: Double?) -> String? {
        guard let level else { return nil }
        let percent = Int((level * 100).rounded())
        return "\(max(0, min(100, percent)))%"
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
        .withToasts(settingsToastManager)
        .onAppear {
            AppLogger.shared.log("🔍 [SettingsView] onAppear called")
            AppLogger.shared.log("🔍 [SettingsView] Using shared SimpleKanataManager - state: \(kanataManager.currentState.rawValue)")
            AppLogger.shared.log("🔍 [SettingsView] Using shared SimpleKanataManager - showWizard: \(kanataManager.showWizard)")

            if kanataManager.showWizard {
                AppLogger.shared.log("🎭 [SettingsView] Triggering wizard from Settings - Kanata needs help")
                showingInstallationWizard = true
            }

            Task {
                await kanataManager.forceRefreshStatus()
            }
        }
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsView(kanataManager: kanataManager)
        }
        .sheet(isPresented: $showingInstallationWizard) {
            // If helper isn’t installed, start wizard on Helper page
            let startPage: WizardPage? = HelperManager.shared.isHelperInstalled() ? nil : .helper
            InstallationWizardView(initialPage: startPage)
                .onAppear {
                    AppLogger.shared.log("🔍 [SettingsView] Installation wizard sheet is being presented")
                }
                .onDisappear {
                    AppLogger.shared.log("🔍 [SettingsView] Installation wizard closed - triggering retry")
                    Task {
                        await kanataManager.onWizardClosed()
                    }
                }
                .environmentObject(kanataManager)
        }
        .onDisappear {
            AppLogger.shared.log("🔍 [SettingsView] onDisappear - status monitoring handled centrally")
        }
        .onChange(of: kanataManager.showWizard) { _, shouldShow in
            AppLogger.shared.log("🔍 [SettingsView] showWizard changed to: \(shouldShow)")
            AppLogger.shared.log("🔍 [SettingsView] Current kanataManager state: \(kanataManager.currentState.rawValue)")
            showingInstallationWizard = shouldShow
        }
        .onChange(of: preferences.communicationProtocol) { _, _ in
            // Protocol changed, no specific action needed as it will be picked up on next operation
        }
        .onChange(of: kanataManager.currentState) { _, _ in
            checkTCPServerStatus()
        }
        .alert("Reset Configuration?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetToDefaultConfig()
            }
        } message: {
            Text("This will reset your configuration to the default mapping (Caps Lock → Escape). Your current configuration will be lost.")
        }
        .alert("Developer Reset", isPresented: $showingDevResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Task {
                    await performDevReset()
                }
            }
        } message: {
            Text("""
            This will perform a complete developer reset:

            • Stop the Kanata daemon service
            • Clear all system logs (/var/log/kanata.log)
            • Wait 2 seconds for cleanup
            • Restart the service via KanataManager
            • Refresh system status

            TCC permissions will NOT be affected.
            """)
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
        .appGlassHeader()
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
                helperManagementSection
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
                isActive: kanataManager.currentState == .running
            )

            StatusRow(
                label: "Installation",
                status: kanataManager.isCompletelyInstalled() ? "Installed" : "Not Installed",
                isActive: kanataManager.isCompletelyInstalled()
            )

            if kanataManager.isLowPowerPaused {
                Text("KeyPath paused automatically due to low battery. It will resume when power is above 5%.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("low-power-paused-note")
            }
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
                            await kanataManager.manualStop()
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            await kanataManager.manualStart()
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
                            await kanataManager.forceRefreshStatus()
                        }
                    }
                )

                SettingsButton(
                    title: "Stop Kanata Service",
                    systemImage: "stop.circle",
                    style: .destructive,
                    disabled: kanataManager.currentState == .stopped,
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
                    
                    SettingsButton(
                        title: "Disable Karabiner Grabber",
                        systemImage: "nosign",
                        disabled: disableGrabberInProgress,
                        accessibilityId: "disable-karabiner-grabber-button",
                        accessibilityHint: "Use the privileged helper to disable Karabiner's grabber services",
                        action: {
                            Task { @MainActor in
                                disableGrabberInProgress = true
                                do {
                                    try await PrivilegedOperationsCoordinator.shared.disableKarabinerGrabber()
                                    settingsToastManager.showSuccess("Disabled Karabiner grabber via helper")
                                } catch {
                                    settingsToastManager.showError("Failed to disable grabber: \(error.localizedDescription)")
                                }
                                disableGrabberInProgress = false
                            }
                        }
                    )
                }

                diagnosticSummaryView
            }
        }
    }

    private var helperManagementSection: some View {
        SettingsSection(title: "Privileged Helper") {
            VStack(spacing: 10) {
                // Status row
                HStack {
                    Circle()
                        .fill(helperInstalled ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                    Text("Status:")
                        .foregroundColor(.secondary)
                    Text(helperInstalled ? (helperVersion.map { "Installed (v\($0))" } ?? "Installed") : "Not Installed")
                        .fontWeight(.medium)
                    Spacer()
                }

                // Actions
                HStack(spacing: 10) {
                    SettingsButton(
                        title: "Test XPC",
                        systemImage: "bolt.horizontal.circle",
                        disabled: helperInProgress,
                        accessibilityId: "helper-test-xpc-button",
                        accessibilityHint: "Attempt to contact the helper and read its version",
                        action: { Task { await testHelperXPC() } }
                    )

                    SettingsButton(
                        title: "Bless Diagnostics",
                        systemImage: "text.magnifyingglass",
                        disabled: helperInProgress,
                        accessibilityId: "helper-diagnostics-button",
                        accessibilityHint: "Show SMAppService/launchd diagnostics for the helper",
                        action: { runHelperDiagnostics() }
                    )

                    SettingsButton(
                        title: "Helper Logs…",
                        systemImage: "doc.text.magnifyingglass",
                        disabled: helperInProgress,
                        accessibilityId: "helper-logs-button",
                        accessibilityHint: "Show recent KeyPathHelper logs",
                        action: { Task { await showHelperLogs() } }
                    )

                    SettingsButton(
                        title: "Uninstall Helper",
                        systemImage: "trash",
                        style: .destructive,
                        disabled: helperInProgress || !helperInstalled,
                        accessibilityId: "helper-uninstall-button",
                        accessibilityHint: "Unregister the privileged helper",
                        action: { showingHelperUninstallConfirm = true }
                    )
                }

                // Optional: route installs to the Wizard
                if !helperInstalled {
                    SettingsButton(
                        title: "Install via Wizard",
                        systemImage: "wrench.and.screwdriver",
                        accessibilityId: "helper-install-via-wizard-button",
                        accessibilityHint: "Open the setup wizard at the Helper step",
                        action: { showingInstallationWizard = true }
                    )
                }

                if let msg = helperMessage, !msg.isEmpty {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }
            .onAppear {
                Task { await refreshHelperStatus() }
            }
            .sheet(isPresented: $showingHelperDiagnostics) {
                ScrollView {
                    Text(helperDiagnosticsText.isEmpty ? "No diagnostics available" : helperDiagnosticsText)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(minWidth: 520, minHeight: 360, alignment: .topLeading)
                }
            }
            .sheet(isPresented: $showingHelperLogs) {
                HelperLogsView(lines: helperLogLines) { showingHelperLogs = false }
            }
            .alert("Uninstall Privileged Helper?", isPresented: $showingHelperUninstallConfirm) {
                Button("Cancel", role: .cancel) { showingHelperUninstallConfirm = false }
                Button("Uninstall", role: .destructive) {
                    Task { await uninstallHelper() }
                }
            } message: {
                Text("This will unregister the helper from the system. You can reinstall it later via the Setup Wizard.")
            }
        }
    }

    private var tcpSettingsView: some View {
        VStack(spacing: 12) {
            HStack {
                Text("TCP Server: Always Enabled")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .help("TCP server is always enabled for config operations (no authentication required)")

            // TCP Port setting
            HStack {
                Text("TCP Port:")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                Text("\(preferences.tcpServerPort)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()
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
                        showingDevResetConfirmation = true
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

    // MARK: - Helper Actions

    private func refreshHelperStatus() async {
        await MainActor.run {
            helperInstalled = HelperManager.shared.isHelperInstalled()
        }
        let v = await HelperManager.shared.getHelperVersion()
        await MainActor.run { helperVersion = v }
    }

    func testHelperXPC() async {
        await MainActor.run { helperInProgress = true; helperMessage = nil }
        defer { Task { await MainActor.run { helperInProgress = false } } }
        let v = await HelperManager.shared.getHelperVersion()
        await MainActor.run {
            if let v {
                helperMessage = "XPC OK (v\(v))"
                settingsToastManager.showSuccess("Helper XPC OK (v\(v))")
            } else {
                helperMessage = "XPC failed (helper unreachable)"
                settingsToastManager.showError("Helper XPC failed")
            }
        }
        await refreshHelperStatus()
    }

    private func runHelperDiagnostics() {
        helperDiagnosticsText = HelperManager.shared.runBlessDiagnostics()
        showingHelperDiagnostics = true
        settingsToastManager.showInfo("Generated helper diagnostics")
    }

    private func uninstallHelper() async {
        await MainActor.run { helperInProgress = true; helperMessage = nil }
        defer { Task { await MainActor.run { helperInProgress = false; showingHelperUninstallConfirm = false } } }
        do {
            try await HelperManager.shared.uninstallHelper()
            await MainActor.run {
                helperMessage = "Helper uninstalled"
                settingsToastManager.showSuccess("Helper uninstalled")
            }
            await refreshHelperStatus()
        } catch {
            await MainActor.run {
                helperMessage = "Uninstall failed: \(error.localizedDescription)"
                settingsToastManager.showError("Uninstall failed")
            }
        }
    }

    private func showHelperLogs() async {
        await MainActor.run { helperInProgress = true }
        defer { Task { await MainActor.run { helperInProgress = false } } }
        // Fetch last 50 messages in a 10 minute window
        let lines = HelperManager.shared.lastHelperLogs(count: 50, windowSeconds: 600)
        await MainActor.run {
            helperLogLines = lines
            showingHelperLogs = true
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
                             isActive: kanataManager.currentState == .running
                         )

                         StatusRow(
                             label: "Installation",
                             status: kanataManager.isCompletelyInstalled() ? "Installed" : "Not Installed",
                             isActive: kanataManager.isCompletelyInstalled()
                         )

                         if kanataManager.isLowPowerPaused {
                             Text("KeyPath paused automatically due to low battery. It will resume when power is above 5%.")
                                 .font(.footnote)
                                 .foregroundColor(.secondary)
                                 .accessibilityIdentifier("low-power-paused-note")
                         }
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
                                         await kanataManager.manualStop()
                                         try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
                                         await kanataManager.manualStart()
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
                                         await kanataManager.forceRefreshStatus()
                                     }
                                 }
                             )

                             SettingsButton(
                                 title: "Stop Kanata Service",
                                 systemImage: "stop.circle",
                                 style: .destructive,
                                 disabled: kanataManager.currentState == .stopped,
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
                                     showingDevResetConfirmation = true
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
                 "🔍 [SettingsView] Using shared SimpleKanataManager - state: \(kanataManager.currentState.rawValue)"
             )
             AppLogger.shared.log(
                 "🔍 [SettingsView] Using shared SimpleKanataManager - showWizard: \(kanataManager.showWizard)"
             )

             // Check if wizard should be shown immediately
             if kanataManager.showWizard {
                 AppLogger.shared.log("🎭 [SettingsView] Triggering wizard from Settings - Kanata needs help")
                 showingInstallationWizard = true
             }

             // Status monitoring now handled centrally by SimpleKanataManager
             // Just do an initial status refresh
             Task {
                 await kanataManager.forceRefreshStatus()
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
                     if kanataManager.currentState == .running {
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
                         await kanataManager.onWizardClosed()
                     }
                 }
                 .environmentObject(kanataManager)
         }
         .onDisappear {
             AppLogger.shared.log("🔍 [SettingsView] onDisappear - status monitoring handled centrally")
             // Status monitoring handled centrally - no cleanup needed
         }
         .onChange(of: kanataManager.showWizard) { shouldShow in
             AppLogger.shared.log("🔍 [SettingsView] showWizard changed to: \(shouldShow)")
             AppLogger.shared.log(
                 "🔍 [SettingsView] Current kanataManager state: \(kanataManager.currentState.rawValue)"
             )
             showingInstallationWizard = shouldShow
         }
         .onChange(of: kanataManager.currentState) { _ in
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
                            .accessibilityLabel("\(errorCount) error\(errorCount == 1 ? "" : "s")")
                            .accessibilityHint("Number of critical errors or errors in diagnostics")
                    }

                    if warningCount > 0 {
                        Label("\(warningCount)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                            .accessibilityLabel("\(warningCount) warning\(warningCount == 1 ? "" : "s")")
                            .accessibilityHint("Number of warnings in diagnostics")
                    }

                    if errorCount == 0, warningCount == 0 {
                        Label("All good", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                            .accessibilityLabel("All diagnostics passed")
                            .accessibilityHint("No errors or warnings found in system diagnostics")
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
        // Create backup before opening for external editing
        if kanataManager.createPreEditBackup() {
            AppLogger.shared.log("✅ [SettingsView] Created backup before opening config for editing")
        } else {
            AppLogger.shared.log("⚠️ [SettingsView] Failed to create backup before editing")
        }

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

                // Show success toast
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ShowUserFeedback"),
                        object: nil,
                        userInfo: ["message": "Configuration reset to default (Caps Lock → Escape)"]
                    )
                }
            } catch {
                AppLogger.shared.log("❌ Failed to reset config: \(error)")

                // Show error toast
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ShowUserFeedback"),
                        object: nil,
                        userInfo: ["message": "❌ Failed to reset configuration: \(error.localizedDescription)"]
                    )
                }
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

    // (Helper management moved to the Wizard; no helper code remains here)

    // MARK: - TCP Server Status

    @State private var tcpServerStatus = "Unknown"

    private func getTCPServerStatus() -> String {
        // TCP server is always enabled in TCP-only mode
        tcpServerStatus
    }

    private func checkTCPServerStatus() {
        Task {
            if kanataManager.currentState == .running {
                let port = 37001 // TCP port (kanata default)
                let client = KanataTCPClient(port: port)
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
            await kanataManager.manualStop()

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
            await kanataManager.forceRefreshStatus()

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
        await kanataManager.manualStart()

        // Step 5: Refresh status
        AppLogger.shared.log("🔧 [SettingsView] Step 5: Refreshing status")
        await kanataManager.forceRefreshStatus()

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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlassCard()
        .padding(.vertical, 4)
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
                    .accessibilityHidden(true)

                Text(status)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(status)")
        .accessibilityValue(isActive ? "Active" : "Inactive")
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
    let manager = KanataManager()
    let viewModel = KanataViewModel(manager: manager)
    SettingsView()
        .environmentObject(viewModel)
}
