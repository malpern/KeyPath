import AppKit
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import SwiftUI

// MARK: - General Settings Tab

struct GeneralSettingsTabView: View {
    @EnvironmentObject var kanataManager: KanataViewModel
    @State private var settingsToastManager = WizardToastManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 40) {
                // Left: Logs
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

                    Divider()
                        .padding(.vertical, 4)

                    // Verbose Logging Toggle
                    VerboseLoggingToggle()
                }
                .frame(minWidth: 220)

                // Right: Recording Settings
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
            .padding(.top, 20)

            Spacer()
        }
        .frame(maxHeight: 300)
        .settingsBackground()
        .withToasts(settingsToastManager)
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
}

// MARK: - Status Settings Tab

struct StatusSettingsTabView: View {
    @EnvironmentObject var kanataManager: KanataViewModel

    @State private var showingInstallationWizard = false
    @State private var showSetupBanner = false
    @State private var permissionSnapshot: PermissionOracle.Snapshot?
    @State private var duplicateAppCopies: [String] = []
    @State private var settingsToastManager = WizardToastManager()
    @State private var showingPermissionAlert = false

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
        }
    }

    private var primaryIssueDetail: StatusDetail? {
        statusDetails
            .sorted { $0.level.rawValue > $1.level.rawValue }
            .first(where: { $0.level.isIssue })
    }

    private var statusDetails: [StatusDetail] {
        var details: [StatusDetail] = [serviceStatusDetail]

        if let detail = permissionDetail {
            details.append(detail)
        }

        if let duplicateDetail = duplicateAppsDetail {
            details.append(duplicateDetail)
        }

        return details
    }

    private var serviceStatusDetail: StatusDetail {
        switch kanataManager.currentState {
        case .running:
            return StatusDetail(
                title: "Kanata Service",
                message: "Running normally.",
                icon: "bolt.fill",
                level: .success
            )
        case .starting:
            return StatusDetail(
                title: "Kanata Service",
                message: "Starting…",
                icon: "hourglass.circle",
                level: .info
            )
        case .needsHelp:
            return StatusDetail(
                title: "Kanata Service",
                message: kanataManager.errorReason ?? "KeyPath needs attention.",
                icon: "exclamationmark.circle",
                level: .critical,
                action: StatusDetailAction(title: "Open Wizard", icon: "wand.and.stars") {
                    showingInstallationWizard = true
                }
            )
        case .stopped:
            return StatusDetail(
                title: "Kanata Service",
                message: "Service is stopped. Use the switch above to turn it on.",
                icon: "pause.circle",
                level: .warning
            )
        }
    }

    private var permissionDetail: StatusDetail? {
        guard let snapshot = permissionSnapshot else {
            return StatusDetail(
                title: "Permissions",
                message: "Checking current permissions…",
                icon: "ellipsis.circle",
                level: .info
            )
        }

        let evaluation = permissionGaps(in: snapshot)

        if evaluation.labels.isEmpty {
            return StatusDetail(
                title: "Permissions",
                message: "All required permissions are granted.",
                icon: "checkmark.shield.fill",
                level: .success
            )
        }

        var lines: [String] = []
        if let blocking = snapshot.blockingIssue {
            lines.append(blocking)
        }
        lines.append("Missing: \(evaluation.labels.joined(separator: ", "))")

        return StatusDetail(
            title: "Permissions",
            message: lines.joined(separator: "\n"),
            icon: "exclamationmark.shield",
            level: evaluation.hasErrors ? .critical : .warning,
            action: StatusDetailAction(title: "Fix", icon: "wand.and.stars") {
                showingPermissionAlert = true
            }
        )
    }

    private var duplicateAppsDetail: StatusDetail? {
        guard duplicateAppCopies.count > 1 else { return nil }
        let count = duplicateAppCopies.count
        return StatusDetail(
            title: "Duplicate Installations",
            message: "Found \(count) copies of KeyPath. Extra copies can confuse macOS permissions.",
            icon: "exclamationmark.triangle",
            level: .warning,
            action: StatusDetailAction(title: "Review", icon: "arrow.right") {
                NotificationCenter.default.post(name: .openSettingsAdvanced, object: nil)
            }
        )
    }

    private func permissionGaps(in snapshot: PermissionOracle.Snapshot) -> (labels: [String], hasErrors: Bool) {
        var labels: [String] = []
        var hasErrors = false

        func append(status: PermissionOracle.Status, label: String) {
            guard !status.isReady else { return }
            labels.append(label)
            if case .error = status {
                hasErrors = true
            }
        }

        append(status: snapshot.keyPath.accessibility, label: "KeyPath Accessibility")
        append(status: snapshot.keyPath.inputMonitoring, label: "KeyPath Input Monitoring")
        append(status: snapshot.kanata.accessibility, label: "Kanata Accessibility")
        append(status: snapshot.kanata.inputMonitoring, label: "Kanata Input Monitoring")

        return (labels, hasErrors)
    }

    var body: some View {
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

                            if let issue = primaryIssueDetail {
                                Text(issue.message)
                                    .font(.footnote)
                                    .foregroundColor(issue.level.tintColor)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Button(action: {
                                NotificationCenter.default.post(name: .openSettingsRules, object: nil)
                            }) {
                                let enabledCollections = kanataManager.ruleCollections.filter(\.isEnabled).count
                                let enabledCustomRules = kanataManager.customRules.filter(\.isEnabled).count
                                let activeCount = enabledCollections + enabledCustomRules
                                Text("\(activeCount) active rule\(activeCount == 1 ? "" : "s")")
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

            if shouldShowStartup {
                FormSection(header: "Legacy Startup Agent") {
                    LaunchAgentSettingsView()
                }
            }

            Spacer()
        }
        .frame(maxHeight: 350)
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
        }
        .onReceive(NotificationCenter.default.publisher(for: .wizardClosed)) { _ in
            Task {
                await refreshStatus()
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

private struct StatusDetailAction {
    let title: String
    let icon: String?
    let handler: () -> Void
}

private struct StatusDetail: Identifiable {
    enum Level: Int {
        case success = 0
        case info = 1
        case warning = 2
        case critical = 3
    }

    let title: String
    let message: String
    let icon: String
    let level: Level
    let action: StatusDetailAction?

    var id: String {
        "\(title)|\(message)"
    }

    init(title: String, message: String, icon: String, level: Level, action: StatusDetailAction? = nil) {
        self.title = title
        self.message = message
        self.icon = icon
        self.level = level
        self.action = action
    }
}

private extension StatusDetail.Level {
    var tintColor: Color {
        switch self {
        case .success: .green
        case .info: .secondary
        case .warning: .orange
        case .critical: .red
        }
    }

    var isIssue: Bool {
        switch self {
        case .warning, .critical: true
        case .success, .info: false
        }
    }
}

private struct StatusDetailRow: View {
    let detail: StatusDetail

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: detail.icon)
                .foregroundColor(detail.level.tintColor)
                .font(.body)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(detail.title)
                    .font(.subheadline.weight(.semibold))

                Text(detail.message)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if let action = detail.action {
                Button {
                    action.handler()
                } label: {
                    if let icon = action.icon {
                        Label(action.title, systemImage: icon)
                            .labelStyle(.titleAndIcon)
                    } else {
                        Text(action.title)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
