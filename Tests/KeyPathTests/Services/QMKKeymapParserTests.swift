import Foundation
@testable import KeyPathAppKit
import Testing

/// Tests for QMK keymap.c / keymap.json parsing and keycode resolution
struct QMKKeymapParserTests {
    // MARK: - keymap.json Parsing

    @Test func parseKeymapJSON() {
        let json = """
        {
          "keyboard": "planck/rev7",
          "keymap": "default",
          "layout": "LAYOUT_planck_grid",
          "layers": [
            ["KC_TAB", "KC_Q", "KC_W", "KC_E", "KC_R", "KC_T"],
            ["KC_ESC", "KC_A", "KC_S", "KC_D", "KC_F", "KC_G"]
          ]
        }
        """
        let result = QMKKeymapParser.parseBaseLayer(from: json)
        #expect(result != nil)
        #expect(result?.count == 6)
        #expect(result?[0] == "KC_TAB")
        #expect(result?[1] == "KC_Q")
        #expect(result?[5] == "KC_T")
    }

    // MARK: - keymap.c Parsing

    @Test func parseKeymapCBasic() {
        let source = """
        #include QMK_KEYBOARD_H

        const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {
            [0] = LAYOUT(
                KC_ESC,  KC_1,    KC_2,    KC_3,
                KC_TAB,  KC_Q,    KC_W,    KC_E
            ),
            [1] = LAYOUT(
                KC_GRV,  KC_F1,   KC_F2,   KC_F3,
                _______, _______, _______, _______
            )
        };
        """
        let result = QMKKeymapParser.parseBaseLayer(from: source)
        #expect(result != nil)
        #expect(result?.count == 8)
        #expect(result?[0] == "KC_ESC")
        #expect(result?[1] == "KC_1")
        #expect(result?[4] == "KC_TAB")
        #expect(result?[7] == "KC_E")
    }

    @Test func parseKeymapCWithCompoundKeycodes() {
        let source = """
        const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {
            [_QWERTY] = LAYOUT_split_3x6_3(
                KC_TAB,  KC_Q,    KC_W,    LT(1, KC_SPC),  MT(MOD_LCTL, KC_A),  MO(2)
            )
        };
        """
        let result = QMKKeymapParser.parseBaseLayer(from: source)
        #expect(result != nil)
        #expect(result?.count == 6)
        #expect(result?[0] == "KC_TAB")
        #expect(result?[3] == "LT(1, KC_SPC)")
        #expect(result?[4] == "MT(MOD_LCTL, KC_A)")
        #expect(result?[5] == "MO(2)")
    }

    @Test func parseKeymapCWithComments() {
        let source = """
        const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {
            [0] = LAYOUT(
                KC_ESC,  KC_1,    // number row
                KC_TAB,  KC_Q     /* alpha row */
            )
        };
        """
        let result = QMKKeymapParser.parseBaseLayer(from: source)
        #expect(result != nil)
        #expect(result?.count == 4)
        #expect(result?[0] == "KC_ESC")
        #expect(result?[3] == "KC_Q")
    }

    @Test func parseKeymapCWithLayoutSuffix() {
        let source = """
        const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {
            [_BASE] = LAYOUT_65_ansi(
                KC_GRV, KC_1, KC_2, KC_3
            )
        };
        """
        let result = QMKKeymapParser.parseBaseLayer(from: source)
        #expect(result != nil)
        #expect(result?[0] == "KC_GRV")
    }

    @Test func parseInvalidSourceReturnsNil() {
        let result = QMKKeymapParser.parseBaseLayer(from: "not a keymap file at all")
        #expect(result == nil)
    }

    // MARK: - Compound Keycode Extraction

    @Test func extractBaseKeySimple() {
        #expect(QMKKeymapParser.extractBaseKey("KC_A") == "KC_A")
        #expect(QMKKeymapParser.extractBaseKey("KC_SPACE") == "KC_SPACE")
        #expect(QMKKeymapParser.extractBaseKey("KC_F12") == "KC_F12")
    }

