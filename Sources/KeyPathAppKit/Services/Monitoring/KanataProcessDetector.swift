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

    /// Whether a process command line is a Kanata binary, not a tool that merely
    /// mentions one (an editor, `tail` of a log, `pgrep`). Decided by the
    /// executable, never by substrings: "/Applications" contains "cat".
    nonisolated static func isKanataBinary(
        _ command: String, knownPaths: [String] = WizardSystemPaths.allKnownKanataPaths()
    ) -> Bool {
        // Known install paths may contain spaces ("Kanata Engine.app"), so match
        // them as a prefix before splitting the command line.
        if knownPaths.contains(where: { command == $0 || command.hasPrefix($0 + " ") }) {
            return true
        }
        guard let executable = command.split(separator: " ", maxSplits: 1).first else { return false }
        return (executable as NSString).lastPathComponent == "kanata"
    }
}
