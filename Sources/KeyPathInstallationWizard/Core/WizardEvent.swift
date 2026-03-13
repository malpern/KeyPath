import Foundation

/// Lightweight structured event for wizard observability (in-memory only).
public struct WizardEvent: Codable, Equatable, Sendable {
    public enum Category: String, Codable, Sendable {
        case autofixer
        case permission
        case navigation
        case health
        case statusBanner
        case uninstall
    }

    public let timestamp: Date
    public let category: Category
    public let name: String
    public let result: String?
    public let details: [String: String]?
}
