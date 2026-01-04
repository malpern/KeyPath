import XCTest

@testable import KeyPathAppKit

/// Tests for layer management in RuleCollectionsManager
final class RuleCollectionsManagerLayerTests: XCTestCase {
    // MARK: - RuleCollectionLayer Equality

    func testRuleCollectionLayer_equality_base() {
        XCTAssertEqual(RuleCollectionLayer.base, RuleCollectionLayer.base)
        XCTAssertNotEqual(RuleCollectionLayer.base, RuleCollectionLayer.navigation)
    }

    func testRuleCollectionLayer_equality_custom() {
        XCTAssertEqual(RuleCollectionLayer.custom("test"), RuleCollectionLayer.custom("test"))
        XCTAssertNotEqual(RuleCollectionLayer.custom("test"), RuleCollectionLayer.custom("other"))
    }

    func testRuleCollectionLayer_equality_customCaseSensitive() {
        // Custom layers are case-sensitive in comparison
        // but kanataName lowercases them
        let layer1 = RuleCollectionLayer.custom("Test")
        let layer2 = RuleCollectionLayer.custom("test")

        // They're different enum values
        XCTAssertNotEqual(layer1, layer2)

        // But their kanata names are the same (lowercased)
        XCTAssertEqual(layer1.kanataName, layer2.kanataName)
    }

    // MARK: - Layer Detection from Collections

    func testLayerDetection_fromTargetLayer() {
        let collection = RuleCollection(
            id: UUID(),
            name: "Test",
            summary: "Test collection",
            category: .custom,
            mappings: [],
            isEnabled: true,
            targetLayer: .custom("window")
        )

        XCTAssertEqual(collection.targetLayer.kanataName, "window")
    }

    func testLayerDetection_baseLayer() {
        let collection = RuleCollection(
            id: UUID(),
            name: "Test",
            summary: "Test collection",
            category: .custom,
            mappings: [],
            isEnabled: true,
            targetLayer: .base
        )

        XCTAssertEqual(collection.targetLayer.kanataName, "base")
    }

    func testLayerDetection_navigationLayer() {
        let collection = RuleCollection(
            id: UUID(),
            name: "Test",
            summary: "Test collection",
            category: .custom,
            mappings: [],
            isEnabled: true,
            targetLayer: .navigation
        )

        XCTAssertEqual(collection.targetLayer.kanataName, "nav")
    }

    // MARK: - CustomRule Layer

    func testCustomRule_targetLayerKanataName() {
        let rule = CustomRule(
            id: UUID(),
            input: "a",
            output: "b",
            isEnabled: true,
            targetLayer: .custom("window")
        )

        XCTAssertEqual(rule.targetLayer.kanataName, "window")
    }

    func testCustomRule_defaultTargetLayer() {
        let rule = CustomRule(
            id: UUID(),
            input: "a",
            output: "b"
        )

        // Default target layer is base
        XCTAssertEqual(rule.targetLayer, .base)
    }

    // MARK: - Layer Matching Logic

    func testLayerMatching_caseInsensitive() {
        let layerName = "Window"
        let normalizedName = layerName.lowercased()

        let collection = RuleCollection(
            id: UUID(),
            name: "Test",
            summary: "Test collection",
            category: .custom,
            mappings: [],
            isEnabled: true,
            targetLayer: .custom("window")
        )

        // Matching logic used in removeLayer
        let matches = collection.targetLayer.kanataName.lowercased() == normalizedName
        XCTAssertTrue(matches)
    }

    func testLayerMatching_noMatchDifferentLayer() {
        let layerName = "vim"
        let normalizedName = layerName.lowercased()

        let collection = RuleCollection(
            id: UUID(),
            name: "Test",
            summary: "Test collection",
            category: .custom,
            mappings: [],
            isEnabled: true,
            targetLayer: .custom("window")
        )

        let matches = collection.targetLayer.kanataName.lowercased() == normalizedName
        XCTAssertFalse(matches)
    }

    // MARK: - Layer Removal Logic (Unit Tests for the filtering)

    func testLayerRemoval_filtersCorrectCollections() {
        var collections = [
            RuleCollection(id: UUID(), name: "A", summary: "", category: .custom, mappings: [], targetLayer: .custom("window")),
            RuleCollection(id: UUID(), name: "B", summary: "", category: .custom, mappings: [], targetLayer: .custom("vim")),
            RuleCollection(id: UUID(), name: "C", summary: "", category: .custom, mappings: [], targetLayer: .custom("window")),
            RuleCollection(id: UUID(), name: "D", summary: "", category: .custom, mappings: [], targetLayer: .base)
        ]

        let normalizedName = "window"
        collections.removeAll { collection in
            collection.targetLayer.kanataName.lowercased() == normalizedName
        }

        XCTAssertEqual(collections.count, 2)
        XCTAssertEqual(collections[0].name, "B")
        XCTAssertEqual(collections[1].name, "D")
    }

