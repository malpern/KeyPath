import KeyPathCore

enum KeyboardStageRendererBackend: Equatable, Sendable {
    case swiftUI
    case metal
}

struct KeyboardStageRendererPolicy: Equatable, Sendable {
    var preference: KeyboardStageRendererPreference
    var displayMode: KeyboardStageDisplayMode
    var metalAvailable: Bool
    var metalFailed: Bool

    var backend: KeyboardStageRendererBackend {
        guard !displayMode.reduceMotion, metalAvailable, !metalFailed else {
            return .swiftUI
        }

        switch preference {
        case .swiftUI:
            return .swiftUI
        case .automatic, .metal:
            return .metal
        }
    }

    static func effectivePreference(
        requested: KeyboardStageRendererPreference
    ) -> KeyboardStageRendererPreference {
        guard requested == .automatic else { return requested }
        return FeatureFlags.keyboardStageRendererPreference
    }
}
