import KeyPathCore
import SwiftUI

/// Settings section for activity logging configuration
struct ActivityLoggingSettingsSection: View {
    @State private var showOptInSheet = false
    @State private var showResetConfirmation = false
    @State private var showReportSheet = false
    @State private var eventCount: Int = 0
    @State private var isResetting = false

    @MainActor
    private var isEnabled: Bool {
        PreferencesService.shared.activityLoggingEnabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.cyan)
                    .font(.body)
                Text("Activity Logging")
                    .font(.headline)
                    .foregroundColor(.primary)
            }

            // Main toggle row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Track Usage")
                        .font(.body)
                        .fontWeight(.medium)
                    Text(isEnabled ? "\(eventCount) events logged" : "Encrypted local storage")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if isEnabled {
                    Button("Disable") {
                        disableLogging()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("activity-logging-disable-button")
                } else {
                    Button("Enable") {
                        showOptInSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier("activity-logging-enable-button")
                }
            }
            .accessibilityIdentifier("activity-logging-toggle-row")

            // Action buttons when enabled
            if isEnabled {
                HStack(spacing: 12) {
                    Button("View Report") {
                        showReportSheet = true
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .accessibilityIdentifier("activity-logging-view-report-button")

                    Button {
                        showResetConfirmation = true
                    } label: {
                        if isResetting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Reset Data")
                        }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .foregroundColor(.red)
                    .disabled(isResetting)
                    .accessibilityIdentifier("activity-logging-reset-button")
                }
                .padding(.leading, 16)
            }
        }
        .onAppear {
            refreshEventCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: .activityLoggingChanged)) { _ in
            refreshEventCount()
        }
        .sheet(isPresented: $showOptInSheet) {
            ActivityOptInFlow(isPresented: $showOptInSheet)
        }
        .sheet(isPresented: $showReportSheet) {
            ActivityReportView(isPresented: $showReportSheet)
        }
        .alert("Reset Activity Data?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetData()
            }
        } message: {
            Text("This will permanently delete all logged activity data. This action cannot be undone.")
        }
    }

    private func refreshEventCount() {
        Task { @MainActor in
            eventCount = await ActivityLogStorage.shared.totalEventCount()
        }
    }

    private func disableLogging() {
        Task { @MainActor in
            await ActivityLogger.shared.disable()
            PreferencesService.shared.activityLoggingEnabled = false
        }
    }

    private func resetData() {
        isResetting = true
        Task { @MainActor in
            do {
                try await ActivityLogger.shared.resetData()
                PreferencesService.shared.activityLoggingConsentDate = nil
                PreferencesService.shared.activityLoggingEnabled = false
                eventCount = 0
            } catch {
                AppLogger.shared.log("❌ [ActivityLogging] Reset failed: \(error.localizedDescription)")
            }
            isResetting = false
        }
    }
}

#Preview {
    ActivityLoggingSettingsSection()
        .padding()
        .frame(width: 400)
}
