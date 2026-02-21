@testable import KeyPathAppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// Snapshot tests for views with clean dependency injection.
/// These views accept simple value types, bindings, and closures — no singletons needed.
final class EasyViewSnapshotTests: ScreenshotTestCase {
    // MARK: - KeymapCard

    func testKeymapCardSelected() throws {
        let keymap = try XCTUnwrap(LogicalKeymap.all.first { $0.id == "qwerty-us" })
        let view = KeymapCard(
            keymap: keymap,
            isSelected: true,
            isDark: false,
            fadeAmount: 0,
            onSelect: {}
        )
        assertScreenshot(of: view, size: SnapshotSize.card, named: "keymap-card-selected")
    }

    func testKeymapCardUnselected() {
        let keymap = LogicalKeymap.all.first { $0.id == "colemak" }
            ?? LogicalKeymap.all[1]
        let view = KeymapCard(
            keymap: keymap,
            isSelected: false,
            isDark: false,
            fadeAmount: 0,
            onSelect: {}
        )
        assertScreenshot(of: view, size: SnapshotSize.card, named: "keymap-card-unselected")
    }

    // MARK: - AppRuleCard

    func testAppRuleCardSafari() {
        let keymap = MockFactories.safariKeymap
        let view = AppRuleCard(
            keymap: keymap,
            onEdit: { _ in },
            onDelete: { _ in },
            onAddRule: {}
        )
        assertScreenshot(of: view, size: SnapshotSize.card, named: "app-rule-card-safari")
    }

    // MARK: - CustomRulesInlineEditor

    func testCustomRulesEditorCapsToEscape() {
        let view = CustomRulesInlineEditor(
            inputKey: .constant("caps_lock"),
            outputKey: .constant("escape"),
            title: .constant(""),
            notes: .constant(""),
            inlineError: .constant(nil),
            keyOptions: ["caps_lock", "escape", "left_shift", "left_control", "left_command"],
            onAddRule: {}
        )
        assertScreenshot(
            of: view,
            size: SnapshotSize.panel,
            named: "concepts-new-rule-dialog"
        )
    }

    func testCustomRulesEditorWithHold() {
        let view = CustomRulesInlineEditor(
            inputKey: .constant("caps_lock"),
            outputKey: .constant("escape"),
            title: .constant("Caps Lock to Escape/Control"),
            notes: .constant(""),
            inlineError: .constant(nil),
            keyOptions: ["caps_lock", "escape", "left_shift", "left_control", "left_command"],
            onAddRule: {}
        )
        assertScreenshot(
            of: view,
            size: SnapshotSize.panel,
            named: "tap-hold-rule-editor"
        )
    }

    // MARK: - HomeRowTimingSection

    func testHomeRowTimingSlider() {
        let config = MockFactories.homeRowModsConfig()
        let view = HomeRowTimingSection(
            config: .constant(config),
            onConfigChanged: { _ in }
        )
        assertScreenshot(
            of: view,
            size: SnapshotSize.panel,
            named: "hrm-typing-feel-slider"
        )
    }

    func testHomeRowTimingPerFinger() {
        let config = MockFactories.homeRowModsConfig(showAdvanced: true, showPerFinger: true)
        let view = HomeRowTimingSection(
            config: .constant(config),
            onConfigChanged: { _ in }
        )
        assertScreenshot(
            of: view,
            size: CGSize(width: 600, height: 750),
            named: "hrm-per-finger-sliders"
        )
    }

    // MARK: - LauncherDrawerView

    func testLauncherDrawer() {
        let config = MockFactories.launcherGridConfig()
        let view = LauncherDrawerView(
            config: .constant(config),
            selectedKey: .constant(nil),
            onAddMapping: {},
            onEditMapping: { _ in },
            onDeleteMapping: { _ in }
        )
        // App icon loading from NSWorkspace produces pixel-level variation between runs
        assertScreenshot(
            of: view,
            size: SnapshotSize.drawer,
            named: "action-uri-launcher-drawer",
            precision: 0.98,
            perceptualPrecision: 0.98
        )
    }
}
