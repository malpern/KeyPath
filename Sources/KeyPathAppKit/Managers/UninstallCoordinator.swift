import AppKit
import Foundation
import KeyPathCore

@MainActor
final class UninstallCoordinator: ObservableObject {
    @Published private(set) var logLines: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var didSucceed = false
    @Published private(set) var lastError: String?

    private let resolveUninstallerURLClosure: () -> URL?
    private let runWithAdminPrivilegesClosure: (URL, Bool) async -> AppleScriptResult

    init(
        resolveUninstallerURL: @escaping () -> URL?,
        runWithAdminPrivileges: @escaping (URL, Bool) async -> AppleScriptResult
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
    func uninstall(deleteConfig: Bool = false) async -> Bool {
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
        if deleteConfig {
            logLines.append("🗑️ User configuration will be deleted")
        } else {
            logLines.append("💾 User configuration will be preserved")
        }

        let result = await runWithAdminPrivilegesClosure(scriptURL, deleteConfig)

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

    private static func defaultRunWithAdminPrivileges(scriptURL: URL, deleteConfig: Bool) async
        -> AppleScriptResult
    {
        // Use PrivilegedCommandRunner which respects TestEnvironment.useSudoForPrivilegedOps
        let configFlag = deleteConfig ? " --delete-config" : ""
        let command = "KEYPATH_UNINSTALL_ASSUME_YES=1 '\(scriptURL.path)' --assume-yes\(configFlag)"
        let result = PrivilegedCommandRunner.execute(
            command: command,
            prompt: "KeyPath needs to uninstall system services."
        )
        return AppleScriptResult(
            success: result.success,
            output: result.output,
            error: result.success ? "" : result.output,
            exitStatus: result.exitCode
        )
    }

    private static func escapeForAppleScript(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

struct AppleScriptResult {
    let success: Bool
    let output: String
    let error: String
    let exitStatus: Int32
}

// NOTE: AppleScriptRunner was removed - now using PrivilegedCommandRunner which respects
// TestEnvironment.useSudoForPrivilegedOps for sudo-based execution in test environments.
