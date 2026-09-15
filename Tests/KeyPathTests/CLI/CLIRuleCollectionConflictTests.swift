@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import XCTest

/// Regression coverage for the real-world report: with the built-in "Home Row
/// Arrows" collection enabled (it claims `f` on the base layer as a momentary
/// layer activator), `keypath rule add f --tap f --hold lsft --on-conflict
/// replace --apply` reported the rule as created, yet the generated kanata
/// config kept the collection's `layer_home-arrows_f` binding and the custom
/// `beh_base_f` binding never took effect.
///
/// Two separate facts, both verified here:
///  1. `RuleCollectionDeduplicator.detectConflicts` *does* see this collision
///     (activator-vs-mapping, #667), so config generation refuses to build.
///  2. `RulesFacade.addRule` used to persist the rule anyway, because it only
///     ever compared against other custom rules — so the rule was reported as
///     created, could never be applied, and broke every later `apply` until it
///     was removed by hand.
@MainActor
final class CLIRuleCollectionConflictTests: XCTestCase {
    private func homeRowArrows() throws -> RuleCollection {
        let collection = try XCTUnwrap(
            RuleCollectionCatalog().defaultCollections()
                .first { $0.id == RuleCollectionIdentifier.homeRowArrows },
            "Catalog must contain the Home Row Arrows collection"
        )
        XCTAssertEqual(collection.momentaryActivator?.input, "f")
        XCTAssertEqual(collection.momentaryActivator?.sourceLayer, .base)
        return collection
    }

    private func tapHoldF() -> (action: KeyAction, behavior: MappingBehavior) {
        (
            .keystroke(key: "f"),
            .dualRole(DualRoleBehavior(
                tapAction: .keystroke(key: "f"),
                holdAction: .keystroke(key: "lsft"),
                tapTimeout: 200
            ))
        )
    }

    private func makeFacade(
        collections: [RuleCollection]
    ) throws -> (facade: RulesFacade, store: CustomRulesStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kp-rule-conflict-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = CustomRulesStore(fileURL: directory.appendingPathComponent("CustomRules.json"))
        let facade = RulesFacade(store: store, collectionLoader: { collections })
        return (facade, store, directory)
    }

    // MARK: - The collision is real

    func testActivatorVersusCustomRuleIsDetectedAsAConflict() throws {
        var arrows = try homeRowArrows()
        arrows.isEnabled = true
        let rule = CustomRule(
            input: "f", action: tapHoldF().action, behavior: tapHoldF().behavior
        )

        let conflicts = RuleCollectionDeduplicator.detectConflicts(
            in: [rule].asRuleCollections() + [arrows]
        )

        XCTAssertEqual(conflicts.count, 1, "Home Row Arrows' `f` activator collides with a base-layer `f` rule")
        XCTAssertEqual(conflicts.first?.inputKey, "f")
        XCTAssertTrue(
            conflicts.first?.conflictingCollections.contains("Home Row Arrows") ?? false,
            "The conflict must name the collection that owns the key"
        )
    }

    /// The silent drop itself: generation keeps the collection's activator and
    /// discards the custom rule's binding. This is why persisting the rule and
    /// reporting success is wrong — it can never take effect.
    func testGenerationKeepsTheActivatorAndDropsTheCustomBinding() throws {
        var arrows = try homeRowArrows()
        arrows.isEnabled = true
        let rule = CustomRule(
            input: "f", action: tapHoldF().action, behavior: tapHoldF().behavior
        )

        let deduped = RuleCollectionDeduplicator.dedupe([rule].asRuleCollections() + [arrows])
        let config = KanataConfiguration.generateFromCollections(deduped)

        XCTAssertTrue(config.contains("layer_home-arrows_f"), "Collection activator survives")
        XCTAssertFalse(
            config.contains("@beh_base_f"),
            "The custom rule's binding is never referenced by a layer — it has no effect"
        )
    }

    // MARK: - addRule refuses instead of persisting a rule that can never apply

    func testAddRuleRefusesAKeyOwnedByAnEnabledCollection() async throws {
        var arrows = try homeRowArrows()
        arrows.isEnabled = true
        let (facade, store, directory) = try makeFacade(collections: [arrows])
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            _ = try await facade.addRule(
                input: "f", action: tapHoldF().action, behavior: tapHoldF().behavior,
                onConflict: .replace
            )
            XCTFail("addRule must refuse a key an enabled collection already claims")
        } catch let error as CLICollectionConflictError {
            XCTAssertEqual(error.input, "f")
            XCTAssertEqual(
                error.collectionNames, ["Home Row Arrows"],
                "The error names the owning collection only, not the rejected rule itself"
            )
            XCTAssertFalse(error.explanation.isEmpty)
            XCTAssertTrue(
                error.description.contains("Home Row Arrows"),
                "The one-line message must name the collection: \(error.description)"
            )
        }

