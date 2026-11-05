import KeyPathInstallationWizard

/// What happens when a user upgrading from KeyPath 1.0.1 chooses Remove Old
/// Service (#1353): remove the privileged stack, confirm the refusal cleared on
/// fresh evidence, then start the session runtime.
@MainActor
enum LegacyRuntimeUpgradeFlow {
    enum Outcome: Equatable {
        case removalFailed(String)
        /// Removal verified, yet the refusal's own detector still sees a daemon.
        case stillDetected
        case started(virtualHIDNotice: String?)
        case removedButNotStarted(reason: String?, virtualHIDNotice: String?)

        var message: String {
            switch self {
            case let .removalFailed(reason):
                reason
            case .stillDetected:
                "The old KeyPath service was removed, but KeyPath still detects it. Restart your Mac, then open KeyPath again."
            case let .started(notice):
                Self.join("Old KeyPath service removed. KeyPath is running.", notice)
            case let .removedButNotStarted(reason, notice):
                Self.join("Old KeyPath service removed. \(reason ?? "Turn KeyPath on with the switch above.")", notice)
            }
        }

        var isFailure: Bool {
            switch self {
            case .removalFailed, .stillDetected: true
            case .started, .removedButNotStarted: false
            }
        }

        private static func join(_ message: String, _ notice: String?) -> String {
            notice.map { "\(message) \($0)" } ?? message
        }
    }

    static func run(
        remove: () async -> InstallerEngine.LegacyRuntimeRemovalResult,
        refusalStillStands: () async -> Bool,
        start: () async -> Bool,
        lastError: () -> String?
    ) async -> Outcome {
        let result = await remove()
        guard result.report.success else {
            return .removalFailed(result.report.failureReason ?? "The old KeyPath service could not be removed.")
        }
        if await refusalStillStands() {
            return .stillDetected
        }
        if await start() {
            return .started(virtualHIDNotice: result.virtualHIDNotice)
        }
        return .removedButNotStarted(reason: lastError(), virtualHIDNotice: result.virtualHIDNotice)
    }
}
