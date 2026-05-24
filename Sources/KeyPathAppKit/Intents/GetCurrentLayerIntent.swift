import AppIntents
import Foundation

struct GetCurrentLayerIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Current Layer"
    static let description = IntentDescription("Returns the currently active keyboard layer.")

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let layer = await MainActor.run { DistributedNotificationBridge.currentLayer }
        return .result(value: layer)
    }

    static let openAppWhenRun: Bool = false
}
