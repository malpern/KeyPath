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

        let config = KanataConfiguration.generateFromCollections(
            [navCollection],
            navActivationMode: .tapToToggle
        )

        assertContains(config, "layer_nav_spc")
        assertContains(config, "(one-shot-press 65000 (layer-while-held nav))")
        assertContains(config, "(multi (release-layer nav) left (push-msg \"layer:base\"))")
        assertContains(config, "@layer_nav_spc")
    }

    func testNavigationActivatorUsesLayerWhileHeldInHoldMode() throws {
        let navCollection = try makeCollection(
            id: XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111")),
            name: "Navigation",
            summary: "Nav layer",
            category: .navigation,
            mappings: [KeyMapping(input: "h", output: "left")],
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )

        let config = KanataConfiguration.generateFromCollections(
            [navCollection],
            navActivationMode: .holdToShow
        )

        assertContains(config, "layer_nav_spc")
        // holdToShow uses standard layer-while-held (no one-shot)
        assertContains(config, "(layer-while-held nav)")
        assertContains(config, "on-release-fakekey kp-layer-nav-exit tap")
        // Should NOT contain one-shot-press for nav
        XCTAssertFalse(
            config.contains("one-shot-press"),
            "holdToShow mode should not use one-shot-press for nav layer\n\nActual output:\n\(config)"
        )
        // Mappings should not be wrapped with release-layer (not one-shot)
        XCTAssertFalse(
            config.contains("release-layer nav"),
            "holdToShow mode should not wrap nav mappings with release-layer\n\nActual output:\n\(config)"
        )
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

    func testModifierChordsExpandedInsideMultiWrapper() throws {
        let navCollection = try makeCollection(
            id: XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111")),
            name: "Navigation",
            summary: "Nav layer",
            category: .navigation,
            mappings: [
                KeyMapping(input: "p", output: "M-v"),
                KeyMapping(input: "slash", output: "C-S-z"),
            ],
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )

        let config = KanataConfiguration.generateFromCollections(
            [navCollection],
            navActivationMode: .tapToToggle
        )

        // Modifier chords must expand inside the release-layer multi wrapper.
        // Kanata drops modifier-prefixed tokens after release-layer, so the
        // generator emits explicit nested multi forms instead.
        assertContains(config, "(multi (release-layer nav) (multi lmet v) (push-msg \"layer:base\"))")
        assertContains(config, "(multi (release-layer nav) (multi lctl lsft z) (push-msg \"layer:base\"))")

        XCTAssertFalse(
            config.contains("(multi (release-layer nav) M-v (push-msg \"layer:base\"))"),
            "M-v should be expanded inside multi\n\nActual output:\n\(config)"
        )
        XCTAssertFalse(
            config.contains("(multi (release-layer nav) C-S-z (push-msg \"layer:base\"))"),
            "C-S-z should be expanded inside multi\n\nActual output:\n\(config)"
        )
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

    // MARK: - defhands + require-prior-idle Integration

    func testOppositeHandActivation_EmitsDefhandsBlock() throws {
        let hrmCollection = try makeCollection(
            id: XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            name: "Home Row Mods",
            summary: "HRM",
            category: .custom,
            mappings: [],
            targetLayer: .base,
            momentaryActivator: nil,
            configuration: .homeRowMods(HomeRowModsConfig(
                enabledKeys: ["a", "f"],
                modifierAssignments: ["a": "lsft", "f": "lmet"],
                holdMode: .modifiers,
                oppositeHandMode: .press
            ))
        )

        let config = KanataConfiguration.generateFromCollections([hrmCollection])

        assertContains(config, "(defhands")
        assertContains(config, "(left q w e r t a s d f g z x c v b)")
        assertContains(config, "(right y u i o p h j k l ; n m , . /)")
        assertContains(config, "tap-hold-opposite-hand")
    }

    func testOppositeHandOff_OmitsDefhandsBlock() throws {
        let hrmCollection = try makeCollection(
            id: XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            name: "Home Row Mods",
            summary: "HRM",
            category: .custom,
            mappings: [],
            targetLayer: .base,
            momentaryActivator: nil,
            configuration: .homeRowMods(HomeRowModsConfig(
                enabledKeys: ["a"],
                modifierAssignments: ["a": "lsft"],
                holdMode: .modifiers,
                oppositeHandMode: .off
            ))
        )

        let config = KanataConfiguration.generateFromCollections([hrmCollection])

        XCTAssertFalse(config.contains("defhands"), "Should not contain defhands when opposite-hand is off")
        XCTAssertFalse(config.contains("tap-hold-opposite-hand"), "Should not contain tap-hold-opposite-hand")
    }

    func testRequirePriorIdle_EmitsDefcfgOption() throws {
        var timing = TimingConfig.default
        timing.requirePriorIdleMs = 150

        let hrmCollection = try makeCollection(
            id: XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            name: "Home Row Mods",
            summary: "HRM",
            category: .custom,
            mappings: [],
            targetLayer: .base,
            momentaryActivator: nil,
            configuration: .homeRowMods(HomeRowModsConfig(
                enabledKeys: ["a"],
                modifierAssignments: ["a": "lsft"],
                holdMode: .modifiers,
                timing: timing,
                oppositeHandMode: .press
            ))
        )

        let config = KanataConfiguration.generateFromCollections([hrmCollection])

        assertContains(config, "require-prior-idle 150")
        // Must be inside defcfg, not wrapping individual actions
        XCTAssertTrue(
            config.contains("(defcfg") && config.contains("require-prior-idle 150"),
            "require-prior-idle should be a defcfg option"
        )
    }

    func testRequirePriorIdleZero_OmitsFromDefcfg() throws {
        var timing = TimingConfig.default
        timing.requirePriorIdleMs = 0

        let hrmCollection = try makeCollection(
            id: XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            name: "Home Row Mods",
            summary: "HRM",
            category: .custom,
            mappings: [],
            targetLayer: .base,
            momentaryActivator: nil,
            configuration: .homeRowMods(HomeRowModsConfig(
                enabledKeys: ["a"],
                modifierAssignments: ["a": "lsft"],
                holdMode: .modifiers,
                timing: timing,
                oppositeHandMode: .press
            ))
        )

        let config = KanataConfiguration.generateFromCollections([hrmCollection])

        XCTAssertFalse(config.contains("require-prior-idle"), "Should not contain require-prior-idle when 0")
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
