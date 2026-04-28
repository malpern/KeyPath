import SwiftUI

@MainActor
struct KindaVimStatusBlock: View {
    @State private var adapter = KindaVimStateAdapter.shared
    @State private var strategyMonitor = KindaVimStrategyMonitor.shared
    @AppStorage("kindaVim.showAdvancedHints") private var showAdvancedHints: Bool = false
    @AppStorage("kindaVim.showHintsInTerminals") private var showHintsInTerminals: Bool = false
    @AppStorage("kindaVim.telemetryEnabled") private var telemetryEnabled: Bool = false

    @State private var appInstalled: Bool = FileManager.default
        .fileExists(atPath: "/Applications/kindaVim.app")
    @State private var showClearTelemetryConfirmation: Bool = false
    @State private var showTerminalInfo: Bool = false

    private static let websiteURL = URL(string: "https://kindavim.app")!

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. Status
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

            if !appInstalled {
                Button("Get KindaVim →") {
                    NSWorkspace.shared.open(Self.websiteURL)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("kindavim-status-get-kindavim")
            }

            // 2. Stats
            Divider()
            telemetrySection

            if telemetryEnabled {
                KindaVimInsightsView()
            }

            // 3. Config
            Divider()
            rightAlignedToggle(
                "Show all keys (advanced)",
                subtitle: "Adds page motions, search, and bracket-match hints.",
                isOn: $showAdvancedHints,
                id: "kindavim-status-show-advanced"
            )

            rightAlignedToggle(
                "Show vim hints in terminal apps",
                subtitle: "Shows keycap hints and mode badge in Kitty, Ghostty, Terminal, iTerm, and other terminals — even when they're in KindaVim's ignore list.",
                isOn: $showHintsInTerminals,
                id: "kindavim-status-show-hints-terminals"
            )

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showTerminalInfo.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(showTerminalInfo ? 90 : 0))
                    Text("Setting up vim mode in Terminal")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("kindavim-status-terminal-info")

            if showTerminalInfo {
                Text("Terminal apps are usually in KindaVim's ignore list. To practice vim motions there, add `bindkey -v` to your ~/.zshrc to enable zsh's built-in vi mode, then turn on \"Show vim hints in terminal apps\" above.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 15)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()
            Text(
                "This pack adds no remappings. KindaVim itself handles every keypress; KeyPath just shows you the current mode in the overlay."
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
        rightAlignedToggle(
            "Record local KindaVim usage stats",
            subtitle: "Used by KeyPath to show you which vim commands you use most. This data stays on your Mac and is never sent anywhere.",
            isOn: $telemetryEnabled,
            id: "kindavim-status-telemetry-toggle"
        )

        if telemetryEnabled {
            Button(role: .destructive) {
                showClearTelemetryConfirmation = true
            } label: {
                Label("Clear all usage data…", systemImage: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("kindavim-status-clear-telemetry")
        }
    }

    private func rightAlignedToggle(
        _ title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        id: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .accessibilityIdentifier(id)
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
