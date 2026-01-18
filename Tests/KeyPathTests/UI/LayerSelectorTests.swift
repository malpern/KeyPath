import XCTest

@testable import KeyPathAppKit

/// Tests for layer selector functionality in MapperViewModel
@MainActor
final class LayerSelectorTests: XCTestCase {
    // MARK: - getAvailableLayers Tests

    func testGetAvailableLayers_defaultsToBaseAndNav() {
        // Without rulesManager, should return default layers
        let viewModel = MapperViewModel()
        let layers = viewModel.getAvailableLayers()

        XCTAssertTrue(layers.contains("base"))
        XCTAssertTrue(layers.contains("nav"))
        XCTAssertEqual(layers.count, 2)
    }

    func testGetAvailableLayers_sortsSystemLayersFirst() {
        let viewModel = MapperViewModel()
        let layers = viewModel.getAvailableLayers()

        // System layers should come before custom layers alphabetically
        if let baseIndex = layers.firstIndex(of: "base"),
           let navIndex = layers.firstIndex(of: "nav")
        {
            // Both system layers should be at the beginning
            XCTAssertLessThan(baseIndex, 2)
            XCTAssertLessThan(navIndex, 2)
        }
    }

    // MARK: - isSystemLayer Tests

    func testIsSystemLayer_base() {
        let viewModel = MapperViewModel()
        XCTAssertTrue(viewModel.isSystemLayer("base"))
        XCTAssertTrue(viewModel.isSystemLayer("Base"))
        XCTAssertTrue(viewModel.isSystemLayer("BASE"))
    }

    func testIsSystemLayer_nav() {
        let viewModel = MapperViewModel()
        XCTAssertTrue(viewModel.isSystemLayer("nav"))
        XCTAssertTrue(viewModel.isSystemLayer("Nav"))
        XCTAssertTrue(viewModel.isSystemLayer("NAV"))
    }

    func testIsSystemLayer_navigation() {
        let viewModel = MapperViewModel()
        XCTAssertTrue(viewModel.isSystemLayer("navigation"))
        XCTAssertTrue(viewModel.isSystemLayer("Navigation"))
    }

    func testIsSystemLayer_customLayerReturnsFalse() {
        let viewModel = MapperViewModel()
        XCTAssertFalse(viewModel.isSystemLayer("window"))
        XCTAssertFalse(viewModel.isSystemLayer("vim"))
        XCTAssertFalse(viewModel.isSystemLayer("custom"))
        XCTAssertFalse(viewModel.isSystemLayer("test"))
    }

    func testRefreshAvailableLayers_includesTcpLayers() async {
        let manager = StubRuntimeCoordinator()
        manager.stubLayerNames = ["VIM", "work"]

        let viewModel = MapperViewModel()
        viewModel.configure(kanataManager: manager)
        await viewModel.refreshAvailableLayers()

        XCTAssertEqual(viewModel.getAvailableLayers(), ["base", "nav", "vim", "work"])
    }

    // MARK: - RuleCollectionLayer Tests

    func testRuleCollectionLayer_kanataName() {
        XCTAssertEqual(RuleCollectionLayer.base.kanataName, "base")
        XCTAssertEqual(RuleCollectionLayer.navigation.kanataName, "nav")
        XCTAssertEqual(RuleCollectionLayer.custom("window").kanataName, "window")
        XCTAssertEqual(RuleCollectionLayer.custom("VIM").kanataName, "vim") // lowercased
    }

    func testRuleCollectionLayer_displayName() {
        XCTAssertEqual(RuleCollectionLayer.base.displayName, "Base")
        XCTAssertEqual(RuleCollectionLayer.navigation.displayName, "Navigation")
        XCTAssertEqual(RuleCollectionLayer.custom("window").displayName, "Window") // capitalized
    }

    // MARK: - MomentaryActivator Tests

    func testMomentaryActivator_defaultSourceLayer() {
        let activator = MomentaryActivator(
            input: "w",
            targetLayer: .custom("window")
        )

        XCTAssertEqual(activator.input, "w")
        XCTAssertEqual(activator.targetLayer, .custom("window"))
        XCTAssertEqual(activator.sourceLayer, .base) // default
    }

