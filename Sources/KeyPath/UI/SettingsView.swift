import AppKit
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var kanataManager: KanataViewModel

    @State private var showingInstallationWizard = false
    @State private var showSetupBanner = false
    @State private var permissionSnapshot: PermissionOracle.Snapshot?
    @State private var duplicateAppCopies: [String] = []
    @State private var settingsToastManager = WizardToastManager()
    @State private var showingPermissionAlert = false

    // Service management state
    @State private var activeMethod: ServiceMethod = .unknown
    @State private var isMigrating = false

    enum ServiceMethod {
        case smappservice
        case launchctl
        case unknown
    }

    private var shouldShowStartup: Bool {
        LaunchAgentManager.isInstalled() || LaunchAgentManager.isLoaded()
    }

    private var isServiceRunning: Bool {
        kanataManager.currentState == .running
    }

    private var isSystemHealthy: Bool {
        kanataManager.currentState == .running && (permissionSnapshot?.isSystemReady ?? false)
    }

    private var systemHealthMessage: String {
        if kanataManager.currentState != .running {
            kanataServiceStatus
        } else if !(permissionSnapshot?.isSystemReady ?? false) {
            "Permissions Required"
        } else {
            "Everything's Working"
        }
    }

    private var kanataServiceStatus: String {
        switch kanataManager.currentState {
        case .running:
            "Service Running"
        case .starting:
            "Service Starting"
        case .needsHelp:
            "Attention Needed"
        case .stopped:
            "Service Stopped"
        case .pausedLowPower:
            "Paused (Low Power)"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if FeatureFlags.allowOptionalWizard, showSetupBanner {
                    SetupBanner {
                        showingInstallationWizard = true
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }

                // System Status Hero Section
                HStack(alignment: .top, spacing: 40) {
                    // Large status indicator with centered toggle
                    VStack(spacing: 16) {
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(isSystemHealthy ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                    .frame(width: 80, height: 80)

                                Image(systemName: isSystemHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(isSystemHealthy ? .green : .orange)
                            }

                            VStack(spacing: 4) {
                                Text(systemHealthMessage)
                                    .font(.title3.weight(.semibold))
                                    .multilineTextAlignment(.center)

                                if kanataManager.isLowPowerPaused {
                                    Text("Low Battery Pause")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }

                                Button(action: {
                                    NotificationCenter.default.post(name: .openSettingsRules, object: nil)
                                }) {
                                    Text("\(kanataManager.keyMappings.count) active rule\(kanataManager.keyMappings.count == 1 ? "" : "s")")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Centered toggle
                        HStack(spacing: 12) {
                            Toggle("", isOn: Binding(
                                get: { isServiceRunning },
                                set: { newValue in
                                    Task {
                                        if newValue {
                                            await kanataManager.manualStart()
                                            await MainActor.run {
                                                settingsToastManager.showSuccess("KeyPath activated")
                                            }
                                        } else {
                                            await kanataManager.manualStop()
                                            await MainActor.run {
                                                settingsToastManager.showInfo("KeyPath deactivated")
                                            }
                                        }
                                    }
                                }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.large)

                            Text(isServiceRunning ? "ON" : "OFF")
                                .font(.body.weight(.medium))
                                .foregroundColor(isServiceRunning ? .green : .secondary)
                        }
                    }
                    .frame(minWidth: 220)

                    // Permissions grid
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Permissions")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            PermissionStatusRow(
                                title: "KeyPath Accessibility",
                                icon: "lock.shield",
                                granted: permissionSnapshot?.keyPath.accessibility.isReady
                            )

                            PermissionStatusRow(
                                title: "KeyPath Input Monitoring",
                                icon: "keyboard",
                                granted: permissionSnapshot?.keyPath.inputMonitoring.isReady
                            )

                            PermissionStatusRow(
                                title: "Kanata Accessibility",
                                icon: "lock.shield",
                                granted: permissionSnapshot?.kanata.accessibility.isReady
                            )

                            PermissionStatusRow(
                                title: "Kanata Input Monitoring",
                                icon: "keyboard",
                                granted: permissionSnapshot?.kanata.inputMonitoring.isReady
                            )
                        }

                        // Wizard button
                        if let snapshot = permissionSnapshot {
                            if snapshot.isSystemReady {
                                Button(action: { showingInstallationWizard = true }) {
                                    Label("Install wizard…", systemImage: "wand.and.stars.inverse")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else {
                                Button(action: { showingPermissionAlert = true }) {
                                    Label("Fix it…", systemImage: "wand.and.stars")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)

                // Service Management - only show if there's an issue
                if activeMethod != .smappservice {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Service Management")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        serviceManagementSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }

                // Recording Settings and Logs
                HStack(alignment: .top, spacing: 40) {
                    // Left: Log Files (aligned under health indicator)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Logs")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        HStack(spacing: 30) {
                            // KeyPath Log
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.blue)

                                Text("KeyPath log")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Button("Open") {
                                    openLogFile(NSHomeDirectory() + "/Library/Logs/KeyPath/keypath-debug.log")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            // Kanata Log
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.green)

                                Text("Kanata log")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Button("Open") {
                                    openLogFile("/var/log/kanata.log")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    .frame(minWidth: 220)

                    // Right: Recording Settings (aligned under permissions)
                    VStack(alignment: .leading, spacing: 20) {
                        // Capture Mode
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Capture Mode")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            Picker("", selection: Binding(
                                get: { PreferencesService.shared.isSequenceMode },
                                set: { PreferencesService.shared.isSequenceMode = $0 }
                            )) {
                                Text("Sequences - Keys one after another").tag(true)
                                Text("Combos - Keys together").tag(false)
                            }
                            .pickerStyle(.radioGroup)
                            .labelsHidden()
                        }

                        // Recording Behavior
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recording Behavior")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            Picker("", selection: Binding(
                                get: { PreferencesService.shared.applyMappingsDuringRecording },
                                set: { PreferencesService.shared.applyMappingsDuringRecording = $0 }
                            )) {
                                Text("Record physical keys (pause KeyPath)").tag(false)
                                Text("Record with KeyPath mappings running").tag(true)
                            }
                            .pickerStyle(.radioGroup)
                            .labelsHidden()
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)

                if shouldShowStartup {
                    FormSection(header: "Legacy Startup Agent") {
                        LaunchAgentSettingsView()
                    }
                }

                Spacer()
            }
        }
        .settingsBackground()
        .withToasts(settingsToastManager)
        .sheet(isPresented: $showingInstallationWizard) {
            let startPage: WizardPage? = HelperManager.shared.isHelperInstalled() ? nil : .helper
            InstallationWizardView(initialPage: startPage)
                .customizeSheetWindow()
                .environmentObject(kanataManager)
        }
        .alert("Permissions Required", isPresented: $showingPermissionAlert) {
            Button("Open Wizard") {
                showingInstallationWizard = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("KeyPath needs system permissions to remap your keyboard. The installation wizard will guide you through granting the necessary permissions.")
        }
        .task {
            await refreshStatus()
            await refreshServiceStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .wizardClosed)) { _ in
            Task {
                await refreshStatus()
                await refreshServiceStatus()
            }
        }
    }

    // MARK: - Helpers

    private func refreshStatus() async {
        await kanataManager.forceRefreshStatus()
        let snapshot = await PermissionOracle.shared.currentSnapshot()
        let duplicates = HelperMaintenance.shared.detectDuplicateAppCopies()

        await MainActor.run {
            permissionSnapshot = snapshot
            showSetupBanner = !snapshot.isSystemReady
            duplicateAppCopies = duplicates
        }
    }

    private func openConfigInEditor() {
        let url = URL(fileURLWithPath: kanataManager.configPath)
        NSWorkspace.shared.open(url)
        AppLogger.shared.log("📝 [Settings] Opened config for editing")
    }

    private func openBackupsFolder() {
        let backupsPath = "\(NSHomeDirectory())/.config/keypath/.backups"
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: backupsPath)
    }

    private func resetToDefaultConfig() {
        Task {
            do {
                try await kanataManager.resetToDefaultConfig()
                settingsToastManager.showSuccess("Configuration reset to default")
            } catch {
                settingsToastManager.showError("Reset failed: \(error.localizedDescription)")
            }
        }
    }

    private func openLogFile(_ filePath: String) {
        // Try to open with Zed editor first (if available)
        let zedProcess = Process()
        zedProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/zed")
        zedProcess.arguments = [filePath]

        do {
            try zedProcess.run()
            AppLogger.shared.log("📝 [Settings] Opened log in Zed: \(filePath)")
            return
        } catch {
            // Fallback: Try to open with default text editor
            let fallbackProcess = Process()
            fallbackProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            fallbackProcess.arguments = ["-t", filePath]

            do {
                try fallbackProcess.run()
                AppLogger.shared.log("📝 [Settings] Opened log in default text editor: \(filePath)")
            } catch {
                AppLogger.shared.log("❌ [Settings] Failed to open log file: \(error.localizedDescription)")
                settingsToastManager.showError("Failed to open log file")
            }
        }
    }

    private func refreshServiceStatus() async {
        await MainActor.run {
            let state = KanataDaemonManager.determineServiceManagementState()
            AppLogger.shared.log("🔄 [SettingsView] refreshServiceStatus: state=\(state)")
            switch state {
            case .legacyActive:
                activeMethod = .launchctl
                AppLogger.shared.log("  → Set activeMethod = .launchctl")
            case .smappserviceActive, .smappservicePending:
                activeMethod = .smappservice
                AppLogger.shared.log("  → Set activeMethod = .smappservice")
            case .conflicted:
                activeMethod = .launchctl // Show migration section when conflicted!
                AppLogger.shared.log("  → Set activeMethod = .launchctl (conflicted)")
            case .unknown, .uninstalled:
                activeMethod = .unknown
                AppLogger.shared.log("  → Set activeMethod = .unknown")
            }
            AppLogger.shared.log("  → Final activeMethod value: \(activeMethod)")
        }
    }

    // MARK: - Service Management Section

    @ViewBuilder
    private var serviceManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: activeMethodIcon)
                    .foregroundColor(activeMethodColor)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(activeMethodText)
                        .font(.body)
                        .fontWeight(.medium)

                    Text(activeMethodDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Migration button - only show if legacy is detected
            if activeMethod == .launchctl, KanataDaemonManager.shared.hasLegacyInstallation() {
                HStack(spacing: 8) {
                    Button(isMigrating ? "Migrating…" : "Migrate to SMAppService") {
                        guard !isMigrating else { return }
                        isMigrating = true
                        Task { @MainActor in
                            do {
                                try await KanataDaemonManager.shared.migrateFromLaunchctl()
                                settingsToastManager.showSuccess("Migrated to SMAppService")
                                await refreshServiceStatus()
                            } catch {
                                settingsToastManager.showError("Migration failed: \(error.localizedDescription)")
                            }
                            isMigrating = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isMigrating)

                    Spacer()
                }
            }
        }
    }

    private var activeMethodIcon: String {
        switch activeMethod {
        case .smappservice: "checkmark.circle.fill"
        case .launchctl: "gear.circle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    private var activeMethodColor: Color {
        switch activeMethod {
        case .smappservice: .green
        case .launchctl: .orange
        case .unknown: .gray
        }
    }

    private var activeMethodText: String {
        switch activeMethod {
        case .smappservice: "Using SMAppService"
        case .launchctl: "Using launchctl (Legacy)"
        case .unknown: "Checking service method..."
        }
    }

    private var activeMethodDescription: String {
        switch activeMethod {
        case .smappservice: "Modern service management via System Settings"
        case .launchctl: "Traditional service management via launchctl"
        case .unknown: "Determining active service method"
        }
    }
}

// MARK: - Supporting Views

private struct PermissionStatusRow: View {
    let title: String
    let icon: String
    let granted: Bool?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(statusColor)
                .frame(width: 20)

            Text(title)
                .font(.body)

            Spacer()

            if let granted {
                Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(granted ? .green : .red)
                    .font(.body)
            } else {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            }
        }
    }

    private var statusColor: Color {
        if let granted {
            granted ? .green : .red
        } else {
            .secondary
        }
    }
}
