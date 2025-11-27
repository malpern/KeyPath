import Foundation

/// Lightweight structured event for wizard observability (in-memory only).
struct WizardEvent: Codable, Equatable {
    enum Category: String, Codable {
        case autofixer
        case permission
        case navigation
        case health
        case statusBanner
        case uninstall
    }

    let timestamp: Date
    let category: Category
    let name: String
    let result: String?
    let details: [String: String]?
}
