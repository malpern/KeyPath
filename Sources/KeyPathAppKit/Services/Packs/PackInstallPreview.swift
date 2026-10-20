import Foundation
import KeyPathCore
import KeyPathRulesCore

/// What installing a pack would change, decided by the admission engine before
/// anything is written (phase 4c; ADR-039 §5; decision 4).
///
/// One click when nothing the user already has would change; a preview with
/// choices only when a verdict needs one or blocks; automatic resolutions are
/// summarised afterwards.
public struct PackInstallPreview: Sendable {
    public struct Item: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public let severity: AdmissionVerdict.Severity
        public let presentation: AdmissionPresentation
    }

    public let packID: String
    public let items: [Item]
    /// Collections and custom rules the user may turn off to proceed.
    public let disableOptions: [(subject: AdmissionSubject, id: UUID, label: String)]
    /// Installed packs the user may remove to proceed.
    public let removeOptions: [(packID: String, label: String)]

    public var isBlocked: Bool {
        items.contains { $0.severity == .blocking }
    }

    public var needsChoice: Bool {
        items.contains { $0.severity == .needsChoice }
    }

    /// Decision 4: only a choice or a block interrupts a one-click install.
    public var requiresConfirmation: Bool {
        isBlocked || needsChoice
    }

    /// Lines worth showing after a one-click install (automatic resolutions).
    public var summaryLines: [String] {
        items.filter { $0.severity == .automatic }.map(\.presentation.explanation)
    }

    public var blockingItems: [Item] {
        items.filter { $0.severity == .blocking }
    }
}

/// How `PackInstaller.install` applies admission.
public enum PackInstallAdmission: Sendable {
    /// Compute a preview; proceed only if it needs no confirmation, else throw
    /// `InstallError.needsReview`. The UI paths use this.
    case checked
    /// The user reviewed this preview and chose what to turn off or remove.
    case confirmed(disablingCollections: Set<UUID>, disablingRules: Set<UUID>, removingPacks: Set<String>)
    /// Install as before this phase: pack wins silently. For guided onboarding
    /// and programmatic callers that manage their own confirmation.
    case unchecked
}
