import CoreGraphics
@testable import KeyPathAppKit
import XCTest

@MainActor
final class KeyboardStageSceneTests: XCTestCase {
    func testEveryMomentKeepsAContinuousKeyboardDeck() {
        for moment in allMoments {
            let scene = makeScene(moment: moment)
            let deck = scene.decorations.first { $0.kind == .keyboardDeck }

            XCTAssertNotNil(deck, "Missing keyboard deck for \(moment)")
            XCTAssertEqual(deck?.role, .deck)
            XCTAssertGreaterThan(deck?.frame.minX ?? 0, scene.layoutBounds.minX)
            XCTAssertLessThan(deck?.frame.maxX ?? 0, scene.layoutBounds.maxX)
        }
    }

    func testCapsSequenceTransformsTheExistingCapsKeyInPlace() throws {
        let motivation = makeScene(moment: .capsMotivation)
        let applying = makeScene(moment: .capsApplying)
        let installed = makeScene(moment: .capsInstalled)
        let motivationCaps = try capsKey(in: motivation)
        let applyingCaps = try capsKey(in: applying)
        let installedCaps = try capsKey(in: installed)

        XCTAssertEqual(motivationCaps.id, applyingCaps.id)
        XCTAssertEqual(applyingCaps.id, installedCaps.id)
        XCTAssertEqual(motivationCaps.frame, applyingCaps.frame)
        XCTAssertEqual(applyingCaps.frame, installedCaps.frame)
        XCTAssertNotEqual(applyingCaps.transformedFrame, applyingCaps.frame)
        XCTAssertEqual(motivationCaps.legend.primary, "caps lock")
        XCTAssertEqual(applyingCaps.legend.previous, "caps lock")
        XCTAssertEqual(applyingCaps.legend.primary, "esc")
        XCTAssertGreaterThan(applyingCaps.pressure, 0)
        XCTAssertEqual(installedCaps.legend.primary, "esc")
        XCTAssertEqual(applying.decorations.filter { decoration in
            if case .capsEcho = decoration.kind { return true }
            return false
        }.count, 5)
    }

    func testHyperSequenceGathersFourModifierTokensIntoCaps() throws {
        let motivation = makeScene(moment: .hyperMotivation)
        let applying = makeScene(moment: .hyperApplying)
        let installed = makeScene(moment: .hyperInstalled)
        let sourceTokens = modifierTokens(in: motivation)
        let gatheredTokens = modifierTokens(in: applying)
        let caps = try capsKey(in: applying)

        XCTAssertEqual(sourceTokens.count, 4)
        XCTAssertEqual(gatheredTokens.count, 4)
        XCTAssertTrue(gatheredTokens.allSatisfy { token in
            token.frame.midX >= caps.frame.minX - 0.01
                && token.frame.midX <= caps.frame.maxX + 0.01
        })
        XCTAssertEqual(try capsKey(in: installed).legend.secondary, "⌃⌥⇧⌘")
    }

    func testHyperSourceBadgesDoNotCoverModifierLegends() throws {
        let scene = makeScene(moment: .hyperMotivation)
        let sourceKeyCodesByTokenID: [String: Set<UInt16>] = [
            "hyper-token-control": [59, 62],
            "hyper-token-option": [58, 61],
            "hyper-token-shift": [56, 60],
            "hyper-token-command": [54, 55],
        ]

        for token in modifierTokens(in: scene) {
            let keyCodes = try XCTUnwrap(sourceKeyCodesByTokenID[token.id])
            let sourceKey = try XCTUnwrap(scene.keys.first { keyCodes.contains($0.keyCode) })
            XCTAssertLessThan(
                token.frame.maxY,
                sourceKey.frame.midY,
                "\(token.id) should stay above the native key legend"
            )
        }
    }

