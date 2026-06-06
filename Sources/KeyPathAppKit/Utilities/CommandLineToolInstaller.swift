import Foundation
import KeyPathCore

enum CommandLineToolInstaller {
    static let linkPath = "/usr/local/bin/keypath-cli"

    enum InstallError: LocalizedError {
        case bundledToolMissing(String)
        case destinationConflict(String)
        case privilegedCommandFailed(String)

        var errorDescription: String? {
            switch self {
            case let .bundledToolMissing(path):
                "The bundled command-line tool was not found at \(path)."
            case let .destinationConflict(path):
                "\(path) already exists and is not a KeyPath command-line tool link."
            case let .privilegedCommandFailed(output):
                output.isEmpty ? "The command-line tool could not be installed." : output
            }
        }
    }

    static var bundledToolPath: String {
        "\(Bundle.main.bundlePath)/Contents/MacOS/keypath-cli"
    }

    static func status() -> String {
        if isInstalled {
            return "Installed at \(linkPath)"
        }
        return "Not installed"
    }

    static var isInstalled: Bool {
        existingLinkDestination() == bundledToolPath
    }

    static func canReplaceExistingDestination() -> Bool {
        let manager = FileManager.default
        guard manager.fileExists(atPath: linkPath) else { return true }
        guard let destination = existingLinkDestination() else { return false }
        return destination.contains("/KeyPath.app/Contents/MacOS/keypath-cli")
    }

    static func install() async throws {
        let toolPath = bundledToolPath
        guard FileManager.default.isExecutableFile(atPath: toolPath) else {
            throw InstallError.bundledToolMissing(toolPath)
        }
        guard canReplaceExistingDestination() else {
            throw InstallError.destinationConflict(linkPath)
        }

        let command = """
        mkdir -p /usr/local/bin
        ln -sfn \(shellSingleQuoted(toolPath)) \(shellSingleQuoted(linkPath))
        """
        let result = PrivilegedCommandRunner.execute(
            command: command,
            prompt: "KeyPath needs to install the keypath-cli command-line tool."
        )
        guard result.success else {
            throw InstallError.privilegedCommandFailed(result.output)
        }
    }

    private static func existingLinkDestination() -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath)
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