    @Test func extractBaseKeyLayerTap() {
        #expect(QMKKeymapParser.extractBaseKey("LT(1, KC_SPC)") == "KC_SPC")
        #expect(QMKKeymapParser.extractBaseKey("LT(2, KC_ENTER)") == "KC_ENTER")
    }

    @Test func extractBaseKeyModTap() {
        #expect(QMKKeymapParser.extractBaseKey("MT(MOD_LCTL, KC_A)") == "KC_A")
    }

    @Test func extractBaseKeyModWrapper() {
        #expect(QMKKeymapParser.extractBaseKey("LCTL(KC_C)") == "KC_C")
        #expect(QMKKeymapParser.extractBaseKey("LGUI(KC_V)") == "KC_V")
    }

    @Test func extractBaseKeyLayerSwitch() {
        #expect(QMKKeymapParser.extractBaseKey("MO(1)") == nil)
        #expect(QMKKeymapParser.extractBaseKey("TG(2)") == nil)
        #expect(QMKKeymapParser.extractBaseKey("TO(0)") == nil)
    }

    @Test func extractBaseKeyTransparent() {
        #expect(QMKKeymapParser.extractBaseKey("_______") == nil)
        #expect(QMKKeymapParser.extractBaseKey("KC_TRNS") == nil)
        #expect(QMKKeymapParser.extractBaseKey("KC_NO") == nil)
        #expect(QMKKeymapParser.extractBaseKey("XXXXXXX") == nil)
    }

    @Test func extractBaseKeySystem() {
        #expect(QMKKeymapParser.extractBaseKey("QK_BOOT") == nil)
        #expect(QMKKeymapParser.extractBaseKey("RGB_TOG") == nil)
    }

    // MARK: - Full Resolution Pipeline

    @Test func resolveSimpleKeycodes() {
        let tab = QMKKeymapParser.resolveKeycode("KC_TAB")
        #expect(tab?.keyCode == 0x30) // kVK_Tab
        #expect(tab?.label == "⇥")

        let a = QMKKeymapParser.resolveKeycode("KC_A")
        #expect(a?.keyCode == 0x00) // kVK_ANSI_A
        #expect(a?.label == "a")

        let space = QMKKeymapParser.resolveKeycode("KC_SPC")
        #expect(space?.keyCode == 0x31) // kVK_Space
        #expect(space?.label == "␣")
    }

    @Test func resolveCompoundKeycodes() {
        let lt = QMKKeymapParser.resolveKeycode("LT(1, KC_SPC)")
        #expect(lt?.keyCode == 0x31) // kVK_Space (base key)
        #expect(lt?.label == "␣")

        let mt = QMKKeymapParser.resolveKeycode("MT(MOD_LCTL, KC_A)")
        #expect(mt?.keyCode == 0x00) // kVK_ANSI_A (base key)
    }

    @Test func resolveLayerKeysReturnsNil() {
        #expect(QMKKeymapParser.resolveKeycode("MO(1)") == nil)
        #expect(QMKKeymapParser.resolveKeycode("_______") == nil)
        #expect(QMKKeymapParser.resolveKeycode("KC_NO") == nil)
    }

    @Test func resolveNavClusterLabels() {
        // These labels must match hasSpecialLabel in OverlayKeycapView
        let home = QMKKeymapParser.resolveKeycode("KC_HOME")
        #expect(home?.label == "home")

        let pgup = QMKKeymapParser.resolveKeycode("KC_PGUP")
        #expect(pgup?.label == "pgup")

        let pgdn = QMKKeymapParser.resolveKeycode("KC_PGDN")
        #expect(pgdn?.label == "pgdn")

        let del = QMKKeymapParser.resolveKeycode("KC_DEL")
        #expect(del?.label == "⌦")

        let end = QMKKeymapParser.resolveKeycode("KC_END")
        #expect(end?.label == "end")

        let ins = QMKKeymapParser.resolveKeycode("KC_INS")
        #expect(ins?.label == "ins")
    }

    @Test func resolveMediaKeyLabels() {
        let mute = QMKKeymapParser.resolveKeycode("KC_MUTE")
        #expect(mute?.label == "mute")

        let vold = QMKKeymapParser.resolveKeycode("KC_VOLD")
        #expect(vold?.label == "v-")

        let volu = QMKKeymapParser.resolveKeycode("KC_VOLU")
        #expect(volu?.label == "v+")
    }

