import AppKit
import KeyPathCore

struct SingleInstanceCoordinator {
    struct Candidate: Equatable {
        let pid: pid_t
        let bundleIdentifier: String?
        let isTerminated: Bool
    }

    static func existingInstancePID(
        currentPID: pid_t,
        bundleIdentifier: String,
        candidates: [Candidate]
    ) -> pid_t? {
        candidates
            .filter { candidate in
                candidate.pid != currentPID
                    && candidate.bundleIdentifier == bundleIdentifier
                    && candidate.isTerminated == false
            }
            .map(\.pid)
            .sorted()
            .first
    }

    @MainActor
    @discardableResult
    static func activateExistingAndTerminateIfNeeded(
        bundleIdentifier: String,
        currentPID: pid_t = getpid()
    ) -> Bool {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        let liveApps = runningApps.filter { app in
            app.processIdentifier != currentPID && app.isTerminated == false
        }

        guard
            let existingApp = liveApps
                .sorted(by: { $0.processIdentifier < $1.processIdentifier })
                .first
        else {
            return false
        }

        AppLogger.shared.warn(
            "🪟 [App] Another KeyPath instance is already running (pid=\(existingApp.processIdentifier)); activating it and terminating the new launch"
        )
        let options: NSApplication.ActivationOptions = [.activateAllWindows]
        existingApp.activate(options: options)
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
        return true
    }
}
