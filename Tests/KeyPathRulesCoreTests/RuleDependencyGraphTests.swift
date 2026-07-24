import Foundation
@testable import KeyPathRulesCore
import XCTest

final class RuleDependencyGraphTests: XCTestCase {
    func testEmptyGraph() {
        let graph = RuleDependencyGraph.build(from: [])

        XCTAssertTrue(graph.enabledCollectionIDs.isEmpty)
        XCTAssertTrue(graph.capabilitiesByCollection.isEmpty)
        XCTAssertTrue(graph.requirementsByCollection.isEmpty)
        XCTAssertTrue(graph.providersByCapability.isEmpty)
        XCTAssertTrue(graph.activeProvidersByCapability.isEmpty)
        XCTAssertTrue(graph.collectionIDs.isEmpty)
    }

    func testActiveProviderIsKnownAndActive() {
        let providerID = uuid(1)
        let functionContent = layerContent("fun")
        let graph = RuleDependencyGraph.build(from: [
            contribution(
                providerID,
                isEnabled: true,
                provides: [functionContent]
            ),
        ])

        XCTAssertEqual(graph.knownProviders(for: functionContent), [providerID])
        XCTAssertEqual(graph.activeProviders(for: functionContent), [providerID])
        XCTAssertEqual(graph.capabilitiesProvided(by: providerID), [functionContent])
    }

    func testDisabledProviderIsKnownButNotActive() {
        let providerID = uuid(1)
        let functionContent = layerContent("fun")
        let graph = RuleDependencyGraph.build(from: [
            contribution(
                providerID,
                isEnabled: false,
                provides: [functionContent]
            ),
        ])

        XCTAssertEqual(graph.knownProviders(for: functionContent), [providerID])
        XCTAssertTrue(graph.activeProviders(for: functionContent).isEmpty)
    }

    func testMultipleProvidersHaveStableOrdering() {
        let firstProviderID = uuid(1)
        let secondProviderID = uuid(2)
        let navigationActivation = layerActivation("nav")
        let graph = RuleDependencyGraph.build(from: [
            contribution(
                secondProviderID,
                isEnabled: false,
                provides: [navigationActivation]
            ),
            contribution(
                firstProviderID,
                isEnabled: true,
                provides: [navigationActivation]
            ),
        ])

        XCTAssertEqual(
            graph.knownProviders(for: navigationActivation),
            [firstProviderID, secondProviderID]
        )
        XCTAssertEqual(
            graph.activeProviders(for: navigationActivation),
            [firstProviderID]
        )
    }

    func testRequirementCanBeMissingWithNoKnownProvider() {
        let consumerID = uuid(1)
        let requirement = RuleRequirement(capability: layerContent("sym"))
        let graph = RuleDependencyGraph.build(from: [
            contribution(
                consumerID,
                isEnabled: true,
                requirements: [requirement]
            ),
        ])

        XCTAssertEqual(graph.requirements(for: consumerID), [requirement])
        XCTAssertTrue(graph.knownProviders(for: requirement.capability).isEmpty)
        XCTAssertTrue(graph.activeProviders(for: requirement.capability).isEmpty)
    }

    func testLayerNamesAreNormalizedAtTheCapabilityBoundary() {
        let providerID = uuid(1)
        let normalizedCapability = layerContent("fun")
        let graph = RuleDependencyGraph.build(from: [
            contribution(
                providerID,
                isEnabled: true,
                provides: [layerContent("  FUN\n")]
            ),
        ])

        XCTAssertEqual(
            graph.knownProviders(for: normalizedCapability),
            [providerID]
        )
        XCTAssertEqual(
            graph.capabilitiesProvided(by: providerID),
            [normalizedCapability]
        )
    }

    func testEvidenceIsPreservedAndNormalizedForStableQueries() throws {
        let consumerID = uuid(1)
        let firstMappingID = uuid(10)
        let secondMappingID = uuid(20)
        let requirement = RuleRequirement(
            capability: layerContent("fun"),
            evidence: [
                .keys([";", "a", "a"]),
                .layerPath(
                    source: RuleLayerIdentifier(" NAV "),
                    target: RuleLayerIdentifier(" FUN ")
                ),
                .configuration(field: "toggleMode", value: "toggle"),
                .mappingIDs([secondMappingID, firstMappingID, secondMappingID]),
            ]
        )
        let graph = RuleDependencyGraph.build(from: [
            contribution(
                consumerID,
                isEnabled: true,
                requirements: [requirement]
            ),
        ])

        let storedRequirement = try XCTUnwrap(
            graph.requirements(for: consumerID).first
        )
        XCTAssertEqual(storedRequirement.capability, layerContent("fun"))
        XCTAssertEqual(
            storedRequirement.sortedEvidence,
            [
                .keys([";", "a"]),
                .layerPath(
                    source: RuleLayerIdentifier("nav"),
                    target: RuleLayerIdentifier("fun")
                ),
                .configuration(field: "toggleMode", value: "toggle"),
                .mappingIDs([firstMappingID, secondMappingID]),
            ]
        )
    }

    func testContributionsForOneCollectionAreMerged() {
        let collectionID = uuid(1)
        let graph = RuleDependencyGraph.build(from: [
            contribution(
                collectionID,
                isEnabled: false,
                provides: [layerContent("fun")]
            ),
            contribution(
                collectionID,
                isEnabled: true,
                provides: [layerActivation("fun")],
                requirements: [
                    RuleRequirement(capability: layerActivation("nav")),
                ]
            ),
        ])

        XCTAssertEqual(graph.collectionIDs, [collectionID])
        XCTAssertEqual(
            graph.capabilitiesProvided(by: collectionID),
            [layerContent("fun"), layerActivation("fun")]
        )
        XCTAssertEqual(
            graph.requirements(for: collectionID),
            [RuleRequirement(capability: layerActivation("nav"))]
        )
        XCTAssertEqual(
            graph.activeProviders(for: layerContent("fun")),
            [collectionID]
        )
    }

    private func contribution(
        _ collectionID: UUID,
        isEnabled: Bool,
        provides: Set<RuleCapability> = [],
        requirements: Set<RuleRequirement> = []
    ) -> RuleDependencyContribution {
        RuleDependencyContribution(
            collectionID: collectionID,
            isEnabled: isEnabled,
            provides: provides,
            requirements: requirements
        )
    }

    private func layerContent(_ name: String) -> RuleCapability {
        .layerContent(RuleLayerIdentifier(name))
    }

    private func layerActivation(_ name: String) -> RuleCapability {
        .layerActivation(RuleLayerIdentifier(name))
    }

    private func uuid(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
    }
}
