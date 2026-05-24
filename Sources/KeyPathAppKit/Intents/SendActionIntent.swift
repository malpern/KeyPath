import AppIntents
import Foundation

struct SendActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Send KeyPath Action"
    static let description = IntentDescription(
        "Send an action to KeyPath (e.g., launch an app, show a notification, trigger a system action)."
    )

    @Parameter(title: "Action URI", description: "A keypath:// URI or shorthand (e.g., keypath://launch/Obsidian or launch:obsidian)")
    var uri: String

    @MainActor
    func perform() async throws -> some IntentResult {
        var normalized = uri
        if !normalized.hasPrefix("keypath://"), !normalized.contains(":") {
            normalized = "keypath://\(normalized)"
        }
        let result = ActionDispatcher.shared.dispatch(message: normalized)
        switch result {
        case .success:
            return .result()
        case let .unknownAction(action):
            throw ActionError.unknownAction(action)
        case let .missingTarget(action):
            throw ActionError.missingTarget(action)
        case let .failed(action, error):
            throw ActionError.failed(action, error.localizedDescription)
        }
    }

    static let openAppWhenRun: Bool = false

    enum ActionError: Swift.Error, CustomLocalizedStringResourceConvertible {
        case unknownAction(String)
        case missingTarget(String)
        case failed(String, String)

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case let .unknownAction(action):
                "Unknown action: \(action)"
            case let .missingTarget(action):
                "Missing target for action: \(action)"
            case let .failed(action, message):
                "Action '\(action)' failed: \(message)"
            }
        }
    }
}
