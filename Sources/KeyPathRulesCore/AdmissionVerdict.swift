import Foundation

/// Who a verdict is about: the rule, pack or reservation that caused it.
public enum AdmissionSubject: Hashable, Sendable {
    case collection(UUID)
    case customRule(UUID)
    case pack(String)
    /// A party the detector names but no stored rule owns (leader key, a chord
    /// group, an alias pair). Carries the detector's display name.
    case named(String)
}

/// One finding from the admission engine, attributed to its subject.
///
/// Phase 3 of docs/architecture/rules-admission-review.md. Presentation-free:
/// dialogs, the CLI and diagnostics each render the same verdicts.
public struct AdmissionVerdict: Hashable, Sendable {
    public enum Severity: Int, Comparable, Sendable {
        /// Resolved without asking (decision 1: a rule taking the Caps
        /// intermediate key moves the intermediate). Worth a one-line note.
        case automatic
        /// Informational; nothing to choose.
        case advisory
        /// The user must choose (two rules claim one key).
        case needsChoice
        /// Cannot run as written on this backend or Mac.
        case blocking

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public enum Reason: Hashable, Sendable {
        /// Two or more parties claim `key` on `layer`.
        case conflict(key: String, layer: String, parties: [AdmissionSubject])
        /// A need the backend or Mac cannot meet.
        case unmetNeed(RuleEnvironmentNeed)
        /// The rule uses the key reserved as the Caps Lock intermediate.
        case reservedKey(key: String)
        /// Another app already remaps Caps Lock on the chosen keyboard.
        case capsLockHeldByOtherApp(String)
        /// Two installed packs declare `conflictsWith`.
        case packConflict(otherPackID: String, description: String)
    }

    public enum Fix: Hashable, Sendable {
        case disable(AdmissionSubject)
        /// Move the Caps intermediate to one of these free keys (Kanata names).
        case moveCapsIntermediate(candidates: [String])
        case installApp(name: String, path: String)
    }

    public let severity: Severity
    public let subject: AdmissionSubject
    public let reason: Reason
    public let fixes: [Fix]

    public init(severity: Severity, subject: AdmissionSubject, reason: Reason, fixes: [Fix] = []) {
        self.severity = severity
        self.subject = subject
        self.reason = reason
        self.fixes = fixes
    }
}