    func testLauncherMomentAddsAChoiceTargetWithoutInventingAnAssignment() throws {
        let scene = makeScene(moment: .launcher)
        let launcherKeys = scene.keys.filter { $0.role == .launcher }
        let caps = try capsKey(in: scene)

        XCTAssertGreaterThan(launcherKeys.count, 1)
        XCTAssertEqual(caps.role, .hyper)
        XCTAssertEqual(caps.legend.primary, "Hyper")
        XCTAssertEqual(caps.legend.secondary, "⌃⌥⇧⌘")
        XCTAssertFalse(scene.keys.contains { key in
            if case .launcherKey? = key.accessibilityRole { return true }
            return false
        })
        XCTAssertFalse(scene.decorations.contains { decoration in
            if case .applicationTarget = decoration.kind { return true }
            return false
        })
        XCTAssertEqual(
            scene.decorations.filter { $0.kind == .launcherChoiceTarget }.count,
            1
        )
        XCTAssertEqual(scene.revealTarget, .launcherChoice)
    }

    func testLauncherCameraKeepsHyperAndAvailableLettersInOneStory() throws {
        let scene = KeyboardStageSceneBuilder.make(
            layout: .macBookUS,
            keymap: .qwertyUS,
            moment: .launcher,
            displayMode: .standard
        )
        let caps = try capsKey(in: scene)
        let projection = KeyboardStageProjection(
            scene: scene,
            size: CGSize(width: 600, height: 420)
        )
        let visibleLauncherKeys = scene.keys.filter { key in
            key.role == .launcher
                && key.frame.midX >= projection.sourceRect.minX
                && key.frame.midX <= projection.sourceRect.maxX
                && key.frame.midY >= projection.sourceRect.minY
                && key.frame.midY <= projection.sourceRect.maxY
        }

        XCTAssertEqual(caps.role, .hyper)
        XCTAssertGreaterThanOrEqual(caps.frame.midX, projection.sourceRect.minX)
        XCTAssertLessThanOrEqual(caps.frame.midX, projection.sourceRect.maxX)
        XCTAssertGreaterThan(visibleLauncherKeys.count, 4)
    }

    func testDifferentiateWithoutColorAddsNeutralMarkersToLauncherCandidatesOnly() throws {
        var displayMode = KeyboardStageDisplayMode.standard
        displayMode.differentiateWithoutColor = true
        let scene = KeyboardStageSceneBuilder.make(
            layout: testLayout,
            keymap: .qwertyUS,
            moment: .launcher,
            displayMode: displayMode
        )
        let launcherKeys = scene.keys.filter { $0.role == .launcher }
        let markers = scene.decorations.compactMap { decoration -> (String, KeyboardStageDecoration)? in
            guard case let .launcherCandidateMarker(keyID) = decoration.kind else { return nil }
            return (keyID, decoration)
        }

        XCTAssertEqual(markers.count, launcherKeys.count)
        XCTAssertEqual(Set(markers.map(\.0)), Set(launcherKeys.map(\.id)))
        for (keyID, marker) in markers {
            let key = try XCTUnwrap(launcherKeys.first { $0.id == keyID })
            XCTAssertEqual(marker.role, .deck)
            XCTAssertGreaterThan(marker.frame.minX, key.frame.midX)
            XCTAssertLessThan(marker.frame.maxY, key.frame.midY)
        }

        let defaultScene = makeScene(moment: .launcher)
        XCTAssertFalse(defaultScene.decorations.contains { decoration in
            if case .launcherCandidateMarker = decoration.kind { return true }
            return false
        })
    }

    func testHandoffKeepsHyperAnchoredAndRevealsRulesInTheScene() throws {
        let scene = makeScene(moment: .handoff)
        let caps = try capsKey(in: scene)

        XCTAssertEqual(scene.revealTarget, .rules)
        XCTAssertEqual(caps.role, .hyper)
        XCTAssertEqual(caps.legend.primary, "Hyper")
        XCTAssertEqual(caps.legend.secondary, "⌃⌥⇧⌘")
        XCTAssertTrue(scene.keys.filter { $0.id != caps.id }.allSatisfy { $0.role == .dimmed })
        XCTAssertEqual(scene.decorations.filter { $0.kind == .handoffTarget }.count, 1)
    }

