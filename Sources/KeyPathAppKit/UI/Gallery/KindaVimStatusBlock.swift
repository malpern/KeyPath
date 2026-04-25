// Custom Pack Detail block for the KindaVim Mode Display pack. Shows
// whether the kindaVim.app companion is installed, the current mode if
// available, and a link to the project's homepage when it isn't.

import SwiftUI

@MainActor
struct KindaVimStatusBlock: View {
    @State private var adapter = KindaVimStateAdapter.shared
    @State private var strategyMonitor = KindaVimStrategyMonitor.shared
    @AppStorage("kindaVim.showAdvancedHints") private var showAdvancedHints: Bool = false
    @AppStorage("kindaVim.telemetryEnabled") private var telemetryEnabled: Bool = false
    @State private var appInstalled: Bool = FileManager.default
        .fileExists(atPath: "/Applications/kindaVim.app")
    @State private var showClearTelemetryConfirmation: Bool = false

    private static let websiteURL = URL(string: "https://kindavim.app")!

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row(
                label: "KindaVim app",
                value: appInstalled ? "Installed" : "Not installed",
                tint: appInstalled ? .green : .orange
            )
            row(
                label: "Current mode",
                value: modeDisplay,
                tint: modeTint
            )
            row(
                label: "Strategy (frontmost app)",
                value: strategyMonitor.currentStrategy.displayName,
                tint: strategyTint
            )
            Divider()
            Toggle(isOn: $showAdvancedHints) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show all keys (advanced)")
                        .font(.system(size: 12, weight: .medium))
                    Text("Adds page motions, search, and bracket-match hints.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityIdentifier("kindavim-status-show-advanced")

            Divider()
            telemetrySection

            if telemetryEnabled {
                Divider()
                KindaVimInsightsView()
            }

            Divider()
            Text(
                "This pack adds no remappings. KindaVim itself handles every keypress; KeyPath just shows you the current mode in the overlay."
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if !appInstalled {
                Button("Get KindaVim →") {
                    NSWorkspace.shared.open(Self.websiteURL)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("kindavim-status-get-kindavim")
            }
        }
        .animation(.easeInOut(duration: 0.35), value: telemetryEnabled)
        .onAppear {
            appInstalled = FileManager.default
                .fileExists(atPath: "/Applications/kindaVim.app")
        }
        .alert("Clear KindaVim usage data?", isPresented: $showClearTelemetryConfirmation) {
            Button("Clear", role: .destructive) {
                KindaVimTelemetryStore.shared.clearAll()
            }
            .accessibilityIdentifier("kindavim-status-clear-telemetry-confirm")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("kindavim-status-clear-telemetry-cancel")
        } message: {
            Text(
                "This permanently deletes all locally-recorded command counts, " +
                "mode dwell time, and other usage statistics. KeyPath has no " +
                "copies of this data — it stays on your Mac and is never sent " +
                "anywhere."
            )
        }
    }

    @ViewBuilder
    private var telemetrySection: some View {
        Toggle(isOn: $telemetryEnabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Record local KindaVim usage stats")
                    .font(.system(size: 12, weight: .medium))
                Text(
                    "Used by KeyPath to show you which vim commands you use " +
                    "most. This data stays on your Mac and is never sent " +
                    "anywhere."
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .accessibilityIdentifier("kindavim-status-telemetry-toggle")

        if telemetryEnabled {
            Button(role: .destructive) {
                showClearTelemetryConfirmation = true
            } label: {
                Text("Clear all KindaVim usage data")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("kindavim-status-clear-telemetry")
        }
    }

    @ViewBuilder
    private func row(label: String, value: String, tint: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
        }
    }

    private var modeDisplay: String {
        let mode = adapter.state.mode
        // We deliberately ignore `isStale` here — kindaVim only writes the
        // environment file on mode transitions, so staleness is the steady
        // state, not a "lost signal" condition.
        if mode == .unknown { return "—" }
        return mode.displayName
    }

    private var modeTint: Color {
        switch adapter.state.mode {
        case .normal: return .green
        case .insert: return .blue
        case .visual: return .orange
        case .operatorPending: return .purple
        case .unknown: return .secondary
        }
    }

    private var strategyTint: Color {
        switch strategyMonitor.currentStrategy {
        case .accessibility: return .green
        case .hybrid: return .blue
        case .keyboard: return .orange
        case .ignored: return .secondary
        }
    }
}
