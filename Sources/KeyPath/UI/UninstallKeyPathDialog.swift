import SwiftUI

struct UninstallKeyPathDialog: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var coordinator = UninstallCoordinator()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            guidance
            removalList
            statusFooter
            actions
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 480)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Uninstall KeyPath")
                    .font(.system(size: 22, weight: .bold))
                Text("Remove all LaunchDaemons, helper tools, configs, and the app bundle.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Close") { dismiss() }
        }
    }

    private var guidance: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("This runs KeyPath's bundled uninstaller script with administrator privileges so every file is removed for you.")
            } icon: {
                Image(systemName: "wrench.adjustable")
                    .foregroundColor(.blue)
            }
            .font(.footnote)
        }
    }

    private var removalList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("The uninstaller will:")
                .font(.headline)
            Label("Stop and unload KeyPath LaunchDaemons", systemImage: "bolt.slash")
            Label("Remove helper binaries, plists, and configs from /Library", systemImage: "trash")
            Label("Delete /Applications/KeyPath.app", systemImage: "app.dashed")
            Label("Clear log files and kanata installs", systemImage: "doc.text")
        }
        .labelStyle(.titleAndIcon)
        .font(.subheadline)
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if coordinator.isRunning {
                Label("Running uninstall…", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundColor(.secondary)
            } else if let error = coordinator.lastError, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundColor(.orange)
                    .font(.footnote)
            } else if coordinator.didSucceed {
                Label("All components removed.", systemImage: "checkmark.circle")
                    .foregroundColor(.green)
                    .font(.footnote)
            } else {
                Text("You may be asked for your administrator password once.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    coordinator.copyTerminalCommand()
                } label: {
                    Label("Copy Terminal Command", systemImage: "doc.on.doc")
                }
                Spacer()
            }

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button(role: .destructive) {
                    Task {
                        let success = await coordinator.uninstall()
                        if success {
                            NotificationCenter.default.post(name: .keyPathUninstallCompleted, object: nil)
                            await MainActor.run { dismiss() }
                        }
                    }
                } label: {
                    Label(coordinator.isRunning ? "Working…" : "Uninstall KeyPath", systemImage: "trash")
                }
                .disabled(coordinator.isRunning)
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