    func testMomentaryActivator_customSourceLayer() {
        let activator = MomentaryActivator(
            input: "w",
            targetLayer: .custom("window"),
            sourceLayer: .navigation
        )

        XCTAssertEqual(activator.input, "w")
        XCTAssertEqual(activator.targetLayer, .custom("window"))
        XCTAssertEqual(activator.sourceLayer, .navigation)
    }

    // MARK: - RuleCollection Creation Tests

    func testRuleCollection_customLayerStructure() {
        let targetLayer = RuleCollectionLayer.custom("test")
        let collection = RuleCollection(
            id: UUID(),
            name: "Test",
            summary: "Custom layer: test",
            category: .custom,
            mappings: [],
            isEnabled: true,
            icon: "square.stack.3d.up",
            tags: ["custom-layer"],
            targetLayer: targetLayer,
            momentaryActivator: MomentaryActivator(
                input: "t",
                targetLayer: targetLayer,
                sourceLayer: .navigation
            ),
            activationHint: "Leader → T",
            configuration: .list
        )

        XCTAssertEqual(collection.name, "Test")
        XCTAssertEqual(collection.category, .custom)
        XCTAssertEqual(collection.targetLayer.kanataName, "test")
        XCTAssertNotNil(collection.momentaryActivator)
        XCTAssertEqual(collection.momentaryActivator?.input, "t")
        XCTAssertEqual(collection.momentaryActivator?.sourceLayer, .navigation)
        XCTAssertEqual(collection.activationHint, "Leader → T")
    }

    func testRuleCollection_activatorFromFirstLetter() {
        // Simulating the createLayer logic
        let layerName = "window"
        let activatorKey = String(layerName.prefix(1))

        XCTAssertEqual(activatorKey, "w")

        let layerName2 = "vim"
        let activatorKey2 = String(layerName2.prefix(1))

        XCTAssertEqual(activatorKey2, "v")
    }

    // MARK: - Layer Name Sanitization Tests

    func testLayerNameSanitization_lowercased() {
        let name = "WINDOW"
        let sanitized = name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }

        XCTAssertEqual(sanitized, "window")
    }

    func testLayerNameSanitization_spacesToUnderscores() {
        let name = "my layer"
        let sanitized = name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }

        XCTAssertEqual(sanitized, "my_layer")
    }

    func testLayerNameSanitization_removesSpecialChars() {
        let name = "layer!@#$%"
        let sanitized = name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }

        XCTAssertEqual(sanitized, "layer")
    }

    func testLayerNameSanitization_preservesNumbers() {
        let name = "layer2"
        let sanitized = name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }

        XCTAssertEqual(sanitized, "layer2")
    }
}

// MARK: - ChangeLayer Tests

extension LayerSelectorTests {
    func testChangeLayerResult_successCase() {
        let result = KanataTCPClient.ChangeLayerResult.success
        if case .success = result {
            // Success
        } else {
            XCTFail("Expected success case")
        }
    }

    func testChangeLayerResult_errorCase() {
        let result = KanataTCPClient.ChangeLayerResult.error("Layer not found")
        if case let .error(msg) = result {
            XCTAssertEqual(msg, "Layer not found")
        } else {
            XCTFail("Expected error case")
        }
    }

    func testChangeLayerResult_networkErrorCase() {
        let result = KanataTCPClient.ChangeLayerResult.networkError("Connection refused")
        if case let .networkError(msg) = result {
            XCTAssertEqual(msg, "Connection refused")
        } else {
            XCTFail("Expected networkError case")
        }
    }

    func testChangeLayer_stubCoordinator_success() async {
        let manager = StubRuntimeCoordinator()
        manager.stubChangeLayerResult = true

        let success = await manager.changeLayer("nav")
        XCTAssertTrue(success)
    }

    func testChangeLayer_stubCoordinator_failure() async {
        let manager = StubRuntimeCoordinator()
        manager.stubChangeLayerResult = false

        let success = await manager.changeLayer("nonexistent")
        XCTAssertFalse(success)
    }
}

private final class StubRuntimeCoordinator: RuntimeCoordinator {
    var stubLayerNames: [String] = []
    var stubChangeLayerResult: Bool = false

    override func fetchLayerNamesFromKanata() async -> [String] {
        stubLayerNames
    }

    override func changeLayer(_: String) async -> Bool {
        stubChangeLayerResult
    }
}
