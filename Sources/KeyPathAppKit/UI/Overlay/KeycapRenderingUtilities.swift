import KeyPathCore
import SwiftUI

enum KeycapSymbols {
    static func sfSymbolForAction(_ action: String) -> String? {
        let lower = action.lowercased()

        if lower.contains("left") && lower.contains("half") { return "rectangle.lefthalf.filled" }
        if lower.contains("right") && lower.contains("half") { return "rectangle.righthalf.filled" }
        if lower.contains("top") && lower.contains("half") { return "rectangle.tophalf.filled" }
        if lower.contains("bottom") && lower.contains("half") { return "rectangle.bottomhalf.filled" }

        if lower.contains("top") && lower.contains("left") && lower.contains("corner") { return "arrow.up.left" }
        if lower.contains("top") && lower.contains("right") && lower.contains("corner") { return "arrow.up.right" }
        if lower.contains("bottom") && lower.contains("left") && lower.contains("corner") { return "arrow.down.left" }
        if lower.contains("bottom") && lower.contains("right") && lower.contains("corner") { return "arrow.down.right" }

        if lower.contains("maximize") || lower.contains("fullscreen") || lower.contains("full screen") {
            return "arrow.up.left.and.arrow.down.right"
        }
        if lower.contains("restore") { return "arrow.down.right.and.arrow.up.left" }
        if lower.contains("center") && !lower.contains("align") { return "circle.grid.cross" }

        if lower.contains("next display") || lower.contains("display right") || lower.contains("move right display") {
            return "arrow.right.to.line"
        }
        if lower.contains("previous display") || lower.contains("display left") || lower.contains("move left display") {
            return "arrow.left.to.line"
        }

        if lower.contains("next space") || lower.contains("space right") { return "arrow.right.square" }
        if lower.contains("previous space") || lower.contains("space left") { return "arrow.left.square" }

        if lower.contains("left third") || lower.contains("left 1/3") { return "rectangle.leadinghalf.filled" }
        if lower.contains("center third") || lower.contains("middle third") { return "rectangle.center.inset.filled" }
        if lower.contains("right third") || lower.contains("right 1/3") { return "rectangle.trailinghalf.filled" }

        if lower.contains("left two thirds") || lower.contains("left 2/3") { return "rectangle.leadingthird.inset.filled" }
        if lower.contains("right two thirds") || lower.contains("right 2/3") { return "rectangle.trailingthird.inset.filled" }

        if lower == "up" || lower == "move up" { return "arrow.up" }
        if lower == "down" || lower == "move down" { return "arrow.down" }
        if lower == "left" || lower == "move left" { return "arrow.left" }
        if lower == "right" || lower == "move right" { return "arrow.right" }

        if lower.contains("yank") || lower.contains("copy") { return "doc.on.doc" }
        if lower.contains("paste") { return "doc.on.clipboard" }
        if lower.contains("delete") || lower.contains("remove") { return "trash" }
        if lower.contains("undo") { return "arrow.uturn.backward" }
        if lower.contains("redo") { return "arrow.uturn.forward" }
        if lower.contains("save") { return "square.and.arrow.down" }
        if lower.contains("search") || lower.contains("find") { return "magnifyingglass" }

        return nil
    }

    static func isModifierOrSpecialKey(_ label: String) -> Bool {
        let lower = label.lowercased()
        let modifierKeys: Set = [
            "shift", "lshift", "rshift", "leftshift", "rightshift",
            "control", "ctrl", "lctrl", "rctrl", "leftcontrol", "rightcontrol",
            "option", "opt", "alt", "lalt", "ralt", "leftoption", "rightoption",
            "command", "cmd", "meta", "lmet", "rmet", "leftcommand", "rightcommand",
            "hyper", "meh",
            "capslock", "caps",
            "return", "enter", "ret",
            "escape", "esc",
            "tab",
            "space", "spc",
            "backspace", "bspc",
            "delete", "del",
            "fn", "function"
        ]
        return modifierKeys.contains(lower)
    }

    static func windowActionSymbol(from label: String, layerName: String) -> String? {
        guard layerName.lowercased().contains("window") else { return nil }

        let lower = label.lowercased()

        if lower.contains("left") && lower.contains("half") { return "arrow.left" }
        if lower.contains("right") && lower.contains("half") { return "arrow.right" }
        if lower.contains("top") && lower.contains("left") { return "arrow.up.left" }
        if lower.contains("top") && lower.contains("right") { return "arrow.up.right" }
        if lower.contains("bottom") && lower.contains("left") { return "arrow.down.left" }
        if lower.contains("bottom") && lower.contains("right") { return "arrow.down.right" }
        if lower.contains("maximize") || lower.contains("fullscreen") {
            return "arrow.up.left.and.arrow.down.right"
        }
        if lower.contains("center") { return "circle.grid.cross" }
        if lower.contains("display") || lower.contains("monitor") { return "display" }
        if lower.contains("next"), lower.contains("space") { return "arrow.right.square" }
        if lower.contains("previous"), lower.contains("space") { return "arrow.left.square" }

        return nil
    }

