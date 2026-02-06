import SwiftUI

/// View for displaying activity reports
struct ActivityReportView: View {
    @Binding var isPresented: Bool
    @State private var selectedPeriod: ReportPeriod = .daily
    @State private var report: ActivityReport?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Activity Report")
                    .font(.headline)

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("activity-report-close-button")
            }
            .padding()

            Divider()

            // Period picker
            Picker("Period", selection: $selectedPeriod) {
                ForEach(ReportPeriod.allCases, id: \.self) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .accessibilityIdentifier("activity-report-period-picker")

            // Content
            if isLoading {
                Spacer()
                ProgressView("Loading...")
                Spacer()
            } else if let report {
                reportContent(report)
            } else {
                Spacer()
                Text("No data available")
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .frame(width: 500, height: 600)
        .onAppear {
            loadReport()
        }
        .onChange(of: selectedPeriod) { _, _ in
            loadReport()
        }
    }

    private func reportContent(_ report: ActivityReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary
                HStack {
                    StatCard(
                        title: "Total Events",
                        value: "\(report.totalEvents)",
                        icon: "chart.bar"
                    )
                    StatCard(
                        title: "Apps Used",
                        value: "\(report.appUsage.count)",
                        icon: "app.badge"
                    )
                    StatCard(
                        title: "Shortcuts",
                        value: "\(report.topShortcuts.count)",
                        icon: "keyboard"
                    )
                }
                .accessibilityIdentifier("activity-report-summary")

                // App Usage
                if !report.appUsage.isEmpty {
                    ReportSection(title: "Top Apps", icon: "app.badge") {
                        ForEach(report.appUsage.prefix(10)) { app in
                            HStack {
                                Text(app.appName)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(app.switchCount) switches")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .accessibilityIdentifier("activity-report-apps-section")
                }

                // Top Shortcuts
                if !report.topShortcuts.isEmpty {
                    ReportSection(title: "Top Shortcuts", icon: "keyboard") {
                        ForEach(report.topShortcuts.prefix(10)) { shortcut in
                            HStack {
                                Text(shortcut.shortcut)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                Text("\(shortcut.count)x")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .accessibilityIdentifier("activity-report-shortcuts-section")
                }

                // KeyPath Actions
                if !report.keyPathActions.isEmpty {
                    ReportSection(title: "KeyPath Actions", icon: "bolt") {
                        ForEach(report.keyPathActions.prefix(10)) { action in
                            HStack {
                                Text(action.displayString)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(action.count)x")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .accessibilityIdentifier("activity-report-actions-section")
                }
            }
            .padding()
        }
    }

    private func loadReport() {
        isLoading = true
        Task { @MainActor in
            report = await ActivityReportGenerator.shared.generateReport(for: selectedPeriod)
            isLoading = false
        }
    }
}

// MARK: - Helper Views

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

private struct ReportSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)
        }
    }
}

#Preview {
    ActivityReportView(isPresented: .constant(true))
}
