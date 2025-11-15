import SwiftUI

/// Simple log viewer - shows last N lines with refresh and open buttons
struct SimpleLogViewer: View {
    let logPath: String
    let title: String
    let maxLines: Int = 50

    @State private var logContent: String = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with actions
            HStack {
                Text(title)
                    .font(.headline)

                Spacer()

                // File path (clickable to open in Finder)
                Button(action: openInFinder) {
                    Text(logPath)
                        .font(.caption.monospaced())
                        .foregroundColor(.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .help("Click to open folder in Finder")

                Button(action: refreshLog) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoading)

                Button(action: openInEditor) {
                    Label("Open Full Log", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Log content
            ScrollView {
                if isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loading...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    Text(logContent.isEmpty ? "No logs yet...\nLogs will appear here when KeyPath runs." : logContent)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(logContent.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                }
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .onAppear {
            loadLog()
        }
    }

    private func loadLog() {
        isLoading = true
        Task {
            let content = await loadLogContent()
            await MainActor.run {
                logContent = content
                isLoading = false
            }
        }
    }

    private func refreshLog() {
        loadLog()
    }

    private func loadLogContent() async -> String {
        // Run file reading off main thread
        await Task.detached {
            guard let content = try? String(contentsOfFile: logPath, encoding: .utf8) else {
                return "Log file not found at: \(logPath)"
            }

            let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

            // Show last N lines
            if lines.count > maxLines {
                let recentLines = lines.suffix(maxLines)
                return "... (showing last \(maxLines) lines) ...\n\n" + recentLines.joined(separator: "\n")
            } else {
                return content
            }
        }.value
    }

    private func openInFinder() {
        // Open the containing folder in Finder and select the log file
        let folderPath = (logPath as NSString).deletingLastPathComponent
        NSWorkspace.shared.selectFile(logPath, inFileViewerRootedAtPath: folderPath)
    }

    private func openInEditor() {
        // Try common editors in order of preference
        let editors = [
            // Zed (fast, modern)
            ("/usr/local/bin/zed", [logPath]),
            ("/opt/homebrew/bin/zed", [logPath]),
            // VSCode
            ("/usr/local/bin/code", [logPath]),
            ("/opt/homebrew/bin/code", [logPath]),
            // Sublime
            ("/usr/local/bin/subl", [logPath]),
            // Vim/Neovim in terminal
            ("/usr/bin/open", ["-a", "Terminal", logPath])
        ]

        for (editorPath, args) in editors {
            if FileManager.default.fileExists(atPath: editorPath) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: editorPath)
                process.arguments = args
                try? process.run()
                return
            }
        }

        // Fallback: open with default text editor
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }
}
