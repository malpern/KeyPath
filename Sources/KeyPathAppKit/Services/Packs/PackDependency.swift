import Foundation

/// A dependency that a pack has on another pack.
///
/// Uses string IDs (not enums) so community packs can reference
/// dependencies without compile-time coupling. Config predicates
/// are a serializable enum (not closures) for future JSON manifests.
public struct PackDependency: Codable, Equatable, Sendable {
    /// The pack ID this dependency targets
    public let packID: String

    /// Whether this dependency is required or enhances the pack
    public let kind: DependencyKind

    /// Optional configuration requirement beyond "is enabled"
    public let configPredicate: ConfigPredicate?

    /// Human-readable description shown in UI
    public let description: String

    public init(
        packID: String,
        kind: DependencyKind,
        configPredicate: ConfigPredicate? = nil,
        description: String
    ) {
        self.packID = packID
        self.kind = kind
        self.configPredicate = configPredicate
        self.description = description
    }
}

public enum DependencyKind: String, Codable, Sendable {
    case requires
    case enhancedBy
    case conflictsWith
}

/// Serializable predicates for configuration state checks.
/// New cases can be added as pack configuration grows.
public enum ConfigPredicate: Codable, Equatable, Sendable {
    case holdOutput(String)
    case tapOutput(String)
    case isEnabled
}

/// Result of checking a single dependency
public struct UnmetDependency: Equatable, Sendable {
    public let dependency: PackDependency
    public let reason: UnmetReason

    public enum UnmetReason: Equatable, Sendable {
        case notEnabled
        case configMismatch
    }
}
