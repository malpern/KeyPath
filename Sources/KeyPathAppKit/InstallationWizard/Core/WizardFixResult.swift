import Foundation

/// Result of a wizard "Fix" operation.
///
/// Wizard pages should treat `.skipped` as a non-error outcome (e.g. another fix already running).
enum WizardFixResult: Equatable, Sendable {
    case applied
    case skipped(reason: String)
    case failed(reason: String?)
}