    func testLayerRemoval_filtersCorrectRules() {
        var rules = [
            CustomRule(id: UUID(), input: "a", output: "b", isEnabled: true, targetLayer: .custom("window")),
            CustomRule(id: UUID(), input: "c", output: "d", isEnabled: true, targetLayer: .custom("vim")),
            CustomRule(id: UUID(), input: "e", output: "f", isEnabled: true, targetLayer: .custom("window")),
            CustomRule(id: UUID(), input: "g", output: "h", isEnabled: true, targetLayer: .base)
        ]

        let normalizedName = "window"
        rules.removeAll { rule in
            rule.targetLayer.kanataName.lowercased() == normalizedName
        }

        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(rules[0].input, "c")
        XCTAssertEqual(rules[1].input, "g")
    }

    func testLayerRemoval_doesNotRemoveSystemLayers() {
        var collections = [
            RuleCollection(id: UUID(), name: "A", summary: "", category: .custom, mappings: [], targetLayer: .base),
            RuleCollection(id: UUID(), name: "B", summary: "", category: .custom, mappings: [], targetLayer: .navigation),
            RuleCollection(id: UUID(), name: "C", summary: "", category: .custom, mappings: [], targetLayer: .custom("window"))
        ]

        // Only remove "window" layer
        let normalizedName = "window"
        collections.removeAll { collection in
            collection.targetLayer.kanataName.lowercased() == normalizedName
        }

        XCTAssertEqual(collections.count, 2)
        XCTAssertEqual(collections[0].targetLayer, .base)
        XCTAssertEqual(collections[1].targetLayer, .navigation)
    }

    // MARK: - Collection Removal by ID

    func testCollectionRemoval_byId() {
        let idToRemove = UUID()
        var collections = [
            RuleCollection(id: UUID(), name: "A", summary: "", category: .custom, mappings: []),
            RuleCollection(id: idToRemove, name: "B", summary: "", category: .custom, mappings: []),
            RuleCollection(id: UUID(), name: "C", summary: "", category: .custom, mappings: [])
        ]

        collections.removeAll { $0.id == idToRemove }

        XCTAssertEqual(collections.count, 2)
        XCTAssertFalse(collections.contains { $0.id == idToRemove })
        XCTAssertTrue(collections.contains { $0.name == "A" })
        XCTAssertTrue(collections.contains { $0.name == "C" })
    }

    // MARK: - Available Layers Discovery

    func testAvailableLayers_fromCollections() {
        let collections = [
            RuleCollection(id: UUID(), name: "A", summary: "", category: .custom, mappings: [], isEnabled: true, targetLayer: .base),
            RuleCollection(id: UUID(), name: "B", summary: "", category: .custom, mappings: [], isEnabled: true, targetLayer: .navigation),
            RuleCollection(id: UUID(), name: "C", summary: "", category: .custom, mappings: [], isEnabled: true, targetLayer: .custom("window")),
            RuleCollection(id: UUID(), name: "D", summary: "", category: .custom, mappings: [], isEnabled: false, targetLayer: .custom("disabled"))
        ]

        var layers = Set<String>(["base", "nav"])
        for collection in collections where collection.isEnabled {
            layers.insert(collection.targetLayer.kanataName)
        }

        XCTAssertEqual(layers.count, 3)
        XCTAssertTrue(layers.contains("base"))
        XCTAssertTrue(layers.contains("nav"))
        XCTAssertTrue(layers.contains("window"))
        XCTAssertFalse(layers.contains("disabled")) // disabled collection
    }

    func testAvailableLayers_fromCustomRules() {
        let rules = [
            CustomRule(id: UUID(), input: "a", output: "b", isEnabled: true, targetLayer: .base),
            CustomRule(id: UUID(), input: "c", output: "d", isEnabled: true, targetLayer: .custom("vim")),
            CustomRule(id: UUID(), input: "e", output: "f", isEnabled: false, targetLayer: .custom("disabled"))
        ]

        var layers = Set<String>(["base", "nav"])
        for rule in rules where rule.isEnabled {
            layers.insert(rule.targetLayer.kanataName)
        }

        XCTAssertEqual(layers.count, 3)
        XCTAssertTrue(layers.contains("base"))
        XCTAssertTrue(layers.contains("nav"))
        XCTAssertTrue(layers.contains("vim"))
        XCTAssertFalse(layers.contains("disabled")) // disabled rule
    }
}
