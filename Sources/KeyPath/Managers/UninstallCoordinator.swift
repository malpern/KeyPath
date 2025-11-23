import AppKit
import Foundation

@MainActor
final class UninstallCoordinator: ObservableObject {
    @Published private(set) var logLines: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var didSucceed = false
    @Published private(set) var lastError: String?

    private let resolveUninstallerURLClosure: () -> URL?
    private let runWithAdminPrivilegesClosure: (URL) async -> AppleScriptResult

    init(
        resolveUninstallerURL: @escaping () -> URL?,
        runWithAdminPrivileges: @escaping (URL) async -> AppleScriptResult
    ) {
        resolveUninstallerURLClosure = resolveUninstallerURL
        runWithAdminPrivilegesClosure = runWithAdminPrivileges
    }

    convenience init() {
        self.init(
            resolveUninstallerURL: Self.defaultResolveUninstallerURL,
            runWithAdminPrivileges: Self.defaultRunWithAdminPrivileges
        )
    }

    @discardableResult
    func uninstall() async -> Bool {
        guard !isRunning else { return false }

        isRunning = true
        didSucceed = false
        lastError = nil
        logLines = ["🗑️ Starting KeyPath uninstall..."]

        defer { isRunning = false }

        guard let scriptURL = resolveUninstallerURLClosure() else {
            let message = "Uninstaller script wasn't found in this build."
            logLines.append("❌ \(message)")
            lastError = message
            return false
        }

        logLines.append("📄 Using uninstaller at: \(scriptURL.path)")

        let result = await runWithAdminPrivilegesClosure(scriptURL)

        if result.success {
            didSucceed = true
            let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !output.isEmpty {
                logLines.append(contentsOf: output.components(separatedBy: "\n"))
            }
            logLines.append("✅ Uninstall completed")
        } else {
            let trimmed = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                logLines.append("❌ \(trimmed)")
                lastError = trimmed
            } else {
                logLines.append("❌ Uninstall failed (error code \(result.exitStatus))")
                lastError = "Uninstall failed with exit code \(result.exitStatus)"
            }
        }

        return result.success
    }

    func copyTerminalCommand() {
        guard let scriptURL = resolveUninstallerURLClosure() else { return }
        let command = "sudo \"\(scriptURL.path)\""
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        logLines.append("📋 Copied command: \(command)")
    }

    func revealUninstallerInFinder() {
        guard let scriptURL = resolveUninstallerURLClosure() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([scriptURL])
    }

    // MARK: - Helpers

    private static func defaultResolveUninstallerURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "uninstall", withExtension: "sh") {
            return bundled
        }

        let repoPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/KeyPath/Resources/uninstall.sh")
        if FileManager.default.isExecutableFile(atPath: repoPath.path) {
            return repoPath
        }

        return nil
    }

    private static func defaultRunWithAdminPrivileges(scriptURL: URL) async -> AppleScriptResult {
        let command = "KEYPATH_UNINSTALL_ASSUME_YES=1 '\(scriptURL.path)' --assume-yes"
        let result = await PrivilegedCommandRunner.runAsync(
            command,
            prompt: "KeyPath needs administrator privileges to uninstall."
        )
        return AppleScriptResult(
            success: result.exitCode == 0,
            output: result.output,
            error: result.exitCode != 0 ? result.output : "",
            exitStatus: result.exitCode
        )
    }
}

struct AppleScriptResult {
    let success: Bool
    let output: String
    let error: String
    let exitStatus: Int32
}
