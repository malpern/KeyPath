import AppKit
import SwiftUI

struct UninstallKeyPathDialog: View {
    @Environment(\.dismiss) private var dismiss
    @State private var deleteConfig = false

    // InstallerEngine façade for uninstall
    private let installerEngine = InstallerEngine()
    private var privilegeBroker: PrivilegeBroker {
        PrivilegeBroker()
    }

    // Local state tracking (replaces UninstallCoordinator's @Published properties)
    @State private var isRunning = false
    @State private var lastError: String?
    @State private var didSucceed = false
    @State private var logLines: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            guidance
            removalList
            configCheckbox
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
                Text(
                    "This runs KeyPath's bundled uninstaller script with administrator privileges so every file is removed for you."
                )
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

    private var configCheckbox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $deleteConfig) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Also delete your configuration")
                        .font(.body)
                    Text("If unchecked, your config will be preserved at ~/.config/keypath")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.checkbox)
        }
        .padding(.vertical, 8)
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isRunning {
                Label("Running uninstall…", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundColor(.secondary)
            } else if let error = lastError, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundColor(.orange)
                    .font(.footnote)
            } else if didSucceed {
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
                    copyTerminalCommand()
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
                        await performUninstall()
                    }
                } label: {
                    Label(isRunning ? "Working…" : "Uninstall KeyPath", systemImage: "trash")
                }
                .disabled(isRunning)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Actions

    private func performUninstall() async {
        guard !isRunning else { return }

        await MainActor.run {
            isRunning = true
            didSucceed = false
            lastError = nil
            logLines = ["🗑️ Starting KeyPath uninstall..."]
        }

        let broker = privilegeBroker
        let report = await installerEngine.uninstall(deleteConfig: deleteConfig, using: broker)

        await MainActor.run {
            isRunning = false
            didSucceed = report.success
            lastError = report.failureReason
            logLines = report.logs

            if report.success {
                NotificationCenter.default.post(name: .keyPathUninstallCompleted, object: nil)
                dismiss()
            }
        }
    }

    private func copyTerminalCommand() {
        // Extract uninstaller script URL (same logic as UninstallCoordinator)
        let scriptURL: URL?
        if let bundled = Bundle.main.url(forResource: "uninstall", withExtension: "sh") {
            scriptURL = bundled
        } else {
            let repoPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources/KeyPath/Resources/uninstall.sh")
            scriptURL = FileManager.default.isExecutableFile(atPath: repoPath.path) ? repoPath : nil
        }

        guard let scriptURL else { return }
        let command = "sudo \"\(scriptURL.path)\""
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)

        logLines.append("📋 Copied command: \(command)")
    }
}
