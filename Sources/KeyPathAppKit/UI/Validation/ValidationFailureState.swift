import Foundation

/// Normalizes validation failure errors for presentation in the UI.
/// Ensures we always have at least one actionable message and provides
/// copy-ready text for the clipboard.
struct ValidationFailureState: Equatable {
    static let fallbackMessage = "Configuration validation failed, but Kanata did not return any specific error messages."

    /// Sanitized error strings (never empty, trimmed, and deduplicated only when necessary)
    let errors: [String]

    init(rawErrors: [String]) {
        let sanitized = rawErrors
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        errors = sanitized.isEmpty ? [Self.fallbackMessage] : sanitized
    }

    /// Collapses the sanitized errors into a single block for clipboard use
    var copyText: String {
        errors.joined(separator: "\n")
    }
}
