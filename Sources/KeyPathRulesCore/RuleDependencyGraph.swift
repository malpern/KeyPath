import Foundation

/// A canonical layer identifier used by rule dependency capabilities.
///
/// Layer names are open-ended because custom rules and packs can introduce
/// them. Canonicalizing at this boundary prevents equivalent Kanata layer names
/// such as `FUN` and ` fun ` from producing different graph nodes.
///
/// Raw Kanata syntax is case-sensitive, but KeyPath's `RuleCollectionLayer`
/// model and layer-creation path lowercase custom layer names before config
/// generation. This type represents those canonical KeyPath layer names, not
/// arbitrary identifiers parsed from an external Kanata configuration.
public struct RuleLayerIdentifier: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public init(_ layer: RuleCollectionLayer) {
        self.init(rawValue: layer.kanataName)
    }
}

/// Named aliases that one rule can expose for another rule to consume.
public enum RuleKeyAlias: String, Hashable, Sendable {
    case hyper
}

/// A typed unit of rule behavior that can be provided or required.
public enum RuleCapability: Hashable, Sendable {
    /// A layer contains useful mappings or generated behavior.
    case layerContent(RuleLayerIdentifier)

    /// A functional path reaches or activates a layer.
    case layerActivation(RuleLayerIdentifier)

    /// A named alias is defined with the expected behavior.
    case keyAlias(RuleKeyAlias)
}

/// Structured context explaining why a rule requires a capability.
///
/// This is deliberately presentation-free. Later UI can format the same
/// evidence differently for dialogs, accessibility, CLI output, or diagnostics.
public enum RuleDependencyEvidence: Hashable, Sendable {
    case keys([String])
    case layerPath(source: RuleLayerIdentifier, target: RuleLayerIdentifier)
    case configuration(field: String, value: String)
    case mappingIDs([UUID])

    fileprivate var normalized: Self {
        switch self {
        case let .keys(keys):
            .keys(Array(Set(keys)).sorted())
        case let .layerPath(source, target):
            .layerPath(
                source: RuleLayerIdentifier(source.rawValue),
                target: RuleLayerIdentifier(target.rawValue)
            )
        case let .configuration(field, value):
            .configuration(field: field, value: value)
        case let .mappingIDs(ids):
            .mappingIDs(Array(Set(ids)).sorted(by: Self.uuidLessThan))
        }
    }

    fileprivate var stableSortKey: String {
        switch self {
        case let .keys(keys):
            "0|\(keys.joined(separator: "\u{1F}"))"
        case let .layerPath(source, target):
            "1|\(source.rawValue)|\(target.rawValue)"
        case let .configuration(field, value):
            "2|\(field)|\(value)"
        case let .mappingIDs(ids):
            "3|\(ids.map(\.uuidString).joined(separator: "|"))"
        }
    }

    private static func uuidLessThan(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}

/// A capability requirement plus the configuration evidence that created it.
public struct RuleRequirement: Hashable, Sendable {
    public let capability: RuleCapability
    public let evidence: Set<RuleDependencyEvidence>

    public init(
        capability: RuleCapability,
        evidence: Set<RuleDependencyEvidence> = []
    ) {
        self.capability = capability
        self.evidence = evidence
    }

    /// Evidence in deterministic order for query and presentation adapters.
    public var sortedEvidence: [RuleDependencyEvidence] {
        evidence.sorted { $0.stableSortKey < $1.stableSortKey }
    }

    fileprivate var normalized: Self {
        RuleRequirement(
            capability: capability,
            evidence: Set(evidence.map(\.normalized))
        )
    }

    fileprivate var stableSortKey: String {
        let evidenceKey = sortedEvidence
            .map(\.stableSortKey)
            .joined(separator: "\u{1E}")
        return "\(capability.stableSortKey)|\(evidenceKey)"
    }
}

/// One collection's dependency contribution to a graph snapshot.
///
/// Family-specific extraction from `RuleCollection` intentionally lives in an
/// app-layer adapter. Keeping this input generic makes the graph independently
/// testable and reusable by future import, pack, and CLI validation paths.
///
/// Enabled state is intentionally not part of a contribution. Independent
/// extractors may emit multiple contributions for one collection, while
/// enabled state has exactly one collection-wide source of truth supplied to
/// the graph builder.
public struct RuleDependencyContribution: Equatable, Sendable {
    public let collectionID: UUID
    public let provides: Set<RuleCapability>
    public let requirements: Set<RuleRequirement>

    public init(
        collectionID: UUID,
        provides: Set<RuleCapability> = [],
        requirements: Set<RuleRequirement> = []
    ) {
        self.collectionID = collectionID
        self.provides = provides
        self.requirements = requirements
    }
}

/// A deterministic snapshot of capabilities across the known rule catalog.
///
/// Lookup indexes retain disabled providers so callers can distinguish
/// "missing now" from "available to enable." The graph is derived data and
/// should be rebuilt whenever the analyzed collection configuration changes.
public struct RuleDependencyGraph: Equatable, Sendable {
    public let enabledCollectionIDs: Set<UUID>
    public let capabilitiesByCollection: [UUID: Set<RuleCapability>]
    public let requirementsByCollection: [UUID: Set<RuleRequirement>]
    public let providersByCapability: [RuleCapability: Set<UUID>]
    public let activeProvidersByCapability: [RuleCapability: Set<UUID>]

