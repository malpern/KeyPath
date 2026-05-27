import SwiftUI

extension OverlayKeycapView {
    func isModifierOrSpecialKey(_ label: String) -> Bool {
        KeycapSymbols.isModifierOrSpecialKey(label)
    }

    func sfSymbolForAction(_ action: String) -> String? {
        KeycapSymbols.sfSymbolForAction(action)
    }

    func dynamicTextLabel(_ text: String) -> some View {
        KeycapSymbols.dynamicTextLabel(text, scale: scale)
    }
}
