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
    @State private var showTechnicalDetails: Set<UUID> = []
    @State private var isRunningDiagnostics = false
    @State private var showingWizard = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with navigation-style toolbar
            HStack {
                Button("Refresh") {
                    runDiagnostics()
                }
                .disabled(isRunningDiagnostics)
                .buttonStyle(.bordered)

                Spacer()

                Text("Diagnostics")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .appGlassHeader()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Running diagnostics indicator
                    if isRunningDiagnostics {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Running diagnostics...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Process Status
                    ProcessStatusSection(kanataManager: kanataManager)

                    // Enhanced System Status
                    EnhancedStatusSection(kanataManager: kanataManager)

                    // Runtime Diagnostics (process crashes, config errors, etc.)
                    if !kanataManager.diagnostics.isEmpty {
                        DiagnosticSection(
                            title: "Runtime Issues",
                            diagnostics: kanataManager.diagnostics,
                            showTechnicalDetails: $showTechnicalDetails,
                            kanataManager: kanataManager
                        )
                    }

                    // Config File Status
                    ConfigStatusSection(kanataManager: kanataManager)

                    // Log Access Section
                    LogAccessSection(
                        onOpenKeyPathLogs: openKeyPathLogs,
                        onOpenKanataLogs: openKanataLogs
                    )
                }
                .padding(20)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 600, height: 700)
        .onAppear {
            runDiagnostics()
        }
        .sheet(isPresented: $showingWizard) {
            InstallationWizardView()
                .environmentObject(kanataManager)
        }
    }

    private func runDiagnostics() {
        isRunningDiagnostics = true

        Task {
            await MainActor.run {
                systemDiagnostics = []
                isRunningDiagnostics = false
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

struct ProcessStatusSection: View {
    @ObservedObject var kanataManager: KanataViewModel // Phase 4: MVVM

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Process Status")
                .font(.headline)
                .foregroundColor(.primary)

            HStack(spacing: 12) {
                Image(systemName: kanataManager.isRunning ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(kanataManager.isRunning ? .green : .red)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(kanataManager.isRunning ? "Kanata is running" : "Kanata is not running")
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
        }
        .padding(16)
        .appGlassCard()
    }
}

struct PermissionStatusSection: View {
    @ObservedObject var kanataManager: KanataViewModel // Phase 4: MVVM
    let onShowWizard: () -> Void
    @Environment(\.permissionSnapshotProvider) private var permissionProvider
    @State private var snapshot: PermissionOracle.Snapshot?

    var body: some View {
        let inputMonitoring = snapshot?.keyPath.inputMonitoring.isReady ?? false
        let accessibility = snapshot?.keyPath.accessibility.isReady ?? false
        let allPermissions = inputMonitoring && accessibility

        return VStack(alignment: .leading, spacing: 8) {
            Text("Permissions")
                .font(.headline)

            HStack {
                Circle()
                    .fill(allPermissions ? Color.green : Color.red)
                    .frame(width: 8, height: 8)

                Text(allPermissions ? "All permissions granted" : "Missing permissions")
                    .font(.body)

                Spacer()

                if !allPermissions {
                    Button("Open Wizard") {
                        onShowWizard()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            // Show detailed permission status
            if !allPermissions {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle()
                            .fill(inputMonitoring ? Color.green : Color.red)
                            .frame(width: 6, height: 6)
                        Text("Input Monitoring")
                            .font(.caption)
                    }

                    HStack {
                        Circle()
                            .fill(accessibility ? Color.green : Color.red)
                            .frame(width: 6, height: 6)
                        Text("Accessibility")
                            .font(.caption)
                    }
                }
                .padding(.leading, 16)
            }
        }
        .padding()
        .background(allPermissions ? Color.green.opacity(0.05) : Color.red.opacity(0.05))
        .cornerRadius(8)
    }
}

struct DiagnosticSection: View {
    let title: String
    let diagnostics: [KanataDiagnostic]
    @Binding var showTechnicalDetails: Set<UUID>
    @ObservedObject var kanataManager: KanataViewModel // Phase 4: MVVM

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ForEach(diagnostics.indices, id: \.self) { index in
                let diagnostic = diagnostics[index]
                let diagnosticId = UUID() // Create stable ID for this diagnostic

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
                            await kanataManager.autoFixDiagnostic(diagnostic)
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
        VStack(alignment: .leading, spacing: 8) {
            // Main diagnostic info
            HStack {
                Text(diagnostic.severity.emoji)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(diagnostic.title)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(diagnostic.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Category badge
                Text(diagnostic.category.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(categoryColor(diagnostic.category).opacity(0.2))
                    .foregroundColor(categoryColor(diagnostic.category))
                    .cornerRadius(4)
            }

            // Suggested action
            if !diagnostic.suggestedAction.isEmpty {
                Text("💡 \(diagnostic.suggestedAction)")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.leading, 24)
            }

            // Action buttons
            HStack {
                if diagnostic.canAutoFix {
                    Button("Auto Fix") {
                        onAutoFix()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button(showTechnicalDetails ? "Hide Details" : "Show Details") {
                    onToggleTechnicalDetails()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Text(diagnostic.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Technical details (expandable)
            if showTechnicalDetails, !diagnostic.technicalDetails.isEmpty {
                Text(diagnostic.technicalDetails)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Color.secondary)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding()
        .background(severityColor(diagnostic.severity).opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(severityColor(diagnostic.severity).opacity(0.3), lineWidth: 1)
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
                            try? await kanataManager.resetToDefaultConfig()
                            validateConfig()
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
                    if let configContent = try? String(contentsOfFile: kanataManager.configPath) {
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
            Text("Enhanced System Status")
                .font(.headline)
                .foregroundColor(.primary)

            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Gathering system information...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    // Kanata Binary Info
                    SystemInfoRow(label: "Kanata Version", value: kanataVersion, icon: "hammer")
                    SystemInfoRow(label: "Code Signature", value: codeSignature, icon: "checkmark.seal")
                    SystemInfoRow(label: "Canonical Path", value: canonicalPath, icon: "folder")
                    SystemInfoRow(label: "Inode", value: inode, icon: "number")

                    Divider()
                        .padding(.vertical, 4)

                    // LaunchDaemon Status
                    SystemInfoRow(label: "LaunchDaemon State", value: launchDaemonState, icon: "gear")
                    SystemInfoRow(label: "Last Exit Status", value: lastExitStatus, icon: "arrow.right.circle")

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

#Preview {
    let manager = KanataManager()
    let viewModel = KanataViewModel(manager: manager)
    DiagnosticsView(kanataManager: viewModel)
        .frame(width: 600, height: 800)
}
