import KeyPathCore
import SwiftUI

// MARK: - Script Execution Settings Section

/// Settings section for Script Execution in Quick Launcher
struct ScriptExecutionSettingsSection: View {
    @Bindable private var securityService = ScriptSecurityService.shared
    @State private var showingExecutionLog = false
    @State private var showingEnableConfirmation = false
    @State private var showingBypassConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Script Execution", icon: "terminal", color: .green)
            SettingsToggleRow(
                title: "Allow script execution in Quick Launcher",
                subtitle: "Scripts can run commands on your system. Only enable for trusted scripts.",
                isOn: Binding(get: { securityService.isScriptExecutionEnabled }, set: { newValue in
                    if newValue { showingEnableConfirmation = true }
                    else { securityService.isScriptExecutionEnabled = false }
                }), identifier: "settings-script-execution-toggle"
            )
            .sheet(isPresented: $showingEnableConfirmation) {
                ScriptEnableConfirmationView(
                    onAllow: {
                        showingEnableConfirmation = false
                    },
                    onCancel: {
                        showingEnableConfirmation = false
                    }
                )
            }

            if securityService.isScriptExecutionEnabled {
                SettingsToggleRow(
                    title: "Skip confirmation dialog",
                    subtitle: "⚠️ Scripts will run immediately without warning", subtitleColor: .orange,
                    isOn: Binding(get: { securityService.bypassFirstRunDialog }, set: { newValue in
                        if newValue { showingBypassConfirmation = true }
                        else { securityService.bypassFirstRunDialog = false }
                    }), identifier: "settings-script-bypass-dialog-toggle"
                )
                .padding(.leading, SettingsDesign.sectionGap)
                .sheet(isPresented: $showingBypassConfirmation) {
                    ScriptBypassConfirmationView(
                        onAllow: { showingBypassConfirmation = false },
                        onCancel: { showingBypassConfirmation = false }
                    )
                }

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
    private var securityService = ScriptSecurityService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingClearConfirmation = false

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
                        .font(.largeTitle)
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
                                .font(.footnote.monospaced())
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
                    showingClearConfirmation = true
                }
                .settingsAction()
                .disabled(logEntries.isEmpty)
                .accessibilityIdentifier("settings-script-clear-log-button")
            }
            .padding()
        }
        .frame(width: 500, height: 400)
        .confirmationDialog(
            "Clear the script execution log?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Log", role: .destructive) {
                clearLog()
            }
            .accessibilityIdentifier("settings-script-clear-log-confirm")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("settings-script-clear-log-cancel")
        } message: {
            Text("This permanently deletes the audit history of scripts KeyPath has run. This can't be undone.")
        }
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
