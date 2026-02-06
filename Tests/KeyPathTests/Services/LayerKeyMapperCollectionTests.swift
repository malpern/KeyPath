@testable import KeyPathAppKit
@preconcurrency import XCTest

/// Tests for collection ownership tracking in LayerKeyMapper
final class LayerKeyMapperCollectionTests: XCTestCase {
    // MARK: - Test Data

    private let vimCollectionId = UUID(uuidString: "A1E0744C-66C1-4E69-8E68-DA2643765429")!
    private let windowCollectionId = UUID(uuidString: "F7A9B1C3-5D6E-8F0A-2B4C-6D8E0F2A4B6C")!
    private let customCollectionId = UUID()

    private func makeVimCollection() -> RuleCollection {
        RuleCollection(
            id: vimCollectionId,
            name: "Vim Navigation",
            summary: "Vim-style navigation",
            category: .navigation,
            mappings: [
                KeyMapping(input: "h", output: "left", description: "Left"),
                KeyMapping(input: "j", output: "down", description: "Down"),
                KeyMapping(input: "k", output: "up", description: "Up"),
                KeyMapping(input: "l", output: "right", description: "Right")
            ],
            isEnabled: true,
            isSystemDefault: false,
            icon: "arrow.left.and.right",
            tags: ["vim", "navigation"],
            targetLayer: .navigation
        )
    }

    private func makeWindowCollection() -> RuleCollection {
        RuleCollection(
            id: windowCollectionId,
            name: "Window Snapping",
            summary: "Snap windows to edges",
            category: .productivity,
            mappings: [
                KeyMapping(input: "h", output: "window:left", description: "Snap left"),
                KeyMapping(input: "l", output: "window:right", description: "Snap right")
            ],
            isEnabled: true,
            isSystemDefault: false,
            icon: "rectangle.split.3x3",
            tags: ["window", "snapping"],
            targetLayer: .custom("window"),
            momentaryActivator: MomentaryActivator(
                input: "w",
                targetLayer: .custom("window"),
                sourceLayer: .navigation
            )
        )
    }

    private func makeCustomCollection() -> RuleCollection {
        RuleCollection(
            id: customCollectionId,
            name: "Custom Rules",
            summary: "User custom mappings",
            category: .custom,
            mappings: [
                KeyMapping(input: "q", output: "quit", description: "Quit")
            ],
            isEnabled: true,
            isSystemDefault: false,
            icon: "gear",
            tags: ["custom"],
            targetLayer: .navigation
        )
    }

    // MARK: - Integration Tests (require simulator)

    func testCollectionIdPropagationThroughSimulation() async throws {
        // This test requires simulator to verify collection IDs propagate through full simulation
        let simulatorPath = try Self.resolveSimulatorPath() ?? {
            throw XCTSkip("Simulator not available")
        }()

        // Create config with Vim and Window collections
        let config = """
        (defcfg process-unmapped-keys yes danger-enable-cmd yes)

        (deffakekeys
          kp-layer-nav-enter (push-msg "layer:nav")
          kp-layer-nav-exit (push-msg "layer:base")
          kp-layer-window-enter (push-msg "layer:window")
          kp-layer-window-exit (push-msg "layer:base")
        )

        (defsrc spc w h j k l)

        (deflayer base
          @layer_nav_spc
          w
          h j k l
        )

        (deflayer nav
          XX
          @layer_window_w
          left down up right
        )

        (deflayer window
          _
          _
          (push-msg "window:left")
          _
          _
          (push-msg "window:right")
        )

        (defalias
          layer_nav_spc (tap-hold 200 200 spc
            (multi
              (layer-while-held nav)
              (on-press-fakekey kp-layer-nav-enter tap)
              (on-release-fakekey kp-layer-nav-exit tap)))
          layer_window_w (multi
            (one-shot-press 2000 (layer-while-held window))
            (on-press-fakekey kp-layer-window-enter tap)
            (on-release-fakekey kp-layer-window-exit tap))
        )
        """

        let configPath = try createTempConfig(config, name: "test-collection-mapping.kbd")
        defer { try? FileManager.default.removeItem(atPath: configPath) }

        let simulatorService = SimulatorService.forTesting(simulatorPath: simulatorPath)
        let mapper = LayerKeyMapper(simulatorService: simulatorService)

        let vim = makeVimCollection()
        let window = makeWindowCollection()
        let collections = [vim, window]

        // Test navigation layer
        let navMapping = try await mapper.getMapping(
            for: "nav",
            configPath: configPath,
            layout: PhysicalLayout.macBookUS,
            collections: collections
        )

        // H key (keycode 4) should belong to Vim collection
        let hKey = navMapping[4]
        XCTAssertNotNil(hKey, "H key should have mapping in nav layer")
        XCTAssertEqual(hKey?.collectionId, vimCollectionId, "H key should belong to Vim collection")
        XCTAssertEqual(hKey?.outputKey, "left", "H should output left arrow")

        // W key (keycode 13) should belong to Window Snapping collection
        let wKey = navMapping[13]
        XCTAssertNotNil(wKey, "W key should have mapping in nav layer")
        XCTAssertEqual(wKey?.collectionId, windowCollectionId, "W key should belong to Window Snapping collection")
        XCTAssertTrue(wKey?.isLayerSwitch ?? false, "W key should be detected as layer switch")

        // Test window layer
        let windowMapping = try await mapper.getMapping(
            for: "window",
            configPath: configPath,
            layout: PhysicalLayout.macBookUS,
            collections: collections
        )

        // H key in window layer should belong to Window Snapping collection
        let windowHKey = windowMapping[4]
        XCTAssertNotNil(windowHKey, "H key should have mapping in window layer")
        XCTAssertEqual(windowHKey?.collectionId, windowCollectionId, "H key in window layer should belong to Window Snapping")
    }

