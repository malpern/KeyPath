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

        if lower.contains("top") && lower.contains("left") { return .purple }
        if lower.contains("top") && lower.contains("right") { return .purple }
        if lower.contains("bottom") && lower.contains("left") { return .purple }
        if lower.contains("bottom") && lower.contains("right") { return .purple }
        if lower.contains("left") && lower.contains("half") { return .blue }
        if lower.contains("right") && lower.contains("half") { return .blue }
        if lower.contains("maximize") || lower.contains("fullscreen") { return .green }
        if lower.contains("center") { return .green }
        if lower.contains("display") || lower.contains("monitor") { return .orange }
        if lower.contains("space") { return .cyan }
        if lower.contains("undo") { return .gray }

        return nil
    }

    private enum LayerColors {
        static let defaultLayer = KeyPathColors.layerOrange
        static let vim = KeyPathColors.layerOrange
        static let windowSnapping = Color.purple
        static let symbols = Color.blue
        static let launcher = Color.cyan
        static let neovimTerminal = KeyPathColors.layerBlue
        static let vallackNav = KeyPathColors.layerGreen
    }

    static func collectionColor(for collectionId: UUID?) -> Color {
        guard let id = collectionId else {
            return LayerColors.defaultLayer
        }

        switch id {
        case RuleCollectionIdentifier.vimNavigation:
            return LayerColors.vim
        case RuleCollectionIdentifier.windowSnapping:
            return LayerColors.windowSnapping
        case RuleCollectionIdentifier.symbolLayer:
            return LayerColors.symbols
        case RuleCollectionIdentifier.launcher:
            return LayerColors.launcher
        case RuleCollectionIdentifier.neovimTerminal:
            return LayerColors.neovimTerminal
        case RuleCollectionIdentifier.vallackNavigation:
            return LayerColors.vallackNav
        default:
            return LayerColors.defaultLayer
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