    func testLauncherAndHandoffKeepTheInstalledCapsKeyContinuous() throws {
        let installedCaps = try capsKey(in: makeScene(moment: .hyperInstalled))
        let launcherCaps = try capsKey(in: makeScene(moment: .launcher))
        let handoffCaps = try capsKey(in: makeScene(moment: .handoff))

        XCTAssertEqual(installedCaps.id, launcherCaps.id)
        XCTAssertEqual(launcherCaps.id, handoffCaps.id)
        XCTAssertEqual(installedCaps.frame, launcherCaps.frame)
        XCTAssertEqual(launcherCaps.frame, handoffCaps.frame)
        XCTAssertEqual(installedCaps.legend.primary, "Hyper")
        XCTAssertEqual(launcherCaps.legend.primary, "Hyper")
        XCTAssertEqual(handoffCaps.legend.primary, "Hyper")
        XCTAssertEqual(launcherCaps.accessibilityRole, .capsToHyper)
        XCTAssertEqual(handoffCaps.accessibilityRole, .capsToHyper)
    }

    func testJourneyTargetsShareARestrainedLegendFreeSpacebarPlacement() throws {
        let launcher = KeyboardStageSceneBuilder.make(
            layout: .macBookUS,
            keymap: .qwertyUS,
            moment: .launcher,
            displayMode: .standard
        )
        let handoff = KeyboardStageSceneBuilder.make(
            layout: .macBookUS,
            keymap: .qwertyUS,
            moment: .handoff,
            displayMode: .standard
        )
        let launcherTarget = try XCTUnwrap(
            launcher.decorations.first { $0.kind == .launcherChoiceTarget }
        )
        let handoffTarget = try XCTUnwrap(
            handoff.decorations.first { $0.kind == .handoffTarget }
        )
        let spacebar = try XCTUnwrap(launcher.keys.first { $0.keyCode == 49 })
        let projection = KeyboardStageProjection(
            scene: launcher,
            size: CGSize(width: 600, height: 420)
        )

        XCTAssertEqual(launcherTarget.id, handoffTarget.id)
        XCTAssertEqual(launcherTarget.frame, handoffTarget.frame)
        XCTAssertGreaterThanOrEqual(launcherTarget.frame.minX, spacebar.frame.minX)
        XCTAssertLessThanOrEqual(launcherTarget.frame.maxX, spacebar.frame.maxX)
        XCTAssertGreaterThanOrEqual(launcherTarget.frame.minY, spacebar.frame.minY)
        XCTAssertLessThanOrEqual(launcherTarget.frame.maxY, spacebar.frame.maxY)
        XCTAssertLessThan(launcherTarget.frame.size.width, spacebar.frame.size.width)
        XCTAssertLessThan(launcherTarget.frame.size.height, spacebar.frame.size.height)
        XCTAssertGreaterThanOrEqual(launcherTarget.frame.minX, projection.sourceRect.minX)
        XCTAssertLessThanOrEqual(launcherTarget.frame.maxX, projection.sourceRect.maxX)
        XCTAssertGreaterThanOrEqual(launcherTarget.frame.minY, projection.sourceRect.minY)
        XCTAssertLessThanOrEqual(launcherTarget.frame.maxY, projection.sourceRect.maxY)

        let coveredLegends = launcher.keys.filter { key in
            intersects(key.frame, launcherTarget.frame)
                && !key.legend.primary.allSatisfy(\.isWhitespace)
        }
        XCTAssertTrue(coveredLegends.isEmpty)
    }

    func testStableKeyIdentitySurvivesEveryMoment() {
        let scenes = allMoments.map { makeScene(moment: $0) }
        let expectedIDs = scenes[0].keys.map(\.id)

        for scene in scenes.dropFirst() {
            XCTAssertEqual(scene.keys.prefix(expectedIDs.count).map(\.id), expectedIDs)
        }
    }