    private init(
        enabledCollectionIDs: Set<UUID>,
        capabilitiesByCollection: [UUID: Set<RuleCapability>],
        requirementsByCollection: [UUID: Set<RuleRequirement>],
        providersByCapability: [RuleCapability: Set<UUID>],
        activeProvidersByCapability: [RuleCapability: Set<UUID>]
    ) {
        self.enabledCollectionIDs = enabledCollectionIDs
        self.capabilitiesByCollection = capabilitiesByCollection
        self.requirementsByCollection = requirementsByCollection
        self.providersByCapability = providersByCapability
        self.activeProvidersByCapability = activeProvidersByCapability
    }

    /// Builds a graph in linear time over the supplied contributions and edges.
    ///
    /// Multiple contributions for one collection are merged. This supports
    /// independent extractors without making ordering part of graph semantics.
    /// Enabled state is supplied once per graph snapshot so extractors cannot
    /// disagree about a collection's state.
    public static func build(
        from contributions: [RuleDependencyContribution],
        enabledCollectionIDs: Set<UUID> = []
    ) -> Self {
        var capabilitiesByCollection: [UUID: Set<RuleCapability>] = [:]
        var requirementEvidenceByCollection:
            [UUID: [RuleCapability: Set<RuleDependencyEvidence>]] = [:]
        var providersByCapability: [RuleCapability: Set<UUID>] = [:]

        for contribution in contributions {
            capabilitiesByCollection[contribution.collectionID, default: []]
                .formUnion(contribution.provides)

            for requirement in contribution.requirements.map(\.normalized) {
                requirementEvidenceByCollection[
                    contribution.collectionID,
                    default: [:]
                ][requirement.capability, default: []]
                    .formUnion(requirement.evidence)
            }

            for capability in contribution.provides {
                providersByCapability[capability, default: []]
                    .insert(contribution.collectionID)
            }
        }

        let requirementsByCollection = requirementEvidenceByCollection.mapValues { requirements in
            Set(requirements.map { capability, evidence in
                RuleRequirement(capability: capability, evidence: evidence)
            })
        }

        var activeProvidersByCapability: [RuleCapability: Set<UUID>] = [:]
        activeProvidersByCapability.reserveCapacity(providersByCapability.count)
        for (capability, providers) in providersByCapability {
            let activeProviders = providers.intersection(enabledCollectionIDs)
            if !activeProviders.isEmpty {
                activeProvidersByCapability[capability] = activeProviders
            }
        }

        return RuleDependencyGraph(
            enabledCollectionIDs: enabledCollectionIDs,
            capabilitiesByCollection: capabilitiesByCollection,
            requirementsByCollection: requirementsByCollection,
            providersByCapability: providersByCapability,
            activeProvidersByCapability: activeProvidersByCapability
        )
    }

    /// All known collections in deterministic UUID order.
    public var collectionIDs: [UUID] {
        enabledCollectionIDs
            .union(capabilitiesByCollection.keys)
            .union(requirementsByCollection.keys)
            .sorted(by: Self.uuidLessThan)
    }

    /// All known providers, including disabled collections.
    public func knownProviders(for capability: RuleCapability) -> [UUID] {
        providersByCapability[capability, default: []]
            .sorted(by: Self.uuidLessThan)
    }

    /// Providers enabled in this graph snapshot.
    public func activeProviders(for capability: RuleCapability) -> [UUID] {
        activeProvidersByCapability[capability, default: []]
            .sorted(by: Self.uuidLessThan)
    }

    /// Capabilities contributed by a collection in deterministic order.
    public func capabilitiesProvided(by collectionID: UUID) -> [RuleCapability] {
        capabilitiesByCollection[collectionID, default: []]
            .sorted { $0.stableSortKey < $1.stableSortKey }
    }

    /// Requirements contributed by a collection in deterministic order.
    ///
    /// Contributions requiring the same capability are represented once with
    /// their normalized evidence combined.
    public func requirements(for collectionID: UUID) -> [RuleRequirement] {
        requirementsByCollection[collectionID, default: []]
            .sorted { $0.stableSortKey < $1.stableSortKey }
    }

    private static func uuidLessThan(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}

private extension RuleCapability {
    var stableSortKey: String {
        switch self {
        case let .layerContent(layer):
            "0|\(layer.rawValue)"
        case let .layerActivation(layer):
            "1|\(layer.rawValue)"
        case let .keyAlias(alias):
            "2|\(alias.rawValue)"
        }
    }
}