    @Test func resolveJISAndISOLabels() {
        let nubs = QMKKeymapParser.resolveKeycode("KC_NUBS")
        #expect(nubs?.label == "§")

        let int3 = QMKKeymapParser.resolveKeycode("KC_INT3")
        #expect(int3?.label == "¥")

        let int1 = QMKKeymapParser.resolveKeycode("KC_INT1")
        #expect(int1?.label == "_")

        let lng1 = QMKKeymapParser.resolveKeycode("KC_LNG1")
        #expect(lng1?.label == "かな")

        let lng2 = QMKKeymapParser.resolveKeycode("KC_LNG2")
        #expect(lng2?.label == "英数")
    }

    @Test func resolveHelpKeyLabel() {
        let help = QMKKeymapParser.resolveKeycode("KC_HELP")
        #expect(help?.label == "help")
    }

    // MARK: - Abbreviate Token Tests

    @Test func abbreviateTokenMultiDigitLayers() {
        #expect(QMKLayoutParser.abbreviateToken("MO(1)") == "L1")
        #expect(QMKLayoutParser.abbreviateToken("MO(12)") == "L12")
        #expect(QMKLayoutParser.abbreviateToken("TG(3)") == "T3")
        #expect(QMKLayoutParser.abbreviateToken("TG(10)") == "T10")
        #expect(QMKLayoutParser.abbreviateToken("LT(2, KC_SPC)") == "L2")
        #expect(QMKLayoutParser.abbreviateToken("LT(15, KC_SPC)") == "L15")
        #expect(QMKLayoutParser.abbreviateToken("OSL(4)") == "L4")
        #expect(QMKLayoutParser.abbreviateToken("OSL(11)") == "L11")
    }

    @Test func abbreviateTokenSpecialKeys() {
        #expect(QMKLayoutParser.abbreviateToken("QK_BOOT") == "⟲")
        #expect(QMKLayoutParser.abbreviateToken("RGB_TOG") == "RGB")
        #expect(QMKLayoutParser.abbreviateToken("BL_TOGG") == "BL")
    }

    // MARK: - Keycode Mapping Table

