import KeyPathCore
import KeyPathPermissions
import SwiftUI

// MARK: - File Navigation (999 lines)

//
// This file displays system diagnostics and health checks. Use CMD+F to jump to:
//
// Main Actions:
//   - runDiagnostics()         Collect all diagnostic information
//   - refreshSystemStatus()    Update system state
//   - validateConfig()         Check Kanata configuration
//
// Data Collection:
//   - getKanataVersion()       Check Kanata binary version
//   - getCodeSignature()       Verify code signing
//   - getLaunchDaemonState()   Check service status
//   - probePermissions()       Test all permissions
//
// UI Utilities:
//   - severityColor()          Color for diagnostic severity
//   - categoryColor()          Color for diagnostic category
//   - openKeyPathLogs()        Open KeyPath log directory
//   - openKanataLogs()         Open Kanata log file

struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var kanataManager: KanataViewModel // Phase 4: MVVM
    @State private var systemDiagnostics: [KanataDiagnostic] = []
    @State private var showTechnicalDetails: Set<Int> = []
    @State private var isRunningDiagnostics = false
    @State private var showingWizard = false
    @State private var selectedTab: Tab = .summary
    @State private var exporting = false
    @State private var exportMessage: String?
    // Helper management state (moved from Settings)
    @State private var helperInstalled: Bool = HelperManager.shared.isHelperInstalled()
    @State private var helperVersion: String?
    @State private var helperInProgress = false
    @State private var helperMessage: String?
    @State private var showingHelperDiagnostics = false
    @State private var helperDiagnosticsText: String = ""
    @State private var showingHelperLogs = false
    @State private var helperLogLines: [String] = []
    @State private var showingHelperCleanup = false
    @State private var showingHelperUninstallConfirm = false
    @State private var disableGrabberInProgress = false
    // Recovery tools
    @State private var showingDevResetConfirmation = false
    @State private var showingResetEverythingConfirmation = false
    @State private var isResetting = false
    @State private var helperServiceStatus = DiagnosticsServiceHealthStatus(title: "Privileged Helper", level: .unknown, message: "Not checked")
    @State private var smAppServiceStatus = DiagnosticsServiceHealthStatus(title: "Background Item", level: .unknown, message: "Not checked")
    @State private var vhidServiceStatus = DiagnosticsServiceHealthStatus(title: "VirtualHID", level: .unknown, message: "Not checked")

    enum Tab: String, CaseIterable {
        case summary = "Summary"
        case logs = "Logs"
        case advanced = "Advanced"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with navigation-style toolbar
            HStack {
                // Left: segmented tabs
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                Spacer()

                // Right: actions
                Button(isRunningDiagnostics ? "Refreshing…" : "Refresh") {
                    runDiagnostics()
                }
                .disabled(isRunningDiagnostics)
                .buttonStyle(.bordered)

                Button("Support Report…") {
                    Task { exporting = true; exportMessage = await exportSupportReport(); exporting = false }
                }
                .buttonStyle(.borderedProminent)
                .disabled(exporting)
                .accessibilityLabel("Generate Support Report")
                .accessibilityHint("Creates a zip on your Desktop with logs and diagnostics")

                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .appGlassHeader()

            Divider()

            Group {
                switch selectedTab {
                case .summary:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if isRunningDiagnostics {
                                HStack {
                                    ProgressView().scaleEffect(0.8)
                                    Text("Running diagnostics…").font(.subheadline).foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            ProcessStatusSection(kanataManager: kanataManager)
                            PermissionStatusSection(kanataManager: kanataManager, onShowWizard: { showingWizard = true })
                            ServiceHealthSection(
                                helperStatus: helperServiceStatus,
                                smAppStatus: smAppServiceStatus,
                                vhidStatus: vhidServiceStatus,
                                onFixHelper: { showingHelperDiagnostics = true; Task { await refreshHelperStatus() } },
                                onOpenWizard: { showingWizard = true }
                            )
                            // Keep a concise health snapshot
                            EnhancedStatusSection(kanataManager: kanataManager)
                            if !systemDiagnostics.isEmpty {
                                DiagnosticSection(
                                    title: "System Diagnostics",
                                    diagnostics: systemDiagnostics,
                                    showTechnicalDetails: $showTechnicalDetails,
                                    kanataManager: kanataManager
                                )
                            }
                        }
                        .padding(20)
                    }
                case .logs:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            VerboseLoggingSection()
                            LogAccessSection(
                                onOpenKeyPathLogs: openKeyPathLogs,
                                onOpenKanataLogs: openKanataLogs
                            )
                        }
                        .padding(20)
                    }
                case .advanced:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            ServiceManagementSection(kanataManager: kanataManager)
                            HelperManagementAdvancedSection(
                                helperInstalled: $helperInstalled,
                                helperVersion: $helperVersion,
                                helperInProgress: $helperInProgress,
                                helperMessage: $helperMessage,
                                showingHelperDiagnostics: $showingHelperDiagnostics,
                                helperDiagnosticsText: $helperDiagnosticsText,
                                showingHelperLogs: $showingHelperLogs,
                                helperLogLines: $helperLogLines,
                                showingHelperCleanup: $showingHelperCleanup,
                                showingHelperUninstallConfirm: $showingHelperUninstallConfirm,
                                onRefreshStatus: { await refreshHelperStatus() },
                                onTestXPC: { await testHelperXPC() },
                                onShowHelperLogs: { await showHelperLogs() },
                                onRunHelperDiagnostics: { runHelperDiagnostics() },
                                onUninstallHelper: { await uninstallHelper() },
                                onDisableGrabber: {
                                    await disableKarabinerGrabber()
                                }
                            )
                            RecoveryToolsSection(
                                isResetting: $isResetting,
                                onDevReset: { await performDevReset() },
                                onResetEverything: { await performResetEverything() },
                                showingDevResetConfirmation: $showingDevResetConfirmation,
                                showingResetEverythingConfirmation: $showingResetEverythingConfirmation
                            )
                            ConfigStatusSection(kanataManager: kanataManager)
                            if !kanataManager.diagnostics.isEmpty {
                                DiagnosticSection(
                                    title: "Runtime Issues",
                                    diagnostics: kanataManager.diagnostics,
                                    showTechnicalDetails: $showTechnicalDetails,
                                    kanataManager: kanataManager
                                )
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .alert("Developer Reset", isPresented: $showingDevResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Task { await performDevReset() }
            }
        } message: {
            Text("Stops the daemon, clears logs, waits briefly, restarts service. TCC permissions are not touched.")
        }
        .alert("Reset Everything?", isPresented: $showingResetEverythingConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Task { await performResetEverything() }
            }
        } message: {
            Text("Force kills Kanata, clears PID/state, and resets manager state. Does not restart automatically.")
        }
        .frame(width: 600, height: 700)
        .onAppear {
            runDiagnostics()
            Task { await refreshHelperStatus() }
        }
        .sheet(isPresented: $showingWizard) {
            InstallationWizardView()
                .customizeSheetWindow() // Remove border and fix dark mode
                .environmentObject(kanataManager)
        }
        .sheet(isPresented: $showingHelperLogs) {
            HelperLogsView(lines: helperLogLines) { showingHelperLogs = false }
        }
        .sheet(isPresented: $showingHelperCleanup) {
            CleanupAndRepairView()
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
        .alert("Uninstall Privileged Helper?", isPresented: $showingHelperUninstallConfirm) {
            Button("Cancel", role: .cancel) { showingHelperUninstallConfirm = false }
            Button("Uninstall", role: .destructive) {
                Task { await uninstallHelper() }
            }
        } message: {
            Text("This will unregister the helper from the system. You can reinstall it later via the Setup Wizard.")
        }
        .alert("Support Report", isPresented: .constant(exportMessage != nil)) {
            Button("OK") { exportMessage = nil }
        } message: {
            Text(exportMessage ?? "")
        }
        .task {
            await refreshServiceHealth()
        }
    }

    private func runDiagnostics() {
        isRunningDiagnostics = true

        Task {
            // Fetch system diagnostics including TCP status
            let diagnostics = await kanataManager.underlyingManager.getSystemDiagnostics()
            await refreshServiceHealth()
            await MainActor.run {
                systemDiagnostics = diagnostics
                isRunningDiagnostics = false
            }
        }
    }

    // Minimal export: zip KeyPath logs and helper logs to Desktop
    func exportSupportReport() async -> String {
        let desktop = NSHomeDirectory() + "/Desktop"
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "_")
        let zipPath = "\(desktop)/KeyPath-Support-Report-\(timestamp).zip"

        let appLog = NSHomeDirectory() + "/Library/Logs/KeyPath/keypath-debug.log"
        let helperStdout = "/var/log/com.keypath.helper.stdout.log"
        let helperStderr = "/var/log/com.keypath.helper.stderr.log"
        let tempDir = NSTemporaryDirectory() + "kp_support_\(UUID().uuidString)"

        do {
            try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
            // Copy present files (ignore missing)
            if FileManager.default.fileExists(atPath: appLog) {
                try FileManager.default.copyItem(atPath: appLog, toPath: tempDir + "/keypath-debug.log")
            }
            if FileManager.default.fileExists(atPath: helperStdout) {
                try FileManager.default.copyItem(atPath: helperStdout, toPath: tempDir + "/helper-stdout.log")
            }
            if FileManager.default.fileExists(atPath: helperStderr) {
                try FileManager.default.copyItem(atPath: helperStderr, toPath: tempDir + "/helper-stderr.log")
            }
            // Add a brief environment summary
            let bi = BuildInfo.current()
            let summary = "KeyPath \(bi.version) (\(bi.build))\nmacOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
            try summary.write(toFile: tempDir + "/summary.txt", atomically: true, encoding: .utf8)
            // Bless/SMAppService diagnostics (text)
            let bless = HelperManager.shared.runBlessDiagnostics()
            try bless.write(toFile: tempDir + "/bless-diagnostics.txt", atomically: true, encoding: .utf8)
            // README
            let readme = """
            KeyPath Support Report
            ----------------------
            Files included:
            - keypath-debug.log: KeyPath application log
            - helper-stdout.log/helper-stderr.log: helper logs (if present)
            - bless-diagnostics.txt: SMAppService and launchd status for helper
            - summary.txt: app and OS versions

            Generated: \(Date().formatted(date: .abbreviated, time: .standard))
            """
            try readme.write(toFile: tempDir + "/README.txt", atomically: true, encoding: .utf8)

            // Zip
            let p = Process()
            p.launchPath = "/usr/bin/zip"
            p.arguments = ["-r", zipPath, "."]
            p.currentDirectoryPath = tempDir
            try p.run()
            p.waitUntilExit()

            return p.terminationStatus == 0 ? "Saved to Desktop: \(zipPath)" : "Failed to create report (zip exit \(p.terminationStatus))"
        } catch {
            return "Export failed: \(error.localizedDescription)"
        }
    }

    private func refreshServiceHealth() async {
        let helperInstalled = HelperManager.shared.isHelperInstalled()
        let helperResponsive = await HelperManager.shared.testHelperFunctionality()
        let helperStatus = if helperInstalled, helperResponsive {
            DiagnosticsServiceHealthStatus(title: "Privileged Helper", level: .good, message: "Helper is registered and responding")
        } else if helperInstalled {
            DiagnosticsServiceHealthStatus(title: "Privileged Helper", level: .warning, message: "Helper installed but not responding")
        } else {
            DiagnosticsServiceHealthStatus(title: "Privileged Helper", level: .error, message: "Helper not installed")
        }

        let smState = KanataDaemonManager.determineServiceManagementState()
        let smStatus = switch smState {
        case .smappserviceActive:
            DiagnosticsServiceHealthStatus(title: "Background Item", level: .good, message: "SMAppService registered and enabled")
        case .smappservicePending:
            DiagnosticsServiceHealthStatus(title: "Background Item", level: .warning, message: "Awaiting approval in System Settings → Login Items")
        case .legacyActive, .conflicted:
            DiagnosticsServiceHealthStatus(title: "Background Item", level: .error, message: "Legacy launchctl plist detected; run Setup Wizard to migrate")
        case .uninstalled:
            DiagnosticsServiceHealthStatus(title: "Background Item", level: .error, message: "Kanata service is not registered")
        case .unknown:
            DiagnosticsServiceHealthStatus(title: "Background Item", level: .warning, message: "State unknown; rerun wizard to repair")
        }

        let installer = LaunchDaemonInstaller()
        let vhidDaemonHealthy = installer.isServiceHealthy(serviceID: "com.keypath.karabiner-vhiddaemon")
        let vhidManagerHealthy = installer.isServiceHealthy(serviceID: "com.keypath.karabiner-vhidmanager")
        let vhidStatus = if vhidDaemonHealthy, vhidManagerHealthy {
            DiagnosticsServiceHealthStatus(title: "VirtualHID Services", level: .good, message: "Driver services are loaded")
        } else {
            DiagnosticsServiceHealthStatus(title: "VirtualHID Services", level: .error, message: "Driver services need repair")
        }

        await MainActor.run {
            helperServiceStatus = helperStatus
            smAppServiceStatus = smStatus
            vhidServiceStatus = vhidStatus
        }
    }

    // MARK: - Helper management (moved from Settings)

    private func refreshHelperStatus() async {
        await MainActor.run { helperInstalled = HelperManager.shared.isHelperInstalled() }
        let v = await HelperManager.shared.getHelperVersion()
        await MainActor.run { helperVersion = v }
    }

    // MARK: - Recovery tools

    private func performDevReset() async {
        await MainActor.run { isResetting = true }
        defer { Task { await MainActor.run { isResetting = false } } }
        // Stop → wait → start → refresh
        await kanataManager.manualStop()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await kanataManager.manualStart()
        await kanataManager.forceRefreshStatus()
    }

    private func performResetEverything() async {
        await MainActor.run { isResetting = true }
        defer { Task { await MainActor.run { isResetting = false } } }
        let autoFixer = WizardAutoFixer(kanataManager: kanataManager.underlyingManager)
        _ = await autoFixer.resetEverything()
        await kanataManager.forceRefreshStatus()
    }

    func testHelperXPC() async {
        await MainActor.run { helperInProgress = true; helperMessage = nil }
        defer { Task { await MainActor.run { helperInProgress = false } } }
        let v = await HelperManager.shared.getHelperVersion()
        await MainActor.run {
            if let v {
                helperMessage = "XPC OK (v\(v))"
            } else {
                helperMessage = "XPC failed (helper unreachable)"
            }
        }
        await refreshHelperStatus()
    }

    private func runHelperDiagnostics() {
        helperDiagnosticsText = HelperManager.shared.runBlessDiagnostics()
        showingHelperDiagnostics = true
    }

    private func showHelperLogs() async {
        await MainActor.run { helperInProgress = true }
        defer { Task { await MainActor.run { helperInProgress = false } } }
        let lines = HelperManager.shared.lastHelperLogs(count: 50, windowSeconds: 600)
        await MainActor.run {
            helperLogLines = lines
            showingHelperLogs = true
        }
    }

    private func uninstallHelper() async {
        await MainActor.run { helperInProgress = true; helperMessage = nil }
        defer { Task { await MainActor.run { helperInProgress = false; showingHelperUninstallConfirm = false } } }
        do {
            try await HelperManager.shared.uninstallHelper()
            await MainActor.run { helperMessage = "Helper uninstalled" }
            await refreshHelperStatus()
        } catch {
            await MainActor.run { helperMessage = "Uninstall failed: \(error.localizedDescription)" }
        }
    }

    private func disableKarabinerGrabber() async {
        await MainActor.run { disableGrabberInProgress = true }
        defer { Task { await MainActor.run { disableGrabberInProgress = false } } }
        do {
            try await PrivilegedOperationsCoordinator.shared.disableKarabinerGrabber()
        } catch { /* no toast here; diagnostics view keeps minimal chrome */ }
    }

    private func openKeyPathLogs() {
        let logPath = "\(NSHomeDirectory())/Library/Logs/KeyPath/keypath-debug.log"

        // Try to open with Zed first
        let zedProcess = Process()
        zedProcess.launchPath = "/usr/local/bin/zed"
        zedProcess.arguments = [logPath]

        do {
            try zedProcess.run()
            return
        } catch {
            // Try Homebrew path for Zed
            let homebrewZedProcess = Process()
            homebrewZedProcess.launchPath = "/opt/homebrew/bin/zed"
            homebrewZedProcess.arguments = [logPath]

            do {
                try homebrewZedProcess.run()
                return
            } catch {
                // Try using 'open' command with Zed
                let openZedProcess = Process()
                openZedProcess.launchPath = "/usr/bin/open"
                openZedProcess.arguments = ["-a", "Zed", logPath]

                do {
                    try openZedProcess.run()
                    return
                } catch {
                    // Fallback: Try to open with default text editor
                    let fallbackProcess = Process()
                    fallbackProcess.launchPath = "/usr/bin/open"
                    fallbackProcess.arguments = ["-t", logPath]

                    do {
                        try fallbackProcess.run()
                    } catch {
                        // Last resort: Open containing folder
                        let folderPath = "\(NSHomeDirectory())/Library/Logs/KeyPath"
                        NSWorkspace.shared.open(URL(fileURLWithPath: folderPath))
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
            return
        } catch {
            // Try Homebrew path for Zed
            let homebrewZedProcess = Process()
            homebrewZedProcess.launchPath = "/opt/homebrew/bin/zed"
            homebrewZedProcess.arguments = [kanataLogPath]

            do {
                try homebrewZedProcess.run()
                return
            } catch {
                // Try using 'open' command with Zed
                let openZedProcess = Process()
                openZedProcess.launchPath = "/usr/bin/open"
                openZedProcess.arguments = ["-a", "Zed", kanataLogPath]

                do {
                    try openZedProcess.run()
                    return
                } catch {
                    // Fallback: Try to open with default text editor
                    let fallbackProcess = Process()
                    fallbackProcess.launchPath = "/usr/bin/open"
                    fallbackProcess.arguments = ["-t", kanataLogPath]

                    do {
                        try fallbackProcess.run()
                    } catch {
                        // Last resort: Open containing folder
                        let folderPath = "\(NSHomeDirectory())/Library/Logs/KeyPath"
                        NSWorkspace.shared.open(URL(fileURLWithPath: folderPath))
                    }
                }
            }
        }
    }
}

private struct DiagnosticsServiceHealthStatus: Equatable {
    enum Level {
        case good, warning, error, unknown
    }

    let title: String
    let level: Level
    let message: String

    var icon: String {
        switch level {
        case .good: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch level {
        case .good: .green
        case .warning: .orange
        case .error: .red
        case .unknown: .gray
        }
    }

    var requiresAction: Bool {
        level == .warning || level == .error
    }
}

private struct ServiceHealthSection: View {
    let helperStatus: DiagnosticsServiceHealthStatus
    let smAppStatus: DiagnosticsServiceHealthStatus
    let vhidStatus: DiagnosticsServiceHealthStatus
    let onFixHelper: () -> Void
    let onOpenWizard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Background Service Health")
                .font(.headline)

            ServiceHealthRow(status: helperStatus, actionTitle: helperStatus.requiresAction ? "Inspect" : nil, action: onFixHelper)
            ServiceHealthRow(status: smAppStatus, actionTitle: smAppStatus.requiresAction ? "Open Wizard" : nil, action: onOpenWizard)
            ServiceHealthRow(status: vhidStatus, actionTitle: vhidStatus.requiresAction ? "Repair" : nil, action: onOpenWizard)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 1)
    }
}

private struct ServiceHealthRow: View {
    let status: DiagnosticsServiceHealthStatus
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: status.icon)
                .foregroundColor(status.color)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(status.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(status.message)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let actionTitle, status.requiresAction {
                Button(actionTitle) {
                    action()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

struct ProcessStatusSection: View {
    @ObservedObject var kanataManager: KanataViewModel // Phase 4: MVVM
    @State private var isRegenerating = false
    @State private var statusMessage: String = ""
    @State private var showSuccessMessage = false
    @State private var showErrorMessage = false
    @State private var statusMessageTimer: DispatchWorkItem?
    @State private var isRestarting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Service Status")
                .font(.headline)
                .foregroundColor(.primary)

            HStack(spacing: 12) {
                Image(systemName: kanataManager.isRunning ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(kanataManager.isRunning ? .green : .red)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(kanataManager.isRunning ? "Service running" : "Service not running")
                        .font(.body)
                        .fontWeight(.medium)

                    if !kanataManager.isRunning, let exitCode = kanataManager.lastProcessExitCode {
                        Text("Last exit code: \(exitCode)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            if let error = kanataManager.lastError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)

                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }

            HStack {
                Button(isRegenerating ? "Rebuilding…" : "Rebuild Services") {
                    guard !isRegenerating else { return }
                    isRegenerating = true
                    Task { @MainActor in
                        let ok = await kanataManager.regenerateServices()
                        if ok {
                            showToast("✅ Services rebuilt", isError: false)
                        } else {
                            let msg = kanataManager.lastError ?? "Rebuild services failed"
                            showToast("❌ \(msg)", isError: true)
                        }
                        isRegenerating = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isRegenerating)

                Button(isRestarting ? "Restarting…" : "Restart Kanata") {
                    guard !isRestarting else { return }
                    isRestarting = true
                    Task { @MainActor in
                        await kanataManager.restartKanata()
                        showToast("✅ Kanata restarted", isError: false)
                        await kanataManager.forceRefreshStatus()
                        isRestarting = false
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRestarting)

                Spacer()
            }
            .padding(.top, 4)

            if showSuccessMessage || showErrorMessage {
                HStack {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(showErrorMessage ? .red : .green)
                        .padding(8)
                        .background(showErrorMessage ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                        .cornerRadius(6)
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .padding(16)
        .appGlassCard()
    }
}

extension ProcessStatusSection {
    private func showToast(_ message: String, isError: Bool) {
        statusMessageTimer?.cancel()
        statusMessage = message
        showErrorMessage = isError
        showSuccessMessage = !isError

        let workItem = DispatchWorkItem {
            showErrorMessage = false
            showSuccessMessage = false
        }
        statusMessageTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + (isError ? 5.0 : 3.0), execute: workItem)
    }
}

struct ServiceManagementSection: View {
    @ObservedObject var kanataManager: KanataViewModel
    @State private var activeMethod: ServiceMethod = .unknown
    @State private var isMigrating = false
    @State private var statusMessage: String = ""
    @State private var showSuccessMessage = false
    @State private var showErrorMessage = false
    @State private var statusMessageTimer: DispatchWorkItem?

    enum ServiceMethod {
        case smappservice
        case launchctl
        case unknown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Service Management")
                .font(.headline)
                .foregroundColor(.primary)

            // Active method display
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

            // Action buttons
            HStack(spacing: 8) {
                // Migration button - only show if legacy is detected (auto-resolve should handle it, but keep as utility)
                if activeMethod == .launchctl, KanataDaemonManager.shared.hasLegacyInstallation() {
                    Button(isMigrating ? "Migrating…" : "Migrate to SMAppService") {
                        guard !isMigrating else { return }
                        isMigrating = true
                        Task { @MainActor in
                            do {
                                try await KanataDaemonManager.shared.migrateFromLaunchctl()
                                showToast("✅ Migrated to SMAppService", isError: false)
                                await refreshStatus()
                            } catch {
                                showToast("❌ Migration failed: \(error.localizedDescription)", isError: true)
                            }
                            isMigrating = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isMigrating)
                }

                Spacer()
            }
            .padding(.top, 4)

            if showSuccessMessage || showErrorMessage {
                HStack {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(showErrorMessage ? .red : .green)
                        .padding(8)
                        .background(showErrorMessage ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                        .cornerRadius(6)
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .padding(16)
        .appGlassCard()
        .onAppear {
            Task {
                await refreshStatus()
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

    private func refreshStatus() async {
        await MainActor.run {
            // Use state determination for consistent detection (same logic as guards)
            let state = KanataDaemonManager.determineServiceManagementState()

            AppLogger.shared.log("🔍 [ServiceManagement] refreshStatus() called")
            AppLogger.shared.log("🔍 [ServiceManagement] State: \(state.description)")

            // Map state to UI activeMethod
            switch state {
            case .legacyActive:
                AppLogger.shared.log("⚠️ [ServiceManagement] Detected: Using launchctl (legacy plist exists)")
                activeMethod = .launchctl
            case .smappserviceActive, .smappservicePending:
                AppLogger.shared.log("✅ [ServiceManagement] Detected: Using SMAppService (state: \(state.description))")
                activeMethod = .smappservice
            case .conflicted:
                AppLogger.shared.log("⚠️ [ServiceManagement] Detected: Conflicted state (both methods active)")
                // Prefer SMAppService if conflicted (feature flag is ON)
                activeMethod = .smappservice
            case .unknown, .uninstalled:
                AppLogger.shared.log("❓ [ServiceManagement] Detected: Unknown/Uninstalled (state: \(state.description))")
                activeMethod = .unknown
            }

            AppLogger.shared.log("🔍 [ServiceManagement] Final activeMethod: \(String(describing: activeMethod))")
        }
    }

    private func showToast(_ message: String, isError: Bool) {
        statusMessageTimer?.cancel()
        statusMessage = message
        showErrorMessage = isError
        showSuccessMessage = !isError

        let workItem = DispatchWorkItem {
            showErrorMessage = false
            showSuccessMessage = false
        }
        statusMessageTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + (isError ? 5.0 : 3.0), execute: workItem)
    }
}

struct PermissionStatusSection: View {
    @ObservedObject var kanataManager: KanataViewModel // Phase 4: MVVM
    let onShowWizard: () -> Void
    @Environment(\.permissionSnapshotProvider) private var permissionProvider
    @State private var snapshot: PermissionOracle.Snapshot?

    var body: some View {
        let allPermissions = snapshot?.isSystemReady ?? false

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Permissions")
                    .font(.headline)

                Spacer()

                if !allPermissions {
                    Button("Open Setup Wizard") {
                        onShowWizard()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            // Show all permission details with icons
            if let snapshot {
                VStack(alignment: .leading, spacing: 8) {
                    PermissionRow(
                        title: "KeyPath Accessibility",
                        icon: "lock.shield",
                        granted: snapshot.keyPath.accessibility.isReady
                    )

                    PermissionRow(
                        title: "KeyPath Input Monitoring",
                        icon: "keyboard",
                        granted: snapshot.keyPath.inputMonitoring.isReady
                    )

                    PermissionRow(
                        title: "Kanata Accessibility",
                        icon: "lock.shield",
                        granted: snapshot.kanata.accessibility.isReady
                    )

                    PermissionRow(
                        title: "Kanata Input Monitoring",
                        icon: "keyboard",
                        granted: snapshot.kanata.inputMonitoring.isReady
                    )
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Checking permissions…")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        // Always source from PermissionOracle for consistency with the Wizard
        .task {
            snapshot = await PermissionOracle.shared.currentSnapshot()
        }
        .onChange(of: kanataManager.currentState) { _, _ in
            Task { snapshot = await PermissionOracle.shared.currentSnapshot() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wizardClosed)) { _ in
            Task { snapshot = await PermissionOracle.shared.currentSnapshot() }
        }
    }
}

// MARK: - Permission Row

private struct PermissionRow: View {
    let title: String
    let icon: String
    let granted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(granted ? .green : .red)
                .frame(width: 20)

            Text(title)
                .font(.body)

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(granted ? Color.green : Color.red)
                    .frame(width: 8, height: 8)

                Text(granted ? "Granted" : "Required")
                    .font(.caption)
                    .foregroundColor(granted ? .green : .red)
            }
        }
    }
}

// MARK: - Helper Management (Advanced tab)

struct HelperManagementAdvancedSection: View {
    @Binding var helperInstalled: Bool
    @Binding var helperVersion: String?
    @Binding var helperInProgress: Bool
    @Binding var helperMessage: String?
    @Binding var showingHelperDiagnostics: Bool
    @Binding var helperDiagnosticsText: String
    @Binding var showingHelperLogs: Bool
    @Binding var helperLogLines: [String]
    @Binding var showingHelperCleanup: Bool
    @Binding var showingHelperUninstallConfirm: Bool

    let onRefreshStatus: () async -> Void
    let onTestXPC: () async -> Void
    let onShowHelperLogs: () async -> Void
    let onRunHelperDiagnostics: () -> Void
    let onUninstallHelper: () async -> Void
    let onDisableGrabber: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Privileged Helper")
                .font(.headline)
                .foregroundColor(.primary)

            // Status
            HStack {
                Circle()
                    .fill(helperInstalled ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                Text(helperInstalled ? (helperVersion.map { "Installed (v\($0))" } ?? "Installed") : "Not Installed")
                    .fontWeight(.medium)
                Spacer()
                Button("Refresh") { Task { await onRefreshStatus() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            // Actions
            HStack(spacing: 8) {
                Button("Cleanup & Repair…") { showingHelperCleanup = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(helperInProgress)

                Button("Test XPC") { Task { await onTestXPC() } }
                    .buttonStyle(.bordered)
                    .disabled(helperInProgress)

                Button("Diagnostics") { onRunHelperDiagnostics() }
                    .buttonStyle(.bordered)
                    .disabled(helperInProgress)

                Button("Logs…") { Task { await onShowHelperLogs() } }
                    .buttonStyle(.bordered)
                    .disabled(helperInProgress)

                Spacer()

                Button("Uninstall", role: .destructive) { showingHelperUninstallConfirm = true }
                    .buttonStyle(.bordered)
                    .disabled(helperInProgress || !helperInstalled)
            }

            // Tools
            HStack(spacing: 8) {
                Button("Disable Karabiner Grabber") { Task { await onDisableGrabber() } }
                    .buttonStyle(.bordered)
            }

            if let msg = helperMessage, !msg.isEmpty {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .appGlassCard()
    }
}

struct RecoveryToolsSection: View {
    @Binding var isResetting: Bool
    let onDevReset: () async -> Void
    let onResetEverything: () async -> Void
    @Binding var showingDevResetConfirmation: Bool
    @Binding var showingResetEverythingConfirmation: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recovery Tools")
                .font(.headline)
                .foregroundColor(.primary)

            HStack(spacing: 8) {
                Button(isResetting ? "Resetting…" : "Developer Reset") {
                    showingDevResetConfirmation = true
                }
                .buttonStyle(.bordered)
                .disabled(isResetting)

                Button(isResetting ? "Resetting…" : "Reset Everything") {
                    showingResetEverythingConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isResetting)
            }
        }
        .padding(16)
        .appGlassCard()
    }
}

struct DiagnosticSection: View {
    let title: String
    let diagnostics: [KanataDiagnostic]
    @Binding var showTechnicalDetails: Set<Int>
    @ObservedObject var kanataManager: KanataViewModel // Phase 4: MVVM

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ForEach(diagnostics.indices, id: \.self) { index in
                let diagnostic = diagnostics[index]
                let diagnosticKey = "\(diagnostic.title)|\(diagnostic.description)|\(diagnostic.technicalDetails)"
                let diagnosticId = diagnosticKey.hashValue // Stable per-content id

                DiagnosticCard(
                    diagnostic: diagnostic,
                    showTechnicalDetails: showTechnicalDetails.contains(diagnosticId),
                    onToggleTechnicalDetails: {
                        if showTechnicalDetails.contains(diagnosticId) {
                            showTechnicalDetails.remove(diagnosticId)
                        } else {
                            showTechnicalDetails.insert(diagnosticId)
                        }
                    },
                    onAutoFix: {
                        Task {
                            if diagnostic.title.contains("protocol too old") {
                                _ = await kanataManager.regenerateServices()
                                await kanataManager.forceRefreshStatus()
                            } else {
                                await kanataManager.autoFixDiagnostic(diagnostic)
                            }
                        }
                    }
                )
            }
        }
    }
}

struct DiagnosticCard: View {
    let diagnostic: KanataDiagnostic
    let showTechnicalDetails: Bool
    let onToggleTechnicalDetails: () -> Void
    let onAutoFix: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Main diagnostic info
            HStack(alignment: .top, spacing: 12) {
                Text(diagnostic.severity.emoji)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 6) {
                    Text(diagnostic.title)
                        .font(.body)
                        .fontWeight(.semibold)

                    Text(diagnostic.description)
                        .font(.body)
                        .foregroundColor(.primary)
                }

                Spacer()

                // Category badge (no color)
                Text(diagnostic.category.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .foregroundColor(.secondary)
                    .cornerRadius(6)
            }

            // Suggested action
            if !diagnostic.suggestedAction.isEmpty {
                Text("💡 \(diagnostic.suggestedAction)")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.leading, 32)
            }

            // Action buttons
            HStack {
                if diagnostic.canAutoFix {
                    Button("Auto Fix") {
                        onAutoFix()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }

                if !diagnostic.technicalDetails.isEmpty {
                    Button(showTechnicalDetails ? "Hide Details" : "Show Details") {
                        onToggleTechnicalDetails()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                Spacer()

                Text(diagnostic.timestamp, style: .time)
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            // Technical details (expandable)
            if showTechnicalDetails, !diagnostic.technicalDetails.isEmpty {
                Text(diagnostic.technicalDetails)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary)
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    private func severityColor(_ severity: DiagnosticSeverity) -> Color {
        switch severity {
        case .info: .blue
        case .warning: .orange
        case .error: .red
        case .critical: .purple
        }
    }

    private func categoryColor(_ category: DiagnosticCategory) -> Color {
        switch category {
        case .configuration: .blue
        case .permissions: .orange
        case .process: .green
        case .system: .purple
        case .conflict: .red
        }
    }
}

struct ConfigStatusSection: View {
    @ObservedObject var kanataManager: KanataViewModel // Phase 4: MVVM
    @State private var configValidation: (isValid: Bool, errors: [String]) = (true, [])
    @State private var showConfigContent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configuration")
                .font(.headline)
                .foregroundColor(.primary)

            HStack(spacing: 12) {
                Image(systemName: configValidation.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(configValidation.isValid ? .green : .red)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(configValidation.isValid ? "Configuration is valid" : "Configuration has errors")
                        .font(.body)
                        .fontWeight(.medium)
                }

                Spacer()

                Button("Validate") {
                    validateConfig()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if !configValidation.isValid {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)

                        Text("Configuration Errors:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(configValidation.errors, id: \.self) { error in
                            Text("• \(error)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.leading, 20)

                    Button("Reset to Default") {
                        Task {
                            do {
                                try await kanataManager.resetToDefaultConfig()
                                validateConfig()

                                // Show success toast
                                await MainActor.run {
                                    NotificationCenter.default.post(
                                        name: NSNotification.Name("ShowUserFeedback"),
                                        object: nil,
                                        userInfo: ["message": "Configuration reset to default"]
                                    )
                                }
                            } catch {
                                // Show error toast
                                await MainActor.run {
                                    NotificationCenter.default.post(
                                        name: NSNotification.Name("ShowUserFeedback"),
                                        object: nil,
                                        userInfo: ["message": "❌ Failed to reset: \(error.localizedDescription)"]
                                    )
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.top, 8)
            }

            // Show config content section
            Divider()
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Button(action: { showConfigContent.toggle() }, label: {
                    HStack {
                        Image(systemName: showConfigContent ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(showConfigContent ? "Hide Configuration" : "Show Configuration")
                            .font(.subheadline)
                    }
                })
                .buttonStyle(.plain)

                if showConfigContent {
                    if let configContent = try? String(contentsOfFile: kanataManager.configPath, encoding: .utf8) {
                        ScrollView {
                            Text(configContent)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 200)
                        .padding(12)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                        )
                    }
                }
            }
        }
        .padding(16)
        .appGlassCard()
        .onAppear {
            validateConfig()
        }
    }

    private func validateConfig() {
        Task {
            let result = await kanataManager.validateConfigFile()
            await MainActor.run {
                configValidation = result
            }
        }
    }
}

struct LogAccessSection: View {
    let onOpenKeyPathLogs: () -> Void
    let onOpenKanataLogs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Logs")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(spacing: 8) {
                Button(action: onOpenKeyPathLogs) {
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundColor(.blue)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("KeyPath Logs")
                                .font(.body)
                                .fontWeight(.medium)

                            Text("Application debug logs and events")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .appGlassCard()
                }
                .buttonStyle(.plain)

                Button(action: onOpenKanataLogs) {
                    HStack {
                        Image(systemName: "terminal")
                            .foregroundColor(.green)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kanata Logs")
                                .font(.body)
                                .fontWeight(.medium)

                            Text("Kanata service logs and errors")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .appGlassCard()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .appGlassCard()
    }
}

struct EnhancedStatusSection: View {
    @ObservedObject var kanataManager: KanataViewModel // Phase 4: MVVM
    @State private var kanataVersion: String = "Unknown"
    @State private var codeSignature: String = "Unknown"
    @State private var canonicalPath: String = "Unknown"
    @State private var inode: String = "Unknown"
    @State private var launchDaemonState: String = "Unknown"
    @State private var lastExitStatus: String = "Unknown"
    @State private var axProbeResult: (Bool, Date) = (false, Date())
    @State private var imProbeResult: (Bool, Date) = (false, Date())
    @State private var isLoading = false
    @State private var showExpandedDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System Status")
                .font(.headline)
                .foregroundColor(.primary)

            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Collecting system info…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    // Kanata Binary Info
                    SystemInfoRow(label: "Kanata Version", value: kanataVersion, icon: "hammer")
                    SystemInfoRow(label: "Code Signature", value: codeSignature, icon: "checkmark.seal")
                    SystemInfoRow(label: "Binary Path", value: canonicalPath, icon: "folder")
                    SystemInfoRow(label: "File ID", value: inode, icon: "number")

                    Divider()
                        .padding(.vertical, 4)

                    // LaunchDaemon Status
                    SystemInfoRow(label: "Daemon State", value: launchDaemonState, icon: "gear")
                    SystemInfoRow(label: "Last Exit", value: lastExitStatus, icon: "arrow.right.circle")

                    Divider()
                        .padding(.vertical, 4)

                    // Permission Probe Results
                    ProbeStatusRow(
                        label: "Accessibility",
                        result: axProbeResult.0,
                        timestamp: axProbeResult.1,
                        icon: "accessibility"
                    )
                    ProbeStatusRow(
                        label: "Input Monitoring",
                        result: imProbeResult.0,
                        timestamp: imProbeResult.1,
                        icon: "eye"
                    )
                }

                HStack {
                    Button("Refresh Status") {
                        Task {
                            await refreshSystemStatus()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Button(showExpandedDetails ? "Hide Details" : "Show Raw Data") {
                        showExpandedDetails.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }

                if showExpandedDetails {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Raw System Data:")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.bottom, 2)

                            Text("Binary Path: \(canonicalPath)")
                            Text("Inode: \(inode)")
                            Text("Code Signature: \(codeSignature)")
                            Text("LaunchDaemon: \(launchDaemonState)")
                            Text("Exit Status: \(lastExitStatus)")
                            Text("AX Check: \(String(describing: axProbeResult.0)) at \(axProbeResult.1.formatted(date: .omitted, time: .shortened))")
                            Text("IM Check: \(String(describing: imProbeResult.0)) at \(imProbeResult.1.formatted(date: .omitted, time: .shortened))")
                        }
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
        .onAppear {
            Task {
                await refreshSystemStatus()
            }
        }
    }

    private func refreshSystemStatus() async {
        isLoading = true

        // Get canonical path and inode
        let kanataBinaryPath = WizardSystemPaths.kanataActiveBinary
        canonicalPath = kanataBinaryPath

        if FileManager.default.fileExists(atPath: kanataBinaryPath) {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: kanataBinaryPath)
                if let inodeNumber = attributes[.systemFileNumber] as? UInt64 {
                    inode = String(inodeNumber)
                }
            } catch {
                inode = "Error: \(error.localizedDescription)"
            }
        } else {
            inode = "File not found"
        }

        // Get Kanata version
        await getKanataVersion()

        // Get code signature
        await getCodeSignature()

        // Get LaunchDaemon state
        await getLaunchDaemonState()

        // Probe permissions
        await probePermissions()

        await MainActor.run {
            isLoading = false
        }
    }

    private func getKanataVersion() async {
        let process = Process()
        let pipe = Pipe()

        process.launchPath = canonicalPath
        process.arguments = ["--version"]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                await MainActor.run {
                    kanataVersion = output.isEmpty ? "Unknown" : output
                }
            }
        } catch {
            await MainActor.run {
                kanataVersion = "Error: \(error.localizedDescription)"
            }
        }
    }

    private func getCodeSignature() async {
        let process = Process()
        let pipe = Pipe()

        process.launchPath = "/usr/bin/codesign"
        process.arguments = ["-dv", "--verbose=2", canonicalPath]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Extract Team ID or Authority from codesign output
                let lines = output.components(separatedBy: .newlines)
                for line in lines where line.contains("Authority=") {
                    let authority = line.components(separatedBy: "Authority=").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"
                    await MainActor.run {
                        codeSignature = authority
                    }
                    return
                }
                await MainActor.run {
                    codeSignature = "Signed but no authority found"
                }
            }
        } catch {
            await MainActor.run {
                codeSignature = "Error: \(error.localizedDescription)"
            }
        }
    }

    private func getLaunchDaemonState() async {
        let process = Process()
        let pipe = Pipe()

        process.launchPath = "/bin/launchctl"
        process.arguments = ["print", "system/com.keypath.kanata"]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                if output.contains("state = running") {
                    await MainActor.run {
                        launchDaemonState = "loaded/running"
                    }
                } else if output.contains("state = ") {
                    let state = output.components(separatedBy: "state = ").dropFirst().first?.components(separatedBy: "\n").first ?? "unknown"
                    await MainActor.run {
                        launchDaemonState = "loaded/\(state)"
                    }
                } else {
                    await MainActor.run {
                        launchDaemonState = "not loaded"
                    }
                }

                // Extract last exit status
                if let exitMatch = output.range(of: "last exit code = (\\d+)", options: .regularExpression) {
                    let exitCode = String(output[exitMatch]).components(separatedBy: " = ").last?.replacingOccurrences(of: ")", with: "") ?? "unknown"
                    await MainActor.run {
                        lastExitStatus = exitCode
                    }
                } else {
                    await MainActor.run {
                        lastExitStatus = "none"
                    }
                }
            }
        } catch {
            await MainActor.run {
                launchDaemonState = "Error: \(error.localizedDescription)"
                lastExitStatus = "Error"
            }
        }
    }

    private func probePermissions() async {
        let timestamp = Date()
        let snapshot = await PermissionOracle.shared.currentSnapshot()
        await MainActor.run {
            axProbeResult = (snapshot.keyPath.accessibility.isReady, timestamp)
            imProbeResult = (snapshot.keyPath.inputMonitoring.isReady, timestamp)
        }
    }
}

struct SystemInfoRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 16)

            Text(label + ":")
                .font(.caption)
                .fontWeight(.medium)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer()
        }
    }
}

struct ProbeStatusRow: View {
    let label: String
    let result: Bool
    let timestamp: Date
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 16)

            Text(label + ":")
                .font(.caption)
                .fontWeight(.medium)
                .frame(width: 120, alignment: .leading)

            HStack(spacing: 4) {
                Circle()
                    .fill(result ? Color.green : Color.red)
                    .frame(width: 6, height: 6)

                Text(result ? "Granted" : "Denied")
                    .font(.caption)
                    .foregroundColor(result ? .green : .red)

                Text("(\(timestamp.formatted(date: .omitted, time: .shortened)))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - Verbose Logging Section

struct VerboseLoggingSection: View {
    @State private var verboseLogging = PreferencesService.shared.verboseKanataLogging
    @State private var showingRestartAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagnostic Logging")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $verboseLogging) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Verbose Kanata Logging")
                            .font(.body)
                            .fontWeight(.medium)

                        Text("Enable comprehensive trace logging with event timing (requires service restart)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: verboseLogging) { _, newValue in
                    Task { @MainActor in
                        PreferencesService.shared.verboseKanataLogging = newValue
                        showingRestartAlert = true
                    }
                }

                if verboseLogging {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)

                        Text("Trace logging generates large log files. Use for debugging key repeat or performance issues only.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding(12)
            .appGlassCard()
        }
        .alert("Service Restart Required", isPresented: $showingRestartAlert) {
            Button("Later", role: .cancel) {}
            Button("Restart Now") {
                Task {
                    await restartKanataService()
                }
            }
        } message: {
            Text("Kanata needs to restart for the new logging setting to take effect. Would you like to restart now?")
        }
    }

    private func restartKanataService() async {
        AppLogger.shared.log("🔄 [VerboseLogging] Restarting Kanata service with new logging flags")
        // Post notification to trigger service restart
        NotificationCenter.default.post(name: .retryStartService, object: nil)
    }
}

#Preview {
    let manager = KanataManager()
    let viewModel = KanataViewModel(manager: manager)
    DiagnosticsView(kanataManager: viewModel)
        .frame(width: 600, height: 800)
}
