import SwiftUI

extension OverlayKeycapView {
    /// Check if a label represents a modifier or special key that should keep text labels
    func isModifierOrSpecialKey(_ label: String) -> Bool {
        let lower = label.lowercased()
        let modifierKeys: Set<String> = [
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
            "fn", "function",
        ]
        return modifierKeys.contains(lower)
    }

    /// Map action descriptions to SF Symbols
    func sfSymbolForAction(_ action: String) -> String? {
        let lower = action.lowercased()

        if lower.contains("left") && lower.contains("half") {
            return "rectangle.lefthalf.filled"
        }
        if lower.contains("right") && lower.contains("half") {
            return "rectangle.righthalf.filled"
        }
        if lower.contains("top") && lower.contains("half") {
            return "rectangle.tophalf.filled"
        }
        if lower.contains("bottom") && lower.contains("half") {
            return "rectangle.bottomhalf.filled"
        }

        if lower.contains("top") && lower.contains("left") && lower.contains("corner") {
            return "arrow.up.left"
        }
        if lower.contains("top") && lower.contains("right") && lower.contains("corner") {
            return "arrow.up.right"
        }
        if lower.contains("bottom") && lower.contains("left") && lower.contains("corner") {
            return "arrow.down.left"
        }
        if lower.contains("bottom") && lower.contains("right") && lower.contains("corner") {
            return "arrow.down.right"
        }

        if lower.contains("maximize") || lower.contains("fullscreen") || lower.contains("full screen") {
            return "arrow.up.left.and.arrow.down.right"
        }
        if lower.contains("restore") {
            return "arrow.down.right.and.arrow.up.left"
        }
        if lower.contains("center") && !lower.contains("align") {
            return "circle.grid.cross"
        }

        if lower.contains("next display") || lower.contains("display right") || lower.contains("move right display") {
            return "arrow.right.to.line"
        }
        if lower.contains("previous display") || lower.contains("display left") || lower.contains("move left display") {
            return "arrow.left.to.line"
        }

        if lower.contains("next space") || lower.contains("space right") {
            return "arrow.right.square"
        }
        if lower.contains("previous space") || lower.contains("space left") {
            return "arrow.left.square"
        }

        if lower.contains("left third") || lower.contains("left 1/3") {
            return "rectangle.leadinghalf.filled"
        }
        if lower.contains("center third") || lower.contains("middle third") {
            return "rectangle.center.inset.filled"
        }
        if lower.contains("right third") || lower.contains("right 1/3") {
            return "rectangle.trailinghalf.filled"
        }

        if lower.contains("left two thirds") || lower.contains("left 2/3") {
            return "rectangle.leadingthird.inset.filled"
        }
        if lower.contains("right two thirds") || lower.contains("right 2/3") {
            return "rectangle.trailingthird.inset.filled"
        }

        if lower == "up" || lower == "move up" {
            return "arrow.up"
        }
        if lower == "down" || lower == "move down" {
            return "arrow.down"
        }
        if lower == "left" || lower == "move left" {
            return "arrow.left"
        }
        if lower == "right" || lower == "move right" {
            return "arrow.right"
        }

        if lower.contains("yank") || lower.contains("copy") {
            return "doc.on.doc"
        }
        if lower.contains("paste") {
            return "doc.on.clipboard"
        }
        if lower.contains("delete") || lower.contains("remove") {
            return "trash"
        }
        if lower.contains("undo") {
            return "arrow.uturn.backward"
        }
        if lower.contains("redo") {
            return "arrow.uturn.forward"
        }
        if lower.contains("save") {
            return "square.and.arrow.down"
        }

        if lower.contains("search") || lower.contains("find") {
            return "magnifyingglass"
        }

        return nil
    }

    /// Characters that benefit from monospaced font to avoid ambiguity
    static var monoDisambiguationChars: Set<String> { ["o", "0", "O"] }

    /// Render text label with dynamic sizing and multi-line wrapping
    func dynamicTextLabel(_ text: String) -> some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - 4 * scale
            let availableHeight = geometry.size.height - 4 * scale
            let preferredSize: CGFloat = 10 * scale
            let mediumSize: CGFloat = 8 * scale
            let smallSize: CGFloat = 6 * scale
            let estimatedWidth = CGFloat(text.count) * preferredSize * 0.6
            let fontSize = estimatedWidth <= availableWidth ? preferredSize : (estimatedWidth <= availableWidth * 1.5 ? mediumSize : smallSize)
            let useMono = Self.monoDisambiguationChars.contains(text)

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
