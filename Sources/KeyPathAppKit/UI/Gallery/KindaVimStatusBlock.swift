// Custom Pack Detail block for the KindaVim Mode Display pack. Shows
// whether the kindaVim.app companion is installed, the current mode if
// available, and a link to the project's homepage when it isn't.

import SwiftUI

@MainActor
struct KindaVimStatusBlock: View {
    @State private var adapter = KindaVimStateAdapter.shared
    @State private var appInstalled: Bool = FileManager.default
        .fileExists(atPath: "/Applications/kindaVim.app")

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
        .onAppear {
            appInstalled = FileManager.default
                .fileExists(atPath: "/Applications/kindaVim.app")
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
}