    @Test func keycodeTableHasAllLetters() {
        for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            let key = "KC_\(letter)"
            #expect(QMKKeycodeMapping.qmkToMacOS[key] != nil, "Missing mapping for \(key)")
        }
    }

    @Test func keycodeTableHasAllNumbers() {
        for num in 0 ... 9 {
            let key = "KC_\(num)"
            #expect(QMKKeycodeMapping.qmkToMacOS[key] != nil, "Missing mapping for \(key)")
        }
    }

    @Test func keycodeTableHasModifiers() {
        #expect(QMKKeycodeMapping.qmkToMacOS["KC_LSFT"] != nil)
        #expect(QMKKeycodeMapping.qmkToMacOS["KC_RSFT"] != nil)
        #expect(QMKKeycodeMapping.qmkToMacOS["KC_LCTL"] != nil)
        #expect(QMKKeycodeMapping.qmkToMacOS["KC_LGUI"] != nil)
        #expect(QMKKeycodeMapping.qmkToMacOS["KC_LCMD"] != nil) // alias
        #expect(QMKKeycodeMapping.qmkToMacOS["KC_LALT"] != nil)
        #expect(QMKKeycodeMapping.qmkToMacOS["KC_LOPT"] != nil) // alias
    }

    @Test func keycodeTableHasFunctionKeys() {
        for i in 1 ... 12 {
            let key = "KC_F\(i)"
            #expect(QMKKeycodeMapping.qmkToMacOS[key] != nil, "Missing mapping for \(key)")
        }
    }

    @Test func keycodeTableSpotCheck() {
        // Verify a few critical mappings against known macOS kVK_ values
        #expect(QMKKeycodeMapping.qmkToMacOS["KC_A"] == 0x00) // kVK_ANSI_A
        #expect(QMKKeycodeMapping.qmkToMacOS["KC_S"] == 0x01) // kVK_ANSI_S
        #expect(QMKKeycodeMapping.qmkToMacOS["KC_ENTER"] == 0x24) // kVK_Return
        #expect(QMKKeycodeMapping.qmkToMacOS["KC_ESC"] == 0x35) // kVK_Escape
        #expect(QMKKeycodeMapping.qmkToMacOS["KC_SPC"] == 0x31) // kVK_Space
        #expect(QMKKeycodeMapping.qmkToMacOS["KC_F1"] == 0x7A) // kVK_F1
        #expect(QMKKeycodeMapping.qmkToMacOS["KC_LGUI"] == 0x37) // kVK_Command
        #expect(QMKKeycodeMapping.qmkToMacOS["KC_RIGHT"] == 0x7C) // kVK_RightArrow
    }

    // MARK: - parseWithKeymap Integration

    @Test func parseWithKeymapAssignsByIndex() {
        // Simple 2-key layout with keymap
        let json = """
        {
          "id": "test",
          "name": "Test",
          "layouts": {
            "default_transform": {
              "layout": [
                {"matrix": [0,0], "x": 0, "y": 0},
                {"matrix": [0,1], "x": 1, "y": 0}
              ]
            }
          }
        }
        """.data(using: .utf8)!

        let keymapTokens = ["KC_A", "KC_B"]
        let result = QMKLayoutParser.parseWithKeymap(
            data: json,
            keymapTokens: keymapTokens
        )

        #expect(result != nil)
        #expect(result?.layout.keys.count == 2)
        #expect(result?.layout.keys[0].keyCode == 0x00) // A
        #expect(result?.layout.keys[0].label == "a")
        #expect(result?.layout.keys[1].keyCode == 0x0B) // B
        #expect(result?.layout.keys[1].label == "b")
        #expect(result?.matchRatio == 1.0)
    }

    @Test func parseWithKeymapHandlesLayerKeys() {
        let json = """
        {
          "id": "test",
          "name": "Test",
          "layouts": {
            "default_transform": {
              "layout": [
                {"matrix": [0,0], "x": 0, "y": 0},
                {"matrix": [0,1], "x": 1, "y": 0},
                {"matrix": [0,2], "x": 2, "y": 0}
              ]
            }
          }
        }
        """.data(using: .utf8)!

        let keymapTokens = ["KC_A", "MO(1)", "LT(2, KC_SPC)"]
        let result = QMKLayoutParser.parseWithKeymap(
            data: json,
            keymapTokens: keymapTokens
        )

        #expect(result != nil)
        #expect(result?.layout.keys.count == 3)

        // KC_A → resolved
        #expect(result?.layout.keys[0].keyCode == 0x00)

        // MO(1) → layer key, should still count as matched
        #expect(result?.layout.keys[1].keyCode == PhysicalKey.unmappedKeyCode)

        // LT(2, KC_SPC) → base key is Space
        #expect(result?.layout.keys[2].keyCode == 0x31) // kVK_Space

        // All 3 should be matched (no "?" labels)
        #expect(result?.matchRatio == 1.0)
    }

    @Test func parseWithKeymapFallsBackForShortKeymap() {
        let json = """
        {
          "id": "test",
          "name": "Test",
          "layouts": {
            "default_transform": {
              "layout": [
                {"matrix": [0,0], "x": 0, "y": 0},
                {"matrix": [0,1], "x": 1, "y": 0},
                {"matrix": [0,2], "x": 2, "y": 0}
              ]
            }
          }
        }
        """.data(using: .utf8)!

        // Keymap has fewer entries than layout
        let keymapTokens = ["KC_A"]
        let result = QMKLayoutParser.parseWithKeymap(
            data: json,
            keymapTokens: keymapTokens
        )

        #expect(result != nil)
        #expect(result?.layout.keys[0].keyCode == 0x00) // A from keymap
        #expect(result?.layout.keys[1].label == "?") // No keymap entry
        #expect(result?.layout.keys[2].label == "?") // No keymap entry
        #expect(result?.unmatchedKeys == 2)
    }
}
