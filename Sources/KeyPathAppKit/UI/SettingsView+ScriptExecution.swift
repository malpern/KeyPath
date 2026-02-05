import KeyPathCore
import SwiftUI

// MARK: - Script Execution Settings Section

/// Settings section for Script Execution in Quick Launcher
struct ScriptExecutionSettingsSection: View {
    @ObservedObject private var securityService = ScriptSecurityService.shared
    @State private var showingExecutionLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .foregroundColor(.green)
                    .font(.body)
                Text("Script Execution")
                    .font(.headline)
                    .foregroundColor(.primary)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow script execution in Quick Launcher")
                        .font(.body)
                        .fontWeight(.medium)
                    Text("Scripts can run commands on your system. Only enable for trusted scripts.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: $securityService.isScriptExecutionEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .accessibilityIdentifier("settings-script-execution-toggle")
            .accessibilityLabel("Allow script execution")

            if securityService.isScriptExecutionEnabled {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Skip confirmation dialog")
                            .font(.body)
                            .fontWeight(.medium)
                        Text("⚠️ Scripts will run immediately without warning")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    Spacer()
                    Toggle("", isOn: $securityService.bypassFirstRunDialog)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(.leading, 24)
                .accessibilityIdentifier("settings-script-bypass-dialog-toggle")
                .accessibilityLabel("Skip script confirmation dialog")

                // Execution log button
                HStack {
                    Button(action: { showingExecutionLog = true }) {
                        Label("View Execution Log", systemImage: "list.bullet.rectangle")
                    }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("settings-script-execution-log-button")

                    Text("(\(securityService.executionLog.count) entries)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 24)
                .padding(.top, 4)
            }
        }
        .sheet(isPresented: $showingExecutionLog) {
            ScriptExecutionLogView()
        }
    }
}

// MARK: - Script Execution Log View

/// Shows the history of script executions for audit purposes
private struct ScriptExecutionLogView: View {
    @ObservedObject private var securityService = ScriptSecurityService.shared
    @Environment(\.dismiss) private var dismiss

    private var logEntries: [(id: Int, path: String, timestamp: String, success: Bool, error: String)] {
        securityService.executionLog.enumerated().reversed().map { index, entry in
            (
                id: index,
                path: entry["path"] as? String ?? "Unknown",
                timestamp: entry["timestamp"] as? String ?? "Unknown",
                success: entry["success"] as? Bool ?? false,
                error: entry["error"] as? String ?? ""
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Script Execution Log")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("settings-script-log-done")
            }
            .padding()

            Divider()

            if logEntries.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No scripts have been executed yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Log entries table
                List(logEntries, id: \.id) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(entry.success ? .green : .red)

                            Text(entry.path)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            Text(formatTimestamp(entry.timestamp))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if !entry.error.isEmpty {
                            Text(entry.error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }

            Divider()

            // Footer with clear button
            HStack {
                Text("\(logEntries.count) entries (max 100)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Clear Log") {
                    clearLog()
                }
                .buttonStyle(.bordered)
                .disabled(logEntries.isEmpty)
                .accessibilityIdentifier("settings-script-clear-log-button")
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }

    private func formatTimestamp(_ iso8601: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso8601) else { return iso8601 }

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .short
        displayFormatter.timeStyle = .medium
        return displayFormatter.string(from: date)
    }

    private func clearLog() {
        UserDefaults.standard.removeObject(forKey: "KeyPath.Security.ScriptExecutionLog")
    }
}