    func testHeroOmitsFunctionRowAndUnmappedHardwareKeys() {
        let layout = PhysicalLayout(
            id: "keyboard-stage-function-row-test",
            name: "Keyboard Stage Function Row Test",
            keys: [
                PhysicalKey(keyCode: 53, label: "esc", x: 0, y: 0),
                PhysicalKey(keyCode: 122, label: "f1", x: 1.05, y: 0),
                PhysicalKey(keyCode: PhysicalKey.unmappedKeyCode, label: "touch id", x: 2.1, y: 0),
                PhysicalKey(keyCode: 18, label: "1", x: 0, y: 1.05),
                PhysicalKey(keyCode: 57, label: "caps", x: 0, y: 2.1, width: 1.5),
            ]
        )

        let scene = KeyboardStageSceneBuilder.make(
            layout: layout,
            keymap: .qwertyUS,
            moment: .capsMotivation,
            displayMode: .standard
        )

        XCTAssertFalse(scene.keys.contains { $0.keyCode == 53 })
        XCTAssertFalse(scene.keys.contains { $0.keyCode == 122 })
        XCTAssertFalse(scene.keys.contains { $0.keyCode == PhysicalKey.unmappedKeyCode })
        XCTAssertTrue(scene.keys.contains { $0.keyCode == 18 })
        XCTAssertTrue(scene.keys.contains { $0.keyCode == 57 })
    }

    func testReducedMotionApplyingScenesKeepMeaningWithoutSpatialMotion() throws {
        var reducedMotion = KeyboardStageDisplayMode.standard
        reducedMotion.reduceMotion = true

        for moment in [KeyboardStageMoment.capsApplying, .hyperApplying] {
            let scene = KeyboardStageSceneBuilder.make(
                layout: testLayout,
                keymap: .qwertyUS,
                moment: moment,
                displayMode: reducedMotion
            )

            XCTAssertTrue(scene.keys.allSatisfy { key in
                key.pressure == 0
                    && key.scale == 1
                    && key.translation == .zero
            })
            XCTAssertTrue(scene.decorations.allSatisfy { decoration in
                decoration.pressure == 0 && decoration.scale == 1
            })
            XCTAssertFalse(scene.decorations.contains { decoration in
                switch decoration.kind {
                case .capsEcho, .modifierToken:
                    true
                case .keyboardDeck,
                     .launcherCandidateMarker,
                     .applicationTarget,
                     .launcherChoiceTarget,
                     .handoffTarget:
                    false
                }
            })
        }

        let capsApplying = KeyboardStageSceneBuilder.make(
            layout: testLayout,
            keymap: .qwertyUS,
            moment: .capsApplying,
            displayMode: reducedMotion
        )
        let hyperApplying = KeyboardStageSceneBuilder.make(
            layout: testLayout,
            keymap: .qwertyUS,
            moment: .hyperApplying,
            displayMode: reducedMotion
        )

        XCTAssertEqual(try capsKey(in: capsApplying).role, .escape)
        XCTAssertEqual(try capsKey(in: capsApplying).legend.primary, "esc")
        XCTAssertGreaterThan(try capsKey(in: capsApplying).glow, 0)
        XCTAssertEqual(try capsKey(in: hyperApplying).role, .hyper)
        XCTAssertEqual(try capsKey(in: hyperApplying).legend.primary, "Hyper")
        XCTAssertGreaterThan(try capsKey(in: hyperApplying).glow, 0)
    }

    func testSceneAndEnvironmentReducedMotionPathsProduceTheSameScene() {
        var reducedMotion = KeyboardStageDisplayMode.standard
        reducedMotion.reduceMotion = true
        let standardScene = makeScene(moment: .capsApplying)
        let sceneConfiguredForReducedMotion = KeyboardStageSceneBuilder.make(
            layout: testLayout,
            keymap: .qwertyUS,
            moment: .capsApplying,
            displayMode: reducedMotion
        )

        XCTAssertEqual(
            sceneConfiguredForReducedMotion,
            standardScene.replacingDisplayMode(reducedMotion)
        )
    }

