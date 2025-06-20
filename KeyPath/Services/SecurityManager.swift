import Foundation
import SwiftUI
import Observation

@Observable
class SecurityManager {
    var isKanataInstalled = false
    var hasConfigAccess = false
    var needsSudoPermission = false

    private let kanataInstaller = KanataInstaller()

    init() {
        checkEnvironment()
    }

    func checkEnvironment() {
        // Check if kanata binary exists
        checkKanataInstallation()

        // Check config access
        switch kanataInstaller.checkKanataSetup() {
        case .success:
            hasConfigAccess = true
        case .failure:
            hasConfigAccess = false
        }
    }

    func forceRefresh() {
        checkEnvironment()
    }

    private func checkKanataInstallation() {
        // Check common installation paths
        let commonPaths = [
            "/usr/local/bin/kanata",
            "/usr/bin/kanata",
            "/opt/homebrew/bin/kanata",
            "/usr/local/sbin/kanata"
        ]

        // First check if it's in common paths
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                print("Kanata found at: \(path)")
                isKanataInstalled = true
                return
            }
        }

        // Then try using 'which' command
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["which", "kanata"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                print("Kanata found at: \(output ?? "unknown")")
                isKanataInstalled = true
            } else {
                isKanataInstalled = false
            }
        } catch {
            print("Error checking for Kanata: \(error)")
            isKanataInstalled = false
        }
    }

    func requestConfirmation(
        for rule: KanataRule,
        completion: @escaping (Bool) -> Void
    ) {
        DispatchQueue.main.async {
            // This will be called from the UI to show confirmation dialog
            completion(true) // For now, auto-confirm - in real app, show dialog
        }
    }

    func canInstallRules() -> Bool {
        return isKanataInstalled && hasConfigAccess
    }

    func getSetupInstructions() -> String {
        var instructions = ""

        if !isKanataInstalled {
            instructions += """
            ## Kanata Not Found

            KeyPath requires Kanata to be installed on your system.

            To install Kanata:
            1. Visit: https://github.com/jtroo/kanata
            2. Download the latest release for macOS
            3. Move the binary to /usr/local/bin/
            4. Make it executable: chmod +x /usr/local/bin/kanata

            """
        }

        if !hasConfigAccess {
            instructions += """
            ## Configuration Setup

            KeyPath will automatically create a Kanata configuration file when you first use it.

            The config will be created at: ~/.config/kanata/kanata.kbd

            """
        }

        if needsSudoPermission {
            instructions += """
            ## Sudo Access Required

            Kanata requires sudo access to intercept keyboard events.

            You'll be prompted for your password when installing rules.

            """
        }

        return instructions
    }
}

struct SecurityConfirmationView: View {
    let rule: KanataRule
    let onConfirm: (Bool) -> Void

    @State private var showDetails = false

    var body: some View {
        VStack(spacing: 20) {
            // Warning icon
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Confirm Rule Installation")
                .font(.title2)
                .fontWeight(.semibold)

            Text("KeyPath will modify your Kanata configuration file to add this remapping rule.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            // Rule preview
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    EnhancedRemapVisualizer(behavior: rule.visualization.behavior)
                        .frame(maxWidth: .infinity)

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("What will be added:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(rule.kanataRule)
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .background(Color(NSColor.quaternaryLabelColor).opacity(0.3))
                            .cornerRadius(6)
                    }
                }
                .padding(8)
            }

            // Warnings
            VStack(alignment: .leading, spacing: 8) {
                Label("A backup of your config will be created", systemImage: "doc.badge.plus")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Label("You may need to enter your password", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Label("Your keyboard will be reloaded", systemImage: "keyboard.badge.ellipsis")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)

            // Actions
            HStack(spacing: 16) {
                Button("Cancel") {
                    onConfirm(false)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                Button("Install Rule") {
                    onConfirm(true)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .frame(width: 450)
    }
}
