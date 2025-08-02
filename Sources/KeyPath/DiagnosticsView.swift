import SwiftUI

struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var kanataManager: KanataManager
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
            .background(Color(NSColor.controlBackgroundColor))

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
    @ObservedObject var kanataManager: KanataManager

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
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }
}

struct PermissionStatusSection: View {
    @ObservedObject var kanataManager: KanataManager
    let onShowWizard: () -> Void

    var body: some View {
        let inputMonitoring = kanataManager.hasInputMonitoringPermission()
        let accessibility = kanataManager.hasAccessibilityPermission()
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
    @ObservedObject var kanataManager: KanataManager

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
            if showTechnicalDetails && !diagnostic.technicalDetails.isEmpty {
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
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .critical: return .purple
        }
    }

    private func categoryColor(_ category: DiagnosticCategory) -> Color {
        switch category {
        case .configuration: return .blue
        case .permissions: return .orange
        case .process: return .green
        case .system: return .purple
        case .conflict: return .red
        }
    }
}

struct ConfigStatusSection: View {
    @ObservedObject var kanataManager: KanataManager
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
                Button(action: { showConfigContent.toggle() }) {
                    HStack {
                        Image(systemName: showConfigContent ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(showConfigContent ? "Hide Configuration" : "Show Configuration")
                            .font(.subheadline)
                    }
                }
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
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
        .onAppear {
            validateConfig()
        }
    }

    private func validateConfig() {
        configValidation = kanataManager.validateConfigFile()
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
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
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
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }
}

#Preview {
    DiagnosticsView(kanataManager: KanataManager())
        .frame(width: 600, height: 800)
}
