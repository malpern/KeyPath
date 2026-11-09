import Foundation
import KeyPathCore

/// Finds Kanata processes that are not KeyPath's own.
///
/// KeyPath runs Kanata inside its own user-session worker (the KeyPath
/// executable hosting the Kanata bridge), never as a separate `kanata` binary.
/// So any running `kanata` process belongs to something else, such as a
/// standalone install, and competes with KeyPath for the keyboard.
@MainActor
final class KanataProcessDetector {
    struct ProcessInfo: Sendable, Equatable {
        let pid: pid_t
        let command: String
    }

    struct Conflicts: Sendable {
        let externalProcesses: [ProcessInfo]

        var hasConflicts: Bool {
            !externalProcesses.isEmpty
        }
    }

    private let systemStateProvider: SystemStateProvider

    init(systemStateProvider: SystemStateProvider = .shared) {
        self.systemStateProvider = systemStateProvider
    }

    /// Every running Kanata binary is an external conflict.
    func detectConflicts() async -> Conflicts {
        // Skip process detection in test environment
        if TestEnvironment.shouldSkipAdminOperations {
            return Conflicts(externalProcesses: [])
        }

        let matches = await systemStateProvider.processMatches(matching: "kanata")
        let processes = matches
            .filter { Self.isKanataBinary($0.command) }
            .map { ProcessInfo(pid: $0.pid, command: $0.command) }
        if !processes.isEmpty {
            AppLogger.shared.log(
                "⚠️ [KanataProcessDetector] External Kanata processes: \(processes.map(\.pid))"
            )
        }
        return Conflicts(externalProcesses: processes)
    }

    /// Simple check for actual kanata binaries (not editor plugins, log viewers, etc.)
    static func isKanataBinary(_ command: String) -> Bool {
        // Skip pgrep itself and editor extensions
        if command.contains("pgrep") || command.contains("vscode") || command.contains(".cursor") {
            return false
        }

        // Skip log monitoring and other utilities that contain "kanata" in paths
        if command.contains("tail") || command.contains("cat") || command.contains("grep")
            || command.contains("less") || command.contains("vim") || command.contains("nano")
        {
            return false
        }

        // Check against all known kanata paths (bundled, homebrew, standard locations)
        for path in WizardSystemPaths.allKnownKanataPaths() where command.contains(path) {
            return true
        }

        return command.contains("/bin/kanata") || command.hasPrefix("kanata ") || command == "kanata"
    }
}