    static func windowActionColor(from label: String, layerName: String) -> Color? {
        guard layerName.lowercased().contains("window") else { return nil }

        let lower = label.lowercased()

        // Window-action labels reuse the shared palette so window keys match the
        // window/spaces family color used elsewhere (purple), with blue/green/teal
        // accents for halves/maximize/spaces.
        if lower.contains("top") && lower.contains("left") { return KeyPathColors.layerPurple }
        if lower.contains("top") && lower.contains("right") { return KeyPathColors.layerPurple }
        if lower.contains("bottom") && lower.contains("left") { return KeyPathColors.layerPurple }
        if lower.contains("bottom") && lower.contains("right") { return KeyPathColors.layerPurple }
        if lower.contains("left") && lower.contains("half") { return KeyPathColors.layerBlue }
        if lower.contains("right") && lower.contains("half") { return KeyPathColors.layerBlue }
        if lower.contains("maximize") || lower.contains("fullscreen") { return KeyPathColors.layerGreen }
        if lower.contains("center") { return KeyPathColors.layerGreen }
        if lower.contains("display") || lower.contains("monitor") { return KeyPathColors.layerOrange }
        if lower.contains("space") { return KeyPathColors.layerTeal }
        if lower.contains("undo") { return Color.gray }

        return nil
    }

    /// Semantic color families for collection-owned keys shown on a layer.
    ///
    /// Every collection maps to an intentional color grouped by *what the layer does*,
    /// rather than each color carrying an unrelated meaning. Collections without a
    /// vibrant category fall to the calm `keycapMapped` blue-gray — NOT orange — so
    /// simple remaps (function keys, caps/escape/delete remaps, leader, custom) don't
    /// shout. Modifier-producing keys use a quieter blue-gray.
    private enum LayerColors {
        static let navigation = KeyPathColors.layerGreen
        static let window = KeyPathColors.layerPurple
        static let symbols = KeyPathColors.layerBlue
        static let launcher = KeyPathColors.layerTeal
        /// Editor / terminal integration — shares the blue family with symbols
        /// (they don't appear together, so the shared hue is intentional).
        static let editor = KeyPathColors.layerBlue
        static let modifier = KeyPathColors.layerModifier
        /// Calm default for everything without a vibrant category (simple remaps).
        static let mapped = KeyPathColors.keycapMapped
    }

    static func collectionColor(for collectionId: UUID?) -> Color {
        guard let id = collectionId else {
            return LayerColors.mapped
        }

        switch id {
        case RuleCollectionIdentifier.vimNavigation,
             RuleCollectionIdentifier.kindaVim,
             RuleCollectionIdentifier.homeRowArrows,
             RuleCollectionIdentifier.vallackNavigation:
            return LayerColors.navigation
        case RuleCollectionIdentifier.windowSnapping,
             RuleCollectionIdentifier.missionControl:
            return LayerColors.window
        case RuleCollectionIdentifier.symbolLayer,
             RuleCollectionIdentifier.numpadLayer,
             RuleCollectionIdentifier.autoShiftSymbols:
            return LayerColors.symbols
        case RuleCollectionIdentifier.launcher,
             RuleCollectionIdentifier.funLayer:
            return LayerColors.launcher
        case RuleCollectionIdentifier.neovimTerminal:
            return LayerColors.editor
        case RuleCollectionIdentifier.homeRowMods,
             RuleCollectionIdentifier.homeRowLayerToggles,
             RuleCollectionIdentifier.capsLockHyperKey:
            return LayerColors.modifier
        default:
            // Simple remaps (function keys, caps/escape/delete remaps, leader,
            // custom, chords, sequences, …) — calm blue-gray, not orange.
            return LayerColors.mapped
        }
    }

    static var monoDisambiguationChars: Set<String> {
        ["o", "0", "O"]
    }

    static func dynamicTextLabel(_ text: String, scale: CGFloat) -> some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - 4 * scale
            let availableHeight = geometry.size.height - 4 * scale
            let preferredSize: CGFloat = 10 * scale
            let mediumSize: CGFloat = 8 * scale
            let smallSize: CGFloat = 6 * scale
            let estimatedWidth = CGFloat(text.count) * preferredSize * 0.6
            let fontSize = estimatedWidth <= availableWidth ? preferredSize : (estimatedWidth <= availableWidth * 1.5 ? mediumSize : smallSize)
            let useMono = monoDisambiguationChars.contains(text)

            Text(text.capitalized)
                .font(.system(size: fontSize, weight: .medium, design: useMono ? .monospaced : .default))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: availableWidth, maxHeight: availableHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
