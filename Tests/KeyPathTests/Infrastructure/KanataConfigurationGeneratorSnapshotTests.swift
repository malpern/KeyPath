@testable import KeyPathAppKit
import XCTest

final class KanataConfigurationGeneratorSnapshotTests: XCTestCase {
    func testBaseConfigIncludesDefaultFunctionKeys() {
        let config = KanataConfiguration.generateFromCollections([])

        assertContains(config, "brdn")
        assertContains(config, "volu")
    }

    func testNavigationActivatorUsesOneShotAndWrapsMappings() throws {
        let navCollection = try makeCollection(
            id: XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111")),
            name: "Navigation",
            summary: "Nav layer",
            category: .navigation,
            mappings: [KeyMapping(input: "h", output: "left")],
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )

        let config = KanataConfiguration.generateFromCollections([navCollection])

        assertContains(config, "layer_nav_spc")
        assertContains(config, "(one-shot-press 65000 (layer-while-held nav))")
        assertContains(config, "(multi (release-layer nav) left (push-msg \"layer:base\"))")
        assertContains(config, "@layer_nav_spc")
    }

    func testChainedWindowLayerUsesOneShotExit() throws {
        let navCollection = try makeCollection(
            id: XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            name: "Navigation",
            summary: "Nav layer",
            category: .navigation,
            mappings: [KeyMapping(input: "h", output: "left")],
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )

        let windowCollection = makeCollection(
            id: RuleCollectionIdentifier.windowSnapping,
            name: "Window Snapping",
            summary: "Window layer",
            category: .productivity,
            mappings: [KeyMapping(input: "h", output: "(push-msg \"window:left\")")],
            targetLayer: .custom("window"),
            momentaryActivator: MomentaryActivator(
                input: "w",
                targetLayer: .custom("window"),
                sourceLayer: .navigation
            )
        )

        let config = KanataConfiguration.generateFromCollections([navCollection, windowCollection])

        assertContains(config, "layer_window_w")
        assertContains(config, "(one-shot-press 65000 (layer-while-held window))")
        assertContains(config, "act_window_h (push-msg \"window:left\")")
        assertContains(config, "(multi (release-layer window) @act_window_h (push-msg \"layer:base\"))")
    }

    func testLauncherTapModeWrapsOutputAndAddsCancel() throws {
        let config = try LauncherGridConfig(
            activationMode: .holdHyper,
            hyperTriggerMode: .tap,
            mappings: [
                LauncherMapping(
                    id: XCTUnwrap(UUID(uuidString: "33333333-3333-3333-3333-333333333333")),
                    key: "a",
                    target: .app(name: "Calculator", bundleId: "com.apple.calculator"),
                    isEnabled: true
                )
            ],
            hasSeenWelcome: true
        )

        let launcherCollection = makeCollection(
            id: RuleCollectionIdentifier.launcher,
            name: "Launcher",
            summary: "Launcher grid",
            category: .productivity,
            mappings: [],
            targetLayer: .custom("launcher"),
            momentaryActivator: nil,
            configuration: .launcherGrid(config)
        )

        let output = KanataConfiguration.generateFromCollections([launcherCollection])

        assertContains(
            output,
            "(multi (push-msg \"launch:com.apple.calculator\") (push-msg \"layer:base\"))"
        )
        assertContains(output, "(multi XX (push-msg \"layer:base\"))")
    }

    private func makeCollection(
        id: UUID,
        name: String,
        summary: String,
        category: RuleCollectionCategory,
        mappings: [KeyMapping],
        targetLayer: RuleCollectionLayer,
        momentaryActivator: MomentaryActivator?,
        configuration: RuleCollectionConfiguration = .list
    ) -> RuleCollection {
        RuleCollection(
            id: id,
            name: name,
            summary: summary,
            category: category,
            mappings: mappings,
            isEnabled: true,
            isSystemDefault: false,
            icon: nil,
            tags: [],
            targetLayer: targetLayer,
            momentaryActivator: momentaryActivator,
            activationHint: nil,
            configuration: configuration
        )
    }

    private func assertContains(
        _ config: String,
        _ snippet: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            config.contains(snippet),
            "Expected config to contain:\n\(snippet)\n\nActual output:\n\(config)",
            file: file,
            line: line
        )
    }
}
