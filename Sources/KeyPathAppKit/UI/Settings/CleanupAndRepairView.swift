import SwiftUI

/// Simple UI to run helper cleanup/repair and show step-by-step logs.
struct CleanupAndRepairView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var maintenance = HelperMaintenance.shared
    @StateObject private var errorMonitor = KanataErrorMonitor.shared
    @State private var started = false
    @State private var succeeded = false
    @State private var useAppleScriptFallback = true
    @State private var duplicateCopies: [String] = []
    @State private var selectedTab: DiagnosticTab = .cleanup
    @State private var helperHealth: HelperManager.HealthState?
    @State private var simulatorAndVirtualKeysEnabled = FeatureFlags.simulatorAndVirtualKeysEnabled

    enum DiagnosticTab: String, CaseIterable {
        case cleanup = "Cleanup & Repair"
        case errors = "Kanata Errors"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diagnostics & Repair")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Close") { dismiss() }
                    .accessibilityIdentifier("cleanup-repair-close-button")
                    .accessibilityLabel("Close")
            }
            .padding(.bottom, 4)

            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(DiagnosticTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("cleanup-repair-tab-picker")
            .accessibilityLabel("Diagnostic tab")

            // Tab content
            if selectedTab == .cleanup {
                cleanupTabContent
            } else {
                errorsTabContent
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 360)
        .onAppear {
            duplicateCopies = HelperMaintenance.shared.detectDuplicateAppCopies()
            errorMonitor.markAllAsRead() // Mark errors as read when viewing diagnostics
            simulatorAndVirtualKeysEnabled = FeatureFlags.simulatorAndVirtualKeysEnabled
            refreshHelperHealth()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showErrorsTab)) { _ in
            selectedTab = .errors
        }
    }

    // MARK: - Cleanup Tab Content

    @ViewBuilder
    private var cleanupTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            helperHealthCard

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Enable Simulator + Virtual Keys", isOn: Binding(
                    get: { simulatorAndVirtualKeysEnabled },
                    set: { newValue in
                        simulatorAndVirtualKeysEnabled = newValue
                        FeatureFlags.setSimulatorAndVirtualKeysEnabled(newValue)
                    }
                ))
                .font(.system(size: 12))
                .accessibilityIdentifier("cleanup-repair-simulator-toggle")
                .accessibilityLabel("Enable Simulator + Virtual Keys")
                Text("Gates the simulator UI, overlay mapping via simulator, and virtual key actions.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Text(
                "This will unregister the helper, remove stale artifacts, and re-register it from /Applications/KeyPath.app. You may be prompted for an administrator password."
            )
            .font(.system(size: 12))
            .foregroundColor(.secondary)

            // Duplicate copies hint + reveal
            if duplicateCopies.count > 1 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(.orange)
                    Text("Multiple KeyPath.app copies detected. Remove extras to avoid stale approvals.")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                    Spacer()
                    Button("Reveal Copies") {
                        for p in duplicateCopies {
                            let url = URL(fileURLWithPath: p)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                    .accessibilityIdentifier("cleanup-repair-reveal-copies-button")
                    .accessibilityLabel("Reveal duplicate copies")
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(maintenance.logLines.indices, id: \.self) { idx in
                        Text(maintenance.logLines[idx])
                            .font(.system(.footnote, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
            .frame(minHeight: 220)

            Toggle("Use Admin Prompt Fallback (AppleScript)", isOn: $useAppleScriptFallback)
                .font(.system(size: 12))
                .accessibilityIdentifier("cleanup-repair-applescript-toggle")
                .accessibilityLabel("Use Admin Prompt Fallback")

            HStack {
                if maintenance.isRunning {
                    ProgressView().scaleEffect(0.8)
                }
                if started, !maintenance.isRunning {
                    Image(systemName: succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(succeeded ? .green : .red)
                }
                Spacer()
                Button(maintenance.isRunning ? "Working…" : "Run Cleanup") {
                    Task {
                        started = true
                        succeeded = await maintenance.runCleanupAndRepair(
                            useAppleScriptFallback: useAppleScriptFallback)
                        refreshHelperHealth()
                    }
                }
                .disabled(maintenance.isRunning)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("cleanup-repair-run-button")
                .accessibilityLabel(maintenance.isRunning ? "Working" : "Run Cleanup")
            }
        }
    }

    // MARK: - Errors Tab Content

    @ViewBuilder
    private var errorsTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Health status header
            HStack(spacing: 8) {
                Image(systemName: errorMonitor.healthStatus.icon)
                    .foregroundColor(statusColor)
                    .font(.system(size: 16))

                Text(healthStatusText)
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                if !errorMonitor.recentErrors.isEmpty {
                    Button("Clear All") {
                        errorMonitor.clearErrors()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
                    .accessibilityIdentifier("cleanup-repair-clear-errors-button")
                    .accessibilityLabel("Clear all errors")
                }
            }
            .padding(.vertical, 4)

            Text("Monitoring Kanata stderr for critical errors. Only severe issues are shown here.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            // Error list
            ScrollView {
                if errorMonitor.recentErrors.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                        Text("No errors detected")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("Kanata is running smoothly")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(errorMonitor.recentErrors) { error in
                            errorRow(error)
                        }
                    }
                    .padding(8)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
            .frame(minHeight: 220)

            // Stats footer
            HStack {
                Text("\(errorMonitor.recentErrors.count) errors logged (last 100)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func errorRow(_ error: KanataError) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Severity icon
            Image(systemName: error.severity.icon)
                .foregroundColor(severityColor(error.severity))
                .font(.system(size: 14))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(error.timestampString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)

                    Text(error.severity.rawValue.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(severityColor(error.severity).opacity(0.2))
                        )
                        .foregroundColor(severityColor(error.severity))
                }

                Text(error.message)
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)

                Text(error.rawLine)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch errorMonitor.healthStatus {
        case .healthy: .green
        case .degraded: .orange
        case .critical: .red
        }
    }

    private var healthStatusText: String {
        switch errorMonitor.healthStatus {
        case .healthy: "Healthy"
        case let .degraded(reason): "Warning: \(reason)"
        case let .critical(reason): "Critical: \(reason)"
        }
    }

    private func severityColor(_ severity: KanataErrorSeverity) -> Color {
        switch severity {
        case .critical: .red
        case .warning: .orange
        case .info: .gray
        }
    }

    private var helperHealthCard: some View {
        HStack(spacing: 10) {
            Image(systemName: helperHealthIcon)
                .foregroundColor(helperHealthTint)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text("Helper Health")
                    .font(.system(size: 12, weight: .semibold))
                Text(helperHealthMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Refresh") {
                refreshHelperHealth()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("cleanup-repair-refresh-button")
            .accessibilityLabel("Refresh helper health")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }

    private var helperHealthMessage: String {
        switch helperHealth {
        case .healthy(let version):
            if let version {
                return "Responding via XPC (v\(version))."
            }
            return "Responding via XPC."
        case .requiresApproval(let detail):
            return detail ?? "Approval required in Login Items."
        case .registeredButUnresponsive(let detail):
            return detail ?? "Registered but not responding."
        case .notInstalled:
            return "Not installed or not registered."
        case .none:
            return "Checking helper status…"
        }
    }

    private var helperHealthIcon: String {
        switch helperHealth {
        case .healthy:
            return "checkmark.shield.fill"
        case .requiresApproval:
            return "exclamationmark.triangle.fill"
        case .registeredButUnresponsive, .notInstalled:
            return "xmark.octagon.fill"
        case .none:
            return "ellipsis.circle"
        }
    }

    private var helperHealthTint: Color {
        switch helperHealth {
        case .healthy:
            return .green
        case .requiresApproval:
            return .orange
        case .registeredButUnresponsive, .notInstalled:
            return .red
        case .none:
            return .secondary
        }
    }

    private func refreshHelperHealth() {
        Task {
            let state = await HelperManager.shared.getHelperHealth()
            await MainActor.run {
                helperHealth = state
            }
        }
    }
}
