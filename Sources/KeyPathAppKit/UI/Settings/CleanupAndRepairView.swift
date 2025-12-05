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
        }
        .onReceive(NotificationCenter.default.publisher(for: .showErrorsTab)) { _ in
            selectedTab = .errors
        }
    }

    // MARK: - Cleanup Tab Content

    @ViewBuilder
    private var cleanupTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                "This will unregister the helper, remove stale artifacts, and re-register it from /Applications/KeyPath.app. You may be prompted for an administrator password."
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            // Duplicate copies hint + reveal
            if duplicateCopies.count > 1 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Text("Multiple KeyPath.app copies detected. Remove extras to avoid stale approvals.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reveal Copies") {
                        for p in duplicateCopies {
                            let url = URL(fileURLWithPath: p)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
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

            HStack {
                if maintenance.isRunning {
                    ProgressView().scaleEffect(0.8)
                }
                if started, !maintenance.isRunning {
                    Image(systemName: succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(succeeded ? .green : Color.red)
                }
                Spacer()
                Button(maintenance.isRunning ? "Working…" : "Run Cleanup") {
                    Task {
                        started = true
                        succeeded = await maintenance.runCleanupAndRepair(
                            useAppleScriptFallback: useAppleScriptFallback)
                    }
                }
                .disabled(maintenance.isRunning)
                .buttonStyle(.borderedProminent)
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
                    .foregroundStyle(statusColor)
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
                }
            }
            .padding(.vertical, 4)

            Text("Monitoring Kanata stderr for critical errors. Only severe issues are shown here.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            // Error list
            ScrollView {
                if errorMonitor.recentErrors.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)
                        Text("No errors detected")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("Kanata is running smoothly")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func errorRow(_ error: KanataError) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Severity icon
            Image(systemName: error.severity.icon)
                .foregroundStyle(severityColor(error.severity))
                .font(.system(size: 14))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(error.timestampString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Text(error.severity.rawValue.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(severityColor(error.severity).opacity(0.2))
                        )
                        .foregroundStyle(severityColor(error.severity))
                }

                Text(error.message)
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)

                Text(error.rawLine)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
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
}