    func testLivePressAddsMaterialResponseToTheMatchingKeyOnly() throws {
        let scene = makeScene(moment: .capsInstalled)
        let responsiveScene = scene.applyingInteraction(
            KeyboardStageInteractionLevels(
                state: KeyboardStageInteractionState(
                    pressedKeyCodes: [57],
                    heldKeyCodes: [],
                    phase: .press,
                    revision: 1
                )
            )
        )
        let caps = try capsKey(in: responsiveScene)
        let otherKey = try XCTUnwrap(responsiveScene.keys.first { $0.keyCode != 57 })
        let originalOtherKey = try XCTUnwrap(scene.keys.first { $0.id == otherKey.id })

        XCTAssertGreaterThan(caps.pressure, try capsKey(in: scene).pressure)
        XCTAssertLessThan(caps.scale, 1)
        XCTAssertGreaterThanOrEqual(caps.glow, try capsKey(in: scene).glow)
        XCTAssertEqual(otherKey, originalOtherKey)
    }

    func testReducedMotionLivePressKeepsColorFeedbackWithoutMovement() throws {
        var reducedMotion = KeyboardStageDisplayMode.standard
        reducedMotion.reduceMotion = true
        let scene = KeyboardStageSceneBuilder.make(
            layout: testLayout,
            keymap: .qwertyUS,
            moment: .capsInstalled,
            displayMode: reducedMotion
        )
        let responsiveScene = scene.applyingInteraction(
            KeyboardStageInteractionLevels(
                state: KeyboardStageInteractionState(
                    pressedKeyCodes: [57],
                    heldKeyCodes: [],
                    phase: .press,
                    revision: 1
                )
            )
        )
        let caps = try capsKey(in: responsiveScene)

        XCTAssertEqual(caps.pressure, 0)
        XCTAssertEqual(caps.scale, 1)
        XCTAssertGreaterThan(caps.glow, try capsKey(in: scene).glow)
    }

    private var allMoments: [KeyboardStageMoment] {
        [
            .welcome,
            .capsMotivation,
            .capsApplying,
            .capsInstalled,
            .hyperMotivation,
            .hyperApplying,
            .hyperInstalled,
            .launcher,
            .handoff,
        ]
    }

    private func makeScene(moment: KeyboardStageMoment) -> KeyboardStageScene {
        KeyboardStageSceneBuilder.make(
            layout: testLayout,
            keymap: .qwertyUS,
            moment: moment,
            displayMode: .standard
        )
    }

    private func capsKey(in scene: KeyboardStageScene) throws -> KeyboardStageKey {
        try XCTUnwrap(scene.keys.first { $0.keyCode == 57 })
    }

    private func modifierTokens(in scene: KeyboardStageScene) -> [KeyboardStageDecoration] {
        scene.decorations.filter { decoration in
            if case .modifierToken = decoration.kind { return true }
            return false
        }
    }

    private func intersects(_ lhs: KeyboardStageRect, _ rhs: KeyboardStageRect) -> Bool {
        lhs.minX < rhs.maxX
            && lhs.maxX > rhs.minX
            && lhs.minY < rhs.maxY
            && lhs.maxY > rhs.minY
    }

    private var testLayout: PhysicalLayout {
        PhysicalLayout(
            id: "keyboard-stage-test",
            name: "Keyboard Stage Test",
            keys: [
                PhysicalKey(keyCode: 18, label: "1", x: 0, y: 0),
                PhysicalKey(keyCode: 19, label: "2", x: 1.05, y: 0),
                PhysicalKey(keyCode: 12, label: "q", x: 0.3, y: 1.05),
                PhysicalKey(keyCode: 13, label: "w", x: 1.35, y: 1.05),
                PhysicalKey(keyCode: 0, label: "a", x: 0.55, y: 2.1),
                PhysicalKey(keyCode: 1, label: "s", x: 1.6, y: 2.1),
                PhysicalKey(keyCode: 57, label: "⇪", x: 0, y: 3.15, width: 1.5),
                PhysicalKey(keyCode: 56, label: "⇧", x: 0, y: 4.2, width: 1.3),
                PhysicalKey(keyCode: 59, label: "⌃", x: 1.35, y: 4.2),
                PhysicalKey(keyCode: 58, label: "⌥", x: 2.4, y: 4.2),
                PhysicalKey(keyCode: 55, label: "⌘", x: 3.45, y: 4.2),
            ]
        )
    }
}