    func testEmptyCollectionsArray() async throws {
        let simulatorPath = try Self.resolveSimulatorPath() ?? {
            throw XCTSkip("Simulator not available")
        }()

        let config = """
        (defcfg process-unmapped-keys yes)
        (defsrc h j)
        (deflayer base left down)
        """

        let configPath = try createTempConfig(config, name: "test-empty-collections.kbd")
        defer { try? FileManager.default.removeItem(atPath: configPath) }

        let simulatorService = SimulatorService.forTesting(simulatorPath: simulatorPath)
        let mapper = LayerKeyMapper(simulatorService: simulatorService)

        // Call with empty collections array
        let mapping = try await mapper.getMapping(
            for: "base",
            configPath: configPath,
            layout: PhysicalLayout.macBookUS,
            collections: []
        )

        // Keys should have nil collection IDs (graceful degradation)
        let hKey = mapping[4]
        XCTAssertNotNil(hKey, "H key should have mapping")
        XCTAssertNil(hKey?.collectionId, "H key should have nil collection ID when no collections provided")
    }

    func testDisabledCollectionsIgnored() async throws {
        let simulatorPath = try Self.resolveSimulatorPath() ?? {
            throw XCTSkip("Simulator not available")
        }()

        let config = """
        (defcfg process-unmapped-keys yes)
        (defsrc h)
        (deflayer nav left)
        """

        let configPath = try createTempConfig(config, name: "test-disabled-collection.kbd")
        defer { try? FileManager.default.removeItem(atPath: configPath) }

        let simulatorService = SimulatorService.forTesting(simulatorPath: simulatorPath)
        let mapper = LayerKeyMapper(simulatorService: simulatorService)

        // Create disabled Vim collection
        var vim = makeVimCollection()
        vim.isEnabled = false

        let mapping = try await mapper.getMapping(
            for: "nav",
            configPath: configPath,
            layout: PhysicalLayout.macBookUS,
            collections: [vim]
        )

        // H key should have nil collection ID (disabled collections ignored)
        let hKey = mapping[4]
        XCTAssertNotNil(hKey, "H key should have mapping")
        XCTAssertNil(hKey?.collectionId, "Disabled collection should not contribute collection ID")
    }

    func testMultipleCollectionsSameLayer() async throws {
        let simulatorPath = try Self.resolveSimulatorPath() ?? {
            throw XCTSkip("Simulator not available")
        }()

        let config = """
        (defcfg process-unmapped-keys yes)
        (defsrc h q)
        (deflayer nav left quit)
        """

        let configPath = try createTempConfig(config, name: "test-multi-collection.kbd")
        defer { try? FileManager.default.removeItem(atPath: configPath) }

        let simulatorService = SimulatorService.forTesting(simulatorPath: simulatorPath)
        let mapper = LayerKeyMapper(simulatorService: simulatorService)

        let vim = makeVimCollection()
        let custom = makeCustomCollection()

        let mapping = try await mapper.getMapping(
            for: "nav",
            configPath: configPath,
            layout: PhysicalLayout.macBookUS,
            collections: [vim, custom]
        )

        // H key should belong to Vim
        let hKey = mapping[4]
        XCTAssertEqual(hKey?.collectionId, vimCollectionId, "H key should belong to Vim")

        // Q key should belong to Custom
        let qKey = mapping[12]
        XCTAssertEqual(qKey?.collectionId, customCollectionId, "Q key should belong to Custom collection")
    }

    // MARK: - Helper Methods

    private func createTempConfig(_ content: String, name: String) throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let configPath = tempDir.appendingPathComponent(name).path
        try content.write(toFile: configPath, atomically: true, encoding: .utf8)
        return configPath
    }

    private static func resolveSimulatorPath() -> String? {
        // Check installed app location
        let installedPath = "/Applications/KeyPath.app/Contents/Resources/kanata_simulator"
        if FileManager.default.fileExists(atPath: installedPath) {
            return installedPath
        }

        // Check local build (from project root)
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let localPath = projectRoot
            .appendingPathComponent("Resources")
            .appendingPathComponent("kanata_simulator")
            .path
        if FileManager.default.fileExists(atPath: localPath) {
            return localPath
        }

        return nil
    }
}