        let stored = await store.loadRules()
        XCTAssertTrue(stored.isEmpty, "Nothing may be persisted when the rule can never be applied")
    }

    func testAddRuleRefusesAKeyMappedByAnEnabledCollection() async throws {
        let capsCollection = try XCTUnwrap(
            RuleCollectionCatalog().defaultCollections()
                .first { $0.id == RuleCollectionIdentifier.capsLockRemap }
        )
        var enabled = capsCollection
        enabled.isEnabled = true
        let (facade, store, directory) = try makeFacade(collections: [enabled])
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            _ = try await facade.addRule(input: "caps", action: .keystroke(key: "esc"))
            XCTFail("addRule must refuse a key an enabled collection already maps")
        } catch is CLICollectionConflictError {
            // expected
        }
        let stored = await store.loadRules()
        XCTAssertTrue(stored.isEmpty)
    }

    func testAddRuleSkipStrategyNoOpsInsteadOfThrowing() async throws {
        var arrows = try homeRowArrows()
        arrows.isEnabled = true
        let (facade, store, directory) = try makeFacade(collections: [arrows])
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try await facade.addRule(
            input: "f", action: tapHoldF().action, behavior: tapHoldF().behavior,
            onConflict: .skip
        )

        guard case .skipped = result else {
            return XCTFail("--on-conflict=skip must no-op on a collection-owned key, got \(result)")
        }
        let stored = await store.loadRules()
        XCTAssertTrue(stored.isEmpty)
    }

    // MARK: - The check must not over-fire

    func testAddRuleAllowsAKeyNoEnabledCollectionClaims() async throws {
        var arrows = try homeRowArrows()
        arrows.isEnabled = true
        let (facade, store, directory) = try makeFacade(collections: [arrows])
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try await facade.addRule(input: "f13", action: .keystroke(key: "f14"))

        guard case .created = result else {
            return XCTFail("An unclaimed key must still be accepted, got \(result)")
        }
        let stored = await store.loadRules()
        XCTAssertEqual(stored.map(\.input), ["f13"])
    }

    func testAddRuleAllowsAKeyOwnedOnlyByADisabledCollection() async throws {
        var arrows = try homeRowArrows()
        arrows.isEnabled = false
        let (facade, store, directory) = try makeFacade(collections: [arrows])
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try await facade.addRule(
            input: "f", action: tapHoldF().action, behavior: tapHoldF().behavior
        )

        guard case .created = result else {
            return XCTFail("A disabled collection claims nothing, got \(result)")
        }
        let stored = await store.loadRules()
        XCTAssertEqual(stored.map(\.input), ["f"])
    }

    /// A store that is already conflicted must not block an unrelated rule: only
    /// conflicts the new rule introduces are held against it.
    func testPreExistingCollectionConflictDoesNotBlockAnUnrelatedRule() async throws {
        var arrows = try homeRowArrows()
        arrows.isEnabled = true
        let conflicting = RuleCollection(
            id: UUID(),
            name: "Rival F Mapper",
            summary: "Also claims f on the base layer",
            category: .custom,
            mappings: [KeyMapping(input: "f", action: .keystroke(key: "x"))],
            isEnabled: true,
            isSystemDefault: false,
            icon: "square.and.pencil",
            targetLayer: .base
        )

        let (facade, store, directory) = try makeFacade(collections: [arrows, conflicting])
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertFalse(
            RuleCollectionDeduplicator.detectConflicts(in: [arrows, conflicting]).isEmpty,
            "Precondition: the collections conflict with each other"
        )

        let result = try await facade.addRule(input: "f13", action: .keystroke(key: "f14"))
        guard case .created = result else {
            return XCTFail("A pre-existing conflict must not block an unrelated key, got \(result)")
        }
        let stored = await store.loadRules()
        XCTAssertEqual(stored.map(\.input), ["f13"])
    }

    /// The facade the app and the plain CLI initialiser build has no collection
    /// loader, so its behaviour is unchanged.
    func testFacadeWithoutCollectionLoaderIsUnchanged() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kp-rule-noloader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CustomRulesStore(fileURL: directory.appendingPathComponent("CustomRules.json"))

        let result = try await RulesFacade(store: store).addRule(
            input: "f", action: tapHoldF().action, behavior: tapHoldF().behavior
        )

        guard case .created = result else {
            return XCTFail("Expected created, got \(result)")
        }
    }
}
