import Foundation

/// Save operation status for UI feedback
enum SaveStatus: Equatable, Sendable {
    case idle
    case saving
    case validating
    case success
    case failed(String)

    var message: String {
        switch self {
        case .idle: ""
        case .saving: String(localized: "Saving...")
        case .validating: String(localized: "Validating...")
        case .success: String(localized: "✅ Done")
        case let .failed(error): String(localized: "❌ Config Invalid: \(error)")
        }
    }

    var isActive: Bool {
        switch self {
        case .idle, .success: false
        default: true
        }
    }
}
