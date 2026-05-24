import AppIntents
import AppKit
import Foundation

enum ServiceAction: String, AppEnum {
    case start
    case stop
    case restart

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Service Action")
    static let caseDisplayRepresentations: [ServiceAction: DisplayRepresentation] = [
        .start: "Start",
        .stop: "Stop",
        .restart: "Restart",
    ]
}

struct ServiceControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Control KeyPath Service"
    static let description = IntentDescription("Start, stop, or restart the KeyPath keyboard remapping service.")

    @Parameter(title: "Action")
    var action: ServiceAction

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let delegate = NSApp?.delegate as? AppDelegate,
              let manager = delegate.kanataManager
        else {
            throw ServiceError.appNotRunning
        }

        let success: Bool
        switch action {
        case .start:
            success = await manager.startKanata(reason: "Siri / App Intent")
        case .stop:
            success = await manager.stopKanata(reason: "Siri / App Intent")
        case .restart:
            success = await manager.restartKanata(reason: "Siri / App Intent")
        }

        if success {
            return .result(value: "KeyPath service \(action.rawValue) succeeded.")
        } else {
            throw ServiceError.operationFailed(action.rawValue)
        }
    }

    static let openAppWhenRun: Bool = false

    enum ServiceError: Swift.Error, CustomLocalizedStringResourceConvertible {
        case appNotRunning
        case operationFailed(String)

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .appNotRunning:
                "KeyPath is not running."
            case let .operationFailed(action):
                "Service \(action) failed."
            }
        }
    }
}
